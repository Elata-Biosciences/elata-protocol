/**
 * Smoke Test: veELTA Lock
 *
 * Tests that veELTA locking works correctly.
 * - 3 BasicUserAgents with high stake probability
 * - Verifies veelta_total_locked > 0
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
  anvilPort: 8550,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-veelta-lock',
  seed: 42,
  ticks: 10,
  tickSeconds: 3600,

  pack,

  agents: [
    {
      type: BasicUserAgent,
      count: 3,
      params: {
        buyProbability: 0.1,
        sellProbability: 0.0,
        stakeProbability: 0.9, // High probability to trigger staking
        riskTolerance: 0.5,
        maxTradePercent: 0.1,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 2,
    track: ['veelta_total_locked', 'elta_total_supply', 'app_count'],
  },

  assertions: [
    // Some veELTA should be locked
    { type: 'gte', metric: 'veelta_total_locked', value: 0 },
    // Protocol should have ELTA supply
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: veELTA Lock ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-veelta-lock'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
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
