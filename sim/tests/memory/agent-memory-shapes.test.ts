import type { Action, TickContext } from '@elata-biosciences/agentforge';
import assert from 'node:assert/strict';
import test from 'node:test';
import { GovernanceStrategistAgent } from '../../agents/GovernanceStrategistAgent.js';
import { LiquidityDefenderAgent } from '../../agents/LiquidityDefenderAgent.js';
import { LlmGossipCoordinatorAgent } from '../../agents/LlmGossipCoordinatorAgent.js';
import { OpportunisticAttackerAgent } from '../../agents/OpportunisticAttackerAgent.js';
import { ProbabilisticStakerAgent } from '../../agents/ProbabilisticStakerAgent.js';
import { RegimeNoiseTraderAgent } from '../../agents/RegimeNoiseTraderAgent.js';
import { createTestApp, createTestContext, setAgentBalance } from './testHarness.js';

class TestGovernanceStrategistAgent extends GovernanceStrategistAgent {
  protected override async preStep(_ctx: TickContext): Promise<void> {}
}

class TestLiquidityDefenderAgent extends LiquidityDefenderAgent {
  protected override async preStep(_ctx: TickContext): Promise<void> {}
}

class TestProbabilisticStakerAgent extends ProbabilisticStakerAgent {
  protected override async preStep(_ctx: TickContext): Promise<void> {}
}

class TestRegimeNoiseTraderAgent extends RegimeNoiseTraderAgent {
  protected override async preStep(_ctx: TickContext): Promise<void> {}

  protected override chooseRandomApp(_ctx: TickContext) {
    return createTestApp(11);
  }
}

class TestOpportunisticAttackerAgent extends OpportunisticAttackerAgent {
  protected override async preStep(_ctx: TickContext): Promise<void> {}

  protected override chooseRandomApp(_ctx: TickContext) {
    return createTestApp(13);
  }
}

class MemoryHarnessLlmGossipCoordinatorAgent extends LlmGossipCoordinatorAgent {
  protected override getWorldState() {
    return {
      appCount: 3,
      feesCollectedTotal: 123n,
      feesDistributed: 45n,
      apps: new Map(),
    } as ReturnType<GovernanceStrategistAgent['getWorldState']>;
  }
}

type AgentWithMemory = {
  step: (ctx: TickContext) => Promise<Action | null>;
  exportMemory: () => Record<string, unknown>;
};

function assertDecisionMemoryShape(memory: Record<string, unknown>, reason: string): void {
  assert.equal(typeof memory.lastDecision, 'string');
  assert.equal(memory.lastReason, reason);
  assert.equal(typeof memory.lastTick, 'number');
  assert.ok(Array.isArray(memory.decisionHistory));
  assert.ok((memory.decisionHistory as unknown[]).length > 0);
}

function latestDecisionContext(memory: Record<string, unknown>): Record<string, unknown> {
  const history = memory.decisionHistory as Array<{ context?: Record<string, unknown> }>;
  return history[history.length - 1]?.context ?? {};
}

test('key agents populate decision memory with expected reason codes', async () => {
  const governanceAgent = new TestGovernanceStrategistAgent('gov-1');
  setAgentBalance(governanceAgent, { elta: BigInt(1_000e18), veElta: 0n });

  const liquidityAgent = new TestLiquidityDefenderAgent('liq-1');
  setAgentBalance(liquidityAgent, { elta: BigInt(1_000e18), veElta: 0n });

  const stakerAgent = new TestProbabilisticStakerAgent('stk-1');
  setAgentBalance(stakerAgent, { elta: BigInt(1_000e18), veElta: 0n });

  const noiseTraderAgent = new TestRegimeNoiseTraderAgent('rng-1');
  setAgentBalance(noiseTraderAgent, { elta: BigInt(1_000e18), veElta: 0n });

  const attackerAgent = new TestOpportunisticAttackerAgent('atk-1');
  setAgentBalance(attackerAgent, { elta: BigInt(1_000e18), veElta: 0n });

  const scenarios: Array<{
    name: string;
    agent: AgentWithMemory;
    ctx: TickContext;
    expectedReason: string;
  }> = [
    {
      name: 'governance strategist lock',
      agent: governanceAgent,
      ctx: createTestContext({
        tick: 1,
        gossip: {
          readInbox: () => [
            {
              envelope: {
                id: 'm1',
                tick: 1,
                authorAgentId: 'x',
                channelId: 'governance',
              audience: { type: 'public' },
              costPaid: 1,
              credibilityPrior: 0.8,
              payloadHash: 'abc',
              },
              payload: { text: 'vote on proposal and claim reward' },
            },
          ],
          postMessage: () => ({ ok: true }),
        },
      }),
      expectedReason: 'increase_voting_power',
    },
    {
      name: 'liquidity defender lock',
      agent: liquidityAgent,
      ctx: createTestContext({ tick: 2 }),
      expectedReason: 'maintain_defense_lock',
    },
    {
      name: 'probabilistic staker lock',
      agent: stakerAgent,
      ctx: createTestContext({
        tick: 3,
        rng: { chance: true, pickOne: (items) => items[1]! },
      }),
      expectedReason: 'state_lock_bias',
    },
    {
      name: 'noise trader risk-on buy',
      agent: noiseTraderAgent,
      ctx: createTestContext({
        tick: 4,
        rng: { chance: true, pickOne: (items) => items[0]!, nextFloat: 0.4 },
      }),
      expectedReason: 'regime_risk_on_buy',
    },
    {
      name: 'opportunistic attacker burst buy',
      agent: attackerAgent,
      ctx: createTestContext({
        tick: 5,
        rng: { chance: true, pickOne: (items) => items[1]! },
      }),
      expectedReason: 'burst_buy_execute',
    },
    {
      name: 'llm gossip no-op without gossip context',
      agent: new MemoryHarnessLlmGossipCoordinatorAgent('llm-1'),
      ctx: createTestContext({ tick: 6 }),
      expectedReason: 'gossip_unavailable',
    },
    {
      name: 'llm gossip post failure captures error code',
      agent: new MemoryHarnessLlmGossipCoordinatorAgent('llm-2', {
        channelId: 'risk',
        postEveryTicks: 1,
      }),
      ctx: createTestContext({
        tick: 7,
        gossip: {
          readInbox: () => [],
          postMessage: () => ({ ok: false, error: 'unknown_channel:risk' }),
        },
      }),
      expectedReason: 'gossip_post_failed_unknown_channel:risk',
    },
    {
      name: 'llm gossip post success records post decision',
      agent: new MemoryHarnessLlmGossipCoordinatorAgent('llm-3', {
        channelId: 'governance',
        postEveryTicks: 1,
      }),
      ctx: createTestContext({
        tick: 8,
        gossip: {
          readInbox: () => [],
          postMessage: () => ({ ok: true, messageId: 'msg-123' }),
        },
      }),
      expectedReason: 'posted_gossip_deterministic',
    },
  ];

  for (const scenario of scenarios) {
    await scenario.agent.step(scenario.ctx);
    const memory = scenario.agent.exportMemory();
    assertDecisionMemoryShape(memory, scenario.expectedReason);
    assert.equal(typeof memory.lastDecision, 'string', scenario.name);
    if (scenario.name === 'governance strategist lock') {
      const context = latestDecisionContext(memory);
      assert.equal(context.gossipReads, 1);
      assert.equal(context.targetVeElta, '500000000000000000000');
    }
    if (scenario.name === 'llm gossip post failure captures error code') {
      assert.equal(memory.lastDecision, 'no_op');
      const context = latestDecisionContext(memory);
      assert.equal(context.error, 'unknown_channel:risk');
    }
    if (scenario.name === 'llm gossip post success records post decision') {
      assert.equal(memory.lastDecision, 'post_gossip');
      const context = latestDecisionContext(memory);
      assert.equal(context.messageId, 'msg-123');
    }
  }
});

test('gossip consumer agents record inbox-derived context fields', async () => {
  const governanceAgent = new TestGovernanceStrategistAgent('gov-gossip');
  setAgentBalance(governanceAgent, { elta: BigInt(1_000e18), veElta: 0n });
  await governanceAgent.step(
    createTestContext({
      tick: 2,
      gossip: {
        readInbox: () => [
          {
            envelope: {
              id: 'g-msg',
              tick: 2,
              authorAgentId: 'llm-1',
              channelId: 'governance',
              audience: { type: 'public' },
              costPaid: 1,
              credibilityPrior: 0.9,
              payloadHash: 'hash',
            },
            payload: { text: 'vote now and claim rewards' },
          },
        ],
        postMessage: () => ({ ok: true }),
      },
    })
  );
  const governanceMemory = governanceAgent.exportMemory();
  assert.equal(latestDecisionContext(governanceMemory).gossipReads, 1);

  const liquidityAgent = new TestLiquidityDefenderAgent('liq-gossip');
  setAgentBalance(liquidityAgent, { elta: BigInt(1_000e18), veElta: 0n });
  await liquidityAgent.step(
    createTestContext({
      tick: 3,
      gossip: {
        readInbox: () => [
          {
            envelope: {
              id: 'l-msg',
              tick: 3,
              authorAgentId: 'llm-2',
              channelId: 'risk',
              audience: { type: 'public' },
              costPaid: 1,
              credibilityPrior: 0.7,
              payloadHash: 'hash-2',
            },
            payload: { text: 'high risk attack volatility alert' },
          },
        ],
        postMessage: () => ({ ok: true }),
      },
    })
  );
  const liquidityMemory = liquidityAgent.exportMemory();
  assert.equal(latestDecisionContext(liquidityMemory).gossipReads, 1);

  const regimeAgent = new TestRegimeNoiseTraderAgent('regime-gossip');
  setAgentBalance(regimeAgent, { elta: BigInt(1_000e18), veElta: 0n });
  await regimeAgent.step(
    createTestContext({
      tick: 4,
      rng: { chance: true, pickOne: (items) => items[0]!, nextFloat: 0.4 },
      gossip: {
        readInbox: () => [
          {
            envelope: {
              id: 'r-msg',
              tick: 4,
              authorAgentId: 'llm-3',
              channelId: 'markets',
              audience: { type: 'public' },
              costPaid: 1,
              credibilityPrior: 0.6,
              payloadHash: 'hash-3',
            },
            payload: { text: 'bull buy accumulate now' },
          },
        ],
        postMessage: () => ({ ok: true }),
      },
    })
  );
  const regimeMemory = regimeAgent.exportMemory();
  assert.equal(latestDecisionContext(regimeMemory).gossipReads, 1);
});
