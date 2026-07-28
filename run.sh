#!/bin/bash
set -e

BASE="-f docker-compose.yml -f docker-compose.traefik.yml"
FILES_ALL="$BASE -f docker-compose.moodle.yml -f docker-compose.n8n.yml -f docker-compose.freshrss.yml"
FILES_MOODLE="$BASE -f docker-compose.moodle.yml"
FILES_N8N="$BASE -f docker-compose.n8n.yml"
FILES_FRESHRSS="$BASE -f docker-compose.freshrss.yml"

usage() {
  echo "Usage: $0 {all|traefik|moodle|n8n|freshrss} [docker-compose arguments]"
  echo ""
  echo "Examples:"
  echo "  $0 all up -d              Start all services"
  echo "  $0 moodle up -d           Start moodle + traefik"
  echo "  $0 n8n logs -f            Follow n8n logs"
  echo "  $0 freshrss stop          Stop freshrss container"
  echo ""
  echo "Manage individual containers directly:"
  echo "  docker compose stop moodle_app"
  echo "  docker compose start moodle_app"
  echo "  docker compose restart n8n_app"
  exit 1
}

[ $# -lt 1 ] && usage

APP=$1; shift

case "$APP" in
  all)      docker compose $FILES_ALL "$@" ;;
  moodle)   docker compose $FILES_MOODLE "$@" ;;
  n8n)      docker compose $FILES_N8N "$@" ;;
  freshrss) docker compose $FILES_FRESHRSS "$@" ;;
  traefik)  docker compose $BASE "$@" ;;
  *)        usage ;;
esac
