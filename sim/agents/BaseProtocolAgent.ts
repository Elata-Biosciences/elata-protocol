/**
 * BaseProtocolAgent - Base class for all Elata Protocol agents
 *
 * Extends AgentForge's BaseAgent with Elata-specific helpers:
 * - Wallet and address management
 * - Protocol contract access
 * - Balance queries
 * - Common action helpers
 */

import { type Action, BaseAgent, type TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import type { EltaAction } from '../actions/index.js';
import type { AppState, EltaPack, EltaWorldState } from '../packs/EltaPack.js';

// ============================================
// Types for Enhanced Agent Patterns
// ============================================

/**
 * Action with associated probability
 */
export interface ProbabilityAction {
  /** The action to execute */
  action: Action;
  /** Probability weight (relative, not necessarily 0-1) */
  weight: number;
  /** Optional condition that must be true */
  condition?: boolean;
}

/**
 * Error categories for agent actions
 */
export type ErrorCategory =
  | 'insufficient_balance'
  | 'invalid_state'
  | 'contract_revert'
  | 'timeout'
  | 'network'
  | 'validation'
  | 'unknown';

/**
 * Categorized error with context
 */
export interface CategorizedError {
  category: ErrorCategory;
  message: string;
  context: Record<string, unknown>;
}

/**
 * Parameters common to all protocol agents
 */
export interface BaseProtocolAgentParams {
  /** Risk tolerance (0-1, higher = more aggressive) */
  riskTolerance?: number;
  /** Maximum percentage of balance to use per trade */
  maxTradePercent?: number;
  /** Minimum ELTA to keep in reserve */
  minEltaReserve?: bigint;
}

type DecisionMemoryPrimitive = string | number | boolean | null;

export interface DecisionMemoryOutcome {
  ok: boolean;
  error?: string;
}

export interface DecisionMemoryEntry {
  tick: number;
  decision: string;
  reason: string;
  outcome?: DecisionMemoryOutcome;
  context?: Record<string, DecisionMemoryPrimitive>;
}

export interface DecisionMemoryPayload {
  decision: string;
  reason: string;
  context?: Record<string, unknown>;
  outcome?: DecisionMemoryOutcome;
}

/**
 * Base class for Elata Protocol agents
 */
export abstract class BaseProtocolAgent extends BaseAgent {
  protected static readonly DECISION_MEMORY_HISTORY_LIMIT = 25;
  protected static readonly DECISION_MEMORY_MAX_REASON_CHARS = 120;
  protected static readonly DECISION_MEMORY_MAX_CONTEXT_KEYS = 10;
  protected static readonly DECISION_MEMORY_MAX_STRING_CHARS = 160;

  /** Agent's wallet address (set during initialize) */
  protected address: Address | null = null;

  /** Reference to the EltaPack */
  protected pack: EltaPack | null = null;

  /** Cached ELTA balance */
  protected eltaBalance = 0n;

  /** Cached veELTA balance */
  protected veEltaBalance = 0n;

  /** App token balances: appId -> balance */
  protected appTokenBalances: Map<string, bigint> = new Map();

  /**
   * Initialize the agent - register with pack and get wallet
   */
  override async initialize(ctx: TickContext): Promise<void> {
    await super.initialize(ctx);

    // Get the pack from context
    this.pack = ctx.pack as unknown as EltaPack;

    // Register with pack to get a wallet address
    this.address = await this.pack.registerAgent(this.id);

    // Fetch initial ELTA balance
    this.eltaBalance = await this.pack.getAgentEltaBalance(this.id);

    ctx.logger.debug(
      { agentId: this.id, address: this.address, eltaBalance: this.eltaBalance.toString() },
      'Agent registered'
    );
  }

  /**
   * Get agent's wallet address
   */
  getAddress(): Address {
    if (!this.address) {
      throw new Error(`Agent ${this.id} not initialized`);
    }
    return this.address;
  }

  /**
   * Get current world state
   */
  protected getWorldState(): EltaWorldState {
    if (!this.pack) {
      throw new Error(`Agent ${this.id} not initialized`);
    }
    return this.pack.getWorldState();
  }

  /**
   * Get a specific app's state
   */
  protected getAppState(appId: string): AppState | undefined {
    return this.getWorldState().apps.get(appId);
  }

  /**
   * Get all apps
   */
  protected getAllApps(): Map<string, AppState> {
    return this.getWorldState().apps;
  }

  /**
   * Get number of apps
   */
  protected getAppCount(): number {
    return this.getWorldState().appCount;
  }

  /**
   * Get ELTA balance
   */
  protected getEltaBalance(): bigint {
    return this.eltaBalance;
  }

  /**
   * Get veELTA balance
   */
  protected getVeEltaBalance(): bigint {
    return this.veEltaBalance;
  }

  /**
   * Get app token balance
   */
  protected getAppTokenBalance(appId: string): bigint {
    return this.appTokenBalances.get(appId) ?? 0n;
  }

  /**
   * Check if agent has enough ELTA for an amount
   */
  protected hasEnoughElta(amount: bigint): boolean {
    const minReserve = (this.params.minEltaReserve as bigint | undefined) ?? 0n;
    return this.eltaBalance >= amount + minReserve;
  }

  /**
   * Calculate trade amount based on risk tolerance and max trade percent
   */
  protected calculateTradeAmount(
    available: bigint,
    ctx: TickContext,
    baseMultiplier = 1.0
  ): bigint {
    const riskTolerance = (this.params.riskTolerance as number | undefined) ?? 0.5;
    const maxTradePercent = (this.params.maxTradePercent as number | undefined) ?? 0.1;

    // Scale by risk tolerance and add some randomness
    const percent = maxTradePercent * riskTolerance * baseMultiplier;
    const randomFactor = 0.5 + ctx.rng.nextFloat() * 0.5; // 0.5 to 1.0

    const amount = BigInt(Math.floor(Number(available) * percent * randomFactor));
    return amount;
  }

  /**
   * Update cached balances - call this at start of step() or after trades
   */
  protected async updateBalances(): Promise<void> {
    if (!this.pack) return;

    // Refresh ELTA balance from pack
    this.eltaBalance = await this.pack.getAgentEltaBalance(this.id);

    // Refresh veELTA balance
    try {
      this.veEltaBalance = await this.pack.getAgentVeEltaBalance(this.id);
    } catch {
      // veELTA query may not be implemented yet
    }

    // Refresh app token balances for tracked apps
    for (const [appId] of this.appTokenBalances) {
      try {
        const balance = await this.pack.getAgentAppTokenBalance(this.id, appId);
        this.appTokenBalances.set(appId, balance);
      } catch {
        // App token query may fail, keep cached value
      }
    }
  }

  /**
   * Execute an action and refresh balances if it's a trade
   */
  protected async executeAndRefresh(
    action: Action,
    ctx: TickContext
  ): Promise<{ ok: boolean; error?: string }> {
    if (!this.pack) {
      return { ok: false, error: 'Pack not initialized' };
    }

    const result = await this.pack.executeAction(action, this.id);

    // Refresh balances after trade actions
    if (result.ok && (action.name === 'buy_app_token' || action.name === 'sell_app_token')) {
      await this.updateBalances();
    }

    // Record the action
    ctx.logger.debug({ action: action.name, result: result.ok }, 'Action executed');

    return result;
  }

  /**
   * Create an action from an EltaAction payload
   */
  protected createAction(actionName: string, payload: EltaAction, tick: number): Action {
    return {
      id: this.generateActionId(actionName, tick),
      name: actionName,
      params: payload as unknown as Record<string, unknown>,
    };
  }

  /**
   * Helper to choose a random app from available apps
   */
  protected chooseRandomApp(ctx: TickContext): AppState | null {
    const apps = Array.from(this.getAllApps().values());
    if (apps.length === 0) return null;

    return ctx.rng.pickOne(apps);
  }

  /**
   * Helper to choose an app with good momentum (price increase)
   */
  protected chooseAppWithMomentum(threshold = 0): AppState | null {
    const apps = Array.from(this.getAllApps().values());

    // Filter for apps with price > threshold (simple momentum check)
    const candidates = apps.filter((app) => !app.graduated && app.tokenPrice > BigInt(threshold));

    if (candidates.length === 0) return null;

    // Return the one with highest price (simple heuristic)
    return candidates.reduce((best, current) =>
      current.tokenPrice > best.tokenPrice ? current : best
    );
  }

  /**
   * Helper to check if should take action based on probability
   */
  protected shouldAct(ctx: TickContext, probability: number): boolean {
    return ctx.rng.chance(probability);
  }

  /**
   * Format ELTA amount for logging (convert from wei)
   */
  protected formatElta(amount: bigint): string {
    return `${Number(amount) / 1e18} ELTA`;
  }

  // ============================================
  // Governance Helpers
  // ============================================

  /**
   * Get active governance proposals
   * Returns proposal IDs that are in voting period
   */
  protected getActiveProposals(): bigint[] {
    // In a real implementation, this would query the Governor contract
    // For now, return an empty array as placeholder
    return [];
  }

  /**
   * Check if agent has enough voting power for governance actions
   */
  protected hasVotingPower(minPower = 0n): boolean {
    return this.veEltaBalance > minPower;
  }

  /**
   * Get minimum proposal threshold (typically 1% of veELTA supply)
   */
  protected getProposalThreshold(): bigint {
    const state = this.getWorldState();
    // Default to 1% of total veELTA locked
    return state.totalVeEltaLocked / 100n;
  }

  /**
   * Get proposal state from the Governor contract
   * Returns: 0=Pending, 1=Active, 2=Canceled, 3=Defeated, 4=Succeeded, 5=Queued, 6=Expired, 7=Executed
   * Returns null if unable to query
   */
  protected async getProposalState(proposalId: bigint): Promise<number | null> {
    if (!this.pack) return null;
    return this.pack.getProposalState(proposalId);
  }

  /**
   * Check if this agent has voted on a proposal
   */
  protected async hasVotedOnProposal(proposalId: bigint): Promise<boolean> {
    if (!this.pack) return false;
    return this.pack.hasVotedOnProposal(this.id, proposalId);
  }

  // ============================================
  // Rewards Helpers
  // ============================================

  /**
   * Check if agent has claimable veELTA rewards
   */
  protected async hasClaimableVeEltaRewards(): Promise<boolean> {
    if (!this.pack) return false;
    const result = await this.pack.getClaimableRewardsEpochs(this.id);
    return result.hasClaimableRewards;
  }

  /**
   * Get detailed info about claimable veELTA rewards epochs
   */
  protected async getClaimableVeEltaEpochs(): Promise<{
    hasClaimableRewards: boolean;
    lastClaimed: bigint;
    totalEpochs: bigint;
  }> {
    if (!this.pack) return { hasClaimableRewards: false, lastClaimed: 0n, totalEpochs: 0n };
    return this.pack.getClaimableRewardsEpochs(this.id);
  }

  /**
   * Check if agent has claimable app staking rewards
   */
  protected async hasClaimableAppRewards(appId: string): Promise<boolean> {
    if (!this.pack) return false;
    const result = await this.pack.getAppClaimableEpochs(this.id, appId);
    return result.hasClaimableRewards;
  }

  /**
   * Get agent's staked balance for an app
   */
  protected async getStakedBalance(appId: string): Promise<bigint> {
    if (!this.pack) return 0n;
    return this.pack.getAgentStakedBalance(this.id, appId);
  }

  // ============================================
  // Tournament Helpers
  // ============================================

  /**
   * Tournament state tracking
   */
  protected activeTournaments: Map<string, { address: Address; entryFee: bigint; token: Address }> =
    new Map();

  /**
   * Get tournaments the agent has entered
   */
  protected getEnteredTournaments(): string[] {
    return Array.from(this.activeTournaments.keys());
  }

  /**
   * Check if agent can afford tournament entry
   */
  protected canAffordTournamentEntry(entryFee: bigint, token: Address): boolean {
    // Check if token is ELTA
    const state = this.getWorldState();
    if (token === state.elta) {
      return this.hasEnoughElta(entryFee);
    }
    // For app tokens, check app balance
    for (const [appId, app] of this.getAllApps()) {
      if (app.tokenAddress === token) {
        return this.getAppTokenBalance(appId) >= entryFee;
      }
    }
    return false;
  }

  // ============================================
  // Content/NFT Helpers
  // ============================================

  /**
   * Content store tracking per app
   */
  protected contentStores: Map<string, Address> = new Map(); // appId -> contentStoreAddress

  /**
   * Owned NFT content: contentStoreAddress -> tokenIds
   */
  protected ownedContent: Map<Address, bigint[]> = new Map();

  /**
   * Get all content stores from apps
   */
  protected getContentStores(): Map<string, Address> {
    return this.contentStores;
  }

  /**
   * Get owned content for a store
   */
  protected getOwnedContentForStore(storeAddress: Address): bigint[] {
    return this.ownedContent.get(storeAddress) ?? [];
  }

  /**
   * Track content purchase
   */
  protected recordContentPurchase(storeAddress: Address, tokenId: bigint): void {
    const owned = this.ownedContent.get(storeAddress) ?? [];
    owned.push(tokenId);
    this.ownedContent.set(storeAddress, owned);
  }

  // ============================================
  // Fee Pipeline Helpers
  // ============================================

  /**
   * Get all bonding curves that may have fees to sweep
   */
  protected getCurvesWithPendingFees(): Address[] {
    const curves: Address[] = [];
    for (const [_appId, app] of this.getAllApps()) {
      if (!app.graduated && app.curveAddress) {
        curves.push(app.curveAddress);
      }
    }
    return curves;
  }

  /**
   * Get estimated fees from trading activity
   * Used to decide if sweep is worthwhile
   */
  protected getEstimatedPendingFees(): bigint {
    // Estimate based on total raised across all apps (2% fee rate)
    let totalRaised = 0n;
    for (const [_appId, app] of this.getAllApps()) {
      totalRaised += app.totalRaised;
    }
    return totalRaised / 50n; // 2% = 1/50
  }

  /**
   * Check if fee epoch can be closed (time-based)
   */
  protected canCloseFeeEpoch(): boolean {
    // Fee epochs are typically daily
    // In simulation, we assume epoch can always be closed
    return true;
  }

  // ============================================
  // Referral Helpers
  // ============================================

  /**
   * Track if agent has set a referrer
   */
  protected hasReferrer = false;

  /**
   * Addresses this agent has referred
   */
  protected referredAddresses: Address[] = [];

  /**
   * Accumulated referral rewards (tracked locally)
   */
  protected referralRewardsAccrued = 0n;

  /**
   * Check if agent can claim referral rewards
   */
  protected canClaimReferralRewards(): boolean {
    return this.referralRewardsAccrued > 0n;
  }

  /**
   * Record a referral
   */
  protected recordReferral(referredAddress: Address, rewardAmount: bigint): void {
    this.referredAddresses.push(referredAddress);
    this.referralRewardsAccrued += rewardAmount;
  }

  // ============================================
  // Airdrop Helpers
  // ============================================

  /**
   * Airdrop campaigns the agent is eligible for
   * Map: campaignId -> { proof, amount }
   */
  protected eligibleAirdrops: Map<bigint, { proof: `0x${string}`[]; amount: bigint }> = new Map();

  /**
   * Check if agent has unclaimed airdrops
   */
  protected hasUnclaimedAirdrops(): boolean {
    return this.eligibleAirdrops.size > 0;
  }

  /**
   * Get next claimable airdrop
   */
  protected getNextClaimableAirdrop(): {
    campaignId: bigint;
    proof: `0x${string}`[];
    amount: bigint;
  } | null {
    const entries = Array.from(this.eligibleAirdrops.entries());
    if (entries.length === 0) return null;
    const [campaignId, data] = entries[0]!;
    return { campaignId, ...data };
  }

  /**
   * Mark airdrop as claimed
   */
  protected markAirdropClaimed(campaignId: bigint): void {
    this.eligibleAirdrops.delete(campaignId);
  }

  // ============================================
  // Vesting Helpers
  // ============================================

  /**
   * Vesting wallets the agent is beneficiary of
   * Map: vestingWalletAddress -> { appId, totalAmount, releasedAmount }
   */
  protected vestingWallets: Map<
    Address,
    { appId: string; totalAmount: bigint; releasedAmount: bigint }
  > = new Map();

  /**
   * Check if agent has vesting positions
   */
  protected hasVestingPositions(): boolean {
    return this.vestingWallets.size > 0;
  }

  /**
   * Get vesting wallets with releasable tokens
   */
  protected getReleasableVestingWallets(): Address[] {
    const releasable: Address[] = [];
    for (const [address, data] of this.vestingWallets) {
      if (data.releasedAmount < data.totalAmount) {
        releasable.push(address);
      }
    }
    return releasable;
  }

  /**
   * Record vesting release
   */
  protected recordVestingRelease(walletAddress: Address, amount: bigint): void {
    const data = this.vestingWallets.get(walletAddress);
    if (data) {
      data.releasedAmount += amount;
    }
  }

  // ============================================
  // XP/Points Helpers
  // ============================================

  /**
   * Cached XP balance
   */
  protected xpBalance = 0n;

  /**
   * XP claims available (from Merkle distribution)
   */
  protected pendingXpClaim: { proof: `0x${string}`[]; amount: bigint } | null = null;

  /**
   * Get current XP balance
   */
  protected getXpBalance(): bigint {
    return this.xpBalance;
  }

  /**
   * Check if agent has XP to claim
   */
  protected hasPendingXpClaim(): boolean {
    return this.pendingXpClaim !== null;
  }

  /**
   * Check if agent meets XP requirement for early access
   */
  protected meetsXpRequirement(required: bigint): boolean {
    return this.xpBalance >= required;
  }

  // ============================================
  // Enhanced Helper Methods (Phase 1)
  // ============================================

  protected recordDecisionMemory(ctx: TickContext, payload: DecisionMemoryPayload): void {
    const decision = payload.decision.trim() || 'no_op';
    const reason =
      payload.reason.trim().slice(0, BaseProtocolAgent.DECISION_MEMORY_MAX_REASON_CHARS) ||
      'unspecified';

    const lastResult = ctx.lastResult ?? null;
    const outcome: DecisionMemoryOutcome | undefined =
      payload.outcome ??
      (lastResult
        ? {
            ok: lastResult.ok,
            ...(lastResult.error
              ? {
                  error: lastResult.error.slice(
                    0,
                    BaseProtocolAgent.DECISION_MEMORY_MAX_STRING_CHARS
                  ),
                }
              : {}),
          }
        : undefined);

    const compactContext = this.compactDecisionContext(payload.context);
    const entry: DecisionMemoryEntry = {
      tick: ctx.tick,
      decision,
      reason,
      ...(outcome ? { outcome } : {}),
      ...(Object.keys(compactContext).length > 0 ? { context: compactContext } : {}),
    };

    const historyLimit = this.resolveDecisionHistoryLimit();
    const history = this.recall<DecisionMemoryEntry[]>('decisionHistory', []) ?? [];
    history.push(entry);
    const boundedHistory = history.slice(-historyLimit);

    this.remember('lastTick', ctx.tick);
    this.remember('lastDecision', decision);
    this.remember('lastReason', reason);
    this.remember('lastOutcome', outcome ?? null);
    this.remember('decisionHistory', boundedHistory);
  }

  private resolveDecisionHistoryLimit(): number {
    const configured = this.getParam<number>(
      'decisionMemoryHistoryLimit',
      BaseProtocolAgent.DECISION_MEMORY_HISTORY_LIMIT
    );
    if (!Number.isFinite(configured) || configured < 1) {
      return BaseProtocolAgent.DECISION_MEMORY_HISTORY_LIMIT;
    }
    return Math.min(Math.floor(configured), 200);
  }

  private compactDecisionContext(
    context: Record<string, unknown> | undefined
  ): Record<string, DecisionMemoryPrimitive> {
    if (!context) return {};

    const compact: Record<string, DecisionMemoryPrimitive> = {};
    const entries = Object.entries(context).slice(0, BaseProtocolAgent.DECISION_MEMORY_MAX_CONTEXT_KEYS);

    for (const [key, value] of entries) {
      const normalized = this.normalizeDecisionContextValue(value);
      if (normalized !== undefined) {
        compact[key] = normalized;
      }
    }

    return compact;
  }

  private normalizeDecisionContextValue(value: unknown): DecisionMemoryPrimitive | undefined {
    if (value === null) return null;
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : undefined;
    }
    if (typeof value === 'string') {
      return value.slice(0, BaseProtocolAgent.DECISION_MEMORY_MAX_STRING_CHARS);
    }
    if (typeof value === 'bigint') {
      return value.toString();
    }
    return undefined;
  }

  /**
   * Pre-step hook - override in subclasses for setup before step logic
   * Called at the start of each step to refresh state
   */
  protected async preStep(ctx: TickContext): Promise<void> {
    // Update all cached balances
    await this.updateBalances();

    ctx.logger.trace(
      {
        agentId: this.id,
        eltaBalance: this.formatElta(this.eltaBalance),
        veEltaBalance: this.formatElta(this.veEltaBalance),
      },
      'Agent pre-step complete'
    );
  }

  /**
   * Ensure agent has veELTA lock with minimum amount and duration
   * Creates or extends lock as needed
   *
   * @param minAmount Minimum amount to have locked
   * @param lockDurationSeconds Lock duration in seconds
   * @returns true if lock is sufficient, action to execute if not
   */
  protected async ensureVeEltaLock(
    minAmount: bigint,
    lockDurationSeconds: number,
    ctx: TickContext
  ): Promise<{ sufficient: boolean; action?: Action }> {
    if (!this.pack) {
      return { sufficient: false };
    }

    // Use cached veELTA balance as proxy for locked amount
    await this.updateBalances();

    // Check if existing lock is sufficient
    if (this.veEltaBalance >= minAmount) {
      return { sufficient: true };
    }

    // Calculate how much more to lock
    const needed = minAmount - this.veEltaBalance;

    // Check if we have enough ELTA
    if (!this.hasEnoughElta(needed)) {
      ctx.logger.debug(
        { agentId: this.id, needed: this.formatElta(needed) },
        'Insufficient ELTA for veELTA lock'
      );
      return { sufficient: false };
    }

    // Create lock action (new lock or increase depending on current state)
    if (this.veEltaBalance === 0n) {
      // Create new lock
      const action = this.createAction(
        'lock_veelta',
        { type: 'lock_veelta', amount: needed, duration: lockDurationSeconds },
        ctx.tick
      );
      return { sufficient: false, action };
    } else {
      // Increase existing lock
      const action = this.createAction(
        'increase_amount',
        { type: 'increase_amount', additionalAmount: needed },
        ctx.tick
      );
      return { sufficient: false, action };
    }
  }

  /**
   * Claim rewards if eligible
   * Returns action to execute or null if not eligible
   *
   * @param type Type of rewards to claim
   * @param appId App ID for app staking rewards
   */
  protected async claimRewardsIfEligible(
    type: 'veelta' | 'app',
    ctx: TickContext,
    appId?: string
  ): Promise<Action | null> {
    if (!this.pack) return null;

    if (type === 'veelta') {
      const hasRewards = await this.hasClaimableVeEltaRewards();
      if (!hasRewards) return null;

      return this.createAction(
        'claim_rewards',
        { type: 'claim_rewards' },
        ctx.tick
      );
    } else if (type === 'app' && appId) {
      const hasRewards = await this.hasClaimableAppRewards(appId);
      if (!hasRewards) return null;

      // Get app address from state
      const app = this.getAppState(appId);
      if (!app) return null;

      return this.createAction(
        'claim_app_rewards',
        { type: 'claim_app_rewards', appId, appAddress: app.tokenAddress },
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Select action based on weighted probabilities
   * Filters by conditions and selects randomly weighted by probability
   *
   * @param actions Array of actions with weights and optional conditions
   * @param ctx Tick context for RNG
   */
  protected selectActionByProbability(
    actions: ProbabilityAction[],
    ctx: TickContext
  ): Action | null {
    // Filter to actions where condition is true (or undefined)
    const eligible = actions.filter((a) => a.condition !== false);

    if (eligible.length === 0) return null;

    // Calculate total weight
    const totalWeight = eligible.reduce((sum, a) => sum + a.weight, 0);
    if (totalWeight <= 0) return null;

    // Random selection weighted by probability
    let random = ctx.rng.nextFloat() * totalWeight;

    for (const item of eligible) {
      random -= item.weight;
      if (random <= 0) {
        return item.action;
      }
    }

    // Fallback to last eligible
    return eligible[eligible.length - 1]!.action;
  }

  /**
   * Build action from type and params with auto-generated ID
   */
  protected buildAction<T extends EltaAction>(
    actionType: T['type'],
    params: Omit<T, 'type'>,
    ctx: TickContext
  ): Action {
    const payload = { type: actionType, ...params } as unknown as EltaAction;
    return this.createAction(actionType, payload, ctx.tick);
  }

  /**
   * Safe action execution with error categorization
   */
  protected async safeExecute(
    action: Action,
    ctx: TickContext
  ): Promise<{ ok: boolean; error?: CategorizedError }> {
    try {
      const result = await this.executeAndRefresh(action, ctx);

      if (!result.ok) {
        return {
          ok: false,
          error: this.categorizeError(new Error(result.error ?? 'Unknown error')),
        };
      }

      return { ok: true };
    } catch (err) {
      return {
        ok: false,
        error: this.categorizeError(err),
      };
    }
  }

  /**
   * Categorize an error by its type and content
   */
  protected categorizeError(error: unknown): CategorizedError {
    const message = error instanceof Error ? error.message : String(error);
    const context: Record<string, unknown> = {
      agentId: this.id,
      originalError: message,
    };

    // Insufficient balance errors
    if (
      message.includes('InsufficientBalance') ||
      message.includes('0xe450d38c') ||
      message.includes('insufficient funds') ||
      message.includes('ERC20InsufficientBalance')
    ) {
      return {
        category: 'insufficient_balance',
        message: 'Insufficient balance for action',
        context,
      };
    }

    // Invalid state errors
    if (
      message.includes('NotActive') ||
      message.includes('InvalidState') ||
      message.includes('NotReady') ||
      message.includes('AlreadyExists')
    ) {
      return {
        category: 'invalid_state',
        message: 'Invalid contract state for action',
        context,
      };
    }

    // Contract revert errors
    if (
      message.includes('revert') ||
      message.includes('execution reverted') ||
      message.includes('0x')
    ) {
      return {
        category: 'contract_revert',
        message: 'Contract reverted',
        context,
      };
    }

    // Timeout errors
    if (message.includes('timeout') || message.includes('ETIMEDOUT')) {
      return {
        category: 'timeout',
        message: 'Operation timed out',
        context,
      };
    }

    // Network errors
    if (
      message.includes('fetch failed') ||
      message.includes('ECONNREFUSED') ||
      message.includes('network')
    ) {
      return {
        category: 'network',
        message: 'Network error',
        context,
      };
    }

    // Validation errors
    if (
      message.includes('invalid') ||
      message.includes('Invalid') ||
      message.includes('validation')
    ) {
      return {
        category: 'validation',
        message: 'Validation error',
        context,
      };
    }

    return {
      category: 'unknown',
      message,
      context,
    };
  }

  /**
   * Try multiple actions in priority order until one succeeds
   */
  protected async tryActionsInOrder(
    actions: Action[],
    ctx: TickContext
  ): Promise<{ action: Action; success: boolean } | null> {
    for (const action of actions) {
      const result = await this.safeExecute(action, ctx);
      if (result.ok) {
        return { action, success: true };
      }
      // Log failed attempt
      ctx.logger.debug(
        {
          agentId: this.id,
          action: action.name,
          error: result.error?.message,
        },
        'Action failed, trying next'
      );
    }
    return null;
  }

  /**
   * Get a random amount within a range
   */
  protected randomAmount(
    min: bigint,
    max: bigint,
    ctx: TickContext
  ): bigint {
    if (max <= min) return min;
    const range = Number(max - min);
    return min + BigInt(Math.floor(ctx.rng.nextFloat() * range));
  }

  /**
   * Check if current tick matches a periodic schedule
   * Useful for actions that should happen every N ticks
   */
  protected isScheduledTick(period: number, ctx: TickContext, offset = 0): boolean {
    return (ctx.tick + offset) % period === 0;
  }
}

/**
 * Agent that does nothing - useful for testing
 */
export class PassiveAgent extends BaseProtocolAgent {
  async step(_ctx: TickContext): Promise<Action | null> {
    return null;
  }
}
