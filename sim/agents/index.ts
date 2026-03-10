/**
 * Agent exports for Elata Protocol simulation
 */

// Base agent
export { BaseProtocolAgent, PassiveAgent } from './BaseProtocolAgent.js';
export type {
  BaseProtocolAgentParams,
  ProbabilityAction,
  ErrorCategory,
  CategorizedError,
} from './BaseProtocolAgent.js';

// User agents
export {
  BasicUserAgent,
  WhaleUserAgent,
  CautiousUserAgent,
  UserAgent,
} from './UserAgent.js';
export type { BasicUserAgentParams, WhaleUserAgentParams } from './UserAgent.js';

// Developer agents
export {
  DeveloperAgent,
  SerialDeveloperAgent,
  QualityDeveloperAgent,
} from './DeveloperAgent.js';
export type { DeveloperAgentParams, SerialDeveloperAgentParams } from './DeveloperAgent.js';

// Staker agents
export { StakerAgent } from './StakerAgent.js';
export type { StakerAgentParams } from './StakerAgent.js';

// App staker agents
export { AppStakerAgent } from './AppStakerAgent.js';
export type { AppStakerAgentParams } from './AppStakerAgent.js';

// Reward hunter agents
export { RewardHunterAgent } from './RewardHunterAgent.js';
export type { RewardHunterAgentParams } from './RewardHunterAgent.js';

// Arbitrager agents
export { ArbitragerAgent } from './ArbitragerAgent.js';
export type { ArbitragerAgentParams } from './ArbitragerAgent.js';

// Fee pipeline agents
export { FeeKeeperAgent } from './FeeKeeperAgent.js';
export type { FeeKeeperAgentParams } from './FeeKeeperAgent.js';

// Governance agents
export { GovernorAgent } from './GovernorAgent.js';
export type { GovernorAgentParams } from './GovernorAgent.js';

export { VoterAgent } from './VoterAgent.js';
export type { VoterAgentParams } from './VoterAgent.js';

// Tournament agents
export { TournamentOrganizerAgent } from './TournamentOrganizerAgent.js';
export type { TournamentOrganizerAgentParams } from './TournamentOrganizerAgent.js';

export { CompetitorAgent } from './CompetitorAgent.js';
export type { CompetitorAgentParams } from './CompetitorAgent.js';

// Content/NFT agents
export { ContentCreatorAgent } from './ContentCreatorAgent.js';
export type { ContentCreatorAgentParams } from './ContentCreatorAgent.js';

export { CollectorAgent } from './CollectorAgent.js';
export type { CollectorAgentParams } from './CollectorAgent.js';

// Referral agents
export { ReferrerAgent } from './ReferrerAgent.js';
export type { ReferrerAgentParams } from './ReferrerAgent.js';

// Airdrop agents
export { AirdropHunterAgent } from './AirdropHunterAgent.js';
export type { AirdropHunterAgentParams } from './AirdropHunterAgent.js';

// Vesting agents
export { VestingBeneficiaryAgent } from './VestingBeneficiaryAgent.js';
export type { VestingBeneficiaryAgentParams } from './VestingBeneficiaryAgent.js';

// Adversarial agents
export { ManipulatorAgent } from './ManipulatorAgent.js';
export type { ManipulatorAgentParams } from './ManipulatorAgent.js';

export { SpammerAgent } from './SpammerAgent.js';
export type { SpammerAgentParams } from './SpammerAgent.js';

// ===========================================
// NEW TRADING AGENTS
// ===========================================

export { DegenTraderAgent } from './DegenTraderAgent.js';
export type { DegenTraderAgentParams } from './DegenTraderAgent.js';

export { ScalperAgent } from './ScalperAgent.js';
export type { ScalperAgentParams } from './ScalperAgent.js';

export { MomentumTraderAgent } from './MomentumTraderAgent.js';
export type { MomentumTraderAgentParams } from './MomentumTraderAgent.js';

export { ContrarianTraderAgent } from './ContrarianTraderAgent.js';
export type { ContrarianTraderAgentParams } from './ContrarianTraderAgent.js';

export { DollarCostAveragerAgent } from './DollarCostAveragerAgent.js';
export type { DollarCostAveragerAgentParams } from './DollarCostAveragerAgent.js';

export { LiquidityProviderAgent } from './LiquidityProviderAgent.js';
export type { LiquidityProviderAgentParams } from './LiquidityProviderAgent.js';

// ===========================================
// NEW STAKING AGENTS
// ===========================================

export { VeELTAManagerAgent } from './VeELTAManagerAgent.js';
export type { VeELTAManagerAgentParams } from './VeELTAManagerAgent.js';

export { LockOptimizerAgent } from './LockOptimizerAgent.js';
export type { LockOptimizerAgentParams } from './LockOptimizerAgent.js';

export { YieldMaximizerAgent } from './YieldMaximizerAgent.js';
export type { YieldMaximizerAgentParams } from './YieldMaximizerAgent.js';

export { CompoundingStakerAgent } from './CompoundingStakerAgent.js';
export type { CompoundingStakerAgentParams } from './CompoundingStakerAgent.js';

// ===========================================
// NEW CONTENT AGENTS
// ===========================================

export { ContentBuyerAgent } from './ContentBuyerAgent.js';
export type { ContentBuyerAgentParams } from './ContentBuyerAgent.js';

export { NFTCollectorAgent } from './NFTCollectorAgent.js';
export type { NFTCollectorAgentParams } from './NFTCollectorAgent.js';

export { ContentFlipperAgent } from './ContentFlipperAgent.js';
export type { ContentFlipperAgentParams } from './ContentFlipperAgent.js';

export { PremiumContentCreatorAgent } from './PremiumContentCreatorAgent.js';
export type { PremiumContentCreatorAgentParams } from './PremiumContentCreatorAgent.js';

// ===========================================
// NEW TOURNAMENT AGENTS
// ===========================================

export { TournamentPlayerAgent } from './TournamentPlayerAgent.js';
export type { TournamentPlayerAgentParams } from './TournamentPlayerAgent.js';

export { TournamentGrinderAgent } from './TournamentGrinderAgent.js';
export type { TournamentGrinderAgentParams } from './TournamentGrinderAgent.js';

export { PrizeHunterAgent } from './PrizeHunterAgent.js';
export type { PrizeHunterAgentParams } from './PrizeHunterAgent.js';

// ===========================================
// NEW ECOSYSTEM AGENTS
// ===========================================

export { ReferralNetworkBuilderAgent } from './ReferralNetworkBuilderAgent.js';
export type { ReferralNetworkBuilderAgentParams } from './ReferralNetworkBuilderAgent.js';

export { XPFarmerAgent } from './XPFarmerAgent.js';
export type { XPFarmerAgentParams } from './XPFarmerAgent.js';

export { AirdropSniperAgent } from './AirdropSniperAgent.js';
export type { AirdropSniperAgentParams } from './AirdropSniperAgent.js';

export { VestingManagerAgent } from './VestingManagerAgent.js';
export type { VestingManagerAgentParams } from './VestingManagerAgent.js';

export { ProtocolKeeperAgent } from './ProtocolKeeperAgent.js';
export type { ProtocolKeeperAgentParams } from './ProtocolKeeperAgent.js';

export { GovernanceDelegateAgent } from './GovernanceDelegateAgent.js';
export type { GovernanceDelegateAgentParams } from './GovernanceDelegateAgent.js';

// ===========================================
// NEW DEVELOPER AGENTS
// ===========================================

export { FullStackDeveloperAgent } from './FullStackDeveloperAgent.js';
export type { FullStackDeveloperAgentParams } from './FullStackDeveloperAgent.js';

export { ModuleDeployerAgent } from './ModuleDeployerAgent.js';
export type { ModuleDeployerAgentParams } from './ModuleDeployerAgent.js';

export { AppGraduatorAgent } from './AppGraduatorAgent.js';
export type { AppGraduatorAgentParams } from './AppGraduatorAgent.js';

// ===========================================
// DETERMINISTIC PROTOCOL AGENTS
// ===========================================

export { EpochFeeClaimerAgent } from './EpochFeeClaimerAgent.js';
export type { EpochFeeClaimerAgentParams } from './EpochFeeClaimerAgent.js';

export { ThresholdRebalancerAgent } from './ThresholdRebalancerAgent.js';
export type { ThresholdRebalancerAgentParams } from './ThresholdRebalancerAgent.js';

export { GovernanceStrategistAgent } from './GovernanceStrategistAgent.js';
export type { GovernanceStrategistAgentParams } from './GovernanceStrategistAgent.js';

export { LiquidityDefenderAgent } from './LiquidityDefenderAgent.js';
export type { LiquidityDefenderAgentParams } from './LiquidityDefenderAgent.js';

// ===========================================
// NON-DETERMINISTIC PROTOCOL AGENTS
// ===========================================

export { RegimeNoiseTraderAgent } from './RegimeNoiseTraderAgent.js';
export type { RegimeNoiseTraderAgentParams } from './RegimeNoiseTraderAgent.js';

export { BurstyCreatorAgent } from './BurstyCreatorAgent.js';
export type { BurstyCreatorAgentParams } from './BurstyCreatorAgent.js';

export { ProbabilisticStakerAgent } from './ProbabilisticStakerAgent.js';
export type { ProbabilisticStakerAgentParams } from './ProbabilisticStakerAgent.js';

export { OpportunisticAttackerAgent } from './OpportunisticAttackerAgent.js';
export type { OpportunisticAttackerAgentParams } from './OpportunisticAttackerAgent.js';

// ===========================================
// LLM + GOSSIP AGENTS
// ===========================================

export { LlmGossipCoordinatorAgent } from './LlmGossipCoordinatorAgent.js';
export type { LlmGossipCoordinatorAgentParams } from './LlmGossipCoordinatorAgent.js';
export { BaseElataPersonaLlmAgent } from './BaseElataPersonaLlmAgent.js';
export type { BaseElataPersonaLlmAgentParams } from './BaseElataPersonaLlmAgent.js';
export { CreatorPersonaAgent } from './CreatorPersonaAgent.js';
export { EconomicPersonaAgent } from './EconomicPersonaAgent.js';
export { BadActorPersonaAgent } from './BadActorPersonaAgent.js';
export { SaboteurPersonaAgent } from './SaboteurPersonaAgent.js';
export { HackerPersonaAgent } from './HackerPersonaAgent.js';

