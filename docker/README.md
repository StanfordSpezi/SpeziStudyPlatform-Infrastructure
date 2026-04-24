# Docker Local Development

Local development environment for the Spezi Study Platform. Provides backing services (PostgreSQL, Keycloak) and optionally runs the full stack using published container images.

Used by:

- [SpeziStudyPlatform-Server](https://github.com/StanfordSpezi/SpeziStudyPlatform-Server)
- [SpeziStudyPlatform-Web](https://github.com/StanfordSpezi/SpeziStudyPlatform-Web)

## Setup

```bash
cp .env.example .env
```

## Full Stack

```bash
docker compose up -d
```

| Service        | URL                         |
| -------------- | --------------------------- |
| Web            | http://localhost:3000       |
| Server         | http://localhost:8080       |
| Keycloak       | http://localhost:8180       |
| Keycloak Admin | http://localhost:8180/admin |
| Server DB      | localhost:5432              |

## Backing Services Only

For running server or web natively:

```bash
docker compose up -d server-db keycloak-db keycloak
```

Then run server/web from their repos against localhost ports.

## Migrations

```bash
docker compose run --rm server-migrate
```

## Test Users

All passwords: `password123`

| Email              | Role        |
| ------------------ | ----------- |
| leland@example.com | admin       |
| jane@example.com   | researcher  |
| alice@example.com  | participant |

## Keycloak Admin

Username: `admin`, password: `admin` (configurable in `.env`)

## Reset

```bash
docker compose down -v
```
