import type { Action, TickContext } from '@elata-biosciences/agentforge';
import assert from 'node:assert/strict';
import test from 'node:test';
import { BaseProtocolAgent, type DecisionMemoryEntry } from '../../agents/BaseProtocolAgent.js';
import { OpportunisticAttackerAgent } from '../../agents/OpportunisticAttackerAgent.js';
import { createTestApp, createTestContext, setAgentBalance } from './testHarness.js';

class RegressionProbeAgent extends BaseProtocolAgent {
  async step(_ctx: TickContext): Promise<Action | null> {
    return null;
  }

  record(ctx: TickContext, decision: string, reason: string): void {
    this.recordDecisionMemory(ctx, { decision, reason, context: { tick: ctx.tick } });
  }
}

class RegressionAttackerAgent extends OpportunisticAttackerAgent {
  protected override async preStep(_ctx: TickContext): Promise<void> {}

  protected override chooseRandomApp(_ctx: TickContext) {
    return createTestApp(21);
  }
}

test('regression: sampled snapshots include meaningful decision fields each tick', async () => {
  const agent = new RegressionAttackerAgent('atk-regression');
  setAgentBalance(agent, { elta: BigInt(1_000e18) });

  for (let tick = 0; tick < 8; tick++) {
    const ctx = createTestContext({
      tick,
      rng: {
        chance: tick % 2 === 0,
        pickOne: (items) => items[0]!,
      },
    });
    await agent.step(ctx);
    const memory = agent.exportMemory();
    assert.equal(typeof memory.lastDecision, 'string');
    assert.equal(typeof memory.lastReason, 'string');
    assert.equal(typeof memory.lastTick, 'number');
    assert.ok(Array.isArray(memory.decisionHistory));
    assert.ok((memory.decisionHistory as unknown[]).length > 0);
  }
});

test('regression: bounded history cap trims oldest entries deterministically', () => {
  const agent = new RegressionProbeAgent('probe-regression', { decisionMemoryHistoryLimit: 4 });

  for (let tick = 0; tick < 12; tick++) {
    agent.record(createTestContext({ tick }), `decision_${tick}`, `reason_${tick}`);
  }

  const history = agent.exportMemory().decisionHistory as DecisionMemoryEntry[];
  assert.equal(history.length, 4);
  assert.deepEqual(
    history.map((entry) => entry.tick),
    [8, 9, 10, 11]
  );
  assert.equal(history[0]?.reason, 'reason_8');
  assert.equal(history[3]?.reason, 'reason_11');
});
