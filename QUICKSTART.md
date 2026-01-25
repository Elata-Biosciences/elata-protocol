# Quick Start Guide

Get the Elata Protocol running locally in under two minutes.

## One-Command Setup

```bash
npm run local:up
```

This command:
1. Starts Anvil (local Ethereum blockchain)
2. Builds and deploys all smart contracts
3. Seeds test data (users, XP, staking positions, apps, funding rounds)
4. Generates frontend configuration

When it completes, your local blockchain is running with everything deployed.

## What Gets Deployed

**Core Contracts**
- ELTA Token (ERC20 governance token)
- ElataPoints (non-transferable reputation)
- VeELTA (vote-escrowed staking)
- RewardsDistributor (fee distribution)
- ElataGovernor and ElataTimelock (on-chain governance)

**App Ecosystem**
- AppFactory (token launcher with bonding curves)
- AppModuleFactory (utility module deployer)
- TournamentFactory (competition infrastructure)

**Test Data**
- 5 users with XP balances (300–5,000 XP each)
- Staking positions (10,000 ELTA locked for 2 years)
- 3 sample apps (NeuroPong, MindfulBreath, FocusTrainer)

## Next Steps

### Start the Frontend

In a separate terminal:

```bash
cd ../elata-appstore
npm run local:full
```

The app store runs at `http://localhost:3001`.

### View Contract Addresses

```bash
cat deployments/local.json
```

### Get Test ELTA

Send 10,000 ELTA to any address:

```bash
npm run faucet <wallet-address>
```

### Connect MetaMask

Add the local network to MetaMask:
- Network Name: Anvil Local
- RPC URL: `http://127.0.0.1:8545`
- Chain ID: `31337`
- Currency Symbol: ETH

Import the default test account:
- Address: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Private Key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

## Commands Reference

| Command | Description |
|---------|-------------|
| `npm run local:up` | Start everything |
| `npm run local:down` | Stop Anvil |
| `npm run local:restart` | Restart from scratch |
| `npm run deploy:local` | Deploy contracts only |
| `npm run seed:local` | Seed test data only |
| `npm run faucet <addr>` | Send 10k ELTA to address |

## Troubleshooting

**Anvil won't start (port in use)**

```bash
pkill -9 anvil
npm run local:up
```

**Contracts fail to deploy**

```bash
forge clean
npm run local:up
```

**MetaMask "nonce too high" error**

Clear MetaMask activity: Settings → Advanced → Clear activity tab data

**Frontend can't connect**

Regenerate the config and restart:

```bash
npm run config:appstore
cd ../elata-appstore && npm run local:full
```

## Further Reading

- [docs/LOCAL_DEVELOPMENT.md](./docs/LOCAL_DEVELOPMENT.md) — Detailed environment setup
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) — System design overview
- [docs/APP_LAUNCH_GUIDE.md](./docs/APP_LAUNCH_GUIDE.md) — Building apps on the protocol
