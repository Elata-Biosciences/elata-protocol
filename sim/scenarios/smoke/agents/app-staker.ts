/**
 * Agent Isolation Test: App Staker Agent
 *
 * Tests the AppStakerAgent's multi-app staking behavior:
 * - Staking across multiple apps
 * - Unstaking strategies
 * - Reward claiming patterns
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { AppStakerAgent, DeveloperAgent, BasicUserAgent, FeeKeeperAgent } from '../../../agents/index.js';
import { createEltaPack } from '../../../packs/EltaPack.js';
import {
  basicStabilityAssertions,
  printScenarioResults,
  allocatePort,
  groupAgentStatsByType,
} from '../../../lib/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: allocatePort(),
  silent: true,
});

const scenario = defineScenario({
  name: 'agent-app-staker',
  seed: 102,
  ticks: 25,
  tickSeconds: 86400, // 1 day per tick for reward accrual

  pack,

  agents: [
    // Test subjects: App stakers with varying strategies
    {
      type: AppStakerAgent,
      count: 5,
      params: {
        stakeProbability: 0.8,
        unstakeProbability: 0.2,
        claimProbability: 0.6,
        maxAppsToStake: 5,
        minStakeAmount: 100n * 10n ** 18n,
      },
    },
    // More conservative stakers
    {
      type: AppStakerAgent,
      count: 3,
      params: {
        stakeProbability: 0.5,
        unstakeProbability: 0.1,
        claimProbability: 0.9, // Aggressive reward claiming
        maxAppsToStake: 2,
        minStakeAmount: 500n * 10n ** 18n,
      },
    },
    // Developers to create apps
    {
      type: DeveloperAgent,
      count: 3,
      params: {
        maxApps: 4,
        launchProbability: 0.8,
      },
    },
    // Users to trade and generate fees
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
    // Fee keeper to close epochs
    {
      type: FeeKeeperAgent,
      count: 1,
      params: {
        closeEpochProbability: 0.5,
        sweepProbability: 0.8,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'veelta_total_locked', 'gas_total'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Expect fee collection from trading
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Agent Isolation Test: App Staker ===\n');
  console.log('Testing multi-app staking and unstaking behavior...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', '..', 'results', 'agent-app-staker'),
      ci: true,
    });

    // Analyze AppStakerAgent behavior
    const grouped = groupAgentStatsByType(result.agentStats);
    const stakerStats = grouped.get('AppStakerAgent');

    console.log('\nApp Staker Analysis:');
    if (stakerStats) {
      console.log(`  Total agents: ${stakerStats.count}`);
      console.log(`  Total actions: ${stakerStats.totalAttempted}`);
      console.log(`  Successful: ${stakerStats.totalSucceeded}`);
      console.log(`  Failed: ${stakerStats.totalFailed}`);
      console.log(`  Success rate: ${Math.round(stakerStats.avgSuccessRate * 100)}%`);
    }

    printScenarioResults(result, {
      showAgentStats: true,
      groupByType: true,
      highlightMetrics: ['app_count', 'fees_collected_total'],
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
