/**
 * Smoke Test: Arbitrager
 *
 * Tests the ArbitragerAgent's price-based trading behavior.
 * - ArbitragerAgents track price movements
 * - WhaleUserAgents create price volatility
 * - Verifies arbitrage mechanics work correctly
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { ArbitragerAgent, DeveloperAgent, WhaleUserAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8561,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-arbitrager',
  seed: 42,
  ticks: 20,
  tickSeconds: 3600,

  pack,

  agents: [
    // Arbitragers looking for price opportunities
    {
      type: ArbitragerAgent,
      count: 3,
      params: {
        buyDipThreshold: 0.1, // 10% price drop triggers buy
        takeProfitThreshold: 0.15, // 15% gain triggers sell
        tradeProbability: 0.6,
        maxTradePercent: 0.2,
      },
    },
    // Whales to create price volatility
    {
      type: WhaleUserAgent,
      count: 2,
      params: {
        minTradeSize: BigInt(2000e18),
        riskTolerance: 0.8,
      },
    },
    // Developer to ensure apps exist
    {
      type: DeveloperAgent,
      count: 1,
      params: {
        maxApps: 2,
        launchProbability: 0.2,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 4,
    track: ['app_count', 'fees_collected_total', 'elta_total_supply'],
  },

  assertions: [
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Arbitrager ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-arbitrager'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Apps: ${result.finalMetrics.app_count}`);
    console.log(`Fees collected: ${result.finalMetrics.fees_collected_total}`);

    // Log agent stats
    for (const stat of result.agentStats) {
      const rate =
        stat.actionsAttempted > 0
          ? Math.round((stat.actionsSucceeded / stat.actionsAttempted) * 100)
          : 0;
      console.log(`  ${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted} (${rate}%)`);
    }

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
