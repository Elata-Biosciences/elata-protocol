#!/bin/bash
# Base Mainnet Deployment Script
# Deploys Elata Protocol to Base Mainnet
# Ledger-first approach with additional safety checks

set -e

echo "=================================================="
echo "  Elata Protocol - Base Mainnet Deployment"
echo "  ⚠️  MAINNET - REAL FUNDS AT RISK ⚠️"
echo "=================================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
USE_LEDGER=true  # Default to Ledger for mainnet
USE_PRIVATE_KEY=false
LEDGER_ADDRESS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --ledger)
            USE_LEDGER=true
            shift
            ;;
        --private-key)
            echo -e "${YELLOW}⚠️  Private key deployment on mainnet not recommended${NC}"
            read -p "Are you absolutely sure? (type 'yes' to continue): " -r
            if [[ $REPLY != "yes" ]]; then
                echo "Deployment cancelled"
                exit 0
            fi
            USE_PRIVATE_KEY=true
            USE_LEDGER=false
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

# Load .env.mainnet if it exists
if [ -f .env.mainnet ]; then
    echo -e "${GREEN}Loading .env.mainnet${NC}"
    source .env.mainnet
fi

# Check required environment variables
if [ -z "$BASE_RPC_URL" ]; then
    echo -e "${RED}Error: BASE_RPC_URL not set${NC}"
    echo "Please set it in .env.mainnet or export it"
    exit 1
fi

if [ -z "$ADMIN_MSIG" ]; then
    echo -e "${RED}Error: ADMIN_MSIG must be set for mainnet deployment${NC}"
    exit 1
fi

if [ -z "$INITIAL_TREASURY" ]; then
    echo -e "${YELLOW}Warning: INITIAL_TREASURY not set, using ADMIN_MSIG${NC}"
    INITIAL_TREASURY=$ADMIN_MSIG
fi

# Deployment method specific setup
if [ "$USE_LEDGER" = true ]; then
    echo -e "${BLUE}=== Ledger Deployment (Recommended) ===${NC}"
    echo ""
    echo "Prerequisites:"
    echo "  1. Connect your Ledger device"
    echo "  2. Open the Ethereum app"
    echo "  3. Enable 'Blind signing' in app settings"
    echo "  4. Ensure Ledger address has sufficient ETH (~0.1 ETH recommended)"
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
    echo -e "${RED}=== Private Key Deployment ===${NC}"
    
    if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
        echo -e "${RED}Error: DEPLOYER_PRIVATE_KEY not set${NC}"
        echo "Please set it in .env.mainnet or export it"
        exit 1
    fi
    
    DEPLOY_FLAGS="--private-key $DEPLOYER_PRIVATE_KEY"
fi

echo ""
echo -e "${RED}⚠️  MAINNET DEPLOYMENT CONFIGURATION ⚠️${NC}"
echo "=================================================="
echo "  Network: Base Mainnet (8453)"
echo "  RPC URL: $BASE_RPC_URL"
echo "  Deployment Method: $([ "$USE_LEDGER" = true ] && echo "Ledger" || echo "Private Key")"
if [ "$USE_LEDGER" = true ]; then
    echo "  Deployer: $LEDGER_ADDRESS"
fi
echo "  Admin Multisig: $ADMIN_MSIG"
echo "  Treasury: $INITIAL_TREASURY"
echo "  Initial Mint: 10,000,000 ELTA → Treasury"
echo "  Router: ${UNISWAP_V2_ROUTER:-"Will deploy mock router"}"
echo "=================================================="
echo ""

# Safety checks
echo -e "${YELLOW}Safety Checks:${NC}"
echo "  ✓ Deploying to Base Mainnet (Chain ID: 8453)"
echo "  ✓ Admin Multisig configured: $ADMIN_MSIG"
echo "  ✓ Treasury configured: $INITIAL_TREASURY"
echo "  ✓ 10M ELTA will be minted to treasury"
echo ""

# Multiple confirmations for mainnet
echo -e "${RED}⚠️  THIS IS A MAINNET DEPLOYMENT ⚠️${NC}"
echo "Real funds will be used. Contracts are immutable after deployment."
echo ""
read -p "Type 'DEPLOY' to continue: " -r
if [[ $REPLY != "DEPLOY" ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
read -p "Final confirmation - Deploy to MAINNET? (yes/no): " -r
if [[ $REPLY != "yes" ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "Starting mainnet deployment..."
if [ "$USE_LEDGER" = true ]; then
    echo -e "${YELLOW}Please approve transactions on your Ledger device${NC}"
    echo -e "${YELLOW}Review each transaction carefully before approving${NC}"
fi
echo ""

# Deploy contracts with verification
if [ -n "$BASESCAN_API_KEY" ]; then
    echo "Deploying with contract verification..."
    forge script script/Deploy.sol:Deploy \
        --rpc-url "$BASE_RPC_URL" \
        $DEPLOY_FLAGS \
        --broadcast \
        --verify \
        --etherscan-api-key "$BASESCAN_API_KEY" \
        --slow \
        -vvv
else
    echo -e "${YELLOW}Warning: BASESCAN_API_KEY not set, deploying without verification${NC}"
    echo "You will need to verify contracts manually"
    echo ""
    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 0
    fi
    
    forge script script/Deploy.sol:Deploy \
        --rpc-url "$BASE_RPC_URL" \
        $DEPLOY_FLAGS \
        --broadcast \
        --slow \
        -vvv
fi

echo ""
echo -e "${GREEN}=================================================="
echo "  Mainnet Deployment Complete!"
echo "==================================================${NC}"
echo ""
echo -e "${YELLOW}Critical Next Steps:${NC}"
echo "  1. Check deployments/base-mainnet-deployment.json for addresses"
echo "  2. Verify ALL contracts on BaseScan"
echo "  3. Run verification script: bash scripts/verify-mainnet.sh"
echo "  4. Test contracts with small amounts first"
echo "  5. Verify multisig has admin control"
echo "  6. Verify 10M ELTA in treasury"
echo "  7. Update production environment variables"
echo "  8. Announce deployment to team"
echo ""
if [ "$USE_PRIVATE_KEY" = true ]; then
    echo -e "${RED}SECURITY: Immediately remove DEPLOYER_PRIVATE_KEY from .env.mainnet${NC}"
    echo ""
fi
echo -e "${GREEN}Save deployment addresses in a secure location!${NC}"
echo ""

