# Deployment Guide

This guide covers deploying Elata Protocol contracts to testnets and mainnet.

## Overview

The deployment process:

1. Configure environment variables
2. Fund the deployer wallet
3. Run the deployment script
4. Verify contracts on block explorer
5. Transfer admin roles to multisig
6. Update frontend configuration

## Prerequisites

- Foundry installed (`forge`, `cast`)
- Node.js v18+
- Deployer wallet with sufficient ETH
- Admin multisig address (Gnosis Safe recommended)
- RPC endpoint (Alchemy, Infura, or public)
- Block explorer API key

## Supported Networks

| Network | Chain ID | Cost Estimate | Notes |
|---------|----------|---------------|-------|
| Ethereum Mainnet | 1 | ~$260 at 20 gwei | Production |
| Base Mainnet | 8453 | ~$2-5 | L2, lower costs |
| Sepolia | 11155111 | Free | Ethereum testnet |
| Base Sepolia | 84532 | Free | Base testnet |

## Testnet Deployment (Sepolia)

### Step 1: Create Environment File

Create `.env.sepolia` in the repository root:

```bash
# Network
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_KEY

# Deployer
DEPLOYER_PRIVATE_KEY=0xYOUR_PRIVATE_KEY

# Protocol Configuration
ADMIN_MSIG=0xYourGnosisSafeAddress
INITIAL_TREASURY=0xYourTreasuryAddress

# Optional: Leave empty to deploy mock router
UNISWAP_V2_ROUTER=
```

Never commit this file. It's already in `.gitignore`.

### Step 2: Fund Deployer

Get Sepolia ETH from a faucet:
- https://sepoliafaucet.com/
- https://www.alchemy.com/faucets/ethereum-sepolia

You'll need about 0.5 ETH for deployment and verification.

### Step 3: Deploy

```bash
npm run deploy:sepolia
```

Or with the script directly:

```bash
bash scripts/deploy-sepolia.sh --private-key
```

The script will:
- Compile contracts
- Deploy in the correct order
- Set up role permissions
- Mint initial ELTA to treasury
- Output addresses to `deployments/sepolia.json`

### Step 4: Verify Contracts

Verification usually happens automatically during deployment. If it fails:

```bash
forge verify-contract <ADDRESS> src/token/ELTA.sol:ELTA \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(string,string,address,address,uint256,uint256)" "ELTA" "ELTA" "0x..." "0x..." 10000000000000000000000000 77000000000000000000000000)
```

### Step 5: Verify Deployment

Run the verification script:

```bash
bash scripts/verify-sepolia.sh
```

Or manually check:

```bash
# Token deployed correctly
cast call $ELTA_ADDRESS "name()" --rpc-url $SEPOLIA_RPC_URL
cast call $ELTA_ADDRESS "totalSupply()" --rpc-url $SEPOLIA_RPC_URL

# Admin has correct roles
cast call $ELTA_ADDRESS "hasRole(bytes32,address)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $ADMIN_MSIG --rpc-url $SEPOLIA_RPC_URL

# Contracts are linked correctly
cast call $VEELTA_ADDRESS "ELTA()" --rpc-url $SEPOLIA_RPC_URL
```

## Base Sepolia Deployment

Base Sepolia deployment works the same way, with a few differences.

### Environment File

Create `.env.base-sepolia`:

```bash
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=YOUR_BASESCAN_KEY
DEPLOYER_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
ADMIN_MSIG=0xYourGnosisSafeAddress
INITIAL_TREASURY=0xYourTreasuryAddress
UNISWAP_V2_ROUTER=
```

### Get Test ETH

Fund from the Base faucet: https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet

### Deploy

```bash
npm run deploy:base-sepolia
```

### Contract Size Note

AppModuleFactory exceeds the 24KB EIP-170 limit on L1 Ethereum. On Base (and other L2s), this limit doesn't apply, so all contracts deploy successfully. If deploying to Ethereum mainnet, you may need to optimize or split this contract.

## Ledger Deployment

For production deployments, use a hardware wallet instead of a private key.

### Setup

1. Connect Ledger device
2. Open Ethereum app
3. Enable "Blind signing" in Settings

### Deploy

```bash
bash scripts/deploy-sepolia.sh --ledger

# Or with specific address
bash scripts/deploy-sepolia.sh --ledger --ledger-address 0xYourLedgerAddress
```

You'll approve each transaction on the device.

## Post-Deployment Checklist

After deploying, verify:

- [ ] All contracts deployed and verified on block explorer
- [ ] Initial ELTA supply minted to treasury
- [ ] Admin roles assigned to multisig
- [ ] Deployer wallet has no remaining admin roles
- [ ] Timelock configured with correct delays
- [ ] Governor has proposer/executor roles on Timelock
- [ ] No ELTA stuck in deployer wallet

### Configure Timelock Permissions

The Governor needs roles on the Timelock to execute proposals:

```bash
# Grant PROPOSER_ROLE to Governor
cast send $TIMELOCK_ADDRESS \
  "grantRole(bytes32,address)" \
  0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1 \
  $GOVERNOR_ADDRESS \
  --rpc-url $RPC_URL

# Grant EXECUTOR_ROLE to Governor
cast send $TIMELOCK_ADDRESS \
  "grantRole(bytes32,address)" \
  0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783 \
  $GOVERNOR_ADDRESS \
  --rpc-url $RPC_URL
```

These should be executed from the multisig via Gnosis Safe.

## Updating Frontend

After deployment, update the App Store environment variables.

For Vercel (production):
1. Go to elata-appstore project → Settings → Environment Variables
2. Add variables for the new network:

```
NEXT_PUBLIC_ELTA_ADDRESS_BASE_SEPOLIA=0x...
NEXT_PUBLIC_APP_FACTORY_ADDRESS_BASE_SEPOLIA=0x...
NEXT_PUBLIC_VE_ELTA_ADDRESS_BASE_SEPOLIA=0x...
NEXT_PUBLIC_ELATA_XP_ADDRESS_BASE_SEPOLIA=0x...
NEXT_PUBLIC_REWARDS_DISTRIBUTOR_ADDRESS_BASE_SEPOLIA=0x...
```

For local development, the deploy script generates these automatically.

## Mainnet Deployment

Mainnet deployment follows the same process with additional precautions:

1. **Audit first** — Get an external security audit before mainnet
2. **Test thoroughly** — Run full E2E tests on testnet
3. **Use multisig** — Deploy from a secure multisig, not a hot wallet
4. **Double-check parameters** — Review all constructor arguments
5. **Monitor after deployment** — Watch for unusual activity

### Cost Estimation

At 20 gwei on Ethereum mainnet:

| Contract | Gas | Cost |
|----------|-----|------|
| ELTA | 2.3M | ~$46 |
| VeELTA | 3.0M | ~$60 |
| ElataXP | 1.8M | ~$36 |
| AppFactory | 2.9M | ~$58 |
| Other contracts | ~4M | ~$80 |
| **Total** | ~14M | ~$280 |

On Base mainnet, expect costs 50-100x lower.

## Troubleshooting

### Deployment fails with "insufficient funds"

Fund the deployer wallet with more ETH. Mainnet deployments need ~0.5 ETH buffer.

### Verification fails

Wait 30 seconds after deployment, then retry. If it still fails:
- Check API key is valid
- Verify constructor arguments match exactly
- Try manual verification on the block explorer

### Transaction stuck

If a transaction is pending too long:

```bash
# Send a replacement with higher gas
cast send --nonce <STUCK_NONCE> --gas-price <HIGHER_PRICE> ...
```

### "Contract too large" error

This happens on L1 for AppModuleFactory. Options:
- Deploy on L2 instead (Base, Arbitrum, Optimism)
- Increase optimizer runs (makes deployment cheaper but execution more expensive)
- Split into smaller contracts

## Security Notes

1. **Never commit private keys** — Use `.env` files that are gitignored
2. **Use dedicated deployer wallet** — Don't use your main wallet
3. **Transfer admin immediately** — Move admin roles to multisig right after deployment
4. **Delete private key from env** — Remove `DEPLOYER_PRIVATE_KEY` after deployment
5. **Verify all transactions** — Double-check addresses before signing

## Deployment Artifacts

After deployment, find artifacts in:

```
deployments/
├── sepolia.json           # Sepolia addresses
├── base-sepolia.json      # Base Sepolia addresses
└── mainnet.json           # Mainnet addresses

broadcast/
└── Deploy.sol/
    └── <chainId>/
        └── run-latest.json  # Foundry broadcast log
```
