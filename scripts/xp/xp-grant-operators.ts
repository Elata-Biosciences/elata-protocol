#!/usr/bin/env -S node --no-warnings
import { createWalletClient, http, isAddress, parseAbi } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

function usage(): never {
  console.error('Usage: tsx scripts/xp/xp-grant-operators.ts --rpc <url> --key <admin_pk> --contract <xp_addr> --ops <addr1,addr2> [--revoke]');
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
    else if (a === '--ops') opts.ops = args[++i];
    else if (a === '--revoke') opts.revoke = true;
  }
  if (!opts.rpc || !opts.key || !opts.contract || !opts.ops) usage();
  if (!isAddress(opts.contract)) throw new Error('Invalid XP contract address');
  const ops = String(opts.ops).split(',').map((s) => s.trim()).filter(Boolean);
  ops.forEach((a) => { if (!isAddress(a)) throw new Error(`Invalid operator address: ${a}`); });
  return { ...opts, ops };
}

async function main() {
  const opts = parseArgs();
  const account = privateKeyToAccount(opts.key as `0x${string}`);
  const client = createWalletClient({ account, transport: http(opts.rpc) });
  const abi = parseAbi([
    'function grantRole(bytes32,address)',
    'function revokeRole(bytes32,address)',
    'function XP_OPERATOR_ROLE() view returns (bytes32)'
  ]);
  const role = await client.readContract({ address: opts.contract, abi, functionName: 'XP_OPERATOR_ROLE' });
  for (const op of opts.ops) {
    const hash = await client.writeContract({ address: opts.contract, abi, functionName: opts.revoke ? 'revokeRole' : 'grantRole', args: [role as `0x${string}`, op] });
    console.log(`${opts.revoke ? 'revoked' : 'granted'} ${op} tx=${hash}`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => { console.error(e); process.exit(1); });
}


