/**
 * Developer Agent Types for Elata Protocol
 *
 * Different types of developers with varying behaviors:
 * - DeveloperAgent: Standard app developer
 * - SerialDeveloperAgent: Launches many apps quickly
 * - QualityDeveloperAgent: Focuses on fewer, better apps
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { createApp } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for DeveloperAgent
 */
export interface DeveloperAgentParams extends BaseProtocolAgentParams {
  /** Maximum number of apps this developer will create */
  maxApps?: number;
  /** Probability of launching per tick (0-1) */
  launchProbability?: number;
  /** Minimum ticks between launches */
  launchCooldown?: number;
  /** App name prefix */
  appNamePrefix?: string;
}

/**
 * Standard developer agent
 *
 * Behavior:
 * - Creates apps with configurable frequency
 * - Respects cooldown between launches
 * - Names apps based on prefix + counter
 */
export class DeveloperAgent extends BaseProtocolAgent {
  /** Track launched apps */
  private launchedApps: string[] = [];

  /** Last tick we launched */
  private lastLaunchTick = -9999;

  async step(ctx: TickContext): Promise<Action | null> {
    const maxApps = (this.params.maxApps as number | undefined) ?? 3;
    const launchProb = (this.params.launchProbability as number | undefined) ?? 0.1;
    const cooldown = (this.params.launchCooldown as number | undefined) ?? 10;

    // Check if at capacity
    if (this.launchedApps.length >= maxApps) {
      return null;
    }

    // Check cooldown
    if (ctx.tick - this.lastLaunchTick < cooldown) {
      return null;
    }

    // Roll for launch
    if (!this.shouldAct(ctx, launchProb)) {
      return null;
    }

    // Generate app name
    const prefix = (this.params.appNamePrefix as string | undefined) ?? 'App';
    const name = `${prefix}_${this.id}_${this.launchedApps.length}`;
    const symbol = `${prefix.substring(0, 3).toUpperCase()}${this.launchedApps.length}`;

    ctx.logger.info({ agent: this.id, appName: name }, 'Launching new app');

    return this.createAction(
      'create_app',
      createApp(name, symbol, `ipfs://metadata/${name.toLowerCase()}`),
      ctx.tick
    );
  }

  /**
   * Called when app launch is confirmed
   */
  onAppLaunched(appId: string, tick: number): void {
    this.launchedApps.push(appId);
    this.lastLaunchTick = tick;
  }

  /**
   * Get number of launched apps
   */
  getLaunchedCount(): number {
    return this.launchedApps.length;
  }
}

/**
 * Parameters for SerialDeveloperAgent
 */
export interface SerialDeveloperAgentParams extends DeveloperAgentParams {
  /** Minimum ticks between rapid launches */
  rapidLaunchCooldown?: number;
}

/**
 * Serial developer agent - launches apps rapidly
 *
 * Behavior:
 * - Higher launch frequency
 * - Shorter cooldowns
 * - Many apps with similar templates
 */
export class SerialDeveloperAgent extends DeveloperAgent {
  constructor(id: string, params?: Record<string, unknown>) {
    // Override defaults for serial behavior
    super(id, {
      maxApps: 10,
      launchProbability: 0.25,
      launchCooldown: 5,
      appNamePrefix: 'Serial',
      ...params,
    });
  }

  async step(ctx: TickContext): Promise<Action | null> {
    // More aggressive launch behavior
    const rapidCooldown = (this.params.rapidLaunchCooldown as number | undefined) ?? 3;

    // Override parent cooldown check
    const baseParams = this.params;
    this.params = { ...baseParams, launchCooldown: rapidCooldown };

    const result = await super.step(ctx);

    this.params = baseParams;
    return result;
  }
}

/**
 * Quality developer agent - focuses on fewer apps
 *
 * Behavior:
 * - Lower launch frequency but more considered
 * - Waits for market conditions
 * - Only launches when ecosystem is healthy
 */
export class QualityDeveloperAgent extends DeveloperAgent {
  constructor(id: string, params?: Record<string, unknown>) {
    // Override defaults for quality behavior
    super(id, {
      maxApps: 2,
      launchProbability: 0.05,
      launchCooldown: 50,
      appNamePrefix: 'Quality',
      ...params,
    });
  }

  async step(ctx: TickContext): Promise<Action | null> {
    // Only launch if ecosystem is healthy
    const appCount = this.getAppCount();

    // Wait for some apps to exist first (proof of concept)
    if (appCount < 5) {
      return null;
    }

    // Check if any apps have graduated (market maturity)
    const apps = Array.from(this.getAllApps().values());
    const graduated = apps.filter((a) => a.graduated);

    if (graduated.length === 0 && appCount > 10) {
      // Market isn't mature enough
      return null;
    }

    return super.step(ctx);
  }
}
