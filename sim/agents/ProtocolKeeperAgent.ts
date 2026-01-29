/**
 * ProtocolKeeperAgent - Maintains protocol operations
 *
 * Behavior:
 * - Executes fee epoch closures
 * - Sweeps fees from bonding curves
 * - Maintains protocol health
 * - Earns keeper incentives
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import { closeFeeEpoch, sweepFees } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Keeper task tracking
 */
interface KeeperTask {
  type: 'close_epoch' | 'sweep_fees' | 'sweep_elta';
  appId?: number;
  curveAddress?: Address;
  lastExecuted: number;
  executionCount: number;
  incentiveEarned: bigint;
}

/**
 * Parameters for ProtocolKeeperAgent
 */
export interface ProtocolKeeperAgentParams extends BaseProtocolAgentParams {
  /** Keeper check frequency (default 0.4) */
  checkFrequency?: number;
  /** Minimum time between epoch closures (default 15 ticks) */
  epochCooldown?: number;
  /** Focus apps (empty = all) */
  focusApps?: number[];
}

/**
 * Protocol keeper maintaining operations
 */
export class ProtocolKeeperAgent extends BaseProtocolAgent {
  /** Active keeper tasks */
  private tasks: Map<string, KeeperTask> = new Map();

  /** Total incentives earned */
  private totalIncentives = 0n;

  /** Tasks executed */
  private tasksExecuted = 0;

  /** Initialized */
  private initialized = false;

  async step(ctx: TickContext): Promise<Action | null> {
    const frequency = (this.params.checkFrequency as number | undefined) ?? 0.4;
    const epochCooldown = (this.params.epochCooldown as number | undefined) ?? 15;
    const focusApps = (this.params.focusApps as number[] | undefined) ?? [];

    // Initialize tasks
    if (!this.initialized) {
      this.initializeTasks(focusApps);
      this.initialized = true;
    }

    // Check for keeper opportunities
    if (this.shouldAct(ctx, frequency)) {
      // Priority 1: Close fee epochs
      const epochAction = this.closeEpochs(ctx, epochCooldown, focusApps);
      if (epochAction) return epochAction;

      // Priority 2: Sweep fees
      const sweepAction = this.sweepAllFees(ctx);
      if (sweepAction) return sweepAction;
    }

    return null;
  }

  /**
   * Initialize keeper tasks
   */
  private initializeTasks(focusApps: number[]): void {
    // Protocol-level epoch task
    this.tasks.set('epoch_0', {
      type: 'close_epoch',
      appId: 0,
      lastExecuted: 0,
      executionCount: 0,
      incentiveEarned: 0n,
    });

    // App-specific tasks
    const apps = focusApps.length > 0 
      ? focusApps 
      : [1, 2, 3, 4, 5]; // Default first 5 apps

    for (const appId of apps) {
      this.tasks.set(`epoch_${appId}`, {
        type: 'close_epoch',
        appId,
        lastExecuted: 0,
        executionCount: 0,
        incentiveEarned: 0n,
      });
    }
  }

  /**
   * Close fee epochs for apps
   */
  private closeEpochs(
    ctx: TickContext,
    cooldown: number,
    focusApps: number[]
  ): Action | null {
    // Check protocol epoch first
    const protocolTask = this.tasks.get('epoch_0');
    if (protocolTask && ctx.tick - protocolTask.lastExecuted >= cooldown) {
      return this.executeEpochClose(ctx, 0);
    }

    // Check app epochs
    const appIds = focusApps.length > 0 ? focusApps : [1, 2, 3, 4, 5];
    
    for (const appId of appIds) {
      const task = this.tasks.get(`epoch_${appId}`);
      if (!task) continue;

      if (ctx.tick - task.lastExecuted >= cooldown) {
        // Verify app exists
        const appState = this.getAppState(String(appId));
        if (appState) {
          return this.executeEpochClose(ctx, appId);
        }
      }
    }

    return null;
  }

  /**
   * Execute epoch closure
   */
  private executeEpochClose(ctx: TickContext, appId: number): Action | null {
    const taskKey = `epoch_${appId}`;
    const task = this.tasks.get(taskKey);
    
    if (task) {
      task.lastExecuted = ctx.tick;
      task.executionCount++;
      
      // Simulate incentive (0.1% of epoch fees)
      const incentive = BigInt(Math.floor(Math.random() * 1e18));
      task.incentiveEarned += incentive;
      this.totalIncentives += incentive;
    }

    this.tasksExecuted++;

    ctx.logger.debug(
      { 
        agent: this.id, 
        appId,
        tasksExecuted: this.tasksExecuted,
        totalIncentives: this.formatElta(this.totalIncentives)
      },
      'Closing fee epoch'
    );

    return this.createAction(
      'close_fee_epoch',
      closeFeeEpoch(appId),
      ctx.tick
    );
  }

  /**
   * Sweep fees from bonding curves
   */
  private sweepAllFees(ctx: TickContext): Action | null {
    // Find curves that might have fees
    for (const [appId, app] of this.getAllApps()) {
      if (app.graduated) continue;

      // Check if we should sweep this curve
      const taskKey = `sweep_${appId}`;
      let task = this.tasks.get(taskKey);
      
      if (!task) {
        task = {
          type: 'sweep_fees',
          appId: Number(appId),
          curveAddress: app.tokenAddress as Address,
          lastExecuted: 0,
          executionCount: 0,
          incentiveEarned: 0n,
        };
        this.tasks.set(taskKey, task);
      }

      // Sweep every 20 ticks
      if (ctx.tick - task.lastExecuted >= 20) {
        task.lastExecuted = ctx.tick;
        task.executionCount++;
        this.tasksExecuted++;

        ctx.logger.debug(
          { agent: this.id, app: appId },
          'Sweeping bonding curve fees'
        );

        return this.createAction(
          'sweep_fees',
          sweepFees(app.tokenAddress as Address),
          ctx.tick
        );
      }
    }

    return null;
  }

  /**
   * Get keeper statistics
   */
  getSimStats(): {
    tasksExecuted: number;
    totalIncentives: bigint;
    taskBreakdown: Array<{ task: string; executions: number; incentive: string }>;
  } {
    const taskBreakdown = Array.from(this.tasks.entries()).map(([key, task]) => ({
      task: key,
      executions: task.executionCount,
      incentive: this.formatElta(task.incentiveEarned),
    }));

    return {
      tasksExecuted: this.tasksExecuted,
      totalIncentives: this.totalIncentives,
      taskBreakdown,
    };
  }
}
