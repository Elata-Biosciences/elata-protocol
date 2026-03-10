/**
 * Smoke Test: Single Agent
 *
 * Minimal system test with just one agent.
 * - Verifies the simulation runs with minimal setup
 * - Catches initialization/cleanup issues
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
  anvilPort: 8554,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-single-agent',
  seed: 42,
  ticks: 5,
  tickSeconds: 3600,

  pack,

  agents: [
    {
      type: BasicUserAgent,
      count: 1,
      params: {
        buyProbability: 0.5,
        sellProbability: 0.2,
        stakeProbability: 0.1,
        riskTolerance: 0.5,
        maxTradePercent: 0.1,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'elta_total_supply'],
  },

  assertions: [
    // Protocol should have ELTA supply
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
    // Bootstrap apps should exist
    { type: 'gte', metric: 'app_count', value: 3 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Single Agent ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-single-agent'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Ticks completed: ${result.ticks}`);

    // Log the single agent's stats
    for (const stat of result.agentStats) {
      console.log(`Agent ${stat.id}:`);
      console.log(`  Actions attempted: ${stat.actionsAttempted}`);
      console.log(`  Actions succeeded: ${stat.actionsSucceeded}`);
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
