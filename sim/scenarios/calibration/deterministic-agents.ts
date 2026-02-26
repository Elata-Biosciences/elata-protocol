import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  DeveloperAgent,
  EpochFeeClaimerAgent,
  GovernanceStrategistAgent,
  ThresholdRebalancerAgent,
} from '../../agents/index.js';
import { anvilPort, scenarioSeed } from '../../lib/runtime-config.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8590),
  silent: true,
});

const scenario = defineScenario({
  name: 'calibration-deterministic-agents',
  seed: scenarioSeed(7101),
  ticks: 8,
  tickSeconds: 3600,
  pack,
  agents: [
    {
      type: DeveloperAgent,
      count: 1,
      params: { maxApps: 2, launchProbability: 0.5, launchCooldown: 1 },
    },
    { type: EpochFeeClaimerAgent, count: 1, params: { sweepEveryTicks: 2, closeEveryTicks: 4 } },
    { type: GovernanceStrategistAgent, count: 1, params: { targetVeEltaLock: BigInt(140e18) } },
    { type: ThresholdRebalancerAgent, count: 1, params: { buyChunk: BigInt(60e18) } },
  ],
  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'veelta_total_locked', 'elta_total_supply'],
  },
  assertions: [{ type: 'gte', metric: 'elta_total_supply', value: 1 }],
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'warn', pretty: false });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'calibration-deterministic-agents'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
