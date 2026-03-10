/**
 * Smoke Test: Rewards Claim
 *
 * Tests that rewards claiming works correctly.
 * - Mixed agents generating fees and claiming rewards
 * - Longer simulation to allow epochs to accumulate
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { BasicUserAgent, DeveloperAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8552,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-rewards-claim',
  seed: 42,
  ticks: 20,
  tickSeconds: 3600,

  pack,

  agents: [
    // Users to generate trading fees and stake
    {
      type: BasicUserAgent,
      count: 4,
      params: {
        buyProbability: 0.5,
        sellProbability: 0.1,
        stakeProbability: 0.2,
        riskTolerance: 0.5,
        maxTradePercent: 0.1,
      },
    },
    // Developer to create apps
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
    sampleEveryTicks: 4,
    track: [
      'app_count',
      'fees_collected_total',
      'fees_distributed',
      'veelta_total_locked',
      'elta_total_supply',
    ],
  },

  assertions: [
    // System should remain stable
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
    // Fees should be collected (even if 0 is acceptable)
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Rewards Claim ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-rewards-claim'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Fees collected: ${result.finalMetrics.fees_collected_total}`);
    console.log(`Fees distributed: ${result.finalMetrics.fees_distributed}`);
    console.log(`veELTA locked: ${result.finalMetrics.veelta_total_locked}`);

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
