import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  LiquidityDefenderAgent,
  OpportunisticAttackerAgent,
  ProbabilisticStakerAgent,
  ThresholdRebalancerAgent,
  WhaleUserAgent,
} from '../../agents/index.js';
import { anvilPort, scenarioSeed } from '../../lib/runtime-config.js';
import { createNotebookReport } from '../../lib/studio-report.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8587),
  silent: true,
  agentEltaBalance: BigInt(80000e18),
});

const scenario = defineScenario({
  name: 'resilience-liquidity-shock-absorption',
  seed: scenarioSeed(6102),
  ticks: 12,
  tickSeconds: 1800,
  pack,
  agents: [
    {
      type: WhaleUserAgent,
      count: 3,
      params: { minTradeSize: BigInt(2000e18), maxTradeSize: BigInt(9000e18), sellBias: 0.75 },
    },
    { type: OpportunisticAttackerAgent, count: 2, params: { attackWindowProbability: 0.22 } },
    { type: LiquidityDefenderAgent, count: 2, params: { defenseBudgetPerTick: BigInt(120e18) } },
    { type: ThresholdRebalancerAgent, count: 2, params: { buyChunk: BigInt(140e18) } },
    { type: ProbabilisticStakerAgent, count: 3, params: { minLockAmount: BigInt(180e18) } },
  ],
  metrics: {
    sampleEveryTicks: 2,
    track: [
      'app_count',
      'fees_collected_total',
      'veelta_total_locked',
      'elta_total_supply',
      'gas_total',
      'timestamp',
    ],
  },
  assertions: [
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
    { type: 'gte', metric: 'veelta_total_locked', value: 1 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Resilience: Liquidity Shock Absorption',
      experimentNotes:
        'Whale sell pressure and opportunistic attacks are introduced while deterministic defenders and rebalancers attempt to stabilize liquidity.',
      hypotheses: [
        'Defender + rebalancer policies should absorb shock without protocol halt.',
        'veELTA participation should remain positive through stress.',
      ],
      successCriteria: ['Fees remain positive.', 'veELTA lock remains non-zero.'],
      metricFields: ['fees_collected_total', 'veelta_total_locked', 'gas_total', 'app_count'],
      primaryMetric: 'fees_collected_total',
      mlFeatures: ['tick', 'veelta_total_locked', 'gas_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'resilience-liquidity-shock-absorption'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
