# Blue-Green Deployment — What Changed and Why

Written for someone new to this. Plain language, no assumed knowledge.

---

## 1. The problem we were solving

Before this change, updating the vote app worked like replacing tyres on a moving car.
Kubernetes swapped the running copies a few at a time:

```
copy1(old)  copy2(old)  copy3(old)
copy1(old)  copy2(old)  copy3(NEW)     ← some users get old, some get new
copy1(old)  copy2(NEW)  copy3(NEW)     ← still mixed
copy1(NEW)  copy2(NEW)  copy3(NEW)
```

That is called a **rolling update**. It is the Kubernetes default and it is usually fine.

Three things about it are uncomfortable:

- **Two versions run at once.** For a few minutes, some users are on the old code and some
  on the new one.
- **You cannot try the new version first.** The moment it starts, real users hit it.
- **Undoing is slow.** Going back means doing the whole slow swap again, in reverse.

---

## 2. What blue-green does instead

Run the **whole** new version alongside the old one, with nobody using it yet.

```
BLUE  (old)   copy1  copy2      ← every user is here
GREEN (new)   copy1  copy2      ← running, healthy, zero users

                  ↓  you check green, then press promote

BLUE  (old)   copy1  copy2      ← zero users, kept for a few minutes
GREEN (new)   copy1  copy2      ← every user is here now
```

The switch is **instant**, because nothing restarts. Kubernetes just changes which copies
count as "the ones users reach". Undoing is equally instant — switch back, blue is still
sitting there.

### The one sentence to remember

> **Rolling update trades time for capacity. Blue-green trades capacity for control.**

Rolling needs almost no spare room but gives you no chance to look first.
Blue-green needs double the room for a few minutes but lets you look before committing.

### How the switch actually works

This surprised me, and it is simpler than it sounds.

In Kubernetes, a **Service** is the thing that decides which copies receive traffic. It picks
them using labels — like "send traffic to anything tagged `app=vote`".

Blue-green adds one extra tag to that rule. Every copy gets a tag identifying **which
version** it belongs to. The Service says "send traffic to anything tagged `app=vote` **and**
`version=blue`".

Promoting changes that one word from `blue` to `green`.

That is it. No restarts, no waiting, no risk — which is why it is instant, and why rolling
back is just as instant.

---

## 3. What we installed

**Argo Rollouts.** It is a separate tool from Argo CD, and mixing them up is common:

| Tool | Job |
|---|---|
| **Argo CD** | Watches GitHub. Makes the cluster match what is in Git. |
| **Argo Rollouts** | Replaces Kubernetes' built-in "Deployment" with a smarter one that knows blue-green. |

Kubernetes cannot do blue-green on its own. It only knows rolling updates. Argo Rollouts
adds a new object type called a **Rollout** that behaves like a Deployment but supports
blue-green and canary.

---

## 4. What we changed, file by file

| File | Change |
|---|---|
| `base/vote_deployment.yaml` → `base/vote_rollout.yaml` | Changed `kind: Deployment` to `kind: Rollout` and added a `strategy` section. Everything else is identical. |
| `base/vote_preview_service.yaml` | **New.** A second door into the app, used to reach the new version before promoting. |
| `base/vote_hpa.yaml` | The autoscaler was pointed at a Deployment that no longer exists. Repointed at the Rollout. |
| `base/nameReference.yaml` | **New.** Explained in problem 3 below. |
| `base/kustomization.yaml` | Lists the new files. |
| `overlays/*/kustomization.yaml` | Vote's settings now use a different patch style. See problem 2. |
| `argocd/app-dev.yaml` | Told Argo CD to stop fighting Argo Rollouts. See problem 4. |

### The important bit of the new file

```yaml
strategy:
  blueGreen:
    activeService: vote-service          # the door real users come through
    previewService: vote-preview-service # the door you use to test
    autoPromotionEnabled: false          # STOP and wait for a human
    scaleDownDelaySeconds: 300           # keep the old version 5 more minutes
```

**`autoPromotionEnabled: false` is the whole point.** With `true`, the new version promotes
itself the moment it looks healthy — which gives you nothing that a rolling update did not
already give you. With `false`, it stops and waits for you.

**`scaleDownDelaySeconds: 300`** is your safety net. For five minutes after promoting, the
old version is still running and untouched, so undoing is instant. After that it is deleted
and going back means a fresh deploy.

---

## 5. The four problems we hit

This is the useful part. Each one is a real trap.

### Problem 1 — The autoscaler pointed at something that no longer existed

**What happened.** The autoscaler (the thing that adds copies when the app gets busy) was
configured to watch a "Deployment" named `vote-deployment`. We had just replaced that with a
"Rollout" of the same name. Different type, same name.

**Why.** In Kubernetes, things are identified by *type plus name*, not name alone. Renaming
the type broke the link even though the name matched.

**The fix.** One line — tell the autoscaler the new type.

**The lesson.** When you change what type something is, everything pointing at it needs
updating too. The name matching is not enough.

---

### Problem 2 — A change that looked perfect and would have deployed a broken app

This was the dangerous one, because **nothing reported an error**.

**Background.** We keep one set of base files and then apply small per-environment
adjustments on top — dev gets less memory than production, and so on. The tool that does
this merging is called kustomize.

**What happened.** Our dev adjustment said "for the container named `vote`, use 50m CPU".
Normally kustomize is clever: it finds the container called `vote` and changes only that one
setting, leaving the image, the settings, and the health checks alone.

It did not do that. It **threw away the entire container description** and replaced it with
just the two lines from our adjustment.

The result would have been a container with:

```
image:           (nothing)
configuration:   (nothing)
health checks:   (nothing)
security rules:  (nothing)
```

A container with no image cannot start. And kustomize reported **success**.

**Why.** Kustomize is only clever about types it was built to understand — Deployments,
Services, and so on. A Rollout is a *custom* type added by Argo Rollouts. Kustomize has never
heard of it, so it falls back to the dumbest possible behaviour: replace, do not merge.

**The fix.** Use a different, more precise style of adjustment for the Rollout. Instead of
"merge this shape in", it says literally: "change the value at this exact address".

```
change /spec/template/spec/containers/0/resources/requests/cpu to 50m
```

It cannot accidentally replace anything, because it never touches anything you did not name.

**The lesson, and it is the big one:**

> A tool saying "success" means it checked the things it knows how to check. It does not
> mean the result is correct.

We only caught this by *looking at the output* instead of trusting the exit code. Get in the
habit of that.

---

### Problem 3 — Pods stuck, complaining about a missing setting

**The error:**

```
CreateContainerConfigError
configmap "voteapp-redis-config" not found
```

**Background you need.** Our app settings live in objects called ConfigMaps. When kustomize
builds everything, it adds a random-looking suffix to their names:

```
voteapp-redis-config-mg788dc68k
```

That suffix is a fingerprint of the contents. Change a setting, the fingerprint changes, the
name changes — and because the name changed, Kubernetes notices the app description is
different and restarts the app to pick it up. It is a clever trick that solves a real
problem: **editing settings does not restart anything on its own**, so without this, changed
settings would sit unused until something else happened to restart the app.

Kustomize normally also updates every *reference* to those names so nothing breaks.

**What happened.** It updated the references everywhere except inside the Rollout. So the
Rollout was asking for `voteapp-redis-config` while the real object was called
`voteapp-redis-config-mg788dc68k`. Kubernetes looked for a name that did not exist and
refused to start the container.

**Why.** Same reason as problem 2. Kustomize does not know a Rollout's shape, so it does not
know where inside it to look for references.

**The fix.** A small file, `base/nameReference.yaml`, that tells kustomize exactly where a
Rollout keeps its references — "look at this path, and this one, and this one".

**The lesson.** Same as problem 2, wearing a different hat. Custom types need to be explained
to your tools. Expect *several* symptoms from that one cause, not one.

---

### Problem 4 — Two tools fighting over the same setting

**The setup.** Remember that promoting works by changing one label in the Service. That means
**Argo Rollouts edits the Service directly, live in the cluster.**

But we had also switched on a feature in Argo CD called `selfHeal`, which means: *if anything
in the cluster differs from what GitHub says, change it back.* It is a genuinely good feature
— it is what would have caught the incident where someone changed a password directly on the
cluster.

**The problem.** The label Argo Rollouts writes is not in GitHub. It cannot be — it changes
every time you deploy.

So: Argo Rollouts writes the label. Argo CD sees something that is not in GitHub, and deletes
it. Traffic goes to the wrong version, or nowhere at all. Then Argo Rollouts writes it again.
Round and round.

**The fix.** Tell Argo CD: "ignore that specific field, someone else owns it."

```yaml
ignoreDifferences:
  - kind: Service
    name: vote-service
    jsonPointers:
      - /spec/selector      # Argo Rollouts owns this, not Git
```

**The lesson.** When two automated systems can write the same field, you must decide which
one owns it — and tell the other to keep its hands off. This is not a bug in either tool.
It is a question only you can answer.

We already had two of these for the same reason:

| Field | Who really owns it |
|---|---|
| How many copies of vote | The autoscaler, not Git |
| Storage settings on the database | Kubernetes fills in defaults Git does not have |
| The Service label | Argo Rollouts |

---

## 6. Using it day to day

**Watch a deploy happen:**

```bash
brew install argoproj/tap/kubectl-argo-rollouts
kubectl argo rollouts get rollout vote-deployment -n voting-dev --watch
```

**Test the new version before anyone else sees it:**

```bash
kubectl port-forward -n voting-dev svc/vote-preview-service 9000:8000
curl localhost:9000
```

**Switch everyone over:**

```bash
kubectl argo rollouts promote vote-deployment -n voting-dev
```

**Change your mind (works for 5 minutes after promoting):**

```bash
kubectl argo rollouts undo vote-deployment -n voting-dev
```

---

## 7. Why only the vote app

Blue-green is not automatically right for everything.

| Service | Blue-green? | Why |
|---|---|---|
| **vote** | Yes | Ordinary web app. Each request is independent, so switching everyone at once is harmless. |
| **result** | Not really | It holds a live connection open to each browser. Those connections do not move when you flip the switch — people stay on the old version until they refresh. Blue-green does not deliver what it promises here. |
| **worker** | No | Nobody connects to it. It reads jobs from a queue on its own. There is no traffic to switch, so there is nothing for blue-green to do. |

Being able to say *"I used blue-green for the web app and left the background worker on a
rolling update, because there is no traffic to switch"* shows you understand the tool rather
than having applied it everywhere.

---

## 8. What blue-green does not fix

Worth knowing so you do not oversell it.

- **Database changes.** If the new version needs a different database shape, blue and green
  are both talking to the same database. Blue-green does not help; that needs careful
  planning where changes work with both versions.
- **Cost.** You are paying for double the copies during every deploy.
- **It is still all-or-nothing.** Everyone moves at the same moment. If the new version has a
  problem that only shows under real traffic, everyone gets it at once. The tool for that is
  **canary** — send 5% of users first, watch, then continue. Argo Rollouts does that too, and
  it is a small change from what we built.

---

## Summary

**What we built:** the vote app now deploys by starting a complete new copy alongside the old
one, letting you check it, and switching everyone over in one instant step that can be undone
just as fast.

**The main thing to take away:** every problem in section 5 came from one root cause —
**tools only understand the things they were built to understand.** Kustomize did not know
what a Rollout was, so it broke three different things in three different ways. Argo CD did
not know Argo Rollouts owned a field, so it fought over it.

And the one worth repeating: **a tool reporting success has only checked what it knows how to
check.** The most dangerous bug today produced a perfectly valid-looking file that would have
deployed an app with no image in it.
