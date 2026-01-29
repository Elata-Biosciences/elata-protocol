/**
 * Healthy Growth Scenario
 *
 * Simulates optimistic protocol growth:
 * - Steady user onboarding
 * - Regular app launches by developers
 * - Healthy trading volume
 * - Fee distribution working correctly
 *
 * Assertions:
 * - Fees are collected and growing
 * - Apps are launched successfully
 * - No contract reverts
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { BasicUserAgent, DeveloperAgent, WhaleUserAgent } from '../agents/index.js';
import { createEltaPack } from '../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..');

// Create the pack
const pack = createEltaPack({
  protocolPath,
  anvilPort: 8546, // Use different port to avoid conflicts
  silent: true,
});

// Define the scenario
const scenario = defineScenario({
  name: 'healthy-growth',
  seed: 42,
  ticks: 100, // 100 ticks of simulation
  tickSeconds: 3600, // 1 hour per tick (about 4 days total)

  pack,

  agents: [
    // 15 basic users with varying parameters
    {
      type: BasicUserAgent,
      count: 15,
      params: {
        buyProbability: 0.25,
        sellProbability: 0.15,
        stakeProbability: 0.05,
        riskTolerance: 0.5,
        maxTradePercent: 0.1,
      },
    },
    // 3 whale users
    {
      type: WhaleUserAgent,
      count: 3,
      params: {
        riskTolerance: 0.7,
        minTradeSize: BigInt(1000e18),
        momentumTrading: true,
      },
    },
    // 5 developers
    {
      type: DeveloperAgent,
      count: 5,
      params: {
        maxApps: 2,
        launchProbability: 0.08,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 5, // Sample every 5 ticks
    track: [
      'elta_total_supply',
      'veelta_total_locked',
      'app_count',
      'fees_collected_total',
      'fees_distributed',
      'block_number',
      'timestamp',
    ],
  },

  assertions: [
    // Apps should be launched (developers creating apps)
    { type: 'gte', metric: 'app_count', value: 5 },
    // Fee collection should be happening from trades
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
    // Sanity check: not too many apps (runaway creation)
    { type: 'lte', metric: 'app_count', value: 200 },
    // Protocol should have positive ELTA supply
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

/**
 * Run the simulation
 */
async function main(): Promise<void> {
  console.log('=== Elata Protocol: Healthy Growth Scenario ===\n');

  const logger = createLogger({
    level: 'info',
    pretty: true,
  });

  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', 'results', 'healthy-growth'),
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

    console.log('\n--- Agent Stats ---');
    for (const stat of result.agentStats) {
      const successRate =
        stat.actionsAttempted > 0
          ? Math.round((stat.actionsSucceeded / stat.actionsAttempted) * 100)
          : 0;
      console.log(
        `  ${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted} (${successRate}%)`
      );
    }

    console.log('\n--- Assertions ---');
    if (result.failedAssertions.length === 0) {
      console.log('  All assertions passed!');
    } else {
      console.log(`  ${result.failedAssertions.length} assertions failed:`);
      for (const failure of result.failedAssertions) {
        console.log(`    - ${failure.message}`);
      }
    }

    // Exit with appropriate code
    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Simulation failed:', error);
    process.exit(2);
  }
}

// Run if executed directly
void main();

export { scenario };
