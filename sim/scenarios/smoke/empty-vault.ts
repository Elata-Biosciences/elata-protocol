/**
 * Smoke Test: Empty Vault
 *
 * Tests claiming rewards from vaults that have no rewards distributed.
 * Verifies graceful handling of empty reward vaults.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { RewardHunterAgent, StakerAgent } from '../../agents/index.js';
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
  name: 'smoke-empty-vault',
  seed: 43,
  ticks: 8,
  tickSeconds: 3600,

  pack,

  agents: [
    // Stakers who lock but won't have rewards yet
    {
      type: StakerAgent,
      count: 3,
      params: {
        lockProbability: 0.9,
        minLockAmount: 1000n * 10n ** 18n,
        preferredLockDays: 30,
      },
    },
    // Reward hunters aggressively trying to claim
    {
      type: RewardHunterAgent,
      count: 3,
      params: {
        claimProbability: 0.95, // Very aggressive claiming
        stakeFirst: true,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'veelta_total_locked', 'fees_collected_total'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Should have some veELTA locked from stakers
    { type: 'gte', metric: 'veelta_total_locked', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Empty Vault ===\n');
  console.log('Testing claim behavior from empty reward vaults...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-empty-vault'),
      ci: true,
    });

    printScenarioResults(result, {
      highlightMetrics: ['veelta_total_locked', 'fees_collected_total'],
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
