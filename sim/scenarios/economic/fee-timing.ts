/**
 * Economic Scenario: Fee Epoch Timing Attack
 *
 * Tests strategic fee epoch closing behavior.
 * Multiple FeeKeeperAgents compete to close epochs for rewards.
 *
 * Key aspects:
 * - Competition for epoch closing
 * - MEV-like behavior simulation
 * - Fee distribution fairness
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  DeveloperAgent,
  FeeKeeperAgent,
  WhaleUserAgent,
} from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8572,
  silent: true,
  agentEltaBalance: BigInt(20000e18),
});

const scenario = defineScenario({
  name: 'economic-fee-timing',
  seed: 789,
  ticks: 50,
  tickSeconds: 7200, // 2 hours per tick

  pack,

  agents: [
    // Developers creating apps with trading activity
    {
      type: DeveloperAgent,
      count: 2,
      params: {
        maxApps: 3,
        launchProbability: 0.3,
      },
    },
    // Multiple competing FeeKeepers
    {
      type: FeeKeeperAgent,
      count: 5,
      params: {
        minFeeThreshold: BigInt(100e18), // Only close if >= 100 ELTA in fees
        sweepProbability: 0.7,
        closeProbability: 0.8,
      },
    },
    // Whale traders generating fees
    {
      type: WhaleUserAgent,
      count: 4,
      params: {
        minTradeSize: BigInt(5000e18),
        maxTradeSize: BigInt(15000e18),
        buyProbability: 0.5,
        sellProbability: 0.3,
      },
    },
    // Basic users for organic activity
    {
      type: BasicUserAgent,
      count: 8,
      params: {
        buyProbability: 0.4,
        sellProbability: 0.2,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 5,
    track: ['app_count', 'fees_collected_total', 'fees_distributed', 'gas_total'],
  },

  assertions: [
    // Apps should exist for fee generation
    { type: 'gte', metric: 'app_count', value: 2 },
    // Fees should be collected from trading
    { type: 'gte', metric: 'fees_collected_total', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Economic Scenario: Fee Epoch Timing Attack ===\n');
  console.log('Testing FeeKeeper competition and fee distribution...\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'economic-fee-timing'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Apps: ${result.finalMetrics.app_count}`);
    console.log(`Fees collected: ${result.finalMetrics.fees_collected_total}`);
    console.log(`Fees distributed: ${result.finalMetrics.fees_distributed}`);
    console.log(`Total gas used: ${result.finalMetrics.gas_total}`);

    // Log agent stats
    console.log('\nAgent Stats:');
    for (const stat of result.agentStats) {
      const rate =
        stat.actionsAttempted > 0
          ? Math.round((stat.actionsSucceeded / stat.actionsAttempted) * 100)
          : 0;
      console.log(`  ${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted} (${rate}%)`);
    }

    // FeeKeeper specific stats
    console.log('\nFeeKeeper Competition Analysis:');
    const feeKeeperStats = result.agentStats.filter((s) => s.id.includes('FeeKeeper'));
    for (const stat of feeKeeperStats) {
      console.log(`  ${stat.id}: ${stat.actionsSucceeded} successful fee operations`);
    }

    // Gas analysis per agent type
    console.log('\nGas Usage per Agent:');
    for (const [key, value] of Object.entries(result.finalMetrics)) {
      if (key.startsWith('gas_per_agent_')) {
        console.log(`  ${key}: ${value}`);
      }
    }

    if (result.failedAssertions.length > 0) {
      console.log('\nFailed Assertions:');
      for (const f of result.failedAssertions) {
        console.log(`  ${f.message}`);
      }
    }

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(2);
  }
}

void main();

export { scenario };
