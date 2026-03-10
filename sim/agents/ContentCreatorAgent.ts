/**
 * ContentCreatorAgent - Creates in-app content
 *
 * Behavior:
 * - Lists content for sale in ContentStore
 * - Sets feature gates for premium content
 * - Manages pricing strategies
 * - Tracks content sales and revenue
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import { listContent } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Payment token type enum matching contract
 * 0 = APP token, 1 = ELTA, 2 = USDC
 */
type PaymentTokenType = 0 | 1 | 2;

/**
 * Content listing tracking
 */
interface ContentListing {
  contentId: bigint;
  storeAddress: Address;
  appId: string;
  price: bigint;
  paymentTokenType: PaymentTokenType;
  maxSupply: bigint;
  soldCount: bigint;
  revenue: bigint;
  listedAt: number;
}

/**
 * Parameters for ContentCreatorAgent
 */
export interface ContentCreatorAgentParams extends BaseProtocolAgentParams {
  /** Probability of listing content each tick */
  listProbability?: number;
  /** Base price for content (in wei) */
  basePrice?: bigint;
  /** Maximum supply per listing */
  maxSupplyPerListing?: bigint;
  /** Maximum active listings */
  maxListings?: number;
}

/**
 * Agent that creates and sells in-app content
 */
export class ContentCreatorAgent extends BaseProtocolAgent {
  /** Track content listings */
  private listings: Map<bigint, ContentListing> = new Map();

  /** Counter for content IDs (simulated) */
  private contentCounter = 0n;

  /** Revenue tracking */
  private totalRevenue = 0n;

  async step(ctx: TickContext): Promise<Action | null> {
    const listProb = (this.params.listProbability as number | undefined) ?? 0.2;
    const maxListings = (this.params.maxListings as number | undefined) ?? 10;

    // Priority 1: List new content if under max
    if (this.listings.size < maxListings && this.shouldAct(ctx, listProb)) {
      const listAction = this.considerListingContent(ctx);
      if (listAction) return listAction;
    }

    return null;
  }

  /**
   * Consider listing new content
   */
  private considerListingContent(ctx: TickContext): Action | null {
    const basePrice = (this.params.basePrice as bigint | undefined) ?? BigInt(5e18);
    const maxSupply = (this.params.maxSupplyPerListing as bigint | undefined) ?? 100n;

    // Get a content store to list on
    const stores = this.getContentStores();
    if (stores.size === 0) {
      // Try to use an app we're associated with
      const apps = Array.from(this.getAllApps().values());
      if (apps.length === 0) return null;

      // Log intent - actual store deployment would require separate action
      ctx.logger.info({ agent: this.id }, 'No content stores available, skipping content listing');
      return null;
    }

    const storeEntries = Array.from(stores.entries());
    const [appId, storeAddress] = ctx.rng.pickOne(storeEntries);

    // Vary price randomly around base
    const priceMultiplier = 0.5 + ctx.rng.nextFloat() * 1.5; // 0.5x to 2x
    const price = BigInt(Math.floor(Number(basePrice) * priceMultiplier));

    // Use ELTA as payment token type (1)
    // PaymentTokenType: 0=APP, 1=ELTA, 2=USDC
    const paymentTokenType: PaymentTokenType = 1;

    // Generate content URI
    this.contentCounter++;
    const contentUri = `ipfs://content-${this.id}-${this.contentCounter}`;

    ctx.logger.info(
      { agent: this.id, app: appId, price: this.formatElta(price), supply: maxSupply.toString() },
      'Listing content for sale'
    );

    return this.createAction(
      'list_content',
      listContent(storeAddress, contentUri, price, paymentTokenType, maxSupply),
      ctx.tick
    );
  }

  /**
   * Record a content sale
   */
  recordSale(contentId: bigint, amount: bigint): void {
    const listing = this.listings.get(contentId);
    if (listing) {
      listing.soldCount++;
      listing.revenue += amount;
      this.totalRevenue += amount;
    }
  }

  /**
   * Register a content store for an app
   */
  registerContentStore(appId: string, storeAddress: Address): void {
    this.contentStores.set(appId, storeAddress);
  }

  /**
   * Track a listing we created
   */
  trackListing(
    contentId: bigint,
    storeAddress: Address,
    appId: string,
    price: bigint,
    paymentTokenType: PaymentTokenType,
    maxSupply: bigint,
    tick: number
  ): void {
    this.listings.set(contentId, {
      contentId,
      storeAddress,
      appId,
      price,
      paymentTokenType,
      maxSupply,
      soldCount: 0n,
      revenue: 0n,
      listedAt: tick,
    });
  }

  /**
   * Get total revenue earned
   */
  getTotalRevenue(): bigint {
    return this.totalRevenue;
  }

  /**
   * Get all active listings
   */
  getListings(): ContentListing[] {
    return Array.from(this.listings.values());
  }
}
