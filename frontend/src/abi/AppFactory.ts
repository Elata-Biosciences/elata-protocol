export const AppFactoryABI = [
  // Events
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "uint256", "name": "appId", "type": "uint256"},
      {"indexed": true, "internalType": "address", "name": "creator", "type": "address"},
      {"indexed": false, "internalType": "string", "name": "name", "type": "string"},
      {"indexed": false, "internalType": "string", "name": "symbol", "type": "string"},
      {"indexed": false, "internalType": "address", "name": "token", "type": "address"},
      {"indexed": false, "internalType": "address", "name": "curve", "type": "address"},
      {"indexed": false, "internalType": "uint256", "name": "seedElta", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "supply", "type": "uint256"}
    ],
    "name": "AppCreated",
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
      {"indexed": false, "internalType": "uint256", "name": "totalRaised", "type": "uint256"},
      {"indexed": false, "internalType": "uint256", "name": "finalSupply", "type": "uint256"}
    ],
    "name": "AppGraduated",
    "type": "event"
  },
  // Read Functions
  {
    "inputs": [],
    "name": "appCount",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "name": "apps",
    "outputs": [
      {"internalType": "address", "name": "creator", "type": "address"},
      {"internalType": "address", "name": "token", "type": "address"},
      {"internalType": "address", "name": "curve", "type": "address"},
      {"internalType": "address", "name": "pair", "type": "address"},
      {"internalType": "address", "name": "locker", "type": "address"},
      {"internalType": "uint64", "name": "createdAt", "type": "uint64"},
      {"internalType": "uint64", "name": "graduatedAt", "type": "uint64"},
      {"internalType": "bool", "name": "graduated", "type": "bool"},
      {"internalType": "uint256", "name": "totalRaised", "type": "uint256"},
      {"internalType": "uint256", "name": "finalSupply", "type": "uint256"}
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "appId", "type": "uint256"}],
    "name": "getApp",
    "outputs": [
      {
        "components": [
          {"internalType": "address", "name": "creator", "type": "address"},
          {"internalType": "address", "name": "token", "type": "address"},
          {"internalType": "address", "name": "curve", "type": "address"},
          {"internalType": "address", "name": "pair", "type": "address"},
          {"internalType": "address", "name": "locker", "type": "address"},
          {"internalType": "uint64", "name": "createdAt", "type": "uint64"},
          {"internalType": "uint64", "name": "graduatedAt", "type": "uint64"},
          {"internalType": "bool", "name": "graduated", "type": "bool"},
          {"internalType": "uint256", "name": "totalRaised", "type": "uint256"},
          {"internalType": "uint256", "name": "finalSupply", "type": "uint256"}
        ],
        "internalType": "struct AppFactory.App",
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "creator", "type": "address"}],
    "name": "getCreatorApps",
    "outputs": [{"internalType": "uint256[]", "name": "", "type": "uint256[]"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getLaunchStats",
    "outputs": [
      {"internalType": "uint256", "name": "totalApps", "type": "uint256"},
      {"internalType": "uint256", "name": "graduatedApps", "type": "uint256"},
      {"internalType": "uint256", "name": "totalValueLocked", "type": "uint256"},
      {"internalType": "uint256", "name": "totalFeesCollected", "type": "uint256"}
    ],
    "stateMutability": "view",
    "type": "function"
  },
  // Write Functions
  {
    "inputs": [
      {"internalType": "string", "name": "name", "type": "string"},
      {"internalType": "string", "name": "symbol", "type": "string"},
      {"internalType": "uint256", "name": "supply", "type": "uint256"},
      {"internalType": "string", "name": "description", "type": "string"},
      {"internalType": "string", "name": "imageURI", "type": "string"},
      {"internalType": "string", "name": "website", "type": "string"}
    ],
    "name": "createApp",
    "outputs": [{"internalType": "uint256", "name": "appId", "type": "uint256"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  // Configuration getters
  {
    "inputs": [],
    "name": "seedElta",
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
    "name": "creationFee",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "defaultSupply",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
] as const;


