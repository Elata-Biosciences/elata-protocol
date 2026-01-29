/**
 * Simulation Library - Common utilities for Elata Protocol simulations
 */

// Error handling
export {
  type ErrorCategory,
  type ErrorSeverity,
  SimulationError,
  AgentActionError,
  ContractError,
  NetworkError,
  TimeoutError,
  categorizeError,
  ErrorAggregator,
  formatError,
  formatErrorSummary,
  type ErrorSample,
  type ErrorSummary,
} from './errors.js';

// Logging
export {
  type LogEventType,
  type LogEntry,
  type ActionLogEntry,
  type ErrorLogEntry,
  type MetricLogEntry,
  type EconomicLogEntry,
  SimulationLogger,
  createSimulationLogger,
  createVerboseLogger,
  createMinimalLogger,
  type SimulationLoggerConfig,
} from './logging.js';

// Results formatting
export {
  RESULT_FORMAT_VERSION,
  type ResultMeta,
  type AssertionResult,
  type OutcomeSummary,
  type EconomicsSummary,
  type AgentPerformance,
  type MetricsSummary,
  type StandardizedResult,
  formatResult,
  exportToJSON,
  exportToMarkdown,
  exportMarkdownToFile,
  aggregateResults,
} from './results.js';

// Scenario helpers
export {
  // Port management
  allocatePort,
  releasePort,
  resetPorts,
  // Pack factory
  createTestPack,
  type CreateTestPackOptions,
  // Metric sets
  CORE_METRICS,
  FEE_METRICS,
  GOVERNANCE_METRICS,
  ECONOMIC_METRICS,
  ALL_METRICS,
  // Assertion builders
  basicStabilityAssertions,
  feeAssertions,
  veEltaAssertions,
  economicAssertions,
  graduationAssertions,
  // Agent stats
  groupAgentStatsByType,
  calculateOverallSuccessRate,
  type AggregatedAgentStats,
  type AgentStats,
  // Formatting
  formatElta,
  formatGas,
  formatDuration,
  printScenarioResults,
  type PrintOptions,
  // Economic calculations
  calculateRevenuePerUser,
  calculateRevenuePerTransaction,
  projectAnnualRevenue,
  calculateCapitalUtilization,
  // Statistics
  calculateStatistics,
  type Statistics,
  // Configuration helpers
  FUNDING_LEVELS,
  TICK_DURATIONS,
  SCENARIO_DURATIONS,
  // Main function helper
  runScenario,
} from './scenario-helpers.js';
