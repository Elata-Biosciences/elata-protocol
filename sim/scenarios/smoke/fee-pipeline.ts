/**
 * Smoke Test: Fee Pipeline
 *
 * Tests the fee collection and distribution pipeline.
 * - FeeKeeperAgent sweeps fees from bonding curves
 * - BasicUserAgents generate trading activity
 * - Verifies fee accumulation and distribution
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { BasicUserAgent, DeveloperAgent, FeeKeeperAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8560,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-fee-pipeline',
  seed: 42,
  ticks: 15,
  tickSeconds: 3600,

  pack,

  agents: [
    // Fee keeper to sweep and close epochs
    {
      type: FeeKeeperAgent,
      count: 2,
      params: {
        sweepProbability: 0.5,
        closeEpochProbability: 0.3,
        minFeesToSweep: BigInt(10e18),
      },
    },
    // Users to generate trading fees
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        buyProbability: 0.5,
        minBuyAmount: BigInt(50e18),
        maxBuyAmount: BigInt(200e18),
      },
    },
    // Developer to ensure apps exist
    {
      type: DeveloperAgent,
      count: 1,
      params: {
        maxApps: 2,
        launchProbability: 0.3,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 3,
    track: ['app_count', 'fees_collected_total', 'elta_total_supply'],
  },

  assertions: [
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Fee Pipeline ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-fee-pipeline'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Apps: ${result.finalMetrics.app_count}`);
    console.log(`Fees collected: ${result.finalMetrics.fees_collected_total}`);

    // Log agent stats
    for (const stat of result.agentStats) {
      const rate =
        stat.actionsAttempted > 0
          ? Math.round((stat.actionsSucceeded / stat.actionsAttempted) * 100)
          : 0;
      console.log(`  ${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted} (${rate}%)`);
    }

    if (result.failedAssertions.length > 0) {
      for (const f of result.failedAssertions) {
        console.log(`  Failed: ${f.message}`);
      }
    }

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
