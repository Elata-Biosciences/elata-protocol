/**
 * Long-Running Economic Validation: Annual Simulation
 *
 * Simulates a full year of protocol operation (365 ticks = 365 days).
 * 50 mixed agents representing realistic user distribution.
 *
 * Focus: Full economic cycle, seasonal patterns, long-term sustainability
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  AppStakerAgent,
  BasicUserAgent,
  CautiousUserAgent,
  DeveloperAgent,
  FeeKeeperAgent,
  GovernorAgent,
  RewardHunterAgent,
  StakerAgent,
  VoterAgent,
  WhaleUserAgent,
} from '../../../agents/index.js';
import {
  allocatePort,
  createNotebookReport,
  economicAssertions,
  formatElta,
  groupAgentStatsByType,
  printScenarioResults,
  projectAnnualRevenue,
} from '../../../lib/index.js';
import { createEltaPack } from '../../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: allocatePort(),
  silent: true,
});

const scenario = defineScenario({
  name: 'economic-annual-simulation',
  seed: 1000,
  ticks: 365, // 1 year
  tickSeconds: 86400, // 1 day per tick

  pack,

  agents: [
    // Regular users (30%)
    {
      type: BasicUserAgent,
      count: 15,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.15,
      },
    },
    // Whales (10%)
    {
      type: WhaleUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.7,
        maxTradePercent: 0.25,
      },
    },
    // Cautious users (10%)
    {
      type: CautiousUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.2,
        maxTradePercent: 0.05,
        sellThreshold: 0.15,
        stopLossThreshold: 0.1,
      },
    },
    // Developers (10%)
    {
      type: DeveloperAgent,
      count: 5,
      params: {
        maxApps: 10,
        launchProbability: 0.3,
      },
    },
    // Stakers (10%)
    {
      type: StakerAgent,
      count: 5,
      params: {
        lockProbability: 0.5,
        minLockAmount: 1000n * 10n ** 18n,
        preferredLockDays: 180,
      },
    },
    // App stakers (10%)
    {
      type: AppStakerAgent,
      count: 5,
      params: {
        stakeProbability: 0.4,
        claimProbability: 0.3,
        maxAppsToStake: 3,
      },
    },
    // Reward hunters (8%)
    {
      type: RewardHunterAgent,
      count: 4,
      params: {
        claimProbability: 0.6,
        stakeFirst: true,
      },
    },
    // Fee keepers (4%)
    {
      type: FeeKeeperAgent,
      count: 2,
      params: {
        sweepProbability: 0.7,
        closeEpochProbability: 0.3,
      },
    },
    // Governors (4%)
    {
      type: GovernorAgent,
      count: 2,
      params: {
        proposeProbability: 0.2,
        minVeEltaForProposal: 5000n * 10n ** 18n,
      },
    },
    // Voters (4%)
    {
      type: VoterAgent,
      count: 2,
      params: {
        voteProbability: 0.7,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 7, // Weekly snapshots
    track: [
      'app_count',
      'elta_total_supply',
      'veelta_total_locked',
      'fees_collected_total',
      'gas_total',
      'graduated_apps',
    ],
  },

  assertions: economicAssertions({ minApps: 10 }),
  studio: {
    report: createNotebookReport({
      title: 'Economic Long-Run: Annual Simulation',
      experimentNotes:
        '365-day mixed-population simulation to test full-cycle sustainability, revenue consistency, and long-horizon protocol behavior.',
      hypotheses: [
        'A diversified agent mix should keep fees and participation structurally positive.',
        'Long-horizon app growth and veELTA lock depth remain stable under mixed behavior.',
      ],
      successCriteria: [
        'Annual economic assertions pass.',
        'Fees, app count, and veELTA lock remain healthy by end of run.',
      ],
      metricFields: [
        'app_count',
        'fees_collected_total',
        'veelta_total_locked',
        'graduated_apps',
        'gas_total',
      ],
      primaryMetric: 'fees_collected_total',
      mlFeatures: ['tick', 'app_count', 'veelta_total_locked'],
    }),
  },
});

async function main(): Promise<void> {
  console.log('=== Long-Running Economic Validation: Annual Simulation ===\n');
  console.log('Simulating 365 days of protocol operation...');
  console.log('This may take several minutes.\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  const startTime = Date.now();

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', '..', 'results', 'economic-annual'),
      ci: true,
    });

    const duration = Date.now() - startTime;

    // Economic analysis
    console.log('\n' + '='.repeat(60));
    console.log('ANNUAL ECONOMIC REPORT');
    console.log('='.repeat(60));

    console.log('\nSimulation Details:');
    console.log('  Duration: ' + Math.round(duration / 60000) + ' minutes');
    console.log('  Simulated period: 365 days (1 year)');
    console.log('  Total agents: 50');

    const feesCollected = result.finalMetrics.fees_collected_total as bigint;
    const annualProjection = projectAnnualRevenue(feesCollected, 365, 86400);

    console.log('\nRevenue Analysis:');
    console.log('  Total fees collected: ' + formatElta(feesCollected));
    console.log('  Annual projection: ' + formatElta(annualProjection));
    console.log('  Daily average: ' + formatElta(feesCollected / 365n));

    console.log('\nProtocol State:');
    console.log('  Apps created: ' + result.finalMetrics.app_count);
    console.log('  Graduated apps: ' + (result.finalMetrics.graduated_apps ?? 0));
    console.log(
      '  veELTA locked: ' + formatElta(result.finalMetrics.veelta_total_locked as bigint)
    );

    // Agent performance
    const grouped = groupAgentStatsByType(result.agentStats);
    console.log('\nAgent Performance Summary:');
    for (const [type, stats] of grouped) {
      console.log('  ' + type + ': ' + Math.round(stats.avgSuccessRate * 100) + '% success');
    }

    printScenarioResults(result, {
      highlightMetrics: ['fees_collected_total', 'app_count', 'veelta_total_locked'],
      showAgentStats: false,
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Annual simulation failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
