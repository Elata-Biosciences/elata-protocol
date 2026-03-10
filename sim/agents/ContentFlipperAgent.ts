/**
 * ContentFlipperAgent - Buys content to resell for profit
 *
 * Behavior:
 * - Identifies undervalued content
 * - Purchases with intent to resell
 * - Generates secondary market activity
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { purchaseContent, listContent } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Flip position tracking
 */
interface FlipPosition {
  appId: string;
  contentId: bigint;
  purchasePrice: bigint;
  purchaseTick: number;
  targetPrice: bigint;
  listed: boolean;
  sold: boolean;
}

/**
 * Parameters for ContentFlipperAgent
 */
export interface ContentFlipperAgentParams extends BaseProtocolAgentParams {
  /** Minimum profit margin (default 0.2 = 20%) */
  minProfitMargin?: number;
  /** Maximum positions (default 10) */
  maxPositions?: number;
  /** Hold time in ticks before listing (default 5) */
  holdTime?: number;
  /** Maximum purchase price (default 20 ELTA) */
  maxPurchasePrice?: bigint;
}

/**
 * Content flipper for secondary market
 */
export class ContentFlipperAgent extends BaseProtocolAgent {
  /** Current flip positions */
  private positions: FlipPosition[] = [];

  /** Completed flips */
  private completedFlips = 0;

  /** Total profit (simulated) */
  private totalProfit = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const minMargin = (this.params.minProfitMargin as number | undefined) ?? 0.2;
    const maxPositions = (this.params.maxPositions as number | undefined) ?? 10;
    const holdTime = (this.params.holdTime as number | undefined) ?? 5;
    const maxPrice = (this.params.maxPurchasePrice as bigint | undefined) ?? BigInt(20e18);

    // Priority 1: List held items after hold period
    if (this.shouldAct(ctx, 0.4)) {
      const listAction = this.listForSale(ctx, holdTime, minMargin);
      if (listAction) return listAction;
    }

    // Priority 2: Simulate sales (mark as sold with some probability)
    this.checkSales(ctx);

    // Priority 3: Buy new items to flip
    const activePositions = this.positions.filter(p => !p.sold);
    if (activePositions.length < maxPositions && this.shouldAct(ctx, 0.25)) {
      return this.buyToFlip(ctx, maxPrice, minMargin);
    }

    return null;
  }

  /**
   * Buy content with intent to flip
   */
  private buyToFlip(ctx: TickContext, maxPrice: bigint, minMargin: number): Action | null {
    const balance = this.getEltaBalance();
    if (balance < maxPrice / 2n) return null;

    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    const [appId, app] = ctx.rng.pickOne(apps);

    // Simulate finding undervalued content
    const basePrice = BigInt(Math.floor(Math.random() * Number(maxPrice)));
    const purchasePrice = basePrice > 0n ? basePrice : BigInt(2e18);

    if (purchasePrice > balance) return null;

    // Calculate target sell price with margin
    const targetPrice = BigInt(Math.floor(Number(purchasePrice) * (1 + minMargin + Math.random() * 0.3)));

    const contentId = BigInt(this.positions.length + 1);

    // Track position
    this.positions.push({
      appId,
      contentId,
      purchasePrice,
      purchaseTick: ctx.tick,
      targetPrice,
      listed: false,
      sold: false,
    });

    ctx.logger.debug(
      { 
        agent: this.id, 
        app: appId,
        purchasePrice: this.formatElta(purchasePrice),
        targetPrice: this.formatElta(targetPrice)
      },
      'Buying content to flip'
    );

    return this.createAction(
      'purchase_content',
      purchaseContent(
        app.tokenAddress as Address,
        contentId,
        this.getWorldState().elta as Address,
        purchasePrice
      ),
      ctx.tick
    );
  }

  /**
   * List held items for sale
   */
  private listForSale(ctx: TickContext, holdTime: number, _minMargin: number): Action | null {
    for (const position of this.positions) {
      if (position.listed || position.sold) continue;
      if (ctx.tick - position.purchaseTick < holdTime) continue;

      const app = this.getAppState(position.appId);
      if (!app) continue;

      // Mark as listed
      position.listed = true;

      ctx.logger.debug(
        { 
          agent: this.id, 
          app: position.appId,
          contentId: position.contentId.toString(),
          listPrice: this.formatElta(position.targetPrice)
        },
        'Listing content for sale'
      );

      return this.createAction(
        'list_content',
        listContent(
          app.tokenAddress as Address,
          `ipfs://content-${position.contentId}`,
          position.targetPrice,
          1, // ELTA payment
          1n // Max supply 1 for resale
        ),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Simulate sales happening
   */
  private checkSales(ctx: TickContext): void {
    for (const position of this.positions) {
      if (!position.listed || position.sold) continue;

      // Simulate sale with some probability
      if (ctx.rng.nextFloat() < 0.1) {
        position.sold = true;
        this.completedFlips++;
        
        const profit = position.targetPrice - position.purchasePrice;
        this.totalProfit += profit;

        ctx.logger.info(
          { 
            agent: this.id, 
            profit: this.formatElta(profit),
            totalFlips: this.completedFlips
          },
          'Content flip completed'
        );
      }
    }
  }

  /**
   * Get flipper statistics
   */
  getSimStats(): {
    activePositions: number;
    completedFlips: number;
    totalProfit: bigint;
  } {
    return {
      activePositions: this.positions.filter(p => !p.sold).length,
      completedFlips: this.completedFlips,
      totalProfit: this.totalProfit,
    };
  }
}
