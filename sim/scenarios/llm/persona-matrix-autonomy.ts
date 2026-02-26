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
import { anvilPort, createNotebookReport, scenarioSeed } from '../../lib/index.js';
import { createEltaPack } from '../../packs/EltaPack.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: anvilPort(8602),
  silent: true,
});

const scenario = defineScenario({
  name: 'llm-persona-matrix-autonomy',
  seed: scenarioSeed(8602),
  ticks: 14,
  tickSeconds: 1800,
  pack,
  agents: [
    { type: CreatorPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    { type: EconomicPersonaAgent, count: 2, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    { type: BadActorPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    { type: SaboteurPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    { type: HackerPersonaAgent, count: 1, params: { model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini' } },
    {
      type: LlmGossipCoordinatorAgent,
      count: 1,
      params: {
        provider: (process.env.LLM_GOSSIP_PROVIDER as 'openai' | 'openrouter' | undefined) ?? 'openai',
        model: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
        channelId: 'global',
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
  gossip: {
    channels: [
      { id: 'global', type: 'global' },
      { id: 'markets', type: 'topic' },
      { id: 'governance', type: 'topic' },
      { id: 'risk', type: 'topic' },
    ],
    budgets: {
      maxPostsPerTick: 3,
      maxPostCostPerTick: 30,
      maxMessagesReadPerTick: 32,
      maxCharsReadPerTick: 10_000,
    },
    defaultLatencyTicks: 1,
    dropRate: 0,
    paraphraseRate: 0,
  },
  metrics: {
    sampleEveryTicks: 1,
    track: ['app_count', 'fees_collected_total', 'veelta_total_locked', 'elta_total_supply'],
  },
  assertions: [
    { type: 'gte', metric: 'elta_total_supply', value: 1 },
    { type: 'gte', metric: 'app_count', value: 1 },
  ],
  studio: {
    report: createNotebookReport({
      title: 'LLM Persona Matrix: Autonomous Mixed Roles',
      experimentNotes:
        'Runs creator/economic/bad-actor/saboteur/hacker personas together with gossip coordination to validate divergence and autonomous RPC call traces.',
      hypotheses: [
        'Distinct personas should emit different intent tags and action families.',
        'Exploration runs should include autonomous RpcCall traces.',
      ],
      successCriteria: [
        'Scenario remains healthy on base invariants.',
        'Memory artifacts include persona-tagged decision entries.',
      ],
      metricFields: ['app_count', 'fees_collected_total', 'veelta_total_locked', 'elta_total_supply'],
      primaryMetric: 'app_count',
      mlFeatures: ['tick', 'app_count', 'fees_collected_total'],
    }),
  },
});

async function main(): Promise<void> {
  const logger = createLogger({ level: 'warn', pretty: false });
  const engine = new SimulationEngine({ logger });
  const result = await engine.run(scenario, {
    outDir: join(__dirname, '..', '..', 'results', 'llm-persona-matrix-autonomy'),
    ci: true,
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
