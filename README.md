# ddev-coolify

A DDEV add-on that generates production-ready Dockerfiles for [Coolify](https://coolify.io/) deployment using [ServerSideUp PHP Docker images](https://serversideup.net/open-source/docker-php/).

## Installation

```bash
ddev add-on get takielias/ddev-coolify
```

## Usage

### Interactive (recommended)

```bash
ddev coolify
```

Prompts for web server (FrankenPHP/Nginx) and container mode (single/multi).

### Non-interactive

```bash
# FrankenPHP + Supervisor (single container)
ddev coolify --server=frankenphp --supervisor

# Nginx + S6 (single container)
ddev coolify --server=nginx --supervisor

# FrankenPHP, separate containers
ddev coolify --server=frankenphp --no-supervisor

# Nginx, separate containers
ddev coolify --server=nginx --no-supervisor
```

### Flags

| Flag | Description |
|---|---|
| `--server`, `-s` | Web server: `frankenphp` or `nginx` |
| `--supervisor` | Single container mode |
| `--no-supervisor` | Multi container mode |
| `--dry-run`, `-n` | Preview without writing files |
| `--force`, `-f` | Overwrite existing files |
| `--output`, `-o` | Custom output directory |

## Features

- Generates multi-stage Dockerfile (Node build -> Composer -> Production image)
- Auto-detects PHP version, database, Node version from DDEV config
- Auto-detects PHP extensions from `composer.json` dependencies
- Auto-detects Horizon, Scheduler, Redis, and Wayfinder requirements
- Includes database client tools (`mysqldump`/`pg_dump`) for backups and debugging
- Auto-generates Wayfinder routes/actions in a dedicated build stage when `laravel/wayfinder` is detected
- Carries over `.ddev/web-build/Dockerfile` customizations
- Interactive prompts with flag overrides for CI/scripting
- Env-based runtime toggles for Horizon and Scheduler (`ENABLE_HORIZON`, `ENABLE_SCHEDULER`)

### Web Server Options

| Server | Image | Process Manager |
|---|---|---|
| **FrankenPHP** | `serversideup/php:X.X-frankenphp` | Supervisor (if single container) |
| **Nginx** | `serversideup/php:X.X-fpm-nginx` | S6 Overlay (built-in) |

### Container Modes

| Mode | Description |
|---|---|
| **Single container** | Web + Horizon + Scheduler in one container |
| **Multi container** | Separate Coolify services for worker + scheduler |

### Runtime Worker Toggles

When using single-container mode, Horizon and Scheduler are **disabled by default** and controlled via environment variables. This prevents crash-loops when Redis isn't configured.

| Variable | Default | Description |
|---|---|---|
| `ENABLE_HORIZON` | `false` | Set to `true` to start Horizon (requires Redis) |
| `ENABLE_SCHEDULER` | `false` | Set to `true` to start the Laravel Scheduler |

Set these in the Coolify UI under Environment Variables.

## Generated Files

| File | When |
|---|---|
| `docker/Dockerfile` | Always |
| `.dockerignore` | Always (project root) |
| `docker/start.sh` | FrankenPHP + Supervisor |
| `docker/supervisord.conf` | FrankenPHP + Supervisor |
| `docker/s6/horizon/run` | Nginx + S6 + Horizon detected |
| `docker/s6/horizon/type` | Nginx + S6 + Horizon detected |
| `docker/s6/scheduler/run` | Nginx + S6 + Scheduler detected |
| `docker/s6/scheduler/type` | Nginx + S6 + Scheduler detected |

## Coolify Setup

1. Push `docker/` folder and `.dockerignore` to your repo
2. In Coolify, create a new service from your repo
3. Set **Dockerfile location**: `docker/Dockerfile`
4. Set **Build context**: `/` (project root)
5. Set **Port**: `8080`
6. Add environment variables:
   - `APP_KEY`, `APP_URL`, `DB_HOST`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`
   - `REDIS_HOST`, `REDIS_DB` (if using Redis)
   - `ENABLE_HORIZON=true`, `ENABLE_SCHEDULER=true` (if using single-container mode with workers)

## Auto-detected PHP Extensions

Extensions are detected from `composer.json` packages:

| Package | Extensions Added |
|---|---|
| `spatie/laravel-medialibrary` | exif, gd |
| `barryvdh/laravel-dompdf` | gd |
| `maatwebsite/excel` | gd |
| `intervention/image` | gd |
| `moneyphp/money` | intl, bcmath |
| `laravel/cashier` | intl, bcmath |

Default image includes: opcache, pcntl, pdo_mysql, pdo_pgsql, redis, zip

## Local Docker Testing

```bash
# Generate
ddev coolify

# Build
docker build -f docker/Dockerfile -t myapp .

# Run (with DDEV's database)
docker run --rm -p 8080:8080 --network ddev-PROJECTNAME_default \
  -e APP_KEY=... -e DB_HOST=ddev-PROJECTNAME-db \
  -e DB_DATABASE=db -e DB_USERNAME=db -e DB_PASSWORD=db \
  -e ENABLE_HORIZON=true -e ENABLE_SCHEDULER=true \
  myapp
```

## Running Add-on Tests

```bash
# Requires: bats-core, bats-assert, bats-file, bats-support
bats tests/test.bats
```
