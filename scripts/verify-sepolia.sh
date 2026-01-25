#!/bin/bash
# Base Sepolia Post-Deployment Verification Script
# Verifies deployed contracts and their configuration

set -e

echo "=================================================="
echo "  Elata Protocol - Deployment Verification"
echo "=================================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment
if [ -f .env.sepolia ]; then
    source .env.sepolia
fi

# Load deployment addresses
DEPLOYMENT_FILE="deployments/base-sepolia-deployment.json"
if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo -e "${RED}Error: Deployment file not found: $DEPLOYMENT_FILE${NC}"
    echo "Please run deployment first"
    exit 1
fi

echo "Reading deployment from $DEPLOYMENT_FILE..."
echo ""

# Extract addresses using grep and sed (portable approach)
ELTA_ADDRESS=$(grep '"ELTA"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
VE_ELTA_ADDRESS=$(grep '"VeELTA"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
ELATA_XP_ADDRESS=$(grep '"ElataPoints"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
APP_FACTORY_ADDRESS=$(grep '"AppFactory"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
REWARDS_DIST_ADDRESS=$(grep '"RewardsDistributor"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')

echo "Contract Addresses:"
echo "  ELTA: $ELTA_ADDRESS"
echo "  VeELTA: $VE_ELTA_ADDRESS"
echo "  ElataPoints: $ELATA_XP_ADDRESS"
echo "  AppFactory: $APP_FACTORY_ADDRESS"
echo "  RewardsDistributor: $REWARDS_DIST_ADDRESS"
echo ""

# Check RPC URL
if [ -z "$BASE_SEPOLIA_RPC_URL" ]; then
    echo -e "${RED}Error: BASE_SEPOLIA_RPC_URL not set${NC}"
    exit 1
fi

# Define treasury and multisig
TREASURY=${INITIAL_TREASURY:-$ADMIN_MSIG}
MULTISIG=${ADMIN_MSIG}

echo "Expected Configuration:"
echo "  Multisig/Admin: $MULTISIG"
echo "  Treasury: $TREASURY"
echo ""
echo "=================================================="
echo "Running Verification Checks..."
echo "=================================================="
echo ""

# Function to check contract code
check_contract_exists() {
    local address=$1
    local name=$2
    
    echo -n "Checking $name... "
    local code=$(cast code "$address" --rpc-url "$BASE_SEPOLIA_RPC_URL")
    if [ "$code" = "0x" ]; then
        echo -e "${RED}FAILED${NC} (no code at address)"
        return 1
    else
        echo -e "${GREEN}OK${NC}"
        return 0
    fi
}

# Check all contracts exist
check_contract_exists "$ELTA_ADDRESS" "ELTA"
check_contract_exists "$VE_ELTA_ADDRESS" "VeELTA"
check_contract_exists "$ELATA_XP_ADDRESS" "ElataPoints"
check_contract_exists "$APP_FACTORY_ADDRESS" "AppFactory"
check_contract_exists "$REWARDS_DIST_ADDRESS" "RewardsDistributor"

echo ""

# Check ELTA total supply
echo -n "Checking ELTA total supply... "
TOTAL_SUPPLY=$(cast call "$ELTA_ADDRESS" "totalSupply()(uint256)" --rpc-url "$BASE_SEPOLIA_RPC_URL")
EXPECTED_SUPPLY="10000000000000000000000000" # 10M * 10^18
if [ "$TOTAL_SUPPLY" = "$EXPECTED_SUPPLY" ]; then
    echo -e "${GREEN}OK${NC} (10,000,000 ELTA)"
else
    echo -e "${YELLOW}WARNING${NC} (Expected: 10M, Got: $(cast --to-unit "$TOTAL_SUPPLY" ether))"
fi

# Check treasury balance
if [ -n "$TREASURY" ]; then
    echo -n "Checking treasury ELTA balance... "
    TREASURY_BALANCE=$(cast call "$ELTA_ADDRESS" "balanceOf(address)(uint256)" "$TREASURY" --rpc-url "$BASE_SEPOLIA_RPC_URL")
    if [ "$TREASURY_BALANCE" = "$EXPECTED_SUPPLY" ]; then
        echo -e "${GREEN}OK${NC} (10,000,000 ELTA)"
    else
        echo -e "${YELLOW}WARNING${NC} (Expected: 10M, Got: $(cast --to-unit "$TREASURY_BALANCE" ether))"
    fi
fi

# Check admin roles
if [ -n "$MULTISIG" ]; then
    echo -n "Checking multisig admin role on ELTA... "
    DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"
    HAS_ROLE=$(cast call "$ELTA_ADDRESS" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$MULTISIG" --rpc-url "$BASE_SEPOLIA_RPC_URL")
    if [ "$HAS_ROLE" = "true" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi
    
    echo -n "Checking multisig admin role on VeELTA... "
    HAS_ROLE=$(cast call "$VE_ELTA_ADDRESS" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$MULTISIG" --rpc-url "$BASE_SEPOLIA_RPC_URL")
    if [ "$HAS_ROLE" = "true" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi
    
    echo -n "Checking multisig admin role on ElataPoints... "
    HAS_ROLE=$(cast call "$ELATA_XP_ADDRESS" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$MULTISIG" --rpc-url "$BASE_SEPOLIA_RPC_URL")
    if [ "$HAS_ROLE" = "true" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi
fi

echo ""
echo "=================================================="
echo "  Verification Complete"
echo "=================================================="
echo ""
echo "Please manually verify:"
echo "  1. All contracts are verified on BaseScan"
echo "     https://sepolia.basescan.org/address/$ELTA_ADDRESS"
echo "  2. Multisig has no unexpected permissions"
echo "  3. No ELTA tokens in deployer wallet"
echo ""

