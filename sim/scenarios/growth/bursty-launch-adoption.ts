import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  BurstyCreatorAgent,
  RegimeNoiseTraderAgent,
  ThresholdRebalancerAgent,
} from '../../agents/index.js';
import { anvilPort, scenarioSeed } from '../../lib/runtime-config.js';
import { createNotebookReport } from '../../lib/studio-report.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8584),
  silent: true,
});

const scenario = defineScenario({
  name: 'growth-bursty-launch-adoption',
  seed: scenarioSeed(5101),
  ticks: 14,
  tickSeconds: 3600,
  pack,
  agents: [
    { type: BurstyCreatorAgent, count: 3, params: { burstProbability: 0.15, burstLength: 4 } },
    { type: BasicUserAgent, count: 8, params: { buyProbability: 0.4, sellProbability: 0.16 } },
    { type: RegimeNoiseTraderAgent, count: 3 },
    { type: ThresholdRebalancerAgent, count: 2 },
  ],
  metrics: {
    sampleEveryTicks: 2,
    track: [
      'app_count',
      'fees_collected_total',
      'elta_total_supply',
      'veelta_total_locked',
      'timestamp',
    ],
  },
  assertions: [
    { type: 'gte', metric: 'app_count', value: 4 },
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Growth: Bursty Launch and Adoption',
      experimentNotes:
        'Models creator launch bursts and measures whether user demand and trading depth absorb app-creation spikes.',
      hypotheses: [
        'Bursty creation should accelerate app_count growth.',
        'Adoption should keep fee generation positive during launch spikes.',
      ],
      successCriteria: ['App count >= 4.', 'Positive fees after burst periods.'],
      metricFields: ['app_count', 'fees_collected_total', 'veelta_total_locked'],
      primaryMetric: 'app_count',
      mlFeatures: ['tick', 'fees_collected_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'growth-bursty-launch-adoption'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
