import type { Action, TickContext } from '@elata-biosciences/agentforge';
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  BaseProtocolAgent,
  type DecisionMemoryEntry,
  type DecisionMemoryPayload,
} from '../../agents/BaseProtocolAgent.js';
import { createTestContext } from './testHarness.js';

class MemoryProbeAgent extends BaseProtocolAgent {
  async step(_ctx: TickContext): Promise<Action | null> {
    return null;
  }

  record(ctx: TickContext, payload: DecisionMemoryPayload): void {
    this.recordDecisionMemory(ctx, payload);
  }

  getMemory(): Record<string, unknown> {
    return this.exportMemory();
  }
}

test('recordDecisionMemory writes required top-level fields', () => {
  const agent = new MemoryProbeAgent('probe-1');
  const ctx = createTestContext({
    tick: 7,
    lastResult: { ok: false, error: 'execution reverted because balance too low' },
  });

  agent.record(ctx, {
    decision: 'buy_app_token',
    reason: 'threshold_crossed',
    context: { appId: 'app-1', amount: 123n },
  });

  const memory = agent.getMemory();
  assert.equal(memory.lastTick, 7);
  assert.equal(memory.lastDecision, 'buy_app_token');
  assert.equal(memory.lastReason, 'threshold_crossed');
  assert.deepEqual(memory.lastOutcome, {
    ok: false,
    error: 'execution reverted because balance too low',
  });

  const history = memory.decisionHistory as DecisionMemoryEntry[];
  assert.equal(history.length, 1);
  assert.equal(history[0]?.decision, 'buy_app_token');
  assert.equal(history[0]?.context?.amount, '123');
});

test('recordDecisionMemory keeps payload compact and truncates oversized fields', () => {
  const agent = new MemoryProbeAgent('probe-2');
  const longReason = 'x'.repeat(250);
  const longText = 'y'.repeat(400);
  const ctx = createTestContext({ tick: 3 });

  agent.record(ctx, {
    decision: 'no_op',
    reason: longReason,
    context: {
      text: longText,
      finite: 42,
      keepBoolean: true,
      nested: { drop: true },
      badNumber: Number.NaN,
    },
  });

  const memory = agent.getMemory();
  const reason = memory.lastReason as string;
  assert.equal(reason.length, 120);

  const history = memory.decisionHistory as DecisionMemoryEntry[];
  const context = history[0]?.context ?? {};
  assert.equal((context.text as string).length, 160);
  assert.equal(context.finite, 42);
  assert.equal(context.keepBoolean, true);
  assert.equal('nested' in context, false);
  assert.equal('badNumber' in context, false);
});

test('recordDecisionMemory enforces rolling history bound and trims oldest entries', () => {
  const agent = new MemoryProbeAgent('probe-3', { decisionMemoryHistoryLimit: 3 });

  for (let tick = 0; tick < 6; tick++) {
    agent.record(createTestContext({ tick }), {
      decision: `decision_${tick}`,
      reason: `reason_${tick}`,
      context: { tick },
    });
  }

  const history = agent.getMemory().decisionHistory as DecisionMemoryEntry[];
  assert.equal(history.length, 3);
  assert.deepEqual(
    history.map((entry) => entry.tick),
    [3, 4, 5]
  );
  assert.equal(history[0]?.decision, 'decision_3');
  assert.equal(history[2]?.decision, 'decision_5');
});
