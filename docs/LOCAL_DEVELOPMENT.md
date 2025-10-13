# Local Development Guide

**Complete guide to running Elata Protocol locally with a mock blockchain**

This guide will help you set up a full local development environment with all smart contracts deployed and seeded with test data. Perfect for frontend development and testing before deploying to testnets.

---

##  Quick Start

### Prerequisites

1. **Foundry** (Forge, Anvil, Cast)
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Node.js** (v18+)
   ```bash
   # Check version
   node --version
   ```

3. **Git**
   ```bash
   git --version
   ```

### One-Command Setup

```bash
npm run dev
```

This single command will:
-  Start Anvil (local blockchain)
-  Deploy ALL Elata Protocol contracts
-  Seed test data (apps, XP, staking positions, funding rounds)
-  Generate frontend configuration files
-  Set up test accounts with ELTA tokens

**That's it!** Your local blockchain is ready for development.

---

## 📋 Available Commands

### Primary Commands

| Command | Description |
|---------|-------------|
| `npm run dev` | Complete setup (start Anvil + deploy + seed) |
| `npm run dev:stop` | Stop Anvil blockchain |
| `npm run dev:restart` | Stop and restart everything |
| `npm run dev:frontend` | Start the frontend dev server |

### Manual Commands (for fine-grained control)

| Command | Description |
|---------|-------------|
| `npm run dev:anvil` | Start Anvil only |
| `npm run dev:deploy` | Deploy contracts only |
| `npm run dev:seed` | Seed test data only |
| `npm run dev:config` | Generate frontend config only |

### Testing Commands

| Command | Description |
|---------|-------------|
| `npm test` | Run all tests |
| `npm run test:gas` | Run tests with gas report |
| `npm run test:coverage` | Generate coverage report |

---

## 🏗️ What Gets Deployed

### Core Protocol Contracts

-  **ELTA Token** - Governance & utility token (77M cap)
-  **ElataXP** - Experience points (soulbound)
-  **VeELTA** - Vote-escrowed staking
-  **LotPool** - XP-weighted funding rounds
-  **RewardsDistributor** - Staker rewards
-  **ElataGovernor** - On-chain governance
-  **ElataTimelock** - Governance timelock

### App Ecosystem Contracts

-  **AppFactory** - Token launcher with bonding curves
-  **AppModuleFactory** - Utility module deployer
-  **TournamentFactory** - Tournament infrastructure

### Mock Contracts (for local testing)

-  **MockUniswapV2Factory** - DEX factory
-  **MockUniswapV2Router** - DEX router

---

## 🌱 Seed Data

The seed script automatically creates:

### Test Users with XP

| Account | XP Amount | Description |
|---------|-----------|-------------|
| Account #1 | 5,000 XP | Power user |
| Account #2 | 3,000 XP | Active user |
| Account #3 | 1,500 XP | Regular user |
| Account #4 | 800 XP | Casual user |
| Account #5 | 300 XP | New user |

### Staking Positions

-  Position 1: 10,000 ELTA locked for 2 years
-  Position 2: 5,000 ELTA locked for 1 year
-  Position 3: 2,500 ELTA locked for 6 months

### Test Apps (fully configured)

1. **NeuroPong Token (NPONG)**
   - EEG-controlled Pong game
   - 3 item tiers (Basic, Premium, Legendary)
   - Feature gating configured

2. **MindfulBreath Token (BREATH)**
   - Meditation with EEG feedback
   - Full economy with items and staking

3. **FocusTrainer Token (FOCUS)**
   - Attention training
   - Tournament-ready configuration

### Funding Round

-  Active 7-day funding round with 3 options:
  - PTSD Research
  - Depression Study
  - Focus Enhancement
-  10,000 ELTA in funding pool

---

##  Test Accounts & Keys

All accounts are pre-funded with **100,000 ELTA** for testing.

### Anvil Default Accounts

| # | Address | Private Key | Balance |
|---|---------|-------------|---------|
| 0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` | 10M ELTA + 10K ETH |
| 1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` | 100K ELTA + 10K ETH |
| 2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` | 100K ELTA + 10K ETH |
| 3 | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` | 100K ELTA + 10K ETH |
| 4 | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | `0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a` | 100K ELTA + 10K ETH |
| 5 | `0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc` | `0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba` | 100K ELTA + 10K ETH |

>  **Warning**: These are Anvil's default test keys. Never use them on real networks!

---

##  Network Configuration

### Local Blockchain (Anvil)

- **RPC URL**: `http://127.0.0.1:8545`
- **Chain ID**: `31337`
- **Block Time**: Instant (auto-mining)
- **Gas Limit**: Unlimited

### MetaMask Setup

1. Open MetaMask
2. Add Network → Add Network Manually
3. Enter details:
   - **Network Name**: Anvil Local
   - **RPC URL**: `http://127.0.0.1:8545`
   - **Chain ID**: `31337`
   - **Currency Symbol**: `ETH`
4. Import one of the test private keys above

---

##  Generated Files

After running `npm run dev`, you'll find:

```
elata-protocol/
├── deployments/
│   └── local.json           # All contract addresses
├── frontend/
│   ├── .env.local           # Environment variables
│   └── src/config/
│       └── contracts.ts     # TypeScript config
├── anvil.log                # Anvil blockchain logs
└── .anvil.pid               # Anvil process ID
```

### `deployments/local.json`

```json
{
  "network": "localhost",
  "chainId": 31337,
  "deployer": "0xf39Fd...",
  "contracts": {
    "ELTA": "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    "ElataXP": "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
    // ... all contract addresses
  },
  "testAccounts": [...]
}
```

### `frontend/.env.local`

Auto-generated environment variables for frontend:

```env
NEXT_PUBLIC_CHAIN_ID=31337
NEXT_PUBLIC_RPC_URL=http://127.0.0.1:8545
NEXT_PUBLIC_ELTA_ADDRESS=0x5FbDB...
# ... all contract addresses
```

### `frontend/src/config/contracts.ts`

Type-safe TypeScript configuration:

```typescript
export const contracts = {
  ELTA: '0x5FbDB...' as const,
  ElataXP: '0xe7f17...' as const,
  // ... all contracts
} as const;

export function getContractAddress(name: ContractName): string {
  return contracts[name];
}
```

---

## 🛠️ Development Workflows

### Standard Development Flow

```bash
# 1. Start local blockchain with everything
npm run dev

# 2. In another terminal, start frontend
npm run dev:frontend

# 3. Open http://localhost:3000
# Your app is now connected to local blockchain!

# 4. When done, stop Anvil
npm run dev:stop
```

### Testing Contract Changes

```bash
# 1. Make changes to contracts in src/

# 2. Restart everything
npm run dev:restart

# 3. Frontend automatically connects to new contracts
```

### Manual Workflow (for debugging)

```bash
# Terminal 1: Start Anvil
npm run dev:anvil

# Terminal 2: Deploy contracts
npm run dev:deploy

# Terminal 3: Seed data
npm run dev:seed

# Terminal 4: Generate config
npm run dev:config

# Terminal 5: Start frontend
npm run dev:frontend
```

---

##  Viewing Blockchain State

### Using Cast (Foundry CLI)

```bash
# Check ELTA balance
cast call $ELTA_ADDRESS "balanceOf(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url http://127.0.0.1:8545

# Check XP balance
cast call $XP_ADDRESS "balanceOf(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url http://127.0.0.1:8545

# Get app info
cast call $APP_FACTORY_ADDRESS "apps(uint256)" 1 --rpc-url http://127.0.0.1:8545

# Current block number
cast block-number --rpc-url http://127.0.0.1:8545
```

### Using Console Logs

Watch Anvil logs in real-time:

```bash
tail -f anvil.log
```

---

## 🧪 Testing Against Local Blockchain

### Running Frontend Tests

```bash
cd frontend
npm test
```

### End-to-End Testing

```bash
# Start local environment
npm run dev

# Run E2E tests (in another terminal)
cd frontend
npm run test:e2e
```

---

##  Troubleshooting

### Problem: Anvil won't start (port already in use)

```bash
# Check what's using port 8545
lsof -i :8545

# Kill the process
kill -9 <PID>

# Or use our stop script
npm run dev:stop
```

### Problem: Contracts not deploying

```bash
# Check Anvil is running
curl -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545

# If Anvil is running but deployment fails, try:
npm run dev:restart
```

### Problem: Frontend can't connect

```bash
# 1. Verify .env.local exists
ls -la frontend/.env.local

# 2. Regenerate config
npm run dev:config

# 3. Restart frontend
cd frontend && npm run dev
```

### Problem: "Nonce too high" errors

This happens when Anvil restarts but frontend still has old state.

```bash
# Solution 1: Hard refresh browser (Cmd+Shift+R)
# Solution 2: Clear MetaMask activity
# Settings → Advanced → Clear activity tab data

# Solution 3: Restart everything
npm run dev:restart
```

### Problem: Test accounts have no ELTA

The seed script should fund accounts automatically. If they're empty:

```bash
# Manually run seed script
npm run dev:seed
```

---

##  Performance & Optimization

### Fast Iteration

Changes to contracts require redeployment:

```bash
# Quick redeploy (keeps Anvil running)
npm run dev:deploy && npm run dev:seed && npm run dev:config
```

### State Persistence

By default, Anvil state is ephemeral (resets on restart). To persist:

```bash
# Start Anvil with state file
anvil --state-interval 1 --dump-state anvil-state.json

# Load previous state
anvil --load-state anvil-state.json
```

---

## 🔐 Security Notes

### Local Development Only

 **Never use these private keys on real networks!**

- All test keys are publicly known
- Anvil is for development only
- No security guarantees

### Before Deploying to Testnet

1. Generate new keys: `cast wallet new`
2. Fund with testnet ETH
3. Update deployment scripts
4. Never commit private keys to git

---

## 🚢 Next Steps: Deploying to Testnet

Once you're happy with local development:

### 1. Get Testnet ETH

- **Sepolia**: https://sepoliafaucet.com/
- **Base Sepolia**: https://bridge.base.org/

### 2. Set Environment Variables

```bash
# .env (don't commit this!)
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
PRIVATE_KEY=0xYOUR_TESTNET_KEY
ADMIN_MSIG=0xYourGnosisSafeAddress
INITIAL_TREASURY=0xYourTreasuryAddress
ETHERSCAN_API_KEY=YOUR_API_KEY
```

### 3. Deploy to Testnet

```bash
npm run deploy:sepolia
```

### 4. Verify Contracts

Verification happens automatically with `--verify` flag, or manually:

```bash
forge verify-contract $CONTRACT_ADDRESS src/token/ELTA.sol:ELTA \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

---

##  Additional Resources

- **Foundry Book**: https://book.getfoundry.sh/
- **Anvil Docs**: https://book.getfoundry.sh/anvil/
- **Cast Reference**: https://book.getfoundry.sh/reference/cast/
- **Elata Docs**: https://docs.elata.bio

---

##  Tips & Best Practices

### 1. Use Multiple Test Accounts

Switch between accounts in MetaMask to test different user scenarios:
- Account 1: Power user with lots of XP
- Account 2: Regular user
- Account 3: New user with minimal XP

### 2. Monitor Gas Usage

```bash
npm run test:gas
```

Optimize contracts before deploying to mainnet where gas costs real money.

### 3. Test Edge Cases

Local blockchain is perfect for testing:
- Maximum values
- Overflow conditions
- Reentrancy attacks
- Access control bypasses

### 4. Keep Scripts Updated

When adding new contracts, update:
- `script/DeployLocalFull.s.sol`
- `script/SeedLocalData.s.sol`
- `scripts/generate-config.ts`

---

##  Contributing

Found an issue with the local development setup? Please:

1. Check existing issues
2. Create a new issue with:
   - Your OS and versions
   - Error messages
   - Steps to reproduce

---

##  Quick Reference

### Most Common Commands

```bash
# Start everything
npm run dev

# Stop Anvil
npm run dev:stop

# Restart everything
npm run dev:restart

# Start frontend
npm run dev:frontend
```

### Contract Addresses

Always read from `deployments/local.json` or use the generated TypeScript config.

### Default RPC

```
http://127.0.0.1:8545
```

### Chain ID

```
31337
```

---

**Happy developing! **

For questions, join our Discord or open a GitHub issue.



