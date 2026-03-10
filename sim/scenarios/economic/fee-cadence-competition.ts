import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  BurstyCreatorAgent,
  EpochFeeClaimerAgent,
  RegimeNoiseTraderAgent,
} from '../../agents/index.js';
import { anvilPort, scenarioSeed } from '../../lib/runtime-config.js';
import { createNotebookReport } from '../../lib/studio-report.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8582),
  silent: true,
});

const scenario = defineScenario({
  name: 'economic-fee-cadence-competition',
  seed: scenarioSeed(4101),
  ticks: 12,
  tickSeconds: 1800,
  pack,
  agents: [
    {
      type: BurstyCreatorAgent,
      count: 2,
      params: { burstProbability: 0.1, burstLength: 2, maxApps: 3, baseLaunchProbability: 0.04 },
    },
    { type: BasicUserAgent, count: 6, params: { buyProbability: 0.4, sellProbability: 0.2 } },
    { type: RegimeNoiseTraderAgent, count: 3, params: { regimeSwitchProbability: 0.2 } },
    { type: EpochFeeClaimerAgent, count: 1, params: { sweepEveryTicks: 3, closeEveryTicks: 7 } },
  ],
  metrics: {
    sampleEveryTicks: 2,
    track: ['app_count', 'fees_collected_total', 'fees_distributed', 'gas_total', 'timestamp'],
  },
  assertions: [
    { type: 'gte', metric: 'app_count', value: 2 },
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
    { type: 'gte', metric: 'fees_distributed', value: 0 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Economic Fee Cadence Competition',
      experimentNotes:
        'Tests how deterministic fee-claimer cadence interacts with stochastic trading intensity and app growth.',
      hypotheses: [
        'Faster fee cadence should keep distribution pipeline active.',
        'Higher trade churn should increase fee collection despite volatility.',
      ],
      successCriteria: ['Positive fee collection.', 'At least two active apps.'],
      metricFields: ['fees_collected_total', 'fees_distributed', 'app_count', 'gas_total'],
      primaryMetric: 'fees_collected_total',
      mlFeatures: ['tick', 'gas_total', 'app_count'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'economic-fee-cadence-competition'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
