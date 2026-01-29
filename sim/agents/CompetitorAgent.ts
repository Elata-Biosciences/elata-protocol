/**
 * CompetitorAgent - Tournament participant
 *
 * Behavior:
 * - Enters tournaments based on expected value calculation
 * - Claims prizes when won
 * - Manages tournament portfolio
 * - Tracks win/loss history
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import { claimTournamentPrize, enterTournament } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Tournament entry tracking
 */
interface TournamentEntry {
  address: Address;
  entryFee: bigint;
  entryToken: Address;
  enteredAt: number;
  won: boolean;
  prizeAmount: bigint;
  prizeClaimed: boolean;
}

/**
 * Parameters for CompetitorAgent
 */
export interface CompetitorAgentParams extends BaseProtocolAgentParams {
  /** Probability of entering a tournament each tick */
  enterProbability?: number;
  /** Maximum entry fee willing to pay (in ELTA) */
  maxEntryFee?: bigint;
  /** Maximum active tournament entries */
  maxActiveEntries?: number;
  /** Win probability for simulation (used to determine outcomes) */
  winProbability?: number;
}

/**
 * Agent that participates in tournaments
 */
export class CompetitorAgent extends BaseProtocolAgent {
  /** Track tournament entries */
  private entries: Map<Address, TournamentEntry> = new Map();

  /** Win/loss statistics */
  private stats = {
    entered: 0,
    won: 0,
    lost: 0,
    totalSpent: 0n,
    totalWon: 0n,
  };

  async step(ctx: TickContext): Promise<Action | null> {
    const enterProb = (this.params.enterProbability as number | undefined) ?? 0.3;
    const maxFee = (this.params.maxEntryFee as bigint | undefined) ?? BigInt(100e18);
    const maxEntries = (this.params.maxActiveEntries as number | undefined) ?? 5;

    // Priority 1: Claim any prizes we've won
    const claimAction = this.considerClaimingPrizes(ctx);
    if (claimAction) return claimAction;

    // Priority 2: Enter new tournaments
    const activeEntries = Array.from(this.entries.values()).filter(
      (e) => !e.prizeClaimed && !e.won
    );
    if (activeEntries.length < maxEntries && this.shouldAct(ctx, enterProb)) {
      const enterAction = this.considerEnteringTournament(ctx, maxFee);
      if (enterAction) return enterAction;
    }

    return null;
  }

  /**
   * Consider entering a tournament
   */
  private considerEnteringTournament(ctx: TickContext, maxFee: bigint): Action | null {
    // Get available tournaments from base class
    const tournaments = Array.from(this.activeTournaments.values());

    // Filter for affordable tournaments
    const affordable = tournaments.filter((t) => {
      if (t.entryFee > maxFee) return false;
      // Check if we already entered
      if (this.entries.has(t.address)) return false;
      // Check if we can afford entry
      return this.canAffordTournamentEntry(t.entryFee, t.token);
    });

    if (affordable.length === 0) return null;

    const tournament = ctx.rng.pickOne(affordable);

    ctx.logger.info(
      { agent: this.id, tournament: tournament.address, fee: this.formatElta(tournament.entryFee) },
      'Entering tournament'
    );

    // Track entry
    this.entries.set(tournament.address, {
      address: tournament.address,
      entryFee: tournament.entryFee,
      entryToken: tournament.token,
      enteredAt: ctx.tick,
      won: false,
      prizeAmount: 0n,
      prizeClaimed: false,
    });

    this.stats.entered++;
    this.stats.totalSpent += tournament.entryFee;

    return this.createAction(
      'enter_tournament',
      enterTournament(tournament.address, tournament.token, tournament.entryFee),
      ctx.tick
    );
  }

  /**
   * Consider claiming prizes from won tournaments
   */
  private considerClaimingPrizes(ctx: TickContext): Action | null {
    for (const [address, entry] of this.entries) {
      if (entry.won && !entry.prizeClaimed && entry.prizeAmount > 0n) {
        entry.prizeClaimed = true;
        this.stats.totalWon += entry.prizeAmount;

        ctx.logger.info(
          { agent: this.id, tournament: address, prize: this.formatElta(entry.prizeAmount) },
          'Claiming tournament prize'
        );

        // Note: In real implementation, would need the actual Merkle proof
        // For simulation, we use an empty proof
        return this.createAction(
          'claim_tournament_prize',
          claimTournamentPrize(address, [], entry.prizeAmount),
          ctx.tick
        );
      }
    }
    return null;
  }

  /**
   * Record that we won a tournament
   */
  recordWin(tournamentAddress: Address, prizeAmount: bigint): void {
    const entry = this.entries.get(tournamentAddress);
    if (entry) {
      entry.won = true;
      entry.prizeAmount = prizeAmount;
      this.stats.won++;
    }
  }

  /**
   * Record that we lost a tournament
   */
  recordLoss(tournamentAddress: Address): void {
    const entry = this.entries.get(tournamentAddress);
    if (entry) {
      entry.won = false;
      this.stats.lost++;
    }
  }

  /**
   * Get tournament statistics
   */
  getTournamentStats(): typeof this.stats {
    return { ...this.stats };
  }

  /**
   * Register an available tournament
   */
  registerAvailableTournament(address: Address, entryFee: bigint, token: Address): void {
    this.activeTournaments.set(address.toLowerCase(), {
      address,
      entryFee,
      token,
    });
  }

  /**
   * Remove a tournament from available list (e.g., finalized)
   */
  removeTournament(address: Address): void {
    this.activeTournaments.delete(address.toLowerCase());
  }
}
