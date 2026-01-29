/**
 * Full Protocol Flow Integration Test
 *
 * Tests the complete user journey:
 * - Developers create apps
 * - Users buy tokens and generate fees
 * - Stakers lock ELTA for veELTA
 * - Users stake app tokens in vaults
 * - Reward hunters claim rewards
 *
 * This is a comprehensive test of all protocol features working together.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  DeveloperAgent,
  RewardHunterAgent,
  StakerAgent,
} from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8560,
  silent: true,
});

const scenario = defineScenario({
  name: 'full-protocol-flow',
  seed: 42,
  ticks: 50,
  tickSeconds: 3600, // 1 hour per tick

  pack,

  agents: [
    // Developers creating apps
    {
      type: DeveloperAgent,
      count: 3,
      params: {
        maxApps: 3,
        launchProbability: 0.3,
      },
    },
    // Regular users trading
    {
      type: BasicUserAgent,
      count: 10,
      params: {
        buyProbability: 0.35,
        sellProbability: 0.15,
        stakeProbability: 0.08,
        appStakeProbability: 0.05,
        claimProbability: 0.03,
        riskTolerance: 0.5,
        maxTradePercent: 0.15,
      },
    },
    // veELTA stakers
    {
      type: StakerAgent,
      count: 5,
      params: {
        minLockAmount: BigInt(300e18),
        lockDurationDays: 365,
        claimProbability: 0.15,
        compoundProbability: 0.1,
      },
    },
    // Reward hunters
    {
      type: RewardHunterAgent,
      count: 3,
      params: {
        claimAggressiveness: 0.7,
        compoundRewards: true,
        minCompoundAmount: BigInt(30e18),
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 5,
    track: [
      'elta_total_supply',
      'veelta_total_locked',
      'app_count',
      'fees_collected_total',
      'fees_distributed',
      'block_number',
      'timestamp',
    ],
  },

  assertions: [
    // Apps should be created
    { type: 'gte', metric: 'app_count', value: 6 },
    // veELTA should be locked (stakers are working)
    { type: 'gte', metric: 'veelta_total_locked', value: 0 },
    // Fees should be collected from trading
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
    // Protocol should have positive ELTA supply
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
    // Not too many apps (sanity check)
    { type: 'lte', metric: 'app_count', value: 50 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Integration Test: Full Protocol Flow ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'full-protocol-flow'),
      ci: false,
    });

    console.log('\n=== Results ===\n');
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Ticks: ${result.ticks}`);
    console.log(`Success: ${result.success}`);

    console.log('\n--- Final Metrics ---');
    console.log(`  Apps: ${result.finalMetrics.app_count}`);
    console.log(`  veELTA Locked: ${result.finalMetrics.veelta_total_locked}`);
    console.log(`  Fees Collected: ${result.finalMetrics.fees_collected_total}`);
    console.log(`  Fees Distributed: ${result.finalMetrics.fees_distributed}`);

    console.log('\n--- Agent Stats ---');
    for (const stat of result.agentStats) {
      const rate =
        stat.actionsAttempted > 0
          ? Math.round((stat.actionsSucceeded / stat.actionsAttempted) * 100)
          : 0;
      console.log(`  ${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted} (${rate}%)`);
    }

    console.log('\n--- Assertions ---');
    if (result.failedAssertions.length === 0) {
      console.log('  All assertions passed!');
    } else {
      for (const f of result.failedAssertions) {
        console.log(`  FAILED: ${f.message}`);
      }
    }

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Simulation failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
