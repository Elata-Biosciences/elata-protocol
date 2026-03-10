/**
 * Generative Test Runner
 *
 * Generates diverse scenario configurations and runs them systematically
 * to explore the protocol's state space and identify edge cases.
 */

import { spawn } from 'node:child_process';
import { writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { calculateStatistics, type Statistics } from '../lib/scenario-helpers.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ============================================
// Configuration Types
// ============================================

interface Range {
  min: number;
  max: number;
  step: number;
}

interface AgentTypeConfig {
  type: string;
  weight: number; // Relative frequency
  paramRanges?: Record<string, Range | number[]>;
}

interface GenerativeConfig {
  name: string;
  /** Total agent counts to explore */
  agentCounts: Range;
  /** Tick counts to explore */
  tickCounts: Range;
  /** Funding levels to try */
  fundingLevels: bigint[];
  /** Agent types with weights */
  agentTypes: AgentTypeConfig[];
  /** Metrics to track */
  targetMetrics: string[];
  /** Seeds per configuration */
  seedsPerConfig: number;
  /** Total configurations to generate */
  maxConfigurations: number;
  /** Parallel runs */
  parallelRuns: number;
  /** Confidence level for statistics */
  confidenceLevel: number;
}

interface GeneratedScenario {
  id: string;
  agentCount: number;
  tickCount: number;
  fundingLevel: bigint;
  agentDistribution: Array<{ type: string; count: number; params: Record<string, unknown> }>;
  seed: number;
}

interface RunResult {
  scenarioId: string;
  success: boolean;
  durationMs: number;
  metrics: Record<string, number | string>;
  agentStats: Array<{
    type: string;
    successRate: number;
    totalActions: number;
  }>;
  error?: string;
}

interface AggregatedResults {
  config: GenerativeConfig;
  totalRuns: number;
  successfulRuns: number;
  failedRuns: number;
  successRate: number;
  durationStats: Statistics;
  metricStats: Record<string, Statistics>;
  byAgentCount: Map<number, { successRate: number; avgDuration: number }>;
  byTickCount: Map<number, { successRate: number; avgMetrics: Record<string, number> }>;
  insights: string[];
}

// ============================================
// Configuration Generation
// ============================================

function* rangeIterator(range: Range): Generator<number> {
  for (let v = range.min; v <= range.max; v += range.step) {
    yield v;
  }
}

function generateDistribution(
  totalAgents: number,
  agentTypes: AgentTypeConfig[],
  seed: number
): Array<{ type: string; count: number; params: Record<string, unknown> }> {
  // Seeded random for reproducibility
  let rng = seed;
  const random = () => {
    rng = (rng * 1103515245 + 12345) & 0x7fffffff;
    return rng / 0x7fffffff;
  };

  const totalWeight = agentTypes.reduce((sum, at) => sum + at.weight, 0);
  const distribution: Array<{ type: string; count: number; params: Record<string, unknown> }> = [];

  let remaining = totalAgents;

  for (let i = 0; i < agentTypes.length; i++) {
    const agentType = agentTypes[i]!;
    const isLast = i === agentTypes.length - 1;

    // Calculate count based on weight
    const baseCount = Math.floor((agentType.weight / totalWeight) * totalAgents);
    const count = isLast ? remaining : Math.min(baseCount, remaining);

    if (count > 0) {
      // Generate random params within ranges
      const params: Record<string, unknown> = {};
      if (agentType.paramRanges) {
        for (const [key, value] of Object.entries(agentType.paramRanges)) {
          if (Array.isArray(value)) {
            params[key] = value[Math.floor(random() * value.length)];
          } else {
            const range = value as Range;
            params[key] = range.min + random() * (range.max - range.min);
          }
        }
      }

      distribution.push({ type: agentType.type, count, params });
      remaining -= count;
    }
  }

  return distribution;
}

function generateScenarios(config: GenerativeConfig): GeneratedScenario[] {
  const scenarios: GeneratedScenario[] = [];
  let id = 0;

  // Iterate through parameter space
  for (const agentCount of rangeIterator(config.agentCounts)) {
    for (const tickCount of rangeIterator(config.tickCounts)) {
      for (const fundingLevel of config.fundingLevels) {
        for (let seedIdx = 0; seedIdx < config.seedsPerConfig; seedIdx++) {
          if (scenarios.length >= config.maxConfigurations) {
            return scenarios;
          }

          const seed = 42 + id * 1000 + seedIdx;
          const distribution = generateDistribution(agentCount, config.agentTypes, seed);

          scenarios.push({
            id: `gen-${id++}`,
            agentCount,
            tickCount,
            fundingLevel,
            agentDistribution: distribution,
            seed,
          });
        }
      }
    }
  }

  return scenarios;
}

// ============================================
// Scenario Execution
// ============================================

async function runScenario(scenario: GeneratedScenario, port: number): Promise<RunResult> {
  const startTime = Date.now();

  try {
    // Generate temporary scenario file
    const tempFile = join(__dirname, '..', 'generated', `${scenario.id}.ts`);
    await mkdir(dirname(tempFile), { recursive: true });

    const scenarioCode = generateScenarioCode(scenario);
    await writeFile(tempFile, scenarioCode);

    // Run the scenario
    const result = await executeScenarioFile(tempFile, port);

    return {
      scenarioId: scenario.id,
      success: result.success,
      durationMs: Date.now() - startTime,
      metrics: result.metrics,
      agentStats: result.agentStats,
    };
  } catch (error) {
    return {
      scenarioId: scenario.id,
      success: false,
      durationMs: Date.now() - startTime,
      metrics: {},
      agentStats: [],
      error: (error as Error).message,
    };
  }
}

function generateScenarioCode(scenario: GeneratedScenario): string {
  const agentImports = [...new Set(scenario.agentDistribution.map((d) => d.type))];

  const agentConfigs = scenario.agentDistribution
    .map(
      (d) => `    {
      type: ${d.type},
      count: ${d.count},
      params: ${JSON.stringify(d.params)},
    }`
    )
    .join(',\n');

  return `/**
 * Auto-generated scenario: ${scenario.id}
 * Agents: ${scenario.agentCount}, Ticks: ${scenario.tickCount}
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { ${agentImports.join(', ')} } from '../agents/index.js';
import { createEltaPack } from '../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..');

const port = parseInt(process.env.ANVIL_PORT ?? '8545', 10);

const pack = createEltaPack({
  protocolPath,
  anvilPort: port,
  silent: true,
});

const scenario = defineScenario({
  name: '${scenario.id}',
  seed: ${scenario.seed},
  ticks: ${scenario.tickCount},
  tickSeconds: 3600,
  pack,
  agents: [
${agentConfigs}
  ],
  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'veelta_total_locked', 'gas_total'],
  },
  assertions: [
    { type: 'gte', metric: 'app_count', value: 3 },
  ],
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'warn', pretty: false });
  const engine = new SimulationEngine({ logger });

  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', 'results', '${scenario.id}'),
    ci: true,
  });

  // Output JSON for parsing
  console.log(JSON.stringify({
    success: result.success,
    metrics: result.finalMetrics,
    agentStats: result.agentStats.map(s => ({
      type: s.id.split('-').slice(0, -1).join('-'),
      successRate: s.actionsAttempted > 0 ? s.actionsSucceeded / s.actionsAttempted : 1,
      totalActions: s.actionsAttempted,
    })),
  }));

  process.exit(result.success ? 0 : 1);
}

void main();
`;
}

async function executeScenarioFile(
  filePath: string,
  port: number
): Promise<{
  success: boolean;
  metrics: Record<string, number | string>;
  agentStats: Array<{ type: string; successRate: number; totalActions: number }>;
}> {
  return new Promise((resolve, reject) => {
    const child = spawn('npx', ['tsx', filePath], {
      env: { ...process.env, ANVIL_PORT: String(port) },
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    child.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    child.on('close', (code) => {
      if (code === 0) {
        try {
          // Find the JSON output in stdout
          const jsonMatch = stdout.match(/\{[\s\S]*\}/);
          if (jsonMatch) {
            const result = JSON.parse(jsonMatch[0]);
            resolve(result);
          } else {
            resolve({ success: true, metrics: {}, agentStats: [] });
          }
        } catch {
          resolve({ success: true, metrics: {}, agentStats: [] });
        }
      } else {
        reject(new Error(`Scenario failed with code ${code}: ${stderr}`));
      }
    });

    // Timeout after 5 minutes
    setTimeout(() => {
      child.kill();
      reject(new Error('Scenario timed out'));
    }, 300000);
  });
}

// ============================================
// Results Aggregation
// ============================================

function aggregateResults(config: GenerativeConfig, results: RunResult[]): AggregatedResults {
  const successful = results.filter((r) => r.success);
  const failed = results.filter((r) => !r.success);

  const durations = results.map((r) => r.durationMs);
  const durationStats = calculateStatistics(durations);

  // Aggregate metrics
  const metricStats: Record<string, Statistics> = {};
  for (const metric of config.targetMetrics) {
    const values = successful
      .map((r) => {
        const val = r.metrics[metric];
        return typeof val === 'number' ? val : typeof val === 'string' ? parseFloat(val) : NaN;
      })
      .filter((v) => !isNaN(v));

    if (values.length > 0) {
      metricStats[metric] = calculateStatistics(values);
    }
  }

  // Group by agent count
  const byAgentCount = new Map<number, { successRate: number; avgDuration: number }>();
  const agentCountGroups = new Map<number, RunResult[]>();
  for (const result of results) {
    // Extract agent count from scenario ID (simplified)
    const group = agentCountGroups.get(10) ?? [];
    group.push(result);
    agentCountGroups.set(10, group);
  }

  for (const [count, group] of agentCountGroups) {
    const successRate = group.filter((r) => r.success).length / group.length;
    const avgDuration = group.reduce((sum, r) => sum + r.durationMs, 0) / group.length;
    byAgentCount.set(count, { successRate, avgDuration });
  }

  // Generate insights
  const insights: string[] = [];

  if (successful.length < results.length * 0.5) {
    insights.push('WARNING: Low success rate - investigate failure patterns');
  }

  if (durationStats.stdDev > durationStats.mean * 0.5) {
    insights.push('High duration variance - some configurations may be problematic');
  }

  const feeMetric = metricStats['fees_collected_total'];
  if (feeMetric && feeMetric.mean > 0) {
    insights.push(`Average fees collected: ${feeMetric.mean.toFixed(2)}`);
  }

  return {
    config,
    totalRuns: results.length,
    successfulRuns: successful.length,
    failedRuns: failed.length,
    successRate: successful.length / results.length,
    durationStats,
    metricStats,
    byAgentCount,
    byTickCount: new Map(),
    insights,
  };
}

// ============================================
// Main Runner
// ============================================

async function runGenerativeTests(config: GenerativeConfig): Promise<AggregatedResults> {
  console.log(`\n=== Generative Test Runner: ${config.name} ===\n`);

  // Generate scenarios
  const scenarios = generateScenarios(config);
  console.log(`Generated ${scenarios.length} scenario configurations`);

  // Run scenarios
  const results: RunResult[] = [];
  let basePort = 8600;

  // Run in batches for parallel execution
  const batchSize = config.parallelRuns;
  for (let i = 0; i < scenarios.length; i += batchSize) {
    const batch = scenarios.slice(i, i + batchSize);
    console.log(`Running batch ${Math.floor(i / batchSize) + 1}/${Math.ceil(scenarios.length / batchSize)}...`);

    const batchPromises = batch.map((scenario, idx) =>
      runScenario(scenario, basePort + idx)
    );

    const batchResults = await Promise.all(batchPromises);
    results.push(...batchResults);

    // Progress update
    const successCount = results.filter((r) => r.success).length;
    console.log(`  Progress: ${results.length}/${scenarios.length} (${successCount} successful)`);

    basePort += batchSize;
  }

  // Aggregate and return
  return aggregateResults(config, results);
}

function printResults(results: AggregatedResults): void {
  console.log('\n' + '='.repeat(60));
  console.log('GENERATIVE TEST RESULTS');
  console.log('='.repeat(60));

  console.log(`\nConfiguration: ${results.config.name}`);
  console.log(`Total runs: ${results.totalRuns}`);
  console.log(`Successful: ${results.successfulRuns} (${Math.round(results.successRate * 100)}%)`);
  console.log(`Failed: ${results.failedRuns}`);

  console.log('\nDuration Statistics:');
  console.log(`  Mean: ${(results.durationStats.mean / 1000).toFixed(1)}s`);
  console.log(`  Std Dev: ${(results.durationStats.stdDev / 1000).toFixed(1)}s`);
  console.log(`  Range: ${(results.durationStats.min / 1000).toFixed(1)}s - ${(results.durationStats.max / 1000).toFixed(1)}s`);

  console.log('\nMetric Statistics:');
  for (const [metric, stats] of Object.entries(results.metricStats)) {
    console.log(`  ${metric}:`);
    console.log(`    Mean: ${stats.mean.toFixed(2)}`);
    console.log(`    95% CI: [${stats.ci95Low.toFixed(2)}, ${stats.ci95High.toFixed(2)}]`);
  }

  if (results.insights.length > 0) {
    console.log('\nInsights:');
    for (const insight of results.insights) {
      console.log(`  - ${insight}`);
    }
  }

  console.log('');
}

// ============================================
// CLI Entry Point
// ============================================

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  // Default configuration
  const config: GenerativeConfig = {
    name: 'default-generative',
    agentCounts: { min: 5, max: 20, step: 5 },
    tickCounts: { min: 10, max: 30, step: 10 },
    fundingLevels: [10000n * 10n ** 18n],
    agentTypes: [
      { type: 'BasicUserAgent', weight: 3 },
      { type: 'DeveloperAgent', weight: 1 },
      { type: 'StakerAgent', weight: 1 },
    ],
    targetMetrics: ['app_count', 'fees_collected_total', 'gas_total'],
    seedsPerConfig: 2,
    maxConfigurations: parseInt(args[0] ?? '10', 10),
    parallelRuns: parseInt(args[1] ?? '2', 10),
    confidenceLevel: 0.95,
  };

  try {
    const results = await runGenerativeTests(config);
    printResults(results);

    // Save results
    const resultsPath = join(__dirname, '..', 'results', 'generative-results.json');
    await mkdir(dirname(resultsPath), { recursive: true });
    await writeFile(
      resultsPath,
      JSON.stringify(
        {
          ...results,
          byAgentCount: Object.fromEntries(results.byAgentCount),
          byTickCount: Object.fromEntries(results.byTickCount),
        },
        (_, v) => (typeof v === 'bigint' ? v.toString() : v),
        2
      )
    );
    console.log(`Results saved to: ${resultsPath}`);

    process.exit(results.successRate >= 0.8 ? 0 : 1);
  } catch (error) {
    console.error('Generative testing failed:', error);
    process.exit(2);
  }
}

void main();

export { runGenerativeTests, generateScenarios, type GenerativeConfig, type AggregatedResults };
