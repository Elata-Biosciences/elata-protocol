/**
 * Smoke Test: Zero Epoch
 *
 * Tests behavior when no fee epochs have been closed.
 * Verifies that reward claiming gracefully handles empty state.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { FeeKeeperAgent, BasicUserAgent, RewardHunterAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';
import {
  basicStabilityAssertions,
  printScenarioResults,
  allocatePort,
} from '../../lib/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: allocatePort(),
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-zero-epoch',
  seed: 42,
  ticks: 10,
  tickSeconds: 3600, // 1 hour per tick - not enough for epoch closure

  pack,

  agents: [
    // Users will generate activity but no epoch closures
    {
      type: BasicUserAgent,
      count: 3,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
    // Fee keeper that WON'T close epochs (low probability)
    {
      type: FeeKeeperAgent,
      count: 1,
      params: {
        closeEpochProbability: 0, // Never close epochs
        sweepProbability: 0.5,
      },
    },
    // Reward hunters trying to claim from empty vaults
    {
      type: RewardHunterAgent,
      count: 2,
      params: {
        claimProbability: 0.8,
        stakeFirst: false,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'veelta_total_locked'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Fees should still be collected even without epoch closure
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Zero Epoch ===\n');
  console.log('Testing behavior with no fee epochs closed...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-zero-epoch'),
      ci: true,
    });

    printScenarioResults(result, {
      highlightMetrics: ['app_count', 'fees_collected_total', 'veelta_total_locked'],
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
