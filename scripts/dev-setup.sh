#!/bin/bash

# Elata Protocol Local Development Setup
set -e

echo "🚀 Setting up Elata Protocol for local development..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "foundry.toml" ]; then
    echo -e "${RED}❌ Please run this script from the elata-protocol directory${NC}"
    exit 1
fi

# Check if Anvil is running
if ! curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Anvil is not running. Starting Anvil...${NC}"
    echo "Please run 'anvil' in a separate terminal and press Enter to continue."
    read -p ""
else
    echo -e "${GREEN}✅ Anvil is running${NC}"
fi

# Build contracts
echo -e "${BLUE}🔨 Building contracts...${NC}"
forge build

# Deploy contracts to local network
echo -e "${BLUE}📦 Deploying contracts to Anvil...${NC}"
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
forge script script/DeployLocal.s.sol:DeployLocal \
    --rpc-url http://127.0.0.1:8545 \
    --broadcast \
    --private-key $PRIVATE_KEY

echo -e "${GREEN}✅ Contracts deployed successfully!${NC}"

# Setup frontend
echo -e "${BLUE}🎨 Setting up frontend...${NC}"
cd frontend

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing frontend dependencies..."
    npm install
fi

# Create .env.local if it doesn't exist
if [ ! -f ".env.local" ]; then
    echo "Creating .env.local file..."
    cat > .env.local << EOF
# Wallet Connect Project ID (get from https://cloud.walletconnect.com/)
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=your_project_id_here

# Local development addresses (updated by deploy script)
NEXT_PUBLIC_ELTA_ADDRESS_LOCALHOST=
NEXT_PUBLIC_APP_FACTORY_ADDRESS_LOCALHOST=
NEXT_PUBLIC_UNISWAP_ROUTER_ADDRESS_LOCALHOST=
EOF
    echo -e "${YELLOW}⚠️  Please update .env.local with the contract addresses from the deploy output above${NC}"
    echo -e "${YELLOW}⚠️  Also get a Wallet Connect project ID from https://cloud.walletconnect.com/${NC}"
else
    echo -e "${GREEN}✅ .env.local already exists${NC}"
fi

echo -e "${GREEN}🎉 Setup complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Update frontend/.env.local with the contract addresses shown above"
echo "2. Get a Wallet Connect project ID from https://cloud.walletconnect.com/"
echo "3. Import this private key into MetaMask: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
echo "4. Add localhost:8545 as a custom network in MetaMask (Chain ID: 31337)"
echo "5. Run 'npm run dev' in the frontend directory"
echo ""
echo -e "${GREEN}Happy building! 🧠⚡${NC}"


