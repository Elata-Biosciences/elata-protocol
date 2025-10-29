# Base Sepolia Deployment Guide

## Deployment Methods

We support two deployment methods:

1. **Ledger (Recommended)** - Most secure, uses hardware wallet
2. **Private Key** - For CI/automated deployments

## Quick Start (Ledger - Recommended)

### 1. Prepare Ledger Device

- Connect your Ledger device
- Open the Ethereum app
- Go to Settings → Enable "Blind signing"
- Keep device connected and unlocked

### 2. Get Base Sepolia ETH

Fund your Ledger address: https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet

### 3. Create `.env.sepolia` file

```bash
# Base Sepolia Deployment Configuration

# Network Configuration
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=your_basescan_api_key_here

# Governance & Treasury
ADMIN_MSIG=0xC50e39B8e22710790939f02Ad77CEb99c1cC7DF4
INITIAL_TREASURY=0xC50e39B8e22710790939f02Ad77CEb99c1cC7DF4

# DEX Router (leave empty to deploy mock router - recommended)
UNISWAP_V2_ROUTER=

# Optional: XP Operators
# XP_OPERATOR_1=0x...
```

**Note**: No private key needed for Ledger deployment!

### 4. Deploy with Ledger

```bash
bash scripts/deploy-sepolia.sh --ledger

# Or with specific Ledger address:
bash scripts/deploy-sepolia.sh --ledger --ledger-address 0xYourLedgerAddress
```

The script will:
- Prompt you to confirm Ledger prerequisites
- Ask for your Ledger address (if not provided)
- Show deployment configuration
- Ask for final confirmation
- Deploy contracts (approve each tx on Ledger device)

### 5. Verify Deployment

```bash
bash scripts/verify-sepolia.sh
```

## Alternative: Private Key Deployment

For automated deployments or if you don't have a Ledger:

### 1. Create `.env.sepolia` with Private Key

```bash
# Add to .env.sepolia
DEPLOYER_PRIVATE_KEY=your_private_key_here
```

### 2. Deploy with Private Key

```bash
bash scripts/deploy-sepolia.sh --private-key
```

**⚠️ Security Warning**: Remove `DEPLOYER_PRIVATE_KEY` from `.env.sepolia` after deployment!

## Configuration Details

### Admin Multisig
- **Address**: `0xC50e39B8e22710790939f02Ad77CEb99c1cC7DF4`
- **Purpose**: Admin control over all protocol contracts
- **Receives**: 10,000,000 ELTA initial mint

### Mock Router Strategy
We deploy our own mock Uniswap V2-compatible router on Base Sepolia for:
- **Full control** over bonding curve testing
- **No external dependencies** on third-party DEXs
- **Consistent behavior** with local development
- **Security** - known codebase

The mock router is identical to what we use for local Anvil development.

### AppModuleFactory Note
**AppModuleFactory is skipped on Base Sepolia** due to the 24KB contract size limit (it's 29.8KB). This is expected and doesn't affect core functionality:
- ✅ App launches work
- ✅ Bonding curves work
- ✅ Staking and rewards work
- ❌ Module deployment (AppAccess1155, etc.) won't be available on testnet

This will be resolved when we deploy to Base Mainnet or can be deployed separately if needed for testing.

### Gas Costs
Estimated deployment gas:
- Total contracts: ~15-20M gas
- At 1 gwei: ~0.015-0.02 ETH
- Budget: 0.05 ETH for safety

### Deployment Artifacts

After deployment, you'll find:
- `deployments/base-sepolia-deployment.json` - Contract addresses
- `broadcast/Deploy.sol/84532/` - Foundry broadcast logs

## Post-Deployment Checklist

- [ ] All contracts deployed successfully
- [ ] All contracts verified on BaseScan
- [ ] 10M ELTA in multisig treasury
- [ ] Multisig has admin roles
- [ ] No ELTA in deployer wallet
- [ ] Verification script passes
- [ ] Addresses documented
- [ ] **Configure Timelock permissions via multisig** (see below)
- [ ] Vercel env vars updated
- [ ] Local .env.sepolia cleaned (private key removed)

## Manual Multisig Configuration Required

After deployment, the multisig must grant Governor permissions on the Timelock:

```bash
# Via Gnosis Safe UI or cast:
# 1. Grant PROPOSER_ROLE to Governor
cast send <TIMELOCK_ADDRESS> \
  "grantRole(bytes32,address)" \
  0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1 \
  <GOVERNOR_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC_URL

# 2. Grant EXECUTOR_ROLE to Governor  
cast send <TIMELOCK_ADDRESS> \
  "grantRole(bytes32,address)" \
  0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783 \
  <GOVERNOR_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

Or use Gnosis Safe Transaction Builder with the Timelock contract.

## Updating Vercel Environment Variables

After deployment, add these to Vercel (elata-appstore project → Settings → Environment Variables):

**Scope**: Preview, Development

```bash
NEXT_PUBLIC_ELTA_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_APP_FACTORY_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_APP_MODULE_FACTORY_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_REWARDS_DISTRIBUTOR_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_APP_REWARDS_DISTRIBUTOR_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_VE_ELTA_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_ELATA_XP_ADDRESS_BASE_SEPOLIA=<from_deployment>
```

## Troubleshooting

### Deployment Fails
- Check RPC URL is accessible
- Verify private key has Base Sepolia ETH
- Confirm environment variables are set

### Verification Fails
- Get BaseScan API key
- Wait 30 seconds after deployment
- Try manual verification on BaseScan

### Contract Too Large
- This is expected for some contracts
- They work on Base (no 24KB limit)
- Local deployment uses lower optimization runs

## Security Notes

1. **Never commit `.env.sepolia`** - it's git-ignored
2. **Deployer key** should be a dedicated testnet-only wallet
3. **After deployment**, remove private key from .env.sepolia
4. **Multisig** should be the only admin with long-term control
5. **Testnet tokens** have no value, but practice good security

## Next Steps

1. Run end-to-end tests on testnet
2. Send test ELTA from multisig to test wallets
3. Launch test apps
4. Verify bonding curve functionality
5. Test staking and rewards
6. Document any issues or learnings

