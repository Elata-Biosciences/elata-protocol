import type { ActionResult, TickContext } from '@elata-biosciences/agentforge';
import type { AppState } from '../../packs/EltaPack.js';

type RngSequence = {
  chance?: boolean;
  nextFloat?: number;
  pickOne?: <T>(items: T[]) => T;
};

export function createTestContext(args?: {
  tick?: number;
  lastResult?: ActionResult | null;
  rng?: RngSequence;
  gossip?: TickContext['gossip'];
  mode?: TickContext['mode'];
}): TickContext {
  const rngConfig = args?.rng ?? {};
  const rng = {
    chance: (_p: number) => rngConfig.chance ?? false,
    nextFloat: () => rngConfig.nextFloat ?? 0.5,
    pickOne: <T>(items: T[]) => {
      if (rngConfig.pickOne) return rngConfig.pickOne(items);
      return items[0]!;
    },
  };

  const logger = {
    trace: () => {},
    debug: () => {},
    info: () => {},
    warn: () => {},
    error: () => {},
    fatal: () => {},
    child: () => logger,
  };

  return {
    tick: args?.tick ?? 0,
    timestamp: 0,
    rng: rng as TickContext['rng'],
    logger: logger as unknown as TickContext['logger'],
    pack: {} as TickContext['pack'],
    world: {} as TickContext['world'],
    mode: args?.mode ?? 'deterministic',
    lastResult: args?.lastResult ?? null,
    ...(args?.gossip ? { gossip: args.gossip } : {}),
  };
}

export function setAgentBalance(agent: object, balances: { elta?: bigint; veElta?: bigint }): void {
  if (balances.elta !== undefined) {
    (agent as { eltaBalance: bigint }).eltaBalance = balances.elta;
  }
  if (balances.veElta !== undefined) {
    (agent as { veEltaBalance: bigint }).veEltaBalance = balances.veElta;
  }
}

export function createTestApp(appId = 1): AppState {
  return {
    id: appId,
    name: `App ${appId}`,
    symbol: `APP${appId}`,
    creator: '0x0000000000000000000000000000000000000001',
    tokenAddress: '0x0000000000000000000000000000000000000002',
    curveAddress: '0x0000000000000000000000000000000000000003',
    graduated: false,
    totalRaised: 0n,
    tokenPrice: 1n,
    tokenSupply: 0n,
  };
}
