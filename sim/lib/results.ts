/**
 * Standardized Results Format
 *
 * Provides a unified JSON output format for all simulation tests.
 */

import { writeFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { RunResult } from '@elata-biosciences/agentforge';
import type { ErrorSummary } from './errors.js';
import { formatElta } from './scenario-helpers.js';

export const RESULT_FORMAT_VERSION = '1.0' as const;

export interface ResultMeta {
  version: typeof RESULT_FORMAT_VERSION;
  timestamp: string;
  scenario: string;
  seed: number;
  ticks: number;
  durationMs: number;
  simulatedDays: number;
}

export interface AssertionResult {
  name: string;
  passed: boolean;
  expected?: string | number;
  actual?: string | number;
  message?: string;
}

export interface OutcomeSummary {
  success: boolean;
  assertions: AssertionResult[];
  errors: ErrorSummary;
}

export interface EconomicsSummary {
  revenue: {
    feesCollected: string;
    feesDistributed: string;
    netRevenue: string;
  };
  volume: {
    totalTrades: number;
    totalVolume: string;
  };
  agents: {
    totalPnL: string;
    profitableCount: number;
    totalCount: number;
  };
}

export interface AgentPerformance {
  id: string;
  type: string;
  actionsAttempted: number;
  actionsSucceeded: number;
  successRate: number;
  pnl?: string;
}

export interface MetricsSummary {
  final: Record<string, string | number>;
  timeSeries?: Array<{ tick: number; values: Record<string, number> }>;
}

export interface StandardizedResult {
  meta: ResultMeta;
  outcome: OutcomeSummary;
  economics: EconomicsSummary;
  metrics: MetricsSummary;
  agents: AgentPerformance[];
}

export function formatResult(
  result: RunResult,
  options: {
    scenario: string;
    seed?: number;
    tickSeconds?: number;
    errorSummary?: ErrorSummary;
  }
): StandardizedResult {
  const { scenario, seed = 0, tickSeconds = 86400, errorSummary } = options;

  const ticks = result.ticks ?? 0;
  const simulatedDays = (ticks * tickSeconds) / 86400;

  const assertions: AssertionResult[] = result.failedAssertions.map((f) => ({
    name: f.assertion?.metric ?? 'unknown',
    passed: false,
    message: f.message,
  }));

  const feesCollected = result.finalMetrics.fees_collected_total as bigint ?? 0n;
  const feesDistributed = result.finalMetrics.fees_distributed as bigint ?? 0n;
  const netRevenue = feesCollected - feesDistributed;

  const totalTrades = result.agentStats.reduce((sum, s) => sum + s.actionsSucceeded, 0);

  let totalPnL = 0n;
  let profitableCount = 0;
  for (const [key, value] of Object.entries(result.finalMetrics)) {
    if (key.startsWith('agent_') && key.endsWith('_realized_pnl')) {
      const pnl = typeof value === 'bigint' ? value : BigInt(value as number);
      totalPnL += pnl;
      if (pnl > 0n) profitableCount++;
    }
  }

  const agents: AgentPerformance[] = result.agentStats.map((stat) => {
    const parts = stat.id.split('-');
    const type = parts.slice(0, -1).join('-') || stat.id;
    const successRate = stat.actionsAttempted > 0
      ? stat.actionsSucceeded / stat.actionsAttempted
      : 1;

    const agent: AgentPerformance = {
      id: stat.id,
      type,
      actionsAttempted: stat.actionsAttempted,
      actionsSucceeded: stat.actionsSucceeded,
      successRate,
    };

    const pnlKey = 'agent_' + stat.id + '_realized_pnl';
    const pnlValue = result.finalMetrics[pnlKey];
    if (pnlValue !== undefined) {
      agent.pnl = formatElta(typeof pnlValue === 'bigint' ? pnlValue : BigInt(pnlValue as number));
    }

    return agent;
  });

  const final: Record<string, string | number> = {};
  for (const [key, value] of Object.entries(result.finalMetrics)) {
    if (typeof value === 'bigint') {
      final[key] = value.toString();
    } else if (typeof value === 'number' || typeof value === 'string') {
      final[key] = value;
    }
  }

  return {
    meta: {
      version: RESULT_FORMAT_VERSION,
      timestamp: new Date().toISOString(),
      scenario,
      seed,
      ticks,
      durationMs: result.durationMs,
      simulatedDays,
    },
    outcome: {
      success: result.success,
      assertions,
      errors: errorSummary ?? {
        totalErrors: 0,
        byCategory: {} as Record<string, number>,
        byAgent: {},
        byAction: {},
        samples: [],
      },
    },
    economics: {
      revenue: {
        feesCollected: formatElta(feesCollected),
        feesDistributed: formatElta(feesDistributed),
        netRevenue: formatElta(netRevenue),
      },
      volume: {
        totalTrades,
        totalVolume: formatElta(feesCollected * 50n),
      },
      agents: {
        totalPnL: formatElta(totalPnL),
        profitableCount,
        totalCount: agents.length,
      },
    },
    metrics: {
      final,
    },
    agents,
  };
}

export async function exportToJSON(result: StandardizedResult, path: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, JSON.stringify(result, null, 2));
}

export function exportToMarkdown(result: StandardizedResult): string {
  const lines: string[] = [];

  lines.push('# Simulation Result: ' + result.meta.scenario);
  lines.push('');
  lines.push('Generated: ' + result.meta.timestamp);
  lines.push('');

  lines.push('## Summary');
  lines.push('');
  lines.push('| Metric | Value |');
  lines.push('|--------|-------|');
  lines.push('| Status | ' + (result.outcome.success ? 'PASS' : 'FAIL') + ' |');
  lines.push('| Duration | ' + (result.meta.durationMs / 1000).toFixed(1) + 's |');
  lines.push('| Simulated Days | ' + result.meta.simulatedDays.toFixed(0) + ' |');
  lines.push('| Total Agents | ' + result.agents.length + ' |');
  lines.push('');

  lines.push('## Economic Summary');
  lines.push('');
  lines.push('| Metric | Value |');
  lines.push('|--------|-------|');
  lines.push('| Fees Collected | ' + result.economics.revenue.feesCollected + ' |');
  lines.push('| Fees Distributed | ' + result.economics.revenue.feesDistributed + ' |');
  lines.push('| Net Revenue | ' + result.economics.revenue.netRevenue + ' |');
  lines.push('| Total Trades | ' + result.economics.volume.totalTrades + ' |');
  lines.push('');

  lines.push('## Agent Performance');
  lines.push('');
  lines.push('| Type | Count | Actions | Success Rate |');
  lines.push('|------|-------|---------|--------------|');

  const byType = new Map<string, { count: number; actions: number; succeeded: number }>();
  for (const agent of result.agents) {
    const existing = byType.get(agent.type) ?? { count: 0, actions: 0, succeeded: 0 };
    existing.count++;
    existing.actions += agent.actionsAttempted;
    existing.succeeded += agent.actionsSucceeded;
    byType.set(agent.type, existing);
  }

  for (const [type, stats] of byType) {
    const rate = stats.actions > 0 ? Math.round((stats.succeeded / stats.actions) * 100) : 100;
    lines.push('| ' + type + ' | ' + stats.count + ' | ' + stats.actions + ' | ' + rate + '% |');
  }
  lines.push('');

  return lines.join('\n');
}

export async function exportMarkdownToFile(result: StandardizedResult, path: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, exportToMarkdown(result));
}

export function aggregateResults(results: StandardizedResult[]): {
  totalRuns: number;
  successRate: number;
  avgDurationMs: number;
  avgSimulatedDays: number;
  totalFeesCollected: string;
  avgAgentSuccessRate: number;
} {
  const successCount = results.filter((r) => r.outcome.success).length;
  const totalDuration = results.reduce((sum, r) => sum + r.meta.durationMs, 0);
  const totalDays = results.reduce((sum, r) => sum + r.meta.simulatedDays, 0);

  let totalFees = 0n;
  for (const r of results) {
    const feesStr = r.economics.revenue.feesCollected;
    const match = feesStr.match(/([\d.]+)([KMB]?)\s*ELTA/);
    if (match) {
      let value = parseFloat(match[1]!);
      const suffix = match[2];
      if (suffix === 'K') value *= 1000;
      if (suffix === 'M') value *= 1000000;
      if (suffix === 'B') value *= 1000000000;
      totalFees += BigInt(Math.floor(value * 1e18));
    }
  }

  let totalAgentRate = 0;
  let agentCount = 0;
  for (const r of results) {
    for (const agent of r.agents) {
      totalAgentRate += agent.successRate;
      agentCount++;
    }
  }

  return {
    totalRuns: results.length,
    successRate: results.length > 0 ? successCount / results.length : 0,
    avgDurationMs: results.length > 0 ? totalDuration / results.length : 0,
    avgSimulatedDays: results.length > 0 ? totalDays / results.length : 0,
    totalFeesCollected: formatElta(totalFees),
    avgAgentSuccessRate: agentCount > 0 ? totalAgentRate / agentCount : 1,
  };
}
