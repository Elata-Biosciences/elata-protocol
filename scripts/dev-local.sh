#!/bin/bash

# ==============================================
# Elata Protocol - Local Development Script
# ==============================================
# This script sets up a complete local blockchain
# environment with all contracts deployed and
# seeded with test data.
# ==============================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${CYAN}"
echo "================================================="
echo "  ELATA PROTOCOL - LOCAL DEVELOPMENT SETUP"
echo "================================================="
echo -e "${NC}"

# Check if Foundry is installed
if ! command -v forge &> /dev/null; then
    echo -e "${RED}Error: Foundry is not installed!${NC}"
    echo "Please install Foundry: https://book.getfoundry.sh/getting-started/installation"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}Error: Node.js is not installed!${NC}"
    echo "Please install Node.js: https://nodejs.org/"
    exit 1
fi

# Create deployments directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/deployments"

echo -e "${YELLOW}[1/6] Checking if Anvil is running...${NC}"
if lsof -Pi :8545 -sTCP:LISTEN -t >/dev/null ; then
    echo -e "${GREEN}✓ Anvil is already running on port 8545${NC}"
else
    echo -e "${YELLOW}Starting Anvil in the background...${NC}"
    anvil --chain-id 31337 --port 8545 > "$PROJECT_ROOT/anvil.log" 2>&1 &
    ANVIL_PID=$!
    echo $ANVIL_PID > "$PROJECT_ROOT/.anvil.pid"
    echo -e "${GREEN}✓ Anvil started (PID: $ANVIL_PID)${NC}"
    
    # Wait for Anvil to be ready
    echo "Waiting for Anvil to be ready..."
    sleep 2
fi

echo -e "${YELLOW}[2/6] Building contracts (this may take 30-60 seconds)...${NC}"
cd "$PROJECT_ROOT"
FOUNDRY_PROFILE=local forge build --force
echo -e "${GREEN}✓ Contracts built successfully${NC}"

echo -e "${YELLOW}[3/6] Deploying all contracts...${NC}"
FOUNDRY_PROFILE=local forge script script/DeployLocalFull.s.sol:DeployLocalFull \
    --rpc-url http://127.0.0.1:8545 \
    --broadcast \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --ffi
echo -e "${GREEN}✓ All contracts deployed${NC}"

echo -e "${YELLOW}[4/6] Seeding test data...${NC}"
FOUNDRY_PROFILE=local forge script script/SeedLocalData.s.sol:SeedLocalData \
    --rpc-url http://127.0.0.1:8545 \
    --broadcast \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --ffi
echo -e "${GREEN}✓ Test data seeded${NC}"

echo -e "${YELLOW}[5/6] Generating frontend configuration...${NC}"
if [ -f "$PROJECT_ROOT/scripts/generate-config.ts" ]; then
    npx tsx "$PROJECT_ROOT/scripts/generate-config.ts"
    echo -e "${GREEN}✓ Frontend configuration generated${NC}"
else
    echo -e "${YELLOW}⚠ Frontend config script not found, skipping...${NC}"
fi

echo -e "${YELLOW}[6/6] Setting up frontend...${NC}"
if [ -d "$PROJECT_ROOT/frontend" ]; then
    cd "$PROJECT_ROOT/frontend"
    if [ ! -d "node_modules" ]; then
        echo "Installing frontend dependencies..."
        npm install
    fi
    echo -e "${GREEN}✓ Frontend ready${NC}"
else
    echo -e "${YELLOW}⚠ Frontend directory not found, skipping...${NC}"
fi

echo -e "${GREEN}"
echo "================================================="
echo "      LOCAL DEVELOPMENT SETUP COMPLETE!"
echo "================================================="
echo -e "${NC}"

echo -e "${CYAN}Contract Addresses:${NC}"
if [ -f "$PROJECT_ROOT/deployments/local.json" ]; then
    cat "$PROJECT_ROOT/deployments/local.json" | head -20
else
    echo "See: deployments/local.json"
fi

echo ""
echo -e "${CYAN}Network Details:${NC}"
echo "  RPC URL:  http://127.0.0.1:8545"
echo "  Chain ID: 31337"
echo ""

echo -e "${CYAN}Test Accounts (all have 100K ELTA):${NC}"
echo "  1. 0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
echo "  2. 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
echo "  3. 0x90F79bf6EB2c4f870365E785982E1f101E93b906"
echo "  4. 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
echo "  5. 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"
echo ""

echo -e "${CYAN}Private Keys (Anvil defaults):${NC}"
echo "  Account 0: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
echo "  Account 1: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
echo "  Account 2: 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
echo ""

echo -e "${GREEN}Ready to develop!${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Start frontend:    npm run dev:frontend"
echo "  2. View logs:         tail -f anvil.log"
echo "  3. Stop Anvil:        npm run dev:stop"
echo "  4. Restart all:       npm run dev:restart"
echo ""

