# Docker Server Configs

Multi-app Docker Compose setup with Traefik reverse proxy, Adapt Learning, n8n, and FreshRSS.

## Architecture

```
[Internet] → Host:80/443 → Traefik
                            ├── learn.example.com   → Adapt Learning → MongoDB
                            ├── n8n.example.com     → n8n            → PostgreSQL
                            └── feeds.example.com   → FreshRSS (SQLite)
```

Only Traefik binds host ports (80/443). Every app registers with Traefik via Docker
labels — no port conflicts, no manual reverse-proxy config per app.

## File Structure

```
.env                                     ← All secrets & config (gitignored)
docker-compose.yml                       ← Shared network & volume definitions
docker-compose.traefik.yml               ← Traefik reverse proxy (entrypoint)
docker-compose.adapt.yml                 ← Adapt Learning + MongoDB
docker-compose.n8n.yml                   ← n8n + PostgreSQL
docker-compose.freshrss.yml              ← FreshRSS (SQLite)
run.sh                                   ← Helper script (shortcut for compose)
.gitignore
```

## Secrets

All credentials live in `.env`, **not** in the compose files:

```env
# Domains
TRAEFIK_ACME_EMAIL=admin@example.com
ADAPT_SITE_URL=learn.example.com
N8N_DOMAIN=n8n.example.com
FRESHRSS_DOMAIN=feeds.example.com

# Adapt Learning
ADAPT_ADMIN_EMAIL=admin@example.com
ADAPT_ADMIN_PASSWORD=...
ADAPT_MONGO_USER=...
ADAPT_MONGO_PASSWORD=...
ADAPT_SESSION_SECRET=...

# n8n
N8N_DB_USER=...
N8N_DB_PASSWORD=...
N8N_DB_NAME=...
N8N_ENCRYPTION_KEY=...
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

### Adapt Learning (`docker-compose.adapt.yml`)
- Image: `garyritchie/docker-adaptauthoring:latest`
- MongoDB 7 on internal `adapt_internal` network
- Authoring tool + LMS frontend behind Traefik (port 5000)
- `ENABLE_REVERSE_PROXY=true` for Traefik, admin credentials from `.env`
- Volumes: `adapt_data`, `adapt_mongodb_data`

### n8n (`docker-compose.n8n.yml`)
- Image: `n8nio/n8n:latest`
- PostgreSQL 16 on internal `n8n_internal` network
- Health-checked dependency on Postgres before starting
- Volumes: `postgres_n8n_data`, `n8n_data`

### FreshRSS (`docker-compose.freshrss.yml`)
- Image: `freshrss/freshrss:latest`
- SQLite (no extra database container)
- Cron job for feed refresh every 20 minutes
- Volumes: `freshrss_data`, `freshrss_extensions`

## Usage

### Start services

```bash
./run.sh all up -d              # Start everything
./run.sh adapt up -d            # Start only Adapt Learning
./run.sh n8n up -d              # Start only n8n
./run.sh freshrss up -d         # Start only freshrss
./run.sh traefik up -d          # Start traefik alone
```

> App compose files treat `traefik_public` as an `external` network, so Traefik
> must be running first. `./run.sh all up -d` handles this ordering automatically.

### View logs

```bash
./run.sh all logs -f            # Follow logs from all services
./run.sh adapt logs -f          # Follow adapt + mongodb logs
./run.sh n8n logs -f            # Follow n8n + postgres logs
```

### Stop / restart individual containers

```bash
docker compose stop adapt_authoring     # Stop Adapt Learning only
docker compose start adapt_authoring    # Start it again
docker compose restart adapt_authoring  # Restart Adapt Learning
docker compose stop freshrss            # Stop freshrss
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
| `adapt_internal` | Adapt only | MongoDB is not exposed to Traefik |
| `n8n_internal` | n8n only | PostgreSQL is not exposed to Traefik |

## First-Run Notes

- Traefik automatically provisions Let's Encrypt certificates. The first HTTPS request
  may be slow (certificate generation).
- Adapt Learning creates its admin user from the `.env` credentials on first start
  (`https://learn.example.com`).
- n8n creates its admin user on first access (`https://n8n.example.com`).
- FreshRSS shows its setup page on first access (`https://feeds.example.com`).

## Upload filesize limit fix
Although php and nginx within docker containers got more generous filesize and upload time limits uploads generally run into a hardcoded 60s limit by Traefik, which runs as a reverse proxy in front of all services listed above.

Fixed by setting respondingTimeouts.readTimeout/writeTimeout/idleTimeout as static configuration (command-line flags on the Traefik entrypoint), not as per-router labels. That's the mechanism that actually works on Traefik v2.11 installation used in this setup. The label-based timeout middleware never parsed correctly, going all the way back to the Moodle attempts.

## Ilias v10.9 2026-07-07 member tab Hotfix
Opening the members tab in an existing course creates an error due to php failing to parse a category.

Open the affected file within the Ilias Docker container in a text editor.

`docker exec -it ilias_app nano /var/www/html/components/ILIAS/Course/classes/class.ilCourseParticipantsTableGUI.php`

Search for a line looking like this

`protected \$refinery;`

and replace it like this

`protected ILIAS\Refinery\Factory $refinery;`

Reload the Ilias website for the cache to refresh.

This fix will be lost after *docker compose down* and needs to be reapplied after it being rebuilt.
