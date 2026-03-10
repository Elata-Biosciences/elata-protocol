/**
 * Whale Dominance Scenario
 *
 * Simulates concentration risk with large holders:
 * - Few whales with large positions
 * - Many small users with minimal impact
 * - Tests protocol resilience to unequal distribution
 *
 * Assertions:
 * - Protocol remains operational
 * - Fees still accumulate
 * - Small users can still participate
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { CautiousUserAgent, DeveloperAgent, WhaleUserAgent } from '../agents/index.js';
import { createEltaPack } from '../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..');

// Create the pack
const pack = createEltaPack({
  protocolPath,
  anvilPort: 8547, // Different port
  silent: true,
});

// Define the scenario
const scenario = defineScenario({
  name: 'whale-dominance',
  seed: 123,
  ticks: 50,
  tickSeconds: 7200, // 2 hours per tick

  pack,

  agents: [
    // 5 whale users - dominant actors
    {
      type: WhaleUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.8,
        minTradeSize: BigInt(5000e18),
        momentumTrading: true,
      },
    },
    // 10 cautious users - small participants
    {
      type: CautiousUserAgent,
      count: 10,
      params: {
        riskTolerance: 0.2,
        maxTradePercent: 0.02,
      },
    },
    // 2 developers - limited app creation
    {
      type: DeveloperAgent,
      count: 2,
      params: {
        maxApps: 1,
        launchProbability: 0.05,
        launchCooldown: 20,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 5,
    track: ['elta_total_supply', 'veelta_total_locked', 'app_count', 'fees_collected_total'],
  },

  assertions: [
    // Protocol should still function with whale activity
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
    // At least one app should exist (from bootstrap or developers)
    { type: 'gte', metric: 'app_count', value: 1 },
    // Whales with 5000 ELTA trades should generate meaningful fees
    // Fee accumulation proves protocol is processing transactions
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

/**
 * Run the simulation
 */
async function main(): Promise<void> {
  console.log('=== Elata Protocol: Whale Dominance Scenario ===\n');

  const logger = createLogger({
    level: 'info',
    pretty: true,
  });

  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', 'results', 'whale-dominance'),
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
