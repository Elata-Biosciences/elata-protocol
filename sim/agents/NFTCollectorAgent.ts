/**
 * NFTCollectorAgent - Collects content NFTs across apps
 *
 * Behavior:
 * - Builds curated collections
 * - Focuses on rare/limited content
 * - Tracks collection value
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import { purchaseContent } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * NFT in collection
 */
interface CollectedNFT {
  appId: string;
  contentId: bigint;
  purchasePrice: bigint;
  rarity: 'common' | 'uncommon' | 'rare' | 'legendary';
  purchaseTick: number;
}

/**
 * Parameters for NFTCollectorAgent
 */
export interface NFTCollectorAgentParams extends BaseProtocolAgentParams {
  /** Target collection size (default 20) */
  targetCollectionSize?: number;
  /** Focus on rare items (default true) */
  preferRare?: boolean;
  /** Maximum price for non-rare (default 5 ELTA) */
  maxCommonPrice?: bigint;
  /** Maximum price for rare (default 50 ELTA) */
  maxRarePrice?: bigint;
  /** Collection budget as percent of balance (default 0.3) */
  collectionBudget?: number;
}

/**
 * NFT collector building curated collections
 */
export class NFTCollectorAgent extends BaseProtocolAgent {
  /** Collected NFTs */
  private collection: CollectedNFT[] = [];

  /** Total collection cost */
  private totalCost = 0n;

  /** Estimated collection value */
  private estimatedValue = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const targetSize = (this.params.targetCollectionSize as number | undefined) ?? 20;
    const preferRare = (this.params.preferRare as boolean | undefined) ?? true;
    const maxCommon = (this.params.maxCommonPrice as bigint | undefined) ?? BigInt(5e18);
    const maxRare = (this.params.maxRarePrice as bigint | undefined) ?? BigInt(50e18);
    const budget = (this.params.collectionBudget as number | undefined) ?? 0.3;

    // Stop collecting if target reached
    if (this.collection.length >= targetSize) {
      return null;
    }

    // Collect NFTs
    if (this.shouldAct(ctx, 0.2)) {
      return this.collectNFT(ctx, preferRare, maxCommon, maxRare, budget);
    }

    return null;
  }

  /**
   * Collect an NFT
   */
  private collectNFT(
    ctx: TickContext,
    preferRare: boolean,
    maxCommon: bigint,
    maxRare: bigint,
    budgetPct: number
  ): Action | null {
    const balance = this.getEltaBalance();
    const budgetAmount = BigInt(Math.floor(Number(balance) * budgetPct));

    if (budgetAmount < BigInt(1e18)) return null;

    // Find an app with content
    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    const [appId, app] = ctx.rng.pickOne(apps);

    // Simulate discovering NFT with rarity
    const rarityRoll = ctx.rng.nextFloat();
    let rarity: CollectedNFT['rarity'];
    let price: bigint;

    if (rarityRoll > 0.95) {
      rarity = 'legendary';
      price = maxRare * 2n;
    } else if (rarityRoll > 0.85) {
      rarity = 'rare';
      price = maxRare;
    } else if (rarityRoll > 0.6) {
      rarity = 'uncommon';
      price = maxCommon * 2n;
    } else {
      rarity = 'common';
      price = maxCommon;
    }

    // Adjust price randomly
    price = BigInt(Math.floor(Number(price) * (0.5 + ctx.rng.nextFloat())));
    if (price === 0n) price = BigInt(1e18);

    // Check if we should collect based on rarity preference
    if (preferRare && rarity === 'common' && ctx.rng.nextFloat() > 0.3) {
      // Skip most common items when preferring rare
      return null;
    }

    // Check budget
    const maxPrice = rarity === 'common' || rarity === 'uncommon' ? maxCommon : maxRare;
    if (price > maxPrice || price > budgetAmount) {
      return null;
    }

    // Add to collection
    const contentId = BigInt(this.collection.length + 1);
    this.collection.push({
      appId,
      contentId,
      purchasePrice: price,
      rarity,
      purchaseTick: ctx.tick,
    });

    this.totalCost += price;
    
    // Update estimated value (rare items appreciate)
    const multiplier = rarity === 'legendary' ? 2.5 : rarity === 'rare' ? 1.5 : rarity === 'uncommon' ? 1.2 : 1.0;
    this.estimatedValue += BigInt(Math.floor(Number(price) * multiplier));

    ctx.logger.info(
      { 
        agent: this.id, 
        app: appId,
        rarity,
        price: this.formatElta(price),
        collectionSize: this.collection.length
      },
      'Collecting NFT'
    );

    return this.createAction(
      'purchase_content',
      purchaseContent(
        app.tokenAddress as Address,
        contentId,
        this.getWorldState().elta as Address,
        price
      ),
      ctx.tick
    );
  }

  /**
   * Get collection statistics
   */
  getSimStats(): {
    collectionSize: number;
    totalCost: bigint;
    estimatedValue: bigint;
    rarityBreakdown: Record<string, number>;
  } {
    const rarityBreakdown: Record<string, number> = {
      common: 0,
      uncommon: 0,
      rare: 0,
      legendary: 0,
    };

    for (const nft of this.collection) {
      const current = rarityBreakdown[nft.rarity];
      if (current !== undefined) {
        rarityBreakdown[nft.rarity] = current + 1;
      }
    }

    return {
      collectionSize: this.collection.length,
      totalCost: this.totalCost,
      estimatedValue: this.estimatedValue,
      rarityBreakdown,
    };
  }
}
