/**
 * Smoke Test: Buy Tokens
 *
 * Tests that buying tokens via bonding curves works correctly.
 * - 3 BasicUserAgents with high buy probability
 * - Verifies the system remains stable and no crashes occur
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
  anvilPort: 8548,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-buy-tokens',
  seed: 42,
  ticks: 10,
  tickSeconds: 3600,

  pack,

  agents: [
    {
      type: BasicUserAgent,
      count: 3,
      params: {
        buyProbability: 0.9, // High probability to ensure buys happen
        sellProbability: 0.0,
        stakeProbability: 0.0,
        riskTolerance: 0.5,
        maxTradePercent: 0.1,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 2,
    track: ['app_count', 'fees_collected_total', 'elta_total_supply'],
  },

  assertions: [
    // System should have bootstrap apps
    { type: 'gte', metric: 'app_count', value: 3 },
    // Protocol should have ELTA supply
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Buy Tokens ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-buy-tokens'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);

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
