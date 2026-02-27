import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import {
  BadActorPersonaAgent,
  CreatorPersonaAgent,
  EconomicPersonaAgent,
  HackerPersonaAgent,
  LlmGossipCoordinatorAgent,
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
  anvilPort: anvilPort(8602),
  anvilTimestamp: anvilTimestamp(1_700_008_602),
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
        apps: [...appsMap.values()].slice(0, 32),
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
      treasuryUsdcRevenue: String(world?.treasuryUsdcRevenue ?? 0),
    }),
  },
  {
    name: 'get_governance_state',
    cost: 2,
    handler: (_params: Record<string, unknown> | undefined, world: any) => ({
      veEltaTotalLocked: String(world?.totalVeEltaLocked ?? world?.veEltaTotalLocked ?? 0),
      activeUsers24h: Number(world?.activeUsers24h ?? 0),
      blockNumber: Number(world?.blockNumber ?? 0),
      timestamp: Number(world?.timestamp ?? 0),
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

const creatorEconomicPostingPolicy = {
  preferredChannels: ['global', 'governance', 'risk'],
  onlyPostOnMaterialChange: false,
  postOnMaterialChange: false,
  postOnInboxThreshold: 1,
  minPostEveryTicks: 2,
  maxPostChars: 240,
};

const adversarialPostingPolicy = {
  preferredChannels: ['global', 'risk'],
  onlyPostOnMaterialChange: false,
  postOnMaterialChange: false,
  postOnInboxThreshold: 2,
  minPostEveryTicks: 4,
  maxPostChars: 240,
};

const scenario = defineScenario({
  name: 'llm-persona-matrix',
  seed: scenarioSeed(8602),
  ticks: 18,
  tickSeconds: 1800,
  pack,
  agents: [
    {
      type: CreatorPersonaAgent,
      count: 2,
      params: {
        model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
        postingPolicy: creatorEconomicPostingPolicy,
      },
    },
    {
      type: EconomicPersonaAgent,
      count: 3,
      params: {
        model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
        postingPolicy: creatorEconomicPostingPolicy,
      },
    },
    {
      type: BadActorPersonaAgent,
      count: 2,
      params: {
        model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
        postingPolicy: adversarialPostingPolicy,
      },
    },
    {
      type: SaboteurPersonaAgent,
      count: 2,
      params: {
        model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
        postingPolicy: adversarialPostingPolicy,
      },
    },
    {
      type: HackerPersonaAgent,
      count: 2,
      params: {
        model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
        postingPolicy: adversarialPostingPolicy,
      },
    },
    {
      type: LlmGossipCoordinatorAgent,
      count: 2,
      params: {
        provider: (process.env.LLM_GOSSIP_PROVIDER as 'openai' | 'openrouter' | undefined) ?? 'openai',
        model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
        channelId: 'global',
        postEveryTicks: 2,
      },
    },
  ],
  exploration: {
    allowArbitraryExecution: true,
    autonomousRpcPolicy: 'aggressive',
    disableAutonomousRpc: false,
    allowlist: {
      allowedContracts: [],
      allowedRpcMethods: [],
    },
  },
  query: {
    defaultBudget: {
      maxQueriesPerTick: 12,
      maxCostPerTick: 60,
      maxBytesPerTick: 28_000,
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
      maxPostsPerTick: 10,
      maxPostCostPerTick: 55,
      maxMessagesReadPerTick: 30,
      maxCharsReadPerTick: 8000,
    },
    defaultLatencyTicks: 1,
    dropRate: 0,
    paraphraseRate: 0,
  },
  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'fees_distributed', 'gas_total', 'elta_total_supply'],
  },
  assertions: [
    { type: 'gte', metric: 'app_count', value: 3 },
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'LLM Persona Matrix',
      experimentNotes:
        'Runs heterogeneous persona agents in one world to validate divergence in actions, rationale, and RPC probe behavior.',
      hypotheses: [
        'Creator personas should bias toward app creation.',
        'Economic personas should bias toward buy/sell rebalancing.',
        'Bad-actor/saboteur/hacker personas should produce more adversarial and RPC-heavy traces.',
      ],
      successCriteria: [
        'Distinct persona reason codes appear in memory traces.',
        'RPC calls are present during exploration runs.',
      ],
      metricFields: ['app_count', 'fees_collected_total', 'fees_distributed', 'gas_total', 'elta_total_supply'],
      primaryMetric: 'fees_collected_total',
      mlFeatures: ['tick', 'app_count', 'gas_total', 'fees_collected_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'warn', pretty: false });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: scenarioOutDir(join(__dirname, '..', '..', 'results', 'llm-persona-matrix')),
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
