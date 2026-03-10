/**
 * ModuleDeployerAgent - Deploys specific modules to apps
 *
 * Behavior:
 * - Specializes in deploying specific features
 * - Works across multiple apps
 * - Optimizes module configurations
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { createTournament, listContent, listContentWithTimeWindow } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Module deployment tracking
 */
interface ModuleDeployment {
  appId: string;
  moduleType: 'tournament' | 'content' | 'staking';
  deployedTick: number;
  config: Record<string, unknown>;
  performance: {
    usageCount: number;
    revenue: bigint;
  };
}

/**
 * Parameters for ModuleDeployerAgent
 */
export interface ModuleDeployerAgentParams extends BaseProtocolAgentParams {
  /** Module types to deploy (default all) */
  moduleTypes?: Array<'tournament' | 'content' | 'staking'>;
  /** Deployment frequency (default 0.15) */
  deployFrequency?: number;
  /** Maximum deployments (default 20) */
  maxDeployments?: number;
  /** Optimize based on performance (default true) */
  optimizeConfig?: boolean;
}

/**
 * Module deployer specialist
 */
export class ModuleDeployerAgent extends BaseProtocolAgent {
  /** Deployments made */
  private deployments: ModuleDeployment[] = [];

  /** Best performing configs */
  private bestConfigs: Map<string, Record<string, unknown>> = new Map();

  /** Apps we've deployed to */
  private deployedApps: Set<string> = new Set();

  async step(ctx: TickContext): Promise<Action | null> {
    const moduleTypes = (this.params.moduleTypes as Array<'tournament' | 'content' | 'staking'> | undefined) 
      ?? ['tournament', 'content'];
    const frequency = (this.params.deployFrequency as number | undefined) ?? 0.15;
    const maxDeploys = (this.params.maxDeployments as number | undefined) ?? 20;
    const optimize = (this.params.optimizeConfig as boolean | undefined) ?? true;

    // Update performance metrics
    this.updatePerformance(ctx);

    // Deploy modules
    if (this.deployments.length < maxDeploys && this.shouldAct(ctx, frequency)) {
      return this.deployModule(ctx, moduleTypes, optimize);
    }

    return null;
  }

  /**
   * Deploy a module to an app
   */
  private deployModule(
    ctx: TickContext,
    moduleTypes: Array<'tournament' | 'content' | 'staking'>,
    optimize: boolean
  ): Action | null {
    // Find app to deploy to
    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    // Prefer apps we haven't deployed to
    let targetApp;
    const newApps = apps.filter(([id, _]) => !this.deployedApps.has(id));
    
    if (newApps.length > 0) {
      targetApp = ctx.rng.pickOne(newApps);
    } else {
      targetApp = ctx.rng.pickOne(apps);
    }

    const [appId, app] = targetApp;
    const moduleType = ctx.rng.pickOne(moduleTypes);

    // Get config (optimized or default)
    const config = optimize 
      ? this.getOptimizedConfig(moduleType) 
      : this.getDefaultConfig(moduleType);

    this.deployedApps.add(appId);

    // Track deployment
    this.deployments.push({
      appId,
      moduleType,
      deployedTick: ctx.tick,
      config,
      performance: { usageCount: 0, revenue: 0n },
    });

    ctx.logger.info(
      { 
        agent: this.id, 
        app: appId,
        module: moduleType,
        deploymentCount: this.deployments.length
      },
      'Deploying module'
    );

    // Execute deployment based on type
    switch (moduleType) {
      case 'tournament':
        return this.deployTournamentModule(ctx, appId, app.tokenAddress, config);
      case 'content':
        return this.deployContentModule(ctx, appId, app.tokenAddress, config);
      default:
        return null;
    }
  }

  /**
   * Deploy tournament module
   */
  private deployTournamentModule(
    ctx: TickContext,
    appId: string,
    tokenAddress: Address,
    config: Record<string, unknown>
  ): Action | null {
    const entryFee = (config.entryFee as bigint) ?? BigInt(10e18);
    const duration = (config.duration as number) ?? 3600;
    const maxParticipants = (config.maxParticipants as bigint) ?? 50n;
    const prizePoolBps = (config.prizePoolBps as bigint) ?? 8000n;

    const now = BigInt(Math.floor(Date.now() / 1000));
    const startTime = now + 120n;
    const endTime = startTime + BigInt(duration);

    return this.createAction(
      'create_tournament',
      createTournament(appId, tokenAddress, entryFee, startTime, endTime, maxParticipants, prizePoolBps),
      ctx.tick
    );
  }

  /**
   * Deploy content module
   */
  private deployContentModule(
    ctx: TickContext,
    appId: string,
    tokenAddress: Address,
    config: Record<string, unknown>
  ): Action | null {
    const price = (config.price as bigint) ?? BigInt(5e18);
    const maxSupply = (config.maxSupply as bigint) ?? 100n;
    const isLimited = (config.isLimited as boolean) ?? false;

    if (isLimited) {
      const now = BigInt(Math.floor(Date.now() / 1000));
      const startTime = now;
      const endTime = now + 86400n; // 24 hours

      return this.createAction(
        'list_content_with_time_window',
        listContentWithTimeWindow(
          tokenAddress,
          `ipfs://module-content-${appId}-${Date.now()}`,
          price,
          1, // ELTA
          maxSupply,
          startTime,
          endTime
        ),
        ctx.tick
      );
    } else {
      return this.createAction(
        'list_content',
        listContent(
          tokenAddress,
          `ipfs://module-content-${appId}-${Date.now()}`,
          price,
          1, // ELTA
          maxSupply
        ),
        ctx.tick
      );
    }
  }

  /**
   * Get optimized config based on past performance
   */
  private getOptimizedConfig(moduleType: string): Record<string, unknown> {
    const best = this.bestConfigs.get(moduleType);
    if (best) return { ...best };

    // Return default with small variations
    const defaults = this.getDefaultConfig(moduleType);
    
    // Add some random optimization
    if (moduleType === 'tournament') {
      defaults.entryFee = BigInt(Math.floor(Number(defaults.entryFee as bigint) * (0.8 + Math.random() * 0.4)));
    }

    return defaults;
  }

  /**
   * Get default config for module type
   */
  private getDefaultConfig(moduleType: string): Record<string, unknown> {
    switch (moduleType) {
      case 'tournament':
        return {
          entryFee: BigInt(10e18),
          duration: 3600,
          maxParticipants: 50n,
          prizePoolBps: 8000n,
        };
      case 'content':
        return {
          price: BigInt(5e18),
          maxSupply: 100n,
          isLimited: false,
        };
      default:
        return {};
    }
  }

  /**
   * Update performance metrics and best configs
   */
  private updatePerformance(ctx: TickContext): void {
    // Simulate performance updates
    for (const deployment of this.deployments) {
      if (ctx.rng.nextFloat() < 0.3) {
        deployment.performance.usageCount++;
        deployment.performance.revenue += BigInt(Math.floor(Math.random() * 10e18));
      }
    }

    // Find best performing configs
    const byType = new Map<string, ModuleDeployment[]>();
    for (const d of this.deployments) {
      const list = byType.get(d.moduleType) ?? [];
      list.push(d);
      byType.set(d.moduleType, list);
    }

    for (const [type, deployments] of byType) {
      const best = deployments.reduce((a, b) => 
        a.performance.revenue > b.performance.revenue ? a : b
      );
      if (best.performance.revenue > 0n) {
        this.bestConfigs.set(type, best.config);
      }
    }
  }

  /**
   * Get deployer statistics
   */
  getSimStats(): {
    totalDeployments: number;
    uniqueApps: number;
    totalRevenue: bigint;
    byModuleType: Record<string, number>;
  } {
    const byModuleType: Record<string, number> = {};
    let totalRevenue = 0n;

    for (const d of this.deployments) {
      byModuleType[d.moduleType] = (byModuleType[d.moduleType] ?? 0) + 1;
      totalRevenue += d.performance.revenue;
    }

    return {
      totalDeployments: this.deployments.length,
      uniqueApps: this.deployedApps.size,
      totalRevenue,
      byModuleType,
    };
  }
}
