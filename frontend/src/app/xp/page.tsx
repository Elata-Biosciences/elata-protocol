'use client';

import Link from 'next/link';
import { useAccount } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Header } from '../../components/Header';
import { Footer } from '../../components/Footer';
import { IoStatsChart, IoTrophy, IoFlash, IoPeople, IoCheckmarkCircle } from 'react-icons/io5';

export default function XPPage() {
  const { isConnected } = useAccount();

  if (!isConnected) {
    return (
      <div className="min-h-screen bg-offCream">
        <Header />
        
        <main className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
          <div className="text-center">
            <div className="bg-white rounded-2xl p-8 shadow-lg max-w-md mx-auto">
              <div className="w-16 h-16 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-4">
                <IoStatsChart className="w-8 h-8 text-elataGreen" />
              </div>
              <h1 className="text-2xl font-montserrat font-bold text-offBlack mb-4">
                Connect Wallet
              </h1>
              <p className="text-gray3 mb-6 font-sf-pro">
                Connect your wallet to view your ELTA XP and participation rewards.
              </p>
              <ConnectButton />
            </div>
          </div>
        </main>
        
        <Footer />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-offCream">
      <Header />
      
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Page Header */}
        <div className="mb-12">
          <h1 className="text-4xl font-montserrat font-bold text-offBlack mb-4">
            ELTA Experience Points (XP)
          </h1>
          <p className="text-lg text-gray3 font-sf-pro max-w-3xl">
            Earn XP through protocol participation and unlock additional benefits. XP rewards 
            ecosystem engagement and provides access to exclusive features and governance weight.
          </p>
        </div>

        {/* XP Overview */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 mb-12">
          <div className="bg-white rounded-2xl p-8 shadow-lg text-center">
            <div className="w-16 h-16 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-4">
              <IoStatsChart className="w-8 h-8 text-elataGreen" />
            </div>
            <div className="text-3xl font-montserrat font-bold text-elataGreen mb-2">
              1,250
            </div>
            <div className="text-sm text-gray3 font-sf-pro">
              Total XP Earned
            </div>
          </div>
          
          <div className="bg-white rounded-2xl p-8 shadow-lg text-center">
            <div className="w-16 h-16 bg-accentRed/10 rounded-full flex items-center justify-center mx-auto mb-4">
              <IoTrophy className="w-8 h-8 text-accentRed" />
            </div>
            <div className="text-3xl font-montserrat font-bold text-accentRed mb-2">
              Gold
            </div>
            <div className="text-sm text-gray3 font-sf-pro">
              Current Tier
            </div>
          </div>
          
          <div className="bg-white rounded-2xl p-8 shadow-lg text-center">
            <div className="w-16 h-16 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-4">
              <IoFlash className="w-8 h-8 text-elataGreen" />
            </div>
            <div className="text-3xl font-montserrat font-bold text-elataGreen mb-2">
              2.5x
            </div>
            <div className="text-sm text-gray3 font-sf-pro">
              Governance Multiplier
            </div>
          </div>
        </div>

        {/* XP Earning Activities */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-12">
          <div className="bg-white rounded-2xl p-8 shadow-lg">
            <h3 className="text-xl font-montserrat font-bold text-offBlack mb-6">
              How to Earn XP
            </h3>
            <div className="space-y-4">
              <div className="flex items-center space-x-4">
                <div className="w-10 h-10 bg-elataGreen/10 rounded-full flex items-center justify-center">
                  <IoCheckmarkCircle className="w-5 h-5 text-elataGreen" />
                </div>
                <div>
                  <div className="font-medium text-offBlack">Launch Apps</div>
                  <div className="text-sm text-gray3 font-sf-pro">+100 XP per app launched</div>
                </div>
              </div>
              
              <div className="flex items-center space-x-4">
                <div className="w-10 h-10 bg-elataGreen/10 rounded-full flex items-center justify-center">
                  <IoCheckmarkCircle className="w-5 h-5 text-elataGreen" />
                </div>
                <div>
                  <div className="font-medium text-offBlack">Stake ELTA</div>
                  <div className="text-sm text-gray3 font-sf-pro">+10 XP per day staked</div>
                </div>
              </div>
              
              <div className="flex items-center space-x-4">
                <div className="w-10 h-10 bg-elataGreen/10 rounded-full flex items-center justify-center">
                  <IoCheckmarkCircle className="w-5 h-5 text-elataGreen" />
                </div>
                <div>
                  <div className="font-medium text-offBlack">Governance Participation</div>
                  <div className="text-sm text-gray3 font-sf-pro">+50 XP per vote cast</div>
                </div>
              </div>
              
              <div className="flex items-center space-x-4">
                <div className="w-10 h-10 bg-elataGreen/10 rounded-full flex items-center justify-center">
                  <IoCheckmarkCircle className="w-5 h-5 text-elataGreen" />
                </div>
                <div>
                  <div className="font-medium text-offBlack">ZORP Participation</div>
                  <div className="text-sm text-gray3 font-sf-pro">+25 XP per data submission</div>
                </div>
              </div>
            </div>
          </div>
          
          <div className="bg-white rounded-2xl p-8 shadow-lg">
            <h3 className="text-xl font-montserrat font-bold text-offBlack mb-6">
              XP Tier Benefits
            </h3>
            <div className="space-y-6">
              <div>
                <div className="flex items-center space-x-2 mb-2">
                  <div className="w-4 h-4 rounded-full" style={{ backgroundColor: '#CD7F32' }}></div>
                  <span className="font-medium text-offBlack">Bronze (0-500 XP)</span>
                </div>
                <p className="text-sm text-gray3 font-sf-pro ml-6">Basic protocol access</p>
              </div>
              
              <div>
                <div className="flex items-center space-x-2 mb-2">
                  <div className="w-4 h-4 rounded-full" style={{ backgroundColor: '#C0C0C0' }}></div>
                  <span className="font-medium text-offBlack">Silver (500-1000 XP)</span>
                </div>
                <p className="text-sm text-gray3 font-sf-pro ml-6">1.5x governance weight</p>
              </div>
              
              <div>
                <div className="flex items-center space-x-2 mb-2">
                  <div className="w-4 h-4 rounded-full" style={{ backgroundColor: '#FFD700' }}></div>
                  <span className="font-medium text-offBlack">Gold (1000+ XP)</span>
                </div>
                <p className="text-sm text-gray3 font-sf-pro ml-6">2.5x governance weight + exclusive features</p>
              </div>
            </div>
          </div>
        </div>

        {/* Coming Soon Notice */}
        <div className="bg-white rounded-2xl p-12 shadow-lg text-center">
          <div className="w-20 h-20 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-6">
            <IoStatsChart className="w-10 h-10 text-elataGreen" />
          </div>
          <h2 className="text-3xl font-montserrat font-bold text-offBlack mb-4">
            XP System Coming Soon
          </h2>
          <p className="text-lg text-gray3 mb-8 font-sf-pro max-w-2xl mx-auto">
            The ELTA XP system is currently in development. Track your participation, 
            earn rewards, and unlock governance benefits through protocol engagement.
          </p>
          
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Link
              href="/create"
              className="inline-flex items-center justify-center px-6 sm:px-8 py-3 font-sf-pro font-medium rounded-xl sm:rounded-none shadow-lg hover:shadow-xl transform hover:scale-105 hover:-translate-y-1 transition-all duration-300"
              style={{ backgroundColor: '#171717', color: '#FDFDFD' }}
            >
              Start Earning XP
            </Link>
            <Link
              href="/staking"
              className="inline-flex items-center justify-center px-6 sm:px-8 py-3 bg-white text-offBlack font-sf-pro font-medium rounded-full shadow-lg hover:shadow-xl hover:bg-gray1/20 transform hover:scale-105 hover:-translate-y-1 transition-all duration-300"
            >
              Learn About Staking
            </Link>
          </div>
        </div>
      </main>
      
      <Footer />
    </div>
  );
}
