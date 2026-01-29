/**
 * Scenario Helpers Library
 *
 * Common utilities for creating and running simulation scenarios.
 * Reduces boilerplate and ensures consistency across all tests.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Assertion, RunResult } from '@elata-biosciences/agentforge';
import { createEltaPack, type EltaPack, type EltaPackConfig } from '../packs/EltaPack.js';

// ============================================
// Port Management
// ============================================

// Track allocated ports to avoid conflicts
const allocatedPorts = new Set<number>();
let nextPort = 8500;

/**
 * Get a unique port for Anvil instance
 */
export function allocatePort(): number {
  while (allocatedPorts.has(nextPort)) {
    nextPort++;
  }
  const port = nextPort;
  allocatedPorts.add(port);
  nextPort++;
  return port;
}

/**
 * Release a port when done
 */
export function releasePort(port: number): void {
  allocatedPorts.delete(port);
}

/**
 * Reset port allocation (useful between test runs)
 */
export function resetPorts(): void {
  allocatedPorts.clear();
  nextPort = 8500;
}

// ============================================
// Pack Factory
// ============================================

/**
 * Options for creating a test pack
 */
export interface CreateTestPackOptions {
  /** Base path to protocol (defaults to sim parent directory) */
  protocolPath?: string;
  /** Whether to suppress Anvil output */
  silent?: boolean;
  /** Explicit port (auto-allocates if not provided) */
  port?: number;
  /** Additional EltaPack config */
  config?: Partial<EltaPackConfig>;
}

/**
 * Create an EltaPack for testing with automatic port management
 */
export function createTestPack(options: CreateTestPackOptions = {}): EltaPack {
  const __dirname = dirname(fileURLToPath(import.meta.url));
  const protocolPath = options.protocolPath ?? join(__dirname, '..', '..');

  return createEltaPack({
    protocolPath,
    anvilPort: options.port ?? allocatePort(),
    silent: options.silent ?? true,
    ...options.config,
  });
}

// ============================================
// Common Metric Sets
// ============================================

/** Core protocol stability metrics */
export const CORE_METRICS = ['app_count', 'elta_total_supply', 'veelta_total_locked'] as const;

/** Fee-related metrics */
export const FEE_METRICS = ['fees_collected_total', 'fees_distributed', 'gas_total'] as const;

/** Governance metrics */
export const GOVERNANCE_METRICS = ['veelta_total_locked', 'active_proposals'] as const;

/** Comprehensive economic metrics */
export const ECONOMIC_METRICS = [
  'app_count',
  'elta_total_supply',
  'veelta_total_locked',
  'fees_collected_total',
  'fees_distributed',
  'gas_total',
  'graduated_apps',
  'total_trade_volume',
] as const;

/** All available metrics */
export const ALL_METRICS = [
  ...ECONOMIC_METRICS,
  'block_number',
  'timestamp',
] as const;

// ============================================
// Assertion Builders
// ============================================

/**
 * Basic stability assertions - protocol should not break
 */
export function basicStabilityAssertions(): Assertion[] {
  return [
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ];
}

/**
 * Fee collection assertions
 */
export function feeAssertions(minFees = 0n): Assertion[] {
  return [
    ...basicStabilityAssertions(),
    {
      type: 'gte',
      metric: 'fees_collected_total',
      value: Number(minFees),
    },
  ];
}

/**
 * veELTA locking assertions
 */
export function veEltaAssertions(minLocked = 0n): Assertion[] {
  return [
    ...basicStabilityAssertions(),
    {
      type: 'gte',
      metric: 'veelta_total_locked',
      value: Number(minLocked),
    },
  ];
}

/**
 * Economic health assertions
 */
export function economicAssertions(options: {
  minApps?: number;
  minFees?: bigint;
  minVeEltaLocked?: bigint;
} = {}): Assertion[] {
  const assertions: Assertion[] = [
    {
      type: 'gte',
      metric: 'app_count',
      value: options.minApps ?? 3,
    },
    {
      type: 'gte',
      metric: 'elta_total_supply',
      value: 1,
    },
  ];

  if (options.minFees !== undefined) {
    assertions.push({
      type: 'gte',
      metric: 'fees_collected_total',
      value: Number(options.minFees),
    });
  }

  if (options.minVeEltaLocked !== undefined) {
    assertions.push({
      type: 'gte',
      metric: 'veelta_total_locked',
      value: Number(options.minVeEltaLocked),
    });
  }

  return assertions;
}

/**
 * App graduation assertions
 */
export function graduationAssertions(minGraduated = 0): Assertion[] {
  return [
    ...basicStabilityAssertions(),
    {
      type: 'gte',
      metric: 'graduated_apps',
      value: minGraduated,
    },
  ];
}

// ============================================
// Agent Stats Utilities
// ============================================

/**
 * Aggregated stats for a group of agents
 */
export interface AggregatedAgentStats {
  type: string;
  count: number;
  totalAttempted: number;
  totalSucceeded: number;
  totalFailed: number;
  avgSuccessRate: number;
  minSuccessRate: number;
  maxSuccessRate: number;
}

/**
 * Individual agent stats from run result
 */
export interface AgentStats {
  id: string;
  actionsAttempted: number;
  actionsSucceeded: number;
  actionsFailed: number;
}

/**
 * Group agent stats by agent type
 */
export function groupAgentStatsByType(stats: AgentStats[]): Map<string, AggregatedAgentStats> {
  const groups = new Map<string, AgentStats[]>();

  // Group by type (extract from agent ID like "BasicUserAgent-0")
  for (const stat of stats) {
    const parts = stat.id.split('-');
    const type = parts.slice(0, -1).join('-') || stat.id;

    const group = groups.get(type) ?? [];
    group.push(stat);
    groups.set(type, group);
  }

  // Aggregate each group
  const aggregated = new Map<string, AggregatedAgentStats>();

  for (const [type, groupStats] of groups) {
    const totalAttempted = groupStats.reduce((sum, s) => sum + s.actionsAttempted, 0);
    const totalSucceeded = groupStats.reduce((sum, s) => sum + s.actionsSucceeded, 0);
    const totalFailed = groupStats.reduce((sum, s) => sum + s.actionsFailed, 0);

    const successRates = groupStats.map((s) =>
      s.actionsAttempted > 0 ? s.actionsSucceeded / s.actionsAttempted : 1
    );

    aggregated.set(type, {
      type,
      count: groupStats.length,
      totalAttempted,
      totalSucceeded,
      totalFailed,
      avgSuccessRate: successRates.reduce((a, b) => a + b, 0) / successRates.length,
      minSuccessRate: Math.min(...successRates),
      maxSuccessRate: Math.max(...successRates),
    });
  }

  return aggregated;
}

/**
 * Calculate overall success rate from agent stats
 */
export function calculateOverallSuccessRate(stats: AgentStats[]): number {
  const totalAttempted = stats.reduce((sum, s) => sum + s.actionsAttempted, 0);
  const totalSucceeded = stats.reduce((sum, s) => sum + s.actionsSucceeded, 0);
  return totalAttempted > 0 ? totalSucceeded / totalAttempted : 1;
}

// ============================================
// Result Formatting
// ============================================

/**
 * Options for printing scenario results
 */
export interface PrintOptions {
  /** Show individual agent stats */
  showAgentStats?: boolean;
  /** Group agent stats by type */
  groupByType?: boolean;
  /** Show all metrics */
  showAllMetrics?: boolean;
  /** Metrics to highlight */
  highlightMetrics?: string[];
  /** Show time series summary */
  showTimeSeries?: boolean;
}

/**
 * Format ELTA amount for display (from wei to ELTA)
 */
export function formatElta(amount: bigint | number | string): string {
  const value = typeof amount === 'bigint' ? amount : BigInt(amount);
  const elta = Number(value) / 1e18;

  if (elta >= 1_000_000) {
    return `${(elta / 1_000_000).toFixed(2)}M ELTA`;
  } else if (elta >= 1_000) {
    return `${(elta / 1_000).toFixed(2)}K ELTA`;
  }
  return `${elta.toFixed(4)} ELTA`;
}

/**
 * Format gas amount for display
 */
export function formatGas(gas: bigint | number | string): string {
  const value = typeof gas === 'bigint' ? Number(gas) : Number(gas);

  if (value >= 1_000_000_000) {
    return `${(value / 1_000_000_000).toFixed(2)}B`;
  } else if (value >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(2)}M`;
  } else if (value >= 1_000) {
    return `${(value / 1_000).toFixed(2)}K`;
  }
  return value.toLocaleString();
}

/**
 * Format duration in milliseconds
 */
export function formatDuration(ms: number): string {
  if (ms >= 60_000) {
    const minutes = Math.floor(ms / 60_000);
    const seconds = Math.floor((ms % 60_000) / 1000);
    return `${minutes}m ${seconds}s`;
  } else if (ms >= 1_000) {
    return `${(ms / 1000).toFixed(1)}s`;
  }
  return `${ms}ms`;
}

/**
 * Print formatted scenario results
 */
export function printScenarioResults(result: RunResult, options: PrintOptions = {}): void {
  const {
    showAgentStats = true,
    groupByType = true,
    showAllMetrics = false,
    highlightMetrics = ['app_count', 'fees_collected_total', 'veelta_total_locked'],
  } = options;

  // Header
  console.log('\n' + '='.repeat(60));
  console.log(`Result: ${result.success ? 'PASS' : 'FAIL'}`);
  console.log(`Duration: ${formatDuration(result.durationMs)}`);
  console.log('='.repeat(60));

  // Key metrics
  console.log('\nKey Metrics:');
  for (const metric of highlightMetrics) {
    const value = result.finalMetrics[metric];
    if (value !== undefined) {
      let formatted: string;
      if (metric.includes('fees') || metric.includes('supply') || metric.includes('locked')) {
        formatted = formatElta(value as bigint);
      } else if (metric.includes('gas')) {
        formatted = formatGas(value as bigint);
      } else {
        formatted = String(value);
      }
      console.log(`  ${metric}: ${formatted}`);
    }
  }

  // All metrics if requested
  if (showAllMetrics) {
    console.log('\nAll Metrics:');
    for (const [key, value] of Object.entries(result.finalMetrics)) {
      console.log(`  ${key}: ${value}`);
    }
  }

  // Agent stats
  if (showAgentStats && result.agentStats.length > 0) {
    console.log('\nAgent Performance:');

    if (groupByType) {
      const grouped = groupAgentStatsByType(result.agentStats);
      for (const [type, stats] of grouped) {
        const rate = Math.round(stats.avgSuccessRate * 100);
        console.log(
          `  ${type}: ${stats.totalSucceeded}/${stats.totalAttempted} (${rate}%)`
        );
      }
    } else {
      for (const stat of result.agentStats) {
        const rate =
          stat.actionsAttempted > 0
            ? Math.round((stat.actionsSucceeded / stat.actionsAttempted) * 100)
            : 100;
        console.log(
          `  ${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted} (${rate}%)`
        );
      }
    }
  }

  // Failed assertions
  if (result.failedAssertions.length > 0) {
    console.log('\nFailed Assertions:');
    for (const failure of result.failedAssertions) {
      console.log(`  - ${failure.message}`);
    }
  }

  console.log('');
}

// ============================================
// Economic Calculations
// ============================================

/**
 * Calculate revenue per user
 */
export function calculateRevenuePerUser(
  totalFees: bigint,
  uniqueUsers: number
): bigint {
  if (uniqueUsers === 0) return 0n;
  return totalFees / BigInt(uniqueUsers);
}

/**
 * Calculate revenue per transaction
 */
export function calculateRevenuePerTransaction(
  totalFees: bigint,
  totalTransactions: number
): bigint {
  if (totalTransactions === 0) return 0n;
  return totalFees / BigInt(totalTransactions);
}

/**
 * Calculate annualized revenue projection
 * @param totalFees Fees collected
 * @param ticks Number of ticks
 * @param tickSeconds Seconds per tick
 */
export function projectAnnualRevenue(
  totalFees: bigint,
  ticks: number,
  tickSeconds: number
): bigint {
  const simulatedSeconds = ticks * tickSeconds;
  const secondsPerYear = 365 * 24 * 60 * 60;

  // Scale fees to annual projection
  const scaleFactor = secondsPerYear / simulatedSeconds;
  return BigInt(Math.floor(Number(totalFees) * scaleFactor));
}

/**
 * Calculate capital utilization rate
 */
export function calculateCapitalUtilization(
  activeTvl: bigint,
  totalTvl: bigint
): number {
  if (totalTvl === 0n) return 0;
  return Number(activeTvl) / Number(totalTvl);
}

// ============================================
// Statistical Utilities
// ============================================

/**
 * Statistical summary of a set of values
 */
export interface Statistics {
  mean: number;
  stdDev: number;
  min: number;
  max: number;
  median: number;
  ci95Low: number;
  ci95High: number;
}

/**
 * Calculate statistics for an array of numbers
 */
export function calculateStatistics(values: number[]): Statistics {
  if (values.length === 0) {
    return {
      mean: 0,
      stdDev: 0,
      min: 0,
      max: 0,
      median: 0,
      ci95Low: 0,
      ci95High: 0,
    };
  }

  const sorted = [...values].sort((a, b) => a - b);
  const n = values.length;

  const mean = values.reduce((a, b) => a + b, 0) / n;
  const variance = values.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / n;
  const stdDev = Math.sqrt(variance);

  const median =
    n % 2 === 0
      ? (sorted[n / 2 - 1]! + sorted[n / 2]!) / 2
      : sorted[Math.floor(n / 2)]!;

  // 95% confidence interval
  const tValue = 1.96;
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

// ============================================
// Scenario Configuration Helpers
// ============================================

/**
 * Common agent funding levels
 */
export const FUNDING_LEVELS = {
  /** Small user: 1,000 ELTA */
  small: 1000n * 10n ** 18n,
  /** Medium user: 10,000 ELTA */
  medium: 10_000n * 10n ** 18n,
  /** Large user: 100,000 ELTA */
  large: 100_000n * 10n ** 18n,
  /** Whale user: 1,000,000 ELTA */
  whale: 1_000_000n * 10n ** 18n,
} as const;

/**
 * Common tick durations
 */
export const TICK_DURATIONS = {
  /** 1 hour per tick */
  hourly: 3600,
  /** 1 day per tick */
  daily: 86400,
  /** 1 week per tick */
  weekly: 604800,
} as const;

/**
 * Common scenario durations
 */
export const SCENARIO_DURATIONS = {
  /** Quick smoke test: 5-10 ticks */
  smoke: { ticks: 10, tickSeconds: TICK_DURATIONS.hourly },
  /** Integration test: 30-50 ticks */
  integration: { ticks: 50, tickSeconds: TICK_DURATIONS.daily },
  /** Economic validation: 100+ ticks */
  economic: { ticks: 100, tickSeconds: TICK_DURATIONS.daily },
  /** Long-running: 365+ ticks */
  annual: { ticks: 365, tickSeconds: TICK_DURATIONS.daily },
} as const;

// ============================================
// Main function helper
// ============================================

/**
 * Standard main function wrapper for scenarios
 */
export async function runScenario(
  name: string,
  scenarioFn: () => Promise<RunResult>,
  options: PrintOptions = {}
): Promise<void> {
  console.log(`=== ${name} ===\n`);

  try {
    const result = await scenarioFn();
    printScenarioResults(result, options);
    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}
