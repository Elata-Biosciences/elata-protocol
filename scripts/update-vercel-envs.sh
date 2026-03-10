#!/bin/bash
# Update Vercel Environment Variables with Ethereum Sepolia contract addresses.
# This script reads deployment artifacts and prints ready-to-run Vercel env commands.

set -e

echo "=================================================="
echo "  Vercel Environment Variable Generator (Sepolia)"
echo "=================================================="
echo ""

# Load deployment addresses
DEPLOYMENT_FILE="${1:-deployments/sepolia-deployment.json}"
if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "Error: Deployment file not found: $DEPLOYMENT_FILE"
    echo "Please run deployment first"
    exit 1
fi

echo "Reading deployment from $DEPLOYMENT_FILE..."
echo ""

# Extract addresses
ELTA_ADDRESS=$(rg '"ELTA"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
VE_ELTA_ADDRESS=$(rg '"VeELTA"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
ELATA_XP_ADDRESS=$(rg '"ElataPoints"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
APP_FACTORY_ADDRESS=$(rg '"AppFactory"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
APP_REGISTRY_ADDRESS=$(rg '"AppRegistry"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
FEE_COLLECTOR_ADDRESS=$(rg '"FeeCollector"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
FEE_SWAPPER_ADDRESS=$(rg '"FeeSwapper"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
CONTRIBUTOR_SPLIT_FACTORY_ADDRESS=$(rg '"ContributorSplitFactory"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
PROTOCOL_CONFIG_ADDRESS=$(rg '"ProtocolConfig"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
ELATA_GOVERNOR_ADDRESS=$(rg '"ElataGovernor"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
ELATA_TIMELOCK_ADDRESS=$(rg '"ElataTimelock"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')

echo "=================================================="
echo "  Copy these commands to update Vercel env vars"
echo "=================================================="
echo ""
echo "# Navigate to elata-appstore directory first:"
echo "cd ../elata-appstore"
echo ""
echo "# Set environment variables (scope: development, preview)"
echo ""

cat << EOF
vercel env add NEXT_PUBLIC_CHAIN_ID development preview <<< "11155111"
vercel env add NEXT_PUBLIC_RPC_SEPOLIA development preview <<< "https://ethereum-sepolia-rpc.publicnode.com"
vercel env add NEXT_PUBLIC_ELTA_ADDRESS_SEPOLIA development preview <<< "$ELTA_ADDRESS"
vercel env add NEXT_PUBLIC_APP_FACTORY_ADDRESS_SEPOLIA development preview <<< "$APP_FACTORY_ADDRESS"
vercel env add NEXT_PUBLIC_APP_REGISTRY_ADDRESS_SEPOLIA development preview <<< "$APP_REGISTRY_ADDRESS"
vercel env add NEXT_PUBLIC_FEE_COLLECTOR_ADDRESS_SEPOLIA development preview <<< "$FEE_COLLECTOR_ADDRESS"
vercel env add NEXT_PUBLIC_FEE_SWAPPER_ADDRESS_SEPOLIA development preview <<< "$FEE_SWAPPER_ADDRESS"
vercel env add NEXT_PUBLIC_CONTRIBUTOR_SPLIT_FACTORY_ADDRESS_SEPOLIA development preview <<< "$CONTRIBUTOR_SPLIT_FACTORY_ADDRESS"
vercel env add NEXT_PUBLIC_PROTOCOL_CONFIG_ADDRESS_SEPOLIA development preview <<< "$PROTOCOL_CONFIG_ADDRESS"
vercel env add NEXT_PUBLIC_VE_ELTA_ADDRESS_SEPOLIA development preview <<< "$VE_ELTA_ADDRESS"
vercel env add NEXT_PUBLIC_ELATA_GOVERNOR_ADDRESS_SEPOLIA development preview <<< "$ELATA_GOVERNOR_ADDRESS"
vercel env add NEXT_PUBLIC_ELATA_TIMELOCK_ADDRESS_SEPOLIA development preview <<< "$ELATA_TIMELOCK_ADDRESS"
vercel env add NEXT_PUBLIC_ELATA_XP_ADDRESS_SEPOLIA development preview <<< "$ELATA_XP_ADDRESS"
EOF

echo ""
echo "=================================================="
echo "  Or set via Vercel Dashboard"
echo "=================================================="
echo ""
echo "Go to: https://vercel.com/[your-team]/elata-appstore/settings/environment-variables"
echo ""
echo "Add these variables with scope 'Preview' and 'Development':"
echo ""
echo "NEXT_PUBLIC_CHAIN_ID=11155111"
echo "NEXT_PUBLIC_RPC_SEPOLIA=https://ethereum-sepolia-rpc.publicnode.com"
echo "NEXT_PUBLIC_ELTA_ADDRESS_SEPOLIA=$ELTA_ADDRESS"
echo "NEXT_PUBLIC_APP_FACTORY_ADDRESS_SEPOLIA=$APP_FACTORY_ADDRESS"
echo "NEXT_PUBLIC_APP_REGISTRY_ADDRESS_SEPOLIA=$APP_REGISTRY_ADDRESS"
echo "NEXT_PUBLIC_FEE_COLLECTOR_ADDRESS_SEPOLIA=$FEE_COLLECTOR_ADDRESS"
echo "NEXT_PUBLIC_FEE_SWAPPER_ADDRESS_SEPOLIA=$FEE_SWAPPER_ADDRESS"
echo "NEXT_PUBLIC_CONTRIBUTOR_SPLIT_FACTORY_ADDRESS_SEPOLIA=$CONTRIBUTOR_SPLIT_FACTORY_ADDRESS"
echo "NEXT_PUBLIC_PROTOCOL_CONFIG_ADDRESS_SEPOLIA=$PROTOCOL_CONFIG_ADDRESS"
echo "NEXT_PUBLIC_VE_ELTA_ADDRESS_SEPOLIA=$VE_ELTA_ADDRESS"
echo "NEXT_PUBLIC_ELATA_GOVERNOR_ADDRESS_SEPOLIA=$ELATA_GOVERNOR_ADDRESS"
echo "NEXT_PUBLIC_ELATA_TIMELOCK_ADDRESS_SEPOLIA=$ELATA_TIMELOCK_ADDRESS"
echo "NEXT_PUBLIC_ELATA_XP_ADDRESS_SEPOLIA=$ELATA_XP_ADDRESS"
echo ""
echo "Optional compatibility vars (if old Base-Sepolia keys are still used):"
echo "NEXT_PUBLIC_ELTA_ADDRESS_BASE_SEPOLIA=$ELTA_ADDRESS"
echo "NEXT_PUBLIC_APP_FACTORY_ADDRESS_BASE_SEPOLIA=$APP_FACTORY_ADDRESS"
echo "NEXT_PUBLIC_APP_REGISTRY_ADDRESS_BASE_SEPOLIA=$APP_REGISTRY_ADDRESS"
echo "NEXT_PUBLIC_FEE_COLLECTOR_ADDRESS_BASE_SEPOLIA=$FEE_COLLECTOR_ADDRESS"
echo "NEXT_PUBLIC_FEE_SWAPPER_ADDRESS_BASE_SEPOLIA=$FEE_SWAPPER_ADDRESS"
echo "NEXT_PUBLIC_CONTRIBUTOR_SPLIT_FACTORY_ADDRESS_BASE_SEPOLIA=$CONTRIBUTOR_SPLIT_FACTORY_ADDRESS"
echo "NEXT_PUBLIC_PROTOCOL_CONFIG_ADDRESS_BASE_SEPOLIA=$PROTOCOL_CONFIG_ADDRESS"
echo "NEXT_PUBLIC_VE_ELTA_ADDRESS_BASE_SEPOLIA=$VE_ELTA_ADDRESS"
echo "NEXT_PUBLIC_ELATA_GOVERNOR_ADDRESS_BASE_SEPOLIA=$ELATA_GOVERNOR_ADDRESS"
echo "NEXT_PUBLIC_ELATA_TIMELOCK_ADDRESS_BASE_SEPOLIA=$ELATA_TIMELOCK_ADDRESS"
echo "NEXT_PUBLIC_ELATA_XP_ADDRESS_BASE_SEPOLIA=$ELATA_XP_ADDRESS"
echo ""

