import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  EpochFeeClaimerAgent,
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
  anvilPort: anvilPort(8586),
  silent: true,
  agentEltaBalance: BigInt(70000e18),
});

const scenario = defineScenario({
  name: 'resilience-congestion-recovery',
  seed: scenarioSeed(6101),
  ticks: 12,
  tickSeconds: 900,
  pack,
  agents: [
    { type: RegimeNoiseTraderAgent, count: 6, params: { maxTrade: BigInt(240e18) } },
    { type: OpportunisticAttackerAgent, count: 2, params: { attackWindowProbability: 0.25 } },
    { type: LiquidityDefenderAgent, count: 2, params: { defenseBudgetPerTick: BigInt(85e18) } },
    { type: EpochFeeClaimerAgent, count: 1, params: { sweepEveryTicks: 2, closeEveryTicks: 6 } },
  ],
  metrics: {
    sampleEveryTicks: 1,
    track: [
      'app_count',
      'fees_collected_total',
      'fees_distributed',
      'gas_total',
      'elta_total_supply',
      'timestamp',
    ],
  },
  assertions: [
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
    { type: 'gte', metric: 'gas_total', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Resilience: Congestion Recovery',
      experimentNotes:
        'High-frequency stochastic activity and attacker bursts create congestion while deterministic keepers/defenders attempt recovery.',
      hypotheses: [
        'Fee pipeline should keep progressing under heavy load.',
        'Gas usage spikes should not collapse system-level fee accumulation.',
      ],
      successCriteria: ['Positive fees and gas accounting.', 'Protocol supply remains stable.'],
      metricFields: ['fees_collected_total', 'fees_distributed', 'gas_total', 'app_count'],
      primaryMetric: 'gas_total',
      mlFeatures: ['tick', 'fees_collected_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'resilience-congestion-recovery'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
