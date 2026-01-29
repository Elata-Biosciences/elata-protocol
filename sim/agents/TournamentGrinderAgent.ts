/**
 * TournamentGrinderAgent - Serious competitive player
 *
 * Behavior:
 * - Enters many tournaments
 * - Focuses on high-value tournaments
 * - Maximizes tournament participation
 * - Tracks performance metrics
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { enterTournament, claimTournamentPrize } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Grinder tournament tracking
 */
interface GrinderEntry {
  tournamentAddress: Address;
  appId: string;
  entryFee: bigint;
  expectedValue: bigint;
  enteredTick: number;
  result: 'pending' | 'won' | 'lost';
  prizeAmount: bigint;
  claimed: boolean;
}

/**
 * Parameters for TournamentGrinderAgent
 */
export interface TournamentGrinderAgentParams extends BaseProtocolAgentParams {
  /** Maximum concurrent tournaments (default 5) */
  maxConcurrent?: number;
  /** Minimum EV ratio to enter (default 1.2) */
  minEvRatio?: number;
  /** Skill level (0-1, default 0.7) */
  skillLevel?: number;
  /** Maximum entry fee (default 50 ELTA) */
  maxEntryFee?: bigint;
  /** Grind intensity (default 0.4) */
  grindIntensity?: number;
}

/**
 * Competitive tournament grinder
 */
export class TournamentGrinderAgent extends BaseProtocolAgent {
  /** Active and completed entries */
  private entries: GrinderEntry[] = [];

  /** Session stats */
  private sessionStats = {
    entered: 0,
    won: 0,
    lost: 0,
    totalSpent: 0n,
    totalWon: 0n,
  };

  async step(ctx: TickContext): Promise<Action | null> {
    const maxConcurrent = (this.params.maxConcurrent as number | undefined) ?? 5;
    const minEvRatio = (this.params.minEvRatio as number | undefined) ?? 1.2;
    const skill = (this.params.skillLevel as number | undefined) ?? 0.7;
    const maxFee = (this.params.maxEntryFee as bigint | undefined) ?? BigInt(50e18);
    const intensity = (this.params.grindIntensity as number | undefined) ?? 0.4;

    // Priority 1: Claim prizes
    const claimAction = this.claimPrizes(ctx);
    if (claimAction) return claimAction;

    // Priority 2: Process results
    this.processResults(ctx, skill);

    // Priority 3: Enter new tournaments if under limit
    const activeCount = this.entries.filter(e => e.result === 'pending').length;
    if (activeCount < maxConcurrent && this.shouldAct(ctx, intensity)) {
      return this.enterTournament(ctx, maxFee, minEvRatio);
    }

    return null;
  }

  /**
   * Enter a tournament with EV analysis
   */
  private enterTournament(
    ctx: TickContext,
    maxFee: bigint,
    minEvRatio: number
  ): Action | null {
    const balance = this.getEltaBalance();
    if (balance < BigInt(10e18)) return null;

    const apps = Array.from(this.getAllApps().entries())
      .filter(([_, app]) => !app.graduated);

    if (apps.length === 0) return null;

    // Find tournaments with good EV
    for (const [appId, app] of apps) {
      // Simulate tournament analysis
      const entryFee = BigInt(Math.floor(Math.random() * Number(maxFee)));
      const actualFee = entryFee > 0n ? entryFee : BigInt(10e18);

      if (actualFee > balance / 3n) continue; // Max 33% per tournament

      // Calculate expected value
      // Grinders have better win rates
      const winRate = 0.25; // 25% with skill
      const avgMultiplier = 4; // 4x payout on win
      const ev = actualFee * BigInt(Math.floor(winRate * avgMultiplier * 100)) / 100n;
      const evRatio = Number(ev) / Number(actualFee);

      if (evRatio < minEvRatio) continue;

      // Enter this tournament
      const tournamentAddress = `0x${Array(40).fill(0).map(() => Math.floor(Math.random() * 16).toString(16)).join('')}` as Address;

      this.entries.push({
        tournamentAddress,
        appId,
        entryFee: actualFee,
        expectedValue: ev,
        enteredTick: ctx.tick,
        result: 'pending',
        prizeAmount: 0n,
        claimed: false,
      });

      this.sessionStats.entered++;
      this.sessionStats.totalSpent += actualFee;

      ctx.logger.debug(
        { 
          agent: this.id, 
          app: appId,
          entryFee: this.formatElta(actualFee),
          evRatio: evRatio.toFixed(2),
          active: this.entries.filter(e => e.result === 'pending').length
        },
        'Grinder entering tournament'
      );

      return this.createAction(
        'enter_tournament',
        enterTournament(tournamentAddress, app.tokenAddress, actualFee),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Process tournament results
   */
  private processResults(ctx: TickContext, skillLevel: number): void {
    const tournamentDuration = 8; // Grinders play faster tournaments

    for (const entry of this.entries) {
      if (entry.result !== 'pending') continue;
      if (ctx.tick - entry.enteredTick < tournamentDuration) continue;

      // Higher skill = higher win rate
      const winChance = 0.15 + skillLevel * 0.25; // 15-40% based on skill

      if (ctx.rng.nextFloat() < winChance) {
        entry.result = 'won';
        // Grinders know how to maximize prizes
        const multiplier = 3 + ctx.rng.nextFloat() * 4; // 3-7x
        entry.prizeAmount = BigInt(Math.floor(Number(entry.entryFee) * multiplier));
        this.sessionStats.won++;
      } else {
        entry.result = 'lost';
        this.sessionStats.lost++;
      }
    }
  }

  /**
   * Claim unclaimed prizes
   */
  private claimPrizes(ctx: TickContext): Action | null {
    for (const entry of this.entries) {
      if (entry.claimed || entry.result !== 'won') continue;

      entry.claimed = true;
      this.sessionStats.totalWon += entry.prizeAmount;

      ctx.logger.info(
        { 
          agent: this.id, 
          prize: this.formatElta(entry.prizeAmount),
          winRate: ((this.sessionStats.won / this.sessionStats.entered) * 100).toFixed(1) + '%'
        },
        'Grinder claiming prize'
      );

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
   * Get grinder statistics
   */
  getSimStats(): {
    tournamentsEntered: number;
    wins: number;
    losses: number;
    winRate: string;
    totalSpent: bigint;
    totalWon: bigint;
    roi: string;
  } {
    const winRate = this.sessionStats.entered > 0
      ? ((this.sessionStats.won / this.sessionStats.entered) * 100).toFixed(1) + '%'
      : '0%';

    const roi = this.sessionStats.totalSpent > 0n
      ? (((Number(this.sessionStats.totalWon) - Number(this.sessionStats.totalSpent)) / 
          Number(this.sessionStats.totalSpent)) * 100).toFixed(1) + '%'
      : '0%';

    return {
      tournamentsEntered: this.sessionStats.entered,
      wins: this.sessionStats.won,
      losses: this.sessionStats.lost,
      winRate,
      totalSpent: this.sessionStats.totalSpent,
      totalWon: this.sessionStats.totalWon,
      roi,
    };
  }
}
