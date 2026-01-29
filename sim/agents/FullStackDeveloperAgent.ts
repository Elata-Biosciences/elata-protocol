/**
 * FullStackDeveloperAgent - Complete app ecosystem developer
 *
 * Behavior:
 * - Creates apps with all features
 * - Deploys content, tournaments, staking
 * - Builds complete ecosystems
 * - Manages app lifecycle
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { createApp, createTournament, listContent, buyAppToken } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * App feature tracking
 */
interface AppFeatures {
  appId: string;
  hasContent: boolean;
  hasTournaments: boolean;
  hasStaking: boolean;
  contentCount: number;
  tournamentCount: number;
  totalRevenue: bigint;
}

/**
 * Parameters for FullStackDeveloperAgent
 */
export interface FullStackDeveloperAgentParams extends BaseProtocolAgentParams {
  /** Number of apps to create (default 2) */
  appsToCreate?: number;
  /** Feature deployment rate (default 0.2) */
  featureRate?: number;
  /** Self-invest percentage (default 0.1 = 10%) */
  selfInvestPercent?: number;
  /** Focus on quality over quantity (default true) */
  qualityFocus?: boolean;
}

/**
 * Full-stack app developer
 */
export class FullStackDeveloperAgent extends BaseProtocolAgent {
  /** Apps created by this developer */
  private myApps: Map<string, AppFeatures> = new Map();

  /** Apps created count */
  private appsCreated = 0;

  /** Total features deployed */
  private featuresDeployed = 0;

  /** Phase of development */
  private phase: 'creating' | 'developing' | 'maintaining' = 'creating';

  async step(ctx: TickContext): Promise<Action | null> {
    const targetApps = (this.params.appsToCreate as number | undefined) ?? 2;
    const featureRate = (this.params.featureRate as number | undefined) ?? 0.2;
    const selfInvest = (this.params.selfInvestPercent as number | undefined) ?? 0.1;
    const quality = (this.params.qualityFocus as boolean | undefined) ?? true;

    // Phase 1: Create apps
    if (this.phase === 'creating') {
      if (this.appsCreated < targetApps && this.shouldAct(ctx, 0.15)) {
        return this.createNewApp(ctx);
      }
      if (this.appsCreated >= targetApps) {
        this.phase = 'developing';
      }
    }

    // Phase 2: Develop features for apps
    if (this.phase === 'developing' && this.shouldAct(ctx, featureRate)) {
      const developAction = this.developFeatures(ctx, quality);
      if (developAction) return developAction;

      // Check if all apps are fully featured
      const allFeatured = Array.from(this.myApps.values()).every(
        app => app.hasContent && app.hasTournaments
      );
      if (allFeatured) {
        this.phase = 'maintaining';
      }
    }

    // Phase 3: Maintain and grow
    if (this.phase === 'maintaining' && this.shouldAct(ctx, 0.1)) {
      return this.maintainEcosystem(ctx, selfInvest);
    }

    return null;
  }

  /**
   * Create a new app
   */
  private createNewApp(ctx: TickContext): Action | null {
    this.appsCreated++;
    const appName = `FullStack App ${this.appsCreated}`;
    const appSymbol = `FS${this.appsCreated}`;

    ctx.logger.info(
      { agent: this.id, name: appName, number: this.appsCreated },
      'Creating full-stack app'
    );

    // Track app (will be registered when we see it in state)
    return this.createAction(
      'create_app',
      createApp(appName, appSymbol, `ipfs://fullstack-${this.appsCreated}`),
      ctx.tick
    );
  }

  /**
   * Develop features for apps
   */
  private developFeatures(ctx: TickContext, qualityFocus: boolean): Action | null {
    // Register any new apps we've created
    this.registerNewApps();

    // Find app that needs features
    for (const [appId, features] of this.myApps) {
      const app = this.getAppState(appId);
      if (!app || app.graduated) continue;

      // Deploy content if missing
      if (!features.hasContent) {
        return this.deployContent(ctx, appId, app.tokenAddress, qualityFocus);
      }

      // Deploy tournament if missing
      if (!features.hasTournaments) {
        return this.deployTournament(ctx, appId, app.tokenAddress);
      }
    }

    return null;
  }

  /**
   * Register apps we've created
   */
  private registerNewApps(): void {
    for (const [appId, _app] of this.getAllApps()) {
      if (!this.myApps.has(appId)) {
        // Check if this might be our app (by name pattern)
        // In real scenario, would track by creation transaction
        if (this.myApps.size < this.appsCreated) {
          this.myApps.set(appId, {
            appId,
            hasContent: false,
            hasTournaments: false,
            hasStaking: false,
            contentCount: 0,
            tournamentCount: 0,
            totalRevenue: 0n,
          });
        }
      }
    }
  }

  /**
   * Deploy content to app
   */
  private deployContent(
    ctx: TickContext,
    appId: string,
    tokenAddress: Address,
    qualityFocus: boolean
  ): Action | null {
    const features = this.myApps.get(appId);
    if (!features) return null;

    // Deploy content
    const contentCount = qualityFocus ? 3 : 1;
    const price = qualityFocus ? BigInt(10e18) : BigInt(5e18);

    features.hasContent = true;
    features.contentCount += contentCount;
    this.featuresDeployed++;

    ctx.logger.info(
      { agent: this.id, app: appId, contentCount },
      'Deploying content to app'
    );

    return this.createAction(
      'list_content',
      listContent(
        tokenAddress,
        `ipfs://fullstack-content-${appId}`,
        price,
        1, // ELTA payment
        BigInt(1000)
      ),
      ctx.tick
    );
  }

  /**
   * Deploy tournament to app
   */
  private deployTournament(
    ctx: TickContext,
    appId: string,
    tokenAddress: Address
  ): Action | null {
    const features = this.myApps.get(appId);
    if (!features) return null;

    features.hasTournaments = true;
    features.tournamentCount++;
    this.featuresDeployed++;

    const now = BigInt(Math.floor(Date.now() / 1000));
    const startTime = now + 60n; // Start in 1 minute
    const endTime = startTime + 3600n; // 1 hour duration

    ctx.logger.info(
      { agent: this.id, app: appId },
      'Deploying tournament to app'
    );

    return this.createAction(
      'create_tournament',
      createTournament(
        appId,
        tokenAddress,
        BigInt(10e18), // 10 ELTA entry
        startTime,
        endTime,
        100n, // Max 100 participants
        8000n // 80% prize pool
      ),
      ctx.tick
    );
  }

  /**
   * Maintain and grow ecosystem
   */
  private maintainEcosystem(ctx: TickContext, selfInvestPct: number): Action | null {
    const balance = this.getEltaBalance();
    const investAmount = BigInt(Math.floor(Number(balance) * selfInvestPct));

    if (investAmount < BigInt(10e18)) return null;

    // Self-invest in own apps
    const myAppIds = Array.from(this.myApps.keys());
    if (myAppIds.length === 0) return null;

    const targetAppId = ctx.rng.pickOne(myAppIds);
    const app = this.getAppState(targetAppId);
    if (!app) return null;

    ctx.logger.debug(
      { agent: this.id, app: targetAppId, amount: this.formatElta(investAmount) },
      'Self-investing in own app'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(targetAppId, app.tokenAddress, investAmount),
      ctx.tick
    );
  }

  /**
   * Get developer statistics
   */
  getSimStats(): {
    appsCreated: number;
    featuresDeployed: number;
    phase: string;
    appDetails: Array<{ appId: string; hasContent: boolean; hasTournaments: boolean }>;
  } {
    const appDetails = Array.from(this.myApps.values()).map(f => ({
      appId: f.appId,
      hasContent: f.hasContent,
      hasTournaments: f.hasTournaments,
    }));

    return {
      appsCreated: this.appsCreated,
      featuresDeployed: this.featuresDeployed,
      phase: this.phase,
      appDetails,
    };
  }
}
