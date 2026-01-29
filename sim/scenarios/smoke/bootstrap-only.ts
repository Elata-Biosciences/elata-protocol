/**
 * Smoke Test: Bootstrap Only
 *
 * Tests that the system works with only bootstrap apps (no new app creation).
 * - Only BasicUserAgents (no developers)
 * - Verifies trading on bootstrap apps works
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
  anvilPort: 8553,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-bootstrap-only',
  seed: 42,
  ticks: 10,
  tickSeconds: 3600,

  pack,

  agents: [
    // Only users trading on bootstrap apps
    {
      type: BasicUserAgent,
      count: 3,
      params: {
        buyProbability: 0.5,
        sellProbability: 0.2,
        stakeProbability: 0.1,
        riskTolerance: 0.4,
        maxTradePercent: 0.1,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 2,
    track: ['app_count', 'fees_collected_total', 'elta_total_supply'],
  },

  assertions: [
    // App count should be exactly bootstrap apps (3)
    { type: 'eq', metric: 'app_count', value: 3 },
    // Protocol should have ELTA supply
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Bootstrap Only ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-bootstrap-only'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`App count: ${result.finalMetrics.app_count}`);
    console.log(`Fees collected: ${result.finalMetrics.fees_collected_total}`);

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
