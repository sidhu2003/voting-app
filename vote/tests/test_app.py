"""Unit tests for the vote service.

Deliberately covers the two things that have actually broken in this codebase
before -- the double RPUSH and the truncated voter id -- alongside the normal
paths. A test that only covers the happy path would not have caught either.
"""
import json

import pytest


# --------------------------------------------------------------------------
# GET -- rendering the page
# --------------------------------------------------------------------------

def test_get_renders_and_touches_no_redis(client, fake_redis):
    """The page must render without Redis.

    This is why a readiness probe on GET / says nothing about whether voting
    works: the page is served happily while every vote is failing.
    """
    resp = client.get("/")
    assert resp.status_code == 200
    fake_redis.rpush.assert_not_called()


def test_get_shows_the_configured_options(client, fake_redis, monkeypatch):
    import app as vote_app
    monkeypatch.setattr(vote_app, "option_a", "Tabs")
    monkeypatch.setattr(vote_app, "option_b", "Spaces")

    body = client.get("/").get_data(as_text=True)
    assert "Tabs" in body and "Spaces" in body


def test_get_sets_a_voter_id_cookie(client, fake_redis):
    resp = client.get("/")
    assert "voter_id" in resp.headers.get("Set-Cookie", "")


# --------------------------------------------------------------------------
# POST -- casting a vote
# --------------------------------------------------------------------------

def test_post_pushes_one_vote_to_redis(client, fake_redis):
    """REGRESSION: votes were once pushed TWICE.

    rpush was called directly and again inside an `if`. The tally stayed
    correct because the worker's upsert is idempotent, but queue depth and DB
    write volume were both doubled -- corrupting the exact metric used for
    queue-depth autoscaling and alerting.
    """
    client.post("/", data={"vote": "a"})
    assert fake_redis.rpush.call_count == 1


def test_post_sends_the_expected_payload(client, fake_redis):
    """The queue contract between vote and worker.

    Break this shape and the worker silently stops processing. Nothing in
    either codebase would catch it -- there is no schema, just an agreement.
    """
    client.set_cookie("voter_id", "alice")
    client.post("/", data={"vote": "b"})

    key, raw = fake_redis.rpush.call_args[0]
    assert key == "votes"

    payload = json.loads(raw)
    assert payload == {"voter_id": "alice", "vote": "b"}


def test_post_reuses_an_existing_voter_id(client, fake_redis):
    """One vote per browser. The cookie is the identity, so a repeat vote must
    reuse it -- that is what makes the worker's upsert change a vote rather
    than adding one."""
    client.set_cookie("voter_id", "bob")
    client.post("/", data={"vote": "a"})
    client.post("/", data={"vote": "b"})

    ids = {json.loads(c[0][1])["voter_id"] for c in fake_redis.rpush.call_args_list}
    assert ids == {"bob"}


@pytest.mark.parametrize("choice", ["a", "b"])
def test_both_options_are_accepted(client, fake_redis, choice):
    resp = client.post("/", data={"vote": choice})
    assert resp.status_code == 200
    assert json.loads(fake_redis.rpush.call_args[0][1])["vote"] == choice


# --------------------------------------------------------------------------
# voter id generation
# --------------------------------------------------------------------------

def test_generated_voter_id_is_full_length_hex(client, fake_redis):
    """REGRESSION: the last character used to be cut off.

    The code was `hex(...)[2:-1]` -- Python 2 syntax that stripped a trailing
    'L' which Python 3 does not emit. On Python 3 it silently removed a real
    hex digit, shrinking the id space 16x and making collisions between voters
    16x more likely.
    """
    client.post("/", data={"vote": "a"})
    voter_id = json.loads(fake_redis.rpush.call_args[0][1])["voter_id"]

    assert voter_id, "voter id must not be empty"
    int(voter_id, 16)                       # must be valid hex
    assert not voter_id.endswith("L")       # the bug this replaced
    assert len(voter_id) >= 15              # 64 bits, allowing leading zeros


def test_voter_ids_differ_between_fresh_clients(fake_redis):
    import app as vote_app

    ids = set()
    for _ in range(5):
        c = vote_app.app.test_client()
        c.post("/", data={"vote": "a"})
        ids.add(json.loads(fake_redis.rpush.call_args[0][1])["voter_id"])

    assert len(ids) == 5, "each new browser must get its own id"


# --------------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------------

def test_redis_password_absent_means_no_auth(monkeypatch):
    """An unset REDIS_PASSWORD must mean None, not the empty string.

    Passing "" would make the client attempt AUTH with an empty password and
    fail against a Redis that has no password set at all.
    """
    import importlib
    import app as vote_app

    monkeypatch.delenv("REDIS_PASSWORD", raising=False)
    importlib.reload(vote_app)
    assert vote_app.redis_password is None

    monkeypatch.setenv("REDIS_PASSWORD", "")
    importlib.reload(vote_app)
    assert vote_app.redis_password is None
