/**
 * Action types for Elata Protocol simulation
 *
 * These actions map to contract calls that agents can execute.
 */

import type { Address } from 'viem';

/**
 * Buy app tokens using ELTA via bonding curve
 */
export interface BuyAppTokenAction {
  type: 'buy_app_token';
  appId: string;
  appAddress: Address;
  eltaAmount: bigint;
  minTokensOut: bigint | undefined;
}

/**
 * Sell app tokens for ELTA via bonding curve
 */
export interface SellAppTokenAction {
  type: 'sell_app_token';
  appId: string;
  appAddress: Address;
  tokenAmount: bigint;
  minEltaOut: bigint | undefined;
}

/**
 * Create a new app via AppFactory
 */
export interface CreateAppAction {
  type: 'create_app';
  name: string;
  symbol: string;
  metadataUri: string | undefined;
}

/**
 * Lock ELTA to receive veELTA
 */
export interface LockVeEltaAction {
  type: 'lock_veelta';
  amount: bigint;
  /** Lock duration in seconds */
  duration: number;
}

/**
 * Extend an existing veELTA lock
 */
export interface ExtendLockAction {
  type: 'extend_lock';
  /** New unlock timestamp */
  newUnlockTime: number;
}

/**
 * Increase the amount in an existing veELTA lock
 */
export interface IncreaseAmountAction {
  type: 'increase_amount';
  additionalAmount: bigint;
}

/**
 * Unlock veELTA after lock period expires
 */
export interface UnlockVeEltaAction {
  type: 'unlock_veelta';
}

/**
 * Claim rewards from RewardsDistributor
 */
export interface ClaimRewardsAction {
  type: 'claim_rewards';
  epoch?: number;
}

/**
 * Stake app tokens in the app's staking vault
 */
export interface StakeAppTokenAction {
  type: 'stake_app_token';
  appId: string;
  appAddress: Address;
  amount: bigint;
}

/**
 * Unstake app tokens from the app's staking vault
 */
export interface UnstakeAppTokenAction {
  type: 'unstake_app_token';
  appId: string;
  appAddress: Address;
  amount: bigint;
}

/**
 * Claim app staking rewards
 */
export interface ClaimAppRewardsAction {
  type: 'claim_app_rewards';
  appId: string;
  appAddress: Address;
}

/**
 * Transfer ELTA to another address
 */
export interface TransferEltaAction {
  type: 'transfer_elta';
  to: Address;
  amount: bigint;
}

/**
 * Approve ELTA spending for a contract
 */
export interface ApproveEltaAction {
  type: 'approve_elta';
  spender: Address;
  amount: bigint;
}

/**
 * No-op action (agent chooses to do nothing)
 */
export interface NoOpAction {
  type: 'noop';
  reason: string | undefined;
}

// ============================================
// Tournament Actions
// ============================================

/**
 * Enter a tournament by paying entry fee
 */
export interface EnterTournamentAction {
  type: 'enter_tournament';
  tournamentAddress: Address;
  entryToken: Address; // APP, ELTA, or USDC
  entryAmount: bigint;
}

/**
 * Claim tournament prize with Merkle proof
 */
export interface ClaimTournamentPrizeAction {
  type: 'claim_tournament_prize';
  tournamentAddress: Address;
  proof: `0x${string}`[];
  amount: bigint;
}

/**
 * Create a new tournament for an app
 */
export interface CreateTournamentAction {
  type: 'create_tournament';
  appId: string;
  entryToken: Address; // APP, ELTA, or USDC
  entryFee: bigint;
  startTime: bigint;
  endTime: bigint;
  maxParticipants: bigint;
  prizePoolBps: bigint; // Basis points of entry fees for prize pool
}

/**
 * Finalize a tournament by setting winners Merkle root
 */
export interface FinalizeTournamentAction {
  type: 'finalize_tournament';
  tournamentAddress: Address;
  winnersRoot: `0x${string}`;
}

// ============================================
// Content/NFT Actions
// ============================================

/**
 * Purchase in-app content (NFT)
 */
export interface PurchaseContentAction {
  type: 'purchase_content';
  contentStoreAddress: Address;
  contentId: bigint;
  paymentToken: Address; // APP, ELTA, or USDC
  maxPrice: bigint;
}

/**
 * List content for sale (operator action)
 * PaymentTokenType: 0=APP, 1=ELTA, 2=USDC
 */
export interface ListContentAction {
  type: 'list_content';
  contentStoreAddress: Address;
  contentUri: string;
  price: bigint;
  paymentTokenType: 0 | 1 | 2; // Enum: 0=APP, 1=ELTA, 2=USDC
  maxSupply: bigint;
}

/**
 * List content with time window for limited availability
 */
export interface ListContentWithTimeWindowAction {
  type: 'list_content_with_time_window';
  contentStoreAddress: Address;
  contentUri: string;
  price: bigint;
  paymentTokenType: 0 | 1 | 2;
  maxSupply: bigint;
  startTime: bigint;
  endTime: bigint;
}

/**
 * Deactivate a content listing
 */
export interface DeactivateContentAction {
  type: 'deactivate_content';
  contentStoreAddress: Address;
  contentId: bigint;
}

/**
 * Reactivate a previously deactivated content listing
 */
export interface ReactivateContentAction {
  type: 'reactivate_content';
  contentStoreAddress: Address;
  contentId: bigint;
}

// ============================================
// Delegation Actions
// ============================================

/**
 * Delegate veELTA voting power
 */
export interface DelegateVotesAction {
  type: 'delegate_votes';
  delegatee: Address;
}

// ============================================
// Governance Actions
// ============================================

/**
 * Create a governance proposal
 */
export interface CreateProposalAction {
  type: 'create_proposal';
  targets: Address[];
  values: bigint[];
  calldatas: `0x${string}`[];
  description: string;
}

/**
 * Cast a vote on a proposal
 */
export interface CastVoteAction {
  type: 'cast_vote';
  proposalId: bigint;
  support: 0 | 1 | 2; // 0=Against, 1=For, 2=Abstain
  reason?: string;
}

/**
 * Queue a passed proposal for execution
 */
export interface QueueProposalAction {
  type: 'queue_proposal';
  proposalId: bigint;
}

/**
 * Execute a queued proposal after timelock
 */
export interface ExecuteProposalAction {
  type: 'execute_proposal';
  proposalId: bigint;
}

// ============================================
// Fee Pipeline Actions
// ============================================

/**
 * Sweep fees from a bonding curve to FeeCollector
 */
export interface SweepFeesAction {
  type: 'sweep_fees';
  curveAddress: Address;
}

/**
 * Sweep ELTA from FeeCollector to FeeManager (step 2 of fee pipeline)
 */
export interface SweepEltaToFeeManagerAction {
  type: 'sweep_elta_to_feemanager';
  appId: number;
}

/**
 * Close fee epoch and distribute (earns incentive)
 * @param appId - The app ID to close epoch for (0 for protocol fees, 1+ for app-specific fees)
 */
export interface CloseFeeEpochAction {
  type: 'close_fee_epoch';
  appId: number;
}

// ============================================
// Referral Actions
// ============================================

/**
 * Set referrer for future purchases
 */
export interface SetReferrerAction {
  type: 'set_referrer';
  referrer: Address;
}

/**
 * Claim accumulated referral rewards
 */
export interface ClaimReferralRewardsAction {
  type: 'claim_referral_rewards';
}

// ============================================
// Airdrop Actions
// ============================================

/**
 * Claim airdrop from Merkle distribution
 */
export interface ClaimAirdropAction {
  type: 'claim_airdrop';
  campaignId: bigint;
  proof: `0x${string}`[];
  amount: bigint;
}

// ============================================
// XP/Points Actions
// ============================================

/**
 * Claim XP points from Merkle distribution
 */
export interface ClaimXpPointsAction {
  type: 'claim_xp_points';
  proof: `0x${string}`[];
  amount: bigint;
}

// ============================================
// Vesting Actions
// ============================================

/**
 * Release vested tokens from vesting wallet
 */
export interface ReleaseVestedTokensAction {
  type: 'release_vested_tokens';
  vestingWalletAddress: Address;
}

/**
 * Union type of all possible Elata actions
 */
export type EltaAction =
  // Core trading actions
  | BuyAppTokenAction
  | SellAppTokenAction
  | CreateAppAction
  // veELTA actions
  | LockVeEltaAction
  | ExtendLockAction
  | IncreaseAmountAction
  | UnlockVeEltaAction
  | ClaimRewardsAction
  // App staking actions
  | StakeAppTokenAction
  | UnstakeAppTokenAction
  | ClaimAppRewardsAction
  // Token management
  | TransferEltaAction
  | ApproveEltaAction
  // Tournament actions
  | EnterTournamentAction
  | ClaimTournamentPrizeAction
  | CreateTournamentAction
  | FinalizeTournamentAction
  // Content/NFT actions
  | PurchaseContentAction
  | ListContentAction
  | ListContentWithTimeWindowAction
  | DeactivateContentAction
  | ReactivateContentAction
  // Delegation actions
  | DelegateVotesAction
  // Governance actions
  | CreateProposalAction
  | CastVoteAction
  | QueueProposalAction
  | ExecuteProposalAction
  // Fee pipeline actions
  | SweepFeesAction
  | SweepEltaToFeeManagerAction
  | CloseFeeEpochAction
  // Referral actions
  | SetReferrerAction
  | ClaimReferralRewardsAction
  // Airdrop actions
  | ClaimAirdropAction
  // XP/Points actions
  | ClaimXpPointsAction
  // Vesting actions
  | ReleaseVestedTokensAction
  // No-op
  | NoOpAction;

/**
 * Type guard for buy action
 */
export function isBuyAction(action: EltaAction): action is BuyAppTokenAction {
  return action.type === 'buy_app_token';
}

/**
 * Type guard for sell action
 */
export function isSellAction(action: EltaAction): action is SellAppTokenAction {
  return action.type === 'sell_app_token';
}

/**
 * Type guard for create app action
 */
export function isCreateAppAction(action: EltaAction): action is CreateAppAction {
  return action.type === 'create_app';
}

/**
 * Type guard for veELTA lock action
 */
export function isLockAction(action: EltaAction): action is LockVeEltaAction {
  return action.type === 'lock_veelta';
}

/**
 * Type guard for noop action
 */
export function isNoOpAction(action: EltaAction): action is NoOpAction {
  return action.type === 'noop';
}

/**
 * Create a buy action helper
 */
export function buyAppToken(
  appId: string,
  appAddress: Address,
  eltaAmount: bigint,
  minTokensOut?: bigint
): BuyAppTokenAction {
  return {
    type: 'buy_app_token',
    appId,
    appAddress,
    eltaAmount,
    minTokensOut,
  };
}

/**
 * Create a sell action helper
 */
export function sellAppToken(
  appId: string,
  appAddress: Address,
  tokenAmount: bigint,
  minEltaOut?: bigint
): SellAppTokenAction {
  return {
    type: 'sell_app_token',
    appId,
    appAddress,
    tokenAmount,
    minEltaOut,
  };
}

/**
 * Create a create app action helper
 */
export function createApp(name: string, symbol: string, metadataUri?: string): CreateAppAction {
  return {
    type: 'create_app',
    name,
    symbol,
    metadataUri,
  };
}

/**
 * Create a lock veELTA action helper
 */
export function lockVeElta(amount: bigint, durationSeconds: number): LockVeEltaAction {
  return {
    type: 'lock_veelta',
    amount,
    duration: durationSeconds,
  };
}

/**
 * Create an unlock veELTA action helper
 */
export function unlockVeElta(): UnlockVeEltaAction {
  return {
    type: 'unlock_veelta',
  };
}

/**
 * Create an extend lock action helper
 */
export function extendLock(newUnlockTime: number): ExtendLockAction {
  return {
    type: 'extend_lock',
    newUnlockTime,
  };
}

/**
 * Alias for extendLock that takes duration instead of timestamp
 */
export function extendVeEltaLock(newDurationSeconds: number): ExtendLockAction {
  // Calculate new unlock time from duration
  const newUnlockTime = Math.floor(Date.now() / 1000) + newDurationSeconds;
  return {
    type: 'extend_lock',
    newUnlockTime,
  };
}

/**
 * Create an increase amount action helper
 */
export function increaseAmount(additionalAmount: bigint): IncreaseAmountAction {
  return {
    type: 'increase_amount',
    additionalAmount,
  };
}

/**
 * Create a stake app token action helper
 */
export function stakeAppToken(
  appId: string,
  appAddress: Address,
  amount: bigint
): StakeAppTokenAction {
  return {
    type: 'stake_app_token',
    appId,
    appAddress,
    amount,
  };
}

/**
 * Alias for stakeAppToken
 */
export const stakeAppTokens = stakeAppToken;

/**
 * Create an unstake app token action helper
 */
export function unstakeAppToken(
  appId: string,
  appAddress: Address,
  amount: bigint
): UnstakeAppTokenAction {
  return {
    type: 'unstake_app_token',
    appId,
    appAddress,
    amount,
  };
}

/**
 * Create a claim rewards action helper (veELTA rewards)
 */
export function claimRewards(epoch?: number): ClaimRewardsAction {
  const action: ClaimRewardsAction = {
    type: 'claim_rewards',
  };
  if (epoch !== undefined) {
    action.epoch = epoch;
  }
  return action;
}

/**
 * Create a claim app rewards action helper (app staking rewards)
 */
export function claimAppRewards(appId: string, appAddress: Address): ClaimAppRewardsAction {
  return {
    type: 'claim_app_rewards',
    appId,
    appAddress,
  };
}

/**
 * Create a noop action helper
 */
export function noop(reason?: string): NoOpAction {
  return {
    type: 'noop',
    reason,
  };
}

// ============================================
// Tournament Action Helpers
// ============================================

/**
 * Create an enter tournament action helper
 */
export function enterTournament(
  tournamentAddress: Address,
  entryToken: Address,
  entryAmount: bigint
): EnterTournamentAction {
  return {
    type: 'enter_tournament',
    tournamentAddress,
    entryToken,
    entryAmount,
  };
}

/**
 * Create a claim tournament prize action helper
 */
export function claimTournamentPrize(
  tournamentAddress: Address,
  proof: `0x${string}`[],
  amount: bigint
): ClaimTournamentPrizeAction {
  return {
    type: 'claim_tournament_prize',
    tournamentAddress,
    proof,
    amount,
  };
}

/**
 * Create a tournament action helper
 */
export function createTournament(
  appId: string,
  entryToken: Address,
  entryFee: bigint,
  startTime: bigint,
  endTime: bigint,
  maxParticipants: bigint,
  prizePoolBps = 8000n // 80% default
): CreateTournamentAction {
  return {
    type: 'create_tournament',
    appId,
    entryToken,
    entryFee,
    startTime,
    endTime,
    maxParticipants,
    prizePoolBps,
  };
}

/**
 * Finalize tournament action helper
 */
export function finalizeTournament(
  tournamentAddress: Address,
  winnersRoot: `0x${string}`
): FinalizeTournamentAction {
  return {
    type: 'finalize_tournament',
    tournamentAddress,
    winnersRoot,
  };
}

// ============================================
// Content/NFT Action Helpers
// ============================================

/**
 * Create a purchase content action helper
 */
export function purchaseContent(
  contentStoreAddress: Address,
  contentId: bigint,
  paymentToken: Address,
  maxPrice: bigint
): PurchaseContentAction {
  return {
    type: 'purchase_content',
    contentStoreAddress,
    contentId,
    paymentToken,
    maxPrice,
  };
}

/**
 * Create a list content action helper
 */
export function listContent(
  contentStoreAddress: Address,
  contentUri: string,
  price: bigint,
  paymentTokenType: 0 | 1 | 2, // 0=APP, 1=ELTA, 2=USDC
  maxSupply: bigint
): ListContentAction {
  return {
    type: 'list_content',
    contentStoreAddress,
    contentUri,
    price,
    paymentTokenType,
    maxSupply,
  };
}

/**
 * Create a list content with time window action helper
 */
export function listContentWithTimeWindow(
  contentStoreAddress: Address,
  contentUri: string,
  price: bigint,
  paymentTokenType: 0 | 1 | 2,
  maxSupply: bigint,
  startTime: bigint,
  endTime: bigint
): ListContentWithTimeWindowAction {
  return {
    type: 'list_content_with_time_window',
    contentStoreAddress,
    contentUri,
    price,
    paymentTokenType,
    maxSupply,
    startTime,
    endTime,
  };
}

/**
 * Create a deactivate content action helper
 */
export function deactivateContent(
  contentStoreAddress: Address,
  contentId: bigint
): DeactivateContentAction {
  return {
    type: 'deactivate_content',
    contentStoreAddress,
    contentId,
  };
}

/**
 * Create a reactivate content action helper
 */
export function reactivateContent(
  contentStoreAddress: Address,
  contentId: bigint
): ReactivateContentAction {
  return {
    type: 'reactivate_content',
    contentStoreAddress,
    contentId,
  };
}

// ============================================
// Governance Action Helpers
// ============================================

/**
 * Create a proposal action helper
 */
export function createProposal(
  targets: Address[],
  values: bigint[],
  calldatas: `0x${string}`[],
  description: string
): CreateProposalAction {
  return {
    type: 'create_proposal',
    targets,
    values,
    calldatas,
    description,
  };
}

/**
 * Create a cast vote action helper
 */
export function castVote(proposalId: bigint, support: 0 | 1 | 2, reason?: string): CastVoteAction {
  const action: CastVoteAction = {
    type: 'cast_vote',
    proposalId,
    support,
  };
  if (reason !== undefined) {
    action.reason = reason;
  }
  return action;
}

/**
 * Create a queue proposal action helper
 */
export function queueProposal(proposalId: bigint): QueueProposalAction {
  return {
    type: 'queue_proposal',
    proposalId,
  };
}

/**
 * Create an execute proposal action helper
 */
export function executeProposal(proposalId: bigint): ExecuteProposalAction {
  return {
    type: 'execute_proposal',
    proposalId,
  };
}

// ============================================
// Delegation Action Helpers
// ============================================

/**
 * Create a delegate votes action helper
 */
export function delegateVotes(delegatee: Address): DelegateVotesAction {
  return {
    type: 'delegate_votes',
    delegatee,
  };
}

// ============================================
// Fee Pipeline Action Helpers
// ============================================

/**
 * Create a sweep fees action helper
 */
export function sweepFees(curveAddress: Address): SweepFeesAction {
  return {
    type: 'sweep_fees',
    curveAddress,
  };
}

/**
 * Create a sweep ELTA to FeeManager action helper
 */
export function sweepEltaToFeeManager(appId: number): SweepEltaToFeeManagerAction {
  return {
    type: 'sweep_elta_to_feemanager',
    appId,
  };
}

/**
 * Create a close fee epoch action helper
 * @param appId - The app ID to close epoch for (0 for protocol fees, 1+ for app-specific fees)
 */
export function closeFeeEpoch(appId: number = 0): CloseFeeEpochAction {
  return {
    type: 'close_fee_epoch',
    appId,
  };
}

// ============================================
// Referral Action Helpers
// ============================================

/**
 * Create a set referrer action helper
 */
export function setReferrer(referrer: Address): SetReferrerAction {
  return {
    type: 'set_referrer',
    referrer,
  };
}

/**
 * Create a claim referral rewards action helper
 */
export function claimReferralRewards(): ClaimReferralRewardsAction {
  return {
    type: 'claim_referral_rewards',
  };
}

// ============================================
// Airdrop Action Helpers
// ============================================

/**
 * Create a claim airdrop action helper
 */
export function claimAirdrop(
  campaignId: bigint,
  proof: `0x${string}`[],
  amount: bigint
): ClaimAirdropAction {
  return {
    type: 'claim_airdrop',
    campaignId,
    proof,
    amount,
  };
}

// ============================================
// XP/Points Action Helpers
// ============================================

/**
 * Create a claim XP points action helper
 */
export function claimXpPoints(proof: `0x${string}`[], amount: bigint): ClaimXpPointsAction {
  return {
    type: 'claim_xp_points',
    proof,
    amount,
  };
}

// ============================================
// Vesting Action Helpers
// ============================================

/**
 * Create a release vested tokens action helper
 */
export function releaseVestedTokens(vestingWalletAddress: Address): ReleaseVestedTokensAction {
  return {
    type: 'release_vested_tokens',
    vestingWalletAddress,
  };
}
