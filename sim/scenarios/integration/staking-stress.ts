/**
 * Staking Stress Test
 *
 * Heavy staking activity to stress test:
 * - VeELTA contract (many locks, extends, increases)
 * - AppStakingVault contracts (many stakes, unstakes)
 * - Rewards distribution under load
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { AppStakerAgent, DeveloperAgent, StakerAgent } from '../../agents/index.js';
import { anvilPort, createNotebookReport, scenarioSeed } from '../../lib/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8561),
  silent: true,
});

const scenario = defineScenario({
  name: 'staking-stress',
  seed: scenarioSeed(123),
  ticks: 30,
  tickSeconds: 3600,

  pack,

  agents: [
    // Developers to create apps for staking
    {
      type: DeveloperAgent,
      count: 3,
      params: {
        maxApps: 5,
        launchProbability: 0.5,
      },
    },
    // Heavy veELTA stakers
    {
      type: StakerAgent,
      count: 15,
      params: {
        minLockAmount: BigInt(200e18),
        lockDurationDays: 365,
        claimProbability: 0.25,
        compoundProbability: 0.15,
      },
    },
    // Heavy app token stakers
    {
      type: AppStakerAgent,
      count: 12,
      params: {
        buyToStakeProbability: 0.4,
        stakeProbability: 0.5,
        claimProbability: 0.25,
        unstakeProbability: 0.08,
        minStakeAmount: BigInt(30e18),
        targetApps: 4,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 3,
    track: ['elta_total_supply', 'veelta_total_locked', 'app_count', 'fees_collected_total'],
  },

  assertions: [
    // Apps should be created for staking
    { type: 'gte', metric: 'app_count', value: 5 },
    // veELTA staking should happen
    { type: 'gte', metric: 'veelta_total_locked', value: 1 },
    // System should remain stable
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Integration: Staking Stress',
      experimentNotes:
        'Applies heavy concurrent veELTA and app-staking activity to validate staking-path reliability under sustained load.',
      hypotheses: [
        'High staking throughput should preserve positive veELTA lock depth.',
        'Protocol stays stable while staking and claiming paths are saturated.',
      ],
      successCriteria: [
        'App count exceeds staking baseline.',
        'veELTA lock and ELTA supply remain positive through run.',
      ],
      metricFields: [
        'app_count',
        'veelta_total_locked',
        'fees_collected_total',
        'elta_total_supply',
      ],
      primaryMetric: 'veelta_total_locked',
      mlFeatures: ['tick', 'app_count', 'fees_collected_total'],
    }),
  },
});

async function main(): Promise<void> {
  console.log('=== Integration Test: Staking Stress ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'staking-stress'),
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

    console.log('\n--- Agent Stats ---');
    let totalAttempted = 0;
    let totalSucceeded = 0;
    for (const stat of result.agentStats) {
      totalAttempted += stat.actionsAttempted;
      totalSucceeded += stat.actionsSucceeded;
    }
    const overallRate =
      totalAttempted > 0 ? Math.round((totalSucceeded / totalAttempted) * 100) : 0;
    console.log(`  Total: ${totalSucceeded}/${totalAttempted} (${overallRate}%)`);

    // Show by agent type
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
