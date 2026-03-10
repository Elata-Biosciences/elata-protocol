export function scenarioSeed(defaultSeed: number): number {
  const fromEnv = process.env.SIMULATION_SEED;
  if (!fromEnv) return defaultSeed;
  const parsed = Number.parseInt(fromEnv, 10);
  return Number.isFinite(parsed) ? parsed : defaultSeed;
}

export function anvilPort(defaultPort: number): number {
  const fromEnv = process.env.ANVIL_PORT;
  if (!fromEnv) return defaultPort;
  const parsed = Number.parseInt(fromEnv, 10);
  return Number.isFinite(parsed) ? parsed : defaultPort;
}

export function anvilTimestamp(defaultTimestamp: number): number {
  const fromEnv = process.env.ANVIL_TIMESTAMP;
  if (!fromEnv) return defaultTimestamp;
  const parsed = Number.parseInt(fromEnv, 10);
  return Number.isFinite(parsed) ? parsed : defaultTimestamp;
}

export function scenarioCiMode(defaultCi = true): boolean {
  const fromEnv = process.env.SIMULATION_CI;
  if (!fromEnv) return defaultCi;
  const normalized = fromEnv.trim().toLowerCase();
  if (normalized === '0' || normalized === 'false' || normalized === 'no') return false;
  if (normalized === '1' || normalized === 'true' || normalized === 'yes') return true;
  return defaultCi;
}

export function scenarioOutDir(baseDir: string): string {
  const runTag = process.env.SIM_RUN_TAG?.trim();
  if (!runTag) return baseDir;
  return `${baseDir}-${runTag.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
}
