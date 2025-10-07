'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { WagmiProvider } from 'wagmi';
import { RainbowKitProvider, lightTheme, Theme } from '@rainbow-me/rainbowkit';
import merge from 'lodash.merge';
import { config } from '../lib/wagmi';
import '@rainbow-me/rainbowkit/styles.css';

const queryClient = new QueryClient();

// ZORP-style RainbowKit theme
const theme = merge(lightTheme(), {
  colors: {
    accentColor: '#171717',
    accentColorForeground: '#FDFDFD',
    actionButtonSecondaryBackground: '#DADDD8',
    connectButtonBackground: '#171717',
    connectButtonBackgroundError: '#FF494A',
    connectButtonInnerBackground: '#171717',
    connectButtonText: '#FDFDFD',
    connectButtonTextError: '#FDFDFD',
  },
} as Theme);

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={theme} showRecentTransactions={true}>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
