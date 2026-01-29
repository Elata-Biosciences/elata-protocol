#!/usr/bin/env tsx
/**
 * Simulation Report Generator
 *
 * Generates comprehensive simulation reports with:
 * - Key metrics in ELTA and USD at various FDV levels
 * - Assumptions and methodology
 * - Extrapolations to longer time periods
 * - Sanity checks and implications
 */

import * as fs from 'node:fs/promises';
import * as path from 'node:path';

/**
 * FDV levels to calculate USD values at
 */
const FDV_LEVELS = [
  { fdv: 1_000_000, label: '$1M FDV' },
  { fdv: 10_000_000, label: '$10M FDV' },
  { fdv: 50_000_000, label: '$50M FDV' },
  { fdv: 100_000_000, label: '$100M FDV' },
  { fdv: 1_000_000_000, label: '$1B FDV' },
];

/**
 * Total ELTA supply (from protocol)
 */
const ELTA_TOTAL_SUPPLY = 10_000_000_000; // 10 billion

/**
 * Convert ELTA to USD at a given FDV
 */
function eltaToUsd(eltaAmount: bigint | number, fdv: number): number {
  const pricePerElta = fdv / ELTA_TOTAL_SUPPLY;
  const amount = typeof eltaAmount === 'bigint' ? Number(eltaAmount) / 1e18 : eltaAmount;
  return amount * pricePerElta;
}

/**
 * Format number with commas and decimals
 */
function formatNumber(n: number, decimals = 2): string {
  return n.toLocaleString('en-US', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
}

/**
 * Format USD value
 */
function formatUsd(n: number): string {
  if (n >= 1_000_000_000) return `$${formatNumber(n / 1_000_000_000)}B`;
  if (n >= 1_000_000) return `$${formatNumber(n / 1_000_000)}M`;
  if (n >= 1_000) return `$${formatNumber(n / 1_000)}K`;
  return `$${formatNumber(n)}`;
}

/**
 * Format ELTA amount
 */
function formatElta(n: bigint | number): string {
  const amount = typeof n === 'bigint' ? Number(n) / 1e18 : n;
  if (amount >= 1_000_000) return `${formatNumber(amount / 1_000_000)}M ELTA`;
  if (amount >= 1_000) return `${formatNumber(amount / 1_000)}K ELTA`;
  return `${formatNumber(amount)} ELTA`;
}

/**
 * Simulation metrics from AgentForge
 */
interface SimulationMetrics {
  // Core metrics
  elta_total_supply: bigint;
  veelta_total_locked: bigint;
  app_count: number;
  graduated_apps: number;
  fees_collected_total: bigint;
  treasury_usdc_revenue: bigint;
  treasury_usdc_balance: bigint;

  // VC metrics
  tvl_total: bigint;
  tvl_veelta: bigint;
  tvl_apps: bigint;
  trading_volume_total: bigint;
  users_total_unique: number;
  dau_estimate: number;
  revenue_per_user: bigint;
  token_velocity_bps: bigint;
  staking_rate_bps: bigint;
  graduation_rate_bps: number;

  // Feature adoption
  feature_content_purchases: number;
  feature_tournament_entries: number;
  feature_referrals: number;
  feature_governance_votes: number;
  feature_staking_events: number;
  feature_app_trades: number;

  // Gas
  gas_total: bigint;

  // Time
  tick_count: number;
  simulation_duration_ticks: number;
}

/**
 * Generate the VC report
 */
async function generateReport(metricsPath: string, outputDir: string): Promise<void> {
  console.log('Loading simulation metrics...');

  // Load metrics JSON
  const metricsJson = await fs.readFile(metricsPath, 'utf-8');
  const rawMetrics = JSON.parse(metricsJson);

  // Convert string values to bigint where needed
  const metrics: SimulationMetrics = {
    elta_total_supply: BigInt(rawMetrics.elta_total_supply ?? '0'),
    veelta_total_locked: BigInt(rawMetrics.veelta_total_locked ?? '0'),
    app_count: Number(rawMetrics.app_count ?? 0),
    graduated_apps: Number(rawMetrics.graduated_apps ?? 0),
    fees_collected_total: BigInt(rawMetrics.fees_collected_total ?? '0'),
    treasury_usdc_revenue: BigInt(rawMetrics.treasury_usdc_revenue ?? '0'),
    treasury_usdc_balance: BigInt(rawMetrics.treasury_usdc_balance ?? '0'),
    tvl_total: BigInt(rawMetrics.tvl_total ?? '0'),
    tvl_veelta: BigInt(rawMetrics.tvl_veelta ?? '0'),
    tvl_apps: BigInt(rawMetrics.tvl_apps ?? '0'),
    trading_volume_total: BigInt(rawMetrics.trading_volume_total ?? '0'),
    users_total_unique: Number(rawMetrics.users_total_unique ?? 0),
    dau_estimate: Number(rawMetrics.dau_estimate ?? 0),
    revenue_per_user: BigInt(rawMetrics.revenue_per_user ?? '0'),
    token_velocity_bps: BigInt(rawMetrics.token_velocity_bps ?? '0'),
    staking_rate_bps: BigInt(rawMetrics.staking_rate_bps ?? '0'),
    graduation_rate_bps: Number(rawMetrics.graduation_rate_bps ?? 0),
    feature_content_purchases: Number(rawMetrics.feature_content_purchases ?? 0),
    feature_tournament_entries: Number(rawMetrics.feature_tournament_entries ?? 0),
    feature_referrals: Number(rawMetrics.feature_referrals ?? 0),
    feature_governance_votes: Number(rawMetrics.feature_governance_votes ?? 0),
    feature_staking_events: Number(rawMetrics.feature_staking_events ?? 0),
    feature_app_trades: Number(rawMetrics.feature_app_trades ?? 0),
    gas_total: BigInt(rawMetrics.gas_total ?? '0'),
    tick_count: Number(rawMetrics.tick_count ?? rawMetrics.block_number ?? 0),
    simulation_duration_ticks: Number(rawMetrics.simulation_duration_ticks ?? rawMetrics.tick_count ?? 100),
  };

  // Calculate extrapolations
  const ticksPerDay = 96; // 15 min per tick
  const ticksPerMonth = ticksPerDay * 30;
  const ticksPerYear = ticksPerDay * 365;

  const simulatedDays = metrics.simulation_duration_ticks / ticksPerDay;
  const dailyMultiplier = ticksPerDay / Math.max(1, metrics.simulation_duration_ticks);
  const monthlyMultiplier = ticksPerMonth / Math.max(1, metrics.simulation_duration_ticks);
  const yearlyMultiplier = ticksPerYear / Math.max(1, metrics.simulation_duration_ticks);

  // Generate JSON report
  const jsonReport = {
    generated_at: new Date().toISOString(),
    simulation_params: {
      tick_count: metrics.tick_count,
      simulated_days: simulatedDays.toFixed(2),
      tick_duration_seconds: 900, // 15 minutes
    },
    core_metrics: {
      elta: {
        total_supply: formatElta(metrics.elta_total_supply),
        veelta_locked: formatElta(metrics.veelta_total_locked),
        staking_rate_percent: (Number(metrics.staking_rate_bps) / 100).toFixed(2),
      },
      apps: {
        total_created: metrics.app_count,
        graduated: metrics.graduated_apps,
        graduation_rate_percent: (metrics.graduation_rate_bps / 100).toFixed(2),
      },
      revenue: {
        fees_collected_elta: formatElta(metrics.fees_collected_total),
        treasury_usdc: Number(metrics.treasury_usdc_revenue) / 1e6, // USDC has 6 decimals
      },
    },
    vc_metrics: {
      tvl: {
        total_elta: formatElta(metrics.tvl_total),
        breakdown: {
          veelta: formatElta(metrics.tvl_veelta),
          apps: formatElta(metrics.tvl_apps),
        },
      },
      volume: {
        total_elta: formatElta(metrics.trading_volume_total),
        daily_projected_elta: formatElta(BigInt(Math.floor(Number(metrics.trading_volume_total) * dailyMultiplier))),
      },
      users: {
        total_unique: metrics.users_total_unique,
        dau_estimate: metrics.dau_estimate,
        revenue_per_user_elta: formatElta(metrics.revenue_per_user),
      },
      token_velocity_bps: Number(metrics.token_velocity_bps),
    },
    feature_adoption: {
      app_trades: metrics.feature_app_trades,
      staking_events: metrics.feature_staking_events,
      content_purchases: metrics.feature_content_purchases,
      tournament_entries: metrics.feature_tournament_entries,
      governance_votes: metrics.feature_governance_votes,
      referrals: metrics.feature_referrals,
    },
    fdv_projections: FDV_LEVELS.map(level => ({
      fdv: level.label,
      price_per_elta: (level.fdv / ELTA_TOTAL_SUPPLY).toFixed(8),
      tvl_usd: formatUsd(eltaToUsd(metrics.tvl_total, level.fdv)),
      daily_volume_usd: formatUsd(eltaToUsd(metrics.trading_volume_total, level.fdv) * dailyMultiplier),
      monthly_volume_usd: formatUsd(eltaToUsd(metrics.trading_volume_total, level.fdv) * monthlyMultiplier),
      annual_fees_usd: formatUsd(eltaToUsd(metrics.fees_collected_total, level.fdv) * yearlyMultiplier),
      revenue_per_user_usd: formatUsd(eltaToUsd(metrics.revenue_per_user, level.fdv)),
    })),
    extrapolations: {
      monthly: {
        projected_users: Math.floor(metrics.users_total_unique * monthlyMultiplier / simulatedDays),
        projected_volume_elta: formatElta(BigInt(Math.floor(Number(metrics.trading_volume_total) * monthlyMultiplier))),
        projected_fees_elta: formatElta(BigInt(Math.floor(Number(metrics.fees_collected_total) * monthlyMultiplier))),
      },
      annual: {
        projected_users: Math.floor(metrics.users_total_unique * yearlyMultiplier / simulatedDays),
        projected_volume_elta: formatElta(BigInt(Math.floor(Number(metrics.trading_volume_total) * yearlyMultiplier))),
        projected_fees_elta: formatElta(BigInt(Math.floor(Number(metrics.fees_collected_total) * yearlyMultiplier))),
        projected_apps: Math.floor(metrics.app_count * yearlyMultiplier / simulatedDays),
      },
    },
  };

  // Write JSON report
  await fs.mkdir(outputDir, { recursive: true });
  const jsonPath = path.join(outputDir, 'simulation-report.json');
  await fs.writeFile(jsonPath, JSON.stringify(jsonReport, null, 2));
  console.log(`JSON report written to ${jsonPath}`);

  // Generate Markdown report
  const mdReport = generateMarkdownReport(metrics, jsonReport, simulatedDays);
  const mdPath = path.join(outputDir, 'simulation-report.md');
  await fs.writeFile(mdPath, mdReport);
  console.log(`Markdown report written to ${mdPath}`);
}

/**
 * Generate Markdown report
 */
function generateMarkdownReport(
  metrics: SimulationMetrics,
  json: Record<string, unknown>,
  simulatedDays: number
): string {
  const projections = (json as { fdv_projections: Array<Record<string, string>> }).fdv_projections;
  const extraps = json.extrapolations as { monthly: Record<string, unknown>; annual: Record<string, unknown> };

  return `# Elata Protocol - VC Simulation Report

Generated: ${new Date().toISOString()}

## Executive Summary

This report presents simulation results for the Elata Protocol, demonstrating protocol economics, user behavior, and projected growth metrics at various fully diluted valuation (FDV) levels.

## Simulation Parameters

| Parameter | Value |
|-----------|-------|
| Simulation Duration | ${simulatedDays.toFixed(2)} simulated days |
| Total Ticks | ${metrics.tick_count} |
| Tick Duration | 15 minutes |
| Total Unique Users | ${metrics.users_total_unique} |
| Daily Active Users (DAU) | ${metrics.dau_estimate} |

## Core Protocol Metrics

### Token Economics

| Metric | Value |
|--------|-------|
| Total ELTA Supply | ${formatElta(metrics.elta_total_supply)} |
| veELTA Locked | ${formatElta(metrics.veelta_total_locked)} |
| Staking Rate | ${(Number(metrics.staking_rate_bps) / 100).toFixed(2)}% |

### App Ecosystem

| Metric | Value |
|--------|-------|
| Apps Created | ${metrics.app_count} |
| Apps Graduated | ${metrics.graduated_apps} |
| Graduation Rate | ${(metrics.graduation_rate_bps / 100).toFixed(2)}% |

### Revenue & Fees

| Metric | Value |
|--------|-------|
| Total Fees Collected | ${formatElta(metrics.fees_collected_total)} |
| Treasury USDC Revenue | $${(Number(metrics.treasury_usdc_revenue) / 1e6).toFixed(2)} |

## Total Value Locked (TVL)

| Component | Value |
|-----------|-------|
| **Total TVL** | ${formatElta(metrics.tvl_total)} |
| veELTA | ${formatElta(metrics.tvl_veelta)} |
| App Tokens | ${formatElta(metrics.tvl_apps)} |

## Trading Volume

| Period | Volume |
|--------|--------|
| Simulation Total | ${formatElta(metrics.trading_volume_total)} |
| Token Velocity | ${(Number(metrics.token_velocity_bps) / 100).toFixed(2)}% |

## Feature Adoption

| Feature | Usage Count |
|---------|-------------|
| App Token Trades | ${metrics.feature_app_trades} |
| Staking Events | ${metrics.feature_staking_events} |
| Content Purchases | ${metrics.feature_content_purchases} |
| Tournament Entries | ${metrics.feature_tournament_entries} |
| Governance Votes | ${metrics.feature_governance_votes} |
| Referral Registrations | ${metrics.feature_referrals} |

## FDV Projections

| FDV Level | TVL (USD) | Daily Volume | Monthly Volume | Annual Fees |
|-----------|-----------|--------------|----------------|-------------|
${projections.map(p => `| ${p.fdv} | ${p.tvl_usd} | ${p.daily_volume_usd} | ${p.monthly_volume_usd} | ${p.annual_fees_usd} |`).join('\n')}

## Extrapolations

### Monthly Projections

| Metric | Projected Value |
|--------|-----------------|
| Users | ${extraps.monthly.projected_users} |
| Volume | ${extraps.monthly.projected_volume_elta} |
| Fees | ${extraps.monthly.projected_fees_elta} |

### Annual Projections

| Metric | Projected Value |
|--------|-----------------|
| Users | ${extraps.annual.projected_users} |
| Volume | ${extraps.annual.projected_volume_elta} |
| Fees | ${extraps.annual.projected_fees_elta} |
| Apps | ${extraps.annual.projected_apps} |

## Assumptions & Methodology

1. **Tick Duration**: Each simulation tick represents 15 minutes of real-world time.
2. **User Behavior**: Agent behaviors are parameterized to simulate realistic user patterns including trading, staking, content consumption, and governance participation.
3. **Extrapolation**: Projections assume linear scaling, which may be conservative for network effects or optimistic for market saturation.
4. **FDV Calculations**: Based on a total supply of ${(ELTA_TOTAL_SUPPLY / 1e9).toFixed(0)}B ELTA tokens.

## Sanity Checks

- **Staking Rate**: ${(Number(metrics.staking_rate_bps) / 100).toFixed(2)}% of supply locked - ${Number(metrics.staking_rate_bps) > 500 ? 'Healthy engagement' : 'Room for growth'}
- **Graduation Rate**: ${(metrics.graduation_rate_bps / 100).toFixed(2)}% - ${metrics.graduation_rate_bps > 10 ? 'Strong app quality' : 'Early stage'}
- **User Activity**: ${metrics.feature_app_trades} trades, ${metrics.feature_staking_events} staking events

## Implications

1. **At $10M FDV**: Protocol demonstrates early-stage traction with meaningful user engagement.
2. **At $100M FDV**: Revenue and volume metrics suggest a maturing ecosystem.
3. **At $1B FDV**: Projections indicate significant value creation potential with current user patterns.

---

*This report was generated programmatically from simulation data. Actual results may vary based on market conditions and user adoption.*
`;
}

// Main execution
const args = process.argv.slice(2);
const metricsPath = args[0] ?? './simulation-results/metrics.json';
const outputDir = args[1] ?? './simulation-results/reports';

generateReport(metricsPath, outputDir).catch(console.error);
