'use client';

import Link from 'next/link';
import Image from 'next/image';
import { formatEther } from 'viem';
import type { AppWithMetadata } from '../types';

interface AppCardProps {
  app: AppWithMetadata;
  className?: string;
}

export function AppCard({ app, className = '' }: AppCardProps) {
  const progress = app.graduated ? 100 : Math.min((Number(app.totalRaised) / (42000 * 1e18)) * 100, 100);
  const totalRaisedFormatted = parseFloat(formatEther(app.totalRaised)).toLocaleString();
  const targetFormatted = '42,000'; // From contract default
  
  return (
    <Link href={`/app/${app.id}`}>
      <div className={`card group cursor-pointer h-full ${className}`}>
        {/* App Image */}
        <div className="relative w-full h-32 mb-4 rounded-xl overflow-hidden bg-cream1">
          <Image
            src={app.metadata.imageURI}
            alt={app.metadata.name}
            fill
            className="object-cover group-hover:scale-105 transition-transform duration-300"
            onError={(e) => {
              // Fallback to gradient background
              const target = e.target as HTMLImageElement;
              target.style.display = 'none';
            }}
          />
          {/* Fallback gradient */}
          <div className="absolute inset-0 bg-gradient-to-br from-elataGreen/20 to-accentRed/20 flex items-center justify-center">
            <span className="text-2xl font-montserrat font-bold text-elataGreen">
              {app.metadata.symbol}
            </span>
          </div>
          
          {/* Status Badge */}
          <div className="absolute top-3 right-3">
            <span className={`px-2 py-1 text-xs font-medium rounded-full ${
              app.graduated 
                ? 'bg-success text-white' 
                : 'bg-elataGreen text-white'
            }`}>
              {app.graduated ? 'Graduated' : 'Active'}
            </span>
          </div>
        </div>

        {/* App Info */}
        <div className="flex-1">
          <h3 className="font-montserrat font-bold text-lg text-offBlack mb-2 group-hover:text-elataGreen transition-colors">
            {app.metadata.name}
          </h3>
          
          <p className="text-sm text-gray3 mb-4 line-clamp-2 font-sf-pro">
            {app.metadata.description}
          </p>

          {/* Progress Section */}
          {!app.graduated ? (
            <div className="mb-4">
              <div className="flex justify-between items-center mb-2">
                <span className="text-xs text-gray3 font-sf-pro">
                  Funding Progress
                </span>
                <span className="text-xs font-medium text-elataGreen">
                  {progress.toFixed(1)}%
                </span>
              </div>
              
              <div className="w-full bg-cream2 rounded-full h-2 mb-2">
                <div 
                  className="bg-gradient-to-r from-elataGreen to-accentRed h-2 rounded-full transition-all duration-500"
                  style={{ width: `${Math.max(progress, 2)}%` }}
                />
              </div>
              
              <div className="flex justify-between text-xs text-gray3 font-sf-pro">
                <span>{totalRaisedFormatted} ELTA raised</span>
                <span>{targetFormatted} ELTA target</span>
              </div>
            </div>
          ) : (
            <div className="mb-4 p-3 bg-success/10 rounded-lg">
              <div className="flex items-center space-x-2">
                <svg className="w-4 h-4 text-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
                <span className="text-sm font-medium text-success">
                  Successfully Graduated
                </span>
              </div>
              <p className="text-xs text-success/80 mt-1">
                {totalRaisedFormatted} ELTA raised • LP tokens locked
              </p>
            </div>
          )}

          {/* Creator & Date */}
          <div className="flex items-center justify-between text-xs text-gray3 font-sf-pro">
            <span>
              {app.creator.slice(0, 6)}...{app.creator.slice(-4)}
            </span>
            <span>
              {new Date(Number(app.createdAt)).toLocaleDateString()}
            </span>
          </div>
        </div>

        {/* Action Button */}
        <div className="mt-4 pt-4 border-t border-cream2">
          {app.graduated ? (
            <div className="flex space-x-2">
              <button className="flex-1 bg-cream2 text-offBlack py-2 px-4 rounded-lg text-sm font-medium hover:bg-cream1 transition-colors">
                View Details
              </button>
              <button className="flex-1 bg-elataGreen text-white py-2 px-4 rounded-lg text-sm font-medium hover:bg-elataGreen/90 transition-colors">
                Trade on DEX
              </button>
            </div>
          ) : (
            <button className="w-full bg-elataGreen text-white py-2 px-4 rounded-lg text-sm font-medium hover:bg-elataGreen/90 transition-colors">
              Buy Tokens
            </button>
          )}
        </div>
      </div>
    </Link>
  );
}


