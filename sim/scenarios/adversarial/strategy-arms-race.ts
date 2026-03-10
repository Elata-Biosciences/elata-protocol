import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  BurstyCreatorAgent,
  LiquidityDefenderAgent,
  OpportunisticAttackerAgent,
  RegimeNoiseTraderAgent,
} from '../../agents/index.js';
import { anvilPort, scenarioSeed } from '../../lib/runtime-config.js';
import { createNotebookReport } from '../../lib/studio-report.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8580),
  silent: true,
});

const scenario = defineScenario({
  name: 'adversarial-strategy-arms-race',
  seed: scenarioSeed(3101),
  ticks: 12,
  tickSeconds: 1800,
  pack,
  agents: [
    {
      type: BurstyCreatorAgent,
      count: 2,
      params: { burstProbability: 0.08, burstLength: 2, maxApps: 3, baseLaunchProbability: 0.03 },
    },
    { type: BasicUserAgent, count: 5, params: { buyProbability: 0.35, sellProbability: 0.2 } },
    { type: RegimeNoiseTraderAgent, count: 3, params: { regimeSwitchProbability: 0.22 } },
    { type: OpportunisticAttackerAgent, count: 2, params: { attackWindowProbability: 0.24 } },
    { type: LiquidityDefenderAgent, count: 1, params: { defenseBudgetPerTick: BigInt(80e18) } },
  ],
  metrics: {
    sampleEveryTicks: 2,
    track: [
      'app_count',
      'elta_total_supply',
      'fees_collected_total',
      'veelta_total_locked',
      'gas_total',
      'timestamp',
      'block_number',
    ],
  },
  assertions: [
    { type: 'gte', metric: 'app_count', value: 2 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Adversarial Strategy Arms Race',
      experimentNotes:
        'This run pits opportunistic attackers against deterministic liquidity defenders while regular users and developers continue normal protocol activity.',
      hypotheses: [
        'Attack pressure increases volatility but should not halt app creation.',
        'Defender liquidity injections should keep fee generation positive.',
      ],
      successCriteria: [
        'At least 2 apps remain active.',
        'Fees remain positive under attack pressure.',
      ],
      metricFields: ['app_count', 'fees_collected_total', 'veelta_total_locked', 'gas_total'],
      primaryMetric: 'fees_collected_total',
      mlFeatures: ['tick', 'app_count', 'gas_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'adversarial-strategy-arms-race'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
