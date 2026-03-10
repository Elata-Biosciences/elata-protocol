import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BurstyCreatorAgent,
  OpportunisticAttackerAgent,
  ProbabilisticStakerAgent,
  RegimeNoiseTraderAgent,
} from '../../agents/index.js';
import { anvilPort, scenarioSeed } from '../../lib/runtime-config.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8591),
  silent: true,
});

const scenario = defineScenario({
  name: 'calibration-stochastic-agents',
  seed: scenarioSeed(7102),
  ticks: 10,
  tickSeconds: 1800,
  pack,
  agents: [
    {
      type: BurstyCreatorAgent,
      count: 2,
      params: { burstProbability: 0.2, burstLength: 3, maxApps: 4 },
    },
    { type: RegimeNoiseTraderAgent, count: 3, params: { regimeSwitchProbability: 0.35 } },
    {
      type: ProbabilisticStakerAgent,
      count: 2,
      params: { stateSwitchProbability: 0.3, minLockAmount: BigInt(80e18) },
    },
    {
      type: OpportunisticAttackerAgent,
      count: 2,
      params: { attackWindowProbability: 0.3, attackBudget: BigInt(80e18) },
    },
  ],
  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'veelta_total_locked', 'gas_total', 'elta_total_supply'],
  },
  assertions: [
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
    { type: 'gte', metric: 'app_count', value: 1 },
  ],
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'warn', pretty: false });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'calibration-stochastic-agents'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
