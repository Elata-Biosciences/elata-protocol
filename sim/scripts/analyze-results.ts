#!/usr/bin/env tsx
/**
 * analyze-results.ts - Aggregate and analyze simulation results
 *
 * Reads all result directories and produces summary statistics.
 * Includes price history, P&L analysis, gas usage, and statistical metrics.
 *
 * Usage:
 *   pnpm analyze              # Analyze all scenarios
 *   pnpm analyze healthy      # Analyze specific scenario
 *   pnpm analyze --detailed   # Include detailed metrics
 */

import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const resultsDir = join(__dirname, '..', 'results');

interface SummaryJson {
  runId: string;
  scenarioName: string;
  seed: number;
  ticks: number;
  durationMs: number;
  success: boolean;
  failedAssertions: Array<{ message: string }>;
  finalMetrics: Record<string, string | number | bigint>;
  agentStats: Array<{
    id: string;
    actionsAttempted: number;
    actionsSucceeded: number;
    actionsFailed: number;
  }>;
  timestamp: string;
}

interface ScenarioStats {
  name: string;
  runCount: number;
  successCount: number;
  failureCount: number;
  avgDurationMs: number;
  minDurationMs: number;
  maxDurationMs: number;
  avgAppCount: number;
  minAppCount: number;
  maxAppCount: number;
  avgTotalActions: number;
  runs: Array<{
    runId: string;
    success: boolean;
    durationMs: number;
    appCount: number;
    totalActions: number;
    timestamp: string;
  }>;
}

async function findResultDirs(scenarioFilter?: string): Promise<Map<string, string[]>> {
  const scenarioMap = new Map<string, string[]>();

  try {
    const scenarios = await readdir(resultsDir);

    for (const scenario of scenarios) {
      if (scenarioFilter && !scenario.includes(scenarioFilter)) {
        continue;
      }

      const scenarioDir = join(resultsDir, scenario);
      try {
        const runs = await readdir(scenarioDir);
        const runDirs = runs.filter((r) => r.startsWith(scenario));
        if (runDirs.length > 0) {
          scenarioMap.set(
            scenario,
            runDirs.map((r) => join(scenarioDir, r))
          );
        }
      } catch {
        // Not a directory or no access
      }
    }
  } catch {
    console.error('Could not read results directory');
  }

  return scenarioMap;
}

async function loadSummary(runDir: string): Promise<SummaryJson | null> {
  try {
    const summaryPath = join(runDir, 'summary.json');
    const content = await readFile(summaryPath, 'utf-8');
    return JSON.parse(content) as SummaryJson;
  } catch {
    return null;
  }
}

function analyzeScenario(name: string, summaries: SummaryJson[]): ScenarioStats {
  const stats: ScenarioStats = {
    name,
    runCount: summaries.length,
    successCount: summaries.filter((s) => s.success).length,
    failureCount: summaries.filter((s) => !s.success).length,
    avgDurationMs: 0,
    minDurationMs: Number.MAX_SAFE_INTEGER,
    maxDurationMs: 0,
    avgAppCount: 0,
    minAppCount: Number.MAX_SAFE_INTEGER,
    maxAppCount: 0,
    avgTotalActions: 0,
    runs: [],
  };

  let totalDuration = 0;
  let totalApps = 0;
  let totalActions = 0;

  for (const summary of summaries) {
    const appCount = Number(summary.finalMetrics.app_count ?? 0);
    const runActions = summary.agentStats.reduce((sum, a) => sum + a.actionsAttempted, 0);

    stats.runs.push({
      runId: summary.runId,
      success: summary.success,
      durationMs: summary.durationMs,
      appCount,
      totalActions: runActions,
      timestamp: summary.timestamp,
    });

    totalDuration += summary.durationMs;
    totalApps += appCount;
    totalActions += runActions;

    stats.minDurationMs = Math.min(stats.minDurationMs, summary.durationMs);
    stats.maxDurationMs = Math.max(stats.maxDurationMs, summary.durationMs);
    stats.minAppCount = Math.min(stats.minAppCount, appCount);
    stats.maxAppCount = Math.max(stats.maxAppCount, appCount);
  }

  if (summaries.length > 0) {
    stats.avgDurationMs = Math.round(totalDuration / summaries.length);
    stats.avgAppCount = Math.round(totalApps / summaries.length);
    stats.avgTotalActions = Math.round(totalActions / summaries.length);
  }

  // Reset min values if no runs
  if (stats.runCount === 0) {
    stats.minDurationMs = 0;
    stats.minAppCount = 0;
  }

  return stats;
}

function printStats(scenarioStats: ScenarioStats, showDetailed = false): void {
  const stats = scenarioStats;
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Scenario: ${stats.name}`);
  console.log(`${'='.repeat(60)}`);

  console.log(`\nRuns: ${stats.runCount}`);
  console.log(
    `  Success: ${stats.successCount} (${Math.round((stats.successCount / stats.runCount) * 100)}%)`
  );
  console.log(`  Failure: ${stats.failureCount}`);

  console.log(`\nDuration (ms):`);
  console.log(`  Avg: ${stats.avgDurationMs}`);
  console.log(`  Min: ${stats.minDurationMs}`);
  console.log(`  Max: ${stats.maxDurationMs}`);

  console.log(`\nApp Count:`);
  console.log(`  Avg: ${stats.avgAppCount}`);
  console.log(`  Min: ${stats.minAppCount}`);
  console.log(`  Max: ${stats.maxAppCount}`);

  console.log(`\nTotal Actions (avg): ${stats.avgTotalActions}`);

  if (stats.runs.length > 0) {
    console.log(`\nRecent Runs:`);
    const recentRuns = stats.runs
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
      .slice(0, 5);

    for (const run of recentRuns) {
      const status = run.success ? '✓' : '✗';
      console.log(
        `  ${status} ${run.runId}: ${run.durationMs}ms, ${run.appCount} apps, ${run.totalActions} actions`
      );
    }
  }

  // Detailed analysis if requested
  if (showDetailed && stats.runs.length > 0) {
    printDetailedAnalysis(stats);
  }
}

/**
 * Print detailed analysis including P&L, gas, and prices
 */
function printDetailedAnalysis(_stats: ScenarioStats): void {
  // This would need access to full metrics from summaries
  console.log(`\nDetailed Analysis:`);
  console.log(`  (Run with --detailed flag and ensure metrics are collected)`);
}

/**
 * Calculate statistical metrics from a series of numbers
 */
function calculateStatistics(values: number[]): {
  mean: number;
  stdDev: number;
  min: number;
  max: number;
  median: number;
  ci95Low: number;
  ci95High: number;
} {
  if (values.length === 0) {
    return { mean: 0, stdDev: 0, min: 0, max: 0, median: 0, ci95Low: 0, ci95High: 0 };
  }

  const sorted = [...values].sort((a, b) => a - b);
  const n = values.length;

  const mean = values.reduce((a, b) => a + b, 0) / n;
  const variance = values.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / n;
  const stdDev = Math.sqrt(variance);

  const median =
    n % 2 === 0 ? (sorted[n / 2 - 1]! + sorted[n / 2]!) / 2 : sorted[Math.floor(n / 2)]!;

  // 95% confidence interval using t-distribution approximation
  const tValue = 1.96; // For large samples
  const standardError = stdDev / Math.sqrt(n);
  const ci95Low = mean - tValue * standardError;
  const ci95High = mean + tValue * standardError;

  return {
    mean,
    stdDev,
    min: sorted[0]!,
    max: sorted[n - 1]!,
    median,
    ci95Low,
    ci95High,
  };
}

/**
 * Print price history analysis
 */
function analyzePriceHistory(summaries: SummaryJson[]): void {
  console.log(`\nPrice History Analysis:`);

  // Collect price metrics across all runs
  const priceChanges: Map<string, number[]> = new Map();

  for (const summary of summaries) {
    for (const [key, value] of Object.entries(summary.finalMetrics)) {
      if (key.includes('_price_change_bps')) {
        const appId = key.replace('app_', '').replace('_price_change_bps', '');
        const changes = priceChanges.get(appId) ?? [];
        changes.push(Number(value));
        priceChanges.set(appId, changes);
      }
    }
  }

  for (const [appId, changes] of priceChanges) {
    if (changes.length > 0) {
      const stats = calculateStatistics(changes);
      console.log(`  App ${appId}:`);
      console.log(`    Mean change: ${stats.mean.toFixed(2)} bps`);
      console.log(`    Std dev: ${stats.stdDev.toFixed(2)} bps`);
      console.log(`    Range: ${stats.min.toFixed(2)} to ${stats.max.toFixed(2)} bps`);
    }
  }
}

/**
 * Print agent P&L analysis
 */
function analyzeAgentPnL(summaries: SummaryJson[]): void {
  console.log(`\nAgent P&L Analysis:`);

  const pnlByAgent: Map<string, number[]> = new Map();

  for (const summary of summaries) {
    for (const [key, value] of Object.entries(summary.finalMetrics)) {
      if (key.includes('_realized_pnl')) {
        const agentId = key.replace('agent_', '').replace('_realized_pnl', '');
        const pnls = pnlByAgent.get(agentId) ?? [];
        pnls.push(Number(value));
        pnlByAgent.set(agentId, pnls);
      }
    }
  }

  // Group by agent type
  const pnlByType: Map<string, number[]> = new Map();
  for (const [agentId, pnls] of pnlByAgent) {
    const type = agentId.split('-')[0] ?? 'Unknown';
    const typePnls = pnlByType.get(type) ?? [];
    typePnls.push(...pnls);
    pnlByType.set(type, typePnls);
  }

  for (const [type, pnls] of pnlByType) {
    if (pnls.length > 0) {
      const stats = calculateStatistics(pnls);
      const meanFormatted = (stats.mean / 1e18).toFixed(4);
      console.log(`  ${type} agents:`);
      console.log(`    Mean P&L: ${meanFormatted} ELTA`);
      console.log(
        `    95% CI: [${(stats.ci95Low / 1e18).toFixed(4)}, ${(stats.ci95High / 1e18).toFixed(4)}]`
      );
    }
  }
}

/**
 * Print gas usage analysis
 */
function analyzeGasUsage(summaries: SummaryJson[]): void {
  console.log(`\nGas Usage Analysis:`);

  const gasByAction: Map<string, number[]> = new Map();
  const totalGas: number[] = [];

  for (const summary of summaries) {
    // Total gas
    if (summary.finalMetrics.gas_total !== undefined) {
      totalGas.push(Number(summary.finalMetrics.gas_total));
    }

    // Gas per action
    for (const [key, value] of Object.entries(summary.finalMetrics)) {
      if (key.startsWith('gas_per_action_')) {
        const actionType = key.replace('gas_per_action_', '');
        const gasValues = gasByAction.get(actionType) ?? [];
        gasValues.push(Number(value));
        gasByAction.set(actionType, gasValues);
      }
    }
  }

  if (totalGas.length > 0) {
    const stats = calculateStatistics(totalGas);
    console.log(`  Total Gas:`);
    console.log(`    Mean: ${stats.mean.toLocaleString()}`);
    console.log(`    Std Dev: ${stats.stdDev.toLocaleString()}`);
    console.log(`    Range: ${stats.min.toLocaleString()} - ${stats.max.toLocaleString()}`);
  }

  console.log(`\n  Gas by Action Type:`);
  for (const [actionType, gasValues] of gasByAction) {
    if (gasValues.length > 0) {
      const stats = calculateStatistics(gasValues);
      console.log(`    ${actionType}: ${stats.mean.toLocaleString()} avg`);
    }
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const detailed = args.includes('--detailed');
  const scenarioFilter = args.find((a) => !a.startsWith('--'));

  console.log('Analyzing simulation results...');
  if (scenarioFilter) {
    console.log(`Filtering for: ${scenarioFilter}`);
  }
  if (detailed) {
    console.log('Detailed analysis enabled');
  }

  const scenarioMap = await findResultDirs(scenarioFilter);

  if (scenarioMap.size === 0) {
    console.log('\nNo results found.');
    return;
  }

  const allStats: ScenarioStats[] = [];
  const allSummaries: SummaryJson[] = [];

  for (const [scenario, runDirs] of scenarioMap) {
    const summaries: SummaryJson[] = [];

    for (const runDir of runDirs) {
      const summary = await loadSummary(runDir);
      if (summary) {
        summaries.push(summary);
        allSummaries.push(summary);
      }
    }

    if (summaries.length > 0) {
      const stats = analyzeScenario(scenario, summaries);
      allStats.push(stats);
      printStats(stats, detailed);
    }
  }

  // Print overall summary
  if (allStats.length > 1) {
    console.log(`\n${'='.repeat(60)}`);
    console.log('OVERALL SUMMARY');
    console.log(`${'='.repeat(60)}`);

    const totalRuns = allStats.reduce((sum, s) => sum + s.runCount, 0);
    const totalSuccess = allStats.reduce((sum, s) => sum + s.successCount, 0);

    console.log(`\nTotal Runs: ${totalRuns}`);
    console.log(`Overall Success Rate: ${Math.round((totalSuccess / totalRuns) * 100)}%`);

    console.log('\nBy Scenario:');
    for (const stats of allStats) {
      const rate = Math.round((stats.successCount / stats.runCount) * 100);
      console.log(`  ${stats.name}: ${stats.runCount} runs, ${rate}% success`);
    }
  }

  // Detailed analysis across all runs
  if (detailed && allSummaries.length > 0) {
    console.log(`\n${'='.repeat(60)}`);
    console.log('DETAILED METRICS ANALYSIS');
    console.log(`${'='.repeat(60)}`);

    analyzePriceHistory(allSummaries);
    analyzeAgentPnL(allSummaries);
    analyzeGasUsage(allSummaries);
  }
}

void main();
