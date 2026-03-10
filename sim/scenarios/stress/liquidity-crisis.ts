/**
 * Stress Test: Liquidity Crisis
 *
 * Simulates mass withdrawal / bank run scenario.
 * WhaleUserAgents with 90% sell bias create selling pressure.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { WhaleUserAgent, CautiousUserAgent, DeveloperAgent, BasicUserAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';
import {
  basicStabilityAssertions,
  printScenarioResults,
  allocatePort,
  groupAgentStatsByType,
} from '../../lib/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: allocatePort(),
  silent: true,
});

const scenario = defineScenario({
  name: 'stress-liquidity-crisis',
  seed: 202,
  ticks: 25,
  tickSeconds: 3600,

  pack,

  agents: [
    // Whales with heavy sell bias (panic sellers)
    {
      type: WhaleUserAgent,
      count: 10,
      params: {
        riskTolerance: 0.9,
        maxTradePercent: 0.5,
        sellBias: 0.9, // 90% sell probability
      },
    },
    // More moderate sellers
    {
      type: WhaleUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.7,
        maxTradePercent: 0.3,
        sellBias: 0.7,
      },
    },
    // Cautious users who will also sell
    {
      type: CautiousUserAgent,
      count: 15,
      params: {
        riskTolerance: 0.1,
        maxTradePercent: 0.1,
        sellThreshold: 0.02, // Very low threshold
        stopLossThreshold: 0.01,
      },
    },
    // Some buyers trying to catch the dip
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.8,
        maxTradePercent: 0.4,
        buyBias: 0.8,
      },
    },
    // Developers created apps earlier (bootstrap provides some)
    {
      type: DeveloperAgent,
      count: 2,
      params: {
        maxApps: 3,
        launchProbability: 0.5,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'gas_total', 'veelta_total_locked'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Protocol should survive liquidity crisis
  ],
});

async function main(): Promise<void> {
  console.log('=== Stress Test: Liquidity Crisis ===\n');
  console.log('Simulating mass withdrawal / bank run scenario...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'stress-liquidity-crisis'),
      ci: true,
    });

    // Analyze selling pressure
    const grouped = groupAgentStatsByType(result.agentStats);

    console.log('\nLiquidity Crisis Analysis:');
    console.log('Selling pressure from WhaleUserAgents:');
    const whaleStats = grouped.get('WhaleUserAgent');
    if (whaleStats) {
      console.log(`  Total whale actions: ${whaleStats.totalAttempted}`);
      console.log(`  Success rate: ${Math.round(whaleStats.avgSuccessRate * 100)}%`);
    }

    console.log('\nCautious user behavior:');
    const cautiousStats = grouped.get('CautiousUserAgent');
    if (cautiousStats) {
      console.log(`  Total actions: ${cautiousStats.totalAttempted}`);
      console.log(`  Success rate: ${Math.round(cautiousStats.avgSuccessRate * 100)}%`);
    }

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
