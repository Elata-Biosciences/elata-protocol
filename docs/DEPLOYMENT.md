# Deployment Guide

This guide covers deploying the Elata Protocol smart contracts to various networks.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Network Configuration](#network-configuration)
- [Deployment Process](#deployment-process)
- [Post-Deployment](#post-deployment)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

- [Foundry](https://getfoundry.sh/) (latest version)
- [Git](https://git-scm.com/)
- Access to RPC endpoints
- API keys for contract verification

### Required Accounts

- Deployer wallet with sufficient ETH for gas
- Admin multisig wallet (Gnosis Safe recommended)
- Treasury wallet for initial token distribution

## Environment Setup

### 1. Clone and Setup Repository

```bash
git clone https://github.com/Elata-Biosciences/elata-protocol
cd elata-protocol
forge install
forge build
```

### 2. Configure Environment Variables

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` with your values:

```bash
# Required for deployment
ADMIN_MSIG=0x...                    # Your Gnosis Safe address
INITIAL_TREASURY=0x...              # Initial token recipient
SEPOLIA_RPC_URL=https://...         # Testnet RPC
MAINNET_RPC_URL=https://...         # Mainnet RPC (if deploying to mainnet)
ETHERSCAN_API_KEY=...               # For contract verification
```

### 3. Fund Deployer Wallet

Ensure your deployer wallet has sufficient funds:

| Network | Estimated Gas Cost |
|---------|-------------------|
| Ethereum Mainnet | ~0.1 ETH |
| Sepolia Testnet | ~0.01 ETH (free from faucet) |
| Base Mainnet | ~0.001 ETH |
| Base Sepolia | ~0.0001 ETH (free from faucet) |

## Network Configuration

### Supported Networks

| Network | Chain ID | RPC URL | Explorer |
|---------|----------|---------|----------|
| Ethereum Mainnet | 1 | Various providers | etherscan.io |
| Sepolia Testnet | 11155111 | Various providers | sepolia.etherscan.io |
| Base Mainnet | 8453 | https://mainnet.base.org | basescan.org |
| Base Sepolia | 84532 | https://sepolia.base.org | sepolia.basescan.org |

### Gas Price Recommendations

```bash
# Check current gas prices
cast gas-price --rpc-url $MAINNET_RPC_URL

# Set gas price in foundry.toml if needed
[profile.mainnet]
gas_price = 20_000_000_000  # 20 gwei
```

## Deployment Process

### Step 1: Validate Configuration

```bash
# Test compilation
forge build

# Run all tests
forge test

# Simulate deployment (dry run)
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL
```

### Step 2: Deploy to Testnet

```bash
# Deploy to Sepolia testnet
forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Step 3: Verify Testnet Deployment

```bash
# Check deployment addresses
cat broadcast/Deploy.s.sol/11155111/run-latest.json | jq '.transactions[].contractAddress'

# Verify contracts are working
cast call <ELTA_ADDRESS> "totalSupply()" --rpc-url $SEPOLIA_RPC_URL
cast call <ELTA_ADDRESS> "hasRole(bytes32,address)" 0x0000000000000000000000000000000000000000000000000000000000000000 $ADMIN_MSIG --rpc-url $SEPOLIA_RPC_URL
```

### Step 4: Deploy to Mainnet (Production)

⚠️ **CRITICAL**: Only deploy to mainnet after thorough testnet testing!

```bash
# Final checks
forge test
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL  # Dry run

# Deploy to mainnet
forge script script/Deploy.s.sol \
  --rpc-url $MAINNET_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --slow  # Add delay between transactions
```

## Post-Deployment

### Contract Addresses

After deployment, record the contract addresses:

```bash
# Save addresses to a file
echo "ELTA_ADDRESS=$(cat broadcast/Deploy.s.sol/1/run-latest.json | jq -r '.transactions[] | select(.contractName == "ELTA") | .contractAddress')" >> deployed-addresses.env
echo "VEELTA_ADDRESS=$(cat broadcast/Deploy.s.sol/1/run-latest.json | jq -r '.transactions[] | select(.contractName == "VeELTA") | .contractAddress')" >> deployed-addresses.env
echo "XP_ADDRESS=$(cat broadcast/Deploy.s.sol/1/run-latest.json | jq -r '.transactions[] | select(.contractName == "ElataXP") | .contractAddress')" >> deployed-addresses.env
echo "LOTPOOL_ADDRESS=$(cat broadcast/Deploy.s.sol/1/run-latest.json | jq -r '.transactions[] | select(.contractName == "LotPool") | .contractAddress')" >> deployed-addresses.env
```

### Initial Configuration

1. **Transfer Admin Roles** (if needed):
   ```bash
   # Transfer DEFAULT_ADMIN_ROLE to multisig
   cast send $ELTA_ADDRESS "grantRole(bytes32,address)" 0x0000000000000000000000000000000000000000000000000000000000000000 $NEW_ADMIN --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY
   ```

2. **Configure XP Minters**:
   ```bash
   # Grant XP_MINTER_ROLE to app contracts
   cast send $XP_ADDRESS "grantRole(bytes32,address)" $(cast call $XP_ADDRESS "XP_MINTER_ROLE()") $APP_CONTRACT --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY
   ```

3. **Setup Initial LotPool Funding**:
   ```bash
   # Approve ELTA for LotPool
   cast send $ELTA_ADDRESS "approve(address,uint256)" $LOTPOOL_ADDRESS 100000000000000000000000 --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY
   
   # Fund LotPool
   cast send $LOTPOOL_ADDRESS "fund(uint256)" 100000000000000000000000 --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY
   ```

## Verification

### Contract Verification

Contracts should auto-verify during deployment. If verification fails:

```bash
# Manual verification
forge verify-contract \
  --chain-id 1 \
  --num-of-optimizations 500 \
  --constructor-args $(cast abi-encode "constructor(string,string,address,address,uint256,uint256)" "ELTA" "ELTA" $ADMIN_MSIG $INITIAL_TREASURY 10000000000000000000000000 77000000000000000000000000) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  $ELTA_ADDRESS \
  src/token/ELTA.sol:ELTA
```

### Functionality Testing

Test core functionality on deployed contracts:

```bash
# Test ELTA token
cast call $ELTA_ADDRESS "name()" --rpc-url $MAINNET_RPC_URL
cast call $ELTA_ADDRESS "symbol()" --rpc-url $MAINNET_RPC_URL
cast call $ELTA_ADDRESS "totalSupply()" --rpc-url $MAINNET_RPC_URL
cast call $ELTA_ADDRESS "MAX_SUPPLY()" --rpc-url $MAINNET_RPC_URL

# Test VeELTA
cast call $VEELTA_ADDRESS "MIN_LOCK()" --rpc-url $MAINNET_RPC_URL
cast call $VEELTA_ADDRESS "MAX_LOCK()" --rpc-url $MAINNET_RPC_URL

# Test XP
cast call $XP_ADDRESS "name()" --rpc-url $MAINNET_RPC_URL
cast call $XP_ADDRESS "symbol()" --rpc-url $MAINNET_RPC_URL

# Test LotPool
cast call $LOTPOOL_ADDRESS "currentRoundId()" --rpc-url $MAINNET_RPC_URL
```

## Troubleshooting

### Common Issues

#### 1. Insufficient Gas

**Error**: `Transaction failed: out of gas`

**Solution**:
```bash
# Increase gas limit in foundry.toml
[profile.default]
gas_limit = 30000000

# Or specify gas limit in command
forge script script/Deploy.s.sol --gas-limit 30000000
```

#### 2. Nonce Issues

**Error**: `Transaction failed: nonce too low/high`

**Solution**:
```bash
# Check current nonce
cast nonce $DEPLOYER_ADDRESS --rpc-url $MAINNET_RPC_URL

# Reset nonce if needed (use with caution)
# Wait for pending transactions or cancel them
```

#### 3. Verification Failures

**Error**: `Contract verification failed`

**Solution**:
```bash
# Check compiler version matches
forge --version

# Ensure optimization settings match
# Check constructor arguments are correct
# Try manual verification with exact parameters
```

#### 4. Role Assignment Issues

**Error**: `AccessControlUnauthorizedAccount`

**Solution**:
```bash
# Verify admin address is correct
cast call $ELTA_ADDRESS "hasRole(bytes32,address)" 0x0000000000000000000000000000000000000000000000000000000000000000 $ADMIN_MSIG

# Check if you're using the right private key
cast wallet address --private-key $PRIVATE_KEY
```

### Emergency Procedures

If deployment fails partially:

1. **Document** all successful contract deployments
2. **Pause** any problematic contracts if possible
3. **Redeploy** failed contracts with updated parameters
4. **Update** integration points with new addresses

### Gas Optimization Tips

- Deploy during low network congestion
- Use appropriate gas price (not too low, not too high)
- Consider using CREATE2 for deterministic addresses
- Batch related transactions when possible

---

*Always test deployments thoroughly on testnets before mainnet deployment. Keep detailed records of all deployment transactions and addresses.*
