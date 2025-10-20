#!/usr/bin/env -S node --no-warnings
import { readFileSync } from 'fs';
import { keccak256, createWalletClient, createPublicClient, http, isAddress, stringToHex, getContract, parseAbi } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

function usage(): never {
  console.error('Usage: tsx scripts/xp/xp-publish-root.ts --rpc <url> --key <hex> --contract <addr> --json <path>');
  process.exit(1);
}

function parseArgs() {
  const args = process.argv.slice(2);
  const opts: any = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--rpc') opts.rpc = args[++i];
    else if (a === '--key') opts.key = args[++i];
    else if (a === '--contract') opts.contract = args[++i];
    else if (a === '--json') opts.json = args[++i];
  }
  if (!opts.rpc || !opts.key || !opts.contract || !opts.json) usage();
  if (!isAddress(opts.contract)) throw new Error('Invalid contract address');
  return opts;
}

async function main() {
  const opts = parseArgs();
  const account = privateKeyToAccount(opts.key as `0x${string}`);
  const client = createWalletClient({ account, transport: http(opts.rpc) });
  const publicClient = createPublicClient({ transport: http(opts.rpc) });
  const abi = parseAbi([
    'function setMerkleRoot(bytes32,bytes32)',
    'function currentDistributionId() view returns (uint256)'
  ]);
  const contract = getContract({ address: opts.contract, abi, client });

  const json = readFileSync(opts.json, 'utf8');
  const parsed = JSON.parse(json);
  const expectedDataHash = keccak256(stringToHex(JSON.stringify(parsed), { size: 0 }));
  if (parsed.dataHash !== expectedDataHash) {
    throw new Error(`dataHash mismatch: json=${parsed.dataHash} computed=${expectedDataHash}`);
  }
  const root = parsed.merkleRoot as string;
  const hash = await contract.write.setMerkleRoot([root, parsed.dataHash]);
  console.log('tx', hash);
  await publicClient.waitForTransactionReceipt({ hash });
  const id = await contract.read.currentDistributionId();
  console.log('currentDistributionId', id.toString());
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}


