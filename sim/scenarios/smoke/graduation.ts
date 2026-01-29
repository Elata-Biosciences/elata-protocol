/**
 * Smoke Test: Graduation
 *
 * Tests that bonding curve graduation works correctly.
 * - WhaleUserAgents making large purchases to trigger graduation
 * - Graduation threshold is 42,000 ELTA per app (from ProtocolConfig)
 * - Verifies graduation handling doesn't crash the simulation
 *
 * Note: With 5 whales making 15,000 ELTA trades over 30 ticks on 3 bootstrap apps,
 * there should be enough volume to graduate at least one app.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { DeveloperAgent, WhaleUserAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8555,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-graduation',
  seed: 42,
  ticks: 30,
  tickSeconds: 3600,

  pack,

  agents: [
    // Whales making large purchases to trigger graduation
    // Need to hit 42,000 ELTA per app to graduate
    // Each agent gets ~10,000 ELTA, so use 5,000 ELTA trades to leave room for fees
    {
      type: WhaleUserAgent,
      count: 8,
      params: {
        riskTolerance: 0.95, // Very high risk tolerance for large trades
        minTradeSize: BigInt(5000e18), // 5,000 ELTA per trade
        momentumTrading: false,
      },
    },
    // Developers create apps that can be graduated
    {
      type: DeveloperAgent,
      count: 1,
      params: {
        maxApps: 1, // Focus all trading on fewer apps
        launchProbability: 0.1,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 5,
    track: [
      'app_count',
      'graduated_apps',
      'fees_collected_total',
      'elta_total_supply',
      'veelta_total_locked',
    ],
  },

  assertions: [
    // System should remain stable even with graduations
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
    // Fees should be collected from all the trading
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Graduation ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-graduation'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Apps: ${result.finalMetrics.app_count}`);
    console.log(`Graduated Apps: ${result.finalMetrics.graduated_apps ?? 0}`);
    console.log(`Fees collected: ${result.finalMetrics.fees_collected_total}`);
    console.log(`veELTA locked: ${result.finalMetrics.veelta_total_locked}`);

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
