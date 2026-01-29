/**
 * Structured Error Types for Simulation
 *
 * Provides categorized error handling for agent actions
 * with rich context for debugging and analysis.
 */

// ============================================
// Error Categories
// ============================================

export type ErrorCategory =
  | 'insufficient_balance'
  | 'invalid_state'
  | 'contract_revert'
  | 'timeout'
  | 'network'
  | 'validation'
  | 'precondition'
  | 'configuration'
  | 'unknown';

export type ErrorSeverity = 'fatal' | 'error' | 'warning' | 'info';

// ============================================
// Error Classes
// ============================================

export class SimulationError extends Error {
  readonly category: ErrorCategory;
  readonly severity: ErrorSeverity;
  readonly context: Record<string, unknown>;
  readonly timestamp: Date;

  constructor(
    message: string,
    category: ErrorCategory,
    severity: ErrorSeverity = 'error',
    context: Record<string, unknown> = {}
  ) {
    super(message);
    this.name = 'SimulationError';
    this.category = category;
    this.severity = severity;
    this.context = context;
    this.timestamp = new Date();
  }

  toJSON(): Record<string, unknown> {
    return {
      name: this.name,
      message: this.message,
      category: this.category,
      severity: this.severity,
      context: this.context,
      timestamp: this.timestamp.toISOString(),
    };
  }
}

export class AgentActionError extends SimulationError {
  readonly agentId: string;
  readonly actionType: string;

  constructor(
    agentId: string,
    actionType: string,
    message: string,
    category: ErrorCategory,
    context: Record<string, unknown> = {}
  ) {
    super(message, category, 'error', {
      agentId,
      actionType,
      ...context,
    });
    this.name = 'AgentActionError';
    this.agentId = agentId;
    this.actionType = actionType;
  }
}

export class ContractError extends SimulationError {
  readonly contractAddress: string | undefined;
  readonly functionName: string | undefined;
  readonly revertData: string | undefined;

  constructor(
    message: string,
    options: {
      contractAddress?: string;
      functionName?: string;
      revertData?: string;
      context?: Record<string, unknown>;
    } = {}
  ) {
    super(message, 'contract_revert', 'error', {
      contractAddress: options.contractAddress,
      functionName: options.functionName,
      revertData: options.revertData,
      ...options.context,
    });
    this.name = 'ContractError';
    this.contractAddress = options.contractAddress;
    this.functionName = options.functionName;
    this.revertData = options.revertData;
  }
}

export class NetworkError extends SimulationError {
  readonly url: string | undefined;
  readonly statusCode: number | undefined;

  constructor(
    message: string,
    options: {
      url?: string;
      statusCode?: number;
      context?: Record<string, unknown>;
    } = {}
  ) {
    super(message, 'network', 'error', {
      url: options.url,
      statusCode: options.statusCode,
      ...options.context,
    });
    this.name = 'NetworkError';
    this.url = options.url;
    this.statusCode = options.statusCode;
  }
}

export class TimeoutError extends SimulationError {
  readonly timeoutMs: number;
  readonly operation: string;

  constructor(operation: string, timeoutMs: number, context: Record<string, unknown> = {}) {
    super('Operation timed out after ' + timeoutMs + 'ms', 'timeout', 'error', {
      operation,
      timeoutMs,
      ...context,
    });
    this.name = 'TimeoutError';
    this.operation = operation;
    this.timeoutMs = timeoutMs;
  }
}

// ============================================
// Error Categorization
// ============================================

const KNOWN_ERROR_SIGNATURES: Record<string, { category: ErrorCategory; message: string }> = {
  '0xe450d38c': { category: 'insufficient_balance', message: 'ERC20InsufficientBalance' },
  '0xfb8f41b2': { category: 'insufficient_balance', message: 'ERC20InsufficientAllowance' },
  '0x8c10e357': { category: 'invalid_state', message: 'NotActive' },
  '0x82b42900': { category: 'invalid_state', message: 'Locked' },
  '0x3d693ada': { category: 'invalid_state', message: 'AlreadyExists' },
  '0x2e07630c': { category: 'invalid_state', message: 'InvalidState' },
  '0x80af9525': { category: 'precondition', message: 'InsufficientXP' },
};

export function categorizeError(error: unknown): {
  category: ErrorCategory;
  message: string;
  originalError: unknown;
} {
  const originalError = error;

  if (error instanceof SimulationError) {
    return {
      category: error.category,
      message: error.message,
      originalError,
    };
  }

  const message = error instanceof Error ? error.message : String(error);

  for (const [signature, info] of Object.entries(KNOWN_ERROR_SIGNATURES)) {
    if (message.includes(signature)) {
      return {
        category: info.category,
        message: info.message,
        originalError,
      };
    }
  }

  if (
    message.includes('InsufficientBalance') ||
    message.includes('insufficient funds') ||
    message.includes('exceeds balance')
  ) {
    return { category: 'insufficient_balance', message, originalError };
  }

  if (
    message.includes('NotActive') ||
    message.includes('InvalidState') ||
    message.includes('NotReady') ||
    message.includes('AlreadyExists') ||
    message.includes('Locked') ||
    message.includes('Expired')
  ) {
    return { category: 'invalid_state', message, originalError };
  }

  if (message.includes('revert') || message.includes('execution reverted')) {
    return { category: 'contract_revert', message, originalError };
  }

  if (message.includes('timeout') || message.includes('ETIMEDOUT')) {
    return { category: 'timeout', message, originalError };
  }

  if (
    message.includes('fetch failed') ||
    message.includes('ECONNREFUSED') ||
    message.includes('network') ||
    message.includes('HTTP request failed')
  ) {
    return { category: 'network', message, originalError };
  }

  if (
    message.includes('invalid') ||
    message.includes('Invalid') ||
    message.includes('validation')
  ) {
    return { category: 'validation', message, originalError };
  }

  return { category: 'unknown', message, originalError };
}

// ============================================
// Error Aggregation
// ============================================

export interface ErrorSample {
  category: ErrorCategory;
  message: string;
  agentId?: string;
  actionType?: string;
  timestamp: Date;
  context?: Record<string, unknown>;
}

export interface ErrorSummary {
  totalErrors: number;
  byCategory: Record<ErrorCategory, number>;
  byAgent: Record<string, number>;
  byAction: Record<string, number>;
  samples: ErrorSample[];
  firstError?: ErrorSample;
  lastError?: ErrorSample;
}

export class ErrorAggregator {
  private errors: ErrorSample[] = [];
  private byCategory: Record<ErrorCategory, number> = {
    insufficient_balance: 0,
    invalid_state: 0,
    contract_revert: 0,
    timeout: 0,
    network: 0,
    validation: 0,
    precondition: 0,
    configuration: 0,
    unknown: 0,
  };
  private byAgent: Map<string, number> = new Map();
  private byAction: Map<string, number> = new Map();
  private maxSamples: number;

  constructor(maxSamples = 100) {
    this.maxSamples = maxSamples;
  }

  record(
    error: unknown,
    options: {
      agentId?: string;
      actionType?: string;
      context?: Record<string, unknown>;
    } = {}
  ): void {
    const categorized = categorizeError(error);

    const sample: ErrorSample = {
      category: categorized.category,
      message: categorized.message,
      timestamp: new Date(),
    };

    if (options.agentId) {
      sample.agentId = options.agentId;
      const current = this.byAgent.get(options.agentId) ?? 0;
      this.byAgent.set(options.agentId, current + 1);
    }

    if (options.actionType) {
      sample.actionType = options.actionType;
      const current = this.byAction.get(options.actionType) ?? 0;
      this.byAction.set(options.actionType, current + 1);
    }

    if (options.context) {
      sample.context = options.context;
    }

    this.byCategory[categorized.category]++;

    if (this.errors.length < this.maxSamples) {
      this.errors.push(sample);
    }
  }

  getSummary(): ErrorSummary {
    const totalErrors = Object.values(this.byCategory).reduce((a, b) => a + b, 0);

    const summary: ErrorSummary = {
      totalErrors,
      byCategory: { ...this.byCategory },
      byAgent: Object.fromEntries(this.byAgent),
      byAction: Object.fromEntries(this.byAction),
      samples: [...this.errors],
    };

    const first = this.errors[0];
    const last = this.errors[this.errors.length - 1];
    if (first) {
      summary.firstError = first;
    }
    if (last) {
      summary.lastError = last;
    }

    return summary;
  }

  clear(): void {
    this.errors = [];
    for (const key of Object.keys(this.byCategory)) {
      this.byCategory[key as ErrorCategory] = 0;
    }
    this.byAgent.clear();
    this.byAction.clear();
  }
}

// ============================================
// Error Formatting
// ============================================

export function formatError(error: unknown): string {
  if (error instanceof SimulationError) {
    return '[' + error.category + '] ' + error.message;
  }

  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
}

export function formatErrorSummary(summary: ErrorSummary): string {
  const lines: string[] = [];

  lines.push('Total errors: ' + summary.totalErrors);
  lines.push('');
  lines.push('By category:');
  for (const [category, count] of Object.entries(summary.byCategory)) {
    if (count > 0) {
      lines.push('  ' + category + ': ' + count);
    }
  }

  if (Object.keys(summary.byAgent).length > 0) {
    lines.push('');
    lines.push('Top agents with errors:');
    const sorted = Object.entries(summary.byAgent)
      .sort(([, a], [, b]) => b - a)
      .slice(0, 5);
    for (const [agent, count] of sorted) {
      lines.push('  ' + agent + ': ' + count);
    }
  }

  if (Object.keys(summary.byAction).length > 0) {
    lines.push('');
    lines.push('Top actions with errors:');
    const sorted = Object.entries(summary.byAction)
      .sort(([, a], [, b]) => b - a)
      .slice(0, 5);
    for (const [action, count] of sorted) {
      lines.push('  ' + action + ': ' + count);
    }
  }

  return lines.join('\n');
}
