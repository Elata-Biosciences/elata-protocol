# Base Sepolia Deployment Guide

This guide covers deploying to Base Sepolia testnet specifically. For general deployment information, see [docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md).

## Deployment Methods

Two options:

1. **Ledger (recommended)** — Hardware wallet for production-grade security
2. **Private Key** — For CI/automated deployments

## Ledger Deployment

### 1. Prepare Device

- Connect Ledger and open the Ethereum app
- Enable "Blind signing" in Settings
- Keep device connected and unlocked throughout deployment

### 2. Get Test ETH

Fund your Ledger address from the Base faucet:
https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet

Budget 0.05 ETH for deployment costs.

### 3. Create Environment File

Create `.env.sepolia` in the repository root:

```bash
# Network
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=your_basescan_api_key

# Protocol Configuration
ADMIN_MSIG=0xYourGnosisSafeAddress
INITIAL_TREASURY=0xYourTreasuryAddress

# Leave empty to deploy mock router (recommended for testing)
UNISWAP_V2_ROUTER=
```

No private key needed for Ledger deployment.

### 4. Deploy

```bash
bash scripts/deploy-sepolia.sh --ledger

# Or with specific address:
bash scripts/deploy-sepolia.sh --ledger --ledger-address 0xYourAddress
```

Approve each transaction on the Ledger device.

### 5. Verify

```bash
bash scripts/verify-sepolia.sh
```

## Private Key Deployment

For automated deployments without hardware wallet:

### 1. Add Key to Environment

```bash
# Add to .env.sepolia
DEPLOYER_PRIVATE_KEY=your_private_key_here
```

### 2. Deploy

```bash
bash scripts/deploy-sepolia.sh --private-key
```

**Security**: Remove `DEPLOYER_PRIVATE_KEY` from the file after deployment.

## Base Sepolia Configuration

### Mock Router

We deploy a mock Uniswap V2-compatible router for testing. This provides:
- Full control over bonding curve testing
- No external dependencies
- Consistent behavior with local development

### Contract Size Limit

AppModuleFactory exceeds the 24KB limit and is skipped on Base Sepolia. Core functionality still works:
- App launches work
- Bonding curves work
- Staking and rewards work
- Module deployment (AppAccess1155, etc.) unavailable on testnet

This resolves automatically on Base Mainnet, which doesn't enforce the limit.

### Estimated Costs

- Total deployment: ~15-20M gas
- At 1 gwei: ~0.015-0.02 ETH
- Recommended budget: 0.05 ETH

## Post-Deployment

### Artifacts

After deployment:
- `deployments/base-sepolia-deployment.json` — Contract addresses
- `broadcast/Deploy.sol/84532/` — Foundry broadcast logs

### Checklist

- [ ] All contracts deployed successfully
- [ ] All contracts verified on BaseScan
- [ ] Initial ELTA minted to multisig
- [ ] Multisig has admin roles
- [ ] Verification script passes
- [ ] Timelock permissions configured (see below)
- [ ] Vercel environment variables updated
- [ ] Private key removed from `.env.sepolia`

### Configure Timelock Permissions

The multisig must grant Governor permissions on the Timelock:

```bash
# Grant PROPOSER_ROLE to Governor
cast send $TIMELOCK_ADDRESS \
  "grantRole(bytes32,address)" \
  0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1 \
  $GOVERNOR_ADDRESS \
  --rpc-url $BASE_SEPOLIA_RPC_URL

# Grant EXECUTOR_ROLE to Governor  
cast send $TIMELOCK_ADDRESS \
  "grantRole(bytes32,address)" \
  0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783 \
  $GOVERNOR_ADDRESS \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

Or use Gnosis Safe Transaction Builder.

### Vercel Environment Variables

Add these to the elata-appstore project in Vercel (Settings → Environment Variables):

```
NEXT_PUBLIC_ELTA_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_APP_FACTORY_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_APP_MODULE_FACTORY_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_REWARDS_DISTRIBUTOR_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_APP_REWARDS_DISTRIBUTOR_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_VE_ELTA_ADDRESS_BASE_SEPOLIA=<from_deployment>
NEXT_PUBLIC_ELATA_XP_ADDRESS_BASE_SEPOLIA=<from_deployment>
```

Set scope to Preview and Development.

## Troubleshooting

### Deployment fails
- Verify RPC URL is accessible
- Check deployer has sufficient ETH
- Confirm all environment variables are set

### Verification fails
- Ensure BaseScan API key is valid
- Wait 30 seconds after deployment before verifying
- Try manual verification on BaseScan

### Contract too large error
Expected for AppModuleFactory. It deploys successfully on L2s without the 24KB limit.

## Testing After Deployment

1. Run end-to-end tests against testnet
2. Send test ELTA from multisig to test wallets
3. Launch a test app
4. Verify bonding curve buys and sells work
5. Test staking and reward claims
6. Document any issues
