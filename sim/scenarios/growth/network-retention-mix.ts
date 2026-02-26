import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BasicUserAgent,
  BurstyCreatorAgent,
  GovernanceStrategistAgent,
  ProbabilisticStakerAgent,
} from '../../agents/index.js';
import { anvilPort, scenarioSeed } from '../../lib/runtime-config.js';
import { createNotebookReport } from '../../lib/studio-report.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8585),
  silent: true,
});

const scenario = defineScenario({
  name: 'growth-network-retention-mix',
  seed: scenarioSeed(5102),
  ticks: 14,
  tickSeconds: 3600,
  pack,
  agents: [
    { type: BurstyCreatorAgent, count: 2, params: { burstProbability: 0.12, maxApps: 6 } },
    { type: GovernanceStrategistAgent, count: 2, params: { targetVeEltaLock: BigInt(320e18) } },
    { type: ProbabilisticStakerAgent, count: 4, params: { stateSwitchProbability: 0.22 } },
    { type: BasicUserAgent, count: 7, params: { buyProbability: 0.34, sellProbability: 0.18 } },
  ],
  metrics: {
    sampleEveryTicks: 2,
    track: [
      'app_count',
      'veelta_total_locked',
      'fees_collected_total',
      'fees_distributed',
      'elta_total_supply',
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
      title: 'Growth: Network and Retention Mix',
      experimentNotes:
        'Combines stochastic staking behavior with governance-focused retention to test whether engagement and lock depth grow alongside app adoption.',
      hypotheses: [
        'Stochastic stakers should still produce persistent veELTA lock growth.',
        'Governance-oriented retention should support sustained fee collection.',
      ],
      successCriteria: ['Non-zero veELTA lock depth.', 'Positive fee collection and app growth.'],
      metricFields: [
        'app_count',
        'veelta_total_locked',
        'fees_collected_total',
        'fees_distributed',
      ],
      primaryMetric: 'veelta_total_locked',
      mlFeatures: ['tick', 'app_count', 'fees_collected_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'growth-network-retention-mix'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
