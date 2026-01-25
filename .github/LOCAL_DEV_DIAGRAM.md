# Local Development Environment - Visual Guide

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    npm run dev (One Command!)                   │
│                                                                 │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
        ┌──────────────────────────────────────┐
        │     scripts/dev-local.sh             │
        │  (Orchestrates everything)           │
        └──────────┬──────────┬────────┬───────┘
                   │          │        │
        ┌──────────▼──┐  ┌────▼────┐  ▼
        │   Anvil     │  │  Forge  │  
        │   (Port     │  │  Build  │  
        │   8545)     │  │         │  
        └──────┬──────┘  └────┬────┘  
               │              │
               │   ┌──────────▼──────────────────┐
               │   │ DeployLocalFull.s.sol       │
               │   │ • 10 Core Contracts         │
               │   │ • 2 Mock Uniswap           │
               │   │ • 5 Test Accounts          │
               │   └──────────┬──────────────────┘
               │              │
               │   ┌──────────▼──────────────────┐
               │   │ SeedLocalData.s.sol         │
               │   │ • 3 Test Apps              │
               │   │ • XP Distribution          │
               │   │ • Staking Positions        │
               │   │ • Funding Round            │
               │   └──────────┬──────────────────┘
               │              │
               └──────────┬───┴──────────────────┐
                          │                      │
                          ▼                      ▼
              ┌─────────────────────┐  ┌──────────────────────┐
              │ deployments/        │  │ generate-config.ts   │
              │   local.json        │  │                      │
              │ (Contract Addresses)│  │ Creates:             │
              └─────────────────────┘  │ • .env.local         │
                                       │ • contracts.ts       │
                                       └──────────────────────┘
```

## Contract Deployment Flow

```
Start Anvil
    │
    ├─► Core Protocol Contracts
    │   ├─► ELTA Token ─────────────► 0x5FbDB...
    │   ├─► ElataPoints ────────────► 0xe7f17...
    │   ├─► VeELTA ────────────────► 0x9fE46...
    │   ├─► RewardsDistributor ────► 0xDc64a...
    │   ├─► ElataTimelock ─────────► 0x5FC8d...
    │   └─► ElataGovernor ─────────► 0x0165...
    │
    ├─► App Ecosystem Contracts
    │   ├─► AppFactory ────────────► 0xa513...
    │   ├─► AppModuleFactory ──────► 0x2279...
    │   └─► TournamentFactory ─────► 0x8A79...
    │
    └─► Mock DEX Contracts
        ├─► UniswapV2Factory ──────► 0x9fE4...
        └─► UniswapV2Router ────────► 0xCf7E...
```

## Data Seeding Flow

```
SeedLocalData.s.sol
    │
    ├─► Award XP
    │   ├─► Account 1 ─────► 5,000 XP (Power User)
    │   ├─► Account 2 ─────► 3,000 XP (Active User)
    │   ├─► Account 3 ─────► 1,500 XP (Regular User)
    │   ├─► Account 4 ─────► 800 XP (Casual User)
    │   └─► Account 5 ─────► 300 XP (New User)
    │
    ├─► Create Staking Positions
    │   ├─► Lock #1 ───────► 10,000 ELTA × 2 years
    │   ├─► Lock #2 ───────► 5,000 ELTA × 1 year
    │   └─► Lock #3 ───────► 2,500 ELTA × 6 months
    │
    ├─► Deploy Test Apps
    │   ├─► NeuroPong
    │   │   ├─► NPONG Token
    │   │   ├─► Bonding Curve
    │   │   ├─► Access1155 (3 items)
    │   │   ├─► StakingVault
    │   │   └─► EpochRewards
    │   │
    │   ├─► MindfulBreath
    │   │   └─► (Same structure)
    │   │
    │   └─► FocusTrainer
    │       └─► (Same structure)
    │
    └─► Start Funding Round
        ├─► Option 1: PTSD Research
        ├─► Option 2: Depression Study
        ├─► Option 3: Focus Enhancement
        └─► Pool: 10,000 ELTA
```

## Frontend Integration

```
generate-config.ts
    │
    ├─► Read: deployments/local.json
    │
    ├─► Generate: frontend/.env.local
    │   ├─► NEXT_PUBLIC_CHAIN_ID=31337
    │   ├─► NEXT_PUBLIC_RPC_URL=http://127.0.0.1:8545
    │   ├─► NEXT_PUBLIC_ELTA_ADDRESS=0x5FbDB...
    │   ├─► NEXT_PUBLIC_ELATA_XP_ADDRESS=0xe7f17...
    │   └─► ... (all contracts)
    │
    └─► Generate: frontend/src/config/contracts.ts
        export const contracts = {
          ELTA: '0x5FbDB...' as const,
          ElataPoints: '0xe7f17...' as const,
          ...
        };
```

## Test Accounts

```
Deployer (Account 0)
├─► Address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
├─► Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
├─► ELTA Balance: 10,000,000 ELTA
└─► ETH Balance: 10,000 ETH

Test Account 1
├─► Address: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
├─► Private Key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
├─► ELTA Balance: 100,000 ELTA
├─► XP Balance: 5,000 XP
└─► ETH Balance: 10,000 ETH

Test Account 2
├─► Address: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
├─► Private Key: 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
├─► ELTA Balance: 100,000 ELTA
├─► XP Balance: 3,000 XP
└─► ETH Balance: 10,000 ETH

(+3 more accounts...)
```

## Development Workflow

```
┌──────────────────────┐
│   npm run dev        │ ◄─────── One command starts everything
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│   Anvil Running      │ ◄─────── Local blockchain on :8545
│   All Contracts      │
│   Test Data Seeded   │
└──────────┬───────────┘
           │
           ├─────► npm run dev:frontend  ───► http://localhost:3000
           │
           ├─────► Connect MetaMask
           │       └─► Network: localhost:8545
           │           Chain ID: 31337
           │           Import private key
           │
           └─────► Start Developing!
                   │
                   ├─► Edit contracts? → npm run dev:restart
                   ├─► View logs? → tail -f anvil.log
                   └─► Done? → npm run dev:stop
```

## File Structure

```
elata-protocol/
├── script/
│   ├── DeployLocalFull.s.sol   ← Deploys everything
│   ├── SeedLocalData.s.sol     ← Seeds test data
│   ├── Deploy.sol              ← Production deployment
│   └── DeployLocal.s.sol       ← Old simple version
│
├── scripts/
│   ├── dev-local.sh            ← Main orchestration script
│   ├── dev-stop.sh             ← Stop Anvil
│   ├── dev-restart.sh          ← Restart everything
│   └── generate-config.ts      ← Generate frontend config
│
├── deployments/
│   ├── .gitignore              ← Ignore local.json
│   └── local.json              ← Contract addresses (auto-gen)
│
├── frontend/
│   ├── .env.local              ← Environment variables (auto-gen)
│   └── src/config/
│       └── contracts.ts        ← TypeScript config (auto-gen)
│
├── docs/
│   └── LOCAL_DEVELOPMENT.md    ← Complete guide
│
├── QUICKSTART.md               ← Quick reference
├── LOCAL_DEV_SETUP_SUMMARY.md  ← This summary
└── package.json                ← npm scripts
```

## Quick Command Reference

```bash
# Setup & Start
npm run dev              # Start everything (recommended)
npm run dev:start        # Alias for npm run dev

# Individual Steps
npm run dev:anvil        # Start Anvil only
npm run dev:deploy       # Deploy contracts only
npm run dev:seed         # Seed data only
npm run dev:config       # Generate config only

# Management
npm run dev:stop         # Stop Anvil
npm run dev:restart      # Clean restart

# Development
npm run dev:frontend     # Start frontend
npm test                 # Run tests
npm run test:gas         # Gas report

# Build
npm run build            # Build contracts
```

## Network Configuration

```
Chain ID:    31337
RPC URL:     http://127.0.0.1:8545
Block Time:  Instant (auto-mining)
Gas Limit:   Unlimited
Persistence: Ephemeral (resets on restart)
```

## What Gets Created

### Contracts (12)
- ✅ ELTA, ElataPoints, VeELTA
- ✅ RewardsDistributor, ElataTimelock, ElataGovernor
- ✅ AppFactory, AppModuleFactory, TournamentFactory
- ✅ Mock Uniswap Factory + Router

### Test Apps (3)
- ✅ NeuroPong (NPONG)
- ✅ MindfulBreath (BREATH)
- ✅ FocusTrainer (FOCUS)

### Each App Has
- ✅ Token with bonding curve
- ✅ 3 NFT items (Basic, Premium, Legendary)
- ✅ Staking vault
- ✅ Rewards system
- ✅ Feature gates

### Test Data
- ✅ 5 users with XP (300-5000)
- ✅ 3 staking positions (2.5K-10K ELTA)
- ✅ 1 active funding round (7 days)
- ✅ 10K ELTA in funding pool

---

**Ready to develop! Start with: `npm run dev`** 🚀

