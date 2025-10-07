'use client';

import { useAccount } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Header } from '../../components/Header';
import { Footer } from '../../components/Footer';
import { useAppFactory } from '../../hooks/useAppFactory';
import { AppCard } from '../../components/AppCard';
import { useState, useEffect } from 'react';
import type { AppWithMetadata } from '../../types';

export default function MyAppsPage() {
  const { address, isConnected } = useAccount();
  const { useCreatorApps, useApp } = useAppFactory();
  const { data: creatorAppIds, isLoading: isLoadingIds } = useCreatorApps(address);
  
  const [myApps, setMyApps] = useState<AppWithMetadata[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Load app details for creator's apps
  useEffect(() => {
    if (!creatorAppIds || creatorAppIds.length === 0) {
      setMyApps([]);
      setIsLoading(false);
      return;
    }

    const loadAppDetails = async () => {
      setIsLoading(true);
      const apps: AppWithMetadata[] = [];
      
      // For now, create mock data since we don't have real apps yet
      for (let i = 0; i < creatorAppIds.length; i++) {
        const appId = Number(creatorAppIds[i]);
        const mockApp: AppWithMetadata = {
          id: appId,
          creator: address!,
          token: '0x742d35Cc6634C0532925a3b8D4C0b1f6e7E6D3f8' as const,
          curve: '0x742d35Cc6634C0532925a3b8D4C0b1f6e7E6D3f8' as const,
          pair: '0x0000000000000000000000000000000000000000' as const,
          locker: '0x0000000000000000000000000000000000000000' as const,
          createdAt: BigInt(Date.now() - Math.random() * 86400000 * 7), // Random date in last 7 days
          graduatedAt: 0n,
          graduated: Math.random() > 0.5,
          totalRaised: BigInt(Math.floor(Math.random() * 40000) * 1e18),
          finalSupply: BigInt(1000000000 * 1e18),
          metadata: {
            name: `My EEG App ${appId + 1}`,
            symbol: `MEA${appId + 1}`,
            description: `An innovative EEG/BCI application I created for ${['cognitive enhancement', 'meditation tracking', 'focus training', 'brain-computer interface'][Math.floor(Math.random() * 4)]}.`,
            imageURI: `https://api.dicebear.com/7.x/shapes/svg?seed=myapp${appId}`,
            website: `https://my-eeg-app${appId + 1}.com`,
          },
        };
        apps.push(mockApp);
      }
      
      setMyApps(apps);
      setIsLoading(false);
    };

    loadAppDetails();
  }, [creatorAppIds, address]);

  if (!isConnected) {
    return (
      <div className="min-h-screen bg-offCream">
        <Header />
        
        <main className="w-full">
        {/* Hero Section */}
        <section className="py-12 sm:py-16 px-4 bg-gradient-to-br from-cream1 via-offCream to-cream2">
          <div className="max-w-6xl mx-auto text-center">
            <h1 className="font-montserrat font-bold text-4xl text-offBlack mb-4 animate-fadeInUp">
              My Applications
            </h1>
            <p className="font-sf-pro text-gray3 leading-relaxed animate-fadeInUp stagger-2 max-w-3xl mx-auto">
              Connect your wallet to view and manage your launched EEG/BCI applications.
            </p>
          </div>
        </section>
          
          {/* Content Section */}
          <section className="py-16 px-4">
            <div className="max-w-4xl mx-auto text-center">
              <div className="bg-white rounded-2xl p-12 shadow-xl">
                <div className="w-16 h-16 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-4">
                  <svg className="w-8 h-8 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                  </svg>
                </div>
                <h2 className="text-2xl font-montserrat font-bold text-offBlack mb-4">
                  Connect Wallet
                </h2>
                <p className="text-gray3 mb-6 font-sf-pro">
                  Connect your wallet to view and manage your launched applications.
                </p>
                <ConnectButton />
              </div>
            </div>
          </section>
        </main>
        
        <Footer />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-offCream">
      <Header />
      
      <main className="w-full">
        {/* Hero Section */}
        <section className="py-12 sm:py-16 px-4 bg-gradient-to-br from-cream1 via-offCream to-cream2">
          <div className="max-w-6xl mx-auto text-center">
            <h1 className="font-montserrat font-bold text-4xl text-offBlack mb-4 animate-fadeInUp">
              My Applications
            </h1>
            <p className="font-sf-pro text-gray3 leading-relaxed animate-fadeInUp stagger-2 max-w-3xl mx-auto">
              Manage your launched EEG/BCI applications and track their performance on the Elata Protocol.
            </p>
          </div>
        </section>
        
        {/* Content Section */}
        <section className="pb-16 px-4">
          <div className="max-w-7xl mx-auto">
            {/* Stats Overview */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
              <div className="bg-white rounded-2xl p-8 shadow-xl text-center">
                <div className="text-3xl font-montserrat font-bold text-elataGreen mb-2">
                  {myApps.length}
                </div>
                <div className="text-sm text-gray3 font-sf-pro">
                  Apps Launched
                </div>
              </div>
              
              <div className="bg-white rounded-2xl p-8 shadow-xl text-center">
                <div className="text-3xl font-montserrat font-bold text-accentRed mb-2">
                  {myApps.filter(app => app.graduated).length}
                </div>
                <div className="text-sm text-gray3 font-sf-pro">
                  Graduated Apps
                </div>
              </div>
              
              <div className="bg-white rounded-2xl p-8 shadow-xl text-center">
                <div className="text-3xl font-montserrat font-bold text-elataGreen mb-2">
                  {myApps.filter(app => !app.graduated).length}
                </div>
                <div className="text-sm text-gray3 font-sf-pro">
                  Active Launches
                </div>
              </div>
            </div>

            {/* Apps List */}
            {isLoading ? (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {[...Array(3)].map((_, i) => (
                  <div key={i} className="bg-white rounded-2xl p-8 shadow-xl animate-pulse">
                    <div className="h-32 bg-cream2 rounded-xl mb-4"></div>
                    <div className="h-4 bg-cream2 rounded mb-2"></div>
                    <div className="h-6 bg-cream2 rounded mb-4"></div>
                    <div className="h-4 bg-cream2 rounded"></div>
                  </div>
                ))}
              </div>
            ) : myApps.length > 0 ? (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {myApps.map((app, index) => (
                  <AppCard 
                    key={app.id} 
                    app={app}
                    className={`animate-fadeInUp stagger-${(index % 6) + 1}`}
                  />
                ))}
              </div>
            ) : (
              <div className="bg-white rounded-2xl p-12 shadow-xl text-center">
                <div className="w-24 h-24 bg-cream2 rounded-full flex items-center justify-center mx-auto mb-6">
                  <svg className="w-12 h-12 text-gray3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                  </svg>
                </div>
                <h3 className="text-xl font-montserrat font-semibold text-offBlack mb-2">
                  No Apps Created Yet
                </h3>
                <p className="text-gray3 mb-6 font-sf-pro">
                  You haven't launched any applications yet. Create your first EEG/BCI app to get started.
                </p>
                <a
                  href="/create"
                  className="inline-flex items-center justify-center px-8 sm:px-10 py-4 font-sf-pro font-semibold text-lg rounded-none shadow-lg hover:shadow-2xl transform hover:scale-105 hover:-translate-y-2 transition-all duration-300"
                  style={{ backgroundColor: '#171717', color: '#FDFDFD' }}
                >
                  <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                  </svg>
                  Launch Your First App
                </a>
              </div>
            )}
          </div>
        </section>
      </main>
      
      <Footer />
    </div>
  );
}