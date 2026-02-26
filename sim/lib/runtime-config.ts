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
