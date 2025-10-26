#!/usr/bin/env node

/**
 * Local ETH Faucet (Anvil)
 * Sends ETH from Anvil account #0 to a recipient on chainId 31337.
 *
 * Usage:
 *   npm run faucet:eth <recipient> [amountEth]
 * Examples:
 *   npm run faucet:eth 0xabc... 10
 *   npm run faucet:eth 0xabc...        # defaults to 10 ETH
 */

const { createWalletClient, createPublicClient, http, parseEther } = require('viem');
const { localhost } = require('viem/chains');
const { privateKeyToAccount } = require('viem/accounts');

const PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

async function main() {
  const recipient = process.argv[2];
  const amountEth = process.argv[3] || '10';

  if (!recipient || !/^0x[a-fA-F0-9]{40}$/.test(recipient)) {
    console.error('Usage: npm run faucet:eth <recipient> [amountEth]');
    process.exit(1);
  }

  const publicClient = createPublicClient({ chain: localhost, transport: http('http://127.0.0.1:8545') });
  try {
    const chainId = await publicClient.getChainId();
    if (chainId !== 31337) {
      console.error(`❌ Wrong network. Expected chainId 31337, got ${chainId}`);
      process.exit(1);
    }
  } catch (e) {
    console.error('❌ Cannot reach Anvil at http://127.0.0.1:8545');
    console.error('   Start it with: bash scripts/dev-local.sh');
    process.exit(1);
  }

  const account = privateKeyToAccount(PRIVATE_KEY);
  const walletClient = createWalletClient({ account, chain: { ...localhost, id: 31337 }, transport: http('http://127.0.0.1:8545') });

  const value = parseEther(amountEth);
  console.log(`\n💧 Sending ${amountEth} ETH to ${recipient} ...`);
  try {
    const hash = await walletClient.sendTransaction({ to: recipient, value });
    console.log(`✅ Tx sent: ${hash}`);
    console.log('⏳ Waiting for confirmation...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status === 'success') {
      console.log('✅ Success! ETH transferred.');
    } else {
      console.error('❌ Transaction failed');
      process.exit(1);
    }
  } catch (e) {
    console.error('❌ Error sending ETH:', e.message || e);
    process.exit(1);
  }
}

main();


