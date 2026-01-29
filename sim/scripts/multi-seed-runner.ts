#!/usr/bin/env tsx
/**
 * multi-seed-runner.ts - Run a scenario with multiple seeds for statistical analysis
 *
 * Runs the same scenario multiple times with different random seeds,
 * then aggregates results for statistical confidence.
 *
 * Usage:
 *   pnpm multi-seed <scenario-file> [--seeds=10] [--parallel=2]
 *
 * Example:
 *   pnpm multi-seed scenarios/smoke/buy-tokens.ts --seeds=20 --parallel=4
 */

import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

interface RunResult {
  seed: number;
  success: boolean;
  durationMs: number;
  finalMetrics: Record<string, number | string | bigint>;
  agentStats: Array<{
    id: string;
    actionsAttempted: number;
    actionsSucceeded: number;
  }>;
  error?: string;
}

interface AggregatedResults {
  scenarioFile: string;
  totalRuns: number;
  successfulRuns: number;
  failedRuns: number;
  successRate: number;
  durationStats: {
    mean: number;
    stdDev: number;
    min: number;
    max: number;
    ci95: [number, number];
  };
  metricStats: Record<
    string,
    {
      mean: number;
      stdDev: number;
      min: number;
      max: number;
      ci95: [number, number];
    }
  >;
  agentSuccessRates: Record<
    string,
    {
      mean: number;
      stdDev: number;
      ci95: [number, number];
    }
  >;
  runs: RunResult[];
}

function parseArgs(): { scenarioFile: string; seeds: number; parallel: number } {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0]?.startsWith('--')) {
    console.error('Usage: multi-seed-runner.ts <scenario-file> [--seeds=10] [--parallel=2]');
    process.exit(1);
  }

  const scenarioFile = args[0]!;
  let seeds = 10;
  let parallel = 2;

  for (const arg of args.slice(1)) {
    if (arg.startsWith('--seeds=')) {
      seeds = Number.parseInt(arg.split('=')[1] ?? '10', 10);
    }
    if (arg.startsWith('--parallel=')) {
      parallel = Number.parseInt(arg.split('=')[1] ?? '2', 10);
    }
  }

  return { scenarioFile, seeds, parallel };
}

function calculateStats(values: number[]): {
  mean: number;
  stdDev: number;
  min: number;
  max: number;
  ci95: [number, number];
} {
  if (values.length === 0) {
    return { mean: 0, stdDev: 0, min: 0, max: 0, ci95: [0, 0] };
  }

  const n = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const variance = values.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / n;
  const stdDev = Math.sqrt(variance);

  const sorted = [...values].sort((a, b) => a - b);
  const min = sorted[0]!;
  const max = sorted[n - 1]!;

  // 95% CI
  const tValue = 1.96;
  const se = stdDev / Math.sqrt(n);
  const ci95: [number, number] = [mean - tValue * se, mean + tValue * se];

  return { mean, stdDev, min, max, ci95 };
}

async function runScenarioWithSeed(
  scenarioFile: string,
  seed: number,
  port: number
): Promise<RunResult> {
  return new Promise((resolve) => {
    const startTime = Date.now();

    // Create a temporary modified scenario with the seed
    const proc = spawn('tsx', [scenarioFile], {
      env: {
        ...process.env,
        SIMULATION_SEED: String(seed),
        ANVIL_PORT: String(port),
      },
      cwd: join(__dirname, '..'),
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    proc.on('close', (code) => {
      const durationMs = Date.now() - startTime;

      if (code === 0) {
        // Parse output for metrics (basic parsing)
        const success = !stdout.includes('FAIL');

        resolve({
          seed,
          success,
          durationMs,
          finalMetrics: {},
          agentStats: [],
        });
      } else {
        resolve({
          seed,
          success: false,
          durationMs,
          finalMetrics: {},
          agentStats: [],
          error: stderr || `Exit code: ${code}`,
        });
      }
    });

    proc.on('error', (error) => {
      resolve({
        seed,
        success: false,
        durationMs: Date.now() - startTime,
        finalMetrics: {},
        agentStats: [],
        error: error.message,
      });
    });
  });
}

async function runBatch(
  scenarioFile: string,
  seeds: number[],
  basePort: number
): Promise<RunResult[]> {
  const promises = seeds.map((seed, idx) =>
    runScenarioWithSeed(scenarioFile, seed, basePort + idx)
  );
  return Promise.all(promises);
}

async function main(): Promise<void> {
  const { scenarioFile, seeds, parallel } = parseArgs();

  console.log('='.repeat(60));
  console.log('Multi-Seed Scenario Runner');
  console.log('='.repeat(60));
  console.log(`\nScenario: ${scenarioFile}`);
  console.log(`Seeds: ${seeds}`);
  console.log(`Parallel runs: ${parallel}`);
  console.log('');

  const allSeeds = Array.from({ length: seeds }, (_, i) => i + 1);
  const results: RunResult[] = [];

  // Run in batches
  const basePort = 8600;
  for (let i = 0; i < allSeeds.length; i += parallel) {
    const batch = allSeeds.slice(i, i + parallel);
    console.log(
      `Running batch ${Math.floor(i / parallel) + 1}/${Math.ceil(allSeeds.length / parallel)}: seeds ${batch.join(', ')}`
    );

    const batchResults = await runBatch(scenarioFile, batch, basePort);
    results.push(...batchResults);

    // Progress indicator
    const successCount = batchResults.filter((r) => r.success).length;
    console.log(`  Completed: ${successCount}/${batch.length} successful`);
  }

  // Aggregate results
  const successful = results.filter((r) => r.success);
  const failed = results.filter((r) => !r.success);

  const aggregated: AggregatedResults = {
    scenarioFile,
    totalRuns: results.length,
    successfulRuns: successful.length,
    failedRuns: failed.length,
    successRate: (successful.length / results.length) * 100,
    durationStats: calculateStats(results.map((r) => r.durationMs)),
    metricStats: {},
    agentSuccessRates: {},
    runs: results,
  };

  // Print summary
  console.log('\n' + '='.repeat(60));
  console.log('RESULTS SUMMARY');
  console.log('='.repeat(60));

  console.log(`\nTotal Runs: ${aggregated.totalRuns}`);
  console.log(`Successful: ${aggregated.successfulRuns} (${aggregated.successRate.toFixed(1)}%)`);
  console.log(`Failed: ${aggregated.failedRuns}`);

  console.log('\nDuration Statistics:');
  console.log(`  Mean: ${aggregated.durationStats.mean.toFixed(0)}ms`);
  console.log(`  Std Dev: ${aggregated.durationStats.stdDev.toFixed(0)}ms`);
  console.log(`  Range: ${aggregated.durationStats.min}ms - ${aggregated.durationStats.max}ms`);
  console.log(
    `  95% CI: [${aggregated.durationStats.ci95[0].toFixed(0)}ms, ${aggregated.durationStats.ci95[1].toFixed(0)}ms]`
  );

  if (failed.length > 0) {
    console.log('\nFailed Runs:');
    for (const fail of failed.slice(0, 5)) {
      console.log(`  Seed ${fail.seed}: ${fail.error ?? 'Unknown error'}`);
    }
    if (failed.length > 5) {
      console.log(`  ... and ${failed.length - 5} more`);
    }
  }

  // Save results
  const resultsDir = join(__dirname, '..', 'results', 'multi-seed');
  await mkdir(resultsDir, { recursive: true });

  const scenarioName = basename(scenarioFile, '.ts');
  const outputFile = join(resultsDir, `${scenarioName}-${Date.now()}.json`);

  await writeFile(outputFile, JSON.stringify(aggregated, null, 2));
  console.log(`\nResults saved to: ${outputFile}`);

  // Exit with appropriate code
  process.exit(aggregated.successRate < 70 ? 1 : 0);
}

void main();
