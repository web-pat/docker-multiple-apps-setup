#!/bin/bash

# Docker Compose Helper Script for Multi-App Setup with Traefik
# Manages Traefik, ILIAS, n8n, and FreshRSS

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get service and command
SERVICE=${1:-all}
COMMAND=${2:-up -d}

# Shift arguments
shift 2

# Map services to their compose files
case "$SERVICE" in
  all)
    echo -e "${GREEN}Managing all services (traefik, ilias, n8n, freshrss)${NC}"
    COMPOSE_FILES="-f docker-compose.traefik.yml -f docker-compose.ilias.yml -f docker-compose.n8n.yml -f docker-compose.freshrss.yml"
    ;;
  traefik)
    echo -e "${GREEN}Managing Traefik only${NC}"
    COMPOSE_FILES="-f docker-compose.traefik.yml"
    ;;
  ilias)
    echo -e "${GREEN}Managing ILIAS (LMS + MariaDB + cron)${NC}"
    COMPOSE_FILES="-f docker-compose.ilias.yml"
    ;;
  n8n)
    echo -e "${GREEN}Managing n8n${NC}"
    COMPOSE_FILES="-f docker-compose.n8n.yml"
    ;;
  freshrss)
    echo -e "${GREEN}Managing FreshRSS${NC}"
    COMPOSE_FILES="-f docker-compose.freshrss.yml"
    ;;
  *)
    echo -e "${RED}Unknown service: $SERVICE${NC}"
    echo "Available services: all, traefik, ilias, n8n, freshrss"
    exit 1
    ;;
esac

# Validate .env file exists
if [ ! -f .env ]; then
  echo -e "${RED}Error: .env file not found!${NC}"
  echo "Create one based on your services' .env.example files"
  exit 1
fi

# Execute docker compose command
echo -e "${YELLOW}Running: docker compose $COMPOSE_FILES $COMMAND $@${NC}"
docker compose $COMPOSE_FILES $COMMAND $@

# Provide helpful output for specific commands
if [ "$COMMAND" = "up" ] || [ "$COMMAND" = "up -d" ]; then
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
