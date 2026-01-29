/**
 * TournamentPlayerAgent - Casual tournament participant
 *
 * Behavior:
 * - Enters tournaments occasionally
 * - Enjoys the competitive experience
 * - May win prizes based on luck
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { enterTournament, claimTournamentPrize } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Tournament entry tracking
 */
interface TournamentEntry {
  tournamentAddress: Address;
  appId: string;
  entryFee: bigint;
  enteredTick: number;
  claimed: boolean;
  wonPrize: boolean;
  prizeAmount: bigint;
}

/**
 * Parameters for TournamentPlayerAgent
 */
export interface TournamentPlayerAgentParams extends BaseProtocolAgentParams {
  /** Entry frequency (default 0.1) */
  entryFrequency?: number;
  /** Maximum entry fee (default 20 ELTA) */
  maxEntryFee?: bigint;
  /** Budget percentage for tournaments (default 0.1 = 10%) */
  tournamentBudget?: number;
  /** Skill level affecting win rate (0-1, default 0.5) */
  skillLevel?: number;
}

/**
 * Casual tournament player
 */
export class TournamentPlayerAgent extends BaseProtocolAgent {
  /** Tournament entries */
  private entries: TournamentEntry[] = [];

  /** Total spent on entry fees */
  private totalSpent = 0n;

  /** Total prizes won */
  private totalWon = 0n;

  /** Tournaments participated */
  private tournamentCount = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const frequency = (this.params.entryFrequency as number | undefined) ?? 0.1;
    const maxFee = (this.params.maxEntryFee as bigint | undefined) ?? BigInt(20e18);
    const budget = (this.params.tournamentBudget as number | undefined) ?? 0.1;
    const skill = (this.params.skillLevel as number | undefined) ?? 0.5;

    // Priority 1: Claim unclaimed prizes
    const claimAction = this.claimPrizes(ctx);
    if (claimAction) return claimAction;

    // Priority 2: Check for tournament results
    this.checkResults(ctx, skill);

    // Priority 3: Enter new tournaments
    if (this.shouldAct(ctx, frequency)) {
      return this.enterNewTournament(ctx, maxFee, budget);
    }

    return null;
  }

  /**
   * Enter a new tournament
   */
  private enterNewTournament(
    ctx: TickContext,
    maxFee: bigint,
    budgetPct: number
  ): Action | null {
    const balance = this.getEltaBalance();
    const budgetAmount = BigInt(Math.floor(Number(balance) * budgetPct));

    if (budgetAmount < BigInt(1e18)) return null;

    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    const [appId, app] = ctx.rng.pickOne(apps);

    // Simulate tournament with random entry fee
    const entryFee = BigInt(Math.floor(Math.random() * Number(maxFee)));
    const actualFee = entryFee > 0n ? entryFee : BigInt(5e18);

    if (actualFee > budgetAmount) return null;

    // Generate tournament address (simulated)
    const tournamentAddress = `0x${Array(40).fill(0).map(() => Math.floor(Math.random() * 16).toString(16)).join('')}` as Address;

    // Track entry
    this.entries.push({
      tournamentAddress,
      appId,
      entryFee: actualFee,
      enteredTick: ctx.tick,
      claimed: false,
      wonPrize: false,
      prizeAmount: 0n,
    });

    this.totalSpent += actualFee;
    this.tournamentCount++;

    ctx.logger.debug(
      { 
        agent: this.id, 
        app: appId,
        entryFee: this.formatElta(actualFee),
        tournamentCount: this.tournamentCount
      },
      'Entering tournament'
    );

    return this.createAction(
      'enter_tournament',
      enterTournament(tournamentAddress, app.tokenAddress, actualFee),
      ctx.tick
    );
  }

  /**
   * Check tournament results
   */
  private checkResults(ctx: TickContext, skillLevel: number): void {
    const tournamentDuration = 10; // Ticks

    for (const entry of this.entries) {
      if (entry.claimed) continue;
      if (ctx.tick - entry.enteredTick < tournamentDuration) continue;

      // Determine if won based on skill + luck
      const winChance = 0.1 + skillLevel * 0.2; // 10-30% based on skill
      
      if (ctx.rng.nextFloat() < winChance) {
        entry.wonPrize = true;
        // Prize is typically 2-5x entry fee
        const multiplier = 2 + ctx.rng.nextFloat() * 3;
        entry.prizeAmount = BigInt(Math.floor(Number(entry.entryFee) * multiplier));
      }
    }
  }

  /**
   * Claim unclaimed prizes
   */
  private claimPrizes(ctx: TickContext): Action | null {
    for (const entry of this.entries) {
      if (entry.claimed || !entry.wonPrize) continue;

      entry.claimed = true;
      this.totalWon += entry.prizeAmount;

      ctx.logger.info(
        { 
          agent: this.id, 
          prize: this.formatElta(entry.prizeAmount),
          totalWon: this.formatElta(this.totalWon)
        },
        'Claiming tournament prize'
      );

      // Generate mock proof (in reality would be from backend)
      const mockProof: `0x${string}`[] = [
        '0x0000000000000000000000000000000000000000000000000000000000000001' as `0x${string}`,
      ];

      return this.createAction(
        'claim_tournament_prize',
        claimTournamentPrize(entry.tournamentAddress, mockProof, entry.prizeAmount),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Get player statistics
   */
  getSimStats(): {
    tournamentsEntered: number;
    totalSpent: bigint;
    totalWon: bigint;
    netPnL: bigint;
    winRate: string;
  } {
    const wins = this.entries.filter(e => e.wonPrize).length;
    const completed = this.entries.filter(e => e.claimed || e.wonPrize === false).length;
    const winRate = completed > 0 ? ((wins / completed) * 100).toFixed(1) + '%' : '0%';

    return {
      tournamentsEntered: this.tournamentCount,
      totalSpent: this.totalSpent,
      totalWon: this.totalWon,
      netPnL: this.totalWon - this.totalSpent,
      winRate,
    };
  }
}
