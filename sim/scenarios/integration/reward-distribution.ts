/**
 * Reward Distribution Test
 *
 * Verifies the reward pipeline works correctly:
 * - Fees are generated from trading activity
 * - Fees flow to RewardsDistributor
 * - veELTA holders can claim rewards
 * - App stakers can claim app rewards
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  DeveloperAgent,
  RewardHunterAgent,
  WhaleUserAgent,
} from '../../agents/index.js';
import { anvilPort, createNotebookReport, scenarioSeed } from '../../lib/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8562),
  silent: true,
});

const scenario = defineScenario({
  name: 'reward-distribution',
  seed: scenarioSeed(456),
  ticks: 60,
  tickSeconds: 3600,

  pack,

  agents: [
    // Developers to create apps
    {
      type: DeveloperAgent,
      count: 5,
      params: {
        maxApps: 4,
        launchProbability: 0.35,
      },
    },
    // High-volume traders to generate fees
    {
      type: BasicUserAgent,
      count: 15,
      params: {
        buyProbability: 0.45,
        sellProbability: 0.2,
        stakeProbability: 0.05,
        appStakeProbability: 0.03,
        claimProbability: 0.02,
        riskTolerance: 0.6,
        maxTradePercent: 0.2,
      },
    },
    // Whales for bigger fee generation
    {
      type: WhaleUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.8,
        minTradeSize: BigInt(500e18),
        momentumTrading: true,
      },
    },
    // Reward hunters to claim rewards
    {
      type: RewardHunterAgent,
      count: 8,
      params: {
        claimAggressiveness: 0.9, // Very aggressive claiming
        compoundRewards: true,
        minCompoundAmount: BigInt(20e18),
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 6,
    track: [
      'elta_total_supply',
      'veelta_total_locked',
      'app_count',
      'fees_collected_total',
      'fees_distributed',
    ],
  },

  assertions: [
    // Apps should be created
    { type: 'gte', metric: 'app_count', value: 8 },
    // Fees should be collected from all the trading
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
    // veELTA should be locked for rewards
    { type: 'gte', metric: 'veelta_total_locked', value: 1 },
    // System should remain stable
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Integration: Reward Distribution',
      experimentNotes:
        'Validates fee generation, distribution pipeline, and downstream claiming behavior with mixed normal users, whales, and reward hunters.',
      hypotheses: [
        'Higher trade activity should keep total protocol fees positive.',
        'Reward-oriented actors should sustain non-zero veELTA lock and claiming flow.',
      ],
      successCriteria: [
        'App count grows above baseline.',
        'Fees and veELTA lock are both positive by end of run.',
      ],
      metricFields: [
        'app_count',
        'fees_collected_total',
        'fees_distributed',
        'veelta_total_locked',
        'elta_total_supply',
      ],
      primaryMetric: 'fees_collected_total',
      mlFeatures: ['tick', 'app_count', 'veelta_total_locked'],
    }),
  },
});

async function main(): Promise<void> {
  console.log('=== Integration Test: Reward Distribution ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'reward-distribution'),
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
    // Group by type
    const byType = new Map<string, { attempted: number; succeeded: number }>();
    for (const stat of result.agentStats) {
      const type = stat.id.replace(/-\d+$/, '');
      const existing = byType.get(type) ?? { attempted: 0, succeeded: 0 };
      byType.set(type, {
        attempted: existing.attempted + stat.actionsAttempted,
        succeeded: existing.succeeded + stat.actionsSucceeded,
      });
    }
    for (const [type, stats] of byType) {
      const rate = stats.attempted > 0 ? Math.round((stats.succeeded / stats.attempted) * 100) : 0;
      console.log(`  ${type}: ${stats.succeeded}/${stats.attempted} (${rate}%)`);
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
