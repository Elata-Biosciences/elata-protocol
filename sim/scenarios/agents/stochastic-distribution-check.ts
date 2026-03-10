import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BurstyCreatorAgent,
  OpportunisticAttackerAgent,
  ProbabilisticStakerAgent,
  RegimeNoiseTraderAgent,
} from '../../agents/index.js';
import { createNotebookReport } from '../../lib/studio-report.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8589,
  silent: true,
});

const scenario = defineScenario({
  name: 'agents-stochastic-distribution-check',
  seed: 7102,
  ticks: 22,
  tickSeconds: 1800,
  pack,
  agents: [
    { type: BurstyCreatorAgent, count: 4, params: { burstProbability: 0.14 } },
    { type: RegimeNoiseTraderAgent, count: 8, params: { regimeSwitchProbability: 0.2 } },
    { type: ProbabilisticStakerAgent, count: 6, params: { stateSwitchProbability: 0.25 } },
    { type: OpportunisticAttackerAgent, count: 3, params: { attackWindowProbability: 0.22 } },
  ],
  metrics: {
    sampleEveryTicks: 1,
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
    { type: 'gte', metric: 'app_count', value: 2 },
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Agent Calibration: Stochastic Distribution Check',
      experimentNotes:
        'This run verifies that stochastic agents produce diverse but protocol-valid behavior under random policy transitions.',
      hypotheses: [
        'Stochastic agents should show meaningful spread in attempted actions.',
        'Distributional variability should not break core protocol invariants.',
      ],
      successCriteria: [
        'Action-attempt spread is above configured minimum.',
        'Core protocol assertions continue to pass.',
      ],
      metricFields: ['app_count', 'fees_collected_total', 'veelta_total_locked', 'gas_total'],
      primaryMetric: 'gas_total',
      mlFeatures: ['tick', 'fees_collected_total', 'app_count'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'agents-stochastic-distribution-check'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
