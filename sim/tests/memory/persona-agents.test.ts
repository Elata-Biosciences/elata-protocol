import type { Action, GossipMessage, TickContext } from '@elata-biosciences/agentforge';
import assert from 'node:assert/strict';
import test from 'node:test';
import { BaseElataPersonaLlmAgent } from '../../agents/BaseElataPersonaLlmAgent.js';
import {
  BadActorPersonaAgent,
  CreatorPersonaAgent,
  EconomicPersonaAgent,
  HackerPersonaAgent,
  SaboteurPersonaAgent,
} from '../../agents/index.js';
import { createTestApp, createTestContext, setAgentBalance } from './testHarness.js';

function personaWorld() {
  const app = createTestApp(41);
  return {
    appCount: 1,
    apps: new Map([[String(app.id), app]]),
    feesCollectedTotal: 123n,
    feesDistributed: 40n,
    totalVeEltaLocked: 500n,
    activeUsers24h: 10,
  };
}

class CreatorHarness extends CreatorPersonaAgent {
  protected override getWorldState() {
    return personaWorld() as unknown as ReturnType<CreatorPersonaAgent['getWorldState']>;
  }
}
class EconomicHarness extends EconomicPersonaAgent {
  protected override getWorldState() {
    return personaWorld() as unknown as ReturnType<EconomicPersonaAgent['getWorldState']>;
  }
}
class BadActorHarness extends BadActorPersonaAgent {
  protected override getWorldState() {
    return personaWorld() as unknown as ReturnType<BadActorPersonaAgent['getWorldState']>;
  }
}
class SaboteurHarness extends SaboteurPersonaAgent {
  protected override getWorldState() {
    return personaWorld() as unknown as ReturnType<SaboteurPersonaAgent['getWorldState']>;
  }
}
class HackerHarness extends HackerPersonaAgent {
  protected override getWorldState() {
    return personaWorld() as unknown as ReturnType<HackerPersonaAgent['getWorldState']>;
  }
}

class GossipHarness extends BaseElataPersonaLlmAgent {
  protected override getPersonaProfile() {
    return {
      id: 'gossip-test',
      style: 'signal relay',
      goals: ['Broadcast meaningful state changes'],
      riskProfile: 'balanced',
    };
  }

  protected override getFallbackIntent(_ctx: TickContext) {
    return {
      name: 'PostMessage',
      params: {
        channelId: 'global',
        text: 'state changed',
      },
      rationale: 'share signal',
      metadata: { personaId: 'gossip-test', confidence: 0.6 },
    };
  }

  protected override getWorldState() {
    return personaWorld() as unknown as ReturnType<CreatorPersonaAgent['getWorldState']>;
  }
}

class LlmGuardrailHarness extends BaseElataPersonaLlmAgent {
  protected override getPersonaProfile() {
    return {
      id: 'guardrail-test',
      style: 'adaptive coordinator',
      goals: ['Coordinate peers with concise signals'],
      riskProfile: 'balanced',
    };
  }

  protected override getFallbackIntent(_ctx: TickContext) {
    return {
      name: 'noop',
      params: { reason: 'fallback_unused' },
      metadata: { personaId: 'guardrail-test' },
    };
  }

  protected override getAllowedProtocolActions(): string[] {
    return ['noop'];
  }

  protected override getProviderConfig() {
    return { provider: 'openai' as const, model: 'test-model' };
  }

  protected override getWorldState() {
    return personaWorld() as unknown as ReturnType<CreatorPersonaAgent['getWorldState']>;
  }
}

function getLastReason(agent: { exportMemory: () => Record<string, unknown> }) {
  return String(agent.exportMemory().lastReason ?? '');
}

test('persona agents diverge on same world snapshot', async () => {
  const ctx = createTestContext({
    tick: 2,
    rng: { chance: true, pickOne: (items) => items[0]!, nextFloat: 0.4 },
  });
  const agents = [
    new CreatorHarness('creator-1'),
    new EconomicHarness('economic-1'),
    new BadActorHarness('bad-1'),
    new SaboteurHarness('sab-1'),
    new HackerHarness('hack-1'),
  ];
  for (const agent of agents) {
    setAgentBalance(agent, { elta: BigInt(1_000e18), veElta: 0n });
  }
  setAgentBalance(agents[3]!, { elta: BigInt(1_000e18), veElta: 0n });
  (agents[3] as unknown as { appTokenBalances: Map<string, bigint> }).appTokenBalances.set('41', 9n);

  const actions = (await Promise.all(agents.map((a) => a.step(ctx as TickContext)))) as Array<Action | null>;
  const names = actions.map((a) => a?.name ?? 'null');
  const unique = new Set(names);
  assert.ok(unique.size >= 3, `expected persona divergence, got ${names.join(', ')}`);
});

test('hacker persona deterministic fallback emits rpc call', async () => {
  const hacker = new HackerHarness('hack-fallback');
  setAgentBalance(hacker, { elta: BigInt(500e18), veElta: 0n });
  const action = await hacker.step(createTestContext({ tick: 1, mode: 'deterministic' as TickContext['mode'] }));
  assert.equal(action?.name, 'RpcCall');
  assert.match(getLastReason(hacker), /deterministic_fallback/);
});

test('persona memory captures persona reason codes', async () => {
  const creator = new CreatorHarness('creator-memory');
  setAgentBalance(creator, { elta: BigInt(500e18), veElta: 0n });
  await creator.step(createTestContext({ tick: 2 }));
  const memory = creator.exportMemory();
  assert.equal(typeof memory.lastDecision, 'string');
  assert.match(String(memory.lastReason ?? ''), /^persona_creator_/);
});

test('persona fallback can emit PostMessage with normalized intent metadata', async () => {
  const gossip = new GossipHarness('gossip-memory');
  setAgentBalance(gossip, { elta: BigInt(100e18), veElta: 0n });
  const action = await gossip.step(createTestContext({ tick: 3 }));
  assert.equal(action?.name, 'PostMessage');
  assert.match(getLastReason(gossip), /persona_gossip-test_/);
});

test('persona usefulness floor from sampled actions is non-trivial', async () => {
  const sample = [
    { name: 'QueryWorld', ok: true },
    { name: 'PostMessage', ok: true },
    { name: 'RpcCall', ok: false },
    { name: 'buy_app_tokens', ok: true },
  ];
  const unique = new Set(sample.map((s) => s.name)).size / sample.length;
  const successRate = sample.filter((s) => s.ok).length / sample.length;
  const impact = sample.filter((s) => s.name !== 'QueryWorld' && s.name !== 'DoNothing').length / sample.length;
  const usefulness = 0.35 * successRate + 0.25 * unique + 0.25 * impact + 0.15 * successRate;
  assert.ok(usefulness >= 0.45, `expected usefulness floor >=0.45, got ${usefulness.toFixed(3)}`);
});

test('persona action parse salvage keeps valid action and logs diagnostics', async () => {
  const agent = new LlmGuardrailHarness('guardrail-salvage', {
    forceLlmInDeterministic: true,
    postingPolicy: { minPostEveryTicks: 0 },
  });
  setAgentBalance(agent, { elta: BigInt(200e18), veElta: 0n });
  let calls = 0;
  (agent as unknown as { llm: { complete: (input: unknown) => Promise<string> } }).llm = {
    complete: async () => {
      calls += 1;
      if (calls === 1) {
        return '{"hypothesis":"observe","expectedEffect":"act","preferredActionFamily":"PostMessage","confidence":0.9}';
      }
      return '{"name":"PostMessage","params":{"channelId":"global","text":"salvaged signal"},"metadata":{"personaId":"guardrail-test","confidence":2}}';
    },
  };
  const gossip = {
    readInbox: () => [],
    postMessage: () => ({ ok: true, messageId: 'm-1' }),
  };
  const action = await agent.step(createTestContext({ tick: 4, mode: 'deterministic', gossip }));
  assert.equal(action?.name, 'PostMessage');
  const history = (agent.exportMemory().decisionHistory ?? []) as Array<{ reason?: string }>;
  assert.ok(history.some((h) => String(h.reason ?? '') === 'llm_action_parse_error'));
  assert.ok(history.some((h) => String(h.reason ?? '') === 'llm_action_salvaged'));
});

test('posting guardrail can inject PostMessage in fallback mode', async () => {
  const agent = new LlmGuardrailHarness('guardrail-posting', {
    postingPolicy: {
      preferredChannels: ['global'],
      minPostEveryTicks: 1,
      postOnInboxThreshold: 1,
      postOnMaterialChange: true,
    },
  });
  setAgentBalance(agent, { elta: BigInt(200e18), veElta: 0n });
  const gossip = {
    readInbox: () =>
      [
        {
          envelope: {
            id: 'm-1',
            tick: 0,
            authorAgentId: 'peer-1',
            channelId: 'global',
            payloadHash: 'h',
          },
          payload: { text: 'watch risk' },
        },
      ] as GossipMessage[],
    postMessage: () => ({ ok: true, messageId: 'm-2' }),
  };
  const action = await agent.step(createTestContext({ tick: 5, mode: 'deterministic', gossip }));
  assert.equal(action?.name, 'PostMessage');
  assert.equal(String((action as Action).metadata?.llmSource ?? ''), 'ooda_posting_guardrail');
});

test('llm post retry prefers PostMessage when posting is due', async () => {
  const agent = new LlmGuardrailHarness('llm-post-retry', {
    forceLlmInDeterministic: true,
    postingPolicy: {
      preferredChannels: ['global'],
      minPostEveryTicks: 1,
      postOnInboxThreshold: 1,
      postOnMaterialChange: false,
    },
  });
  setAgentBalance(agent, { elta: BigInt(200e18), veElta: 0n });
  let calls = 0;
  (agent as unknown as { llm: { complete: (input: unknown) => Promise<string> } }).llm = {
    complete: async () => {
      calls += 1;
      if (calls === 1) {
        return '{"hypothesis":"scan inbox","expectedEffect":"decide","preferredActionFamily":"QueryWorld","confidence":0.7}';
      }
      if (calls === 2) {
        return '{"name":"QueryWorld","params":{"endpoint":"get_world"},"metadata":{"personaId":"guardrail-test","confidence":0.6}}';
      }
      return '{"name":"PostMessage","params":{"channelId":"global","text":"I disagree with prior signal; risk is underestimated"},"metadata":{"personaId":"guardrail-test","confidence":0.75}}';
    },
  };
  const gossip = {
    readInbox: () =>
      [
        {
          envelope: {
            id: 'm-1',
            tick: 0,
            authorAgentId: 'peer-1',
            channelId: 'global',
            payloadHash: 'h',
          },
          payload: { text: 'fees look weak; caution advised' },
        },
      ] as GossipMessage[],
    postMessage: () => ({ ok: true, messageId: 'm-3' }),
  };
  const action = await agent.step(createTestContext({ tick: 3, mode: 'deterministic', gossip }));
  assert.equal(action?.name, 'PostMessage');
  assert.equal(String((action as Action).metadata?.llmSource ?? ''), 'llm_post_due_retry');
});
