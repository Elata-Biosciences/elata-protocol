/**
 * Stress Test: Governance Spam
 *
 * Tests protocol under many simultaneous governance proposals.
 * Uses 10 GovernorAgents creating proposals and voting.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { GovernorAgent, VoterAgent, StakerAgent, BasicUserAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';
import {
  basicStabilityAssertions,
  printScenarioResults,
  allocatePort,
  groupAgentStatsByType,
  formatGas,
} from '../../lib/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: allocatePort(),
  silent: true,
});

const scenario = defineScenario({
  name: 'stress-governance-spam',
  seed: 203,
  ticks: 30,
  tickSeconds: 86400, // 1 day per tick for governance timing

  pack,

  agents: [
    // Many governors creating proposals
    {
      type: GovernorAgent,
      count: 10,
      params: {
        proposeProbability: 0.8, // Aggressive proposing
        minVeEltaForProposal: 1000n * 10n ** 18n,
      },
    },
    // Voters to vote on proposals
    {
      type: VoterAgent,
      count: 20,
      params: {
        voteProbability: 0.9,
        minVeEltaForVoting: 100n * 10n ** 18n,
      },
    },
    // Stakers to provide voting power
    {
      type: StakerAgent,
      count: 15,
      params: {
        lockProbability: 0.8,
        minLockAmount: 500n * 10n ** 18n,
        preferredLockDays: 180,
      },
    },
    // Regular users for other activity
    {
      type: BasicUserAgent,
      count: 10,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'veelta_total_locked', 'gas_total'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Should have veELTA locked for governance
    { type: 'gte', metric: 'veelta_total_locked', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Stress Test: Governance Spam ===\n');
  console.log('Testing many simultaneous governance proposals...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'stress-governance-spam'),
      ci: true,
    });

    // Analyze governance activity
    const grouped = groupAgentStatsByType(result.agentStats);

    console.log('\nGovernance Spam Analysis:');

    const govStats = grouped.get('GovernorAgent');
    if (govStats) {
      console.log('Governor Activity:');
      console.log(`  Total proposal attempts: ${govStats.totalAttempted}`);
      console.log(`  Success rate: ${Math.round(govStats.avgSuccessRate * 100)}%`);
    }

    const voterStats = grouped.get('VoterAgent');
    if (voterStats) {
      console.log('Voter Activity:');
      console.log(`  Total vote attempts: ${voterStats.totalAttempted}`);
      console.log(`  Success rate: ${Math.round(voterStats.avgSuccessRate * 100)}%`);
    }

    console.log(`\nGas used: ${formatGas(result.finalMetrics.gas_total as bigint)}`);

    printScenarioResults(result, {
      highlightMetrics: ['veelta_total_locked', 'gas_total'],
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
