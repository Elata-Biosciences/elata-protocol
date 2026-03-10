/**
 * Stress Test: Flash Attack
 *
 * Simulates flash loan attack patterns.
 * ManipulatorAgent + WhaleUserAgent coordinating rapid large trades.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { ManipulatorAgent, WhaleUserAgent, BasicUserAgent, DeveloperAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';
import {
  basicStabilityAssertions,
  printScenarioResults,
  allocatePort,
  groupAgentStatsByType,
  formatElta,
} from '../../lib/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: allocatePort(),
  silent: true,
});

const scenario = defineScenario({
  name: 'stress-flash-attack',
  seed: 204,
  ticks: 15,
  tickSeconds: 60, // 1 minute per tick - fast pace for flash attacks

  pack,

  agents: [
    // Attackers using flash-loan-like patterns
    {
      type: ManipulatorAgent,
      count: 3,
      params: {
        strategy: 'flash_attack',
        aggressiveness: 0.95,
        maxPositionSize: 500000n * 10n ** 18n, // Large positions
      },
    },
    // Coordinating whales
    {
      type: WhaleUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.95,
        maxTradePercent: 0.8, // Very large trades
        tradeProbability: 0.9,
      },
    },
    // Additional manipulators with different strategies
    {
      type: ManipulatorAgent,
      count: 2,
      params: {
        strategy: 'pump_and_dump',
        aggressiveness: 0.9,
        targetPriceMultiplier: 3.0,
      },
    },
    // Regular users as potential victims
    {
      type: BasicUserAgent,
      count: 15,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
    // Developers for targets
    {
      type: DeveloperAgent,
      count: 2,
      params: {
        maxApps: 4,
        launchProbability: 0.8,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'gas_total'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Protocol should survive flash attack attempts
  ],
});

async function main(): Promise<void> {
  console.log('=== Stress Test: Flash Attack ===\n');
  console.log('Simulating flash loan attack patterns...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'stress-flash-attack'),
      ci: true,
    });

    // Analyze attack patterns
    const grouped = groupAgentStatsByType(result.agentStats);

    console.log('\nFlash Attack Analysis:');

    const manipStats = grouped.get('ManipulatorAgent');
    if (manipStats) {
      console.log('Manipulator Activity:');
      console.log(`  Total attack attempts: ${manipStats.totalAttempted}`);
      console.log(`  Success rate: ${Math.round(manipStats.avgSuccessRate * 100)}%`);
    }

    const whaleStats = grouped.get('WhaleUserAgent');
    if (whaleStats) {
      console.log('Whale Activity:');
      console.log(`  Total trades: ${whaleStats.totalAttempted}`);
      console.log(`  Success rate: ${Math.round(whaleStats.avgSuccessRate * 100)}%`);
    }

    // Check impact on regular users
    const basicStats = grouped.get('BasicUserAgent');
    if (basicStats) {
      console.log('\nImpact on Regular Users:');
      console.log(`  Actions attempted: ${basicStats.totalAttempted}`);
      console.log(`  Success rate: ${Math.round(basicStats.avgSuccessRate * 100)}%`);
    }

    console.log(`\nTotal fees collected: ${formatElta(result.finalMetrics.fees_collected_total as bigint)}`);

    printScenarioResults(result, {
      highlightMetrics: ['fees_collected_total', 'gas_total', 'app_count'],
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
