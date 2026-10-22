#!/bin/bash

# Docker Compose Helper Script for Multi-App Setup with Traefik
# Manages Traefik, ILIAS, n8n, and FreshRSS

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
  printf 'Usage: %s <all|traefik|ilias|n8n|freshrss> <command> [args...]\n' "$0" >&2
  printf 'Available services: all, traefik, ilias, n8n, freshrss\n' >&2
}

if (($# == 0)); then
  usage
  exit 2
fi

SERVICE=$1
shift

# Preserve the default command when only a service is specified.
if (($# == 0)); then
  set -- up -d
fi
COMMAND=$1

# Map services to their compose files
COMPOSE_FILES=(-f docker-compose.yml)
case "$SERVICE" in
  all)
    echo -e "${GREEN}Managing all services (traefik, ilias, n8n, freshrss)${NC}"
    COMPOSE_FILES+=(
      -f docker-compose.traefik.yml
      -f docker-compose.ilias.yml
      -f docker-compose.n8n.yml
      -f docker-compose.freshrss.yml
    )
    ;;
  traefik)
    echo -e "${GREEN}Managing Traefik only${NC}"
    COMPOSE_FILES+=(-f docker-compose.traefik.yml)
    ;;
  ilias)
    echo -e "${GREEN}Managing ILIAS (LMS + MariaDB + cron)${NC}"
    COMPOSE_FILES+=(-f docker-compose.ilias.yml)
    ;;
  n8n)
    echo -e "${GREEN}Managing n8n${NC}"
    COMPOSE_FILES+=(-f docker-compose.n8n.yml)
    ;;
  freshrss)
    echo -e "${GREEN}Managing FreshRSS${NC}"
    COMPOSE_FILES+=(-f docker-compose.freshrss.yml)
    ;;
  *)
    printf '%b\n' "${RED}Unknown service: $SERVICE${NC}" >&2
    usage
    exit 2
    ;;
esac

# Validate .env file exists
if [ ! -f .env ]; then
  echo -e "${RED}Error: .env file not found!${NC}"
  echo "Create one based on your services' .env.example files"
  exit 1
fi

# Execute docker compose command
printf '%b' "${YELLOW}Running: docker compose"
printf ' %q' "${COMPOSE_FILES[@]}" "$@"
printf '%b\n' "$NC"
docker compose "${COMPOSE_FILES[@]}" "$@"

# Provide helpful output for specific commands
if [ "$COMMAND" = "up" ]; then
  echo ""
  echo -e "${GREEN}✓ Services starting...${NC}"
  if [[ "$SERVICE" == "all" ]] || [[ "$SERVICE" == "ilias" ]]; then
    echo "  ILIAS LMS:      https://lms.facultyai.eu"
  fi
  if [[ "$SERVICE" == "all" ]] || [[ "$SERVICE" == "n8n" ]]; then
    echo "  n8n:            https://n8n.webpat.net"
  fi
  if [[ "$SERVICE" == "all" ]] || [[ "$SERVICE" == "freshrss" ]]; then
    echo "  FreshRSS:       https://feeds.patrickweber.info"
  fi
  echo ""
  echo "Use './run.sh $SERVICE logs -f' to see logs"
fi

if [ "$COMMAND" = "down" ]; then
  echo -e "${YELLOW}Services stopped${NC}"
fi
