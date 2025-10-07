import type { Config } from "tailwindcss";

export default {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // Elata Design System Color Palette
        black: '#0A0A0A',
        offBlack: '#171717',
        gray3: '#6D6D6D',
        gray2: '#CCCCCC',
        gray1: '#DDDDDD',
        offWhite: '#F7F7F7',
        white: '#FDFDFD',
        elataGreen: '#607274',
        accentRed: '#FF797B',
        offCream: '#F8F5EE',
        cream1: '#F3EEE2',
        cream2: '#E5E0D3',
        
        // Semantic colors
        primary: '#607274', // elataGreen
        secondary: '#FF797B', // accentRed
        warning: '#ffcc00',
        danger: '#ff3b30',
        success: '#34c759',
        info: '#32ade6',
      },
      fontFamily: {
        'montserrat': ['var(--font-montserrat)', 'Montserrat', 'sans-serif'],
        'sf-pro': ['var(--font-sf-pro)', 'SF Pro Text', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'],
      },
      backgroundImage: {
        'gradient-radial': 'radial-gradient(var(--tw-gradient-stops))',
        'gradient-conic': 'conic-gradient(from 180deg at 50% 50%, var(--tw-gradient-stops))',
      },
      screens: {
        xxs: '256px',
        xs: '384px',
        s: '512px',
      },
      maxWidth: {
        'header-nav': '39rem',
      },
      height: {
        sidebar: 'calc(100dvh - 5rem)',
      },
      borderRadius: {
        'xl': '1.25rem',
        '2xl': '1.5rem',
      },
      animation: {
        'fadeInUp': 'fadeInUp 0.6s ease-out forwards',
        'fadeIn': 'fadeIn 0.4s ease-out forwards',
        'slideInLeft': 'slideInLeft 0.5s ease-out forwards',
        'scaleIn': 'scaleIn 0.3s ease-out forwards',
      },
      keyframes: {
        fadeInUp: {
          '0%': { opacity: '0', transform: 'translateY(30px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideInLeft: {
          '0%': { opacity: '0', transform: 'translateX(-30px)' },
          '100%': { opacity: '1', transform: 'translateX(0)' },
        },
        scaleIn: {
          '0%': { opacity: '0', transform: 'scale(0.9)' },
          '100%': { opacity: '1', transform: 'scale(1)' },
        },
      },
    },
  },
  plugins: [],
} satisfies Config;


