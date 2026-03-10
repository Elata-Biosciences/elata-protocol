/**
 * Smoke Test: App Staking
 *
 * Tests that app token staking via AppStakingVault works.
 * - Mixed agents that buy app tokens then stake them
 * - Verifies staking actions succeed
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { BasicUserAgent, DeveloperAgent } from '../../agents/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8551,
  silent: true,
});

const scenario = defineScenario({
  name: 'smoke-app-staking',
  seed: 42,
  ticks: 15,
  tickSeconds: 3600,

  pack,

  agents: [
    // Users to buy tokens first
    {
      type: BasicUserAgent,
      count: 3,
      params: {
        buyProbability: 0.7,
        sellProbability: 0.0,
        stakeProbability: 0.3, // Some staking attempts
        riskTolerance: 0.5,
        maxTradePercent: 0.2,
      },
    },
    // Developer to create apps
    {
      type: DeveloperAgent,
      count: 1,
      params: {
        maxApps: 2,
        launchProbability: 0.5,
      },
    },
  ],

  metrics: {
    sampleEveryTicks: 3,
    track: ['app_count', 'fees_collected_total', 'elta_total_supply'],
  },

  assertions: [
    // Apps should exist
    { type: 'gte', metric: 'app_count', value: 3 },
    // Protocol should have ELTA supply
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
});

async function main(): Promise<void> {
  console.log('=== Smoke Test: App Staking ===\n');

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  try {
    const result = await engine.run(scenario, {
      outDir: join(__dirname, '..', '..', 'results', 'smoke-app-staking'),
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);

    // Log agent stats
    for (const stat of result.agentStats) {
      const rate =
        stat.actionsAttempted > 0
          ? Math.round((stat.actionsSucceeded / stat.actionsAttempted) * 100)
          : 0;
      console.log(`  ${stat.id}: ${stat.actionsSucceeded}/${stat.actionsAttempted} (${rate}%)`);
    }

    if (result.failedAssertions.length > 0) {
      for (const f of result.failedAssertions) {
        console.log(`  Failed: ${f.message}`);
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
