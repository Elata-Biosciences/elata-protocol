/**
 * Results Dashboard Generator
 *
 * Generates an HTML dashboard from simulation results.
 */

import { readdir, readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { StandardizedResult } from '../lib/results.js';
import { aggregateResults } from '../lib/results.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ============================================
// Dashboard Generation
// ============================================

function generateDashboard(results: StandardizedResult[]): string {
  const aggregated = aggregateResults(results);

  // Group by scenario
  const byScenario = new Map<string, StandardizedResult[]>();
  for (const result of results) {
    const group = byScenario.get(result.meta.scenario) ?? [];
    group.push(result);
    byScenario.set(result.meta.scenario, group);
  }

  // Generate scenario rows
  const scenarioRows = Array.from(byScenario.entries())
    .map(([scenario, runs]) => {
      const successCount = runs.filter((r) => r.outcome.success).length;
      const successRate = Math.round((successCount / runs.length) * 100);
      const avgDuration = runs.reduce((s, r) => s + r.meta.durationMs, 0) / runs.length;
      const statusClass = successRate === 100 ? 'success' : successRate >= 80 ? 'warning' : 'error';

      return '<tr>' +
        '<td>' + scenario + '</td>' +
        '<td>' + runs.length + '</td>' +
        '<td class="' + statusClass + '">' + successRate + '%</td>' +
        '<td>' + (avgDuration / 1000).toFixed(1) + 's</td>' +
        '</tr>';
    })
    .join('\n');

  // Generate agent performance chart data
  const agentTypes = new Map<string, { success: number; total: number }>();
  for (const result of results) {
    for (const agent of result.agents) {
      const existing = agentTypes.get(agent.type) ?? { success: 0, total: 0 };
      existing.success += agent.actionsSucceeded;
      existing.total += agent.actionsAttempted;
      agentTypes.set(agent.type, existing);
    }
  }

  const agentLabels = Array.from(agentTypes.keys());
  const agentRates = agentLabels.map((type) => {
    const stats = agentTypes.get(type)!;
    return stats.total > 0 ? Math.round((stats.success / stats.total) * 100) : 100;
  });

  return '<!DOCTYPE html>' +
    '<html lang="en">' +
    '<head>' +
    '<meta charset="UTF-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">' +
    '<title>Simulation Results Dashboard</title>' +
    '<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>' +
    '<style>' +
    'body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }' +
    '.container { max-width: 1200px; margin: 0 auto; }' +
    'h1 { color: #333; }' +
    '.card { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }' +
    '.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 20px; }' +
    '.stat { background: white; border-radius: 8px; padding: 20px; text-align: center; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }' +
    '.stat-value { font-size: 2em; font-weight: bold; color: #2563eb; }' +
    '.stat-label { color: #666; margin-top: 5px; }' +
    'table { width: 100%; border-collapse: collapse; }' +
    'th, td { padding: 12px; text-align: left; border-bottom: 1px solid #eee; }' +
    'th { background: #f8f9fa; font-weight: 600; }' +
    '.success { color: #16a34a; }' +
    '.warning { color: #ca8a04; }' +
    '.error { color: #dc2626; }' +
    '.chart-container { height: 300px; }' +
    '.generated { color: #999; font-size: 0.9em; margin-top: 20px; }' +
    '</style>' +
    '</head>' +
    '<body>' +
    '<div class="container">' +
    '<h1>Simulation Results Dashboard</h1>' +
    '<div class="stats">' +
    '<div class="stat">' +
    '<div class="stat-value">' + aggregated.totalRuns + '</div>' +
    '<div class="stat-label">Total Runs</div>' +
    '</div>' +
    '<div class="stat">' +
    '<div class="stat-value ' + (aggregated.successRate >= 0.8 ? 'success' : 'error') + '">' + Math.round(aggregated.successRate * 100) + '%</div>' +
    '<div class="stat-label">Success Rate</div>' +
    '</div>' +
    '<div class="stat">' +
    '<div class="stat-value">' + (aggregated.avgDurationMs / 1000).toFixed(1) + 's</div>' +
    '<div class="stat-label">Avg Duration</div>' +
    '</div>' +
    '<div class="stat">' +
    '<div class="stat-value">' + aggregated.totalFeesCollected + '</div>' +
    '<div class="stat-label">Total Fees</div>' +
    '</div>' +
    '</div>' +
    '<div class="card">' +
    '<h2>Scenario Results</h2>' +
    '<table>' +
    '<thead><tr><th>Scenario</th><th>Runs</th><th>Success Rate</th><th>Avg Duration</th></tr></thead>' +
    '<tbody>' + scenarioRows + '</tbody>' +
    '</table>' +
    '</div>' +
    '<div class="card">' +
    '<h2>Agent Performance</h2>' +
    '<div class="chart-container">' +
    '<canvas id="agentChart"></canvas>' +
    '</div>' +
    '</div>' +
    '<p class="generated">Generated: ' + new Date().toISOString() + '</p>' +
    '</div>' +
    '<script>' +
    'new Chart(document.getElementById("agentChart"), {' +
    'type: "bar",' +
    'data: {' +
    'labels: ' + JSON.stringify(agentLabels) + ',' +
    'datasets: [{' +
    'label: "Success Rate %",' +
    'data: ' + JSON.stringify(agentRates) + ',' +
    'backgroundColor: "rgba(37, 99, 235, 0.7)"' +
    '}]' +
    '},' +
    'options: {' +
    'responsive: true,' +
    'maintainAspectRatio: false,' +
    'scales: { y: { beginAtZero: true, max: 100 } },' +
    'plugins: { legend: { display: false } }' +
    '}' +
    '});' +
    '</script>' +
    '</body>' +
    '</html>';
}

// ============================================
// Result Loading
// ============================================

async function loadResults(resultsDir: string): Promise<StandardizedResult[]> {
  const results: StandardizedResult[] = [];

  async function processResultDir(scenarioName: string, runDir: string): Promise<void> {
    // Try standardized result first
    const standardPath = join(runDir, 'result.json');
    try {
      const content = await readFile(standardPath, 'utf-8');
      results.push(JSON.parse(content));
      return;
    } catch {
      // Not found, try summary.json
    }

    // Fall back to summary.json
    const summaryPath = join(runDir, 'summary.json');
    try {
      const content = await readFile(summaryPath, 'utf-8');
      const summary = JSON.parse(content);

      // Convert to StandardizedResult format
      results.push({
        meta: {
          version: '1.0',
          timestamp: new Date().toISOString(),
          scenario: scenarioName,
          seed: summary.seed ?? 0,
          ticks: summary.ticks ?? 0,
          durationMs: summary.durationMs ?? 0,
          simulatedDays: (summary.ticks ?? 0) * (summary.tickSeconds ?? 86400) / 86400,
        },
        outcome: {
          success: summary.success ?? false,
          assertions: [],
          errors: {
            totalErrors: 0,
            byCategory: {
              insufficient_balance: 0,
              invalid_state: 0,
              contract_revert: 0,
              timeout: 0,
              network: 0,
              validation: 0,
              precondition: 0,
              configuration: 0,
              unknown: 0,
            },
            byAgent: {},
            byAction: {},
            samples: [],
          },
        },
        economics: {
          revenue: {
            feesCollected: String(summary.finalMetrics?.fees_collected_total ?? '0'),
            feesDistributed: String(summary.finalMetrics?.fees_distributed ?? '0'),
            netRevenue: '0',
          },
          volume: {
            totalTrades: summary.agentStats?.reduce((s: number, a: { actionsSucceeded: number }) => s + a.actionsSucceeded, 0) ?? 0,
            totalVolume: '0',
          },
          agents: {
            totalPnL: '0',
            profitableCount: 0,
            totalCount: summary.agentStats?.length ?? 0,
          },
        },
        metrics: {
          final: summary.finalMetrics ?? {},
        },
        agents: (summary.agentStats ?? []).map((s: { id: string; actionsAttempted: number; actionsSucceeded: number }) => ({
          id: s.id,
          type: s.id.split('-').slice(0, -1).join('-') || s.id,
          actionsAttempted: s.actionsAttempted,
          actionsSucceeded: s.actionsSucceeded,
          successRate: s.actionsAttempted > 0 ? s.actionsSucceeded / s.actionsAttempted : 1,
        })),
      });
    } catch {
      // Skip if not found
    }
  }

  try {
    const scenarioDirs = await readdir(resultsDir, { withFileTypes: true });

    for (const scenarioDir of scenarioDirs) {
      if (!scenarioDir.isDirectory()) continue;

      const scenarioPath = join(resultsDir, scenarioDir.name);
      const runDirs = await readdir(scenarioPath, { withFileTypes: true });

      for (const runDir of runDirs) {
        if (!runDir.isDirectory()) continue;
        await processResultDir(scenarioDir.name, join(scenarioPath, runDir.name));
      }
    }
  } catch (error) {
    console.error('Error loading results:', error);
  }

  return results;
}

// ============================================
// Main
// ============================================

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const resultsDir = args[0] ?? join(__dirname, '..', 'results');
  const outputPath = args.includes('--output')
    ? args[args.indexOf('--output') + 1]
    : join(resultsDir, 'dashboard.html');

  console.log('Dashboard Generator');
  console.log('Loading results from: ' + resultsDir);

  const results = await loadResults(resultsDir);

  if (results.length === 0) {
    console.log('No results found.');
    process.exit(1);
  }

  console.log('Found ' + results.length + ' result(s)');

  const html = generateDashboard(results);

  await mkdir(dirname(outputPath!), { recursive: true });
  await writeFile(outputPath!, html);

  console.log('Dashboard generated: ' + outputPath);

  // Open in browser if requested
  if (args.includes('--open')) {
    const { exec } = await import('node:child_process');
    exec('open "' + outputPath + '"');
  }
}

void main();

export { generateDashboard };
