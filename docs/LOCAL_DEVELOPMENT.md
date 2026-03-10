# Local Development Guide

This guide covers the complete local development environment for the Elata Protocol. Use this when you need more control than the [QUICKSTART](../QUICKSTART.md) provides, or when troubleshooting issues.

## Prerequisites

Before starting, install:

1. **Foundry** (forge, anvil, cast)
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Node.js** v18 or later
   ```bash
   node --version  # Should be 18+
   ```

3. **Git**

## Starting the Environment

### Recommended: One Command

```bash
bash scripts/dev-local.sh
```

This script:
- Starts Anvil on port 8545
- Deploys all protocol contracts
- Seeds test data (users, XP, apps, funding rounds)
- Generates frontend configuration (if frontend repo exists)
- Funds test accounts with ELTA

### Alternative: npm Command

```bash
npm run local:up
```

Same result, different entry point.

### Manual Steps

If you need fine-grained control:

```bash
# Terminal 1: Start blockchain
npm run dev:anvil

# Terminal 2: Deploy contracts
npm run dev:deploy

# Terminal 3: Seed test data
npm run dev:seed

# Terminal 4: Generate frontend config
npm run dev:config
```

## Test Accounts

Anvil provides 10 pre-funded accounts. The first six are configured with ELTA and XP:

| Account | Address | ELTA Balance | XP |
|---------|---------|--------------|-----|
| 0 (Deployer) | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | 10M | - |
| 1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | 100k | 5,000 |
| 2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | 100k | 3,000 |
| 3 | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | 100k | 1,500 |
| 4 | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | 100k | 800 |
| 5 | `0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc` | 100k | 300 |

Each account has 10,000 ETH for gas.

**Private keys** (Anvil defaults—never use on real networks):

```
Account 0: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
Account 1: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
Account 2: 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
Account 3: 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
Account 4: 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
Account 5: 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba
```

## Seeded Test Data

The seed script creates:

**Staking Positions**
- 10,000 ELTA locked for 2 years
- 5,000 ELTA locked for 1 year
- 2,500 ELTA locked for 6 months

**Sample Apps**
1. NeuroPong (NPONG) — EEG-controlled game with item tiers
2. MindfulBreath (BREATH) — Meditation app with staking
3. FocusTrainer (FOCUS) — Attention training with tournaments

**Funding Round**
- 7-day active round
- 10,000 ELTA in the pool
- Three proposals: PTSD Research, Depression Study, Focus Enhancement

## Network Configuration

| Setting | Value |
|---------|-------|
| RPC URL | `http://127.0.0.1:8545` |
| Chain ID | `31337` |
| Block Time | Instant (auto-mine) |

### MetaMask Setup

1. Open MetaMask → Settings → Networks → Add Network
2. Enter:
   - Network Name: `Anvil Local`
   - RPC URL: `http://127.0.0.1:8545`
   - Chain ID: `31337`
   - Currency Symbol: `ETH`
3. Import a test account using one of the private keys above

## Generated Files

After running `dev-local.sh`, you'll have:

```
elata-protocol/
├── deployments/local.json      # Contract addresses
├── anvil.log                   # Blockchain logs
└── .anvil.pid                  # Process ID
```

**deployments/local.json** contains all contract addresses:

```json
{
  "network": "localhost",
  "chainId": 31337,
  "contracts": {
    "ELTA": "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    "ElataPoints": "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
    "VeELTA": "0x...",
    ...
  }
}
```

## Common Commands

| Command | Description |
|---------|-------------|
| `npm run local:up` | Start everything |
| `npm run local:down` | Stop Anvil |
| `npm run local:restart` | Stop and restart |
| `npm run faucet <addr>` | Send 10k ELTA to address |
| `forge test` | Run contract tests |
| `forge test -vvv` | Tests with verbose output |
| `make gas-report` | Generate gas usage report |

## Interacting with Contracts

Use `cast` (part of Foundry) to call contracts directly:

```bash
# Check ELTA balance
cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
  "balanceOf(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  --rpc-url http://127.0.0.1:8545

# Get current block number
cast block-number --rpc-url http://127.0.0.1:8545

# Send a transaction
cast send 0x... "someFunction(uint256)" 100 \
  --private-key 0xac0974... \
  --rpc-url http://127.0.0.1:8545
```

## Troubleshooting

### Anvil won't start

Port 8545 is probably in use. Kill existing processes:

```bash
lsof -i :8545          # Find process
kill -9 <PID>          # Kill it
npm run local:up       # Restart
```

Or use the stop script:

```bash
npm run local:down
npm run local:up
```

### Deployment hangs on "Waiting for pending transactions"

Clear the broadcast cache and restart:

```bash
rm -rf broadcast/Deploy.sol/31337
rm -rf broadcast/SeedLocalData.s.sol/31337
npm run local:restart
```

### MetaMask shows "nonce too high" errors

Anvil restarted but MetaMask cached the old state. Clear it:

MetaMask → Settings → Advanced → Clear activity tab data

Then hard-refresh the browser (Cmd+Shift+R or Ctrl+Shift+R).

### Contracts compile but deployment fails

Clean build artifacts and retry:

```bash
forge clean
npm run local:up
```

### Need more ETH for gas

Send ETH from the deployer account:

```bash
cast send <your-address> --value 10ether \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://127.0.0.1:8545
```

## Testing Contract Changes

When you modify contracts:

```bash
# Quick rebuild and redeploy (keeps Anvil running)
forge build
npm run dev:deploy
npm run dev:seed
npm run dev:config

# Or restart everything
npm run local:restart
```

## State Persistence

By default, Anvil state resets when stopped. To persist state across restarts:

```bash
# Start with state saving
anvil --state-interval 1 --dump-state anvil-state.json

# Later, load saved state
anvil --load-state anvil-state.json
```

## Next Steps

- [ARCHITECTURE.md](./ARCHITECTURE.md) — How the contracts fit together
- [APP_LAUNCH_GUIDE.md](./APP_LAUNCH_GUIDE.md) — Building apps on the protocol
- [DEPLOYMENT.md](./DEPLOYMENT.md) — Deploying to testnet and mainnet
