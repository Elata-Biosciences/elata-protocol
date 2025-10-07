'use client';

import { useState, useEffect } from 'react';
import { useAppFactory } from '../hooks/useAppFactory';
import { AppCard } from './AppCard';
import type { AppWithMetadata } from '../types';

export function AppList() {
  const { useAppCount, useApp } = useAppFactory();
  const { data: appCount, isLoading: isLoadingCount } = useAppCount();
  const [apps, setApps] = useState<AppWithMetadata[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | 'active' | 'graduated'>('all');

  // Load all apps
  useEffect(() => {
    if (!appCount || appCount === 0n) {
      setApps([]);
      setIsLoading(false);
      return;
    }

    const loadApps = async () => {
      setIsLoading(true);
      const loadedApps: AppWithMetadata[] = [];
      
      // For now, we'll load the first few apps
      const count = Number(appCount);
      const maxApps = Math.min(count, 20); // Load max 20 apps for performance
      
      for (let i = 0; i < maxApps; i++) {
        try {
          // In a real implementation, we'd batch these calls or use a subgraph
          // For now, we'll create mock data to demonstrate the UI
          const mockApp: AppWithMetadata = {
            id: i,
            creator: '0x742d35Cc6634C0532925a3b8D4C0b1f6e7E6D3f8' as const,
            token: '0x742d35Cc6634C0532925a3b8D4C0b1f6e7E6D3f8' as const,
            curve: '0x742d35Cc6634C0532925a3b8D4C0b1f6e7E6D3f8' as const,
            pair: '0x0000000000000000000000000000000000000000' as const,
            locker: '0x0000000000000000000000000000000000000000' as const,
            createdAt: BigInt(Date.now() - Math.random() * 86400000 * 30), // Random date in last 30 days
            graduatedAt: 0n,
            graduated: Math.random() > 0.7, // 30% graduated
            totalRaised: BigInt(Math.floor(Math.random() * 40000) * 1e18), // Random amount up to 40k
            finalSupply: BigInt(1000000000 * 1e18), // 1B tokens
            metadata: {
              name: `EEG App ${i + 1}`,
              symbol: `EEG${i + 1}`,
              description: `A revolutionary EEG/BCI application that ${['enhances cognitive performance', 'monitors brain states', 'enables neural control', 'provides biofeedback'][Math.floor(Math.random() * 4)]}.`,
              imageURI: `https://api.dicebear.com/7.x/shapes/svg?seed=app${i}`,
              website: `https://eegapp${i + 1}.example.com`,
            },
          };
          
          loadedApps.push(mockApp);
        } catch (error) {
          console.error(`Failed to load app ${i}:`, error);
        }
      }
      
      setApps(loadedApps);
      setIsLoading(false);
    };

    loadApps();
  }, [appCount]);

  const filteredApps = apps.filter(app => {
    switch (filter) {
      case 'active':
        return !app.graduated;
      case 'graduated':
        return app.graduated;
      default:
        return true;
    }
  });

  if (isLoadingCount || isLoading) {
    return (
      <div className="space-y-6">
        {/* Filter buttons skeleton */}
        <div className="flex space-x-4">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="h-10 w-20 bg-cream2 rounded-full animate-pulse"></div>
          ))}
        </div>
        
        {/* App cards skeleton */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {[...Array(6)].map((_, i) => (
            <div key={i} className="card animate-pulse">
              <div className="h-4 bg-cream2 rounded mb-4"></div>
              <div className="h-6 bg-cream2 rounded mb-2"></div>
              <div className="h-4 bg-cream2 rounded mb-4"></div>
              <div className="h-2 bg-cream2 rounded mb-2"></div>
              <div className="h-8 bg-cream2 rounded"></div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (!apps.length) {
    return (
      <div className="bg-white rounded-2xl p-12 shadow-xl text-center">
        <div className="w-24 h-24 bg-cream2 rounded-full flex items-center justify-center mx-auto mb-6">
          <svg className="w-12 h-12 text-gray3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
          </svg>
        </div>
        <h3 className="font-montserrat font-semibold text-offBlack mb-2">
          No Apps Yet
        </h3>
        <p className="text-gray3 mb-6">
          Be the first to launch an EEG/BCI application on the Elata App Store.
        </p>
        <a
          href="/create"
          className="inline-flex items-center justify-center px-8 sm:px-10 py-4 font-sf-pro font-semibold text-lg rounded-none shadow-lg hover:shadow-2xl transform hover:scale-105 hover:-translate-y-2 transition-all duration-300"
          style={{ backgroundColor: '#171717', color: '#FDFDFD' }}
        >
          <svg className="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
          </svg>
          Launch First App
        </a>
      </div>
    );
  }

  return (
    <div className="space-y-6" id="apps">
      {/* Filter Buttons */}
      <div className="flex flex-wrap gap-3">
        <button
          onClick={() => setFilter('all')}
          className={`px-4 py-2 rounded-full text-sm font-medium transition-all duration-200 ${
            filter === 'all'
              ? 'bg-elataGreen text-white'
              : 'bg-cream2 text-gray3 hover:bg-cream1'
          }`}
        >
          All Apps ({apps.length})
        </button>
        <button
          onClick={() => setFilter('active')}
          className={`px-4 py-2 rounded-full text-sm font-medium transition-all duration-200 ${
            filter === 'active'
              ? 'bg-elataGreen text-white'
              : 'bg-cream2 text-gray3 hover:bg-cream1'
          }`}
        >
          Active ({apps.filter(app => !app.graduated).length})
        </button>
        <button
          onClick={() => setFilter('graduated')}
          className={`px-4 py-2 rounded-full text-sm font-medium transition-all duration-200 ${
            filter === 'graduated'
              ? 'bg-elataGreen text-white'
              : 'bg-cream2 text-gray3 hover:bg-cream1'
          }`}
        >
          Graduated ({apps.filter(app => app.graduated).length})
        </button>
      </div>

      {/* App Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {filteredApps.map((app, index) => (
          <AppCard 
            key={app.id} 
            app={app}
            className={`animate-fadeInUp animate-stagger-${(index % 4) + 1}`}
          />
        ))}
      </div>

      {filteredApps.length === 0 && (
        <div className="bg-white rounded-2xl p-8 shadow-xl text-center">
          <p className="text-gray3">
            No {filter === 'all' ? '' : filter} apps found.
          </p>
        </div>
      )}
    </div>
  );
}
