import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  GovernanceStrategistAgent,
  OpportunisticAttackerAgent,
  ProbabilisticStakerAgent,
  RegimeNoiseTraderAgent,
} from '../../agents/index.js';
import { anvilPort, scenarioSeed } from '../../lib/runtime-config.js';
import { createNotebookReport } from '../../lib/studio-report.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8581),
  silent: true,
});

const scenario = defineScenario({
  name: 'adversarial-governance-pressure',
  seed: scenarioSeed(3102),
  ticks: 12,
  tickSeconds: 3600,
  pack,
  agents: [
    { type: GovernanceStrategistAgent, count: 3, params: { targetVeEltaLock: BigInt(450e18) } },
    { type: ProbabilisticStakerAgent, count: 4, params: { stateSwitchProbability: 0.18 } },
    { type: RegimeNoiseTraderAgent, count: 4, params: { regimeSwitchProbability: 0.2 } },
    { type: OpportunisticAttackerAgent, count: 1, params: { attackWindowProbability: 0.15 } },
  ],
  metrics: {
    sampleEveryTicks: 2,
    track: [
      'veelta_total_locked',
      'fees_collected_total',
      'elta_total_supply',
      'app_count',
      'gas_total',
      'timestamp',
    ],
  },
  assertions: [
    { type: 'gte', metric: 'veelta_total_locked', value: 1 },
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Adversarial Governance Pressure',
      experimentNotes:
        'Governance-focused deterministic actors and stochastic stakers are exposed to opportunistic attack windows to test voting-power resilience.',
      hypotheses: [
        'veELTA lock participation should remain non-zero under pressure.',
        'Fee throughput should stay positive even with governance-focused behavior.',
      ],
      successCriteria: ['veELTA remains locked.', 'Protocol continues fee collection.'],
      metricFields: ['veelta_total_locked', 'fees_collected_total', 'app_count', 'gas_total'],
      primaryMetric: 'veelta_total_locked',
      mlFeatures: ['tick', 'app_count'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'adversarial-governance-pressure'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
