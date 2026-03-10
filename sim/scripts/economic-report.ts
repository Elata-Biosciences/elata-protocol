/**
 * Economic Report Generator
 *
 * Generates comprehensive economic reports from simulation results.
 * Aggregates data from multiple runs for statistical significance.
 */

import { readdir, readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  calculateStatistics,
  formatElta,
  formatDuration,
  projectAnnualRevenue,
  type Statistics,
} from '../lib/scenario-helpers.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Format USDC value (6 decimals) to human-readable string
 */
function formatUsdc(value: bigint): string {
  const DECIMALS = 6n;
  const integer = value / 10n ** DECIMALS;
  const decimal = (value % 10n ** DECIMALS).toString().padStart(6, '0').slice(0, 2);
  return `$${integer.toLocaleString()}.${decimal}`;
}

/**
 * Project annual USDC revenue from simulation data
 */
function projectAnnualUsdc(avgUsdcPerRun: bigint, ticksPerRun: number, tickSeconds: number): bigint {
  if (ticksPerRun === 0 || tickSeconds === 0) return 0n;
  const simulatedSeconds = ticksPerRun * tickSeconds;
  const secondsPerYear = 365n * 24n * 60n * 60n;
  return (avgUsdcPerRun * secondsPerYear) / BigInt(simulatedSeconds);
}

// ============================================
// Types
// ============================================

interface SimulationResult {
  scenario: string;
  runId?: string;
  seed: number;
  ticks: number;
  tickSeconds: number;
  durationMs: number;
  success: boolean;
  finalMetrics: Record<string, number | string | bigint>;
  agentStats: Array<{
    id: string;
    actionsAttempted: number;
    actionsSucceeded: number;
    actionsFailed: number;
  }>;
}

interface EconomicReport {
  meta: {
    generatedAt: string;
    resultsDir: string;
    scenarioCount: number;
    runCount: number;
  };

  summary: {
    totalSimulatedDays: number;
    totalRealTimeMs: number;
    successRate: number;
    totalAgents: number;
    totalActions: number;
    successfulActions: number;
  };

  revenue: {
    totalFeesCollected: string;
    averageFeesPerRun: string;
    feesStdDev: string;
    feesCI95: { low: string; high: string };
    projectedAnnualRevenue: string;
    revenuePerUser: string;
    revenuePerTransaction: string;
    revenuePerSimulatedDay: string;
  };

  usdcRevenue: {
    totalUsdcRevenue: string;
    averageUsdcPerRun: string;
    projectedAnnualUsdc: string;
    conversionEfficiency: string; // Percentage of ELTA fees converted to USDC
  };

  protocol: {
    averageAppCount: number;
    averageGraduatedApps: number;
    averageVeEltaLocked: string;
    averageGasUsed: string;
  };

  agents: {
    byType: Record<string, {
      count: number;
      avgSuccessRate: number;
      totalActions: number;
      successfulActions: number;
    }>;
    topPerformers: Array<{ type: string; successRate: number }>;
    worstPerformers: Array<{ type: string; successRate: number }>;
  };

  statistics: {
    duration: Statistics;
    fees: Statistics;
    appCount: Statistics;
    veEltaLocked: Statistics;
  };

  confidence: {
    sampleSize: number;
    confidenceLevel: number;
    marginOfError: string;
  };
}

// ============================================
// Data Loading
// ============================================

async function loadResults(resultsDir: string): Promise<SimulationResult[]> {
  const results: SimulationResult[] = [];

  try {
    const scenarioDirs = await readdir(resultsDir, { withFileTypes: true });

    for (const scenarioDir of scenarioDirs) {
      if (!scenarioDir.isDirectory()) continue;

      const scenarioPath = join(resultsDir, scenarioDir.name);
      const runDirs = await readdir(scenarioPath, { withFileTypes: true });

      for (const runDir of runDirs) {
        if (!runDir.isDirectory()) continue;

        const summaryPath = join(scenarioPath, runDir.name, 'summary.json');
        try {
          const content = await readFile(summaryPath, 'utf-8');
          const data = JSON.parse(content);
          results.push({
            scenario: scenarioDir.name,
            runId: runDir.name,
            ...data,
          });
        } catch {
          // Skip directories without summary.json
        }
      }
    }
  } catch (error) {
    console.error('Error reading results directory:', error);
  }

  return results;
}

// ============================================
// Report Generation
// ============================================

function generateReport(results: SimulationResult[]): EconomicReport {
  const now = new Date().toISOString();

  // Filter successful runs for economic metrics
  const successfulRuns = results.filter((r) => r.success);

  // Calculate totals
  const totalSimulatedDays = results.reduce((sum, r) => {
    return sum + (r.ticks * r.tickSeconds) / 86400;
  }, 0);

  const totalRealTimeMs = results.reduce((sum, r) => sum + r.durationMs, 0);

  // Agent stats
  const allAgentStats = results.flatMap((r) => r.agentStats);
  const totalActions = allAgentStats.reduce((sum, s) => sum + s.actionsAttempted, 0);
  const successfulActions = allAgentStats.reduce((sum, s) => sum + s.actionsSucceeded, 0);

  // Fee extraction (handle BigInt)
  const feeValues = successfulRuns.map((r) => {
    const fees = r.finalMetrics.fees_collected_total;
    if (typeof fees === 'bigint') return Number(fees);
    if (typeof fees === 'string') return parseFloat(fees);
    if (typeof fees === 'number') return fees;
    return 0;
  });

  const feeStats = calculateStatistics(feeValues);
  const totalFees = feeValues.reduce((a, b) => a + b, 0);

  // USDC Revenue stats
  const usdcValues = successfulRuns.map((r) => {
    const usdc = r.finalMetrics.treasury_usdc_revenue;
    if (typeof usdc === 'bigint') return Number(usdc);
    if (typeof usdc === 'string') return parseFloat(usdc);
    if (typeof usdc === 'number') return usdc;
    return 0;
  });
  const totalUsdcRevenue = usdcValues.reduce((a, b) => a + b, 0);
  const avgUsdcPerRun = usdcValues.length > 0 ? totalUsdcRevenue / usdcValues.length : 0;

  // App count stats
  const appCounts = successfulRuns.map((r) => {
    const count = r.finalMetrics.app_count;
    return typeof count === 'number' ? count : parseInt(String(count), 10) || 0;
  });
  const appStats = calculateStatistics(appCounts);

  // veELTA locked stats
  const veEltaValues = successfulRuns.map((r) => {
    const locked = r.finalMetrics.veelta_total_locked;
    if (typeof locked === 'bigint') return Number(locked);
    if (typeof locked === 'string') return parseFloat(locked);
    if (typeof locked === 'number') return locked;
    return 0;
  });
  const veEltaStats = calculateStatistics(veEltaValues);

  // Duration stats
  const durations = results.map((r) => r.durationMs);
  const durationStats = calculateStatistics(durations);

  // Agent performance by type
  const agentsByType: Record<string, {
    count: number;
    avgSuccessRate: number;
    totalActions: number;
    successfulActions: number;
  }> = {};

  for (const stat of allAgentStats) {
    const parts = stat.id.split('-');
    const type = parts.slice(0, -1).join('-') || stat.id;

    if (!agentsByType[type]) {
      agentsByType[type] = {
        count: 0,
        avgSuccessRate: 0,
        totalActions: 0,
        successfulActions: 0,
      };
    }

    agentsByType[type].count++;
    agentsByType[type].totalActions += stat.actionsAttempted;
    agentsByType[type].successfulActions += stat.actionsSucceeded;
  }

  // Calculate average success rates
  for (const type of Object.keys(agentsByType)) {
    const data = agentsByType[type]!;
    data.avgSuccessRate = data.totalActions > 0
      ? data.successfulActions / data.totalActions
      : 1;
  }

  // Top and worst performers
  const sortedTypes = Object.entries(agentsByType)
    .sort(([, a], [, b]) => b.avgSuccessRate - a.avgSuccessRate);

  const topPerformers = sortedTypes.slice(0, 5).map(([type, data]) => ({
    type,
    successRate: data.avgSuccessRate,
  }));

  const worstPerformers = sortedTypes.slice(-5).reverse().map(([type, data]) => ({
    type,
    successRate: data.avgSuccessRate,
  }));

  // Graduated apps
  const graduatedApps = successfulRuns.map((r) => {
    const grad = r.finalMetrics.graduated_apps;
    return typeof grad === 'number' ? grad : parseInt(String(grad), 10) || 0;
  });

  // Gas usage
  const gasValues = successfulRuns.map((r) => {
    const gas = r.finalMetrics.gas_total;
    if (typeof gas === 'bigint') return Number(gas);
    if (typeof gas === 'string') return parseFloat(gas);
    if (typeof gas === 'number') return gas;
    return 0;
  });

  // Calculate projections
  const avgTicksPerRun = results.length > 0
    ? results.reduce((sum, r) => sum + (r.ticks || 0), 0) / results.length
    : 0;
  const avgTickSeconds = results.length > 0
    ? results.reduce((sum, r) => sum + (r.tickSeconds || 86400), 0) / results.length
    : 86400;
  const avgFees = successfulRuns.length > 0 ? totalFees / successfulRuns.length : 0;
  const annualProjection = avgFees > 0 && avgTicksPerRun > 0 && avgTickSeconds > 0
    ? projectAnnualRevenue(
        BigInt(Math.floor(avgFees)),
        Math.floor(avgTicksPerRun),
        Math.floor(avgTickSeconds)
      )
    : 0n;

  // Average agents per run
  const avgAgentsPerRun = allAgentStats.length / results.length;

  // Margin of error calculation (95% CI)
  const marginOfError = feeStats.stdDev > 0
    ? (1.96 * feeStats.stdDev / Math.sqrt(successfulRuns.length)) / feeStats.mean * 100
    : 0;

  return {
    meta: {
      generatedAt: now,
      resultsDir: 'sim/results',
      scenarioCount: new Set(results.map((r) => r.scenario)).size,
      runCount: results.length,
    },

    summary: {
      totalSimulatedDays,
      totalRealTimeMs,
      successRate: successfulRuns.length / results.length,
      totalAgents: allAgentStats.length,
      totalActions,
      successfulActions,
    },

    revenue: {
      totalFeesCollected: formatElta(BigInt(Math.floor(totalFees))),
      averageFeesPerRun: formatElta(BigInt(Math.floor(avgFees))),
      feesStdDev: formatElta(BigInt(Math.floor(feeStats.stdDev))),
      feesCI95: {
        low: formatElta(BigInt(Math.floor(feeStats.ci95Low))),
        high: formatElta(BigInt(Math.floor(feeStats.ci95High))),
      },
      projectedAnnualRevenue: formatElta(annualProjection),
      revenuePerUser: formatElta(BigInt(Math.floor(totalFees / avgAgentsPerRun))),
      revenuePerTransaction: formatElta(BigInt(Math.floor(totalFees / (successfulActions || 1)))),
      revenuePerSimulatedDay: formatElta(BigInt(Math.floor(totalFees / (totalSimulatedDays || 1)))),
    },

    usdcRevenue: {
      totalUsdcRevenue: formatUsdc(BigInt(Math.floor(totalUsdcRevenue))),
      averageUsdcPerRun: formatUsdc(BigInt(Math.floor(avgUsdcPerRun))),
      projectedAnnualUsdc: totalUsdcRevenue > 0 && avgTicksPerRun > 0 && avgTickSeconds > 0
        ? formatUsdc(projectAnnualUsdc(BigInt(Math.floor(avgUsdcPerRun)), Math.floor(avgTicksPerRun), Math.floor(avgTickSeconds)))
        : '$0.00',
      conversionEfficiency: totalFees > 0
        ? ((totalUsdcRevenue / totalFees) * 100).toFixed(2) + '%'
        : 'N/A',
    },

    protocol: {
      averageAppCount: appStats.mean,
      averageGraduatedApps: graduatedApps.reduce((a, b) => a + b, 0) / (graduatedApps.length || 1),
      averageVeEltaLocked: formatElta(BigInt(Math.floor(veEltaStats.mean))),
      averageGasUsed: gasValues.length > 0
        ? (gasValues.reduce((a, b) => a + b, 0) / gasValues.length).toExponential(2)
        : '0',
    },

    agents: {
      byType: agentsByType,
      topPerformers,
      worstPerformers,
    },

    statistics: {
      duration: durationStats,
      fees: feeStats,
      appCount: appStats,
      veEltaLocked: veEltaStats,
    },

    confidence: {
      sampleSize: successfulRuns.length,
      confidenceLevel: 0.95,
      marginOfError: marginOfError.toFixed(2) + '%',
    },
  };
}

// ============================================
// Output Formatting
// ============================================

function printReport(report: EconomicReport): void {
  console.log('\n');
  console.log('='.repeat(70));
  console.log('                    ECONOMIC VALIDATION REPORT                        ');
  console.log('='.repeat(70));
  console.log();

  console.log('Generated: ' + report.meta.generatedAt);
  console.log('Scenarios: ' + report.meta.scenarioCount);
  console.log('Total runs: ' + report.meta.runCount);
  console.log();

  console.log('-'.repeat(70));
  console.log('SIMULATION SUMMARY');
  console.log('-'.repeat(70));
  console.log('  Total simulated days: ' + report.summary.totalSimulatedDays.toFixed(0));
  console.log('  Real time: ' + formatDuration(report.summary.totalRealTimeMs));
  console.log('  Success rate: ' + (report.summary.successRate * 100).toFixed(1) + '%');
  console.log('  Total agents: ' + report.summary.totalAgents);
  console.log('  Total actions: ' + report.summary.totalActions.toLocaleString());
  console.log('  Successful actions: ' + report.summary.successfulActions.toLocaleString());
  console.log();

  console.log('-'.repeat(70));
  console.log('REVENUE ANALYSIS (ELTA Fees)');
  console.log('-'.repeat(70));
  console.log('  Total fees collected: ' + report.revenue.totalFeesCollected);
  console.log('  Average fees per run: ' + report.revenue.averageFeesPerRun);
  console.log('  Standard deviation: ' + report.revenue.feesStdDev);
  console.log('  95% CI: [' + report.revenue.feesCI95.low + ', ' + report.revenue.feesCI95.high + ']');
  console.log();
  console.log('  PROJECTIONS:');
  console.log('  Projected annual revenue: ' + report.revenue.projectedAnnualRevenue);
  console.log('  Revenue per user: ' + report.revenue.revenuePerUser);
  console.log('  Revenue per transaction: ' + report.revenue.revenuePerTransaction);
  console.log('  Revenue per simulated day: ' + report.revenue.revenuePerSimulatedDay);
  console.log();

  console.log('-'.repeat(70));
  console.log('USDC TREASURY REVENUE');
  console.log('-'.repeat(70));
  console.log('  Total USDC revenue: ' + report.usdcRevenue.totalUsdcRevenue);
  console.log('  Average USDC per run: ' + report.usdcRevenue.averageUsdcPerRun);
  console.log('  Projected annual USDC: ' + report.usdcRevenue.projectedAnnualUsdc);
  console.log('  Conversion efficiency: ' + report.usdcRevenue.conversionEfficiency);
  console.log();

  console.log('-'.repeat(70));
  console.log('PROTOCOL STATE');
  console.log('-'.repeat(70));
  console.log('  Average apps created: ' + report.protocol.averageAppCount.toFixed(1));
  console.log('  Average graduated apps: ' + report.protocol.averageGraduatedApps.toFixed(1));
  console.log('  Average veELTA locked: ' + report.protocol.averageVeEltaLocked);
  console.log('  Average gas used: ' + report.protocol.averageGasUsed);
  console.log();

  console.log('-'.repeat(70));
  console.log('AGENT PERFORMANCE');
  console.log('-'.repeat(70));
  console.log('  Top performers:');
  for (const perf of report.agents.topPerformers) {
    console.log('    - ' + perf.type + ': ' + (perf.successRate * 100).toFixed(1) + '%');
  }
  console.log();
  console.log('  Lowest performers:');
  for (const perf of report.agents.worstPerformers) {
    console.log('    - ' + perf.type + ': ' + (perf.successRate * 100).toFixed(1) + '%');
  }
  console.log();

  console.log('-'.repeat(70));
  console.log('STATISTICAL CONFIDENCE');
  console.log('-'.repeat(70));
  console.log('  Sample size: ' + report.confidence.sampleSize);
  console.log('  Confidence level: ' + (report.confidence.confidenceLevel * 100) + '%');
  console.log('  Margin of error: +/- ' + report.confidence.marginOfError);
  console.log();
  console.log('='.repeat(70));
  console.log();
}

// ============================================
// Main
// ============================================

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const resultsDir = args[0] ?? join(__dirname, '..', 'results');
  const outputPath = args[1] ?? join(resultsDir, 'economic-report.json');

  console.log('Economic Report Generator');
  console.log('Loading results from: ' + resultsDir);

  const results = await loadResults(resultsDir);

  if (results.length === 0) {
    console.log('No simulation results found.');
    process.exit(1);
  }

  console.log('Found ' + results.length + ' simulation runs');

  const report = generateReport(results);
  printReport(report);

  // Save JSON report
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, JSON.stringify(report, null, 2));
  console.log('Report saved to: ' + outputPath);
}

void main();

export { generateReport, type EconomicReport };
