'use client';

import Link from 'next/link';
import Image from 'next/image';
import { useAccount } from 'wagmi';
import { IoRocket, IoArrowForward } from 'react-icons/io5';

export function HeroSection() {
  const { isConnected } = useAccount();

  return (
    <section className="relative min-h-screen flex items-center justify-center overflow-hidden">
      {/* ZORP-style Animated Background */}
      <div className="absolute inset-0 bg-gradient-to-br from-cream1 via-offCream to-cream2">
        
        {/* Dramatic moving gradient waves - Green & Cream Theme */}
        <div className="absolute inset-0 opacity-70">
          <div 
            className="absolute inset-0"
            style={{
              background: 'linear-gradient(45deg, rgba(96, 114, 116, 0.35) 0%, transparent 25%, rgba(96, 114, 116, 0.25) 50%, transparent 75%, rgba(96, 114, 116, 0.15) 100%)',
              animation: 'wave 6s ease-in-out infinite',
              transformOrigin: 'center'
            }}
          ></div>
          <div 
            className="absolute inset-0"
            style={{
              background: 'linear-gradient(-45deg, rgba(96, 114, 116, 0.2) 0%, transparent 30%, rgba(227, 224, 211, 0.4) 60%, transparent 100%)',
              animation: 'wave 8s ease-in-out infinite reverse',
              transformOrigin: 'center'
            }}
          ></div>
          <div 
            className="absolute inset-0"
            style={{
              background: 'linear-gradient(135deg, rgba(243, 238, 226, 0.3) 0%, transparent 35%, rgba(96, 114, 116, 0.18) 70%, transparent 100%)',
              animation: 'wave 10s ease-in-out infinite',
              transformOrigin: 'center'
            }}
          ></div>
        </div>
      </div>
      
      <div className="relative z-10 max-w-6xl mx-auto text-center px-4 sm:px-6 py-12 sm:py-20">
        {/* Logo Icon */}
        <div className="mb-8 sm:mb-12 flex justify-center animate-fadeInScale">
          <Image
            src="/logo.png"
            alt="Elata Icon"
            width={80}
            height={80}
            className="sm:w-[120px] sm:h-[120px] transition-all duration-500 hover:scale-110 drop-shadow-xl"
          />
        </div>
        
        {/* Main Title */}
        <h1 className="text-4xl sm:text-5xl md:text-6xl font-bold font-montserrat gradient-text mb-6 sm:mb-8 animate-fadeInUp">
          Elata Protocol
        </h1>
        
        {/* Subtitle */}
        <h2 className="text-xl sm:text-2xl md:text-3xl font-semibold font-montserrat text-offBlack mb-4 sm:mb-6 animate-fadeInUp stagger-2 px-2">
          Onchain Economics for the Internet of Brains
        </h2>
        
        {/* Description */}
        <p className="text-lg sm:text-xl text-gray3 max-w-4xl mx-auto mb-10 sm:mb-16 leading-relaxed animate-fadeInUp stagger-3 px-2 font-sf-pro">
          The foundational infrastructure for neuroscience applications, research funding, and 
          decentralized governance. Launch tokenized EEG/BCI applications, participate in staking 
          and governance, or contribute to scientific research through the ZORP protocol.
        </p>

        {/* CTA Buttons */}
        <div className="flex flex-col sm:flex-row gap-4 sm:gap-6 justify-center animate-fadeInUp stagger-4 px-4 mb-16">
          <Link
            href="/create"
            className="w-full sm:w-auto inline-flex items-center justify-center px-6 sm:px-8 py-3 font-sf-pro font-medium rounded-none shadow-lg hover:shadow-xl transform hover:scale-105 hover:-translate-y-1 transition-all duration-300"
            style={{ backgroundColor: '#171717', color: '#FDFDFD' }}
          >
            <IoRocket className="w-5 h-5 mr-2" />
            Start Creating
            <IoArrowForward className="w-5 h-5 ml-2" />
          </Link>
          
          <Link
            href="#apps"
            className="w-full sm:w-auto inline-flex items-center justify-center px-6 sm:px-8 py-3 bg-white text-offBlack font-sf-pro font-medium rounded-full shadow-lg hover:shadow-xl hover:bg-gray1/20 transform hover:scale-105 hover:-translate-y-1 transition-all duration-300"
          >
            Learn More
            <IoArrowForward className="w-5 h-5 ml-2" />
          </Link>
        </div>
        
        {/* Key Features */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div className="bg-white rounded-2xl p-8 shadow-lg hover:shadow-2xl hover:-translate-y-2 hover:scale-105 transition-all duration-500 animate-fadeInUp stagger-5">
            <div className="w-16 h-16 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-6">
              <svg className="w-8 h-8 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <h3 className="text-xl font-montserrat font-semibold text-offBlack mb-4">
              Fair Price Discovery
            </h3>
            <p className="text-gray3 leading-relaxed font-sf-pro">
              Constant-product bonding curves ensure fair token distribution with no insider premints or rug pulls.
            </p>
          </div>
          
          <div className="bg-white rounded-2xl p-8 shadow-lg hover:shadow-2xl hover:-translate-y-2 hover:scale-105 transition-all duration-500 animate-fadeInUp stagger-6">
            <div className="w-16 h-16 bg-accentRed/10 rounded-full flex items-center justify-center mx-auto mb-6">
              <svg className="w-8 h-8 text-accentRed" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
              </svg>
            </div>
            <h3 className="text-xl font-montserrat font-semibold text-offBlack mb-4">
              Locked Liquidity
            </h3>
            <p className="text-gray3 leading-relaxed font-sf-pro">
              LP tokens are automatically locked for 2 years after graduation, providing security and trust.
            </p>
          </div>
          
          <div className="bg-white rounded-2xl p-8 shadow-lg hover:shadow-2xl hover:-translate-y-2 hover:scale-105 transition-all duration-500 animate-fadeInUp stagger-1">
            <div className="w-16 h-16 bg-elataGreen/10 rounded-full flex items-center justify-center mx-auto mb-6">
              <svg className="w-8 h-8 text-elataGreen" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
              </svg>
            </div>
            <h3 className="text-xl font-montserrat font-semibold text-offBlack mb-4">
              Scientific Integration
            </h3>
            <p className="text-gray3 leading-relaxed font-sf-pro">
              Apps integrate with ZORP experiments and BOS neural primitives for real-world research impact.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}