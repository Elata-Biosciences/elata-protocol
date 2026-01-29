/**
 * Enhanced Logging System for Simulation
 *
 * Provides structured logging with event types, export capabilities,
 * and integration with the error handling system.
 */

import { writeFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { Action } from '@elata-biosciences/agentforge';
import {
  type ErrorCategory,
  type ErrorSummary,
  ErrorAggregator,
  formatError,
} from './errors.js';

// ============================================
// Event Types
// ============================================

/**
 * Types of events that can be logged
 */
export type LogEventType =
  | 'simulation_start'
  | 'simulation_end'
  | 'tick_start'
  | 'tick_end'
  | 'agent_action'
  | 'agent_error'
  | 'metric_snapshot'
  | 'economic_event'
  | 'state_change'
  | 'warning'
  | 'info';

/**
 * Base log entry structure
 */
export interface LogEntry {
  timestamp: string;
  type: LogEventType;
  tick?: number;
  data: Record<string, unknown>;
}

/**
 * Action log entry
 */
export interface ActionLogEntry extends LogEntry {
  type: 'agent_action';
  data: {
    agentId: string;
    actionName: string;
    success: boolean;
    durationMs?: number;
    gasUsed?: string;
    error?: string;
    params?: Record<string, unknown>;
  };
}

/**
 * Error log entry
 */
export interface ErrorLogEntry extends LogEntry {
  type: 'agent_error';
  data: {
    agentId: string;
    actionType?: string;
    category: ErrorCategory;
    message: string;
    context?: Record<string, unknown>;
  };
}

/**
 * Metric snapshot entry
 */
export interface MetricLogEntry extends LogEntry {
  type: 'metric_snapshot';
  data: {
    tick: number;
    metrics: Record<string, unknown>;
  };
}

/**
 * Economic event entry
 */
export interface EconomicLogEntry extends LogEntry {
  type: 'economic_event';
  data: {
    eventType: string;
    amount?: string;
    from?: string;
    to?: string;
    details?: Record<string, unknown>;
  };
}

// ============================================
// Simulation Logger
// ============================================

/**
 * Configuration for the simulation logger
 */
export interface SimulationLoggerConfig {
  /** Maximum entries to keep in memory */
  maxEntries?: number;
  /** Log levels to capture */
  levels?: LogEventType[];
  /** Include action params in logs */
  includeParams?: boolean;
  /** Pretty print JSON output */
  prettyPrint?: boolean;
}

/**
 * Result interface for action logging
 */
export interface ActionResult {
  ok: boolean;
  error?: string;
  gasUsed?: bigint;
}

/**
 * Enhanced simulation logger
 */
export class SimulationLogger {
  private entries: LogEntry[] = [];
  private errorAggregator: ErrorAggregator;
  private config: Required<SimulationLoggerConfig>;
  private startTime: number = Date.now();

  constructor(config: SimulationLoggerConfig = {}) {
    this.config = {
      maxEntries: config.maxEntries ?? 10000,
      levels: config.levels ?? [
        'simulation_start',
        'simulation_end',
        'agent_action',
        'agent_error',
        'metric_snapshot',
        'economic_event',
      ],
      includeParams: config.includeParams ?? false,
      prettyPrint: config.prettyPrint ?? false,
    };
    this.errorAggregator = new ErrorAggregator();
  }

  /**
   * Log simulation start
   */
  logSimulationStart(scenarioName: string, config: Record<string, unknown>): void {
    this.startTime = Date.now();
    this.addEntry({
      timestamp: new Date().toISOString(),
      type: 'simulation_start',
      data: {
        scenario: scenarioName,
        config,
      },
    });
  }

  /**
   * Log simulation end
   */
  logSimulationEnd(success: boolean, finalMetrics: Record<string, unknown>): void {
    const duration = Date.now() - this.startTime;
    this.addEntry({
      timestamp: new Date().toISOString(),
      type: 'simulation_end',
      data: {
        success,
        durationMs: duration,
        finalMetrics,
        errorSummary: this.errorAggregator.getSummary(),
      },
    });
  }

  /**
   * Log tick start
   */
  logTickStart(tick: number): void {
    this.addEntry({
      timestamp: new Date().toISOString(),
      type: 'tick_start',
      tick,
      data: { tick },
    });
  }

  /**
   * Log tick end
   */
  logTickEnd(tick: number, agentCount: number, actionsExecuted: number): void {
    this.addEntry({
      timestamp: new Date().toISOString(),
      type: 'tick_end',
      tick,
      data: {
        tick,
        agentCount,
        actionsExecuted,
      },
    });
  }

  /**
   * Log an agent action
   */
  logAction(
    agentId: string,
    action: Action,
    result: ActionResult,
    tick?: number,
    durationMs?: number
  ): void {
    const data: ActionLogEntry['data'] = {
      agentId,
      actionName: action.name,
      success: result.ok,
    };

    if (durationMs !== undefined) {
      data.durationMs = durationMs;
    }
    if (result.gasUsed !== undefined) {
      data.gasUsed = result.gasUsed.toString();
    }
    if (result.error !== undefined) {
      data.error = result.error;
    }
    if (this.config.includeParams && action.params) {
      data.params = action.params;
    }

    const entry: ActionLogEntry = {
      timestamp: new Date().toISOString(),
      type: 'agent_action',
      data,
    };

    if (tick !== undefined) {
      entry.tick = tick;
    }

    this.addEntry(entry);
  }

  /**
   * Log an agent error
   */
  logError(
    error: unknown,
    options: {
      agentId?: string;
      actionType?: string;
      tick?: number;
      context?: Record<string, unknown>;
    } = {}
  ): void {
    // Record in aggregator
    const recordOptions: { agentId?: string; actionType?: string; context?: Record<string, unknown> } = {};
    if (options.agentId) recordOptions.agentId = options.agentId;
    if (options.actionType) recordOptions.actionType = options.actionType;
    if (options.context) recordOptions.context = options.context;
    this.errorAggregator.record(error, recordOptions);

    // Add log entry
    const data: ErrorLogEntry['data'] = {
      agentId: options.agentId ?? 'unknown',
      category: 'unknown',
      message: formatError(error),
    };

    if (options.actionType) {
      data.actionType = options.actionType;
    }
    if (options.context) {
      data.context = options.context;
    }

    const entry: ErrorLogEntry = {
      timestamp: new Date().toISOString(),
      type: 'agent_error',
      data,
    };

    if (options.tick !== undefined) {
      entry.tick = options.tick;
    }

    this.addEntry(entry);
  }

  /**
   * Log a metric snapshot
   */
  logMetrics(tick: number, metrics: Record<string, unknown>): void {
    const entry: MetricLogEntry = {
      timestamp: new Date().toISOString(),
      type: 'metric_snapshot',
      tick,
      data: {
        tick,
        metrics,
      },
    };

    this.addEntry(entry);
  }

  /**
   * Log an economic event
   */
  logEconomicEvent(
    eventType: string,
    details: {
      amount?: bigint | string;
      from?: string;
      to?: string;
      tick?: number;
      extra?: Record<string, unknown>;
    } = {}
  ): void {
    const data: EconomicLogEntry['data'] = {
      eventType,
    };

    if (details.amount !== undefined) {
      data.amount = details.amount.toString();
    }
    if (details.from !== undefined) {
      data.from = details.from;
    }
    if (details.to !== undefined) {
      data.to = details.to;
    }
    if (details.extra !== undefined) {
      data.details = details.extra;
    }

    const entry: EconomicLogEntry = {
      timestamp: new Date().toISOString(),
      type: 'economic_event',
      data,
    };

    if (details.tick !== undefined) {
      entry.tick = details.tick;
    }

    this.addEntry(entry);
  }

  /**
   * Log a warning
   */
  logWarning(message: string, context?: Record<string, unknown>): void {
    this.addEntry({
      timestamp: new Date().toISOString(),
      type: 'warning',
      data: {
        message,
        context,
      },
    });
  }

  /**
   * Log info
   */
  logInfo(message: string, context?: Record<string, unknown>): void {
    this.addEntry({
      timestamp: new Date().toISOString(),
      type: 'info',
      data: {
        message,
        context,
      },
    });
  }

  /**
   * Get all entries
   */
  getEntries(): LogEntry[] {
    return [...this.entries];
  }

  /**
   * Get entries by type
   */
  getEntriesByType<T extends LogEntry>(type: LogEventType): T[] {
    return this.entries.filter((e) => e.type === type) as T[];
  }

  /**
   * Get error summary
   */
  getErrorSummary(): ErrorSummary {
    return this.errorAggregator.getSummary();
  }

  /**
   * Export to NDJSON format (newline-delimited JSON)
   */
  async exportToNDJSON(path: string): Promise<void> {
    await mkdir(dirname(path), { recursive: true });

    const lines = this.entries.map((entry) =>
      JSON.stringify(entry, (_, v) => (typeof v === 'bigint' ? v.toString() : v))
    );

    await writeFile(path, lines.join('\n'));
  }

  /**
   * Export to CSV format (actions only)
   */
  async exportToCSV(path: string): Promise<void> {
    await mkdir(dirname(path), { recursive: true });

    const actionEntries = this.getEntriesByType<ActionLogEntry>('agent_action');

    const headers = ['timestamp', 'tick', 'agentId', 'actionName', 'success', 'durationMs', 'gasUsed', 'error'];
    const rows = actionEntries.map((e) => [
      e.timestamp,
      e.tick ?? '',
      e.data.agentId,
      e.data.actionName,
      e.data.success,
      e.data.durationMs ?? '',
      e.data.gasUsed ?? '',
      e.data.error ?? '',
    ]);

    const csv = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
    await writeFile(path, csv);
  }

  /**
   * Export to JSON format
   */
  async exportToJSON(path: string): Promise<void> {
    await mkdir(dirname(path), { recursive: true });

    const data = {
      entries: this.entries,
      summary: {
        totalEntries: this.entries.length,
        entryTypes: Object.fromEntries(
          this.config.levels.map((type) => [
            type,
            this.entries.filter((e) => e.type === type).length,
          ])
        ),
        errorSummary: this.getErrorSummary(),
      },
    };

    const json = this.config.prettyPrint
      ? JSON.stringify(data, (_, v) => (typeof v === 'bigint' ? v.toString() : v), 2)
      : JSON.stringify(data, (_, v) => (typeof v === 'bigint' ? v.toString() : v));

    await writeFile(path, json);
  }

  /**
   * Clear all entries
   */
  clear(): void {
    this.entries = [];
    this.errorAggregator.clear();
  }

  /**
   * Add an entry with limit checking
   */
  private addEntry(entry: LogEntry): void {
    if (!this.config.levels.includes(entry.type)) {
      return;
    }

    if (this.entries.length >= this.config.maxEntries) {
      // Remove oldest entries (keep last 80%)
      const keepCount = Math.floor(this.config.maxEntries * 0.8);
      this.entries = this.entries.slice(-keepCount);
    }

    this.entries.push(entry);
  }
}

// ============================================
// Factory Functions
// ============================================

/**
 * Create a simulation logger with default config
 */
export function createSimulationLogger(config?: SimulationLoggerConfig): SimulationLogger {
  return new SimulationLogger(config);
}

/**
 * Create a verbose logger for debugging
 */
export function createVerboseLogger(): SimulationLogger {
  return new SimulationLogger({
    maxEntries: 50000,
    levels: [
      'simulation_start',
      'simulation_end',
      'tick_start',
      'tick_end',
      'agent_action',
      'agent_error',
      'metric_snapshot',
      'economic_event',
      'state_change',
      'warning',
      'info',
    ],
    includeParams: true,
    prettyPrint: true,
  });
}

/**
 * Create a minimal logger for production
 */
export function createMinimalLogger(): SimulationLogger {
  return new SimulationLogger({
    maxEntries: 1000,
    levels: ['simulation_start', 'simulation_end', 'agent_error'],
    includeParams: false,
    prettyPrint: false,
  });
}
