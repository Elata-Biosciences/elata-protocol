#!/bin/bash
# Ethereum Sepolia Deployment Script
# Deploys Elata Protocol to Ethereum Sepolia testnet
# Supports both Ledger and private key deployment

set -e

echo "=================================================="
echo "  Elata Protocol - Ethereum Sepolia Deployment"
echo "=================================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
USE_LEDGER=false
USE_PRIVATE_KEY=false
LEDGER_ADDRESS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --ledger)
            USE_LEDGER=true
            shift
            ;;
        --private-key)
            USE_PRIVATE_KEY=true
            shift
            ;;
        --ledger-address)
            LEDGER_ADDRESS="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--ledger|--private-key] [--ledger-address ADDRESS]"
            exit 1
            ;;
    esac
done

# If neither flag specified, prompt user
if [ "$USE_LEDGER" = false ] && [ "$USE_PRIVATE_KEY" = false ]; then
    echo -e "${BLUE}Deployment Method:${NC}"
    echo "  1) Ledger (Recommended - most secure)"
    echo "  2) Private Key"
    echo ""
    read -p "Select deployment method (1 or 2): " -n 1 -r
    echo ""
    if [[ $REPLY == "1" ]]; then
        USE_LEDGER=true
    elif [[ $REPLY == "2" ]]; then
        USE_PRIVATE_KEY=true
    else
        echo -e "${RED}Invalid selection${NC}"
        exit 1
    fi
fi

# Load .env.sepolia if it exists
if [ -f .env.sepolia ]; then
    echo -e "${GREEN}Loading .env.sepolia${NC}"
    set -a  # Mark variables for export
    source .env.sepolia
    set +a  # Unmark
fi

# Resolve network/explorer variables (prefer Ethereum Sepolia names; keep Base fallback for compatibility)
RPC_URL="${SEPOLIA_RPC_URL:-$BASE_SEPOLIA_RPC_URL}"
EXPLORER_API_KEY="${ETHERSCAN_API_KEY:-$BASESCAN_API_KEY}"

# Check required environment variables
if [ -z "$RPC_URL" ]; then
    echo -e "${RED}Error: SEPOLIA_RPC_URL not set${NC}"
    echo "Please set SEPOLIA_RPC_URL in .env.sepolia or export it"
    exit 1
fi

if [ -z "$ADMIN_MSIG" ]; then
    echo -e "${YELLOW}Warning: ADMIN_MSIG not set, using deployer address${NC}"
fi

if [ -z "$INITIAL_TREASURY" ]; then
    echo -e "${YELLOW}Warning: INITIAL_TREASURY not set, using ADMIN_MSIG${NC}"
fi

# Deployment method specific setup
if [ "$USE_LEDGER" = true ]; then
    echo -e "${BLUE}=== Ledger Deployment ===${NC}"
    echo ""
    echo "Prerequisites:"
    echo "  1. Connect your Ledger device"
    echo "  2. Open the Ethereum app"
    echo "  3. Enable 'Blind signing' in app settings"
    echo "  4. Ensure Ledger address has Sepolia ETH"
    echo ""
    
    # Prompt for Ledger address if not provided
    if [ -z "$LEDGER_ADDRESS" ]; then
        read -p "Enter your Ledger address (0x...): " LEDGER_ADDRESS
        if [[ ! $LEDGER_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo -e "${RED}Error: Invalid Ethereum address${NC}"
            exit 1
        fi
    fi
    
    echo ""
    echo -e "${GREEN}Using Ledger address: $LEDGER_ADDRESS${NC}"
    echo ""
    read -p "Is this correct? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 0
    fi
    
    DEPLOY_FLAGS="--ledger --sender $LEDGER_ADDRESS"
    
elif [ "$USE_PRIVATE_KEY" = true ]; then
    echo -e "${BLUE}=== Private Key Deployment ===${NC}"
    
    if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
        echo -e "${RED}Error: DEPLOYER_PRIVATE_KEY not set${NC}"
        echo "Please set it in .env.sepolia or export it"
        exit 1
    fi
    
    DEPLOY_FLAGS="--private-key $DEPLOYER_PRIVATE_KEY"
    echo -e "${YELLOW}Warning: Using private key deployment${NC}"
fi

echo ""
echo "Deployment Configuration:"
echo "  Network: Ethereum Sepolia (11155111)"
echo "  RPC URL: $RPC_URL"
echo "  Deployment Method: $([ "$USE_LEDGER" = true ] && echo "Ledger" || echo "Private Key")"
if [ "$USE_LEDGER" = true ]; then
    echo "  Deployer: $LEDGER_ADDRESS"
fi
echo "  Admin Multisig: ${ADMIN_MSIG:-"Using deployer"}"
echo "  Treasury: ${INITIAL_TREASURY:-"Using admin"}"
echo "  Router: from script/config/NetworkConfig.sol"
echo ""

# Confirm deployment
read -p "Continue with deployment? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "Starting deployment..."
if [ "$USE_LEDGER" = true ]; then
    echo -e "${YELLOW}Please approve transactions on your Ledger device${NC}"
fi
echo ""

# Tag this deployment so Deploy.sol writes a uniquely-named artifact.
# This prevents fork simulations from overwriting the file the appstore ingests.
if [ -z "$ELATA_DEPLOYMENT_TAG" ]; then
    # Best-effort: include a short git sha if available.
    GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
    ELATA_DEPLOYMENT_TAG="$(date +%Y%m%d-%H%M)-$GIT_SHA"
    export ELATA_DEPLOYMENT_TAG
fi
echo "  Deployment tag: $ELATA_DEPLOYMENT_TAG"
echo ""

# Deploy contracts
if [ -n "$EXPLORER_API_KEY" ]; then
    echo "Deploying with contract verification..."
    forge script script/Deploy.sol:Deploy \
        --rpc-url "$RPC_URL" \
        $DEPLOY_FLAGS \
        --broadcast \
        --verify \
        --etherscan-api-key "$EXPLORER_API_KEY" \
        -vvv
else
    echo -e "${YELLOW}Warning: ETHERSCAN_API_KEY not set, deploying without verification${NC}"
    forge script script/Deploy.sol:Deploy \
        --rpc-url "$RPC_URL" \
        $DEPLOY_FLAGS \
        --broadcast \
        -vvv
fi

echo ""
echo -e "${GREEN}=================================================="
echo "  Deployment Complete!"
echo "==================================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Check deployments/sepolia-deployment.json for addresses"
echo "  2. Verify all contracts on Etherscan (Sepolia)"
echo "  3. Run verification script: bash scripts/verify-sepolia.sh"
echo "  4. Update Vercel environment variables with contract addresses"
echo ""
if [ "$USE_PRIVATE_KEY" = true ]; then
    echo -e "${YELLOW}Security Reminder: Remove DEPLOYER_PRIVATE_KEY from .env.sepolia${NC}"
    echo ""
fi

