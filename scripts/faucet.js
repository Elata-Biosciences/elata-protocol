#!/usr/bin/env node

/**
 * ELTA Token Faucet for Local Development
 * Sends 10,000 ELTA from the deployer account to any address
 * 
 * Usage: npm run faucet <recipient-address>
 * 
 * ⚠️  ONLY WORKS ON LOCAL NETWORK (chainId 31337)
 * Uses insecure Anvil private key - safe for local dev only!
 */

const { createWalletClient, createPublicClient, http, parseEther } = require('viem');
const { localhost } = require('viem/chains');
const { privateKeyToAccount } = require('viem/accounts');
const fs = require('fs');
const path = require('path');

// Anvil account #0 (has all the ELTA from deployment)
const ANVIL_PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const FAUCET_AMOUNT = parseEther('10000'); // 10,000 ELTA

// ERC20 transfer ABI
const TRANSFER_ABI = [
  {
    name: 'transfer',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    outputs: [{ type: 'bool' }]
  }
];

async function main() {
  console.log('💧 ELTA Token Faucet\n');

  // Check for recipient address
  const recipientAddress = process.argv[2];
  
  if (!recipientAddress) {
    console.error('❌ Error: No recipient address provided\n');
    console.error('Usage: npm run faucet <address>');
    console.error('Example: npm run faucet 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb');
    process.exit(1);
  }

  // Validate address format
  if (!/^0x[a-fA-F0-9]{40}$/.test(recipientAddress)) {
    console.error('❌ Error: Invalid Ethereum address format');
    console.error('   Address must be 42 characters starting with 0x');
    process.exit(1);
  }

  // Read ELTA address from deployment
  const deploymentPath = path.join(__dirname, '../deployments/local.json');
  
  if (!fs.existsSync(deploymentPath)) {
    console.error('❌ Error: deployments/local.json not found');
    console.error('   Please run "npm run local:up" first to deploy contracts');
    process.exit(1);
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));
  const eltaAddress = deployment.contracts.ELTA;

  if (!eltaAddress) {
    console.error('❌ Error: ELTA address not found in deployment');
    process.exit(1);
  }

  console.log(`📍 ELTA Token: ${eltaAddress}`);
  console.log(`📍 Recipient:  ${recipientAddress}`);
  console.log(`💰 Amount:     10,000 ELTA\n`);

  // Create clients
  const publicClient = createPublicClient({
    chain: localhost,
    transport: http('http://127.0.0.1:8545')
  });

  // Verify we're on local network
  try {
    const chainId = await publicClient.getChainId();
    if (chainId !== 31337) {
      console.error('❌ Error: Not on local network!');
      console.error(`   Current chain ID: ${chainId}`);
      console.error('   Expected chain ID: 31337 (Anvil)');
      console.error('\n⚠️  This faucet only works on local development network for safety');
      process.exit(1);
    }
  } catch (error) {
    console.error('❌ Error: Cannot connect to local network');
    console.error('   Is Anvil running on http://127.0.0.1:8545?');
    console.error('\n💡 Start Anvil with: npm run local:up');
    process.exit(1);
  }

  // Setup wallet with Anvil account #0
  const account = privateKeyToAccount(ANVIL_PRIVATE_KEY);
  
  // Define custom localhost chain with correct chainId
  const anvilChain = {
    ...localhost,
    id: 31337,
    name: 'Anvil',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
    rpcUrls: {
      default: { http: ['http://127.0.0.1:8545'] },
      public: { http: ['http://127.0.0.1:8545'] }
    }
  };
  
  const walletClient = createWalletClient({
    account,
    chain: anvilChain,
    transport: http('http://127.0.0.1:8545')
  });

  console.log('🚀 Sending ELTA tokens...');

  try {
    // Transfer ELTA
    const hash = await walletClient.writeContract({
      address: eltaAddress,
      abi: TRANSFER_ABI,
      functionName: 'transfer',
      args: [recipientAddress, FAUCET_AMOUNT]
    });

    console.log(`✅ Transaction sent: ${hash}`);
    
    // Wait for confirmation
    console.log('⏳ Waiting for confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    
    if (receipt.status === 'success') {
      console.log('\n' + '='.repeat(60));
      console.log('✅ SUCCESS! 10,000 ELTA sent to your address');
      console.log('='.repeat(60));
      console.log(`\n📊 Transaction Details:`);
      console.log(`   Block: ${receipt.blockNumber}`);
      console.log(`   Gas used: ${receipt.gasUsed.toString()}`);
      console.log(`\n💡 Check your balance in MetaMask or use:`);
      console.log(`   cast balance ${recipientAddress} --rpc-url http://127.0.0.1:8545`);
    } else {
      console.error('\n❌ Transaction failed');
      process.exit(1);
    }

  } catch (error) {
    console.error('\n❌ Error sending ELTA:', error.message);
    
    if (error.message.includes('insufficient funds')) {
      console.error('\n💡 The deployer account may be out of ELTA');
      console.error('   Try restarting the local network: npm run local:restart');
    }
    
    process.exit(1);
  }
}

main().catch((error) => {
  console.error('\n❌ Fatal error:', error);
  process.exit(1);
});

