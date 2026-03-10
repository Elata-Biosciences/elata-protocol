import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  CreatorPersonaAgent,
  EconomicPersonaAgent,
  GovernanceStrategistAgent,
  HackerPersonaAgent,
  LlmGossipCoordinatorAgent,
  ProbabilisticStakerAgent,
  RegimeNoiseTraderAgent,
} from '../../agents/index.js';
import {
  anvilPort,
  anvilTimestamp,
  createNotebookReport,
  scenarioCiMode,
  scenarioOutDir,
  scenarioSeed,
} from '../../lib/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8600),
  anvilTimestamp: anvilTimestamp(1_700_008_600),
  silent: true,
});

const llmQueryEndpoints = [
  { name: 'get_world', cost: 1, handler: (_params: Record<string, unknown> | undefined, world: any) => world },
  {
    name: 'get_apps',
    cost: 2,
    handler: (_params: Record<string, unknown> | undefined, world: any) => {
      const appsMap = world?.apps instanceof Map ? world.apps : new Map(Object.entries(world?.apps ?? {}));
      return {
        count: Number(world?.appCount ?? appsMap.size ?? 0),
        apps: [...appsMap.values()].slice(0, 24),
      };
    },
  },
  {
    name: 'get_fee_state',
    cost: 2,
    handler: (_params: Record<string, unknown> | undefined, world: any) => ({
      feesCollectedTotal: String(world?.feesCollectedTotal ?? 0),
      feesDistributed: String(world?.feesDistributed ?? 0),
      treasuryUsdcBalance: String(world?.treasuryUsdcBalance ?? 0),
    }),
  },
  {
    name: 'get_governance_state',
    cost: 2,
    handler: (_params: Record<string, unknown> | undefined, world: any) => ({
      veEltaTotalLocked: String(world?.totalVeEltaLocked ?? world?.veEltaTotalLocked ?? 0),
      activeUsers24h: Number(world?.activeUsers24h ?? 0),
      blockNumber: Number(world?.blockNumber ?? 0),
    }),
  },
];

const scenario = defineScenario({
  name: 'llm-governance-gossip-coordination',
  seed: scenarioSeed(8600),
  ticks: 16,
  tickSeconds: 1800,
  pack,
  agents: [
    { type: GovernanceStrategistAgent, count: 2, params: { targetVeEltaLock: BigInt(180e18) } },
    { type: ProbabilisticStakerAgent, count: 3, params: { stateSwitchProbability: 0.2 } },
    { type: RegimeNoiseTraderAgent, count: 4, params: { regimeSwitchProbability: 0.3 } },
    { type: CreatorPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    { type: EconomicPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    { type: HackerPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    {
      type: LlmGossipCoordinatorAgent,
      count: 2,
      params: {
        provider: 'openai',
        model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
        channelId: 'governance',
        postEveryTicks: 1,
      },
    },
  ],
  exploration: {
    allowArbitraryExecution: true,
    autonomousRpcPolicy: 'aggressive',
    allowlist: {
      allowedContracts: [],
      allowedRpcMethods: ['eth_blockNumber', 'eth_getBlockByNumber', 'eth_chainId'],
    },
  },
  query: {
    defaultBudget: {
      maxQueriesPerTick: 12,
      maxCostPerTick: 50,
      maxBytesPerTick: 24_000,
    },
    endpoints: llmQueryEndpoints,
  },
  gossip: {
    channels: [
      { id: 'global', type: 'global' },
      { id: 'markets', type: 'topic' },
      { id: 'governance', type: 'topic' },
      { id: 'risk', type: 'topic' },
    ],
    budgets: {
      maxPostsPerTick: 2,
      maxPostCostPerTick: 20,
      maxMessagesReadPerTick: 24,
      maxCharsReadPerTick: 6000,
    },
    defaultLatencyTicks: 1,
    dropRate: 0,
    paraphraseRate: 0,
  },
  metrics: {
    sampleEveryTicks: 1,
    track: [
      'app_count',
      'veelta_total_locked',
      'fees_collected_total',
      'fees_distributed',
      'elta_total_supply',
    ],
  },
  assertions: [
    { type: 'gte', metric: 'veelta_total_locked', value: 1 },
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'LLM Gossip: Governance Coordination',
      experimentNotes:
        'Coordinator agents broadcast protocol-state summaries to governance channels. Compare deterministic/replay runs against exploration runs with live providers.',
      hypotheses: [
        'Live LLM exploration should generate diverse governance guidance text.',
        'Deterministic/replay should keep stable, reproducible coordination traces.',
      ],
      successCriteria: [
        'veELTA lock and fees remain positive.',
        'Gossip rows are present and inspectable in Studio.',
      ],
      metricFields: [
        'veelta_total_locked',
        'fees_collected_total',
        'fees_distributed',
        'app_count',
        'elta_total_supply',
      ],
      primaryMetric: 'veelta_total_locked',
      mlFeatures: ['tick', 'app_count', 'fees_collected_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'warn', pretty: false });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: scenarioOutDir(join(__dirname, '..', '..', 'results', 'llm-governance-gossip-coordination')),
    ci: scenarioCiMode(true),
    memoryCapture: {
      enabled: true,
      sampleEveryTicks: 1,
      maxBytesPerRecord: 262_144,
    },
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

void main();
export { scenario };
