/**
 * Smoke Test: Rapid Unlock
 *
 * Tests unlocking veELTA immediately after lock expiry.
 * Uses short lock periods and time advancement to test unlock flow.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { StakerAgent, BasicUserAgent } from '../../agents/index.js';
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
  name: 'smoke-rapid-unlock',
  seed: 45,
  ticks: 15,
  tickSeconds: 86400 * 2, // 2 days per tick for faster expiry

  pack,

  agents: [
    // Stakers with short lock periods
    {
      type: StakerAgent,
      count: 5,
      params: {
        lockProbability: 0.8,
        minLockAmount: 1000n * 10n ** 18n,
        maxLockAmount: 10000n * 10n ** 18n,
        preferredLockDays: 7, // Minimum lock: 1 week
        unlockProbability: 0.9, // Aggressive unlocking
      },
    },
    // Some trading activity
    {
      type: BasicUserAgent,
      count: 3,
      params: {
        riskTolerance: 0.4,
        maxTradePercent: 0.15,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['veelta_total_locked', 'elta_total_supply', 'app_count'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // veELTA should fluctuate as locks expire and unlock
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Rapid Unlock ===\n');
  console.log('Testing veELTA unlock immediately after lock expiry...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-rapid-unlock'),
      ci: true,
    });

    printScenarioResults(result, {
      highlightMetrics: ['veelta_total_locked', 'elta_total_supply'],
      showTimeSeries: true,
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
