export const AppBondingCurveABI = [
  // Events
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "uint256", "name": "appId", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "seedElta", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "tokenSupply", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "initialK", "type": "uint256"}
    ],
    "name": "CurveInitialized",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "uint256", "name": "appId", "type": "uint256"},
      {"indexed": true, "internalType": "address", "name": "buyer", "type": "address"},
      {"indexed": false, "internalType": "uint256", "name": "eltaIn", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "tokensOut", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "newReserveElta", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "newReserveToken", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "newPrice", "type": "uint256"}
    ],
    "name": "TokensPurchased",
    "type": "event"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "uint256", "name": "appId", "type": "uint256"},
      {"indexed": true, "internalType": "address", "name": "token", "type": "address"},
      {"indexed": false, "internalType": "address", "name": "pair", "type": "address"},
      {"indexed": false, "internalType": "address", "name": "locker", "type": "address"},
      {"indexed": false, "internalType": "uint256", "name": "unlockAt", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "totalRaisedElta", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "tokensToLp", "type": "uint256"}
    ],
    "name": "AppGraduated",
    "type": "event"
  },
  // Read Functions
  {
    "inputs": [],
    "name": "appId",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "reserveElta",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "reserveToken",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "targetRaisedElta",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "graduated",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "pair",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "eltaIn", "type": "uint256"}],
    "name": "getTokensOut",
    "outputs": [{"internalType": "uint256", "name": "tokensOut", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "tokensDesired", "type": "uint256"}],
    "name": "getEltaInForTokens",
    "outputs": [{"internalType": "uint256", "name": "eltaIn", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getCurrentPrice",
    "outputs": [{"internalType": "uint256", "name": "price", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getCurveState",
    "outputs": [
      {"internalType": "uint256", "name": "eltaReserve", "type": "uint256"},
      {"internalType": "uint256", "name": "tokenReserve", "type": "uint256"},
      {"internalType": "uint256", "name": "target", "type": "uint256"},
      {"internalType": "bool", "name": "isGraduated", "type": "bool"},
      {"internalType": "uint256", "name": "currentPrice", "type": "uint256"},
      {"internalType": "uint256", "name": "progress", "type": "uint256"}
    ],
    "stateMutability": "view",
    "type": "function"
  },
  // Write Functions
  {
    "inputs": [
      {"internalType": "uint256", "name": "eltaIn", "type": "uint256"},
      {"internalType": "uint256", "name": "minTokensOut", "type": "uint256"}
    ],
    "name": "buy",
    "outputs": [{"internalType": "uint256", "name": "tokensOut", "type": "uint256"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "graduate",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
] as const;


