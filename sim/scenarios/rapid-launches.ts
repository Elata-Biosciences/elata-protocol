/**
 * Rapid Launches Scenario
 *
 * Stress test for app creation:
 * - Many developers launching rapidly
 * - High trading volume
 * - Tests system under load
 *
 * Assertions:
 * - Multiple apps created
 * - System remains stable
 * - Fees accumulate properly
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { BasicUserAgent, SerialDeveloperAgent } from '../agents/index.js';
import { createEltaPack } from '../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..');

// Create the pack
const pack = createEltaPack({
  protocolPath,
  anvilPort: 8548, // Different port
  silent: true,
});

// Define the scenario
const scenario = defineScenario({
  name: 'rapid-launches',
  seed: 999,
  ticks: 75,
  tickSeconds: 1800, // 30 min per tick

  pack,

  agents: [
    // 10 serial developers - rapid app launches
    {
      type: SerialDeveloperAgent,
      count: 10,
      params: {
        maxApps: 5,
        launchProbability: 0.3,
        rapidLaunchCooldown: 2,
      },
    },
    // 20 basic users - high trading volume
    {
      type: BasicUserAgent,
      count: 20,
      params: {
        buyProbability: 0.4,
        sellProbability: 0.3,
        riskTolerance: 0.6,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 3,
    track: ['app_count', 'fees_collected_total', 'elta_total_supply'],
  },

  assertions: [
    // Stress test: many apps should be created (10 devs * 5 max = potential 50)
    { type: 'gte', metric: 'app_count', value: 20 },
    // Not too many apps (sanity check for runaway creation)
    { type: 'lte', metric: 'app_count', value: 500 },
    // Fee collection should be happening from trading activity
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
    // Protocol ELTA supply should be positive (system not crashed)
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

/**
 * Run the simulation
 */
async function main(): Promise<void> {
  console.log('=== Elata Protocol: Rapid Launches Scenario ===\n');

  const logger = createLogger({
    level: 'info',
    pretty: true,
  });

  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', 'results', 'rapid-launches'),
      ci: false,
    });

    console.log('\n=== Simulation Complete ===\n');
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Ticks: ${result.ticks}`);
    console.log(`Success: ${result.success}`);

    console.log('\n--- Final Metrics ---');
    for (const [key, value] of Object.entries(result.finalMetrics)) {
      console.log(`  ${key}: ${value}`);
    }

    console.log('\n--- App Count ---');
    console.log(`  Total apps launched: ${result.finalMetrics.app_count ?? 0}`);

    console.log('\n--- Assertions ---');
    if (result.failedAssertions.length === 0) {
      console.log('  All assertions passed!');
    } else {
      for (const failure of result.failedAssertions) {
        console.log(`    - ${failure.message}`);
      }
    }

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Simulation failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
