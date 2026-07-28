# Caerus Docker Configs

Multi-app Docker Compose setup with Traefik reverse proxy, Moodle, n8n, and FreshRSS.

## Architecture

```
[Internet] → Host:80/443 → Traefik
                            ├── moodle.example.com  → Moodle   → MariaDB
                            ├── n8n.example.com     → n8n      → PostgreSQL
                            └── feeds.example.com   → FreshRSS (SQLite)
```

Only Traefik binds host ports (80/443). Every app registers with Traefik via Docker
labels — no port conflicts, no manual reverse-proxy config per app.

## File Structure

```
.env                                     ← All secrets & config (gitignored)
docker-compose.yml                       ← Shared network & volume definitions
docker-compose.traefik.yml               ← Traefik reverse proxy (entrypoint)
docker-compose.moodle.yml                ← Moodle + MariaDB
docker-compose.n8n.yml                   ← n8n + PostgreSQL
docker-compose.freshrss.yml              ← FreshRSS (SQLite)
run.sh                                   ← Helper script (shortcut for compose)
.gitignore
```

## Secrets

All credentials live in `.env`, **not** in the compose files:

```env
# Domains
MOODLE_SITE_URL=moodle.example.com
N8N_DOMAIN=n8n.example.com
FRESHRSS_DOMAIN=feeds.example.com

# Moodle
MOODLE_DB_ROOT_PASSWORD=...
MOODLE_DB_PASSWORD=...
MOODLE_ADMIN_PASSWORD=...

# n8n
N8N_DB_PASSWORD=...
N8N_ENCRYPTION_KEY=...

# FreshRSS
FRESHRSS_ADMIN_PASSWORD=...
```

Compose files reference these as `${VAR}` — Docker Compose reads `.env`
automatically when running from this directory.

## Services

### Traefik (`docker-compose.traefik.yml`)
- Image: `traefik:v2.11`
- Ports 80/443 (host → container)
- Let's Encrypt via HTTP-01 challenge (automatic)
- Docker provider: discovers containers by labels, no config reload needed
- Certificate storage: `traefik_certificates` Docker volume

### Moodle (`docker-compose.moodle.yml`)
- Image: `erseco/alpine-moodle:latest`
- MariaDB 10.11 on internal `moodle_internal` network
- Nginx & Certbot removed (Traefik handles SSL + reverse proxy)
- `REVERSEPROXY=true`, `SSLPROXY=true`
- Volumes: `mariadb_data`, `moodle_code`, `moodle_data`

### n8n (`docker-compose.n8n.yml`)
- Image: `n8nio/n8n:latest`
- PostgreSQL 16 on internal `n8n_internal` network
- Health-checked dependency on Postgres before starting
- Volumes: `postgres_n8n_data`, `n8n_data`

### FreshRSS (`docker-compose.freshrss.yml`)
- Image: `freshrss/freshrss:latest`
- SQLite (no extra database container)
- Cron job for feed refresh every 5 minutes
- Volumes: `freshrss_data`, `freshrss_extensions`

## Usage

### Start services

```bash
./run.sh all up -d              # Start everything
./run.sh moodle up -d           # Start only moodle (+ traefik)
./run.sh n8n up -d              # Start only n8n (+ traefik)
./run.sh freshrss up -d         # Start only freshrss (+ traefik)
./run.sh traefik up -d          # Start traefik alone
```

### View logs

```bash
./run.sh all logs -f            # Follow logs from all services
./run.sh moodle logs -f         # Follow moodle + mariadb logs
./run.sh n8n logs -f            # Follow n8n + postgres logs
```

### Stop / restart individual containers

```bash
docker compose stop n8n_app          # Stop n8n only
docker compose start n8n_app         # Start it again
docker compose restart moodle_app    # Restart moodle
docker compose stop freshrss         # Stop freshrss
```

### Stop everything

```bash
./run.sh all down
```

## Adding a New App

1. Create a new compose file (e.g., `docker-compose.myapp.yml`)
2. Attach the service to the `traefik_public` network
3. Add Traefik labels for routing:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.example.com`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

4. Add secrets to `.env` (never hardcode in YAML)
5. Add the file to `run.sh`

The new app gets an automatic SSL certificate from Let's Encrypt on first request.
No ports to manage — only Traefik exposes 80/443 to the host.

## Networks

| Network | Scope | Purpose |
|---------|-------|---------|
| `traefik_public` | Shared (all apps) | HTTP traffic between Traefik and web services |
| `moodle_internal` | Moodle only | MariaDB is not exposed to Traefik |
| `n8n_internal` | n8n only | PostgreSQL is not exposed to Traefik |

## First-Run Notes

- Traefik automatically provisions Let's Encrypt certificates. The first HTTPS request
  may be slow (certificate generation).
- Moodle's initial setup is done via the `erseco/alpine-moodle` image env vars
  (admin user, site name, etc.). No manual install wizard needed.
- n8n creates its admin user on first access (`https://n8n.example.com`).
- FreshRSS shows its setup page on first access (`https://feeds.example.com`).
