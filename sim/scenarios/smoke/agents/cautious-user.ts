/**
 * Agent Isolation Test: Cautious User Agent
 *
 * Tests the CautiousUserAgent's risk aversion behaviors:
 * - Sell thresholds
 * - Loss avoidance
 * - Conservative position sizing
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { CautiousUserAgent, DeveloperAgent, WhaleUserAgent } from '../../../agents/index.js';
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
  name: 'agent-cautious-user',
  seed: 100,
  ticks: 20,
  tickSeconds: 3600,

  pack,

  agents: [
    // Main test subjects: Cautious users with varying risk tolerances
    {
      type: CautiousUserAgent,
      count: 5,
      params: {
        riskTolerance: 0.2,
        maxTradePercent: 0.05,
        sellThreshold: 0.1,
        stopLossThreshold: 0.05,
      },
    },
    // Additional cautious users with different params
    {
      type: CautiousUserAgent,
      count: 3,
      params: {
        riskTolerance: 0.1,
        maxTradePercent: 0.02,
        sellThreshold: 0.05,
        stopLossThreshold: 0.02,
      },
    },
    // Developers to create apps
    {
      type: DeveloperAgent,
      count: 2,
      params: {
        maxApps: 3,
        launchProbability: 0.7,
      },
    },
    // Whales to create price movements
    {
      type: WhaleUserAgent,
      count: 2,
      params: {
        riskTolerance: 0.9,
        maxTradePercent: 0.3,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'gas_total'],
  },

  assertions: basicStabilityAssertions(),
});

async function main(): Promise<void> {
  console.log('=== Agent Isolation Test: Cautious User ===\n');
  console.log('Testing sell thresholds and risk aversion...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', '..', 'results', 'agent-cautious-user'),
      ci: true,
    });

    const grouped = groupAgentStatsByType(result.agentStats);
    const cautiousStats = grouped.get('CautiousUserAgent');

    console.log('\nCautious User Analysis:');
    if (cautiousStats) {
      console.log('  Total agents: ' + cautiousStats.count);
      console.log('  Actions attempted: ' + cautiousStats.totalAttempted);
      console.log('  Success rate: ' + Math.round(cautiousStats.avgSuccessRate * 100) + '%');
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
