import { Address } from 'viem';

export interface App {
  creator: Address;
  token: Address;
  curve: Address;
  pair: Address;
  locker: Address;
  createdAt: bigint;
  graduatedAt: bigint;
  graduated: boolean;
  totalRaised: bigint;
  finalSupply: bigint;
}

export interface AppWithId extends App {
  id: number;
}

export interface AppMetadata {
  name: string;
  symbol: string;
  description: string;
  imageURI: string;
  website: string;
}

export interface AppWithMetadata extends AppWithId {
  metadata: AppMetadata;
}

export interface CurveState {
  eltaReserve: bigint;
  tokenReserve: bigint;
  target: bigint;
  isGraduated: boolean;
  currentPrice: bigint;
  progress: bigint; // in basis points (0-10000)
}

export interface LaunchStats {
  totalApps: bigint;
  graduatedApps: bigint;
  totalValueLocked: bigint;
  totalFeesCollected: bigint;
}

export interface CreateAppForm {
  name: string;
  symbol: string;
  supply: string; // User input as string, converted to bigint
  description: string;
  imageURI: string;
  website: string;
}

export interface BuyTokensForm {
  eltaAmount: string; // User input as string
  minTokensOut: string; // User input as string
  slippage: number; // Percentage (1-10)
}

export interface TokenBalance {
  balance: bigint;
  symbol: string;
  decimals: number;
}

export type AppStatus = 'active' | 'graduated' | 'failed';

export interface AppCardData {
  id: number;
  name: string;
  symbol: string;
  description: string;
  imageURI: string;
  website: string;
  creator: Address;
  status: AppStatus;
  progress: number; // 0-100
  currentPrice: bigint;
  totalRaised: bigint;
  target: bigint;
  createdAt: Date;
  graduatedAt?: Date;
}


