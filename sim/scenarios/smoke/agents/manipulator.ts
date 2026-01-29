/**
 * Agent Isolation Test: Manipulator Agent
 *
 * Tests the ManipulatorAgent's manipulation strategies:
 * - Pump and dump patterns
 * - Wash trading detection
 * - Front-running simulation
 * - Price manipulation resistance
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { ManipulatorAgent, DeveloperAgent, BasicUserAgent, CautiousUserAgent } from '../../../agents/index.js';
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
  name: 'agent-manipulator',
  seed: 103,
  ticks: 20,
  tickSeconds: 3600,

  pack,

  agents: [
    // Test subjects: Various manipulation strategies
    {
      type: ManipulatorAgent,
      count: 2,
      params: {
        strategy: 'pump_and_dump',
        aggressiveness: 0.8,
        targetPriceMultiplier: 2.0,
      },
    },
    {
      type: ManipulatorAgent,
      count: 2,
      params: {
        strategy: 'wash_trading',
        aggressiveness: 0.6,
        washTradeSize: 1000n * 10n ** 18n,
      },
    },
    {
      type: ManipulatorAgent,
      count: 1,
      params: {
        strategy: 'front_running',
        aggressiveness: 0.9,
      },
    },
    // Developers to create targets
    {
      type: DeveloperAgent,
      count: 2,
      params: {
        maxApps: 3,
        launchProbability: 0.8,
      },
    },
    // Regular users (potential victims)
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
    // Cautious users who should avoid manipulation
    {
      type: CautiousUserAgent,
      count: 3,
      params: {
        riskTolerance: 0.2,
        maxTradePercent: 0.05,
        sellThreshold: 0.1,
        stopLossThreshold: 0.05,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'gas_total'],
  },

  assertions: [
    ...basicStabilityAssertions(),
    // Protocol should remain stable under manipulation attempts
  ],
});

async function main(): Promise<void> {
  console.log('=== Agent Isolation Test: Manipulator ===\n');
  console.log('Testing all manipulation strategies...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', '..', 'results', 'agent-manipulator'),
      ci: true,
    });

    // Analyze ManipulatorAgent behavior
    const grouped = groupAgentStatsByType(result.agentStats);
    const manipStats = grouped.get('ManipulatorAgent');

    console.log('\nManipulator Analysis:');
    if (manipStats) {
      console.log(`  Total agents: ${manipStats.count}`);
      console.log(`  Total manipulation attempts: ${manipStats.totalAttempted}`);
      console.log(`  Successful: ${manipStats.totalSucceeded}`);
      console.log(`  Failed: ${manipStats.totalFailed}`);
      console.log(`  Success rate: ${Math.round(manipStats.avgSuccessRate * 100)}%`);
    }

    // Check impact on regular users
    const basicStats = grouped.get('BasicUserAgent');
    const cautiousStats = grouped.get('CautiousUserAgent');

    console.log('\nImpact on Regular Users:');
    if (basicStats) {
      console.log(`  BasicUser success rate: ${Math.round(basicStats.avgSuccessRate * 100)}%`);
    }
    if (cautiousStats) {
      console.log(`  CautiousUser success rate: ${Math.round(cautiousStats.avgSuccessRate * 100)}%`);
    }

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
