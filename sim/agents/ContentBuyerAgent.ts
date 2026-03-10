/**
 * ContentBuyerAgent - Purchases in-app content
 *
 * Behavior:
 * - Browses available content listings
 * - Purchases content based on preferences
 * - Generates content revenue for apps
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import { purchaseContent } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Content listing info
 */
interface ContentListing {
  contentId: bigint;
  price: bigint;
  contentStoreAddress: Address;
  paymentToken: Address;
  purchased: boolean;
}

/**
 * Parameters for ContentBuyerAgent
 */
export interface ContentBuyerAgentParams extends BaseProtocolAgentParams {
  /** Maximum spend per content item (default 10 ELTA) */
  maxContentPrice?: bigint;
  /** Purchase frequency (default 0.15) */
  purchaseFrequency?: number;
  /** Preferred apps for content (empty = all) */
  preferredApps?: string[];
  /** Budget percentage for content (default 0.1 = 10% of balance) */
  contentBudget?: number;
}

/**
 * Content buyer - generates content commerce
 */
export class ContentBuyerAgent extends BaseProtocolAgent {
  /** Known content listings */
  private knownContent: Map<string, ContentListing[]> = new Map();

  /** Purchase history */
  private purchaseHistory: Array<{ appId: string; contentId: bigint; price: bigint }> = [];

  /** Total spent on content */
  private totalSpent = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const maxPrice = (this.params.maxContentPrice as bigint | undefined) ?? BigInt(10e18);
    const frequency = (this.params.purchaseFrequency as number | undefined) ?? 0.15;
    const budget = (this.params.contentBudget as number | undefined) ?? 0.1;

    // Discover new content periodically
    if (this.shouldAct(ctx, 0.1)) {
      this.discoverContent(ctx, maxPrice);
    }

    // Make purchases
    if (this.shouldAct(ctx, frequency)) {
      return this.purchaseContentItem(ctx, maxPrice, budget);
    }

    return null;
  }

  /**
   * Discover available content from apps
   */
  private discoverContent(_ctx: TickContext, maxPrice: bigint): void {
    const preferredApps = this.params.preferredApps as string[] | undefined;
    
    for (const [appId, app] of this.getAllApps()) {
      // Skip non-preferred apps if preference set
      if (preferredApps && preferredApps.length > 0 && !preferredApps.includes(appId)) {
        continue;
      }

      // Simulate discovering content listings
      // In reality, would query ContentStore contract
      let listings = this.knownContent.get(appId);
      if (!listings) {
        listings = [];
        this.knownContent.set(appId, listings);
      }

      // Add simulated content if not many known
      if (listings.length < 5) {
        const newContentId = BigInt(listings.length + 1);
        const randomPrice = BigInt(Math.floor(Math.random() * Number(maxPrice)));
        
        listings.push({
          contentId: newContentId,
          price: randomPrice > 0n ? randomPrice : BigInt(1e18),
          contentStoreAddress: app.tokenAddress as Address, // Simplified
          paymentToken: this.getWorldState().elta as Address,
          purchased: false,
        });
      }
    }
  }

  /**
   * Purchase a content item
   */
  private purchaseContentItem(
    ctx: TickContext,
    maxPrice: bigint,
    budgetPct: number
  ): Action | null {
    const balance = this.getEltaBalance();
    const budgetAmount = BigInt(Math.floor(Number(balance) * budgetPct));

    if (budgetAmount < BigInt(1e18)) return null;

    // Find unpurchased content within budget
    const candidates: Array<{ appId: string; listing: ContentListing }> = [];

    for (const [appId, listings] of this.knownContent) {
      for (const listing of listings) {
        if (!listing.purchased && listing.price <= maxPrice && listing.price <= budgetAmount) {
          candidates.push({ appId, listing });
        }
      }
    }

    if (candidates.length === 0) return null;

    // Pick random content to purchase
    const target = ctx.rng.pickOne(candidates);
    
    // Mark as purchased
    target.listing.purchased = true;

    // Track purchase
    this.purchaseHistory.push({
      appId: target.appId,
      contentId: target.listing.contentId,
      price: target.listing.price,
    });
    this.totalSpent += target.listing.price;

    ctx.logger.info(
      { 
        agent: this.id, 
        app: target.appId,
        contentId: target.listing.contentId.toString(),
        price: this.formatElta(target.listing.price),
        totalPurchases: this.purchaseHistory.length
      },
      'Purchasing content'
    );

    return this.createAction(
      'purchase_content',
      purchaseContent(
        target.listing.contentStoreAddress,
        target.listing.contentId,
        target.listing.paymentToken,
        target.listing.price
      ),
      ctx.tick
    );
  }

  /**
   * Get buyer statistics
   */
  getSimStats(): {
    totalPurchases: number;
    totalSpent: bigint;
    appsUsed: string[];
  } {
    const appsUsed = [...new Set(this.purchaseHistory.map(p => p.appId))];
    return {
      totalPurchases: this.purchaseHistory.length,
      totalSpent: this.totalSpent,
      appsUsed,
    };
  }
}
