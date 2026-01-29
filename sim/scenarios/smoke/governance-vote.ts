/**
 * Smoke Test: Governance Voting
 *
 * Tests governance participation agents.
 * - GovernorAgent creates proposals and votes
 * - VoterAgent participates in voting
 * - StakerAgents provide veELTA voting power
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { BasicUserAgent, GovernorAgent, StakerAgent, VoterAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8562,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-governance',
  seed: 42,
  ticks: 15,
  tickSeconds: 3600,

  pack,

  agents: [
    // Governor to create and manage proposals
    {
      type: GovernorAgent,
      count: 1,
      params: {
        proposeProbability: 0.2,
        voteProbability: 0.8,
        minVotingPower: BigInt(1000e18),
        lockDurationDays: 365,
      },
    },
    // Voters to participate
    {
      type: VoterAgent,
      count: 3,
      params: {
        voteProbability: 0.7,
        forBias: 0.6,
        abstainProbability: 0.1,
        minVotingPower: BigInt(500e18),
      },
    },
    // Stakers to provide voting power
    {
      type: StakerAgent,
      count: 3,
      params: {
        minLockAmount: BigInt(500e18),
        lockDurationDays: 365,
      },
    },
    // Basic users for ecosystem activity
    {
      type: BasicUserAgent,
      count: 2,
      params: {
        buyProbability: 0.3,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 3,
    track: ['app_count', 'veelta_total_locked', 'elta_total_supply'],
  },

  assertions: [
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'veelta_total_locked', value: 0 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Governance Voting ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-governance'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Apps: ${result.finalMetrics.app_count}`);
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
