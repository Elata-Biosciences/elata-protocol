#!/bin/bash

# ==============================================
# Restart Local Development Environment
# ==============================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${CYAN}Restarting local development environment...${NC}\n"

# Stop existing environment
bash "$SCRIPT_DIR/dev-stop.sh"

# Wait a moment
sleep 1

# Start fresh environment
bash "$SCRIPT_DIR/dev-local.sh"

echo -e "${GREEN}Environment restarted!${NC}"


