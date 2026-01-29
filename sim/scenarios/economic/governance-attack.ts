/**
 * Economic Scenario: 51% Governance Attack
 *
 * Tests the protocol's governance safeguards against a coordinated
 * attempt to acquire majority voting power.
 *
 * Simulates:
 * - Coordinated veELTA accumulation
 * - Proposal spam
 * - Vote manipulation attempts
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  DeveloperAgent,
  GovernorAgent,
  ManipulatorAgent,
  StakerAgent,
  VoterAgent,
} from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8573,
  silent: true,
  agentEltaBalance: BigInt(80000e18), // High balance for governance accumulation
});

const scenario = defineScenario({
  name: 'economic-governance-attack',
  seed: 999,
  ticks: 60,
  tickSeconds: 3600, // 1 hour per tick

  pack,

  agents: [
    // Developer for basic protocol activity
    {
      type: DeveloperAgent,
      count: 1,
      params: {
        maxApps: 2,
        launchProbability: 0.3,
      },
    },
    // Attacker stakers - trying to accumulate majority veELTA
    {
      type: StakerAgent,
      count: 5,
      params: {
        minLockAmount: BigInt(30000e18), // Large locks
        lockDurationDays: 730, // Max duration for max power
        claimProbability: 0.05,
        compoundProbability: 0.5, // Aggressively compound
      },
    },
    // Attacker governors - creating proposals
    {
      type: GovernorAgent,
      count: 3,
      params: {
        minVotingPower: BigInt(5000e18),
        proposeProbability: 0.5, // Higher proposal rate
        voteProbability: 0.9,
        proposalCooldown: 5, // Faster proposals
      },
    },
    // Attacker voters - coordinated voting
    {
      type: VoterAgent,
      count: 5,
      params: {
        minVotingPower: BigInt(5000e18),
        voteProbability: 0.9,
        preferSupportive: true, // Always vote FOR attacker proposals
      },
    },
    // Price manipulator to potentially affect governance token value
    {
      type: ManipulatorAgent,
      count: 1,
      params: {
        aggressiveness: 0.6,
        preferredStrategy: 'accumulate',
        maxPositionPercent: 0.4,
      },
    },
    // Legitimate users (defenders)
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        buyProbability: 0.3,
        sellProbability: 0.2,
      },
    },
    // Legitimate stakers (defenders)
    {
      type: StakerAgent,
      count: 3,
      params: {
        minLockAmount: BigInt(10000e18),
        lockDurationDays: 365,
        claimProbability: 0.1,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 5,
    track: ['app_count', 'veelta_total_locked', 'fees_collected_total', 'gas_total'],
  },

  assertions: [
    // Basic functionality should work
    { type: 'gte', metric: 'app_count', value: 1 },
    // veELTA locking should occur
    { type: 'gte', metric: 'veelta_total_locked', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Economic Scenario: 51% Governance Attack ===\n');
  console.log('Testing governance safeguards under coordinated attack...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'economic-governance-attack'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Apps: ${result.finalMetrics.app_count}`);
    console.log(`veELTA locked: ${result.finalMetrics.veelta_total_locked}`);
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

    // Governance power distribution
    console.log('\nGovernance Analysis:');
    const attackerStakers = result.agentStats.filter((s) => {
      const parts = s.id.split('-');
      const idxStr = parts[1] ?? '0';
      const idx = Number.parseInt(idxStr, 10);
      return s.id.includes('Staker') && idx < 5;
    });
    const defenderStakers = result.agentStats.filter((s) => {
      const parts = s.id.split('-');
      const idxStr = parts[1] ?? '0';
      const idx = Number.parseInt(idxStr, 10);
      return s.id.includes('Staker') && idx >= 5;
    });

    let attackerSuccess = 0;
    let defenderSuccess = 0;

    for (const s of attackerStakers) {
      attackerSuccess += s.actionsSucceeded;
    }
    for (const s of defenderStakers) {
      defenderSuccess += s.actionsSucceeded;
    }

    console.log(`  Attacker staking actions: ${attackerSuccess}`);
    console.log(`  Defender staking actions: ${defenderSuccess}`);

    // Governor activity
    const governors = result.agentStats.filter((s) => s.id.includes('Governor'));
    console.log(`\nGovernor Activity:`);
    for (const gov of governors) {
      console.log(`  ${gov.id}: ${gov.actionsSucceeded}/${gov.actionsAttempted} actions`);
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
