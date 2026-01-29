/**
 * CollectorAgent - Purchases NFT content
 *
 * Behavior:
 * - Buys content across apps
 * - Tracks collection value
 * - Feature gate aware purchases
 * - Manages content portfolio
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import { purchaseContent } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Content ownership tracking
 */
interface OwnedContent {
  contentId: bigint;
  storeAddress: Address;
  appId: string;
  purchasePrice: bigint;
  purchasedAt: number;
  tokenId: bigint;
}

/**
 * Available content for purchase
 */
interface AvailableContent {
  contentId: bigint;
  storeAddress: Address;
  appId: string;
  price: bigint;
  paymentToken: Address;
  remainingSupply: bigint;
}

/**
 * Parameters for CollectorAgent
 */
export interface CollectorAgentParams extends BaseProtocolAgentParams {
  /** Probability of purchasing content each tick */
  purchaseProbability?: number;
  /** Maximum price willing to pay */
  maxPurchasePrice?: bigint;
  /** Target collection size */
  targetCollectionSize?: number;
  /** Prefer rare/limited content */
  preferRare?: boolean;
}

/**
 * Agent that collects NFT content from apps
 */
export class CollectorAgent extends BaseProtocolAgent {
  /** Track owned content */
  private collection: Map<bigint, OwnedContent> = new Map();

  /** Known available content */
  private availableContent: Map<bigint, AvailableContent> = new Map();

  /** Total spent on content */
  private totalSpent = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const purchaseProb = (this.params.purchaseProbability as number | undefined) ?? 0.25;
    const maxPrice = (this.params.maxPurchasePrice as bigint | undefined) ?? BigInt(50e18);
    const targetSize = (this.params.targetCollectionSize as number | undefined) ?? 20;
    const preferRare = (this.params.preferRare as boolean | undefined) ?? true;

    // Check if we should purchase
    if (this.collection.size >= targetSize) return null;
    if (!this.shouldAct(ctx, purchaseProb)) return null;

    // Consider purchasing content
    const purchaseAction = this.considerPurchasingContent(ctx, maxPrice, preferRare);
    if (purchaseAction) return purchaseAction;

    return null;
  }

  /**
   * Consider purchasing content
   */
  private considerPurchasingContent(
    ctx: TickContext,
    maxPrice: bigint,
    preferRare: boolean
  ): Action | null {
    // Filter affordable content we don't own
    const ownedIds = new Set(Array.from(this.collection.keys()).map((id) => id.toString()));
    const affordable = Array.from(this.availableContent.values()).filter((content) => {
      if (ownedIds.has(content.contentId.toString())) return false;
      if (content.price > maxPrice) return false;
      if (content.remainingSupply <= 0n) return false;
      // Check if we can afford it
      return this.hasEnoughElta(content.price);
    });

    if (affordable.length === 0) return null;

    // Sort by rarity preference
    let candidates = affordable;
    if (preferRare) {
      candidates = [...affordable].sort((a, b) => Number(a.remainingSupply - b.remainingSupply));
    }

    // Pick content to purchase
    const content = preferRare ? candidates[0]! : ctx.rng.pickOne(candidates);

    ctx.logger.info(
      {
        agent: this.id,
        contentId: content.contentId.toString(),
        app: content.appId,
        price: this.formatElta(content.price),
        remaining: content.remainingSupply.toString(),
      },
      'Purchasing content'
    );

    return this.createAction(
      'purchase_content',
      purchaseContent(content.storeAddress, content.contentId, content.paymentToken, content.price),
      ctx.tick
    );
  }

  /**
   * Record a content purchase
   */
  recordPurchase(
    contentId: bigint,
    storeAddress: Address,
    appId: string,
    price: bigint,
    tokenId: bigint,
    tick: number
  ): void {
    this.collection.set(contentId, {
      contentId,
      storeAddress,
      appId,
      purchasePrice: price,
      purchasedAt: tick,
      tokenId,
    });

    this.totalSpent += price;

    // Update remaining supply
    const available = this.availableContent.get(contentId);
    if (available && available.remainingSupply > 0n) {
      available.remainingSupply--;
    }

    // Record in base class tracking
    this.recordContentPurchase(storeAddress, tokenId);
  }

  /**
   * Register available content for purchase
   */
  registerAvailableContent(
    contentId: bigint,
    storeAddress: Address,
    appId: string,
    price: bigint,
    paymentToken: Address,
    remainingSupply: bigint
  ): void {
    this.availableContent.set(contentId, {
      contentId,
      storeAddress,
      appId,
      price,
      paymentToken,
      remainingSupply,
    });
  }

  /**
   * Get collection size
   */
  getCollectionSize(): number {
    return this.collection.size;
  }

  /**
   * Get total spent on content
   */
  getTotalSpent(): bigint {
    return this.totalSpent;
  }

  /**
   * Get collection value (sum of purchase prices)
   */
  getCollectionValue(): bigint {
    let total = 0n;
    for (const item of this.collection.values()) {
      total += item.purchasePrice;
    }
    return total;
  }

  /**
   * Get owned content for an app
   */
  getContentForApp(appId: string): OwnedContent[] {
    return Array.from(this.collection.values()).filter((c) => c.appId === appId);
  }
}
