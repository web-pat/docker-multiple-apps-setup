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

## Backups and recovery (WebDAV)

`docker-compose.backup.yml` is an **optional overlay**, not a standalone stack.
It uses [offen/docker-volume-backup](https://offen.github.io/docker-volume-backup/)
to upload a GPG-encrypted archive to WebDAV every day at **03:00 Europe/Berlin**.
It does not publish ports or require a Traefik route. `run.sh` is unchanged and
does **not** include this overlay; use the commands below for backup management.

### Scope and limitations

Included:

- ILIAS database dump (including routines, events, and triggers), `ilias_data`,
  and `ilias_iliasdata` — both database records and uploaded course files matter.
- n8n PostgreSQL dump and `n8n_data`.
- FreshRSS data and extensions, with checked SQLite online backups replacing
  the live database files in the archive.
- Traefik certificates, `.env` (including `N8N_ENCRYPTION_KEY`), Compose files,
  `run.sh`, this README, and `nginx-uploads.conf`.

Not included: Docker images, writable container layers, additional manually
created database roles/databases, or data outside the listed mounts. Live
MariaDB/PostgreSQL storage files are deliberately excluded; restore their dumps
into newly initialized database volumes instead.

Regular backups do not stop applications, but cause additional CPU, disk, and
database load. MariaDB requires transactional tables (InnoDB) for the intended
online consistency; do not run schema migrations during backup. Database dumps
and concurrently changed uploads are **not one atomic application snapshot**.
Before a final migration, arrange a write-free window, including cron jobs,
workflow executions, and feed refreshes, and take a final backup.

The FreshRSS helper expects the current SQLite setup with `*.sqlite` database
files. No databases, unreadable WAL state, a failed integrity check, or a dump
failure aborts the run. Verify these assumptions on the actual installation.
The helper preserves database file ownership and permissions. A run marker for
each database prevents uploading stale dumps if a required container is stopped.

### 1. Configure and start

Add these values to the local, gitignored `.env` (replace all placeholders):

```dotenv
BACKUP_WEBDAV_URL=https://webdav.example.invalid
BACKUP_WEBDAV_PATH=/backups/docker-multi-apps/
BACKUP_WEBDAV_USERNAME=REPLACE_ME
BACKUP_WEBDAV_PASSWORD='REPLACE_WITH_WEBDAV_PASSWORD'
BACKUP_GPG_PASSPHRASE='REPLACE_WITH_LONG_RANDOM_PASSPHRASE'
# Optional Shoutrrr notification URL; failures only by default:
# BACKUP_NOTIFICATION_URLS=...
```

Use HTTPS and a dedicated WebDAV directory/account. The account needs upload,
directory creation/listing, and (if retention is enabled) deletion permissions.
The destination/proxy must accept large single-file uploads and their duration.
TLS verification remains enabled. The source server's Traefik settings do not
affect backup creation; a proxy in front of the WebDAV destination can affect
uploads. An off-server WebDAV destination is strongly recommended.

**Keep the GPG passphrase outside this server as well**, for example in a password
manager. Its copy inside the encrypted archive cannot unlock that archive.
Protect `.env` with `chmod 600 .env`. Environment credentials are visible to
Docker administrators. Docker socket access is effectively host-admin access,
even when the socket is mounted `:ro`; do not expose it over HTTP.

In a Bash shell, from this repository's directory, define this convenience
function (it only affects the current shell):

```bash
dc_backup() {
  docker compose \
    -f docker-compose.yml \
    -f docker-compose.traefik.yml \
    -f docker-compose.ilias.yml \
    -f docker-compose.n8n.yml \
    -f docker-compose.freshrss.yml \
    -f docker-compose.backup.yml "$@"
}

dc_backup config --quiet
dc_backup up -d mariadb postgres_n8n backup-sqlite backup
```

Use the **same Compose project name** as the existing installation. If originally
started with `-p` or `COMPOSE_PROJECT_NAME`, retain that setting. Otherwise new,
empty volumes may be created instead of attaching the existing data.

**Initial setup recreates MariaDB/PostgreSQL containers to add dump mounts**, with
a short database interruption. Schedule this once; application services are not
recreated by the targeted command above. Subsequent backups need no restarts.
Do not switch back to an overlay-free `up` for these database services: Compose
can remove their extra dump mounts/labels by recreating them. For subsequent
stack-wide updates use `dc_backup up -d`, not `./run.sh all up -d`.

Leave enough free space on the Docker storage filesystem for dumps and the
compressed archive plus its encrypted copy. No persistent local archive is kept;
the encrypted result is sent to WebDAV. Upload failures must be monitored and
retried. Automatic retention is initially disabled; after a successful restore
test, optionally set `BACKUP_RETENTION_DAYS` to e.g. `30` in the overlay. Its
`multi-apps-` pruning prefix restricts deletion to matching backup names.

### 2. Trigger and check a backup

```bash
dc_backup exec -T backup backup
dc_backup logs --tail=200 backup
```

Confirm a new, non-empty `.tar.gz.gpg` file exists on WebDAV. Download it and
perform a test restore before relying on this setup. Do not start independent
backup stacks that write to the same dump volumes; the backup lock only
coordinates runs inside one backup container.

### 3. Optional: preserve the exact running application images

The scheduled WebDAV archive does **not** contain images. For an offline migration
or protection against mutable tags, export actual running image IDs separately
(Bash; run while all application containers exist):

```bash
docker inspect --format '{{.Image}} {{.Config.Image}}' \
  traefik ilias_app ilias_cron ilias_db n8n_app n8n_postgres freshrss \
  | sort -u > image-tags.txt
mapfile -t image_ids < <(cut -d ' ' -f 1 image-tags.txt | sort -u)
docker image save --output images.tar "${image_ids[@]}"
sha256sum images.tar image-tags.txt > images.sha256
```

Transfer these three files separately to the destination/off-server storage;
this command does not upload them to WebDAV. They contain application images,
not the backup/helper images. Record the source architecture (`docker info
--format '{{.Architecture}}'`); saved images must be compatible with the target.
If images are re-downloaded instead, mutable tags such as `latest` may resolve
to newer, incompatible software or trigger automatic application migrations.

### 4. Restore on a clean server

**Only use this procedure with empty target volumes. Never restore over running
applications or use `down -v` on a server whose data you need to retain.** Test
in an isolated environment first; n8n workflows, ILIAS cron, and FreshRSS refreshes
can otherwise trigger external actions. Existing installations require a separate
rollback plan and their own pre-restore backup.

1. Install Docker Engine, Compose v2, Python 3, and GPG. Download the selected archive from
   WebDAV. Decrypt/extract into a private directory outside the project:

   ```bash
   umask 077
   mkdir -p "$HOME/docker-restore"
   gpg --output "$HOME/docker-restore/backup.tar.gz" --decrypt /path/to/backup.tar.gz.gpg
   tar -tzf "$HOME/docker-restore/backup.tar.gz"
   sudo tar --numeric-owner -xzpf "$HOME/docker-restore/backup.tar.gz" -C "$HOME/docker-restore"
   export RESTORE_ROOT="$HOME/docker-restore/backup"
   ```

   The archive contains a `backup/` directory with `config/`, `volumes/`, and
   `databases/`. Check this layout and only extract trusted archives. GPG must
   finish successfully before extraction. Decrypted files contain secrets.

2. Copy `config/` (including hidden `.env`) into the new project directory,
   preserve file modes, and keep the same Compose project name. If saved images
   are available, verify and import them **before** creating containers:

   ```bash
   sha256sum --check images.sha256
   docker image load --input images.tar
   while read -r image_id image_tag; do
     docker image tag "$image_id" "$image_tag"
   done < image-tags.txt
   ```

   Perform the remaining commands from the restored project directory. Define
   a base-stack function **without** the backup overlay so no backup runs while
   restoration is in progress:

   ```bash
   dc_restore() {
     docker compose \
       -f docker-compose.yml \
       -f docker-compose.traefik.yml \
       -f docker-compose.ilias.yml \
       -f docker-compose.n8n.yml \
       -f docker-compose.freshrss.yml "$@"
   }
   volume_name() {
     dc_restore config --format json | python3 -c \
       'import json,sys; print(json.load(sys.stdin)["volumes"][sys.argv[1]]["name"])' "$1"
   }
   restore_project=$(dc_restore config --format json | python3 -c \
     'import json,sys; print(json.load(sys.stdin)["name"])')
   ```

   Do not create/start application containers yet: Docker may otherwise populate
   empty volumes with image defaults. If images were not imported, explicitly
   pull the intended compatible versions before starting the services.
   Pull the restore helper `alpine:3.22` as well, or transfer it in advance for an
   offline restore. On an isolated test host, restrict outbound traffic before
   starting any application; do not point production DNS at it yet.

3. Restore the six file volumes, resolving their actual names from Compose
   rather than assuming a project prefix. The function refuses existing volumes:

   ```bash
   restore_volume() {
     local logical="$1" volume
     volume=$(volume_name "$logical") || return 1
     test -n "$volume" || return 1
     if docker volume inspect "$volume" >/dev/null 2>&1; then
       echo "Refusing existing volume: $volume" >&2
       return 1
     fi
     docker volume create \
       --label "com.docker.compose.project=$restore_project" \
       --label "com.docker.compose.volume=$logical" "$volume" || return 1
     docker run --rm \
       -v "$volume:/restore" \
       -v "$RESTORE_ROOT/volumes/$logical:/source:ro" \
       alpine:3.22 sh -ec \
       'test -z "$(ls -A /restore)" || { echo "Target volume is not empty" >&2; exit 1; }; cp -a /source/. /restore/'
   }

   restore_volume ilias_data
   restore_volume ilias_iliasdata
   restore_volume n8n_data
   restore_volume freshrss_data
   restore_volume freshrss_extensions
   restore_volume traefik_certificates
   ```

   **Check every command for success; stop on any error.** Populate FreshRSS's
   already-restored user directories with the separately backed-up SQLite files.
   Copy files only, not the dump directory metadata (which belongs to root):

   ```bash
   freshrss_volume=$(volume_name freshrss_data)
   docker run --rm \
     -v "$freshrss_volume:/restore" \
     -v "$RESTORE_ROOT/databases/freshrss:/sqlite:ro" \
     alpine:3.22 sh -ec 'cd /sqlite; find . -type f -name "*.sqlite" -exec sh -ec '\''for file; do cp -p "$file" "/restore/$file"; done'\'' sh {} +'
   ```

4. Start **only** the databases; wait for both to report healthy with
   `dc_restore ps` before importing. PostgreSQL creates the configured user and
   database from `.env`; MariaDB does likewise. Then import:

   ```bash
   docker network inspect traefik_public >/dev/null 2>&1 || docker network create traefik_public
   dc_restore up -d --pull never mariadb postgres_n8n
   # Wait for both database health checks to pass before continuing.
   dc_restore exec -T mariadb sh -ec \
     'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mariadb --user=root' \
     < "$RESTORE_ROOT/databases/mariadb/ilias.sql"
   dc_restore exec -T postgres_n8n sh -ec \
     'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --host=127.0.0.1 --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --exit-on-error' \
     < "$RESTORE_ROOT/databases/postgres/n8n.dump"
   ```

   Do not start applications unless both imports succeed. Keep `.env`, database
   credentials, and `N8N_ENCRYPTION_KEY` consistent with the backup. Check that
   restored `acme.json` is valid JSON and has mode `600` before starting Traefik.

5. In isolation, start applications deliberately and test ILIAS login/course
   downloads, n8n credential decryption, and FreshRSS users/feed state. Even
   without `ilias-cron`, n8n and FreshRSS can schedule work on startup:

   ```bash
   dc_restore up -d --pull never traefik ilias n8n freshrss
   ```

   Once validated, arrange production DNS/access and external connectivity, start
   `ilias-cron`, and enable the backup overlay again using step 1. Starting the
   overlay recreates the database containers once to attach their dump mounts.
   Keep decrypted recovery files private and remove them securely according to
   your storage policy when they are no longer needed.
