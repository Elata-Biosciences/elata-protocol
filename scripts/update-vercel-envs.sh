#!/bin/bash
# Update Vercel Environment Variables with Base Sepolia Contract Addresses
# This script reads deployment addresses and provides commands to set Vercel env vars

set -e

echo "=================================================="
echo "  Vercel Environment Variable Generator"
echo "=================================================="
echo ""

# Load deployment addresses
DEPLOYMENT_FILE="deployments/base-sepolia-deployment.json"
if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "Error: Deployment file not found: $DEPLOYMENT_FILE"
    echo "Please run deployment first"
    exit 1
fi

echo "Reading deployment from $DEPLOYMENT_FILE..."
echo ""

# Extract addresses
ELTA_ADDRESS=$(grep '"ELTA"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
VE_ELTA_ADDRESS=$(grep '"VeELTA"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
ELATA_XP_ADDRESS=$(grep '"ElataXP"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
APP_FACTORY_ADDRESS=$(grep '"AppFactory"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
APP_MODULE_FACTORY_ADDRESS=$(grep '"AppModuleFactory"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
REWARDS_DIST_ADDRESS=$(grep '"RewardsDistributor"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')
APP_REWARDS_DIST_ADDRESS=$(grep '"AppRewardsDistributor"' "$DEPLOYMENT_FILE" | sed 's/.*: "\(0x[^"]*\)".*/\1/')

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
vercel env add NEXT_PUBLIC_ELTA_ADDRESS_BASE_SEPOLIA development preview <<< "$ELTA_ADDRESS"
vercel env add NEXT_PUBLIC_APP_FACTORY_ADDRESS_BASE_SEPOLIA development preview <<< "$APP_FACTORY_ADDRESS"
vercel env add NEXT_PUBLIC_APP_MODULE_FACTORY_ADDRESS_BASE_SEPOLIA development preview <<< "$APP_MODULE_FACTORY_ADDRESS"
vercel env add NEXT_PUBLIC_REWARDS_DISTRIBUTOR_ADDRESS_BASE_SEPOLIA development preview <<< "$REWARDS_DIST_ADDRESS"
vercel env add NEXT_PUBLIC_APP_REWARDS_DISTRIBUTOR_ADDRESS_BASE_SEPOLIA development preview <<< "$APP_REWARDS_DIST_ADDRESS"
vercel env add NEXT_PUBLIC_VE_ELTA_ADDRESS_BASE_SEPOLIA development preview <<< "$VE_ELTA_ADDRESS"
vercel env add NEXT_PUBLIC_ELATA_XP_ADDRESS_BASE_SEPOLIA development preview <<< "$ELATA_XP_ADDRESS"
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
echo "NEXT_PUBLIC_ELTA_ADDRESS_BASE_SEPOLIA=$ELTA_ADDRESS"
echo "NEXT_PUBLIC_APP_FACTORY_ADDRESS_BASE_SEPOLIA=$APP_FACTORY_ADDRESS"
echo "NEXT_PUBLIC_APP_MODULE_FACTORY_ADDRESS_BASE_SEPOLIA=$APP_MODULE_FACTORY_ADDRESS"
echo "NEXT_PUBLIC_REWARDS_DISTRIBUTOR_ADDRESS_BASE_SEPOLIA=$REWARDS_DIST_ADDRESS"
echo "NEXT_PUBLIC_APP_REWARDS_DISTRIBUTOR_ADDRESS_BASE_SEPOLIA=$APP_REWARDS_DIST_ADDRESS"
echo "NEXT_PUBLIC_VE_ELTA_ADDRESS_BASE_SEPOLIA=$VE_ELTA_ADDRESS"
echo "NEXT_PUBLIC_ELATA_XP_ADDRESS_BASE_SEPOLIA=$ELATA_XP_ADDRESS"
echo ""
echo "Also add these if not already set:"
echo "NEXT_PUBLIC_ENVIRONMENT=dev"
echo "NEXT_PUBLIC_CHAIN_ID=84532"
echo "NEXT_PUBLIC_RPC_BASE_SEPOLIA=https://sepolia.base.org"
echo ""

