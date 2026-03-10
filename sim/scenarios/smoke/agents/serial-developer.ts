/**
 * Agent Isolation Test: Serial Developer Agent
 *
 * Tests the SerialDeveloperAgent's rapid app launch behavior:
 * - Maximum app creation rate
 * - Resource exhaustion handling
 * - Multi-app management
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { SerialDeveloperAgent, BasicUserAgent } from '../../../agents/index.js';
import { createEltaPack } from '../../../packs/EltaPack.js';
import {
  basicStabilityAssertions,
  printScenarioResults,
  allocatePort,
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
  name: 'agent-serial-developer',
  seed: 101,
  ticks: 15,
  tickSeconds: 3600,

  pack,

  agents: [
    // Test subjects: Serial developers with different strategies
    {
      type: SerialDeveloperAgent,
      count: 3,
      params: {
        maxApps: 10, // High limit
        launchProbability: 0.95,
        minLaunchInterval: 0,
      },
    },
    // More conservative serial developers
    {
      type: SerialDeveloperAgent,
      count: 2,
      params: {
        maxApps: 5,
        launchProbability: 0.7,
        minLaunchInterval: 2, // Wait between launches
      },
    },
    // Users to interact with created apps
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'gas_total'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Expect many apps to be created
    { type: 'gte', metric: 'app_count', value: 15 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Agent Isolation Test: Serial Developer ===\n');
  console.log('Testing rapid app launch behavior...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', '..', 'results', 'agent-serial-developer'),
      ci: true,
    });

    // Analyze SerialDeveloperAgent behavior
    const grouped = groupAgentStatsByType(result.agentStats);
    const devStats = grouped.get('SerialDeveloperAgent');

    console.log('\nSerial Developer Analysis:');
    if (devStats) {
      console.log(`  Total agents: ${devStats.count}`);
      console.log(`  Total actions: ${devStats.totalAttempted}`);
      console.log(`  Successful: ${devStats.totalSucceeded}`);
      console.log(`  Success rate: ${Math.round(devStats.avgSuccessRate * 100)}%`);
    }

    console.log(`\nApps created: ${result.finalMetrics.app_count} (including 3 bootstrap)`);

    printScenarioResults(result, {
      showAgentStats: true,
      groupByType: true,
    });

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
