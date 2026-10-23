# Docker Server Configs

Multi-app Docker Compose setup with Traefik reverse proxy, ILIAS, n8n, and FreshRSS.

## Architecture

```
[Internet] → Host:80/443 → Traefik
                            ├── lms.example.com     → ILIAS → MariaDB
                            ├── n8n.example.com     → n8n   → PostgreSQL
                            └── feeds.example.com   → FreshRSS (SQLite)
```

Only Traefik binds host ports (80/443). Every app registers with Traefik via Docker
labels — no port conflicts, no manual reverse-proxy config per app.

## File Structure

```
.gitignore                               ← Excludes local secrets and runtime data
README.md                                ← Setup documentation
docker-compose.freshrss.yml              ← FreshRSS (SQLite)
docker-compose.ilias.yml                 ← ILIAS + MariaDB + cron
docker-compose.n8n.yml                   ← n8n + PostgreSQL
docker-compose.traefik.yml               ← Traefik reverse proxy (entrypoint)
docker-compose.yml                       ← Shared network and certificate volume
nginx-uploads.conf                       ← Nginx upload timeout/size settings (not mounted by Compose)
run.sh                                   ← Helper script (shortcut for compose)
```

## Secrets

Create a local `.env` for credentials and configuration; it is gitignored and
not included in the repository. For example:

```env
# Domains
TRAEFIK_ACME_EMAIL=admin@example.com
ILIAS_SITE_URL=lms.example.com
N8N_DOMAIN=n8n.example.com
FRESHRSS_DOMAIN=feeds.example.com

# ILIAS
ILIAS_DB_USER=...
ILIAS_DB_PASSWORD=...
ILIAS_DB_NAME=...
ILIAS_DB_ROOT_PASSWORD=...
ILIAS_CLIENT_NAME=...
ILIAS_TIMEZONE=Europe/Berlin
ILIAS_ROOT_PASSWORD=...
ILIAS_MAX_UPLOAD_SIZE=500M
ILIAS_MEMORY_LIMIT=512M
ILIAS_SESSION_LIFETIME=3600

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

### ILIAS (`docker-compose.ilias.yml`)
- LMS image: `srsolutions/ilias:10-php8.3-apache`, routed through Traefik on container port 80
- MariaDB 10.11 on the internal `ilias_internal` network (not exposed to Traefik)
- Separate `ilias-cron` container runs scheduled ILIAS jobs using the same image and data volumes
- Automatic setup and updates enabled; database, site, root password, and upload settings come from `.env`
- Volumes: `ilias_data`, `ilias_iliasdata`, `ilias_mariadb_data`

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
./run.sh ilias up -d            # Start ILIAS, MariaDB, and cron
./run.sh n8n up -d              # Start only n8n
./run.sh freshrss up -d         # Start only freshrss
./run.sh traefik up -d          # Start traefik alone
```

> Start Traefik before starting ILIAS on its own: its compose file expects the
> `traefik_public` network to exist. `./run.sh all up -d` creates the network
> as part of the combined Compose setup.

### View logs

```bash
./run.sh all logs -f            # Follow logs from all services
./run.sh ilias logs -f          # Follow ILIAS, MariaDB, and cron logs
./run.sh n8n logs -f            # Follow n8n + postgres logs
```

### Stop / restart individual containers

```bash
./run.sh ilias stop ilias        # Stop the ILIAS web container only
./run.sh ilias start ilias       # Start it again
./run.sh ilias restart ilias     # Restart the ILIAS web container
./run.sh freshrss stop freshrss  # Stop FreshRSS
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
| `ilias_internal` | ILIAS only | MariaDB and cron are not exposed to Traefik |
| `n8n_internal` | n8n only | PostgreSQL is not exposed to Traefik |

## First-Run Notes

- Traefik automatically provisions Let's Encrypt certificates. The first HTTPS request
  may be slow (certificate generation).
- ILIAS runs automated setup on first start using the `.env` database and root
  credentials (`https://lms.example.com` when using the example domain).
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

**Update 2026-10-22:** Hotfix has been made obsolete through updated docker image.
