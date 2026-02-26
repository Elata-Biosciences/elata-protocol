import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  BurstyCreatorAgent,
  LiquidityDefenderAgent,
  ThresholdRebalancerAgent,
} from '../../agents/index.js';
import { anvilPort, scenarioSeed } from '../../lib/runtime-config.js';
import { createNotebookReport } from '../../lib/studio-report.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8583),
  silent: true,
});

const scenario = defineScenario({
  name: 'economic-rebalancing-liquidity',
  seed: scenarioSeed(4102),
  ticks: 12,
  tickSeconds: 3600,
  pack,
  agents: [
    {
      type: BurstyCreatorAgent,
      count: 3,
      params: { burstProbability: 0.08, burstLength: 2, maxApps: 4, baseLaunchProbability: 0.03 },
    },
    { type: BasicUserAgent, count: 7, params: { buyProbability: 0.32, sellProbability: 0.22 } },
    { type: ThresholdRebalancerAgent, count: 3, params: { buyChunk: BigInt(100e18) } },
    { type: LiquidityDefenderAgent, count: 2, params: { defenseBudgetPerTick: BigInt(70e18) } },
  ],
  metrics: {
    sampleEveryTicks: 2,
    track: [
      'app_count',
      'veelta_total_locked',
      'fees_collected_total',
      'elta_total_supply',
      'gas_total',
      'timestamp',
    ],
  },
  assertions: [
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'veelta_total_locked', value: 1 },
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Economic Rebalancing and Liquidity Defense',
      experimentNotes:
        'Compares deterministic threshold-based rebalancing with deterministic liquidity defense under mixed user flow.',
      hypotheses: [
        'Rebalancing reduces inventory concentration risk.',
        'Liquidity defense preserves fee throughput during sell pressure.',
      ],
      successCriteria: ['Positive fee accumulation.', 'Non-zero veELTA lock participation.'],
      metricFields: ['fees_collected_total', 'veelta_total_locked', 'app_count', 'gas_total'],
      primaryMetric: 'fees_collected_total',
      mlFeatures: ['tick', 'veelta_total_locked'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'economic-rebalancing-liquidity'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
