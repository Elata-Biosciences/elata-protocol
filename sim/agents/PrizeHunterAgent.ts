/**
 * PrizeHunterAgent - Optimizes for prize opportunities
 *
 * Behavior:
 * - Hunts for best prize opportunities across tournaments
 * - Analyzes prize pools and participant counts
 * - Strategic timing of entries
 * - Multi-app prize optimization
 */

import type { Action, TickContext } from '@elata-biosciences/agentforge';
import { enterTournament, claimTournamentPrize, claimAirdrop } from '../actions/index.js';
import type { Address } from 'viem';
import { BaseProtocolAgent, type BaseProtocolAgentParams } from './BaseProtocolAgent.js';

/**
 * Prize opportunity tracking
 */
interface PrizeOpportunity {
  type: 'tournament' | 'airdrop' | 'promotion';
  address: Address;
  appId: string;
  cost: bigint;
  potentialPrize: bigint;
  expectedValue: bigint;
  enteredTick: number | null;
  result: 'available' | 'entered' | 'won' | 'lost' | 'claimed';
  actualPrize: bigint;
}

/**
 * Parameters for PrizeHunterAgent
 */
export interface PrizeHunterAgentParams extends BaseProtocolAgentParams {
  /** Minimum prize value to consider (default 50 ELTA) */
  minPrizeValue?: bigint;
  /** Risk tolerance (0-1, default 0.6) */
  riskTolerance?: number;
  /** Hunt aggressiveness (default 0.3) */
  huntFrequency?: number;
  /** Maximum concurrent hunts (default 8) */
  maxHunts?: number;
}

/**
 * Strategic prize hunter
 */
export class PrizeHunterAgent extends BaseProtocolAgent {
  /** Tracked opportunities */
  private opportunities: PrizeOpportunity[] = [];

  /** Hunt statistics */
  private stats = {
    opportunitiesFound: 0,
    opportunitiesEntered: 0,
    prizesWon: 0,
    totalCost: 0n,
    totalPrizes: 0n,
  };

  async step(ctx: TickContext): Promise<Action | null> {
    const minPrize = (this.params.minPrizeValue as bigint | undefined) ?? BigInt(50e18);
    const riskTol = (this.params.riskTolerance as number | undefined) ?? 0.6;
    const frequency = (this.params.huntFrequency as number | undefined) ?? 0.3;
    const maxHunts = (this.params.maxHunts as number | undefined) ?? 8;

    // Priority 1: Claim won prizes
    const claimAction = this.claimWonPrizes(ctx);
    if (claimAction) return claimAction;

    // Priority 2: Process results
    this.processResults(ctx, riskTol);

    // Priority 3: Scout new opportunities
    if (this.shouldAct(ctx, 0.2)) {
      this.scoutOpportunities(ctx, minPrize);
    }

    // Priority 4: Enter best opportunities
    const activeHunts = this.opportunities.filter(o => o.result === 'entered').length;
    if (activeHunts < maxHunts && this.shouldAct(ctx, frequency)) {
      return this.enterBestOpportunity(ctx, minPrize, riskTol);
    }

    return null;
  }

  /**
   * Scout for prize opportunities
   */
  private scoutOpportunities(ctx: TickContext, minPrize: bigint): void {
    for (const [appId, app] of this.getAllApps()) {
      if (app.graduated) continue;

      // Simulate finding tournament opportunities
      if (ctx.rng.nextFloat() < 0.3) {
        const prizePool = BigInt(Math.floor(Math.random() * Number(minPrize) * 10)) + minPrize;
        const entryCost = prizePool / 20n; // ~5% of prize pool

        // Calculate EV based on estimated competition
        const estParticipants = 10 + Math.floor(ctx.rng.nextFloat() * 40);
        const winChance = 1 / estParticipants * 3; // Top 3 places
        const ev = BigInt(Math.floor(Number(prizePool) * winChance));

        const address = `0x${Array(40).fill(0).map(() => 
          Math.floor(Math.random() * 16).toString(16)).join('')}` as Address;

        this.opportunities.push({
          type: 'tournament',
          address,
          appId,
          cost: entryCost,
          potentialPrize: prizePool,
          expectedValue: ev,
          enteredTick: null,
          result: 'available',
          actualPrize: 0n,
        });

        this.stats.opportunitiesFound++;
      }

      // Simulate finding airdrop opportunities
      if (ctx.rng.nextFloat() < 0.1) {
        const airdropValue = BigInt(Math.floor(Math.random() * Number(minPrize) * 5));
        if (airdropValue < minPrize) return;

        const address = `0x${Array(40).fill(0).map(() => 
          Math.floor(Math.random() * 16).toString(16)).join('')}` as Address;

        this.opportunities.push({
          type: 'airdrop',
          address,
          appId,
          cost: 0n, // Airdrops are free
          potentialPrize: airdropValue,
          expectedValue: airdropValue / 10n, // 10% chance to qualify
          enteredTick: null,
          result: 'available',
          actualPrize: 0n,
        });

        this.stats.opportunitiesFound++;
      }
    }
  }

  /**
   * Enter the best available opportunity
   */
  private enterBestOpportunity(
    ctx: TickContext,
    _minPrize: bigint,
    riskTolerance: number
  ): Action | null {
    const balance = this.getEltaBalance();

    // Sort by EV ratio (EV / cost)
    const available = this.opportunities
      .filter(o => o.result === 'available')
      .filter(o => o.cost <= balance / 2n) // Max 50% of balance per opportunity
      .sort((a, b) => {
        const ratioA = a.cost > 0n ? Number(a.expectedValue) / Number(a.cost) : Number(a.expectedValue);
        const ratioB = b.cost > 0n ? Number(b.expectedValue) / Number(b.cost) : Number(b.expectedValue);
        return ratioB - ratioA;
      });

    if (available.length === 0) return null;

    const best = available[0]!;
    const app = this.getAppState(best.appId);
    if (!app) return null;

    // Risk check
    const evRatio = best.cost > 0n 
      ? Number(best.expectedValue) / Number(best.cost) 
      : 999;
    
    if (evRatio < 1 && ctx.rng.nextFloat() > riskTolerance) {
      // Skip negative EV unless high risk tolerance
      return null;
    }

    // Enter the opportunity
    best.result = 'entered';
    best.enteredTick = ctx.tick;
    this.stats.opportunitiesEntered++;
    this.stats.totalCost += best.cost;

    ctx.logger.info(
      { 
        agent: this.id, 
        type: best.type,
        app: best.appId,
        cost: this.formatElta(best.cost),
        potentialPrize: this.formatElta(best.potentialPrize),
        evRatio: evRatio.toFixed(2)
      },
      'Hunting prize opportunity'
    );

    if (best.type === 'tournament') {
      return this.createAction(
        'enter_tournament',
        enterTournament(best.address, app.tokenAddress, best.cost),
        ctx.tick
      );
    } else {
      // For airdrops, we'd claim if eligible
      return this.createAction(
        'claim_airdrop',
        claimAirdrop(
          BigInt(1), // Campaign ID
          ['0x0000000000000000000000000000000000000000000000000000000000000001' as `0x${string}`],
          best.potentialPrize
        ),
        ctx.tick
      );
    }
  }

  /**
   * Process opportunity results
   */
  private processResults(ctx: TickContext, riskTolerance: number): void {
    const resolutionTime = 12;

    for (const opp of this.opportunities) {
      if (opp.result !== 'entered') continue;
      if (opp.enteredTick === null) continue;
      if (ctx.tick - opp.enteredTick < resolutionTime) continue;

      // Determine outcome based on opportunity type and risk
      let winChance;
      if (opp.type === 'tournament') {
        winChance = 0.2 + riskTolerance * 0.1; // 20-30%
      } else {
        winChance = 0.15; // 15% for airdrops
      }

      if (ctx.rng.nextFloat() < winChance) {
        opp.result = 'won';
        // Prize between 50-150% of potential
        const multiplier = 0.5 + ctx.rng.nextFloat();
        opp.actualPrize = BigInt(Math.floor(Number(opp.potentialPrize) * multiplier));
        this.stats.prizesWon++;
      } else {
        opp.result = 'lost';
      }
    }
  }

  /**
   * Claim won prizes
   */
  private claimWonPrizes(ctx: TickContext): Action | null {
    for (const opp of this.opportunities) {
      if (opp.result !== 'won') continue;

      opp.result = 'claimed';
      this.stats.totalPrizes += opp.actualPrize;

      ctx.logger.info(
        { 
          agent: this.id, 
          type: opp.type,
          prize: this.formatElta(opp.actualPrize),
          totalPrizes: this.formatElta(this.stats.totalPrizes)
        },
        'Prize hunter claiming reward'
      );

      const mockProof: `0x${string}`[] = [
        '0x0000000000000000000000000000000000000000000000000000000000000001' as `0x${string}`,
      ];

      return this.createAction(
        'claim_tournament_prize',
        claimTournamentPrize(opp.address, mockProof, opp.actualPrize),
        ctx.tick
      );
    }

    return null;
  }

  /**
   * Get hunter statistics
   */
  getSimStats(): {
    opportunitiesFound: number;
    opportunitiesEntered: number;
    prizesWon: number;
    totalCost: bigint;
    totalPrizes: bigint;
    roi: string;
  } {
    const roi = this.stats.totalCost > 0n
      ? (((Number(this.stats.totalPrizes) - Number(this.stats.totalCost)) / 
          Number(this.stats.totalCost)) * 100).toFixed(1) + '%'
      : '0%';

    return {
      ...this.stats,
      roi,
    };
  }
}
