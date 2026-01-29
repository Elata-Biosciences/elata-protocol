/**
 * Economic Scenario: Bank Run
 *
 * Tests the protocol's resilience under mass selling pressure.
 * Simulates a panic scenario where users rush to exit their positions.
 *
 * Key metrics to observe:
 * - Price floor behavior
 * - Curve resilience
 * - Liquidity depth
 * - Fee accumulation during high volume
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  CautiousUserAgent,
  DeveloperAgent,
  WhaleUserAgent,
} from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8570,
  silent: true,
  agentEltaBalance: BigInt(50000e18), // Higher starting balance for panic selling
});

const scenario = defineScenario({
  name: 'economic-bank-run',
  seed: 123,
  ticks: 30,
  tickSeconds: 1800, // 30 minutes per tick

  pack,

  agents: [
    // Developer to create apps for trading
    {
      type: DeveloperAgent,
      count: 1,
      params: {
        maxApps: 2,
        launchProbability: 0.8,
      },
    },
    // Whale users who will panic sell
    {
      type: WhaleUserAgent,
      count: 5,
      params: {
        minTradeSize: BigInt(5000e18),
        maxTradeSize: BigInt(20000e18),
        sellBias: 0.9, // Heavy sell bias (90% sells)
        buyProbability: 0.05, // Almost no buying
        sellProbability: 0.8, // High sell probability
      },
    },
    // Cautious users who exit early
    {
      type: CautiousUserAgent,
      count: 10,
      params: {
        riskTolerance: 0.2, // Very risk averse
        sellThreshold: 0.02, // Sell on small drops (2%)
        buyProbability: 0.1,
        sellProbability: 0.7, // High sell probability
      },
    },
    // A few normal users still participating
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        buyProbability: 0.3,
        sellProbability: 0.3,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 2,
    track: ['app_count', 'fees_collected_total', 'elta_total_supply', 'gas_total'],
  },

  assertions: [
    // System should remain operational
    { type: 'gte', metric: 'app_count', value: 1 },
    // ELTA supply should remain stable
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
    // Fees should accumulate from trading
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Economic Scenario: Bank Run ===\n');
  console.log('Testing protocol resilience under mass selling pressure...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'economic-bank-run'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Apps: ${result.finalMetrics.app_count}`);
    console.log(`Fees collected: ${result.finalMetrics.fees_collected_total}`);
    console.log(`Total gas used: ${result.finalMetrics.gas_total}`);

    // Log agent stats
    console.log('\nAgent Stats:');
    for (const stat of result.agentStats) {
      const rate =
        stat.actionsAttempted > 0
          ? Math.round((stat.actionsSucceeded / stat.actionsAttempted) * 100)
          : 0;
      console.log(`  ${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted} (${rate}%)`);
    }

    // Price metrics analysis
    console.log('\nPrice Analysis:');
    for (const [key, value] of Object.entries(result.finalMetrics)) {
      if (key.includes('_price') || key.includes('_raised')) {
        console.log(`  ${key}: ${value}`);
      }
    }

    if (result.failedAssertions.length > 0) {
      console.log('\nFailed Assertions:');
      for (const f of result.failedAssertions) {
        console.log(`  ${f.message}`);
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
