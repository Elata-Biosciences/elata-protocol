'use client';

import { useAccount } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Header } from '../../components/Header';
import { Footer } from '../../components/Footer';
import { IoWallet, IoCheckmarkCircle, IoTrendingUp, IoShieldCheckmark, IoTime, IoLockClosed, IoCash } from 'react-icons/io5';

export default function StakingPage() {
  const { isConnected } = useAccount();

  if (!isConnected) {
    return (
      <div className="min-h-screen bg-offCream">
        <Header />
        
        <main className="w-full">
          {/* Hero Section */}
          <section className="px-4 pt-12 pb-4 bg-gradient-to-br from-cream1 via-offCream to-cream2">
            <div className="max-w-6xl mx-auto text-center">
              <h1 className="font-montserrat font-bold text-4xl text-offBlack mb-6 animate-fadeInUp">
                ELTA Staking & Governance
              </h1>
              <p className="font-sf-pro text-gray3 leading-relaxed animate-fadeInUp stagger-2 max-w-4xl mx-auto">
                Connect your wallet to access ELTA staking and governance features.
              </p>
            </div>
          </section>
          
          {/* Content Section */}
          <section className="py-8 px-4">
            <div className="max-w-4xl mx-auto text-center">
              <div className="bg-white rounded-2xl p-12 shadow-lg">
                <div className="w-16 h-16 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-4">
                  <IoWallet className="w-8 h-8 text-elataGreen" />
                </div>
                <h2 className="text-2xl font-montserrat font-bold text-offBlack mb-4">
                  Connect Wallet
                </h2>
                <p className="text-gray3 mb-6 font-sf-pro">
                  Connect your wallet to access ELTA staking and governance features.
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
        <section className="px-4 pt-12 pb-4 bg-gradient-to-br from-cream1 via-offCream to-cream2">
          <div className="max-w-6xl mx-auto text-center">
            <h1 className="font-montserrat font-bold text-4xl text-offBlack mb-6 animate-fadeInUp">
              ELTA Staking & Governance
            </h1>
            <p className="font-sf-pro text-gray3 leading-relaxed animate-fadeInUp stagger-2 max-w-4xl mx-auto">
              Stake ELTA tokens to earn veELTA voting power, participate in governance decisions, 
              and receive protocol rewards. Multiple lock positions supported with flexible terms.
            </p>
          </div>
        </section>
        
        {/* Content Section */}
        <section className="py-8 px-4">
          <div className="max-w-4xl mx-auto">
            {/* Staking Requirements */}
            <div className="bg-white rounded-2xl p-8 shadow-lg mb-8">
              <h2 className="font-montserrat font-semibold text-xl text-offBlack mb-6">
                Staking Requirements
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="flex items-start space-x-3">
                  <div className="w-8 h-8 bg-elataGreen/10 rounded-full flex items-center justify-center mt-0.5">
                    <IoWallet className="w-4 h-4 text-elataGreen" />
                  </div>
                  <div>
                    <h3 className="font-montserrat font-medium text-offBlack mb-1">ELTA Tokens</h3>
                    <p className="text-sm text-gray3 font-sf-pro">Minimum 1 ELTA required to create a staking position</p>
                  </div>
                </div>
                
                <div className="flex items-start space-x-3">
                  <div className="w-8 h-8 bg-elataGreen/10 rounded-full flex items-center justify-center mt-0.5">
                    <IoTime className="w-4 h-4 text-elataGreen" />
                  </div>
                  <div>
                    <h3 className="font-montserrat font-medium text-offBlack mb-1">Lock Duration</h3>
                    <p className="text-sm text-gray3 font-sf-pro">Choose from 30 days to 4 years for maximum rewards</p>
                  </div>
                </div>
                
                <div className="flex items-start space-x-3">
                  <div className="w-8 h-8 bg-elataGreen/10 rounded-full flex items-center justify-center mt-0.5">
                    <IoTrendingUp className="w-4 h-4 text-elataGreen" />
                  </div>
                  <div>
                    <h3 className="font-montserrat font-medium text-offBlack mb-1">Voting Power</h3>
                    <p className="text-sm text-gray3 font-sf-pro">Earn veELTA for governance participation</p>
                  </div>
                </div>
                
                <div className="flex items-start space-x-3">
                  <div className="w-8 h-8 bg-elataGreen/10 rounded-full flex items-center justify-center mt-0.5">
                    <IoShieldCheckmark className="w-4 h-4 text-elataGreen" />
                  </div>
                  <div>
                    <h3 className="font-montserrat font-medium text-offBlack mb-1">Secure Locking</h3>
                    <p className="text-sm text-gray3 font-sf-pro">Non-transferable positions prevent secondary markets</p>
                  </div>
                </div>
              </div>
            </div>

            {/* Staking Process */}
            <div className="bg-white rounded-2xl p-8 shadow-lg mb-8">
              <h2 className="font-montserrat font-semibold text-xl text-offBlack mb-6">
                Staking Process
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                <div className="flex flex-col items-center text-center">
                  <IoWallet className="w-8 h-8 text-elataGreen mb-3" />
                  <h3 className="font-montserrat font-medium text-offBlack mb-1">Lock ELTA</h3>
                  <p className="text-sm text-gray3 font-sf-pro">Choose amount and duration</p>
                </div>
                
                <div className="flex flex-col items-center text-center">
                  <IoTrendingUp className="w-8 h-8 text-elataGreen mb-3" />
                  <h3 className="font-montserrat font-medium text-offBlack mb-1">Earn veELTA</h3>
                  <p className="text-sm text-gray3 font-sf-pro">Receive voting power NFT</p>
                </div>
                
                <div className="flex flex-col items-center text-center">
                  <IoShieldCheckmark className="w-8 h-8 text-elataGreen mb-3" />
                  <h3 className="font-montserrat font-medium text-offBlack mb-1">Participate</h3>
                  <p className="text-sm text-gray3 font-sf-pro">Vote on governance proposals</p>
                </div>
                
                <div className="flex flex-col items-center text-center">
                  <IoCheckmarkCircle className="w-8 h-8 text-success mb-3" />
                  <h3 className="font-montserrat font-medium text-offBlack mb-1">Earn Rewards</h3>
                  <p className="text-sm text-gray3 font-sf-pro">Receive protocol fee share</p>
                </div>
              </div>
            </div>

            {/* Staking Interface */}
            <div className="bg-white rounded-2xl p-8 shadow-lg mb-8">
              <h2 className="font-montserrat font-semibold text-xl text-offBlack mb-6">
                Stake ELTA Tokens
              </h2>
              <p className="text-gray3 mb-6 font-sf-pro">
                Lock your ELTA tokens to earn veELTA voting power and protocol rewards.
              </p>
              
              {/* Staking Form */}
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-offBlack mb-2 font-sf-pro">
                    Amount to Stake
                  </label>
                  <input
                    type="text"
                    placeholder="0.0"
                    className="w-full px-4 py-3 border-2 border-gray2 rounded-xl bg-white focus:border-elataGreen focus:ring-2 focus:ring-elataGreen/20 transition-all duration-200 font-sf-pro"
                  />
                  <p className="text-xs text-gray3 mt-1 font-sf-pro">
                    Available: 0 ELTA
                  </p>
                </div>
                
                <div>
                  <label className="block text-sm font-medium text-offBlack mb-2 font-sf-pro">
                    Lock Duration
                  </label>
                  <select className="w-full px-4 py-3 border-2 border-gray2 rounded-xl bg-white focus:border-elataGreen focus:ring-2 focus:ring-elataGreen/20 transition-all duration-200 font-sf-pro">
                    <option value="30">30 Days (1x multiplier)</option>
                    <option value="90">90 Days (1.5x multiplier)</option>
                    <option value="180">180 Days (2x multiplier)</option>
                    <option value="365">365 Days (4x multiplier)</option>
                  </select>
                </div>
                
                <button
                  disabled
                  className="w-full inline-flex items-center justify-center px-10 sm:px-16 py-4 sm:py-5 rounded-none shadow-lg font-sf-pro font-medium text-base sm:text-lg transition-all duration-300 cursor-not-allowed disabled:opacity-50"
                  style={{ backgroundColor: '#171717', color: '#FDFDFD' }}
                >
                  Staking Coming Soon
                </button>
              </div>
            </div>

            {/* Current Protocol Features */}
            <div className="bg-white rounded-2xl p-8 shadow-lg">
              <h3 className="text-xl font-montserrat font-bold text-offBlack mb-4">
                Current Protocol Features
              </h3>
              <div className="space-y-4">
                <div className="flex items-center space-x-3">
                  <div className="w-8 h-8 bg-success/10 rounded-full flex items-center justify-center">
                    <IoCheckmarkCircle className="w-4 h-4 text-success" />
                  </div>
                  <div>
                    <div className="font-medium text-offBlack">App Token Launches</div>
                    <div className="text-sm text-gray3 font-sf-pro">Permissionless app creation with bonding curves</div>
                  </div>
                </div>
                
                <div className="flex items-center space-x-3">
                  <div className="w-8 h-8 bg-warning/10 rounded-full flex items-center justify-center">
                    <IoLockClosed className="w-4 h-4 text-warning" />
                  </div>
                  <div>
                    <div className="font-medium text-offBlack">ELTA Staking (veELTA)</div>
                    <div className="text-sm text-gray3 font-sf-pro">Vote-escrowed staking system - interface coming soon</div>
                  </div>
                </div>
                
                <div className="flex items-center space-x-3">
                  <div className="w-8 h-8 bg-warning/10 rounded-full flex items-center justify-center">
                    <IoShieldCheckmark className="w-4 h-4 text-warning" />
                  </div>
                  <div>
                    <div className="font-medium text-offBlack">Governance Voting</div>
                    <div className="text-sm text-gray3 font-sf-pro">On-chain governance with timelock - interface coming soon</div>
                  </div>
                </div>
                
                <div className="flex items-center space-x-3">
                  <div className="w-8 h-8 bg-warning/10 rounded-full flex items-center justify-center">
                    <IoCash className="w-4 h-4 text-warning" />
                  </div>
                  <div>
                    <div className="font-medium text-offBlack">Rewards Distribution</div>
                    <div className="text-sm text-gray3 font-sf-pro">Protocol fee sharing - interface coming soon</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      </main>
      
      <Footer />
    </div>
  );
}