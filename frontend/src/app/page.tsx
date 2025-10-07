'use client';

import { Header } from '../components/Header';
import { Footer } from '../components/Footer';
import { AppList } from '../components/AppList';
import { LaunchStats } from '../components/LaunchStats';
import { HeroSection } from '../components/HeroSection';

export default function Home() {
  return (
    <div className="min-h-screen bg-offCream">
      <Header />
      
      <main className="w-full">
        {/* Hero Section */}
        <HeroSection />
        
        {/* Protocol Overview Section */}
        <section className="py-12 sm:py-20 px-4 sm:px-6 bg-cream2">
          <div className="max-w-6xl mx-auto">
            <h3 className="text-2xl sm:text-3xl md:text-4xl font-bold font-montserrat text-center text-offBlack mb-8 sm:mb-12 animate-fadeInUp px-2">
              The Complete Elata Protocol
            </h3>
            <p className="text-lg text-gray3 mb-12 font-sf-pro leading-relaxed text-center max-w-4xl mx-auto">
              Onchain economics for the Internet of Brains. The Elata Protocol provides foundational 
              infrastructure for neuroscience applications, research funding, and decentralized governance.
            </p>
            
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
              <div className="bg-white rounded-2xl p-6 shadow-lg hover:shadow-2xl transform hover:scale-105 hover:-translate-y-3 transition-all duration-500">
                <div className="w-16 h-16 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-4">
                  <svg className="w-6 h-6 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                  </svg>
                </div>
                <h3 className="font-montserrat font-semibold text-offBlack mb-2 text-center">App Launches</h3>
                <p className="text-sm text-gray3 font-sf-pro text-center">Permissionless token launches with bonding curves</p>
              </div>
              
              <div className="bg-white rounded-2xl p-6 shadow-lg hover:shadow-2xl transform hover:scale-105 hover:-translate-y-3 transition-all duration-500">
                <div className="w-12 h-12 bg-accentRed/10 rounded-full flex items-center justify-center mx-auto mb-4">
                  <svg className="w-6 h-6 text-accentRed" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                  </svg>
                </div>
                <h3 className="font-montserrat font-semibold text-offBlack mb-2 text-center">ELTA Staking</h3>
                <p className="text-sm text-gray3 font-sf-pro text-center">Vote-escrowed staking for governance power</p>
              </div>
              
              <div className="bg-white rounded-2xl p-6 shadow-lg hover:shadow-2xl transform hover:scale-105 hover:-translate-y-3 transition-all duration-500">
                <div className="w-12 h-12 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-4">
                  <svg className="w-6 h-6 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4M7.835 4.697a3.42 3.42 0 001.946-.806 3.42 3.42 0 014.438 0 3.42 3.42 0 001.946.806 3.42 3.42 0 013.138 3.138 3.42 3.42 0 00.806 1.946 3.42 3.42 0 010 4.438 3.42 3.42 0 00-.806 1.946 3.42 3.42 0 01-3.138 3.138 3.42 3.42 0 00-1.946.806 3.42 3.42 0 01-4.438 0 3.42 3.42 0 00-1.946-.806 3.42 3.42 0 01-3.138-3.138 3.42 3.42 0 00-.806-1.946 3.42 3.42 0 010-4.438 3.42 3.42 0 00.806-1.946 3.42 3.42 0 013.138-3.138z" />
                  </svg>
                </div>
                <h3 className="font-montserrat font-semibold text-offBlack mb-2 text-center">Governance</h3>
                <p className="text-sm text-gray3 font-sf-pro text-center">Decentralized protocol governance with timelock</p>
              </div>
              
              <div className="bg-white rounded-2xl p-6 shadow-lg hover:shadow-2xl transform hover:scale-105 hover:-translate-y-3 transition-all duration-500">
                <div className="w-12 h-12 bg-accentRed/10 rounded-full flex items-center justify-center mx-auto mb-4">
                  <svg className="w-6 h-6 text-accentRed" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1" />
                  </svg>
                </div>
                <h3 className="font-montserrat font-semibold text-offBlack mb-2 text-center">Rewards</h3>
                <p className="text-sm text-gray3 font-sf-pro text-center">Protocol fee distribution and XP rewards</p>
              </div>
            </div>
          </div>
        </section>

        {/* Launch Statistics */}
        <section className="py-16 px-4">
          <div className="max-w-7xl mx-auto">
            <LaunchStats />
          </div>
        </section>
        
        {/* App Listings */}
        <section className="py-16 px-4 bg-cream1">
          <div className="max-w-7xl mx-auto">
            <div className="flex items-center justify-between mb-8">
              <div>
                <h2 className="text-3xl font-montserrat font-bold text-offBlack mb-2">
                  Live App Launches
                </h2>
                <p className="text-gray3 font-sf-pro">
                  Participate in fair bonding-curve offerings and discover new EEG/BCI applications
                </p>
              </div>
            </div>
            
            <AppList />
        </div>
        </section>
      </main>
      
      <Footer />
    </div>
  );
}