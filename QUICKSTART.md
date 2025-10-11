# Quick Start - Local Development

**Get up and running in 60 seconds**

## Prerequisites

- Foundry installed: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- Node.js v18+: `node --version`

## One Command Setup

```bash
npm run dev
```

This will:
- Start Anvil (local blockchain)
- Deploy all contracts
- Create test apps (NeuroPong, MindfulBreath, FocusTrainer)
- Fund 5 test accounts with 100K ELTA each
- Award XP to users
- Create staking positions
- Start a funding round
- Generate frontend configuration

## Connect Your Frontend

```bash
npm run dev:frontend
```

Open http://localhost:3000

## Test Account

**MetaMask Setup:**
1. Add network: Chain ID `31337`, RPC `http://127.0.0.1:8545`
2. Import private key: `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d`
3. Account address: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
4. You now have 100K ELTA + 10K ETH!

## What You Get

### Test Apps (Pre-deployed)
-  **NeuroPong** - EEG Pong game
-  **MindfulBreath** - Meditation app  
-  **FocusTrainer** - Attention training

Each app has:
- Its own token with bonding curve
- 3 item tiers (Basic, Premium, Legendary)
- Staking vault
- Rewards system

### Test Users with XP
- Account 1: 5,000 XP (power user)
- Account 2: 3,000 XP (active user)
- Account 3: 1,500 XP (regular user)
- Account 4: 800 XP (casual user)
- Account 5: 300 XP (new user)

### Staking Positions
- 10K ELTA locked for 2 years
- 5K ELTA locked for 1 year
- 2.5K ELTA locked for 6 months

### Active Funding Round
- 7-day voting period
- 3 research options
- 10K ELTA funding pool

## 🛠️ Common Commands

```bash
npm run dev            # Start everything
npm run dev:stop       # Stop Anvil
npm run dev:restart    # Restart everything
npm run dev:frontend   # Start frontend
npm test               # Run tests
```

## View Contract Addresses

All addresses saved to: `deployments/local.json`

```bash
cat deployments/local.json
```

Or use the TypeScript config in your frontend:
```typescript
import { contracts } from '@/config/contracts';
console.log(contracts.ELTA); // Contract address
```

##  Troubleshooting

### Port 8545 already in use?
```bash
npm run dev:stop
npm run dev
```

### Frontend can't connect?
```bash
npm run dev:config  # Regenerate config
```

### Nonce errors in MetaMask?
```bash
# In MetaMask: Settings → Advanced → Clear activity tab data
```

##  Full Documentation

For detailed information, see:
- **[Local Development Guide](docs/LOCAL_DEVELOPMENT.md)** - Complete reference
- **[Architecture](docs/ARCHITECTURE.md)** - System design
- **[Main README](README.md)** - Project overview

## 🔗 Contract Addresses on Local

After running `npm run dev`, you'll see addresses like:

```
CORE PROTOCOL:
ELTA:              0x5FbDB2315678afecb367f032d93F642f64180aa3
ElataXP:           0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
VeELTA:            0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
LotPool:           0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
...

APP ECOSYSTEM:
AppFactory:        0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
AppModuleFactory:  0x5FC8d32690cc91D4c39d9d3abcBD16989F875707
...
```

Use these addresses in your frontend or testing scripts!

##  Next Steps

1.  Run `npm run dev` (you've done this!)
2.  Start frontend: `npm run dev:frontend`
3. 🔗 Connect MetaMask to localhost:8545
4.  Start building!

##  Pro Tips

- Use different test accounts for different user types
- Check `anvil.log` for blockchain activity
- Run `npm run dev:seed` again to reset test data
- All data resets when you stop Anvil

---

**Ready to build? Let's go! **

Questions? Check the [full guide](docs/LOCAL_DEVELOPMENT.md) or open an issue.

