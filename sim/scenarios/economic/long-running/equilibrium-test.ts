/**
 * Long-Running Economic Validation: Equilibrium Test
 *
 * Simulates 1000 ticks to test fee/reward equilibrium.
 * 40 mixed agents with balanced activities.
 *
 * Focus: Economic equilibrium, reward sustainability, fee distribution balance
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  WhaleUserAgent,
  CautiousUserAgent,
  DeveloperAgent,
  StakerAgent,
  AppStakerAgent,
  RewardHunterAgent,
  FeeKeeperAgent,
} from '../../../agents/index.js';
import { createEltaPack } from '../../../packs/EltaPack.js';
import {
  economicAssertions,
  printScenarioResults,
  allocatePort,
  formatElta,
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
  name: 'economic-equilibrium-test',
  seed: 1002,
  ticks: 1000,
  tickSeconds: 86400,

  pack,

  agents: [
    {
      type: BasicUserAgent,
      count: 10,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.15,
      },
    },
    {
      type: WhaleUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.6,
        maxTradePercent: 0.25,
      },
    },
    {
      type: CautiousUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.3,
        maxTradePercent: 0.1,
        sellThreshold: 0.2,
        stopLossThreshold: 0.1,
      },
    },
    {
      type: DeveloperAgent,
      count: 5,
      params: {
        maxApps: 8,
        launchProbability: 0.25,
      },
    },
    {
      type: StakerAgent,
      count: 5,
      params: {
        lockProbability: 0.4,
        minLockAmount: 1500n * 10n ** 18n,
        preferredLockDays: 365,
      },
    },
    {
      type: AppStakerAgent,
      count: 4,
      params: {
        stakeProbability: 0.35,
        unstakeProbability: 0.15,
        claimProbability: 0.4,
        maxAppsToStake: 4,
      },
    },
    {
      type: RewardHunterAgent,
      count: 4,
      params: {
        claimProbability: 0.5,
        stakeFirst: true,
      },
    },
    {
      type: FeeKeeperAgent,
      count: 2,
      params: {
        sweepProbability: 0.6,
        closeEpochProbability: 0.3,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 20,
    track: [
      'app_count',
      'elta_total_supply',
      'veelta_total_locked',
      'fees_collected_total',
      'gas_total',
      'graduated_apps',
    ],
  },

  assertions: economicAssertions({ minApps: 15 }),
});

async function main(): Promise<void> {
  console.log('=== Long-Running Economic Validation: Equilibrium Test ===\n');
  console.log('Simulating 1000 days to test fee/reward equilibrium...');
  console.log('This will take several minutes.\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  const startTime = Date.now();

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', '..', 'results', 'economic-equilibrium'),
      ci: true,
    });

    const duration = Date.now() - startTime;

    console.log('\n' + '='.repeat(60));
    console.log('EQUILIBRIUM TEST REPORT');
    console.log('='.repeat(60));

    console.log('\nSimulation Details:');
    console.log('  Duration: ' + Math.round(duration / 60000) + ' minutes');
    console.log('  Simulated period: 1000 days');
    console.log('  Total agents: 40');

    const feesCollected = result.finalMetrics.fees_collected_total as bigint;
    const veEltaLocked = result.finalMetrics.veelta_total_locked as bigint;

    console.log('\nEconomic Equilibrium Metrics:');
    console.log('  Total fees collected: ' + formatElta(feesCollected));
    console.log('  Average daily fees: ' + formatElta(feesCollected / 1000n));
    console.log('  veELTA locked: ' + formatElta(veEltaLocked));

    const avgDailyFees = Number(feesCollected) / 1000;
    const totalLocked = Number(veEltaLocked);
    const impliedApr = totalLocked > 0 ? (avgDailyFees * 365 / totalLocked) * 100 : 0;

    console.log('\nReward Sustainability:');
    console.log('  Implied APR: ' + impliedApr.toFixed(2) + '%');

    const grouped = groupAgentStatsByType(result.agentStats);
    console.log('\nAgent Activity Balance:');
    const totalActions = result.agentStats.reduce((sum, s) => sum + s.actionsAttempted, 0);
    for (const [type, stats] of grouped) {
      const pct = (stats.totalAttempted / totalActions) * 100;
      console.log('  ' + type + ': ' + pct.toFixed(1) + '% of actions');
    }

    printScenarioResults(result, {
      highlightMetrics: ['fees_collected_total', 'veelta_total_locked', 'app_count'],
      showAgentStats: false,
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Equilibrium test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
