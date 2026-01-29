/**
 * TournamentOrganizerAgent - Creates and manages tournaments
 *
 * Behavior:
 * - Creates tournaments for apps with varying entry fees
 * - Finalizes tournaments with winner lists
 * - Tracks tournament lifecycle across ticks
 *
 * Note: Tournament creation requires being an app token owner,
 * so this agent should be used alongside DeveloperAgent.
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import type { Address } from 'viem';
import { createTournament, finalizeTournament } from '../actions/index.js';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Tournament tracking state
 */
interface TournamentState {
  address: Address;
  appId: string;
  entryFee: bigint;
  entryToken: Address;
  createdAt: number;
  finalized: boolean;
  participants: Address[];
}

/**
 * Parameters for TournamentOrganizerAgent
 */
export interface TournamentOrganizerAgentParams extends BaseProtocolAgentParams {
  /** Probability of creating tournament each tick */
  createProbability?: number;
  /** Probability of finalizing eligible tournaments */
  finalizeProbability?: number;
  /** Minimum ticks before finalizing */
  minTournamentDuration?: number;
  /** Default entry fee in wei */
  defaultEntryFee?: bigint;
  /** Maximum active tournaments */
  maxActiveTournaments?: number;
}

/**
 * Agent that organizes and manages tournaments
 */
export class TournamentOrganizerAgent extends BaseProtocolAgent {
  /** Track tournaments we've created */
  private tournaments: Map<Address, TournamentState> = new Map();

  /** Counter for tournament naming */
  private tournamentCounter = 0;

  async step(ctx: TickContext): Promise<Action | null> {
    const createProb = (this.params.createProbability as number | undefined) ?? 0.15;
    const finalizeProb = (this.params.finalizeProbability as number | undefined) ?? 0.5;
    const minDuration = (this.params.minTournamentDuration as number | undefined) ?? 10;
    const maxActive = (this.params.maxActiveTournaments as number | undefined) ?? 5;

    // Priority 1: Finalize eligible tournaments
    const finalizeAction = this.considerFinalizingTournaments(ctx, minDuration, finalizeProb);
    if (finalizeAction) return finalizeAction;

    // Priority 2: Create new tournaments
    const activeTournaments = Array.from(this.tournaments.values()).filter((t) => !t.finalized);
    if (activeTournaments.length < maxActive && this.shouldAct(ctx, createProb)) {
      const createAction = this.considerCreatingTournament(ctx);
      if (createAction) return createAction;
    }

    return null;
  }

  /**
   * Consider creating a new tournament
   */
  private considerCreatingTournament(ctx: TickContext): Action | null {
    const defaultFee = (this.params.defaultEntryFee as bigint | undefined) ?? BigInt(10e18);

    // Find an app to create tournament for
    const apps = Array.from(this.getAllApps().values());
    if (apps.length === 0) return null;

    const app = ctx.rng.pickOne(apps);
    this.tournamentCounter++;

    // Get ELTA address for entry token (could also use app token)
    const state = this.getWorldState();
    const entryToken = state.elta;

    // Tournament timing: start next tick, run for minDuration ticks
    const currentTime = BigInt(Date.now() / 1000);
    const startTime = currentTime + 3600n; // Start in 1 hour
    const endTime = startTime + 86400n; // Run for 24 hours
    const maxParticipants = 100n;

    ctx.logger.info(
      { agent: this.id, app: app.id, entryFee: this.formatElta(defaultFee) },
      `Creating tournament #${this.tournamentCounter} for app`
    );

    return this.createAction(
      'create_tournament',
      createTournament(String(app.id), entryToken, defaultFee, startTime, endTime, maxParticipants),
      ctx.tick
    );
  }

  /**
   * Consider finalizing tournaments that are ready
   */
  private considerFinalizingTournaments(
    ctx: TickContext,
    minDuration: number,
    probability: number
  ): Action | null {
    const eligibleTournaments = Array.from(this.tournaments.values()).filter(
      (t) => !t.finalized && ctx.tick - t.createdAt >= minDuration
    );

    if (eligibleTournaments.length === 0) return null;

    if (!this.shouldAct(ctx, probability)) return null;

    const tournament = ctx.rng.pickOne(eligibleTournaments);

    ctx.logger.info(
      {
        agent: this.id,
        tournament: tournament.address,
        participants: tournament.participants.length,
      },
      'Finalizing tournament'
    );

    // Mark as finalized
    tournament.finalized = true;

    // Generate a simple winners root (in real scenario would be based on competition results)
    // Using a deterministic hash based on tournament address for reproducibility
    const winnersRoot = `0x${'0'.repeat(64)}` as `0x${string}`;

    return this.createAction(
      'finalize_tournament',
      finalizeTournament(tournament.address, winnersRoot),
      ctx.tick
    );
  }

  /**
   * Register a tournament we've created
   */
  registerTournament(
    address: Address,
    appId: string,
    entryFee: bigint,
    entryToken: Address,
    tick: number
  ): void {
    this.tournaments.set(address, {
      address,
      appId,
      entryFee,
      entryToken,
      createdAt: tick,
      finalized: false,
      participants: [],
    });
  }

  /**
   * Record a participant entering one of our tournaments
   */
  recordParticipant(tournamentAddress: Address, participant: Address): void {
    const tournament = this.tournaments.get(tournamentAddress);
    if (tournament) {
      tournament.participants.push(participant);
    }
  }

  /**
   * Get all active (non-finalized) tournaments
   */
  getActiveTournaments(): TournamentState[] {
    return Array.from(this.tournaments.values()).filter((t) => !t.finalized);
  }
}
