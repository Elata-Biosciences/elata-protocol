'use client';
import { Header } from '../../components/Header';
import { Footer } from '../../components/Footer';

export default function XPPage() {
  return (
    <div className="min-h-screen bg-offCream">
      <Header />
      <main className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
        <div className="bg-white rounded-2xl p-8 shadow-lg text-center">
          <h1 className="text-3xl font-montserrat font-bold text-offBlack mb-4">XP UI Moved</h1>
          <p className="text-gray3 font-sf-pro">
            The XP claim interface has moved to the Elata App Store. Please use the appstore frontend for all XP interactions.
          </p>
        </div>
      </main>
      <Footer />
    </div>
  );
}
