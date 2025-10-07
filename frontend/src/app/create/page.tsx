'use client';

import { useState } from 'react';
import { Header } from '../../components/Header';
import { Footer } from '../../components/Footer';
import { CreateAppForm } from '../../components/CreateAppForm';
import { useAccount } from 'wagmi';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { IoRocket, IoTrendingUp, IoCheckmarkCircle, IoWallet } from 'react-icons/io5';

export default function CreateAppPage() {
  const { isConnected } = useAccount();

  return (
    <div className="min-h-screen bg-offCream">
      <Header />
      
      <main className="w-full">
        {/* Hero Section */}
        <section className="px-4 pt-12 pb-4 bg-gradient-to-br from-cream1 via-offCream to-cream2">
          <div className="max-w-6xl mx-auto text-center">
            <h1 className="font-montserrat font-bold text-4xl text-offBlack mb-6 animate-fadeInUp">
              Launch Your EEG/BCI App
            </h1>
            <p className="font-sf-pro text-gray3 leading-relaxed animate-fadeInUp stagger-2 max-w-4xl mx-auto">
              Create a new tokenized application with fair bonding-curve distribution. 
              Your app will integrate with Elata's BOS and ZORP infrastructure for 
              scientific research and data collection.
            </p>
          </div>
        </section>
        
        {/* Content Section */}
        <section className="py-8 px-4">
          <div className="max-w-4xl mx-auto">
            {/* Requirements Section */}
            <div className="bg-white rounded-2xl p-8 shadow-lg mb-8">
              <h2 className="font-montserrat font-semibold text-xl text-offBlack mb-6">
                Launch Requirements
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="flex items-start space-x-3">
                  <div className="w-8 h-8 bg-elataGreen/10 rounded-full flex items-center justify-center mt-0.5">
                    <svg className="w-4 h-4 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                  <div>
                    <h3 className="font-montserrat font-medium text-offBlack mb-1">Seed Liquidity</h3>
                    <p className="text-sm text-gray3 font-sf-pro">100 ELTA required to seed initial bonding curve</p>
                  </div>
                </div>
                
                <div className="flex items-start space-x-3">
                  <div className="w-8 h-8 bg-elataGreen/10 rounded-full flex items-center justify-center mt-0.5">
                    <svg className="w-4 h-4 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                  <div>
                    <h3 className="font-montserrat font-medium text-offBlack mb-1">Creation Fee</h3>
                    <p className="text-sm text-gray3 font-sf-pro">10 ELTA platform fee for app registration</p>
                  </div>
                </div>
                
                <div className="flex items-start space-x-3">
                  <div className="w-8 h-8 bg-elataGreen/10 rounded-full flex items-center justify-center mt-0.5">
                    <svg className="w-4 h-4 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                  <div>
                    <h3 className="font-montserrat font-medium text-offBlack mb-1">Fair Distribution</h3>
                    <p className="text-sm text-gray3 font-sf-pro">Bonding curve ensures fair price discovery</p>
                  </div>
                </div>
                
                <div className="flex items-start space-x-3">
                  <div className="w-8 h-8 bg-elataGreen/10 rounded-full flex items-center justify-center mt-0.5">
                    <svg className="w-4 h-4 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                  <div>
                    <h3 className="font-montserrat font-medium text-offBlack mb-1">Locked Liquidity</h3>
                    <p className="text-sm text-gray3 font-sf-pro">LP tokens locked for 2 years after graduation</p>
                  </div>
                </div>
              </div>
            </div>

            {/* Launch Process */}
            <div className="bg-white rounded-2xl p-8 shadow-lg mb-8">
              <h2 className="font-montserrat font-semibold text-xl text-offBlack mb-6">
                Launch Process
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                <div className="flex flex-col items-center text-center">
                  <IoRocket className="w-8 h-8 text-elataGreen mb-3" />
                  <h3 className="font-montserrat font-medium text-offBlack mb-1">Create App</h3>
                  <p className="text-sm text-gray3 font-sf-pro">Deploy token & bonding curve</p>
                </div>
                
                <div className="flex flex-col items-center text-center">
                  <IoTrendingUp className="w-8 h-8 text-elataGreen mb-3" />
                  <h3 className="font-montserrat font-medium text-offBlack mb-1">Fair Sale</h3>
                  <p className="text-sm text-gray3 font-sf-pro">Users buy via bonding curve</p>
                </div>
                
                <div className="flex flex-col items-center text-center">
                  <IoCheckmarkCircle className="w-8 h-8 text-elataGreen mb-3" />
                  <h3 className="font-montserrat font-medium text-offBlack mb-1">Graduation</h3>
                  <p className="text-sm text-gray3 font-sf-pro">Auto DEX liquidity at 42k ELTA</p>
                </div>
                
                <div className="flex flex-col items-center text-center">
                  <IoWallet className="w-8 h-8 text-success mb-3" />
                  <h3 className="font-montserrat font-medium text-offBlack mb-1">Live Trading</h3>
                  <p className="text-sm text-gray3 font-sf-pro">Locked LP, secure trading</p>
                </div>
              </div>
            </div>

            {/* Create Form or Connect Wallet */}
            {isConnected ? (
              <CreateAppForm />
            ) : (
              <div className="bg-white rounded-2xl p-12 shadow-lg text-center">
                <div className="w-16 h-16 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-4">
                  <svg className="w-8 h-8 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                  </svg>
                </div>
                <h3 className="font-montserrat font-semibold text-offBlack mb-2">
                  Connect Wallet to Continue
                </h3>
                <p className="text-gray3 mb-6">
                  You need to connect your wallet to launch a new app on the Elata platform.
                </p>
                <ConnectButton />
              </div>
            )}
          </div>
        </section>
      </main>
      
      <Footer />
    </div>
  );
}