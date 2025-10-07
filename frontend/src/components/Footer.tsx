'use client';

import React from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { 
  IoLogoGithub, 
  IoShieldCheckmark, 
  IoPlanet,
  IoDocumentText,
  IoFlask,
  IoWallet,
  IoPeople,
  IoMail,
  IoLogoTwitter,
  IoInformationCircle,
  IoGlobe,
  IoApps,
  IoStatsChart
} from 'react-icons/io5';

export function Footer() {
  const footerSections = [
    {
      title: "Protocol",
      links: [
        { label: "Launch App", href: "/create", icon: IoApps },
        { label: "Browse Apps", href: "/", icon: IoDocumentText },
        { label: "Staking", href: "/staking", icon: IoWallet },
        { label: "XP System", href: "/xp", icon: IoStatsChart },
      ]
    },
    {
      title: "Platform",
      links: [
        { label: "My Apps", href: "/my-apps", icon: IoApps },
        { label: "GitHub", href: "https://github.com/Elata-Biosciences/elata-protocol", icon: IoLogoGithub },
        { label: "Documentation", href: "https://github.com/Elata-Biosciences/elata-protocol", icon: IoShieldCheckmark },
      ]
    },
    {
      title: "Elata",
      links: [
        { label: "Elata Biosciences", href: "https://elata.bio", icon: IoPlanet },
        { label: "Research", href: "https://elata.bio/research", icon: IoFlask },
        { label: "Technology", href: "https://elata.bio/technology", icon: IoShieldCheckmark },
        { label: "Community", href: "https://discord.com/invite/UxSQnZnPus", icon: IoPeople },
      ]
    }
  ];

  const socialLinks = [
    {
      href: 'https://github.com/Elata-Biosciences/elata-protocol',
      icon: <IoLogoGithub className="w-5 h-5" />,
      label: 'GitHub',
    },
    {
      href: 'https://discord.com/invite/UxSQnZnPus',
      icon: <IoShieldCheckmark className="w-5 h-5" />,
      label: 'Discord',
    },
    {
      href: 'https://elata.bio',
      icon: <IoPlanet className="w-5 h-5" />,
      label: 'Elata Biosciences',
    },
  ];

  return (
    <footer className="bg-cream2/60 backdrop-blur-sm border-t border-gray2/20">
      {/* Main Footer Content */}
      <div className="max-w-7xl mx-auto px-6 sm:px-6 lg:px-8 py-12">
        <div className="grid lg:grid-cols-4 md:grid-cols-2 gap-8">
          
          {/* Logo and Description */}
          <div className="lg:col-span-1">
            <div className="flex items-center space-x-3 mb-4">
              <Image
                src="/logotype.png"
                alt="Elata Protocol"
                width={100}
                height={32}
                className="transition-all duration-300 hover:opacity-80"
              />
            </div>
            <p className="text-gray3 font-sf-pro text-sm leading-relaxed mb-6">
              Onchain economics for the Internet of Brains. Foundational infrastructure for 
              neuroscience applications, research funding, and decentralized governance.
            </p>
            
            {/* Social Links */}
            <div className="flex space-x-3">
              {socialLinks.map(({ href, icon, label }) => (
                <a
                  key={label}
                  href={href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex justify-center p-2 text-gray3 rounded-lg cursor-pointer transition-all duration-200 hover:text-elataGreen hover:bg-white/60 hover:shadow-md hover:scale-105"
                  aria-label={label}
                >
                  {icon}
                </a>
              ))}
            </div>
          </div>

          {/* Footer Links */}
          {footerSections.map((section) => (
            <div key={section.title} className="space-y-4">
              <h3 className="text-sm font-semibold text-offBlack tracking-wider uppercase font-montserrat">
                {section.title}
              </h3>
              <ul className="space-y-3">
                {section.links.map((link) => {
                  const IconComponent = link.icon;
                  const isExternal = link.href.startsWith('http');
                  
                  return (
                    <li key={link.label}>
                      {isExternal ? (
                        <a
                          href={link.href}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="group flex items-center text-gray3 hover:text-elataGreen transition-all duration-200 font-sf-pro text-sm"
                        >
                          <IconComponent className="w-4 h-4 mr-2 group-hover:scale-110 transition-transform duration-200" />
                          {link.label}
                        </a>
                      ) : (
                        <Link
                          href={link.href}
                          className="group flex items-center text-gray3 hover:text-elataGreen transition-all duration-200 font-sf-pro text-sm"
                        >
                          <IconComponent className="w-4 h-4 mr-2 group-hover:scale-110 transition-transform duration-200" />
                          {link.label}
                        </Link>
                      )}
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </div>

        {/* Bottom Bar */}
        <div className="mt-12 pt-8 border-t border-gray2/30">
          <div className="flex flex-col md:flex-row justify-between items-center space-y-4 md:space-y-0">
            <div className="text-xs text-gray3 font-sf-pro">
              © 2025 Elata Biosciences. All rights reserved.
            </div>
            <div className="flex items-center space-x-6 text-xs text-gray3 font-sf-pro">
              <Link href="/privacy" className="hover:text-elataGreen transition-colors duration-200">
                Privacy Policy
              </Link>
              <Link href="/terms" className="hover:text-elataGreen transition-colors duration-200">
                Terms of Service
              </Link>
              <Link href="/security" className="hover:text-elataGreen transition-colors duration-200">
                Security
              </Link>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
}
