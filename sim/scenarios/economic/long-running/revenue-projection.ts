/**
 * Long-Running Economic Validation: Revenue Projection
 *
 * Simulates 200 ticks with 100 users for revenue at scale.
 * High-volume scenario to project realistic revenue numbers.
 *
 * Focus: Revenue projections, fee generation at scale, economic viability
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
  FeeKeeperAgent,
} from '../../../agents/index.js';
import { createEltaPack } from '../../../packs/EltaPack.js';
import {
  economicAssertions,
  printScenarioResults,
  allocatePort,
  formatElta,
  projectAnnualRevenue,
  calculateRevenuePerUser,
  calculateRevenuePerTransaction,
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
  name: 'economic-revenue-projection',
  seed: 1003,
  ticks: 200,
  tickSeconds: 86400, // 1 day per tick

  pack,

  agents: [
    // Large user base - regular traders
    {
      type: BasicUserAgent,
      count: 60,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.15,
      },
    },
    // Whales for volume
    {
      type: WhaleUserAgent,
      count: 15,
      params: {
        riskTolerance: 0.7,
        maxTradePercent: 0.3,
      },
    },
    // Conservative users
    {
      type: CautiousUserAgent,
      count: 10,
      params: {
        riskTolerance: 0.2,
        maxTradePercent: 0.05,
        sellThreshold: 0.1,
        stopLossThreshold: 0.05,
      },
    },
    // App creators
    {
      type: DeveloperAgent,
      count: 8,
      params: {
        maxApps: 6,
        launchProbability: 0.5,
      },
    },
    // Stakers for veELTA
    {
      type: StakerAgent,
      count: 5,
      params: {
        lockProbability: 0.6,
        minLockAmount: 2000n * 10n ** 18n,
        preferredLockDays: 180,
      },
    },
    // Fee management
    {
      type: FeeKeeperAgent,
      count: 2,
      params: {
        sweepProbability: 0.9,
        closeEpochProbability: 0.5,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 5, // Frequent sampling
    track: [
      'app_count',
      'elta_total_supply',
      'veelta_total_locked',
      'fees_collected_total',
      'gas_total',
      'graduated_apps',
    ],
  },

  assertions: economicAssertions({ minApps: 25 }),
});

async function main(): Promise<void> {
  console.log('=== Long-Running Economic Validation: Revenue Projection ===\n');
  console.log('Simulating 200 days with 100 users for revenue at scale...');
  console.log('This may take several minutes.\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  const startTime = Date.now();

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', '..', 'results', 'economic-revenue'),
      ci: true,
    });

    const duration = Date.now() - startTime;

    // Revenue analysis
    console.log('\n' + '='.repeat(60));
    console.log('REVENUE PROJECTION REPORT');
    console.log('='.repeat(60));

    console.log('\nSimulation Details:');
    console.log('  Duration: ' + Math.round(duration / 60000) + ' minutes');
    console.log('  Simulated period: 200 days');
    console.log('  Total users: 100');

    const feesCollected = result.finalMetrics.fees_collected_total as bigint;
    const totalActions = result.agentStats.reduce((sum, s) => sum + s.actionsSucceeded, 0);

    // Revenue calculations
    const annualProjection = projectAnnualRevenue(feesCollected, 200, 86400);
    const revenuePerUser = calculateRevenuePerUser(feesCollected, 100);
    const revenuePerTx = calculateRevenuePerTransaction(feesCollected, totalActions);

    console.log('\nRevenue Summary:');
    console.log('  Total fees collected: ' + formatElta(feesCollected));
    console.log('  Annual projection: ' + formatElta(annualProjection));
    console.log('  Revenue per user: ' + formatElta(revenuePerUser));
    console.log('  Revenue per transaction: ' + formatElta(revenuePerTx));

    console.log('\nScaling Analysis:');
    const dailyFees = feesCollected / 200n;
    console.log('  Daily fees: ' + formatElta(dailyFees));
    console.log('  Monthly projection: ' + formatElta(dailyFees * 30n));
    console.log('  Quarterly projection: ' + formatElta(dailyFees * 90n));

    // Volume metrics
    const grouped = groupAgentStatsByType(result.agentStats);
    const whaleStats = grouped.get('WhaleUserAgent');
    const basicStats = grouped.get('BasicUserAgent');

    console.log('\nVolume Breakdown:');
    if (whaleStats) {
      console.log('  Whale transactions: ' + whaleStats.totalSucceeded);
    }
    if (basicStats) {
      console.log('  Regular user transactions: ' + basicStats.totalSucceeded);
    }
    console.log('  Total successful transactions: ' + totalActions);

    // User economics
    console.log('\nUser Economics:');
    console.log('  Average actions per user: ' + (totalActions / 100).toFixed(1));
    console.log('  Average daily actions: ' + (totalActions / 200).toFixed(1));

    // Final protocol state
    console.log('\nProtocol State:');
    console.log('  Apps created: ' + result.finalMetrics.app_count);
    console.log('  Graduated apps: ' + (result.finalMetrics.graduated_apps ?? 0));
    console.log('  veELTA locked: ' + formatElta(result.finalMetrics.veelta_total_locked as bigint));

    printScenarioResults(result, {
      highlightMetrics: ['fees_collected_total', 'app_count', 'veelta_total_locked'],
      showAgentStats: true,
      groupByType: true,
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Revenue projection failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
