import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  DeveloperAgent,
  EpochFeeClaimerAgent,
  GovernanceStrategistAgent,
  LiquidityDefenderAgent,
  ThresholdRebalancerAgent,
} from '../../agents/index.js';
import { createNotebookReport } from '../../lib/studio-report.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8588,
  silent: true,
});

const scenario = defineScenario({
  name: 'agents-deterministic-policy-check',
  seed: 7101,
  ticks: 18,
  tickSeconds: 1800,
  pack,
  agents: [
    { type: DeveloperAgent, count: 2, params: { maxApps: 3, launchProbability: 0.2 } },
    { type: EpochFeeClaimerAgent, count: 2, params: { sweepEveryTicks: 3, closeEveryTicks: 6 } },
    { type: ThresholdRebalancerAgent, count: 4, params: { buyChunk: BigInt(80e18) } },
    { type: GovernanceStrategistAgent, count: 3, params: { targetVeEltaLock: BigInt(240e18) } },
    { type: LiquidityDefenderAgent, count: 3, params: { defenseBudgetPerTick: BigInt(65e18) } },
  ],
  metrics: {
    sampleEveryTicks: 1,
    track: [
      'app_count',
      'fees_collected_total',
      'fees_distributed',
      'veelta_total_locked',
      'elta_total_supply',
      'gas_total',
      'timestamp',
    ],
  },
  assertions: [
    { type: 'gte', metric: 'app_count', value: 2 },
    { type: 'gte', metric: 'veelta_total_locked', value: 1 },
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'Agent Calibration: Deterministic Policy Check',
      experimentNotes:
        'This run isolates deterministic policy agents to verify reproducible behavior under a fixed seed.',
      hypotheses: [
        'Deterministic policy agents should produce stable final metrics across repeated runs.',
      ],
      successCriteria: ['Core metrics match across repeated executions with same seed.'],
      metricFields: [
        'app_count',
        'fees_collected_total',
        'fees_distributed',
        'veelta_total_locked',
        'gas_total',
      ],
      primaryMetric: 'fees_collected_total',
      mlFeatures: ['tick', 'gas_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'agents-deterministic-policy-check'),
    ci: true,
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
