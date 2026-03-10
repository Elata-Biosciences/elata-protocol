#!/bin/bash
# Ethereum Sepolia Post-Deployment Verification Script
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

# Pick a deployment artifact:
# - arg1 (explicit path) wins
# - else ELATA_VERIFY_DEPLOYMENT_FILE
# - else newest tagged sepolia-*.json
# - else legacy sepolia-deployment.json
DEPLOYMENT_FILE="${1:-${ELATA_VERIFY_DEPLOYMENT_FILE:-}}"
if [ -z "$DEPLOYMENT_FILE" ]; then
    # Tagged files look like: deployments/sepolia-20260219-2359-abc123.json
    NEWEST_TAGGED=$(ls -1t deployments/sepolia-[0-9]*.json 2>/dev/null | head -n 1 || true)
    if [ -n "$NEWEST_TAGGED" ]; then
        DEPLOYMENT_FILE="$NEWEST_TAGGED"
    else
        DEPLOYMENT_FILE="deployments/sepolia-deployment.json"
    fi
fi

if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo -e "${RED}Error: Deployment file not found: $DEPLOYMENT_FILE${NC}"
    echo "Provide a path as the first argument, or set ELATA_VERIFY_DEPLOYMENT_FILE."
    exit 1
fi

echo "Reading deployment from $DEPLOYMENT_FILE..."
echo ""

extract_address() {
    local key=$1
    grep "\"$key\"" "$DEPLOYMENT_FILE" | head -n 1 | sed 's/.*: "\(0x[^"]*\)".*/\1/'
}

# Core
ELTA_ADDRESS=$(extract_address "ELTA")
VE_ELTA_ADDRESS=$(extract_address "VeELTA")
ELATA_XP_ADDRESS=$(extract_address "ElataPoints")
TIMELOCK_ADDRESS=$(extract_address "ElataTimelock")
GOVERNOR_ADDRESS=$(extract_address "ElataGovernor")
APP_FACTORY_ADDRESS=$(extract_address "AppFactory")
APP_REGISTRY_ADDRESS=$(extract_address "AppRegistry")
CONTRIBUTOR_SPLIT_FACTORY_ADDRESS=$(extract_address "ContributorSplitFactory")
APP_FEE_ROUTER_ADDRESS=$(extract_address "AppFeeRouter")

# Apps / Modules
CONTENT_721_FACTORY_ADDRESS=$(extract_address "InAppContent721Factory")
CONTENT_STORE_FACTORY_ADDRESS=$(extract_address "ContentStoreFactory")
TOURNAMENT_FACTORY_ADDRESS=$(extract_address "TournamentFactory")
PROTOCOL_CONFIG_ADDRESS=$(extract_address "ProtocolConfig")

# Fees
FEE_SWAPPER_ADDRESS=$(extract_address "FeeSwapper")
FEE_COLLECTOR_ADDRESS=$(extract_address "FeeCollector")

# Externals
USDC_ADDRESS=$(extract_address "USDC")
UNISWAP_V2_ROUTER=$(extract_address "UniswapV2Router")

echo "Contract Addresses:"
echo "  ELTA:                    $ELTA_ADDRESS"
echo "  VeELTA:                  $VE_ELTA_ADDRESS"
echo "  ElataPoints:             $ELATA_XP_ADDRESS"
echo "  ElataTimelock:           $TIMELOCK_ADDRESS"
echo "  ElataGovernor:           $GOVERNOR_ADDRESS"
echo "  AppFactory:              $APP_FACTORY_ADDRESS"
echo "  AppRegistry:             $APP_REGISTRY_ADDRESS"
echo "  ContributorSplitFactory: $CONTRIBUTOR_SPLIT_FACTORY_ADDRESS"
echo "  AppFeeRouter:            $APP_FEE_ROUTER_ADDRESS"
echo "  Content721Factory:       $CONTENT_721_FACTORY_ADDRESS"
echo "  ContentStoreFactory:     $CONTENT_STORE_FACTORY_ADDRESS"
echo "  TournamentFactory:       $TOURNAMENT_FACTORY_ADDRESS"
echo "  ProtocolConfig:          $PROTOCOL_CONFIG_ADDRESS"
echo "  FeeSwapper:              $FEE_SWAPPER_ADDRESS"
echo "  FeeCollector:            $FEE_COLLECTOR_ADDRESS"
echo "  USDC:                    $USDC_ADDRESS"
echo "  UniswapV2Router:         $UNISWAP_V2_ROUTER"
echo ""

# Resolve RPC variable (prefer Ethereum Sepolia name; keep Base fallback for compatibility)
RPC_URL="${SEPOLIA_RPC_URL:-$BASE_SEPOLIA_RPC_URL}"

# Check RPC URL
if [ -z "$RPC_URL" ]; then
    echo -e "${RED}Error: SEPOLIA_RPC_URL not set${NC}"
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

    if [[ ! "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo -e "Checking $name... ${YELLOW}SKIP${NC} (missing/invalid address: $address)"
        return 0
    fi
    
    echo -n "Checking $name... "
    local code=$(cast code "$address" --rpc-url "$RPC_URL")
    if [ "$code" = "0x" ]; then
        echo -e "${RED}FAILED${NC} (no code at address)"
        return 1
    else
        echo -e "${GREEN}OK${NC}"
        return 0
    fi
}

# Normalize cast scalar output (strip any trailing annotations like "[7.7e25]")
normalize_cast_uint() {
    echo "$1" | awk '{print $1}'
}

# Check all contracts exist
check_contract_exists "$ELTA_ADDRESS" "ELTA"
check_contract_exists "$VE_ELTA_ADDRESS" "VeELTA"
check_contract_exists "$ELATA_XP_ADDRESS" "ElataPoints"
check_contract_exists "$TIMELOCK_ADDRESS" "ElataTimelock"
check_contract_exists "$GOVERNOR_ADDRESS" "ElataGovernor"
check_contract_exists "$APP_FACTORY_ADDRESS" "AppFactory"
check_contract_exists "$APP_REGISTRY_ADDRESS" "AppRegistry"
check_contract_exists "$CONTRIBUTOR_SPLIT_FACTORY_ADDRESS" "ContributorSplitFactory"
check_contract_exists "$CONTENT_721_FACTORY_ADDRESS" "InAppContent721Factory"
check_contract_exists "$CONTENT_STORE_FACTORY_ADDRESS" "ContentStoreFactory"
check_contract_exists "$TOURNAMENT_FACTORY_ADDRESS" "TournamentFactory"
check_contract_exists "$PROTOCOL_CONFIG_ADDRESS" "ProtocolConfig"
check_contract_exists "$FEE_SWAPPER_ADDRESS" "FeeSwapper"
check_contract_exists "$FEE_COLLECTOR_ADDRESS" "FeeCollector"

echo ""

# Check ELTA total supply
echo -n "Checking ELTA total supply... "
TOTAL_SUPPLY_RAW=$(cast call "$ELTA_ADDRESS" "totalSupply()(uint256)" --rpc-url "$RPC_URL")
TOTAL_SUPPLY=$(normalize_cast_uint "$TOTAL_SUPPLY_RAW")
EXPECTED_SUPPLY="77000000000000000000000000" # 77,000,000 * 10^18
if [ "$TOTAL_SUPPLY" = "$EXPECTED_SUPPLY" ]; then
    echo -e "${GREEN}OK${NC} (77,000,000 ELTA)"
else
    echo -e "${YELLOW}WARNING${NC} (Expected: 77M, Got: $(cast --to-unit "$TOTAL_SUPPLY" ether))"
fi

# Check treasury balance
if [ -n "$TREASURY" ]; then
    echo -n "Checking treasury ELTA balance... "
    TREASURY_BALANCE_RAW=$(cast call "$ELTA_ADDRESS" "balanceOf(address)(uint256)" "$TREASURY" --rpc-url "$RPC_URL")
    TREASURY_BALANCE=$(normalize_cast_uint "$TREASURY_BALANCE_RAW")
    if [ "$TREASURY_BALANCE" = "$EXPECTED_SUPPLY" ]; then
        echo -e "${GREEN}OK${NC} (77,000,000 ELTA)"
    else
        echo -e "${YELLOW}WARNING${NC} (Expected: 77M, Got: $(cast --to-unit "$TREASURY_BALANCE" ether))"
    fi
fi

# FeeSwapper config checks
if [[ "$FEE_SWAPPER_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo ""
    echo "FeeSwapper Configuration:"

    echo -n "  governance == timelock... "
    GOV=$(cast call "$FEE_SWAPPER_ADDRESS" "governance()(address)" --rpc-url "$RPC_URL")
    if [ "$(echo "$GOV" | tr '[:upper:]' '[:lower:]')" = "$(echo "$TIMELOCK_ADDRESS" | tr '[:upper:]' '[:lower:]')" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC} (got: $GOV)"
    fi

    echo -n "  defaultTreasuryTakeBps == 2000... "
    TAKE=$(cast call "$FEE_SWAPPER_ADDRESS" "defaultTreasuryTakeBps()(uint16)" --rpc-url "$RPC_URL")
    if [ "$TAKE" = "2000" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC} (got: $TAKE)"
    fi

    if [[ "$UNISWAP_V2_ROUTER" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo -n "  router allowlisted... "
        ALLOWED=$(cast call "$FEE_SWAPPER_ADDRESS" "isRouterAllowed(address)(bool)" "$UNISWAP_V2_ROUTER" --rpc-url "$RPC_URL")
        if [ "$ALLOWED" = "true" ]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC} (isRouterAllowed=false)"
        fi
    fi
fi

# ContentStoreFactory wiring check
if [[ "$CONTENT_STORE_FACTORY_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]] && [[ "$FEE_SWAPPER_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo -n "Checking ContentStoreFactory.feeSwapper == FeeSwapper... "
    CSF_FS=$(cast call "$CONTENT_STORE_FACTORY_ADDRESS" "feeSwapper()(address)" --rpc-url "$RPC_URL")
    if [ "$(echo "$CSF_FS" | tr '[:upper:]' '[:lower:]')" = "$(echo "$FEE_SWAPPER_ADDRESS" | tr '[:upper:]' '[:lower:]')" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC} (got: $CSF_FS)"
    fi
fi

# Optional: admin roles (these contracts use AccessControl)
if [ -n "$MULTISIG" ]; then
    DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"

    if [[ "$VE_ELTA_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo -n "Checking multisig admin role on VeELTA... "
        HAS_ROLE=$(cast call "$VE_ELTA_ADDRESS" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$MULTISIG" --rpc-url "$RPC_URL")
        if [ "$HAS_ROLE" = "true" ]; then echo -e "${GREEN}OK${NC}"; else echo -e "${RED}FAILED${NC}"; fi
    fi

    if [[ "$ELATA_XP_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo -n "Checking multisig admin role on ElataPoints... "
        HAS_ROLE=$(cast call "$ELATA_XP_ADDRESS" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$MULTISIG" --rpc-url "$RPC_URL")
        if [ "$HAS_ROLE" = "true" ]; then echo -e "${GREEN}OK${NC}"; else echo -e "${RED}FAILED${NC}"; fi
    fi
fi

echo ""
echo "=================================================="
echo "  Verification Complete"
echo "=================================================="
echo ""
echo "Please manually verify:"
echo "  1. All contracts are verified on Etherscan (Sepolia)"
echo "     https://sepolia.etherscan.io/address/$ELTA_ADDRESS"
echo "  2. Multisig has no unexpected permissions"
echo "  3. No ELTA tokens in deployer wallet"
echo ""

