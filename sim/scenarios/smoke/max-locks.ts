/**
 * Smoke Test: Max Locks
 *
 * Tests veELTA locking with maximum duration (4 years / 1460 days).
 * Verifies that max lock periods work correctly.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { StakerAgent, BasicUserAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';
import {
  veEltaAssertions,
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

// Max lock duration: 4 years in days
const MAX_LOCK_DAYS = 1460;

const scenario = defineScenario({
  name: 'smoke-max-locks',
  seed: 44,
  ticks: 10,
  tickSeconds: 86400, // 1 day per tick

  pack,

  agents: [
    // Stakers with maximum lock duration
    {
      type: StakerAgent,
      count: 5,
      params: {
        lockProbability: 0.95,
        minLockAmount: 5000n * 10n ** 18n,
        maxLockAmount: 50000n * 10n ** 18n,
        preferredLockDays: MAX_LOCK_DAYS,
        extendProbability: 0.3,
      },
    },
    // Some regular users for activity
    {
      type: BasicUserAgent,
      count: 2,
      params: {
        riskTolerance: 0.3,
        maxTradePercent: 0.1,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['veelta_total_locked', 'elta_total_supply', 'app_count'],
  },

  assertions: [
    // Should have significant veELTA locked with max duration
    ...veEltaAssertions(1000n * 10n ** 18n),
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Max Locks ===\n');
  console.log(`Testing veELTA locks with max duration (${MAX_LOCK_DAYS} days)...\n`);

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-max-locks'),
      ci: true,
    });

    printScenarioResults(result, {
      highlightMetrics: ['veelta_total_locked', 'elta_total_supply'],
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
