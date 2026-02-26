#!/usr/bin/env tsx

import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';

type SummaryJson = {
  runId: string;
  scenarioName: string;
  success: boolean;
  failedAssertions?: Array<{ message?: string }>;
  durationMs?: number;
  timestamp?: string;
};

const EXPECTED_BY_MODE: Record<string, string[]> = {
  fast: [
    'smoke-single-agent',
    'smoke-bootstrap-only',
    'smoke-app-creation',
    'smoke-buy-tokens',
    'smoke-fee-collection',
    'smoke-veelta-lock',
    'smoke-governance',
    'smoke-attack-resistance',
    'smoke-usdc-revenue',
    'reward-distribution',
  ],
  deep: [
    'smoke-single-agent',
    'smoke-bootstrap-only',
    'smoke-app-creation',
    'smoke-buy-tokens',
    'smoke-fee-collection',
    'smoke-veelta-lock',
    'smoke-app-staking',
    'smoke-arbitrager',
    'smoke-fee-pipeline',
    'smoke-zero-epoch',
    'smoke-empty-vault',
    'smoke-max-locks',
    'smoke-rapid-unlock',
    'smoke-concurrent-apps',
    'agent-cautious-user',
    'agent-serial-developer',
    'agent-app-staker',
    'agent-manipulator',
    'agent-spammer',
    'full-protocol-flow',
    'staking-stress',
    'reward-distribution',
    'economic-bank-run',
    'economic-whale-accumulation',
    'economic-fee-timing',
    'economic-governance-attack',
    'stress-high-frequency',
    'stress-many-small-txs',
    'stress-liquidity-crisis',
    'stress-governance-spam',
    'stress-flash-attack',
  ],
  balanced: [
    'smoke-single-agent',
    'smoke-bootstrap-only',
    'smoke-app-creation',
    'smoke-buy-tokens',
    'smoke-fee-collection',
    'full-protocol-flow',
    'reward-distribution',
    'adversarial-strategy-arms-race',
    'adversarial-governance-pressure',
    'economic-fee-cadence-competition',
    'economic-rebalancing-liquidity',
    'growth-bursty-launch-adoption',
    'growth-network-retention-mix',
    'resilience-congestion-recovery',
    'resilience-liquidity-shock-absorption',
  ],
};

function parseModeArg(): 'fast' | 'deep' | 'balanced' {
  const idx = process.argv.indexOf('--mode');
  const next = idx >= 0 ? process.argv[idx + 1] : undefined;
  if (next === 'balanced') return 'balanced';
  if (next === 'deep') return 'deep';
  return 'fast';
}

async function listScenarioDirs(resultsDir: string): Promise<string[]> {
  const entries = await readdir(resultsDir, { withFileTypes: true });
  return entries.filter((e) => e.isDirectory()).map((e) => e.name);
}

async function loadLatestSummary(
  resultsDir: string,
  scenarioDir: string
): Promise<SummaryJson | null> {
  const scenarioPath = join(resultsDir, scenarioDir);
  const runs = await readdir(scenarioPath, { withFileTypes: true });
  const runDirs = runs
    .filter((r) => r.isDirectory())
    .map((r) => r.name)
    .sort()
    .reverse();
  for (const run of runDirs) {
    try {
      const summaryPath = join(scenarioPath, run, 'summary.json');
      const raw = await readFile(summaryPath, 'utf-8');
      return JSON.parse(raw) as SummaryJson;
    } catch {
      // try next
    }
  }
  return null;
}

async function loadLatestRunDir(resultsDir: string, scenarioDir: string): Promise<string | null> {
  const scenarioPath = join(resultsDir, scenarioDir);
  const runs = await readdir(scenarioPath, { withFileTypes: true });
  const runDirs = runs
    .filter((r) => r.isDirectory())
    .map((r) => r.name)
    .sort()
    .reverse();
  const latest = runDirs[0];
  return latest ? join(scenarioPath, latest) : null;
}

async function validatePersonaQuality(resultsDir: string): Promise<string | null> {
  const runDir = await loadLatestRunDir(resultsDir, 'llm-persona-matrix');
  if (!runDir) return 'llm-persona-matrix run directory not found';
  try {
    const raw = await readFile(join(runDir, 'persona_quality.json'), 'utf-8');
    const parsed = JSON.parse(raw) as { aggregate?: { meanUsefulnessScore?: number } };
    const score = Number(parsed.aggregate?.meanUsefulnessScore ?? 0);
    if (score < 0.35) {
      return `persona usefulness too low: ${score.toFixed(3)} (< 0.35)`;
    }
    return null;
  } catch {
    return 'persona_quality.json missing for llm-persona-matrix';
  }
}

async function main() {
  const mode = parseModeArg();
  const requirePersonaQuality = process.argv.includes('--persona-quality');
  const expected = EXPECTED_BY_MODE[mode] ?? [];
  const resultsDir = join(process.cwd(), 'results');

  const scenarioDirs = await listScenarioDirs(resultsDir);
  const summaries = new Map<string, SummaryJson>();

  for (const dir of scenarioDirs) {
    const summary = await loadLatestSummary(resultsDir, dir);
    if (!summary?.scenarioName) continue;
    summaries.set(summary.scenarioName, summary);
  }

  const missing = expected.filter((name) => !summaries.has(name));
  const failed = expected
    .map((name) => summaries.get(name))
    .filter((s): s is SummaryJson => Boolean(s))
    .filter((s) => !s.success || (s.failedAssertions?.length ?? 0) > 0);

  console.log(`Validating ${expected.length} scenarios for mode=${mode}`);

  if (missing.length > 0) {
    console.error(`Missing summaries for: ${missing.join(', ')}`);
  }

  if (failed.length > 0) {
    console.error('Failed scenarios:');
    for (const f of failed) {
      const firstAssertion = f.failedAssertions?.[0]?.message;
      console.error(
        `  - ${f.scenarioName} (${f.runId}) ${firstAssertion ? `:: ${firstAssertion}` : ''}`
      );
    }
  }

  const passingCount = expected.length - missing.length - failed.length;
  console.log(`Passing summaries: ${passingCount}/${expected.length}`);

  if (missing.length > 0 || failed.length > 0) {
    process.exit(1);
  }

  if (requirePersonaQuality) {
    const qualityError = await validatePersonaQuality(resultsDir);
    if (qualityError) {
      console.error(`Persona quality validation failed: ${qualityError}`);
      process.exit(1);
    }
    console.log('Persona quality validation passed.');
  }
}

void main();
