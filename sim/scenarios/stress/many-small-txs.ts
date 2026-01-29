/**
 * Stress Test: Many Small Transactions
 *
 * Tests high volume of small trades (10 ELTA each).
 * Verifies protocol handles dust-level transactions efficiently.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { BasicUserAgent, DeveloperAgent, SpammerAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';
import {
  basicStabilityAssertions,
  printScenarioResults,
  allocatePort,
  formatGas,
  formatElta,
} from '../../lib/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: allocatePort(),
  silent: true,
});

// Small trade amount: 10 ELTA
const SMALL_TRADE = 10n * 10n ** 18n;

const scenario = defineScenario({
  name: 'stress-many-small-txs',
  seed: 201,
  ticks: 15,
  tickSeconds: 3600,

  pack,

  agents: [
    // 100 users making small trades
    {
      type: BasicUserAgent,
      count: 100,
      params: {
        riskTolerance: 0.3,
        maxTradePercent: 0.01, // Very small trades
        tradeProbability: 0.8,
      },
    },
    // Spammers adding more small transactions
    {
      type: SpammerAgent,
      count: 5,
      params: {
        actionsPerTick: 15,
        actionTypes: ['buy', 'sell'],
        minActionAmount: 1n * 10n ** 18n,
        maxActionAmount: SMALL_TRADE,
      },
    },
    // Developers to create apps
    {
      type: DeveloperAgent,
      count: 3,
      params: {
        maxApps: 5,
        launchProbability: 0.7,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'gas_total'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Should handle many small transactions
  ],
});

async function main(): Promise<void> {
  console.log('=== Stress Test: Many Small Transactions ===\n');
  console.log(`Testing high volume of small trades (${formatElta(SMALL_TRADE)})...\n`);

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  const startTime = Date.now();

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'stress-many-small-txs'),
      ci: true,
    });

    const duration = Date.now() - startTime;

    console.log('\nSmall Transaction Analysis:');
    console.log(`  Duration: ${(duration / 1000).toFixed(1)}s`);
    console.log(`  Total agents: 108`);
    console.log(`  Gas used: ${formatGas(result.finalMetrics.gas_total as bigint)}`);

    // Analyze gas efficiency
    const totalActions = result.agentStats.reduce((sum, s) => sum + s.actionsAttempted, 0);
    const gasPerAction = Number(result.finalMetrics.gas_total as bigint) / totalActions;
    console.log(`  Gas per action: ${formatGas(BigInt(Math.floor(gasPerAction)))}`);

    printScenarioResults(result, {
      highlightMetrics: ['fees_collected_total', 'gas_total'],
      groupByType: true,
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Stress test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
