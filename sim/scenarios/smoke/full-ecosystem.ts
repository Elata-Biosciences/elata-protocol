/**
 * Smoke Test: Full Ecosystem
 *
 * Tests the complete ecosystem with all agent types working together.
 * This is a comprehensive test that validates agent interactions.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  AppStakerAgent,
  ArbitragerAgent,
  BasicUserAgent,
  DeveloperAgent,
  FeeKeeperAgent,
  GovernorAgent,
  RewardHunterAgent,
  StakerAgent,
  VoterAgent,
  WhaleUserAgent,
} from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8565,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-full-ecosystem',
  seed: 42,
  ticks: 20,
  tickSeconds: 3600,

  pack,

  agents: [
    // Core users
    { type: BasicUserAgent, count: 5 },
    { type: WhaleUserAgent, count: 2, params: { minTradeSize: BigInt(1000e18) } },

    // Developers
    { type: DeveloperAgent, count: 2, params: { maxApps: 3 } },

    // Stakers
    { type: StakerAgent, count: 3, params: { minLockAmount: BigInt(500e18) } },
    { type: AppStakerAgent, count: 2 },

    // Reward seekers
    { type: RewardHunterAgent, count: 2 },

    // Market makers
    { type: ArbitragerAgent, count: 2 },

    // Infrastructure
    { type: FeeKeeperAgent, count: 1 },

    // Governance
    { type: GovernorAgent, count: 1, params: { proposeProbability: 0.1 } },
    { type: VoterAgent, count: 2 },
  ],

  metrics: {
    sampleEveryTicks: 4,
    track: [
      'app_count',
      'graduated_apps',
      'veelta_total_locked',
      'fees_collected_total',
      'elta_total_supply',
    ],
  },

  assertions: [
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'veelta_total_locked', value: 0 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Full Ecosystem ===\n');
  console.log('Testing all agent types working together...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-full-ecosystem'),
      ci: true,
    });

    console.log(`\n${'='.repeat(50)}`);
    console.log(`Result: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`${'='.repeat(50)}`);

    console.log('\nFinal Metrics:');
    console.log(`  Apps: ${result.finalMetrics.app_count}`);
    console.log(`  Graduated Apps: ${result.finalMetrics.graduated_apps ?? 0}`);
    console.log(`  veELTA Locked: ${result.finalMetrics.veelta_total_locked}`);
    console.log(`  Fees Collected: ${result.finalMetrics.fees_collected_total}`);

    console.log('\nAgent Performance:');

    // Group stats by agent type
    const agentTypes: Record<string, { success: number; total: number }> = {};
    for (const stat of result.agentStats) {
      const type = stat.id.replace(/-\d+$/, '');
      if (!agentTypes[type]) {
        agentTypes[type] = { success: 0, total: 0 };
      }
      agentTypes[type].success += stat.actionsSucceeded;
      agentTypes[type].total += stat.actionsAttempted;
    }

    for (const [type, stats] of Object.entries(agentTypes)) {
      const rate = stats.total > 0 ? Math.round((stats.success / stats.total) * 100) : 0;
      console.log(`  ${type}: ${stats.success}/${stats.total} (${rate}%)`);
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
