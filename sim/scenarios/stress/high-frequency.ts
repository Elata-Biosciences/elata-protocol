/**
 * Stress Test: High Frequency Trading
 *
 * Tests protocol behavior under 1000+ transactions per tick.
 * Uses 50+ BasicUserAgents for maximum throughput.
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { BasicUserAgent, DeveloperAgent, FeeKeeperAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';
import {
  basicStabilityAssertions,
  printScenarioResults,
  allocatePort,
  formatGas,
} from '../../lib/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: allocatePort(),
  silent: true,
});

const scenario = defineScenario({
  name: 'stress-high-frequency',
  seed: 200,
  ticks: 20,
  tickSeconds: 3600,

  pack,

  agents: [
    // High number of active traders
    {
      type: BasicUserAgent,
      count: 50,
      params: {
        riskTolerance: 0.7,
        maxTradePercent: 0.3,
        tradeProbability: 0.9,
      },
    },
    // Additional traders with different strategies
    {
      type: BasicUserAgent,
      count: 20,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.5,
        tradeProbability: 0.8,
      },
    },
    // Developers to create trading targets
    {
      type: DeveloperAgent,
      count: 5,
      params: {
        maxApps: 5,
        launchProbability: 0.8,
      },
    },
    // Fee keeper to process fees
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
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'gas_total', 'veelta_total_locked'],
  },

  assertions: [
    ...basicStabilityAssertions(),
  ],
});

async function main(): Promise<void> {
  console.log('=== Stress Test: High Frequency Trading ===\n');
  console.log('Testing 1000+ transactions per tick with 50+ agents...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  const startTime = Date.now();

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'stress-high-frequency'),
      ci: true,
    });

    const duration = Date.now() - startTime;

    console.log('\nStress Test Results:');
    console.log('  Duration: ' + (duration / 1000).toFixed(1) + 's');
    console.log('  Total agents: 77');
    console.log('  Gas used: ' + formatGas(result.finalMetrics.gas_total as bigint));

    const totalActions = result.agentStats.reduce((sum, s) => sum + s.actionsAttempted, 0);
    const tps = totalActions / (duration / 1000);
    console.log('  Actions/second: ' + tps.toFixed(1));

    printScenarioResults(result, {
      highlightMetrics: ['fees_collected_total', 'gas_total', 'app_count'],
      groupByType: true,
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Stress test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
