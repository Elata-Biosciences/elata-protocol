# Elata Protocol

**The Internet of Brains** - A decentralized ecosystem for precision psychiatry powered by open-source EEG hardware, tokenized research coordination, and gamified applications.

## Overview

Elata Biosciences is building the infrastructure for the future of mental health research and treatment. Our mission is to replace trial-and-error psychiatry with **biomarker-driven, personalized treatments** by generating open, community-owned EEG datasets and incentivizing their use in experiments.

### Core Components

1. **EEG Hardware** - 8-channel, sub-$500 open-source EEG units
2. **ZORP** - On-chain research protocol for privacy-preserving data submission
3. **App Layer** - EEG-driven games, meditation apps, and competitive platforms
4. **Token Economy** - $ELTA governance token with veELTA staking and XP rewards

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   EEG Hardware  │    │  ZORP Protocol  │    │   App Layer     │
│                 │    │                 │    │                 │
│ • 8-channel     │────│ • Data Trusts   │────│ • EEG Pong      │
│ • Open Source   │    │ • PGP Encrypted │    │ • Meditation    │
│ • Sub-$500      │    │ • IPFS Storage  │    │ • Competitions  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │ Token Economy   │
                    │                 │
                    │ • ELTA Token    │
                    │ • veELTA Staking│
                    │ • XP System     │
                    │ • LotPool Votes │
                    └─────────────────┘
```

## Smart Contracts

### Core Contracts

| Contract | Description | Key Features |
|----------|-------------|--------------|
| **ELTA.sol** | Governance token | ERC20 + Votes + Permit, 77M supply cap |
| **VeELTA.sol** | Simple vote-escrowed staking | Linear time decay, 1 week - 2 year locks |
| **VeELTAMultiLock.sol** | Advanced multi-position staking | NFT-based, multiple concurrent locks |
| **ElataXP.sol** | Basic experience points | Non-transferable, checkpoint tracking |
| **ElataXPWithDecay.sol** | Advanced XP with decay | 14-day rolling decay, keeper functions |
| **LotPool.sol** | Research funding | XP-weighted voting, weekly rounds |
| **RewardsDistributor.sol** | Staker rewards | Merkle tree distribution, multiple tokens |
| **ElataGovernorSimple.sol** | On-chain governance | Quorum voting, emergency proposals |

### Token Economics

- **Total Supply**: 77,000,000 ELTA
- **Distribution**:
  - Presale: 7.5% ($420k raised)
  - Community Sale: 10% (~$1M target)
  - Team & Advisors: 15% (6-year vest)
  - Treasury: 38%
  - Community Incentives: ~20%
  - Liquidity: 10%

### Governance Mechanics

#### Vote-Escrowed Staking (veELTA)
- Lock ELTA for 1 week to 2 years
- Voting power = `amount × (timeRemaining / MAX_LOCK)`
- Linear decay over time
- Non-transferable positions

#### Experience Points (XP)
- Earned through:
  - EEG data submission
  - App usage and engagement
  - Community participation
- Used for:
  - Research funding votes
  - App Store boosts
  - Reputation system

#### LotPool Governance
- Weekly funding rounds
- XP snapshot-based voting
- Multiple proposal support
- Transparent fund distribution

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/)
- [Node.js](https://nodejs.org/) (for frontend integration)
- [Git](https://git-scm.com/)

### Installation

```bash
# Clone the repository
git clone https://github.com/Elata-Biosciences/elata-protocol
cd elata-protocol

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Environment Setup

Create a `.env` file with the following variables:

```bash
# Deployment addresses
ADMIN_MSIG=0x...           # Gnosis Safe multisig
INITIAL_TREASURY=0x...     # Initial token recipient

# RPC URLs
MAINNET_RPC_URL=https://...
SEPOLIA_RPC_URL=https://...
BASE_RPC_URL=https://...
BASE_SEPOLIA_RPC_URL=https://...

# API Keys
ETHERSCAN_API_KEY=...
BASESCAN_API_KEY=...
```

### Deployment

```bash
# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

# Deploy to mainnet (use with caution)
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

## Testing

The protocol includes comprehensive test coverage:

```bash
# Run all tests
forge test

# Run with gas reporting
forge test --gas-report

# Run specific test file
forge test --match-contract ELTATest

# Run with verbosity
forge test -vvv
```

### Test Categories

- **Unit Tests**: Individual contract functionality
- **Integration Tests**: Multi-contract interactions
- **Fuzz Tests**: Property-based testing with random inputs

## Security Considerations

### Access Control
- Role-based permissions using OpenZeppelin AccessControl
- Multi-signature wallet for admin functions
- Time-locked governance for critical changes

### Token Security
- No transfer taxes or fees
- Capped supply with burn functionality
- Non-upgradeable contracts for immutability

### Staking Security
- Reentrancy protection on all state-changing functions
- Linear decay prevents gaming of voting power
- Withdrawal only after lock expiration


## Contributing

We welcome contributions from the community! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## Community

- **Website**: [elata.bio](https://elata.bio)
- **Discord**: [Join our community](https://discord.gg/elata)
- **Twitter**: [@ElataBio](https://twitter.com/ElataBio)
- **Documentation**: [docs.elata.bio](https://docs.elata.bio)

## Legal

### Partnerships
- **Nina Kilbride**: Legal advisor (data trusts, DAO structuring)
- **Dr. Morgan Hough**: EEG scientist and advisor
- **Paragon Strategy**: Communications and PR ($8k/month + 3% tokens)

### Collaborations
- **Spectruth DAO**: PTSD study (200 patients, EEG + epigenetics)
- **Baselight**: Decentralized data resale partnership
- **BIO Protocol**: Token economics research

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Disclaimer**: This software is in active development. Use at your own risk. The token economics and governance mechanisms are experimental and may change based on community feedback and research findings.