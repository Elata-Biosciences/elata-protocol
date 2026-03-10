#!/usr/bin/env tsx

import { spawn } from 'node:child_process';
import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';

type Summary = {
  runId: string;
  scenarioName: string;
  success: boolean;
  finalMetrics: Record<string, number | string>;
};

type RunConfig = {
  scenarioFile: string;
  resultsDirName: string;
  seed: number;
  port: number;
};

function runScenario(config: RunConfig): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn('pnpm', ['exec', 'tsx', config.scenarioFile], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        SIMULATION_SEED: String(config.seed),
        ANVIL_PORT: String(config.port),
      },
    });

    let stderr = '';
    proc.stdout.on('data', () => {
      // Drain stdout to avoid pipe backpressure during long scenario runs.
    });
    proc.stderr.on('data', (d) => {
      stderr += d.toString();
    });
    proc.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`scenario_failed:${config.scenarioFile}::${stderr}`));
    });
    proc.on('error', reject);
  });
}

async function loadLatestSummary(resultsDirName: string): Promise<Summary> {
  const base = join(process.cwd(), 'results', resultsDirName);
  const runDirs = (await readdir(base, { withFileTypes: true }))
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort()
    .reverse();
  if (runDirs.length === 0) {
    throw new Error(`no_runs_found:${resultsDirName}`);
  }
  const summaryPath = join(base, runDirs[0]!, 'summary.json');
  const raw = await readFile(summaryPath, 'utf-8');
  return JSON.parse(raw) as Summary;
}

function numMetric(summary: Summary, key: string): number {
  const value = summary.finalMetrics[key];
  if (typeof value === 'number') return value;
  if (typeof value === 'string' && value.trim() !== '') return Number(value);
  return 0;
}

function stddev(values: number[]): number {
  if (values.length <= 1) return 0;
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  const variance = values.reduce((acc, v) => acc + (v - mean) ** 2, 0) / values.length;
  return Math.sqrt(variance);
}

async function deterministicCheck(): Promise<void> {
  const scenarioFile = 'scenarios/calibration/deterministic-agents.ts';
  const resultsDirName = 'calibration-deterministic-agents';

  await runScenario({ scenarioFile, resultsDirName, seed: 9001, port: 8680 });
  const first = await loadLatestSummary(resultsDirName);
  await runScenario({ scenarioFile, resultsDirName, seed: 9001, port: 8681 });
  const second = await loadLatestSummary(resultsDirName);

  if (!first.success || !second.success) {
    throw new Error('determinism_check_failed:run_not_successful');
  }

  const firstApps = numMetric(first, 'app_count');
  const secondApps = numMetric(second, 'app_count');
  if (Math.abs(firstApps - secondApps) > 1) {
    throw new Error(`determinism_check_failed:app_count_delta_too_high:${firstApps}:${secondApps}`);
  }
}

async function stochasticCheck(): Promise<void> {
  const scenarioFile = 'scenarios/calibration/stochastic-agents.ts';
  const resultsDirName = 'calibration-stochastic-agents';
  const collected: number[] = [];

  const seeds = [9101, 9102, 9103];
  for (let i = 0; i < seeds.length; i += 1) {
    await runScenario({
      scenarioFile,
      resultsDirName,
      seed: seeds[i]!,
      port: 8690 + i,
    });
    const summary = await loadLatestSummary(resultsDirName);
    if (!summary.success) {
      throw new Error(`stochastic_run_failed:seed=${seeds[i]}`);
    }
    collected.push(numMetric(summary, 'fees_collected_total'));
  }

  const sigma = stddev(collected);
  if (sigma <= 0) {
    throw new Error('stochastic_variation_failed:zero_stddev');
  }
}

async function main(): Promise<void> {
  console.log('Agent calibration: deterministic checks...');
  await deterministicCheck();
  console.log('Agent calibration: stochastic distribution checks...');
  await stochasticCheck();
  console.log('Agent calibration passed.');
}

void main();
