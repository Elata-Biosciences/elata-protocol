#!/usr/bin/env -S node --no-warnings
import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { MerkleTree } from 'merkletreejs';
import { keccak256, encodePacked, toBytes, toHex, stringToBytes } from 'viem';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

type Allocation = { address: string; amountWei: string };

function usage(): never {
  console.error('Usage: tsx scripts/xp/xp-generate-merkle.ts --in <alloc.json|csv> --out <path> --id <N> [--dry-run]');
  process.exit(1);
}

function parseArgs() {
  const args = process.argv.slice(2);
  const opts: any = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--in') opts.in = args[++i];
    else if (a === '--out') opts.out = args[++i];
    else if (a === '--id') opts.id = Number(args[++i]);
    else if (a === '--dry-run') opts.dry = true;
  }
  if (!opts.in || !opts.out || !Number.isInteger(opts.id)) usage();
  return opts;
}

export function normalizeAllocations(entries: Allocation[]): Map<string, bigint> {
  const map = new Map<string, bigint>();
  for (const e of entries) {
    const addr = e.address.toLowerCase();
    const amt = BigInt(e.amountWei);
    if (amt === 0n) continue;
    map.set(addr, (map.get(addr) || 0n) + amt);
  }
  return map;
}

export function buildMerkle(map: Map<string, bigint>) {
  const pairs = [...map.entries()];
  const leaves = pairs.map(([addr, amt]) => keccak256(encodePacked(['address','uint256'], [addr as `0x${string}`, amt])));
  const leafBufs = leaves.map((h) => Buffer.from(h.slice(2), 'hex'));
  const hashFn = (d: Buffer) => Buffer.from(keccak256(('0x' + d.toString('hex')) as `0x${string}`).slice(2), 'hex');
  const tree = new MerkleTree(leafBufs, hashFn, { sortPairs: true });
  const root = '0x' + tree.getRoot().toString('hex');
  const proofs: Record<string, string[]> = {};
  for (let i = 0; i < pairs.length; i++) {
    const [addr, amt] = pairs[i];
    const leaf = leafBufs[i];
    const proofBufs = tree.getProof(leaf).map(p => '0x' + p.data.toString('hex'));
    proofs[addr] = proofBufs;
  }
  return { root, proofs };
}

export function makeCanonicalJson(
  id: number,
  root: string,
  claims: Record<string, { amount: string; proof: string[] }>
): string {
  const obj = { distributionId: id, merkleRoot: root, dataHash: '0x', claims } as any;
  // placeholder dataHash then compute over full minified JSON
  const minified = JSON.stringify(obj);
  const dataHash = keccak256((('0x' + Buffer.from(minified, 'utf8').toString('hex')) as `0x${string}`));
  obj.dataHash = dataHash;
  return JSON.stringify(obj);
}

function readAllocations(path: string): Allocation[] {
  if (path.endsWith('.json')) {
    const raw = JSON.parse(readFileSync(path, 'utf8')) as Allocation[];
    return raw;
  }
  if (path.endsWith('.csv')) {
    const rows = readFileSync(path, 'utf8').trim().split(/\r?\n/);
    return rows.map((r) => {
      const [address, amountWei] = r.split(',').map((s) => s.trim());
      return { address, amountWei };
    });
  }
  throw new Error('Unsupported input format. Use .json or .csv');
}

function main() {
  const opts = parseArgs();
  const entries = readAllocations(opts.in);
  const map = normalizeAllocations(entries);
  const { root, proofs } = buildMerkle(map);
  const claims: Record<string, { amount: string; proof: string[] }> = {};
  for (const [addr, amt] of map.entries()) {
    claims[addr] = { amount: amt.toString(), proof: proofs[addr] };
  }
  const json = makeCanonicalJson(opts.id, root, claims);
  if (opts.dry) {
    console.log(json);
    return;
  }
  const outPath = opts.out.startsWith('/') ? opts.out : join(process.cwd(), opts.out);
  const dir = dirname(outPath);
  mkdirSync(dir, { recursive: true });
  writeFileSync(outPath, json);
  console.log(`root=${root}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}


