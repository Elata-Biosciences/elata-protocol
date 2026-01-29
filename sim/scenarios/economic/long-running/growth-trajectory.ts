/**
 * Long-Running Economic Validation: Growth Trajectory
 *
 * Simulates protocol growth over 500 ticks.
 * 30 mixed agents with focus on user acquisition patterns.
 *
 * Focus: User growth curves, network effects, adoption metrics
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  WhaleUserAgent,
  DeveloperAgent,
  SerialDeveloperAgent,
  StakerAgent,
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
  name: 'economic-growth-trajectory',
  seed: 1001,
  ticks: 500,
  tickSeconds: 86400, // 1 day per tick

  pack,

  agents: [
    // Growing user base - regular users
    {
      type: BasicUserAgent,
      count: 12,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
    // Early adopter whales
    {
      type: WhaleUserAgent,
      count: 4,
      params: {
        riskTolerance: 0.6,
        maxTradePercent: 0.3,
      },
    },
    // Active developers
    {
      type: DeveloperAgent,
      count: 4,
      params: {
        maxApps: 5,
        launchProbability: 0.4,
      },
    },
    // Serial developers (high volume)
    {
      type: SerialDeveloperAgent,
      count: 2,
      params: {
        maxApps: 15,
        launchProbability: 0.5,
        minLaunchInterval: 5,
      },
    },
    // Long-term stakers
    {
      type: StakerAgent,
      count: 4,
      params: {
        lockProbability: 0.6,
        minLockAmount: 2000n * 10n ** 18n,
        preferredLockDays: 365,
      },
    },
    // Yield farmers
    {
      type: RewardHunterAgent,
      count: 2,
      params: {
        claimProbability: 0.7,
        stakeFirst: true,
      },
    },
    // Protocol keepers
    {
      type: FeeKeeperAgent,
      count: 2,
      params: {
        sweepProbability: 0.8,
        closeEpochProbability: 0.4,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 10, // Sample every 10 days
    track: [
      'app_count',
      'elta_total_supply',
      'veelta_total_locked',
      'fees_collected_total',
      'gas_total',
      'graduated_apps',
    ],
  },

  assertions: economicAssertions({ minApps: 20 }),
});

async function main(): Promise<void> {
  console.log('=== Long-Running Economic Validation: Growth Trajectory ===\n');
  console.log('Simulating 500 days of protocol growth...');
  console.log('This may take several minutes.\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  const startTime = Date.now();

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', '..', 'results', 'economic-growth'),
      ci: true,
    });

    const duration = Date.now() - startTime;

    // Growth analysis
    console.log('\n' + '='.repeat(60));
    console.log('GROWTH TRAJECTORY REPORT');
    console.log('='.repeat(60));

    console.log('\nSimulation Details:');
    console.log('  Duration: ' + Math.round(duration / 60000) + ' minutes');
    console.log('  Simulated period: 500 days');
    console.log('  Total agents: 30');

    const appCount = result.finalMetrics.app_count as number;
    const feesCollected = result.finalMetrics.fees_collected_total as bigint;

    console.log('\nGrowth Metrics:');
    console.log('  Apps created: ' + appCount);
    console.log('  Apps per day: ' + (appCount / 500).toFixed(2));
    console.log('  Graduated apps: ' + (result.finalMetrics.graduated_apps ?? 0));

    console.log('\nRevenue Growth:');
    console.log('  Total fees: ' + formatElta(feesCollected));
    console.log('  Fees per day: ' + formatElta(feesCollected / 500n));
    console.log('  veELTA locked: ' + formatElta(result.finalMetrics.veelta_total_locked as bigint));

    // Developer productivity
    const grouped = groupAgentStatsByType(result.agentStats);
    const devStats = grouped.get('DeveloperAgent');
    const serialStats = grouped.get('SerialDeveloperAgent');

    console.log('\nDeveloper Activity:');
    if (devStats) {
      console.log('  Regular devs: ' + devStats.totalSucceeded + ' successful actions');
    }
    if (serialStats) {
      console.log('  Serial devs: ' + serialStats.totalSucceeded + ' successful actions');
    }

    printScenarioResults(result, {
      highlightMetrics: ['app_count', 'fees_collected_total', 'graduated_apps'],
      showAgentStats: true,
      groupByType: true,
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Growth trajectory simulation failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
