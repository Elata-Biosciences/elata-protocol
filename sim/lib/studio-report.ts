type NotebookReportOptions = {
  title: string;
  experimentNotes: string;
  hypotheses: string[];
  successCriteria: string[];
  resultsCommentary?: string;
  howToRead?: string;
  metricFields: string[];
  primaryMetric: string;
  mlFeatures?: string[];
  includePersonaQuality?: boolean;
};

function markdownList(items: string[]): string {
  if (items.length === 0) return '- None provided';
  return items.map((item) => `- ${item}`).join('\n');
}

export function createNotebookReport(options: NotebookReportOptions): {
  v: 'v1';
  blocks: Array<Record<string, unknown>>;
} {
  const {
    title,
    experimentNotes,
    hypotheses,
    successCriteria,
    resultsCommentary = 'Fill in after reviewing this run in Studio.',
    howToRead = 'Use the charts for trends, then validate with tables and ML diagnostics.',
    metricFields,
    primaryMetric,
    mlFeatures = ['tick'],
    includePersonaQuality = true,
  } = options;

  const selectFields = Array.from(new Set(['tick', 'timestamp', ...metricFields]));

  return {
    v: 'v1',
    blocks: [
      {
        kind: 'markdown',
        title: 'Experiment Notes',
        markdown: `# ${title}

## Experiment Notes
${experimentNotes}

## Hypotheses
${markdownList(hypotheses)}

## Success Criteria
${markdownList(successCriteria)}
`,
      },
      {
        kind: 'dataset',
        as: 'metrics_core',
        title: 'Core Metrics',
        table: 'metrics',
        spec: {
          v: 'v1',
          select: selectFields,
          sort: { field: 'tick', dir: 'asc' },
          limit: 5000,
        },
      },
      {
        kind: 'transform',
        as: 'metrics_primary_roll',
        title: `Rolling mean: ${primaryMetric}`,
        from: 'metrics_core',
        steps: [
          { kind: 'select', fields: ['tick', primaryMetric] },
          {
            kind: 'rolling',
            as: `${primaryMetric}_roll_mean_10`,
            field: primaryMetric,
            op: 'mean',
            window: 10,
          },
        ],
      },
      {
        kind: 'transform',
        as: 'metrics_primary_cum',
        title: `Cumulative: ${primaryMetric}`,
        from: 'metrics_core',
        steps: [
          { kind: 'select', fields: ['tick', primaryMetric] },
          {
            kind: 'cumulative',
            as: `${primaryMetric}_cum_sum`,
            field: primaryMetric,
            op: 'sum',
          },
        ],
      },
      {
        kind: 'chart',
        title: `${primaryMetric} (raw)`,
        chartType: 'line',
        dataset: 'metrics_core',
        xField: 'tick',
        yField: primaryMetric,
      },
      {
        kind: 'chart',
        title: `${primaryMetric} (rolling mean)`,
        chartType: 'line',
        dataset: 'metrics_primary_roll',
        xField: 'tick',
        yField: `${primaryMetric}_roll_mean_10`,
      },
      {
        kind: 'ml',
        as: 'ml_linear_primary',
        title: `Linear regression: ${primaryMetric} ~ ${mlFeatures.join(' + ')}`,
        request: {
          kind: 'linear_regression',
          runId: 'RUN_ID',
          table: 'metrics',
          x: mlFeatures,
          y: primaryMetric,
          limit: 5000,
        },
      },
      {
        kind: 'chart',
        title: 'Linear fit vs actual',
        chartType: 'line',
        dataset: 'ml_linear_primary.predictions_long',
        xField: 'index',
        yField: 'value',
        seriesField: 'series',
      },
      {
        kind: 'ml',
        as: 'ml_anomaly_primary',
        title: `Anomaly detection (z-score): ${primaryMetric}`,
        request: {
          kind: 'anomaly_zscore',
          runId: 'RUN_ID',
          table: 'metrics',
          field: primaryMetric,
          threshold: 3.0,
          limit: 5000,
        },
      },
      {
        kind: 'chart',
        title: `Anomalies: ${primaryMetric}`,
        chartType: 'scatter',
        dataset: 'ml_anomaly_primary.anomalies',
        xField: 'index',
        yField: 'value',
      },
      {
        kind: 'table',
        title: 'Metrics Table',
        dataset: 'metrics_core',
        limit: 5000,
      },
      {
        kind: 'dataset',
        as: 'action_mix',
        title: 'Action Mix',
        table: 'actions',
        spec: {
          v: 'v1',
          groupBy: ['action.name'],
          aggregates: [{ as: 'action_count', op: 'count' }],
          sort: { field: 'action_count', dir: 'desc' },
          limit: 500,
        },
      },
      {
        kind: 'chart',
        title: 'Action Mix (Donut)',
        chartType: 'donut',
        dataset: 'action_mix',
        xField: 'action.name',
        yField: 'action_count',
      },
      {
        kind: 'dataset',
        as: 'gossip_intents',
        title: 'Gossip Intent Mix',
        table: 'actions',
        spec: {
          v: 'v1',
          filters: [{ field: 'action.name', op: 'eq', value: 'PostMessage' }],
          groupBy: ['action.params.intentTag'],
          aggregates: [{ as: 'post_count', op: 'count' }],
          sort: { field: 'post_count', dir: 'desc' },
          limit: 100,
        },
      },
      {
        kind: 'chart',
        title: 'Gossip Intent Mix (Bar)',
        chartType: 'bar',
        dataset: 'gossip_intents',
        xField: 'action.params.intentTag',
        yField: 'post_count',
      },
      ...(includePersonaQuality
        ? [
            {
              kind: 'dataset',
              as: 'persona_actions',
              title: 'Persona Action Trace',
              table: 'actions',
              spec: {
                v: 'v1',
                select: [
                  'tick',
                  'agentId',
                  'action.name',
                  'action.metadata.personaId',
                  'action.metadata.intentTag',
                  'action.metadata.rationale',
                  'result.ok',
                  'result.error',
                ],
                sort: { field: 'tick', dir: 'asc' },
                limit: 2000,
              },
            },
            {
              kind: 'table',
              title: 'Persona Trace Table',
              dataset: 'persona_actions',
              limit: 2000,
            },
            {
              kind: 'markdown',
              title: 'Persona Quality Artifact',
              markdown:
                'Persona usefulness scores are generated post-run into `persona_quality.json` (see run artifacts). Use this together with Persona Trace Table for auditability.',
            },
          ]
        : []),
      {
        kind: 'markdown',
        title: 'Results Commentary',
        markdown: `## Results Commentary
${resultsCommentary}

## How to Read This
${howToRead}
`,
      },
    ],
  };
}
