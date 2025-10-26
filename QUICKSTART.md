# Elata Protocol - Quick Start Guide

## 🚀 Local Development Setup (One Command)

Get the entire Elata Protocol stack running locally in under 2 minutes:

```bash
npm run local:up
```

This single command will:
1. ✅ Start Anvil (local Ethereum blockchain)
2. ✅ Build all smart contracts
3. ✅ Deploy all contracts (ELTA, AppFactory, Governance, etc.)
4. ✅ Seed test data (users, XP, staking, apps, funding rounds)
5. ✅ Generate frontend configuration

**That's it!** Your local blockchain is now running with all contracts deployed.

---

## 📋 What Gets Deployed

### Core Contracts
- **ELTA Token**: ERC20 governance token
- **ElataXP**: Non-transferable XP token for reputation
- **VeELTA**: Vote-escrowed ELTA for governance voting power
- **AppFactory**: Launch new app tokens with bonding curves
- **AppModuleFactory**: Create app modules (tournaments, leaderboards, etc.)
- **TournamentFactory**: Create competitive tournaments
- **LotPool**: Funding rounds for research/development
- **RewardsDistributor**: Distribute ELTA rewards (70/15/15 split)
- **ElataGovernor**: On-chain governance
- **ElataTimelock**: Timelock for governance execution

### Test Data Seeded
- 5 test users with XP (300-5000 XP each)
- 1 staking position (10,000 ELTA locked for 2 years)
- 3 test apps (NeuroPong, MindfulBreath, FocusTrainer)
- 1 active funding round (10,000 ELTA pool)

---

## 🎮 Next Steps

### Start the Frontend (App Store)

```bash
cd ../elata-appstore
npm run local:full
```

The App Store will be available at `http://localhost:3001`

### View Deployed Contract Addresses

```bash
cat deployments/local.json
```

### Check Anvil Logs

```bash
tail -f anvil.log
```

### Get ELTA Tokens for Testing

Need ELTA to launch apps or test features? Use the faucet:

```bash
npm run faucet <your-wallet-address>
```

This sends 10,000 ELTA from the deployer account to your address.

**Example:**
```bash
npm run faucet 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb
```

**Note:** The faucet only works on local network (chainId 31337) for safety.

---

## 🛠️ Available Commands

### Primary Commands

| Command | Description |
|---------|-------------|
| `npm run local:up` | **Start everything** (Anvil + Deploy + Seed) |
| `npm run local:down` | **Stop everything** (Anvil + cleanup) |
| `npm run local:restart` | **Restart** (Down + Up) |

### Individual Steps (Advanced)

| Command | Description |
|---------|-------------|
| `npm run anvil:start` | Start Anvil only |
| `npm run deploy:local` | Deploy contracts only |
| `npm run seed:local` | Seed test data only |
| `npm run config:appstore` | Generate frontend config only |

### Testnet Deployment

| Command | Description |
|---------|-------------|
| `npm run deploy:sepolia` | Deploy to Sepolia testnet |
| `npm run deploy:base-sepolia` | Deploy to Base Sepolia |

---

## 🔧 Troubleshooting

### Anvil Won't Start

```bash
# Kill any existing Anvil process
pkill -9 anvil

# Try starting again
npm run local:up
```

### Contracts Won't Deploy

```bash
# Clean build artifacts and try again
forge clean
npm run local:up
```

### Frontend Can't Connect

```bash
# Regenerate frontend configuration
npm run config:appstore

# Copy to appstore
cd ../elata-appstore
npm run sync-abi
```

### Check Deployment Status

```bash
# View deployment logs
cat broadcast/Deploy.sol/31337/run-latest.json | jq

# Check if contracts have code
cast code <CONTRACT_ADDRESS> --rpc-url http://127.0.0.1:8545
```

---

## 📚 Additional Resources

- **Full Documentation**: See `docs/LOCAL_DEVELOPMENT.md` for detailed information
- **Architecture**: See `docs/ARCHITECTURE.md` for system design
- **Testing**: See `docs/TESTING.md` for running tests
- **Deployment**: See `docs/DEPLOYMENT.md` for production deployment

---

## ⚠️ Important Notes

### Contract Size Limits

Some contracts (AppModuleFactory) exceed the EIP-170 24KB limit. This is:
- ✅ **Safe for local development** (Anvil allows it)
- ✅ **Safe for L2 deployment** (Base, Arbitrum, Optimism)
- ⚠️ **May need optimization** for Ethereum mainnet

### Anvil Configuration

Anvil is started with:
- Chain ID: `31337`
- Port: `8545`
- `--disable-code-size-limit` (allows oversized contracts)
- 10 pre-funded accounts with 10,000 ETH each

### Default Accounts

Account #0 (Deployer):
- Address: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Private Key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
- Balance: 10,000 ETH

---

## 🤝 Contributing

When making changes:

1. **Test locally first**: `npm run local:up`
2. **Run tests**: `forge test`
3. **Check gas usage**: `forge test --gas-report`
4. **Verify deployment**: Check `deployments/local.json`

---

## 📞 Support

Having issues? Check:
1. This quickstart guide
2. `docs/LOCAL_DEVELOPMENT.md` for detailed setup
3. `docs/TROUBLESHOOTING.md` for common issues
4. GitHub Issues for known problems

---

**Happy Building! 🚀**
