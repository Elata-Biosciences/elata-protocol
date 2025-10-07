'use client';

import { useAppFactory } from '../hooks/useAppFactory';
import { formatEther } from 'viem';

export function LaunchStats() {
  const { useLaunchStats } = useAppFactory();
  const { data: stats, isLoading, error } = useLaunchStats();

  if (isLoading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="bg-white rounded-2xl p-6 shadow-lg animate-pulse">
            <div className="h-4 bg-cream2 rounded mb-2"></div>
            <div className="h-8 bg-cream2 rounded"></div>
          </div>
        ))}
      </div>
    );
  }

  if (error || !stats) {
    return (
      <div className="bg-white rounded-2xl p-6 shadow-lg text-center">
        <p className="text-gray3">Unable to load launch statistics</p>
      </div>
    );
  }

  const [totalApps, graduatedApps, totalValueLocked, totalFeesCollected] = stats;

  const statItems = [
    {
      label: 'Total Apps',
      value: totalApps.toString(),
      description: 'Apps launched on the platform',
      color: 'text-elataGreen',
    },
    {
      label: 'Graduated Apps',
      value: graduatedApps.toString(),
      description: 'Apps with DEX liquidity',
      color: 'text-accentRed',
    },
    {
      label: 'Total Value Locked',
      value: `${parseFloat(formatEther(totalValueLocked)).toLocaleString()} ELTA`,
      description: 'ELTA raised across all apps',
      color: 'text-elataGreen',
    },
    {
      label: 'Protocol Fees',
      value: `${parseFloat(formatEther(totalFeesCollected)).toLocaleString()} ELTA`,
      description: 'Fees collected by protocol',
      color: 'text-gray3',
    },
  ];

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
      {statItems.map((item, index) => (
        <div 
          key={item.label}
          className={`bg-white rounded-2xl p-6 shadow-lg text-center animate-fadeInUp animate-stagger-${index + 1}`}
        >
          <p className="text-sm text-gray3 font-sf-pro mb-1">
            {item.label}
          </p>
          <p className={`text-2xl font-montserrat font-bold mb-2 ${item.color}`}>
            {item.value}
          </p>
          <p className="text-xs text-gray3 font-sf-pro">
            {item.description}
          </p>
        </div>
      ))}
    </div>
  );
}
