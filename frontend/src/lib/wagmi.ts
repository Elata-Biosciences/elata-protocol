import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import {
  arbitrum,
  base,
  mainnet,
  polygon,
  sepolia,
  baseSepolia,
} from 'wagmi/chains';
import { http } from 'viem';

// Define localhost chain for development
export const localhost = {
  id: 31337,
  name: 'Localhost',
  network: 'localhost',
  nativeCurrency: {
    decimals: 18,
    name: 'Ether',
    symbol: 'ETH',
  },
  rpcUrls: {
    default: {
      http: ['http://127.0.0.1:8545'],
    },
    public: {
      http: ['http://127.0.0.1:8545'],
    },
  },
} as const;

export const config = getDefaultConfig({
  appName: 'Elata App Store',
  projectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID || 'YOUR_PROJECT_ID',
  chains: [
    mainnet,
    polygon,
    arbitrum,
    base,
    ...(process.env.NODE_ENV === 'development' ? [localhost, sepolia, baseSepolia] : []),
  ],
  transports: {
    [mainnet.id]: http(),
    [polygon.id]: http(),
    [arbitrum.id]: http(),
    [base.id]: http(),
    [sepolia.id]: http(),
    [baseSepolia.id]: http(),
    [localhost.id]: http(),
  },
  ssr: true,
});

// Contract addresses - these will be updated with actual deployed addresses
export const CONTRACT_ADDRESSES = {
  // Localhost/Development
  31337: {
    ELTA: '0x5FbDB2315678afecb367f032d93F642f64180aa3',
    AppFactory: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
    UniswapV2Router: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  },
  // Ethereum Mainnet (placeholder - not deployed yet)
  1: {
    ELTA: process.env.NEXT_PUBLIC_ELTA_ADDRESS_MAINNET || '',
    AppFactory: process.env.NEXT_PUBLIC_APP_FACTORY_ADDRESS_MAINNET || '',
    UniswapV2Router: '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // Uniswap V2 Router
  },
  // Sepolia Testnet
  11155111: {
    ELTA: process.env.NEXT_PUBLIC_ELTA_ADDRESS_SEPOLIA || '',
    AppFactory: process.env.NEXT_PUBLIC_APP_FACTORY_ADDRESS_SEPOLIA || '',
    UniswapV2Router: '0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008', // Sepolia Uniswap V2
  },
  // Base Sepolia
  84532: {
    ELTA: process.env.NEXT_PUBLIC_ELTA_ADDRESS_BASE_SEPOLIA || '',
    AppFactory: process.env.NEXT_PUBLIC_APP_FACTORY_ADDRESS_BASE_SEPOLIA || '',
    UniswapV2Router: '0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24', // Base Sepolia Uniswap V2
  },
  // Base Mainnet
  8453: {
    ELTA: process.env.NEXT_PUBLIC_ELTA_ADDRESS_BASE || '',
    AppFactory: process.env.NEXT_PUBLIC_APP_FACTORY_ADDRESS_BASE || '',
    UniswapV2Router: '0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24', // Base Uniswap V2
  },
} as const;

export type ChainId = keyof typeof CONTRACT_ADDRESSES;

export function getContractAddress(chainId: number, contract: keyof typeof CONTRACT_ADDRESSES[ChainId]) {
  const addresses = CONTRACT_ADDRESSES[chainId as ChainId];
  if (!addresses) {
    console.warn(`Unsupported chain ID: ${chainId}, falling back to localhost`);
    return CONTRACT_ADDRESSES[31337][contract]; // Fallback to localhost
  }
  return addresses[contract];
}
