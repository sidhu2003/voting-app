# Voting App

A distributed application running across multiple containers, used here as a practice rig for
containerisation, Kubernetes deployment, and high availability.

This solution uses Python, Node.js and .NET, with Redis for messaging and Postgres for storage.

## Getting started

Download [Docker Desktop](https://www.docker.com/products/docker-desktop) for Mac or Windows.
[Docker Compose](https://docs.docker.com/compose) will be automatically installed. On Linux, make
sure you have the latest version of [Compose](https://docs.docker.com/compose/install/).

Run in this directory to build and run the app:

```shell
docker compose up -d --build
```

| Service | URL |
|---|---|
| `vote` — cast a vote | <http://localhost:4000> |
| `result` — live tally | <http://localhost> |

Tear down with `docker compose down -v` (`-v` also removes the Postgres and Redis volumes).

> The `--build` flag matters: the compose file builds from source rather than pulling prebuilt
> images, so it reflects your working tree. If port 80 is already taken on your machine, change
> the `result` port mapping.

## Architecture

![Architecture diagram](architecture.excalidraw.png)

* A front-end web app in [Python](/vote) which lets you vote between two options
* A [Redis](https://hub.docker.com/_/redis/) which collects new votes
* A [.NET](/worker/) worker which consumes votes and stores them in…
* A [Postgres](https://hub.docker.com/_/postgres/) database backed by a volume
* A [Node.js](/result) web app which shows the results of the voting in real time

**📖 See [ARCHITECTURE.md](ARCHITECTURE.md)** for the full engineering reference: how the
components connect, the integration contracts between them, which tiers can and cannot be scaled,
failure and data-loss behaviour, the environment-variable configuration contract for
ConfigMaps/Secrets, and a set of hands-on verification experiments (§13).

## Configuration

Every connection detail is an environment variable — nothing is hardcoded. Non-sensitive values
belong in a ConfigMap, passwords in a Secret:

| Variable | Used by | Default |
|---|---|---|
| `REDIS_HOST` / `REDIS_PORT` / `REDIS_DB` | `vote`, `worker` | `redis` / `6379` / `0` |
| `REDIS_PASSWORD` | `vote`, `worker` | *(unset = no auth)* |
| `POSTGRES_HOST` / `POSTGRES_PORT` | `worker`, `result` | `db` / `5432` |
| `POSTGRES_USER` / `POSTGRES_DB` | `worker`, `result` | `postgres` / `postgres` |
| `POSTGRES_PASSWORD` | `worker`, `result` | `postgres` |
| `OPTION_A` / `OPTION_B` | `vote` | `Cats` / `Dogs` |
| `PORT` | `result` | `4000` |

Full details, including the Redis authentication setup and the three places
`POSTGRES_PASSWORD` must agree, are in [§4.4 of ARCHITECTURE.md](ARCHITECTURE.md).

## Notes

The voting application only accepts one vote per client browser. A repeat vote from the same
browser *changes* the existing vote rather than adding a new one.
