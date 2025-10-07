# Elata App Store Frontend

A Next.js frontend for the Elata App Store - a permissionless launch surface for EEG/BCI applications.

## Overview

This frontend provides a clean, clinical interface for:
- Browsing live app launches and bonding curve offerings
- Participating in fair token sales using ELTA
- Launching new tokenized applications
- Managing created apps and purchased tokens

## Tech Stack

- **Framework**: Next.js 15 with App Router
- **Styling**: Tailwind CSS with Elata design system
- **Web3**: wagmi v2 + viem + RainbowKit
- **State**: TanStack Query for server state
- **TypeScript**: Full type safety across contracts and UI

## Getting Started

### Prerequisites

- Node.js 18+
- npm or yarn
- A Wallet Connect project ID

### Installation

1. Clone the repository and navigate to the frontend directory:
```bash
cd elata-protocol/frontend
npm install
```

2. Set up environment variables:
```bash
cp .env.example .env.local
# Edit .env.local with your configuration
```

3. Start the development server:
```bash
npm run dev
```

The app will be available at `http://localhost:3000`.

## Environment Variables

Create a `.env.local` file with:

```env
# Required: Wallet Connect Project ID
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=your_project_id_here

# Contract addresses for different networks
NEXT_PUBLIC_ELTA_ADDRESS_SEPOLIA=0x...
NEXT_PUBLIC_APP_FACTORY_ADDRESS_SEPOLIA=0x...
```

Get a Wallet Connect project ID from [https://cloud.walletconnect.com/](https://cloud.walletconnect.com/).

## Local Development with Anvil

For local testing with Anvil (Foundry's local node):

1. Start Anvil in the contracts directory:
```bash
cd ../  # Go to elata-protocol root
anvil
```

2. Deploy contracts to local network:
```bash
forge script script/Deploy.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

3. Import an Anvil account into MetaMask:
   - Private key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
   - This account has test ETH and ELTA tokens

4. Connect to localhost:8545 in your wallet

## Project Structure

```
frontend/
├── src/
│   ├── app/              # Next.js App Router pages
│   ├── components/       # React components
│   ├── hooks/            # wagmi/viem hooks for contracts
│   ├── abi/              # Contract ABIs
│   ├── lib/              # Utilities and configuration
│   └── types/            # TypeScript type definitions
├── public/               # Static assets
└── package.json
```

## Key Features

### App Store Interface
- Browse all launched apps with filtering (Active/Graduated)
- View launch statistics and funding progress
- Clinical, research-grade design matching Elata brand

### App Launch Flow
1. **Create App**: Stake ELTA + pay creation fee
2. **Bonding Curve**: Fair price discovery via constant-product formula
3. **Graduation**: Auto-creation of DEX liquidity when target reached
4. **LP Locking**: 2-year lock for security and trust

### Web3 Integration
- **RainbowKit**: Wallet connection with Elata theming
- **wagmi**: Type-safe contract interactions
- **viem**: Low-level Ethereum utilities
- **Multi-chain**: Support for Ethereum, Base, and testnets

## Design System

The frontend uses the Elata design system with:

### Colors
- **Primary**: Elata Green (#607274)
- **Secondary**: Accent Red (#FF797B)
- **Background**: Off Cream (#F8F5EE)
- **Text**: Off Black (#171717)

### Typography
- **Headlines**: Montserrat (Google Fonts)
- **Body**: SF Pro fallbacks (system fonts)

### Components
- Rounded corners (xl, 2xl)
- Glass morphism effects
- Subtle animations and hover states
- Clinical, professional tone

## Contract Integration

The app integrates with:
- **AppFactory**: Create apps, view all launches
- **AppBondingCurve**: Buy tokens, check progress
- **AppToken**: Token metadata and transfers  
- **ELTA**: Approve/transfer for purchases

Contract addresses are configured per network in `src/lib/wagmi.ts`.

## Known Limitations (Local Development)

- **No Uniswap V2 Router**: Local graduation won't work without deploying a router
- **Mock Data**: App list shows mock data for demonstration
- **No Subgraph**: Uses direct contract calls (slower for many apps)

For production, deploy to a testnet with proper Uniswap infrastructure.

## Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run start` - Start production server

## Deployment

The app is designed to be deployed on Vercel at `apps.elata.bio`:

1. Connect your repository to Vercel
2. Set environment variables in Vercel dashboard
3. Deploy automatically on push to main

## Contributing

1. Follow the existing code style and component patterns
2. Use TypeScript for all new code
3. Test with local Anvil setup before submitting
4. Keep the clinical, research-focused tone in copy

## Support

For questions about the Elata App Store frontend:
- GitHub: https://github.com/Elata-Biosciences/elata-protocol
- Website: https://elata.bio