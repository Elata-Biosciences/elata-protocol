#!/bin/bash

echo "🛡️ Elata Protocol Security Check"
echo "================================"

echo "📋 Running security tests..."
forge test --match-contract CoreSecurityVerification

echo "📊 Checking contract sizes..."
forge build --sizes | grep -E "(ELTA|VeELTA|ElataXP|LotPool|RewardsDistributor)"

echo "⛽ Gas cost analysis..."
forge test --gas-report | grep -A 5 "Deployment Cost"

echo "✅ Security check complete!"
