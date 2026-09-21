"""Shared test setup.

app.py sits one directory up, so put it on the import path rather than
restructuring the project into a package (which would change the Dockerfile).
"""
import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app as vote_app  # noqa: E402


@pytest.fixture
def fake_redis(monkeypatch):
    """Replace the Redis client with a mock.

    The app builds its client lazily inside get_redis(), so patching the class
    is enough -- no network, no running Redis, and we can assert on exactly
    what would have been sent.
    """
    client = MagicMock()
    client.rpush.return_value = 1          # Redis returns the new list length
    monkeypatch.setattr(vote_app, "Redis", MagicMock(return_value=client))
    return client


@pytest.fixture
def client():
    vote_app.app.config.update(TESTING=True)
    return vote_app.app.test_client()
