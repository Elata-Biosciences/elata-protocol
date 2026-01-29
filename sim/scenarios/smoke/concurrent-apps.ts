/**
 * Smoke Test: Concurrent Apps
 *
 * Tests creating 10+ apps in the same tick.
 * Verifies protocol handles high-volume app creation.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { SerialDeveloperAgent, BasicUserAgent } from '../../agents/index.js';
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
  name: 'smoke-concurrent-apps',
  seed: 46,
  ticks: 5,
  tickSeconds: 3600,

  pack,

  agents: [
    // Many serial developers launching simultaneously
    {
      type: SerialDeveloperAgent,
      count: 12,
      params: {
        maxApps: 5,
        launchProbability: 1.0, // Always launch
        minLaunchInterval: 0, // No delay between launches
      },
    },
    // Some users to interact with created apps
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'gas_total'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Should have many apps created (3 bootstrap + new apps)
    { type: 'gte', metric: 'app_count', value: 10 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Concurrent Apps ===\n');
  console.log('Testing 10+ app creation in same tick...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-concurrent-apps'),
      ci: true,
    });

    printScenarioResults(result, {
      highlightMetrics: ['app_count', 'fees_collected_total', 'gas_total'],
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
