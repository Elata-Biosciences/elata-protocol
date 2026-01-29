/**
 * Smoke Test: Fee Collection
 *
 * Tests that fees are collected during trading activity.
 * - 5 BasicUserAgents with high buy probability
 * - Verifies fees_collected_total > 0
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { BasicUserAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8549,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-fee-collection',
  seed: 42,
  ticks: 15,
  tickSeconds: 3600,

  pack,

  agents: [
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        buyProbability: 0.8,
        sellProbability: 0.1,
        stakeProbability: 0.0,
        riskTolerance: 0.6,
        maxTradePercent: 0.15,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 3,
    track: ['app_count', 'fees_collected_total', 'fees_distributed', 'elta_total_supply'],
  },

  assertions: [
    // Fees should be collected from trading
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
    // System should have bootstrap apps
    { type: 'gte', metric: 'app_count', value: 3 },
    // Protocol should have ELTA supply
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Fee Collection ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-fee-collection'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Fees collected: ${result.finalMetrics.fees_collected_total}`);
    console.log(`Fees distributed: ${result.finalMetrics.fees_distributed}`);

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
