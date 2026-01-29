/**
 * Smoke Test: App Creation
 *
 * Tests that app creation via AppFactory works correctly.
 * - 2 DeveloperAgents with high launch probability
 * - Verifies at least 2 apps are created beyond bootstrap
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { DeveloperAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8547,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-app-creation',
  seed: 42,
  ticks: 5,
  tickSeconds: 3600,

  pack,

  agents: [
    {
      type: DeveloperAgent,
      count: 2,
      params: {
        maxApps: 3,
        launchProbability: 0.9, // High probability to ensure launches
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'elta_total_supply'],
  },

  assertions: [
    // Bootstrap apps (3) + at least 2 new apps = 5
    { type: 'gte', metric: 'app_count', value: 5 },
    // Protocol should have ELTA supply
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: App Creation ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-app-creation'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Apps created: ${result.finalMetrics.app_count}`);

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
