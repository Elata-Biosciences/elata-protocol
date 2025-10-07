'use client';

import Link from 'next/link';
import Image from 'next/image';
import { usePathname } from 'next/navigation';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount } from 'wagmi';

export function Header() {
  const { isConnected } = useAccount();
  const pathname = usePathname();

  return (
    <header className="px-6 md:px-8 bg-offCream/95 backdrop-blur-md shadow-sm sticky top-0 z-50">
      <nav className="flex items-center justify-between mx-auto max-w-7xl h-16">
        {/* Logo with Elata branding */}
        <Link href="/" className="flex items-center space-x-3 group">
          <Image
            src="/logotype.png"
            alt="Elata Protocol"
            width={120}
            height={40}
            priority
            className="transition-all duration-300 group-hover:opacity-80 group-hover:scale-105"
          />
        </Link>

        {/* Desktop Navigation */}
        <div className="hidden md:flex items-center space-x-8">
          <Link
            href="/"
            className={`transition-colors duration-200 font-sf-pro ${
              pathname === '/' 
                ? 'text-offBlack font-bold' 
                : 'text-gray3 hover:text-offBlack font-medium'
            }`}
          >
            Browse Apps
          </Link>
          <Link
            href="/create"
            className={`transition-colors duration-200 font-sf-pro ${
              pathname === '/create' 
                ? 'text-offBlack font-bold' 
                : 'text-gray3 hover:text-offBlack font-medium'
            }`}
          >
            Launch App
          </Link>
          <Link
            href="/staking"
            className={`transition-colors duration-200 font-sf-pro ${
              pathname === '/staking' 
                ? 'text-offBlack font-bold' 
                : 'text-gray3 hover:text-offBlack font-medium'
            }`}
          >
            Staking
          </Link>
          <Link
            href="/xp"
            className={`transition-colors duration-200 font-sf-pro ${
              pathname === '/xp' 
                ? 'text-offBlack font-bold' 
                : 'text-gray3 hover:text-offBlack font-medium'
            }`}
          >
            XP
          </Link>
          {isConnected && (
            <Link
              href="/my-apps"
              className={`transition-colors duration-200 font-sf-pro ${
                pathname === '/my-apps' 
                  ? 'text-offBlack font-bold' 
                  : 'text-gray3 hover:text-offBlack font-medium'
              }`}
            >
              My Apps
            </Link>
          )}
          <Link
            href="https://github.com/Elata-Biosciences/elata-protocol"
            className="text-gray3 hover:text-offBlack font-medium transition-colors duration-200 font-sf-pro"
            target="_blank"
            rel="noopener noreferrer"
          >
            Documentation
          </Link>
        </div>

        {/* Connect Button */}
        <div className="flex items-center">
          <ConnectButton.Custom>
            {({
              account,
              chain,
              openAccountModal,
              openChainModal,
              openConnectModal,
              authenticationStatus,
              mounted,
            }) => {
              const ready = mounted && authenticationStatus !== 'loading';
              const connected =
                ready &&
                account &&
                chain &&
                (!authenticationStatus ||
                  authenticationStatus === 'authenticated');

              return (
                <div
                  {...(!ready && {
                    'aria-hidden': true,
                    style: {
                      opacity: 0,
                      pointerEvents: 'none',
                      userSelect: 'none',
                    },
                  })}
                >
                  {(() => {
                    if (!connected) {
                      return (
                        <button
                          onClick={openConnectModal}
                          type="button"
                          className="px-6 py-2 bg-white text-offBlack font-sf-pro font-medium rounded-full shadow-lg hover:shadow-xl hover:bg-gray1/20 transform hover:scale-105 transition-all duration-300"
                        >
                          Connect Wallet
                        </button>
                      );
                    }

                    if (chain.unsupported) {
                      return (
                        <button
                          onClick={openChainModal}
                          type="button"
                          className="px-6 py-2 bg-accentRed text-white font-sf-pro font-medium rounded-full shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-300"
                        >
                          Wrong network
                        </button>
                      );
                    }

                    return (
                      <button
                        onClick={openAccountModal}
                        type="button"
                        className="px-3 py-2 bg-white text-offBlack font-sf-pro font-medium text-sm rounded-full hover:bg-gray1/20 transition-all duration-300 max-w-24 truncate"
                      >
                        {account.displayName}
                      </button>
                    );
                  })()}
                </div>
              );
            }}
          </ConnectButton.Custom>
        </div>
      </nav>

      {/* Mobile Navigation */}
      <div className="md:hidden bg-offCream/90 backdrop-blur-sm">
        <nav className="max-w-7xl mx-auto px-4 py-3">
          <div className="flex items-center justify-around">
            <Link
              href="/"
              className="text-gray3 hover:text-offBlack font-medium text-sm transition-colors duration-200 font-sf-pro"
            >
              Browse
            </Link>
            <Link
              href="/create"
              className="text-gray3 hover:text-offBlack font-medium text-sm transition-colors duration-200 font-sf-pro"
            >
              Launch
            </Link>
            <Link
              href="/staking"
              className="text-gray3 hover:text-offBlack font-medium text-sm transition-colors duration-200 font-sf-pro"
            >
              Staking
            </Link>
            <Link
              href="/xp"
              className="text-gray3 hover:text-offBlack font-medium text-sm transition-colors duration-200 font-sf-pro"
            >
              XP
            </Link>
            {isConnected && (
              <Link
                href="/my-apps"
                className="text-gray3 hover:text-offBlack font-medium text-sm transition-colors duration-200 font-sf-pro"
              >
                My Apps
              </Link>
            )}
          </div>
        </nav>
      </div>
    </header>
  );
}
