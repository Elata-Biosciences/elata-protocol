/**
 * Agent Isolation Test: Spammer Agent
 *
 * Tests the SpammerAgent's high-volume transaction handling:
 * - Maximum transaction throughput
 * - Gas optimization
 * - Protocol resilience under load
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { SpammerAgent, DeveloperAgent, BasicUserAgent } from '../../../agents/index.js';
import { createEltaPack } from '../../../packs/EltaPack.js';
import {
  basicStabilityAssertions,
  printScenarioResults,
  allocatePort,
  groupAgentStatsByType,
  formatGas,
} from '../../../lib/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: allocatePort(),
  silent: true,
});

const scenario = defineScenario({
  name: 'agent-spammer',
  seed: 104,
  ticks: 15,
  tickSeconds: 3600,

  pack,

  agents: [
    // Test subjects: Spammers with different intensities
    {
      type: SpammerAgent,
      count: 3,
      params: {
        actionsPerTick: 10,
        actionTypes: ['buy', 'sell'],
        minActionAmount: 10n * 10n ** 18n,
        maxActionAmount: 100n * 10n ** 18n,
      },
    },
    // Higher intensity spammers
    {
      type: SpammerAgent,
      count: 2,
      params: {
        actionsPerTick: 20,
        actionTypes: ['buy', 'sell', 'transfer'],
        minActionAmount: 1n * 10n ** 18n,
        maxActionAmount: 50n * 10n ** 18n,
      },
    },
    // Developers to create targets
    {
      type: DeveloperAgent,
      count: 2,
      params: {
        maxApps: 4,
        launchProbability: 0.9,
      },
    },
    // Regular users to see if they can still operate
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'gas_total'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Expect high gas usage from spam
  ],
});

async function main(): Promise<void> {
  console.log('=== Agent Isolation Test: Spammer ===\n');
  console.log('Testing high-volume transaction handling...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', '..', 'results', 'agent-spammer'),
      ci: true,
    });

    // Analyze SpammerAgent behavior
    const grouped = groupAgentStatsByType(result.agentStats);
    const spamStats = grouped.get('SpammerAgent');

    console.log('\nSpammer Analysis:');
    if (spamStats) {
      console.log(`  Total agents: ${spamStats.count}`);
      console.log(`  Total spam actions: ${spamStats.totalAttempted}`);
      console.log(`  Successful: ${spamStats.totalSucceeded}`);
      console.log(`  Failed: ${spamStats.totalFailed}`);
      console.log(`  Success rate: ${Math.round(spamStats.avgSuccessRate * 100)}%`);
    }

    // Check if regular users were impacted
    const basicStats = grouped.get('BasicUserAgent');
    console.log('\nImpact on Regular Users:');
    if (basicStats) {
      console.log(`  BasicUser actions: ${basicStats.totalAttempted}`);
      console.log(`  Success rate: ${Math.round(basicStats.avgSuccessRate * 100)}%`);
    }

    // Gas analysis
    const totalGas = result.finalMetrics.gas_total as bigint | number | undefined;
    if (totalGas) {
      console.log(`\nGas Usage: ${formatGas(totalGas)}`);
    }

    printScenarioResults(result, {
      showAgentStats: true,
      groupByType: true,
      highlightMetrics: ['gas_total', 'fees_collected_total'],
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
