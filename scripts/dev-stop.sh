#!/bin/bash

# ==============================================
# Stop Local Development Environment
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${YELLOW}Stopping local development environment...${NC}"

# Stop Anvil if PID file exists
if [ -f "$PROJECT_ROOT/.anvil.pid" ]; then
    ANVIL_PID=$(cat "$PROJECT_ROOT/.anvil.pid")
    if ps -p $ANVIL_PID > /dev/null 2>&1; then
        kill $ANVIL_PID
        echo -e "${GREEN}✓ Stopped Anvil (PID: $ANVIL_PID)${NC}"
    else
        echo -e "${YELLOW}⚠ Anvil process not found${NC}"
    fi
    rm "$PROJECT_ROOT/.anvil.pid"
else
    # Try to kill by port
    ANVIL_PID=$(lsof -ti:8545)
    if [ ! -z "$ANVIL_PID" ]; then
        kill $ANVIL_PID
        echo -e "${GREEN}✓ Stopped Anvil on port 8545${NC}"
    else
        echo -e "${YELLOW}⚠ No Anvil process found on port 8545${NC}"
    fi
fi

echo -e "${GREEN}Development environment stopped${NC}"


