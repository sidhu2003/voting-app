# SonarQube — Setup Guide

Scanning and quality gates for the three services. Written as instructions to follow, with
the reasoning included so the choices are yours rather than mine.

Unit tests already exist and produce coverage — see §2. That matters, because a Sonar setup
without coverage data grades you on style and misses the thing that actually predicts bugs.

---

## 1. What SonarQube is doing

Three separate jobs, often confused:

| | What it finds |
|---|---|
| **Static analysis** | bugs, code smells, security hotspots, duplication |
| **Coverage tracking** | which lines your tests actually execute |
| **Quality gate** | a pass/fail rule that can block a merge |

The gate is the point. Analysis nobody acts on is a dashboard; a gate is a decision.

---

## 2. Getting coverage out of the existing tests

Sonar cannot compute coverage itself — you hand it a report. Each language needs one extra
flag or package.

### vote (Python)

```bash
# vote/requirements-dev.txt
pytest==8.3.4
pytest-cov==6.0.0
```

```bash
cd vote
python -m pytest --cov=. --cov-report=xml:coverage.xml --cov-branch
```

Produces `vote/coverage.xml`. `--cov-branch` also measures whether both sides of each `if`
were taken, which is stricter and more useful than line coverage alone.

### result (Node)

Node 22 has coverage built in, so no new dependency:

```bash
cd result
node --test --experimental-test-coverage \
     --test-reporter=lcov --test-reporter-destination=lcov.info \
     tests/*.test.js
```

Produces `result/lcov.info`.

### worker (.NET)

```bash
# worker/tests/Worker.Tests.csproj
<PackageReference Include="coverlet.collector" Version="6.0.2" />
```

```bash
dotnet test worker/tests/Worker.Tests.csproj \
  --collect:"XPlat Code Coverage" \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=opencover
```

Produces `worker/tests/TestResults/*/coverage.opencover.xml`.

---

## 3. Choosing where SonarQube runs

| | Cost | Notes |
|---|---|---|
| **SonarCloud** | free for public repos | No server to run. Public repo means public results. |
| **Self-hosted Community** | free, needs a host | ~2GB RAM plus a Postgres. Full control. |
| **Local, in Docker** | free | Fine for learning; CI cannot reach it unless it is exposed. |

For this project, **SonarCloud** — the repository is already public, and running a server for
one project is not a good trade.

If you self-host to learn how it works:

```bash
docker run -d --name sonarqube -p 9000:9000 sonarqube:community
# http://localhost:9000  --  admin / admin
```

Be aware CI cannot reach `localhost:9000` from a GitHub runner. Either run the scan locally
against it, or use a self-hosted runner.

---

## 4. Project configuration

Create `sonar-project.properties` at the repository root:

```properties
sonar.projectKey=venkata-siddardha_voting-app
sonar.organization=venkata-siddardha

# Analyse only application code. Terraform, manifests and docs are covered by
# tflint, trivy, actionlint and kustomize build -- letting Sonar grade them too
# produces duplicate findings that nobody owns.
sonar.sources=vote,result,worker
sonar.tests=vote/tests,result/tests,worker/tests

sonar.exclusions=**/node_modules/**,**/bin/**,**/obj/**,**/views/*.min.js,**/*.md

# Coverage reports, one per language
sonar.python.coverage.reportPaths=vote/coverage.xml
sonar.javascript.lcov.reportPaths=result/lcov.info
sonar.cs.opencover.reportsPaths=worker/tests/TestResults/**/coverage.opencover.xml

sonar.sourceEncoding=UTF-8
```

> **Exclude `result/views/angular.min.js`.** It is a vendored, minified library. Left in, it
> dominates every duplication and complexity metric and buries your real findings. A Sonar
> report that is 95% third-party noise gets ignored, and an ignored gate is worse than none.

---

## 5. The CI job

Add to `.github/workflows/app.yml`. It must run **after** the tests, because it consumes
their coverage output.

```yaml
  sonar:
    name: sonarqube
    runs-on: ubuntu-latest
    needs: [test]
    if: vars.SONAR_ENABLED == 'true'
    steps:
      - uses: actions/checkout@v4
        with:
          # Sonar attributes issues to commits and computes "new code" from
          # history. A shallow clone makes every line look new.
          fetch-depth: 0

      # regenerate coverage for all three, since `test` only ran the changed ones
      - uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - run: |
          cd vote && pip install -q -r requirements-dev.txt
          python -m pytest --cov=. --cov-report=xml:coverage.xml --cov-branch

      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - run: |
          cd result && npm install --no-audit --no-fund
          node --test --experimental-test-coverage \
               --test-reporter=lcov --test-reporter-destination=lcov.info \
               tests/*.test.js

      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: '8.0' }
      - run: |
          dotnet test worker/tests/Worker.Tests.csproj \
            --collect:"XPlat Code Coverage" \
            -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=opencover

      - uses: SonarSource/sonarqube-scan-action@v4
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}

      # Blocks the merge if the gate fails. Without this step the scan only
      # reports -- the gate exists but enforces nothing.
      - uses: SonarSource/sonarqube-quality-gate-action@v1
        timeout-minutes: 5
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

Then:

```bash
gh secret   set SONAR_TOKEN   --body "<token from SonarCloud>"
gh variable set SONAR_ENABLED --body true
```

> Gated on a repository **variable**, matching `INFRACOST_ENABLED`. A job-level `if:` can
> only read the `github`, `needs`, `vars` and `inputs` contexts — `secrets` is unavailable
> there, so the secret alone cannot switch a job on.

---

## 6. The quality gate — the decision that matters

Sonar ships a default gate called **Sonar way**. It grades **new code only**, not the whole
repository, and that is the single most important thing to understand about it.

| Condition | Default |
|---|---|
| Coverage on new code | ≥ 80% |
| Duplicated lines on new code | ≤ 3% |
| Maintainability / Reliability / Security rating | A |
| Security hotspots reviewed | 100% |

### Why "new code only" is the right default

A gate demanding 80% coverage across an existing codebase fails on day one and stays failing.
People add exclusions until it passes, and the gate becomes decoration.

Grading only what you *changed* means the rule is always achievable: write a test for the
code in this pull request. The codebase improves as it is touched, rather than requiring a
project nobody has time for.

**Start with Sonar way unchanged.** Tune only when you have a specific reason, and record it.

### The gate will fail on your first real run

Expect it. This project has:

- **`result/views/angular.min.js`** — vendored, minified. Exclude it (§4).
- **`Npgsql 4.1.9`** — a known high-severity advisory, already flagged in
  `ARCHITECTURE.md` §8 and surfaced by `dotnet test` as NU1903. Sonar will flag it too. The
  fix is upgrading the package, not silencing the rule.
- **Low coverage on the parts that talk to Redis and Postgres.** Unavoidable in unit tests.
  Either accept a lower threshold for those files with a documented reason, or add
  integration tests.

Fix findings; do not lower the bar to make the number green. That habit is how gates die.

---

## 7. Making it block a merge

The gate only blocks if you make it required:

**Settings → Branches → add a rule for `main` → Require status checks → select `sonarqube`.**

Without that, a failing gate is a red tick people scroll past.

Same reasoning as the GitHub Environment approvals on the Terraform pipeline: the enforcement
lives in **repository settings, not workflow YAML**, so it cannot be bypassed by editing the
workflow in the same pull request.

---

## 8. Where it fits

```
PR opened
  ├─ test          unit tests, all three services
  ├─ kustomize     manifests render
  ├─ sonar         static analysis + coverage + gate   ← new
  └─ trivy         image vulnerabilities

merge
  └─ build → ECR → digest → overlays/dev → Argo CD → cluster
```

Sonar belongs on the pull request, before merge. Its whole value is refusing code, and after
a merge there is nothing left to refuse.

---

## 9. Worth knowing

**Sonar does not replace Trivy.** Sonar reads your source; Trivy reads your dependencies and
built images. `Npgsql 4.1.9` is a dependency problem — Trivy's job. Both are needed.

**"Security hotspots" are not bugs.** They are places needing a human decision, and the gate
requires them *reviewed*, not *fixed*. Reviewing one and marking it safe is a valid outcome.

**Coverage is a floor, not a goal.** 100% coverage of trivial getters tells you nothing.
The tests written for this project deliberately cover the two bugs that actually occurred —
the double RPUSH and the truncated voter id — because those are the shape of real failures
here. A coverage number cannot tell you whether you tested the right things.
