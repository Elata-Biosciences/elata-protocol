/**
 * User Agent Types for Elata Protocol
 *
 * Different types of users with varying behaviors:
 * - BasicUserAgent: Regular user, buys/sells tokens, stakes
 * - WhaleUserAgent: Large holder, bigger trades, market moving
 * - CautiousUserAgent: Risk-averse, small trades, holds long
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import {
  buyAppToken,
  claimAppRewards,
  claimRewards,
  lockVeElta,
  sellAppToken,
  stakeAppToken,
  purchaseContent,
  enterTournament,
  setReferrer,
  castVote,
  delegateVotes,
} from '../actions/index.js';
import type { AppState } from '../packs/EltaPack.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Parameters for BasicUserAgent
 */
export interface BasicUserAgentParams extends BaseProtocolAgentParams {
  /** Probability of buying each tick (0-1) */
  buyProbability?: number;
  /** Probability of selling each tick (0-1) */
  sellProbability?: number;
  /** Probability of staking veELTA (0-1) */
  stakeProbability?: number;
  /** Probability of staking app tokens (0-1) */
  appStakeProbability?: number;
  /** Probability of claiming rewards (0-1) */
  claimProbability?: number;
  /** Minimum ELTA to buy */
  minBuyAmount?: bigint;
  /** Maximum ELTA to buy */
  maxBuyAmount?: bigint;
  /** Lock duration for veELTA in days */
  lockDurationDays?: number;
  // --- NEW MULTIFACETED PARAMS ---
  /** Probability of purchasing content (0-1) */
  contentPurchaseProbability?: number;
  /** Probability of entering tournaments (0-1) */
  tournamentProbability?: number;
  /** Probability of governance activities (0-1) */
  governanceProbability?: number;
  /** Referrer address to set (if any) */
  referrer?: Address;
}

/**
 * Basic user agent - regular trading behavior (ENHANCED with multifaceted behaviors)
 *
 * Behavior:
 * - Randomly buys app tokens when has ELTA
 * - Sells tokens when holding at profit
 * - Occasionally stakes ELTA for veELTA
 * - Claims rewards when available
 * NEW:
 * - Purchases in-app content
 * - Enters tournaments
 * - Participates in governance
 * - Uses referral system
 */
export class BasicUserAgent extends BaseProtocolAgent {
  /** Track positions for P&L calculation */
  private positions: Map<string, { amount: bigint; avgCost: bigint }> = new Map();

  /** Track if referrer has been set */
  private referrerSet = false;

  /** Known proposal IDs to vote on */
  private knownProposals: bigint[] = [];

  /** Tournaments entered */
  private tournamentsEntered = 0;

  /** Content purchased */
  private contentPurchased = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    // Get parameters with defaults
    const buyProb = (this.params.buyProbability as number | undefined) ?? 0.3;
    const sellProb = (this.params.sellProbability as number | undefined) ?? 0.2;
    const stakeProb = (this.params.stakeProbability as number | undefined) ?? 0.05;
    const appStakeProb = (this.params.appStakeProbability as number | undefined) ?? 0.03;
    const claimProb = (this.params.claimProbability as number | undefined) ?? 0.02;
    // New params
    const contentProb = (this.params.contentPurchaseProbability as number | undefined) ?? 0.03;
    const tournamentProb = (this.params.tournamentProbability as number | undefined) ?? 0.02;
    const governanceProb = (this.params.governanceProbability as number | undefined) ?? 0.01;
    const referrer = this.params.referrer as Address | undefined;

    // Priority 0: Set referrer once
    if (!this.referrerSet && referrer) {
      this.referrerSet = true;
      return this.createAction('set_referrer', setReferrer(referrer), ctx.tick);
    }

    // Decide what to do this tick
    const roll = ctx.rng.nextFloat();

    let cumProb = 0;

    // Priority 1: Sell if holding tokens at profit
    cumProb += sellProb;
    if (roll < cumProb) {
      const sellAction = this.considerSelling(ctx);
      if (sellAction) return sellAction;
    }

    // Priority 2: Buy if has ELTA and good opportunity
    cumProb += buyProb;
    if (roll < cumProb) {
      const buyAction = this.considerBuying(ctx);
      if (buyAction) return buyAction;
    }

    // Priority 3: Stake ELTA for veELTA
    cumProb += stakeProb;
    if (roll < cumProb) {
      const stakeAction = this.considerStaking(ctx);
      if (stakeAction) return stakeAction;
    }

    // Priority 4: Stake app tokens in vaults
    cumProb += appStakeProb;
    if (roll < cumProb) {
      const appStakeAction = this.considerAppStaking(ctx);
      if (appStakeAction) return appStakeAction;
    }

    // Priority 5: Claim rewards
    cumProb += claimProb;
    if (roll < cumProb) {
      const claimAction = this.considerClaimingRewards(ctx);
      if (claimAction) return claimAction;
    }

    // Priority 6: Purchase content (NEW)
    cumProb += contentProb;
    if (roll < cumProb) {
      const contentAction = this.considerPurchasingContent(ctx);
      if (contentAction) return contentAction;
    }

    // Priority 7: Enter tournament (NEW)
    cumProb += tournamentProb;
    if (roll < cumProb) {
      const tournamentAction = this.considerEnteringTournament(ctx);
      if (tournamentAction) return tournamentAction;
    }

    // Priority 8: Governance activities (NEW)
    cumProb += governanceProb;
    if (roll < cumProb) {
      const govAction = this.considerGovernance(ctx);
      if (govAction) return govAction;
    }

    // Otherwise, do nothing
    return null;
  }

  /**
   * Consider purchasing in-app content (NEW)
   */
  private considerPurchasingContent(ctx: TickContext): Action | null {
    const maxContentPrice = BigInt(10e18);
    const balance = this.getEltaBalance();

    if (balance < maxContentPrice) return null;

    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    const [appId, app] = ctx.rng.pickOne(apps);
    const price = BigInt(Math.floor(Math.random() * Number(maxContentPrice / 2n))) + BigInt(1e18);

    this.contentPurchased++;

    ctx.logger.debug(
      { agent: this.id, app: appId, price: this.formatElta(price) },
      'Purchasing content'
    );

    return this.createAction(
      'purchase_content',
      purchaseContent(
        app.tokenAddress as Address,
        BigInt(this.contentPurchased),
        this.getWorldState().elta,
        price
      ),
      ctx.tick
    );
  }

  /**
   * Consider entering a tournament (NEW)
   */
  private considerEnteringTournament(ctx: TickContext): Action | null {
    const maxEntryFee = BigInt(20e18);
    const balance = this.getEltaBalance();

    if (balance < maxEntryFee) return null;

    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    const [appId, app] = ctx.rng.pickOne(apps);
    const entryFee = BigInt(Math.floor(Math.random() * Number(maxEntryFee / 2n))) + BigInt(5e18);

    const tournamentAddr = `0x${Array(40).fill(0).map(() => 
      Math.floor(Math.random() * 16).toString(16)).join('')}` as Address;

    this.tournamentsEntered++;

    ctx.logger.debug(
      { agent: this.id, app: appId, entryFee: this.formatElta(entryFee) },
      'Entering tournament'
    );

    return this.createAction(
      'enter_tournament',
      enterTournament(tournamentAddr, app.tokenAddress, entryFee),
      ctx.tick
    );
  }

  /**
   * Consider governance activities (NEW)
   */
  private considerGovernance(ctx: TickContext): Action | null {
    // Need veELTA to participate in governance
    if (this.getVeEltaBalance() === 0n) {
      // Delegate to self to enable voting
      ctx.logger.debug({ agent: this.id }, 'Delegating voting power to self');
      return this.createAction(
        'delegate_votes',
        delegateVotes(this.getAddress() as Address),
        ctx.tick
      );
    }

    // Simulate discovering a proposal
    if (ctx.rng.nextFloat() < 0.5) {
      this.knownProposals.push(BigInt(this.knownProposals.length + 1));
    }

    // Vote on known proposals
    if (this.knownProposals.length > 0) {
      const proposalId = ctx.rng.pickOne(this.knownProposals);
      
      // Remove from list (voted)
      this.knownProposals = this.knownProposals.filter(p => p !== proposalId);

      // Random vote: 70% for, 20% abstain, 10% against
      const vote: 0 | 1 | 2 = ctx.rng.nextFloat() < 0.7 ? 1 : ctx.rng.nextFloat() < 0.66 ? 2 : 0;

      ctx.logger.debug(
        { agent: this.id, proposalId: proposalId.toString(), vote: vote === 1 ? 'For' : vote === 0 ? 'Against' : 'Abstain' },
        'Voting on proposal'
      );

      return this.createAction(
        'cast_vote',
        castVote(proposalId, vote),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Consider buying app tokens
   */
  private considerBuying(ctx: TickContext): Action | null {
    const minBuy = (this.params.minBuyAmount as bigint | undefined) ?? BigInt(1e18); // 1 ELTA
    const maxBuy = (this.params.maxBuyAmount as bigint | undefined) ?? BigInt(100e18); // 100 ELTA

    // Check if we have enough ELTA
    if (!this.hasEnoughElta(minBuy)) {
      return null;
    }

    // Choose an app to buy
    const app = this.shouldAct(ctx, 0.7) ? this.chooseAppWithMomentum() : this.chooseRandomApp(ctx);

    if (!app || app.graduated) {
      return null;
    }

    // Calculate buy amount
    const available = this.getEltaBalance();
    const amount = this.calculateTradeAmount(available, ctx);

    // Clamp to min/max
    const finalAmount = amount < minBuy ? minBuy : amount > maxBuy ? maxBuy : amount;

    if (!this.hasEnoughElta(finalAmount)) {
      return null;
    }

    ctx.logger.debug(
      { agent: this.id, app: app.id, amount: this.formatElta(finalAmount) },
      'Buying app tokens'
    );

    return this.createAction(
      'buy_app_token',
      buyAppToken(String(app.id), app.tokenAddress, finalAmount),
      ctx.tick
    );
  }

  /**
   * Consider selling app tokens
   */
  private considerSelling(ctx: TickContext): Action | null {
    // Find positions we're holding
    const holdings: Array<{ appId: string; app: AppState; balance: bigint }> = [];

    for (const [appId, balance] of this.appTokenBalances) {
      if (balance > 0n) {
        const app = this.getAppState(appId);
        if (app) {
          holdings.push({ appId, app, balance });
        }
      }
    }

    if (holdings.length === 0) {
      return null;
    }

    // Choose a random holding to potentially sell
    const holding = ctx.rng.pickOne(holdings);

    // Check if we're in profit (simple heuristic)
    const position = this.positions.get(holding.appId);
    if (position && holding.app.tokenPrice > position.avgCost) {
      // In profit, more likely to sell
      if (this.shouldAct(ctx, 0.6)) {
        const sellAmount = this.calculateTradeAmount(holding.balance, ctx, 0.5);

        ctx.logger.debug(
          { agent: this.id, app: holding.appId, amount: sellAmount.toString() },
          'Selling app tokens at profit'
        );

        return this.createAction(
          'sell_app_token',
          sellAppToken(holding.appId, holding.app.tokenAddress, sellAmount),
          ctx.tick
        );
      }
    }

    return null;
  }

  /**
   * Consider staking ELTA for veELTA
   */
  private considerStaking(ctx: TickContext): Action | null {
    const lockDays = (this.params.lockDurationDays as number | undefined) ?? 90;

    // Only stake if we have significant ELTA and no veELTA yet
    const minStake = BigInt(100e18); // 100 ELTA
    if (this.getEltaBalance() < minStake || this.getVeEltaBalance() > 0n) {
      return null;
    }

    // Stake a portion of balance
    const stakeAmount = this.calculateTradeAmount(this.getEltaBalance(), ctx, 0.3);

    if (stakeAmount < minStake) {
      return null;
    }

    const durationSeconds = lockDays * 24 * 60 * 60;

    ctx.logger.debug(
      { agent: this.id, amount: this.formatElta(stakeAmount), lockDays },
      'Staking ELTA for veELTA'
    );

    return this.createAction('lock_veelta', lockVeElta(stakeAmount, durationSeconds), ctx.tick);
  }

  /**
   * Consider staking app tokens in vaults
   */
  private considerAppStaking(ctx: TickContext): Action | null {
    // Find apps where we hold tokens
    for (const [appId, balance] of this.appTokenBalances) {
      if (balance > BigInt(100e18)) {
        const app = this.getAppState(appId);
        if (app) {
          // Stake half of our tokens
          const stakeAmount = balance / 2n;

          ctx.logger.debug(
            { agent: this.id, app: appId, amount: stakeAmount.toString() },
            'Staking app tokens'
          );

          return this.createAction(
            'stake_app_token',
            stakeAppToken(appId, app.tokenAddress, stakeAmount),
            ctx.tick
          );
        }
      }
    }
    return null;
  }

  /**
   * Consider claiming rewards (veELTA or app rewards)
   */
  private considerClaimingRewards(ctx: TickContext): Action | null {
    // Claim veELTA rewards if we have veELTA
    if (this.getVeEltaBalance() > 0n) {
      ctx.logger.debug({ agent: this.id }, 'Claiming veELTA rewards');
      return this.createAction('claim_rewards', claimRewards(), ctx.tick);
    }

    // Claim app rewards if we have staked app tokens
    for (const [appId, balance] of this.appTokenBalances) {
      if (balance > 0n) {
        const app = this.getAppState(appId);
        if (app) {
          ctx.logger.debug({ agent: this.id, app: appId }, 'Claiming app rewards');
          return this.createAction(
            'claim_app_rewards',
            claimAppRewards(appId, app.tokenAddress),
            ctx.tick
          );
        }
      }
    }

    return null;
  }

  /**
   * Update position tracking after buy
   */
  onBuyExecuted(appId: string, amount: bigint, cost: bigint): void {
    const existing = this.positions.get(appId);
    if (existing) {
      // Update average cost
      const totalAmount = existing.amount + amount;
      const totalCost = existing.avgCost * existing.amount + cost;
      this.positions.set(appId, {
        amount: totalAmount,
        avgCost: totalCost / totalAmount,
      });
    } else {
      this.positions.set(appId, {
        amount,
        avgCost: cost / amount,
      });
    }
  }
}

/**
 * Parameters for WhaleUserAgent
 */
export interface WhaleUserAgentParams extends BasicUserAgentParams {
  /** Minimum trade size in ELTA */
  minTradeSize?: bigint;
  /** Whether to front-run momentum */
  momentumTrading?: boolean;
}

/**
 * Whale user agent - large holder with market-moving trades (ENHANCED)
 *
 * Behavior:
 * - Makes larger trades that can move prices
 * - More strategic about entry/exit timing
 * - Longer lock periods for veELTA
 * NEW:
 * - Creates premium content
 * - Sponsors tournaments
 * - Active governance participant
 * - Market maker behavior
 */
export class WhaleUserAgent extends BaseProtocolAgent {
  /** Has delegated voting power */
  private hasDelegated = false;

  /** Tournaments sponsored */
  private tournamentsSponsored = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const minTrade = (this.params.minTradeSize as bigint | undefined) ?? BigInt(1000e18);
    const momentumTrading = (this.params.momentumTrading as boolean | undefined) ?? true;

    // Whales are more selective - lower action probability but bigger impact
    if (!this.shouldAct(ctx, 0.4)) {
      return null;
    }

    const roll = ctx.rng.nextFloat();

    // NEW: Governance participation (whales have influence)
    if (roll < 0.1 && this.getVeEltaBalance() > BigInt(1000e18)) {
      const govAction = this.whaleGovernance(ctx);
      if (govAction) return govAction;
    }

    // NEW: Sponsor tournaments (marketing)
    if (roll < 0.15) {
      const sponsorAction = this.sponsorTournament(ctx);
      if (sponsorAction) return sponsorAction;
    }

    // NEW: Market making (buy/sell to create liquidity)
    if (roll < 0.25 && this.hasEnoughElta(minTrade)) {
      const mmAction = this.marketMake(ctx, minTrade);
      if (mmAction) return mmAction;
    }

    // Choose target app
    let app = momentumTrading
      ? this.chooseAppWithMomentum(1000) // Momentum traders look for price action
      : this.chooseRandomApp(ctx); // Non-momentum traders buy any app

    // Fallback to random app if momentum trading finds nothing
    if (!app) {
      app = this.chooseRandomApp(ctx);
    }

    // Execute large buy if we have an app and enough ELTA
    if (app && !app.graduated && this.hasEnoughElta(minTrade)) {
      const amount = minTrade + this.calculateTradeAmount(this.getEltaBalance() - minTrade, ctx);

      ctx.logger.info(
        { agent: this.id, app: app.id, amount: this.formatElta(amount) },
        'Whale buying'
      );

      return this.createAction(
        'buy_app_token',
        buyAppToken(String(app.id), app.tokenAddress, amount),
        ctx.tick
      );
    }

    // Fallback: might stake for long term
    if (this.getVeEltaBalance() === 0n && this.hasEnoughElta(minTrade * 10n)) {
      const stakeAmount = this.getEltaBalance() / 4n; // 25% of holdings
      const lockDays = 365 * 2; // Max lock for 2x boost

      ctx.logger.info(
        { agent: this.id, amount: this.formatElta(stakeAmount), lockDays },
        'Whale locking veELTA'
      );

      return this.createAction(
        'lock_veelta',
        lockVeElta(stakeAmount, lockDays * 24 * 60 * 60),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Whale governance activities (NEW)
   */
  private whaleGovernance(ctx: TickContext): Action | null {
    // Delegate to self first
    if (!this.hasDelegated) {
      this.hasDelegated = true;
      return this.createAction(
        'delegate_votes',
        delegateVotes(this.getAddress() as Address),
        ctx.tick
      );
    }

    // Vote on simulated proposal (whales vote strategically - mostly for)
    const proposalId = BigInt(Math.floor(Math.random() * 100) + 1);
    const vote: 0 | 1 | 2 = ctx.rng.nextFloat() < 0.85 ? 1 : 0; // 85% for, 15% against

    ctx.logger.info(
      { agent: this.id, proposalId: proposalId.toString(), vote: vote === 1 ? 'For' : 'Against' },
      'Whale voting'
    );

    return this.createAction('cast_vote', castVote(proposalId, vote), ctx.tick);
  }

  /**
   * Sponsor a tournament (NEW)
   */
  private sponsorTournament(ctx: TickContext): Action | null {
    const minSponsor = BigInt(500e18);
    if (!this.hasEnoughElta(minSponsor)) return null;

    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    const [appId, app] = ctx.rng.pickOne(apps);
    const sponsorAmount = BigInt(Math.floor(Math.random() * Number(minSponsor))) + minSponsor;

    this.tournamentsSponsored++;

    ctx.logger.info(
      { agent: this.id, app: appId, amount: this.formatElta(sponsorAmount) },
      'Whale sponsoring tournament'
    );

    // For now, sponsoring is implemented as entering with large amount
    const tournamentAddr = `0x${Array(40).fill(0).map(() => 
      Math.floor(Math.random() * 16).toString(16)).join('')}` as Address;

    return this.createAction(
      'enter_tournament',
      enterTournament(tournamentAddr, app.tokenAddress, sponsorAmount),
      ctx.tick
    );
  }

  /**
   * Market making behavior (NEW)
   */
  private marketMake(ctx: TickContext, minTrade: bigint): Action | null {
    // Check if we have positions to rebalance
    const holdings = Array.from(this.appTokenBalances.entries())
      .filter(([_, balance]) => balance > minTrade);

    if (holdings.length > 0 && ctx.rng.nextFloat() < 0.4) {
      // Sell some to create sell-side liquidity
      const [appId, balance] = ctx.rng.pickOne(holdings);
      const app = this.getAppState(appId);
      if (app) {
        const sellAmount = balance / 4n; // Sell 25%

        ctx.logger.debug(
          { agent: this.id, app: appId, amount: this.formatElta(sellAmount) },
          'Whale market making (sell side)'
        );

        return this.createAction(
          'sell_app_token',
          sellAppToken(appId, app.tokenAddress, sellAmount),
          ctx.tick
        );
      }
    }

    return null;
  }
}

/**
 * Cautious user agent - risk-averse behavior
 *
 * Behavior:
 * - Small trade sizes
 * - Only buys established apps
 * - Rarely sells (holds long)
 * - Prefers staking over trading
 */
export class CautiousUserAgent extends BaseProtocolAgent {
  async step(ctx: TickContext): Promise<Action | null> {
    // Very low action probability
    if (!this.shouldAct(ctx, 0.1)) {
      return null;
    }

    // Prefer staking
    if (this.getVeEltaBalance() === 0n && this.hasEnoughElta(BigInt(50e18))) {
      const stakeAmount = this.getEltaBalance() / 2n; // 50% to veELTA
      const lockDays = 180; // 6 months

      return this.createAction(
        'lock_veelta',
        lockVeElta(stakeAmount, lockDays * 24 * 60 * 60),
        ctx.tick
      );
    }

    // Only buy from established apps (high raise)
    const apps = Array.from(this.getAllApps().values());
    const established = apps.filter((a) => a.totalRaised > BigInt(10000e18) && !a.graduated);

    if (established.length > 0 && this.hasEnoughElta(BigInt(10e18))) {
      const app = ctx.rng.pickOne(established);
      const amount = BigInt(10e18); // Small fixed amount

      return this.createAction(
        'buy_app_token',
        buyAppToken(String(app.id), app.tokenAddress, amount),
        ctx.tick
      );
    }

    return null;
  }
}

// Export all user agent types
export { BasicUserAgent as UserAgent };
