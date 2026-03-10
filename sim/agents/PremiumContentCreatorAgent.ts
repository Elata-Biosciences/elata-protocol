/**
 * PremiumContentCreatorAgent - Creates high-value premium content
 *
 * Behavior:
 * - Creates content at premium price points
 * - Manages content portfolio
 * - Maximizes content revenue
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { listContent, listContentWithTimeWindow, deactivateContent, reactivateContent } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Content item tracking
 */
interface ContentItem {
  contentId: bigint;
  appId: string;
  price: bigint;
  salesCount: number;
  totalRevenue: bigint;
  active: boolean;
  limitedEdition: boolean;
  createdTick: number;
}

/**
 * Parameters for PremiumContentCreatorAgent
 */
export interface PremiumContentCreatorAgentParams extends BaseProtocolAgentParams {
  /** Target number of content items (default 5) */
  targetContentCount?: number;
  /** Minimum price (default 10 ELTA) */
  minPrice?: bigint;
  /** Maximum price (default 100 ELTA) */
  maxPrice?: bigint;
  /** Percentage of limited editions (default 0.3 = 30%) */
  limitedEditionRate?: number;
  /** Max supply for limited editions (default 10) */
  limitedEditionMaxSupply?: number;
  /** Target apps for content */
  targetApps?: string[];
}

/**
 * Premium content creator
 */
export class PremiumContentCreatorAgent extends BaseProtocolAgent {
  /** Created content items */
  private contentItems: ContentItem[] = [];

  /** Total revenue earned */
  private totalRevenue = 0n;

  /** Content counter per app */
  private contentCountByApp: Map<string, number> = new Map();

  async step(ctx: TickContext): Promise<Action | null> {
    const targetCount = (this.params.targetContentCount as number | undefined) ?? 5;
    const minPrice = (this.params.minPrice as bigint | undefined) ?? BigInt(10e18);
    const maxPrice = (this.params.maxPrice as bigint | undefined) ?? BigInt(100e18);
    const limitedRate = (this.params.limitedEditionRate as number | undefined) ?? 0.3;
    const limitedSupply = (this.params.limitedEditionMaxSupply as number | undefined) ?? 10;

    // Priority 1: Create new content if below target
    if (this.contentItems.length < targetCount && this.shouldAct(ctx, 0.2)) {
      return this.createContent(ctx, minPrice, maxPrice, limitedRate, limitedSupply);
    }

    // Priority 2: Manage existing content (deactivate underperforming)
    if (this.shouldAct(ctx, 0.1)) {
      return this.manageContent(ctx);
    }

    // Simulate sales happening
    this.simulateSales(ctx);

    return null;
  }

  /**
   * Create new premium content
   */
  private createContent(
    ctx: TickContext,
    minPrice: bigint,
    maxPrice: bigint,
    limitedRate: number,
    limitedSupply: number
  ): Action | null {
    const targetApps = this.params.targetApps as string[] | undefined;
    
    // Find target app
    let targetApp;
    if (targetApps && targetApps.length > 0) {
      const validApps = targetApps
        .map(id => ({ id, app: this.getAppState(id) }))
        .filter(({ app }) => app && !app.graduated);
      
      if (validApps.length > 0) {
        const pick = ctx.rng.pickOne(validApps);
        targetApp = { id: pick.id, app: pick.app! };
      }
    }

    if (!targetApp) {
      const apps = Array.from(this.getAllApps().entries())
        .filter(([_, app]) => !app.graduated);
      if (apps.length === 0) return null;
      const [id, app] = ctx.rng.pickOne(apps);
      targetApp = { id, app };
    }

    // Determine if limited edition
    const isLimited = ctx.rng.nextFloat() < limitedRate;

    // Calculate price (premium content)
    const priceRange = Number(maxPrice - minPrice);
    const price = minPrice + BigInt(Math.floor(Math.random() * priceRange));

    // Get content ID for this app
    const appContentCount = this.contentCountByApp.get(targetApp.id) ?? 0;
    const contentId = BigInt(appContentCount + 1);
    this.contentCountByApp.set(targetApp.id, appContentCount + 1);

    // Track content
    this.contentItems.push({
      contentId,
      appId: targetApp.id,
      price,
      salesCount: 0,
      totalRevenue: 0n,
      active: true,
      limitedEdition: isLimited,
      createdTick: ctx.tick,
    });

    ctx.logger.info(
      { 
        agent: this.id, 
        app: targetApp.id,
        price: this.formatElta(price),
        limitedEdition: isLimited,
        totalContent: this.contentItems.length
      },
      'Creating premium content'
    );

    if (isLimited) {
      // Limited time + limited supply
      const startTime = BigInt(Math.floor(Date.now() / 1000));
      const endTime = startTime + BigInt(7 * 24 * 60 * 60); // 1 week

      return this.createAction(
        'list_content_with_time_window',
        listContentWithTimeWindow(
          targetApp.app.tokenAddress as Address,
          `ipfs://premium-content-${contentId}`,
          price,
          1, // ELTA payment
          BigInt(limitedSupply),
          startTime,
          endTime
        ),
        ctx.tick
      );
    } else {
      // Regular premium content
      return this.createAction(
        'list_content',
        listContent(
          targetApp.app.tokenAddress as Address,
          `ipfs://premium-content-${contentId}`,
          price,
          1, // ELTA payment
          BigInt(1000) // High supply
        ),
        ctx.tick
      );
    }
  }

  /**
   * Manage existing content
   */
  private manageContent(ctx: TickContext): Action | null {
    // Find underperforming content to deactivate
    for (const content of this.contentItems) {
      if (!content.active) continue;

      // Deactivate if no sales after 20 ticks
      const ticksSinceCreated = ctx.tick - content.createdTick;
      if (ticksSinceCreated > 20 && content.salesCount === 0) {
        const app = this.getAppState(content.appId);
        if (!app) continue;

        content.active = false;

        ctx.logger.debug(
          { agent: this.id, app: content.appId, contentId: content.contentId.toString() },
          'Deactivating underperforming content'
        );

        return this.createAction(
          'deactivate_content',
          deactivateContent(app.tokenAddress as Address, content.contentId),
          ctx.tick
        );
      }
    }

    // Reactivate deactivated content with price adjustment
    for (const content of this.contentItems) {
      if (content.active) continue;

      // 10% chance to reactivate
      if (ctx.rng.nextFloat() < 0.1) {
        const app = this.getAppState(content.appId);
        if (!app) continue;

        content.active = true;

        ctx.logger.debug(
          { agent: this.id, app: content.appId, contentId: content.contentId.toString() },
          'Reactivating content'
        );

        return this.createAction(
          'reactivate_content',
          reactivateContent(app.tokenAddress as Address, content.contentId),
          ctx.tick
        );
      }
    }

    return null;
  }

  /**
   * Simulate sales happening
   */
  private simulateSales(ctx: TickContext): void {
    for (const content of this.contentItems) {
      if (!content.active) continue;

      // Simulate sale with probability based on price
      // Lower price = higher chance
      const saleProbability = 0.05 / (Number(content.price) / 1e18);
      
      if (ctx.rng.nextFloat() < saleProbability) {
        content.salesCount++;
        content.totalRevenue += content.price;
        this.totalRevenue += content.price;

        ctx.logger.debug(
          { 
            agent: this.id, 
            contentId: content.contentId.toString(),
            sales: content.salesCount,
            revenue: this.formatElta(content.totalRevenue)
          },
          'Content sale recorded'
        );
      }
    }
  }

  /**
   * Get creator statistics
   */
  getSimStats(): {
    contentCount: number;
    activeContent: number;
    totalRevenue: bigint;
    totalSales: number;
    limitedEditions: number;
  } {
    return {
      contentCount: this.contentItems.length,
      activeContent: this.contentItems.filter(c => c.active).length,
      totalRevenue: this.totalRevenue,
      totalSales: this.contentItems.reduce((sum, c) => sum + c.salesCount, 0),
      limitedEditions: this.contentItems.filter(c => c.limitedEdition).length,
    };
  }
}
