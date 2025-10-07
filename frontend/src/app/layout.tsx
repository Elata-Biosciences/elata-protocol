import type { Metadata } from "next";
import { Montserrat } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";

const montserrat = Montserrat({
  variable: "--font-montserrat",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
});

export const metadata: Metadata = {
  title: "Elata Protocol",
  description: "Onchain economics for the Internet of Brains. The Elata Protocol provides foundational infrastructure for neuroscience applications, research funding, and decentralized governance.",
  keywords: ["Elata", "EEG", "BCI", "neuroscience", "DeSci", "blockchain", "protocol", "staking", "governance"],
  authors: [{ name: "Elata Biosciences" }],
  openGraph: {
    title: "Elata Protocol",
    description: "Onchain economics for the Internet of Brains",
    url: "https://protocol.elata.bio",
    siteName: "Elata Protocol",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Elata Protocol",
    description: "Onchain economics for the Internet of Brains",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={montserrat.variable}>
      <head>
        <link rel="icon" href="/favicon.ico" />
        <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />
        <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png" />
        <link rel="manifest" href="/site.webmanifest" />
      </head>
      <body className="font-sf-pro antialiased">
        <Providers>
          {children}
        </Providers>
      </body>
    </html>
  );
}
