/**
 * Economic Scenario: Whale Accumulation Attack
 *
 * Tests concentrated buying behavior and its impact on:
 * - Token distribution
 * - Price dynamics
 * - Governance implications (if whale locks veELTA)
 *
 * Simulates a whale accumulating large positions to potentially
 * influence governance or manipulate markets.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  DeveloperAgent,
  GovernorAgent,
  StakerAgent,
  WhaleUserAgent,
} from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8571,
  silent: true,
  agentEltaBalance: BigInt(100000e18), // High balance for whale accumulation
});

const scenario = defineScenario({
  name: 'economic-whale-accumulation',
  seed: 456,
  ticks: 40,
  tickSeconds: 3600, // 1 hour per tick

  pack,

  agents: [
    // Developer to create apps
    {
      type: DeveloperAgent,
      count: 1,
      params: {
        maxApps: 2,
        launchProbability: 0.5,
      },
    },
    // Aggressive whale accumulating positions
    {
      type: WhaleUserAgent,
      count: 3,
      params: {
        minTradeSize: BigInt(10000e18),
        maxTradeSize: BigInt(50000e18),
        buyProbability: 0.9, // Almost always buying
        sellProbability: 0.05, // Rarely selling
        preferredApps: [], // Buy across all apps
      },
    },
    // Whale staker - locks ELTA for governance power
    {
      type: StakerAgent,
      count: 2,
      params: {
        minLockAmount: BigInt(20000e18),
        lockDurationDays: 730, // Max lock
        claimProbability: 0.1,
        compoundProbability: 0.3,
      },
    },
    // Governor whale - participates in governance
    {
      type: GovernorAgent,
      count: 1,
      params: {
        minVotingPower: BigInt(10000e18),
        proposeProbability: 0.3,
        voteProbability: 0.8,
      },
    },
    // Normal users (fewer in number)
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        buyProbability: 0.3,
        sellProbability: 0.2,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 5,
    track: ['app_count', 'veelta_total_locked', 'fees_collected_total', 'gas_total'],
  },

  assertions: [
    // Apps should be created
    { type: 'gte', metric: 'app_count', value: 1 },
    // Some veELTA should be locked (governance setup)
    { type: 'gte', metric: 'veelta_total_locked', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Economic Scenario: Whale Accumulation Attack ===\n');
  console.log('Testing concentrated buying and governance implications...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'economic-whale-accumulation'),
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

    // Concentration metrics
    console.log('\nConcentration Analysis:');
    for (const [key, value] of Object.entries(result.finalMetrics)) {
      if (key.includes('_price') || key.includes('_raised') || key.includes('pnl')) {
        console.log(`  ${key}: ${value}`);
      }
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
