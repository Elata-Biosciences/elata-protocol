/**
 * Smoke Test: Attack Resistance
 *
 * Tests the protocol's resistance to adversarial behavior.
 * - ManipulatorAgent attempts price manipulation
 * - SpammerAgent generates high transaction volumes
 * - BasicUserAgents maintain normal activity
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  DeveloperAgent,
  ManipulatorAgent,
  SpammerAgent,
} from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8563,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-attack-resistance',
  seed: 42,
  ticks: 15,
  tickSeconds: 3600,

  pack,

  agents: [
    // Manipulator trying to exploit the system
    {
      type: ManipulatorAgent,
      count: 2,
      params: {
        aggressiveness: 0.8,
        preferredStrategy: 'pump_dump',
        maxPositionPercent: 0.3,
      },
    },
    // Spammer testing system limits
    {
      type: SpammerAgent,
      count: 2,
      params: {
        spamType: 'micro_trades',
        minTradeSize: BigInt(1e16), // 0.01 ELTA
      },
    },
    // Normal users maintaining healthy activity
    {
      type: BasicUserAgent,
      count: 5,
      params: {
        buyProbability: 0.4,
        sellProbability: 0.2,
      },
    },
    // Developer for app creation
    {
      type: DeveloperAgent,
      count: 1,
      params: {
        maxApps: 3,
        launchProbability: 0.2,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 3,
    track: ['app_count', 'fees_collected_total', 'elta_total_supply'],
  },

  assertions: [
    // System should remain stable under attack
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: Attack Resistance ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-attack-resistance'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);
    console.log(`Apps: ${result.finalMetrics.app_count}`);
    console.log(`Fees collected: ${result.finalMetrics.fees_collected_total}`);

    // Log agent stats
    console.log('\nAgent Stats:');
    for (const stat of result.agentStats) {
      const rate =
        stat.actionsAttempted > 0
          ? Math.round((stat.actionsSucceeded / stat.actionsAttempted) * 100)
          : 0;
      console.log(`  ${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted} (${rate}%)`);
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
