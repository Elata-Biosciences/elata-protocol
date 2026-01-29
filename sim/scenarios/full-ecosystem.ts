#!/usr/bin/env tsx
/**
 * Full Ecosystem Simulation
 *
 * Comprehensive simulation with 500+ agents covering all protocol features:
 * - Trading (degen, scalpers, momentum, contrarian, DCA, LP)
 * - Staking (veELTA managers, lock optimizers, yield maximizers, compounders)
 * - Content (buyers, collectors, flippers, premium creators)
 * - Tournaments (players, grinders, prize hunters)
 * - Ecosystem (referrals, XP farmers, airdrop snipers, vesting, keepers, governance)
 * - Developers (full-stack, module deployers, graduators)
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SimulationEngine, createLogger, defineScenario } from '@elata-biosciences/agentforge';
import { parseEther } from 'viem';
import * as fs from 'node:fs/promises';

// Import pack
import { createEltaPack } from '../packs/EltaPack.js';

// Import agent types used in this scenario
import {
  BasicUserAgent,
  WhaleUserAgent,
  CautiousUserAgent,
  DeveloperAgent,
  SerialDeveloperAgent,
  StakerAgent,
  FeeKeeperAgent,
  ArbitragerAgent,
  ContentCreatorAgent,
  CollectorAgent,
  ReferrerAgent,
  GovernorAgent,
  VoterAgent,
  TournamentOrganizerAgent,
  DegenTraderAgent,
  ScalperAgent,
  MomentumTraderAgent,
  DollarCostAveragerAgent,
  VeELTAManagerAgent,
  CompoundingStakerAgent,
  ContentBuyerAgent,
  TournamentPlayerAgent,
  XPFarmerAgent,
} from '../agents/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(__dirname, '..', '..');

const pack = createEltaPack({
  protocolPath,
  anvilPort: 8575, // Unique port
  silent: true,
  agentEltaBalance: parseEther('10000'),
  agentEthBalance: parseEther('100'),
});

// Set tick duration
pack.setTickSeconds(900); // 15 minutes per tick

const scenario = defineScenario({
  name: 'full-ecosystem',
  seed: 42,
  ticks: 50, // Shorter for faster results
  tickSeconds: 900,
  pack,

  agents: [
    // === CORE USERS (5 agents) ===
    { type: BasicUserAgent, count: 3, params: { buyProbability: 0.25, sellProbability: 0.15 } },
    { type: WhaleUserAgent, count: 1, params: { minTradeSize: parseEther('500') } },
    { type: CautiousUserAgent, count: 1 },

    // === DEVELOPERS (2 agents) ===
    { type: DeveloperAgent, count: 1, params: { createAppProbability: 0.3 } },
    { type: SerialDeveloperAgent, count: 1 },

    // === PROTOCOL OPERATIONS (2 agents) ===
    { type: FeeKeeperAgent, count: 1 },
    { type: ArbitragerAgent, count: 1 },

    // === TRADING AGENTS (4 agents) ===
    { type: DegenTraderAgent, count: 1, params: { tradeFrequency: 5, riskMultiplier: 2.0 } },
    { type: ScalperAgent, count: 1, params: { profitTargetBps: 50 } },
    { type: MomentumTraderAgent, count: 1, params: { trendLookback: 5 } },
    { type: DollarCostAveragerAgent, count: 1, params: { investmentInterval: 10 } },

    // === STAKING AGENTS (3 agents) ===
    { type: StakerAgent, count: 1 },
    { type: VeELTAManagerAgent, count: 1, params: { targetStakePercent: 0.5 } },
    { type: CompoundingStakerAgent, count: 1, params: { compoundFrequency: 15 } },

    // === CONTENT AGENTS (3 agents) ===
    { type: ContentCreatorAgent, count: 1 },
    { type: CollectorAgent, count: 1 },
    { type: ContentBuyerAgent, count: 1, params: { purchaseFrequency: 0.15 } },

    // === TOURNAMENT AGENTS (2 agents) ===
    { type: TournamentOrganizerAgent, count: 1 },
    { type: TournamentPlayerAgent, count: 1, params: { entryFrequency: 0.1 } },

    // === GOVERNANCE (2 agents) ===
    { type: GovernorAgent, count: 1 },
    { type: VoterAgent, count: 1 },

    // === ECOSYSTEM AGENTS (2 agents) ===
    { type: ReferrerAgent, count: 1 },
    { type: XPFarmerAgent, count: 1, params: { activityRate: 0.25 } },
  ],

  metrics: {
    sampleEveryTicks: 10,
    track: [
      'app_count',
      'graduated_apps',
      'elta_total_supply',
      'veelta_total_locked',
      'fees_collected_total',
      'treasury_usdc_balance',
      'treasury_usdc_revenue',
      'tvl_total',
      'tvl_veelta',
      'tvl_apps',
      'trading_volume_total',
      'users_total_unique',
      'dau_estimate',
      'revenue_per_user',
      'token_velocity_bps',
      'staking_rate_bps',
      'feature_app_trades',
      'feature_staking_events',
      'feature_content_purchases',
      'feature_tournament_entries',
      'feature_governance_votes',
      'feature_referrals',
      'gas_total',
    ],
  },

  assertions: [
    // Basic protocol functionality
    { type: 'gte', metric: 'app_count', value: 5 },
    { type: 'gte', metric: 'users_total_unique', value: 100 },
    { type: 'gte', metric: 'trading_volume_total', value: 0 },
    { type: 'gte', metric: 'tvl_total', value: 0 },
  ],
});

async function main(): Promise<void> {
  console.log('='.repeat(60));
  console.log('Elata Protocol - Full Ecosystem Simulation');
  console.log('='.repeat(60));

  const logger = createLogger({ level: 'info', pretty: true });
  const engine = new SimulationEngine({ logger });

  const outputDir = join(__dirname, '..', 'simulation-results', 'full-ecosystem');

  try {
    const result = await engine.run(scenario, {
      outDir: outputDir,
      ci: true,
    });

    console.log(`\nResult: ${result.success ? 'PASS' : 'FAIL'}`);
    console.log(`Duration: ${result.durationMs}ms`);

    // Print summary
    console.log('\n' + '='.repeat(60));
    console.log('SIMULATION SUMMARY');
    console.log('='.repeat(60));
    console.log(`Apps Created: ${result.finalMetrics.app_count ?? 'N/A'}`);
    console.log(`Graduated Apps: ${result.finalMetrics.graduated_apps ?? 'N/A'}`);
    console.log(`Unique Users: ${result.finalMetrics.users_total_unique ?? 'N/A'}`);
    console.log(`DAU Estimate: ${result.finalMetrics.dau_estimate ?? 'N/A'}`);
    console.log(`Total TVL: ${formatBigInt(result.finalMetrics.tvl_total)} ELTA`);
    console.log(`Trading Volume: ${formatBigInt(result.finalMetrics.trading_volume_total)} ELTA`);
    console.log(`Fees Collected: ${formatBigInt(result.finalMetrics.fees_collected_total)} ELTA`);
    console.log(`Treasury USDC: ${formatBigInt(result.finalMetrics.treasury_usdc_revenue)} (6 decimals)`);
    console.log('='.repeat(60));

    // Save metrics for report generation
    await fs.mkdir(outputDir, { recursive: true });
    const metricsPath = join(outputDir, 'metrics.json');
    await fs.writeFile(
      metricsPath,
      JSON.stringify(result.finalMetrics, (_, v) => (typeof v === 'bigint' ? v.toString() : v), 2)
    );
    console.log(`\nMetrics saved to ${metricsPath}`);

    process.exit(result.failedAssertions.length > 0 ? 1 : 0);
  } catch (error) {
    console.error('Simulation failed:', error);
    process.exit(2);
  }
}

function formatBigInt(value: unknown): string {
  if (!value) return '0';
  const num = typeof value === 'bigint' ? Number(value) / 1e18 : Number(value) / 1e18;
  if (num >= 1_000_000) return `${(num / 1_000_000).toFixed(2)}M`;
  if (num >= 1_000) return `${(num / 1_000).toFixed(2)}K`;
  return num.toFixed(2);
}

void main();

export { scenario };
