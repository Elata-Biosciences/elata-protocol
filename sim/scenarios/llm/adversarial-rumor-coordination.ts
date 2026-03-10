import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BadActorPersonaAgent,
  EconomicPersonaAgent,
  HackerPersonaAgent,
  LiquidityDefenderAgent,
  LlmGossipCoordinatorAgent,
  OpportunisticAttackerAgent,
  RegimeNoiseTraderAgent,
  SaboteurPersonaAgent,
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
  anvilPort: anvilPort(8601),
  anvilTimestamp: anvilTimestamp(1_700_008_601),
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
  {
    name: 'get_agent_position',
    cost: 2,
    handler: (params: Record<string, unknown> | undefined, world: any) => {
      const agentId = String(params?.agentId ?? '');
      const positions = world?.agentPositions ?? {};
      return {
        agentId,
        position: agentId ? positions?.[agentId] ?? null : null,
      };
    },
  },
];

const scenario = defineScenario({
  name: 'llm-adversarial-rumor-coordination',
  seed: scenarioSeed(8601),
  ticks: 16,
  tickSeconds: 1800,
  pack,
  agents: [
    { type: RegimeNoiseTraderAgent, count: 4, params: { regimeSwitchProbability: 0.35 } },
    { type: OpportunisticAttackerAgent, count: 3, params: { attackWindowProbability: 0.25 } },
    { type: LiquidityDefenderAgent, count: 2, params: { defendThresholdBps: 600 } },
    { type: BadActorPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    { type: SaboteurPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    { type: HackerPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    { type: EconomicPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    {
      type: LlmGossipCoordinatorAgent,
      count: 2,
      params: {
        provider: (process.env.LLM_GOSSIP_PROVIDER as 'openai' | 'openrouter' | undefined) ?? 'openai',
        model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
        channelId: 'risk',
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
    track: ['fees_collected_total', 'gas_total', 'app_count', 'elta_total_supply'],
  },
  assertions: [
    { type: 'gte', metric: 'fees_collected_total', value: 1 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'LLM Gossip: Adversarial Rumor Coordination',
      experimentNotes:
        'Stress-tests whether attacker/defender dynamics remain observable when LLM-based coordinators emit potentially noisy risk narratives over gossip.',
      hypotheses: [
        'Exploration runs should create message diversity and richer gossip traces.',
        'Protocol should maintain positive fees and supply despite rumor noise.',
      ],
      successCriteria: [
        'Scenario passes core invariants.',
        'Gossip and inspector history are available for post-run review.',
      ],
      metricFields: ['fees_collected_total', 'gas_total', 'app_count', 'elta_total_supply'],
      primaryMetric: 'fees_collected_total',
      mlFeatures: ['tick', 'gas_total', 'fees_collected_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'warn', pretty: false });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: scenarioOutDir(join(__dirname, '..', '..', 'results', 'llm-adversarial-rumor-coordination')),
    ci: scenarioCiMode(true),
    memoryCapture: {
      enabled: true,
      sampleEveryTicks: 1,
      maxBytesPerRecord: 262_144,
    },
  });
  process.exit(result.failedAssertions.length > 0 ? 1 : 0);
}

const isDirectExecution =
  process.argv[1] !== undefined && fileURLToPath(import.meta.url) === process.argv[1];
if (isDirectExecution) {
  void main();
}
export { scenario };
