/**
 * EltaPack - Protocol Pack for Elata Protocol simulation
 *
 * Handles:
 * - Contract deployment to Anvil
 * - Action execution against real contracts
 * - World state management
 * - Metrics collection
 */

import type {
  Action,
  ActionResult,
  CapabilityManifest,
  FundingConfig,
  Pack,
  WorldState,
} from '@elata-biosciences/agentforge';
import {
  type AnvilInstance,
  anvilRpc,
  forgeBuild,
  forgeScript,
  getDeployedAddresses,
  loadArtifact,
  spawnAnvil,
  stopAnvil,
} from '@elata-biosciences/agentforge/adapters';
import {
  http,
  type Abi,
  type Address,
  type Log,
  type PublicClient,
  type WalletClient,
  createPublicClient,
  createWalletClient,
  decodeEventLog,
  parseEther,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { foundry } from 'viem/chains';
import type { EltaAction } from '../actions/index.js';

/**
 * Configuration for EltaPack
 */
export interface EltaPackConfig {
  /** Path to elata-protocol Foundry project */
  protocolPath: string;
  /** Port for Anvil (default: 8545) */
  anvilPort?: number;
  /** Initial ELTA supply to mint */
  initialEltaSupply?: bigint;
  /** Initial ETH balance per agent */
  agentEthBalance?: bigint;
  /** Initial ELTA balance per agent */
  agentEltaBalance?: bigint;
  /** Whether to auto-deploy contracts (default: true) */
  autoDeploy?: boolean;
  /** Silent mode for Anvil */
  silent?: boolean;

  /**
   * Path to deployment script (relative to protocolPath)
   * Defaults to 'script/Deploy.sol:Deploy'
   */
  deployScript?: string;

  /**
   * Extra arguments for forge script
   * Defaults to ['--code-size-limit', '50000', '--skip-simulation']
   */
  deployScriptArgs?: string[];

  /**
   * Funding configuration for agents
   * If not provided, defaults to ELTA transfer from deployer
   */
  funding?: FundingConfig;
}

/**
 * State of a single app in the protocol
 */
export interface AppState {
  id: number;
  name: string;
  symbol: string;
  creator: Address;
  tokenAddress: Address;
  curveAddress: Address;
  graduated: boolean;
  totalRaised: bigint;
  tokenPrice: bigint;
  tokenSupply: bigint;
}

/**
 * World state for Elata Protocol
 */
export interface EltaWorldState extends WorldState {
  // Contract addresses
  elta: Address;
  veElta: Address;
  appFactory: Address;
  feeRouter: Address;
  rewardsDistributor: Address;
  elataPoints: Address;

  // Fee pipeline addresses (may be zero if not deployed)
  feeCollector: Address;
  feeManager: Address;
  treasuryVault: Address;
  usdc: Address;
  uniswapRouter: Address;

  // Protocol state
  totalEltaSupply: bigint;
  totalVeEltaLocked: bigint;
  appCount: number;

  // Apps
  apps: Map<string, AppState>;

  // Fee tracking (ELTA)
  feesCollectedTotal: bigint;
  feesDistributed: bigint;

  // Treasury USDC tracking
  treasuryUsdcBalance: bigint;
  treasuryUsdcRevenue: bigint;

  // Current block info
  blockNumber: bigint;
}

/**
 * Agent wallet with address and client
 */
interface AgentWallet {
  address: Address;
  privateKey: `0x${string}`;
  client: WalletClient;
}

/** Zero address constant */
const zeroAddress = '0x0000000000000000000000000000000000000000' as Address;

/**
 * Resolved config type - all required fields are set, but funding remains optional
 */
type ResolvedEltaPackConfig = Required<Omit<EltaPackConfig, 'funding'>> & {
  funding?: FundingConfig;
};

/**
 * EltaPack - Simulation Pack for Elata Protocol
 */
export class EltaPack implements Pack {
  readonly name = 'elata-protocol';

  config: ResolvedEltaPackConfig;
  anvil: AnvilInstance | null = null;
  publicClient: PublicClient | null = null;
  agentWallets: Map<string, AgentWallet> = new Map();
  private state: EltaWorldState | null = null;

  // Contract ABIs (loaded from artifacts)
  private abis: Map<string, Abi> = new Map();

  // Deployed contract addresses (populated during deployment)
  private deployedAddresses: Map<string, Address> = new Map();

  // Deployer wallet for admin operations
  private deployerWallet: WalletClient | null = null;

  // Metrics tracking
  private metrics: Record<string, number | bigint | string> = {};

  // Price history tracking (appId -> tick -> price)
  private priceHistory: Map<string, Map<number, bigint>> = new Map();

  // Agent P&L tracking
  private agentStartingBalances: Map<string, bigint> = new Map();
  private agentRealizedPnL: Map<string, bigint> = new Map();

  // Gas usage aggregation
  private gasUsedByAgent: Map<string, bigint> = new Map();
  private gasUsedByAction: Map<string, bigint> = new Map();
  private totalGasUsed = 0n;

  // Current tick for price history
  private currentTick = 0;

  // Simulated tick duration for time advancement
  private tickSeconds = 60;

  // Track pending async operations for cleanup
  private pendingTimeAdvance: Promise<void> | null = null;

  // Track created apps for world state
  private createdApps: Map<string, AppState> = new Map();
  private appCounter = 0;

  // Track cumulative fees collected across all trades
  private cumulativeFeesCollected = 0n;

  // Cache for veELTA lock state to avoid repeated contract reads
  private lockStateCache: Map<Address, { hasLock: boolean; unlockTime: bigint }> = new Map();

  // ===========================================
  // SIMULATION METRICS TRACKING
  // ===========================================

  /** Total trading volume (sum of all buys + sells in ELTA) */
  private totalTradingVolume = 0n;

  /** Volume by action type */
  private volumeByAction: Map<string, bigint> = new Map();

  /** Unique active users per tick */
  private activeUsersThisTick: Set<string> = new Set();
  
  /** Total unique users ever */
  private totalUniqueUsers: Set<string> = new Set();

  /** Daily Active Users tracking (rolling window) */
  private dauByTick: Map<number, Set<string>> = new Map();

  /** Content purchases count */
  private contentPurchases = 0;

  /** Tournament entries count */
  private tournamentEntries = 0;

  /** Referral registrations count */
  private referralRegistrations = 0;

  /** Governance votes cast */
  private governanceVotes = 0;

  /** Staking events count */
  private stakingEvents = 0;

  /** App token trades count */
  private appTokenTrades = 0;

  /** Revenue earned by category */
  private revenueByCategory: Map<string, bigint> = new Map();

  constructor(config: EltaPackConfig) {
    const baseConfig = {
      protocolPath: config.protocolPath,
      anvilPort: config.anvilPort ?? 8545,
      initialEltaSupply: config.initialEltaSupply ?? parseEther('10000000'),
      agentEthBalance: config.agentEthBalance ?? parseEther('1000'),
      agentEltaBalance: config.agentEltaBalance ?? parseEther('10000'),
      autoDeploy: config.autoDeploy ?? true,
      silent: config.silent ?? false,
      deployScript: config.deployScript ?? 'script/DeployLocal.sol:DeployLocal',
      deployScriptArgs: config.deployScriptArgs ?? [
        '--code-size-limit',
        '50000',
        '--skip-simulation',
      ],
    };

    // Only add funding if provided (respects exactOptionalPropertyTypes)
    this.config = config.funding ? { ...baseConfig, funding: config.funding } : baseConfig;
  }

  /**
   * Set tick duration for time advancement
   */
  setTickSeconds(seconds: number): void {
    this.tickSeconds = seconds;
  }

  /**
   * Initialize the pack - spawn Anvil and deploy contracts
   */
  async initialize(): Promise<void> {
    console.log('Initializing EltaPack...');

    // Check if contracts are already built (skip slow rebuild)
    const artifactPath = `${this.config.protocolPath}/out/AppFactory.sol/AppFactory.json`;
    const fs = await import('node:fs/promises');
    let needsBuild = true;
    try {
      await fs.access(artifactPath);
      console.log('Contracts already built, skipping forge build...');
      needsBuild = false;
    } catch {
      console.log('Building contracts...');
    }

    if (needsBuild) {
      const buildResult = await forgeBuild(this.config.protocolPath);
      if (!buildResult.success) {
        throw new Error(`Forge build failed: ${buildResult.output}`);
      }
    }

    // Load ABIs from artifacts
    await this.loadAbis();

    // Spawn Anvil with higher balance and enough accounts for agents
    // Note: We disable silent mode to allow parsing of account addresses from output
    console.log(`Spawning Anvil on port ${this.config.anvilPort}...`);
    this.anvil = await spawnAnvil({
      port: this.config.anvilPort,
      chainId: 31337,
      accounts: 100, // Enough accounts for deployer + many agents
      balance: parseEther('100000'), // 100k ETH per account for deployment
      silent: false, // Need to parse accounts from output
      codeSizeLimit: 50000, // Allow larger contracts (some protocol contracts exceed EIP-170 limit)
    });

    // Create public client
    this.publicClient = createPublicClient({
      chain: foundry,
      transport: http(this.anvil.url),
    });

    // Create deployer wallet
    const deployerKey = this.anvil.privateKeys[0];
    if (deployerKey) {
      const account = privateKeyToAccount(deployerKey as `0x${string}`);
      this.deployerWallet = createWalletClient({
        account,
        chain: foundry,
        transport: http(this.anvil.url),
      });
    }

    // Deploy contracts if auto-deploy is enabled
    if (this.config.autoDeploy) {
      await this.deployContracts();

      // Advance time past the default activation delay (1 hour)
      // so bonding curves can be immediately activated
      if (this.anvil) {
        console.log('Advancing time past activation delay...');
        await anvilRpc.increaseTime(this.anvil.url, 3600 + 60); // 1 hour + 1 minute
        await anvilRpc.mine(this.anvil.url);
      }
    }

    // Initialize state
    this.state = await this.fetchWorldState();

    // Update metrics immediately so first tick has data
    this.updateMetricsSync();

    // Create bootstrap apps for user agents to trade
    if (this.config.autoDeploy) {
      await this.createBootstrapApps();
    }

    console.log('EltaPack initialized', this.getContractAddresses());
  }

  /**
   * Load contract ABIs from Foundry artifacts
   */
  private async loadAbis(): Promise<void> {
    const contractNames = [
      // Core contracts
      'ELTA',
      'AppFactory',
      'AppBondingCurve',
      'AppToken',
      'VeELTA',
      // Fee infrastructure
      'AppRewardsDistributor',
      'RewardsDistributor',
      'AppFeeRouter',
      'FeeCollector',
      // Other
      'ElataPoints',
    ];

    for (const name of contractNames) {
      try {
        const artifact = await loadArtifact(this.config.protocolPath, name);
        this.abis.set(name, artifact.abi as Abi);
        console.log(`Loaded ABI for ${name}`);
      } catch {
        // Some contracts may not exist, that's okay
        console.warn(`Could not load ABI for ${name}`);
      }
    }
  }

  /**
   * Deploy protocol contracts using Forge script
   * Uses the configurable deployScript path (defaults to Deploy.sol)
   */
  private async deployContracts(): Promise<void> {
    console.log('Deploying contracts...');

    if (!this.anvil) {
      throw new Error('Anvil not initialized');
    }

    // Use the first Anvil account as deployer
    const deployerKey = this.anvil.privateKeys[0];
    if (!deployerKey) {
      throw new Error('No deployer key available');
    }

    const rpcUrl = this.anvil.url;
    const scriptPath = this.config.deployScript;
    const extraArgs = this.config.deployScriptArgs;

    // Extract script name for broadcast parsing
    // e.g., 'script/Deploy.sol:Deploy' -> 'Deploy'
    const scriptName = scriptPath.split(':').pop() ?? 'Deploy';

    console.log(`Running deployment script: ${scriptPath}`);

    // Run deployment script with configurable args
    const scriptResult = await forgeScript(this.config.protocolPath, scriptPath, {
      rpcUrl,
      broadcast: true,
      privateKey: deployerKey,
      extraArgs,
    });

    // Check if deployment actually succeeded by looking for key contracts in output
    // The script may return non-zero exit due to size warnings but still deploy
    const deploymentSucceeded =
      scriptResult.success ||
      scriptResult.output.includes('AppFactory deployed at') ||
        scriptResult.output.includes('DEPLOYMENT COMPLETE') ||
      scriptResult.output.includes('ELATA PROTOCOL DEPLOYMENT');

    if (!deploymentSucceeded) {
      console.error('Deployment failed. Output:', scriptResult.output.slice(-1000));
      throw new Error(`Contract deployment failed: ${scriptResult.output.slice(-500)}`);
    }

    // Try to load addresses from deployments/local.json first (Deploy.sol writes here)
    const addresses = await this.loadAddressesFromDeploymentsJson();

    // Fall back to parsing broadcast if deployments file not found
    if (addresses.size === 0) {
      const broadcastAddresses = await getDeployedAddresses(
        this.config.protocolPath,
        31337,
        scriptName
      );
      // Convert string addresses to Address type
      for (const [name, addr] of broadcastAddresses) {
        addresses.set(name, addr as Address);
      }
    }

    if (addresses.size === 0) {
      throw new Error('No contract addresses found in deployment output');
    }

    this.setupContracts(addresses);
  }

  /**
   * Load deployed addresses from deployments/local.json
   * This is the preferred method as Deploy.sol writes a structured JSON file
   */
  private async loadAddressesFromDeploymentsJson(): Promise<Map<string, Address>> {
    const addresses = new Map<string, Address>();

    try {
      const fs = await import('node:fs/promises');
      const { join } = await import('node:path');
      const deploymentsPath = join(this.config.protocolPath, 'deployments', 'local.json');
      const content = await fs.readFile(deploymentsPath, 'utf-8');
      const deployments = JSON.parse(content) as {
        contracts?: Record<string, string>;
      };

      if (deployments.contracts) {
        for (const [name, address] of Object.entries(deployments.contracts)) {
          addresses.set(name, address as Address);
        }
        console.log(`Loaded ${addresses.size} addresses from deployments/local.json`);
      }
    } catch {
      // File doesn't exist or parse error - fall back to broadcast parsing
      console.log('deployments/local.json not found, will parse broadcast');
    }

    return addresses;
  }

  /**
   * Setup contract instances from deployed addresses
   */
  private setupContracts(addresses: Map<string, Address>): void {
    console.log('Deployed contracts:', Object.fromEntries(addresses));

    // Store addresses for state initialization
    for (const [name, addr] of addresses) {
      this.deployedAddresses.set(name, addr);
    }
  }

  /**
   * Get total supply of ELTA token from contract
   */
  private async getEltaTotalSupply(): Promise<bigint> {
    const eltaAddr = this.deployedAddresses.get('ELTA') ?? this.deployedAddresses.get('MockELTA');
    if (!eltaAddr || eltaAddr === zeroAddress || !this.publicClient) {
      return this.config.initialEltaSupply;
    }

    try {
      const totalSupplyAbi = [
        {
          name: 'totalSupply',
          type: 'function',
          stateMutability: 'view',
          inputs: [],
          outputs: [{ name: '', type: 'uint256' }],
        },
      ] as const;

      const supply = await this.publicClient.readContract({
        address: eltaAddr,
        abi: totalSupplyAbi,
        functionName: 'totalSupply',
      });
      return supply as bigint;
    } catch {
      return this.config.initialEltaSupply;
    }
  }

  /**
   * Get total supply of veELTA token (represents total locked voting power)
   */
  private async getVeEltaTotalSupply(): Promise<bigint> {
    const veEltaAddr = this.deployedAddresses.get('VeELTA');
    if (!veEltaAddr || veEltaAddr === zeroAddress || !this.publicClient) {
      return 0n;
    }

    try {
      const totalSupplyAbi = [
        {
          name: 'totalSupply',
          type: 'function',
          stateMutability: 'view',
          inputs: [],
          outputs: [{ name: '', type: 'uint256' }],
        },
      ] as const;

      const supply = await this.publicClient.readContract({
        address: veEltaAddr,
        abi: totalSupplyAbi,
        functionName: 'totalSupply',
      });
      return supply as bigint;
    } catch {
      return 0n;
    }
  }

  /**
   * Fetch current world state from contracts
   */
  private async fetchWorldState(): Promise<EltaWorldState> {
    if (!this.publicClient) {
      throw new Error('Public client not initialized');
    }

    const blockNumber = await this.publicClient.getBlockNumber();
    const block = await this.publicClient.getBlock({ blockNumber });

    // Get addresses from deployment, with fallbacks for different naming conventions
    const eltaAddr =
      this.deployedAddresses.get('ELTA') ?? this.deployedAddresses.get('MockELTA') ?? zeroAddress;
    const veEltaAddr = this.deployedAddresses.get('VeELTA') ?? zeroAddress;
    // Note: AppFactory creates apps via bonding curve, separate factories for content modules
    // We prioritize AppFactory for app creation
    const appFactoryAddr = this.deployedAddresses.get('AppFactory') ?? zeroAddress;
    const feeRouterAddr =
      this.deployedAddresses.get('AppFeeRouter') ??
      this.deployedAddresses.get('FeeRouter') ??
      zeroAddress;
    const rewardsDistributorAddr = this.deployedAddresses.get('RewardsDistributor') ?? zeroAddress;
    const elataPointsAddr =
      this.deployedAddresses.get('ElataXP') ??
      this.deployedAddresses.get('ElataPoints') ??
      zeroAddress;

    // Fee pipeline addresses (may be zero if not deployed)
    const feeCollectorAddr = this.deployedAddresses.get('FeeCollector') ?? zeroAddress;
    const feeManagerAddr = this.deployedAddresses.get('FeeManager') ?? zeroAddress;
    const treasuryVaultAddr = this.deployedAddresses.get('TreasuryUSDCVault') ?? zeroAddress;
    const usdcAddr = this.deployedAddresses.get('MockUSDC') ?? this.deployedAddresses.get('USDC') ?? zeroAddress;
    const uniswapRouterAddr = this.deployedAddresses.get('UniswapV2Router') ?? zeroAddress;

    // Read actual values from contracts
    const totalEltaSupply = await this.getEltaTotalSupply();
    const totalVeEltaLocked = await this.getVeEltaTotalSupply();

    // Read USDC metrics from treasury vault if available
    let treasuryUsdcBalance = 0n;
    let treasuryUsdcRevenue = 0n;
    if (treasuryVaultAddr !== zeroAddress && this.publicClient) {
      try {
        treasuryUsdcBalance = await this.publicClient.readContract({
          address: treasuryVaultAddr,
          abi: [{ name: 'balance', type: 'function', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' }],
          functionName: 'balance',
        }) as bigint;
        treasuryUsdcRevenue = await this.publicClient.readContract({
          address: treasuryVaultAddr,
          abi: [{ name: 'totalRevenue', type: 'function', inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view' }],
          functionName: 'totalRevenue',
        }) as bigint;
      } catch {
        // Treasury vault may not have these functions or not be deployed
      }
    }

    return {
      elta: eltaAddr,
      veElta: veEltaAddr,
      appFactory: appFactoryAddr,
      feeRouter: feeRouterAddr,
      rewardsDistributor: rewardsDistributorAddr,
      elataPoints: elataPointsAddr,
      feeCollector: feeCollectorAddr,
      feeManager: feeManagerAddr,
      treasuryVault: treasuryVaultAddr,
      usdc: usdcAddr,
      uniswapRouter: uniswapRouterAddr,
      totalEltaSupply,
      totalVeEltaLocked,
      appCount: this.createdApps.size,
      apps: new Map(this.createdApps),
      feesCollectedTotal: this.cumulativeFeesCollected,
      feesDistributed: 0n,
      treasuryUsdcBalance,
      treasuryUsdcRevenue,
      blockNumber,
      timestamp: Number(block.timestamp),
    };
  }

  /**
   * Get contract addresses for logging
   */
  private getContractAddresses(): Record<string, string> {
    if (!this.state) return {};
    return {
      elta: this.state.elta,
      veElta: this.state.veElta,
      appFactory: this.state.appFactory,
      feeRouter: this.state.feeRouter,
      feeCollector: this.state.feeCollector,
      feeManager: this.state.feeManager,
      treasuryVault: this.state.treasuryVault,
      usdc: this.state.usdc,
    };
  }

  /**
   * Clean up - stop Anvil
   */
  async cleanup(): Promise<void> {
    // Wait for any pending time advance to complete
    if (this.pendingTimeAdvance) {
      try {
        await this.pendingTimeAdvance;
      } catch {
        // Ignore errors from pending operations during cleanup
      }
      this.pendingTimeAdvance = null;
    }

    if (this.anvil) {
      await stopAnvil(this.anvil);
      this.anvil = null;
    }
    this.publicClient = null;
    this.deployerWallet = null;
    this.agentWallets.clear();
  }

  /**
   * Get current world state
   */
  getWorldState(): EltaWorldState {
    if (!this.state) {
      throw new Error('EltaPack not initialized');
    }
    return this.state;
  }

  getDeployedContracts(): string[] {
    return [...this.deployedAddresses.keys()].sort((a, b) => a.localeCompare(b));
  }

  getCapabilityManifest(): CapabilityManifest {
    const contracts = [...this.deployedAddresses.entries()].map(([alias, address]) => ({
      alias,
      address,
    }));
    return {
      version: 'v1',
      tools: ['QueryWorld', 'RpcCall', 'PostMessage', 'ContractCall', 'ContractRead'],
      queryEndpoints: [
        { name: 'get_world', cost: 1 },
        { name: 'get_apps', cost: 2 },
        { name: 'get_fee_state', cost: 2 },
        { name: 'get_governance_state', cost: 2 },
        { name: 'get_agent_position', cost: 2 },
      ],
      contracts,
      actionTemplates: [
        {
          name: 'QueryWorld',
          description: 'Read indexed protocol state',
          exampleParams: { endpoint: 'get_world', params: {} },
        },
        {
          name: 'RpcCall',
          description: 'Probe chain state via JSON-RPC',
          exampleParams: { method: 'eth_blockNumber', params: [] },
        },
        {
          name: 'PostMessage',
          description: 'Broadcast to gossip channel',
          exampleParams: { channelId: 'global', text: 'signal', intentTag: 'inform' },
        },
      ],
    };
  }

  /**
   * Get current metrics
   */
  getMetrics(): Record<string, number | bigint | string> {
    return { ...this.metrics };
  }

  /**
   * Called at the start of each tick
   */
  onTick(tick: number, _timestamp: number): void {
    // Track current tick for price history
    this.currentTick = tick;

    // Advance time if needed (tickSeconds)
    if (tick > 0 && this.anvil) {
      // Store promise so cleanup can await it
      this.pendingTimeAdvance = this.doAdvanceTime();
      // Fire and forget - we don't await in the sync interface
      void this.pendingTimeAdvance
        .then(() => {
          this.pendingTimeAdvance = null;
        })
        .catch(() => {
          this.pendingTimeAdvance = null;
        });
    }

    // Update metrics synchronously from current state
    // This ensures metrics are available when metricsCollector.sample() is called
    this.updateMetricsSync();
  }

  /**
   * Advance time in Anvil (async helper)
   */
  private async doAdvanceTime(): Promise<void> {
    if (!this.anvil) return;

    try {
      await anvilRpc.increaseTime(this.anvil.url, this.tickSeconds);
      await anvilRpc.mine(this.anvil.url);

      // Refresh world state
      this.state = await this.fetchWorldState();
    } catch (error) {
      // Ignore errors if Anvil was stopped during cleanup
      if (this.anvil) {
        console.warn('Error advancing time:', (error as Error).message);
      }
    }
  }

  /**
   * Update tracked metrics synchronously from current state
   */
  private updateMetricsSync(): void {
    if (!this.state) return;

    this.metrics = {
      // Token metrics
      elta_total_supply: this.state.totalEltaSupply,
      veelta_total_locked: this.state.totalVeEltaLocked,

      // App metrics
      app_count: this.state.appCount,
      graduated_apps: this.countGraduatedApps(),

      // Fee metrics (ELTA)
      fees_collected_total: this.state.feesCollectedTotal,
      fees_distributed: this.state.feesDistributed,

      // Treasury USDC metrics
      treasury_usdc_balance: this.state.treasuryUsdcBalance,
      treasury_usdc_revenue: this.state.treasuryUsdcRevenue,

      // Block info
      block_number: this.state.blockNumber,
      timestamp: this.state.timestamp,

      // Gas metrics
      gas_total: this.totalGasUsed,
    };

    // Add per-app metrics and track price history
    for (const [id, app] of this.state.apps) {
      this.metrics[`app_${id}_price`] = app.tokenPrice;
      this.metrics[`app_${id}_raised`] = app.totalRaised;
      this.metrics[`app_${id}_graduated`] = app.graduated ? 1 : 0;

      // Record price history
      if (!this.priceHistory.has(id)) {
        this.priceHistory.set(id, new Map());
      }
      this.priceHistory.get(id)!.set(this.currentTick, app.tokenPrice);

      // Calculate price change if we have history
      const history = this.priceHistory.get(id);
      if (history && history.size > 1) {
        const prevTick = this.currentTick - 1;
        const prevPrice = history.get(prevTick);
        if (prevPrice && prevPrice > 0n) {
          const changePercent = ((app.tokenPrice - prevPrice) * 10000n) / prevPrice;
          this.metrics[`app_${id}_price_change_bps`] = changePercent;
        }
      }
    }

    // Add gas metrics per agent
    for (const [agentId, gas] of this.gasUsedByAgent) {
      this.metrics[`gas_per_agent_${agentId}`] = gas;
    }

    // Add gas metrics per action type
    for (const [actionType, gas] of this.gasUsedByAction) {
      this.metrics[`gas_per_action_${actionType}`] = gas;
    }

    // Add agent P&L metrics
    for (const [agentId, realizedPnL] of this.agentRealizedPnL) {
      this.metrics[`agent_${agentId}_realized_pnl`] = realizedPnL;
    }

    // ===========================================
    // SIMULATION METRICS
    // ===========================================

    // TVL (Total Value Locked) - veELTA locked + app tokens staked
    const tvlVeElta = this.state.totalVeEltaLocked;
    const tvlApps = this.calculateAppsTVL();
    this.metrics['tvl_veelta'] = tvlVeElta;
    this.metrics['tvl_apps'] = tvlApps;
    this.metrics['tvl_total'] = tvlVeElta + tvlApps;

    // Trading Volume metrics
    this.metrics['trading_volume_total'] = this.totalTradingVolume;
    this.metrics['trading_volume_24h'] = this.calculateRecentVolume(24); // Last 24 "hours" of ticks
    for (const [action, volume] of this.volumeByAction) {
      this.metrics[`volume_${action}`] = volume;
    }

    // User metrics
    this.metrics['users_total_unique'] = this.totalUniqueUsers.size;
    this.metrics['users_active_this_tick'] = this.activeUsersThisTick.size;
    this.metrics['dau_estimate'] = this.calculateDAU();
    
    // Revenue per user (if any users)
    const totalRevenue = this.state.treasuryUsdcRevenue + this.state.feesCollectedTotal;
    this.metrics['revenue_total'] = totalRevenue;
    if (this.totalUniqueUsers.size > 0) {
      this.metrics['revenue_per_user'] = totalRevenue / BigInt(this.totalUniqueUsers.size);
    } else {
      this.metrics['revenue_per_user'] = 0n;
    }

    // Feature adoption rates
    this.metrics['feature_content_purchases'] = this.contentPurchases;
    this.metrics['feature_tournament_entries'] = this.tournamentEntries;
    this.metrics['feature_referrals'] = this.referralRegistrations;
    this.metrics['feature_governance_votes'] = this.governanceVotes;
    this.metrics['feature_staking_events'] = this.stakingEvents;
    this.metrics['feature_app_trades'] = this.appTokenTrades;

    // Token velocity (simplified: trades per unit supply)
    if (this.state.totalEltaSupply > 0n) {
      const velocity = (this.totalTradingVolume * 1000n) / this.state.totalEltaSupply;
      this.metrics['token_velocity_bps'] = velocity; // Basis points
    }

    // Revenue by category
    for (const [category, revenue] of this.revenueByCategory) {
      this.metrics[`revenue_${category}`] = revenue;
    }

    // Staking rate (% of supply locked)
    if (this.state.totalEltaSupply > 0n) {
      const stakingRate = (tvlVeElta * 10000n) / this.state.totalEltaSupply;
      this.metrics['staking_rate_bps'] = stakingRate;
    }

    // App graduation rate
    if (this.state.appCount > 0) {
      const graduationRate = (this.countGraduatedApps() * 10000) / this.state.appCount;
      this.metrics['graduation_rate_bps'] = graduationRate;
    }

    // Clear per-tick trackers
    this.activeUsersThisTick.clear();
  }

  /**
   * Calculate total TVL in app tokens (simplified)
   */
  private calculateAppsTVL(): bigint {
    let total = 0n;
    const apps = this.state?.apps ?? new Map<string, AppState>();
    for (const [_id, app] of apps) {
      // TVL = token supply * price (in ELTA terms)
      total += (app.tokenSupply * app.tokenPrice) / BigInt(1e18);
    }
    return total;
  }

  /**
   * Calculate recent trading volume (last N ticks)
   */
  private calculateRecentVolume(ticks: number): bigint {
    // For simplicity, return total volume / tick count * ticks
    // A more accurate implementation would track volume per tick
    if (this.currentTick === 0) return 0n;
    return (this.totalTradingVolume * BigInt(Math.min(ticks, this.currentTick))) / BigInt(this.currentTick);
  }

  /**
   * Calculate DAU estimate from recent active users
   */
  private calculateDAU(): number {
    // Sum unique users from recent ticks (simulated "day")
    const dayTicks = 96; // ~24 hours at 15min ticks
    const uniqueRecent = new Set<string>();
    
    for (let t = Math.max(0, this.currentTick - dayTicks); t <= this.currentTick; t++) {
      const users = this.dauByTick.get(t);
      if (users) {
        for (const user of users) {
          uniqueRecent.add(user);
        }
      }
    }
    
    return uniqueRecent.size;
  }

  /**
   * Track user activity for metrics
   */
  private trackUserActivity(agentId: string): void {
    this.activeUsersThisTick.add(agentId);
    this.totalUniqueUsers.add(agentId);
    
    // Track for DAU calculation
    if (!this.dauByTick.has(this.currentTick)) {
      this.dauByTick.set(this.currentTick, new Set());
    }
    this.dauByTick.get(this.currentTick)!.add(agentId);
    
    // Cleanup old DAU data (keep last 200 ticks)
    if (this.currentTick > 200) {
      this.dauByTick.delete(this.currentTick - 200);
    }
  }

  /**
   * Track trading volume
   */
  private trackVolume(actionType: string, amount: bigint): void {
    this.totalTradingVolume += amount;
    const current = this.volumeByAction.get(actionType) ?? 0n;
    this.volumeByAction.set(actionType, current + amount);
  }

  /**
   * Track feature usage
   */
  /**
   * Count how many apps have graduated
   */
  private countGraduatedApps(): number {
    let count = 0;
    for (const [_id, app] of this.createdApps) {
      if (app.graduated) count++;
    }
    return count;
  }

  /**
   * Register an agent and create a wallet for them
   * Implements the Pack.registerAgent interface
   */
  async registerAgent(agentId: string): Promise<Address> {
    if (!this.anvil) {
      throw new Error('EltaPack not initialized');
    }

    // Find an unused account
    const anvil = this.anvil;
    const usedIndices = new Set(
      Array.from(this.agentWallets.values()).map((w) => anvil.accounts.indexOf(w.address))
    );

    let accountIndex = -1;
    for (let i = 1; i < this.anvil.accounts.length; i++) {
      // Skip index 0 (deployer)
      if (!usedIndices.has(i)) {
        accountIndex = i;
        break;
      }
    }

    if (accountIndex === -1) {
      throw new Error('No available accounts for agent');
    }

    const address = this.anvil.accounts[accountIndex] as Address;
    const privateKey = this.anvil.privateKeys[accountIndex] as `0x${string}`;

    const account = privateKeyToAccount(privateKey);
    const client = createWalletClient({
      account,
      chain: foundry,
      transport: http(this.anvil.url),
    });

    this.agentWallets.set(agentId, { address, privateKey, client });

    // Fund the agent with ETH
    await anvilRpc.setBalance(this.anvil.url, address, this.config.agentEthBalance);

    // Fund the agent with tokens using configurable funding
    if (this.config.funding) {
      await this.fundAgent(agentId, this.config.funding);
    } else {
      // Default: fund with ELTA from deployer (backwards compatible)
      await this.fundAgentWithELTA(address, this.config.agentEltaBalance);
    }

    // Grant XP to agent for early buy access
    await this.grantAgentXP(address);

    // Record starting balance for P&L tracking
    const startingBalance = await this.getAgentEltaBalance(agentId);
    this.agentStartingBalances.set(agentId, startingBalance);
    this.agentRealizedPnL.set(agentId, 0n);

    return address;
  }

  /**
   * Grant XP (ElataPoints) to an agent for early buy access
   * The deployer has POINTS_OPERATOR_ROLE and can call award()
   */
  private async grantAgentXP(to: Address): Promise<void> {
    const xpAddress = this.deployedAddresses.get('ElataPoints');
    if (!xpAddress || !this.deployerWallet || !this.publicClient) return;

    const awardAbi = [
      {
        name: 'award',
        type: 'function',
        stateMutability: 'nonpayable',
        inputs: [
          { name: 'to', type: 'address' },
          { name: 'amount', type: 'uint256' },
        ],
        outputs: [],
      },
    ] as const;

    const account = this.deployerWallet.account;
    if (!account) return;

    try {
      // Award 1000 XP (100e18 is minimum required for early buy)
      const xpAmount = parseEther('1000');
      const hash = await this.deployerWallet.writeContract({
        address: xpAddress,
        abi: awardAbi,
        functionName: 'award',
        args: [to, xpAmount],
        chain: foundry,
        account,
      });
      await this.publicClient.waitForTransactionReceipt({ hash });
    } catch (error) {
      console.warn(`Failed to grant XP to ${to}: ${(error as Error).message}`);
    }
  }

  /**
   * Fund an agent using the provided FundingConfig
   * Implements the Pack.fundAgent interface
   *
   * @param agentId - The agent to fund
   * @param config - Funding configuration (token, amount, method)
   */
  async fundAgent(agentId: string, config: FundingConfig): Promise<void> {
    const wallet = this.agentWallets.get(agentId);
    if (!wallet) {
      throw new Error(`Agent ${agentId} not registered`);
    }

    const { tokenAddress, amountPerAgent, method, treasuryAddress, customFunder } = config;

    if (method === 'custom' && customFunder) {
      // Use project-provided custom funder
      await customFunder(wallet.address, amountPerAgent, this.deployerWallet);
      return;
    }

    if (!tokenAddress || !this.deployerWallet || !this.publicClient) {
      console.warn('Cannot fund agent: missing token address or deployer wallet');
      return;
    }

    if (method === 'mint') {
      await this.fundAgentByMint(wallet.address, tokenAddress, amountPerAgent);
    } else {
      // Default to transfer
      const from = treasuryAddress ?? this.deployerWallet.account?.address;
      if (!from) {
        console.warn('Cannot fund agent: no treasury address available');
        return;
      }
      await this.fundAgentByTransfer(wallet.address, tokenAddress, amountPerAgent);
    }
  }

  /**
   * Fund an agent by minting tokens
   */
  private async fundAgentByMint(to: Address, tokenAddress: Address, amount: bigint): Promise<void> {
    if (!this.deployerWallet || !this.publicClient) return;

    const mintAbi = [
      {
        name: 'mint',
        type: 'function',
        stateMutability: 'nonpayable',
        inputs: [
          { name: 'to', type: 'address' },
          { name: 'amount', type: 'uint256' },
        ],
        outputs: [],
      },
    ] as const;

    const account = this.deployerWallet.account;
    if (!account) {
      throw new Error('No deployer account available');
    }

    const hash = await this.deployerWallet.writeContract({
      address: tokenAddress,
      abi: mintAbi,
      functionName: 'mint',
      args: [to, amount],
      chain: foundry,
      account,
    });
    await this.publicClient.waitForTransactionReceipt({ hash });
  }

  /**
   * Fund an agent by transferring tokens from deployer
   */
  private async fundAgentByTransfer(
    to: Address,
    tokenAddress: Address,
    amount: bigint
  ): Promise<void> {
    if (!this.deployerWallet || !this.publicClient) {
      throw new Error('No deployer wallet or public client available');
    }

    const transferAbi = [
      {
        name: 'transfer',
        type: 'function',
        stateMutability: 'nonpayable',
        inputs: [
          { name: 'to', type: 'address' },
          { name: 'amount', type: 'uint256' },
        ],
        outputs: [{ name: '', type: 'bool' }],
      },
    ] as const;

    const account = this.deployerWallet.account;
    if (!account) {
      throw new Error('No deployer account available');
    }

    const hash = await this.deployerWallet.writeContract({
      address: tokenAddress,
      abi: transferAbi,
      functionName: 'transfer',
      args: [to, amount],
      chain: foundry,
      account,
    });
    await this.publicClient.waitForTransactionReceipt({ hash });
  }

  /**
   * Fund an agent with ELTA tokens (default behavior)
   * Uses mint if available (MockELTA), otherwise transfer from deployer
   */
  private async fundAgentWithELTA(to: Address, amount: bigint): Promise<void> {
    const eltaAddress =
      this.deployedAddresses.get('ELTA') ?? this.deployedAddresses.get('MockELTA');
    if (!eltaAddress || !this.deployerWallet || !this.publicClient) {
      return;
    }

    // Try mint first (works with MockELTA), then fall back to transfer
    try {
      await this.fundAgentByMint(to, eltaAddress, amount);
    } catch {
      // Mint failed (real ELTA has access control), try transfer from treasury
      try {
        await this.fundAgentByTransfer(to, eltaAddress, amount);
      } catch (error) {
        console.warn(`Could not fund ${to} with ELTA: ${(error as Error).message}`);
      }
    }
  }

  /**
   * Get agent's wallet
   */
  getAgentWallet(agentId: string): AgentWallet {
    const wallet = this.agentWallets.get(agentId);
    if (!wallet) {
      throw new Error(`Agent ${agentId} not registered`);
    }
    return wallet;
  }

  /**
   * Get an agent's ELTA balance
   */
  async getAgentEltaBalance(agentId: string): Promise<bigint> {
    const wallet = this.agentWallets.get(agentId);
    if (!wallet || !this.publicClient) {
      return 0n;
    }

    const eltaAddress = this.state?.elta;
    if (!eltaAddress || eltaAddress === zeroAddress) {
      // No ELTA contract, return configured balance as approximation
      return this.config.agentEltaBalance;
    }

    const balanceAbi = [
      {
        name: 'balanceOf',
        type: 'function',
        stateMutability: 'view',
        inputs: [{ name: 'account', type: 'address' }],
        outputs: [{ name: '', type: 'uint256' }],
      },
    ] as const;

    try {
      const balance = await this.publicClient.readContract({
        address: eltaAddress,
        abi: balanceAbi,
        functionName: 'balanceOf',
        args: [wallet.address],
      });
      return balance;
    } catch {
      // Return configured balance if contract call fails
      return this.config.agentEltaBalance;
    }
  }

  /**
   * Get an agent's veELTA balance
   */
  async getAgentVeEltaBalance(agentId: string): Promise<bigint> {
    const wallet = this.agentWallets.get(agentId);
    if (!wallet || !this.publicClient) {
      return 0n;
    }

    const veEltaAddress = this.state?.veElta;
    if (!veEltaAddress || veEltaAddress === zeroAddress) {
      return 0n;
    }

    const balanceAbi = [
      {
        name: 'balanceOf',
        type: 'function',
        stateMutability: 'view',
        inputs: [{ name: 'account', type: 'address' }],
        outputs: [{ name: '', type: 'uint256' }],
      },
    ] as const;

    try {
      const balance = await this.publicClient.readContract({
        address: veEltaAddress,
        abi: balanceAbi,
        functionName: 'balanceOf',
        args: [wallet.address],
      });
      return balance;
    } catch {
      return 0n;
    }
  }

  /**
   * Get an agent's app token balance for a specific app
   */
  async getAgentAppTokenBalance(agentId: string, appId: string): Promise<bigint> {
    const wallet = this.agentWallets.get(agentId);
    if (!wallet || !this.publicClient) {
      return 0n;
    }

    // Find the app to get its token address
    const appState = this.createdApps.get(appId);
    if (!appState || appState.tokenAddress === zeroAddress) {
      return 0n;
    }

    const balanceAbi = [
      {
        name: 'balanceOf',
        type: 'function',
        stateMutability: 'view',
        inputs: [{ name: 'account', type: 'address' }],
        outputs: [{ name: '', type: 'uint256' }],
      },
    ] as const;

    try {
      const balance = await this.publicClient.readContract({
        address: appState.tokenAddress,
        abi: balanceAbi,
        functionName: 'balanceOf',
        args: [wallet.address],
      });
      return balance;
    } catch {
      return 0n;
    }
  }

  /**
   * Create bootstrap apps for user agents to trade
   * Uses real AppFactory contracts to create tradeable apps
   */
  private async createBootstrapApps(): Promise<void> {
    const bootstrapApps = [
      { name: 'ElataChat', symbol: 'ECHAT' },
      { name: 'ElataSwap', symbol: 'ESWAP' },
      { name: 'ElataNFT', symbol: 'ENFT' },
    ];

    console.log('Creating bootstrap apps via AppFactory...');

    for (const app of bootstrapApps) {
      const created = await this.createRealApp(app.name, app.symbol);
      if (!created) {
        // Fall back to simulated app if real creation fails
        console.warn(`Failed to create real app ${app.name}, using simulated`);
        await this.createAppInternal(app.name, app.symbol);
      }
    }

    // Refresh state to include new apps
    this.state = await this.fetchWorldState();
    this.updateMetricsSync();

    console.log(`Created ${this.createdApps.size} bootstrap apps`);
  }

  /**
   * Create a real app via AppFactory using the deployer wallet
   * This creates actual on-chain contracts that agents can trade
   */
  private async createRealApp(name: string, symbol: string): Promise<AppState | null> {
    const factoryAddress = this.deployedAddresses.get('AppFactory');
    const eltaAddress = this.deployedAddresses.get('ELTA');

    if (
      !factoryAddress ||
      factoryAddress === zeroAddress ||
      !this.publicClient ||
      !eltaAddress ||
      !this.deployerWallet
    ) {
      return null;
    }

    const abi = this.abis.get('AppFactory');
    if (!abi) {
      return null;
    }

    try {
      const account = this.deployerWallet.account;
      if (!account) {
        return null;
      }

      // First, approve ELTA for the factory (creation fee + seed)
      const approvalAmount = parseEther('1000');
      const approveAbi = [
        {
          name: 'approve',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'spender', type: 'address' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [{ name: '', type: 'bool' }],
        },
      ] as const;

      const approveHash = await this.deployerWallet.writeContract({
        address: eltaAddress,
        abi: approveAbi,
        functionName: 'approve',
        args: [factoryAddress, approvalAmount],
        chain: foundry,
        account,
      });
      await this.publicClient.waitForTransactionReceipt({ hash: approveHash });

      // createApp(name, symbol, supply, description, imageURI, website, operators)
      const hash = await this.deployerWallet.writeContract({
        address: factoryAddress,
        abi,
        functionName: 'createApp',
        args: [
          name,
          symbol,
          0n, // supply - 0 for default
          `Bootstrap app: ${name}`, // description
          '', // imageURI
          '', // website
          [], // operators
        ],
        chain: foundry,
        account,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });

      // Parse AppCreated event to get real addresses
      const appCreatedEvent = this.parseAppCreatedEvent(receipt.logs, abi);
      if (appCreatedEvent) {
        // Store real app state with real addresses
        const appState: AppState = {
          id: Number(appCreatedEvent.appId),
          name,
          symbol,
          creator: account.address,
          tokenAddress: appCreatedEvent.token,
          curveAddress: appCreatedEvent.curve,
          graduated: false,
          totalRaised: 0n,
          tokenPrice: parseEther('0.001'),
          tokenSupply: parseEther('1000000'),
        };
        this.createdApps.set(appCreatedEvent.appId.toString(), appState);

        // Create a temporary wallet wrapper for activation
        const deployerWalletWrapper: AgentWallet = {
          address: account.address,
          privateKey: this.anvil?.privateKeys[0] as `0x${string}`,
          client: this.deployerWallet,
        };

        // Activate the bonding curve so users can buy tokens
        await this.tryActivateBondingCurve(appCreatedEvent.curve, deployerWalletWrapper);

        // Set FeeCollector on the bonding curve for fee routing
        await this.trySetFeeCollector(appCreatedEvent.curve, deployerWalletWrapper);

        console.log(
          `Bootstrap app created: ${name} (appId=${appCreatedEvent.appId}, curve=${appCreatedEvent.curve})`
        );
        return appState;
      }
    } catch (error) {
      console.warn(`Failed to create real app ${name}: ${(error as Error).message}`);
    }

    return null;
  }

  /**
   * Internal method to create a simulated app (fallback when real creation fails)
   */
  private async createAppInternal(name: string, symbol: string): Promise<AppState | null> {
    // Create a simulated app state (fallback when AppFactory is unavailable)
    const appId = this.appCounter++;
    const appState: AppState = {
      id: appId,
      name,
      symbol,
      creator: this.deployerWallet?.account?.address ?? zeroAddress,
      tokenAddress: `0x${appId.toString(16).padStart(40, '0')}` as Address,
      curveAddress: `0x${(appId + 1000).toString(16).padStart(40, '0')}` as Address,
      graduated: false,
      totalRaised: 0n,
      tokenPrice: parseEther('0.001'), // Initial price
      tokenSupply: parseEther('1000000'), // 1M tokens
    };

    this.createdApps.set(appId.toString(), appState);
    return appState;
  }

  /**
   * Execute an action
   */
  async executeAction(action: Action, agentId: string): Promise<ActionResult> {
    const wallet = this.getAgentWallet(agentId);
    const payload = action.params as unknown as EltaAction;
    const actionType = payload.type;

    const trackGas = (result: ActionResult) => {
      if (result.gasUsed) {
        // Track total gas
        this.totalGasUsed += result.gasUsed;

        // Track gas per agent
        const currentAgentGas = this.gasUsedByAgent.get(agentId) ?? 0n;
        this.gasUsedByAgent.set(agentId, currentAgentGas + result.gasUsed);

        // Track gas per action type
        const currentActionGas = this.gasUsedByAction.get(actionType) ?? 0n;
        this.gasUsedByAction.set(actionType, currentActionGas + result.gasUsed);
      }
      return result;
    };

    // Track user activity for simulation metrics
    this.trackUserActivity(agentId);

    try {
      let result: ActionResult;

      switch (actionType) {
        case 'buy_app_token':
          result = await this.executeBuyAppToken(wallet, payload);
          if (result.ok) {
            // Track volume for simulation metrics
            const amount = (payload as { eltaAmount?: bigint }).eltaAmount ?? 0n;
            this.trackVolume('buy', amount);
            this.appTokenTrades++;
          }
          break;

        case 'sell_app_token':
          result = await this.executeSellAppToken(wallet, payload);
          if (result.ok) {
            // Track volume for simulation metrics
            const amount = (payload as { tokenAmount?: bigint }).tokenAmount ?? 0n;
            this.trackVolume('sell', amount);
            this.appTokenTrades++;
          }
          break;

        case 'create_app':
          result = await this.executeCreateApp(wallet, payload);
          break;

        case 'lock_veelta':
          result = await this.executeLockVeElta(wallet, payload);
          if (result.ok) {
            this.stakingEvents++;
            const amount = (payload as { amount?: bigint }).amount ?? 0n;
            this.trackVolume('stake', amount);
          }
          break;

        case 'unlock_veelta':
          result = await this.executeUnlockVeElta(wallet);
          if (result.ok) this.stakingEvents++;
          break;

        case 'extend_lock':
          result = await this.executeExtendLock(wallet, payload);
          if (result.ok) this.stakingEvents++;
          break;

        case 'increase_amount':
          result = await this.executeIncreaseAmount(wallet, payload);
          if (result.ok) this.stakingEvents++;
          break;

        case 'stake_app_token':
          result = await this.executeStakeAppToken(wallet, payload);
          if (result.ok) this.stakingEvents++;
          break;

        case 'unstake_app_token':
          result = await this.executeUnstakeAppToken(wallet, payload);
          break;

        case 'claim_rewards':
          result = await this.executeClaimRewards(wallet, payload);
          break;

        case 'claim_app_rewards':
          result = await this.executeClaimAppRewards(wallet, payload);
          break;

        // Tournament actions
        case 'enter_tournament':
          result = await this.executeEnterTournament(wallet, payload);
          if (result.ok) {
            this.tournamentEntries++;
            const amount = (payload as { entryAmount?: bigint }).entryAmount ?? 0n;
            this.trackVolume('tournament', amount);
          }
          break;

        case 'claim_tournament_prize':
          result = await this.executeClaimTournamentPrize(wallet, payload);
          break;

        // Tournament actions (extended)
        case 'create_tournament':
          result = await this.executeCreateTournament(wallet, payload);
          if (result.ok) this.tournamentEntries++;
          break;

        case 'finalize_tournament':
          result = await this.executeFinalizeTournament(wallet, payload);
          break;

        // Content/NFT actions
        case 'purchase_content':
          result = await this.executePurchaseContent(wallet, payload);
          if (result.ok) {
            this.contentPurchases++;
            const price = (payload as { maxPrice?: bigint }).maxPrice ?? 0n;
            this.trackVolume('content', price);
          }
          break;

        case 'list_content':
          result = await this.executeListContent(wallet, payload);
          break;

        case 'list_content_with_time_window':
          result = await this.executeListContentWithTimeWindow(wallet, payload);
          break;

        case 'deactivate_content':
          result = await this.executeDeactivateContent(wallet, payload);
          break;

        case 'reactivate_content':
          result = await this.executeReactivateContent(wallet, payload);
          break;

        // Governance actions
        case 'create_proposal':
          result = await this.executeCreateProposal(wallet, payload);
          if (result.ok) this.governanceVotes++;
          break;

        case 'cast_vote':
          result = await this.executeCastVote(wallet, payload);
          if (result.ok) this.governanceVotes++;
          break;

        case 'queue_proposal':
          result = await this.executeQueueProposal(wallet, payload);
          break;

        case 'execute_proposal':
          result = await this.executeExecuteProposal(wallet, payload);
          break;

        // Fee pipeline actions
        case 'sweep_fees':
          result = await this.executeSweepFees(wallet, payload);
          break;

        case 'sweep_elta_to_feemanager':
          result = await this.executeSweepEltaToFeeManager(wallet, payload);
          break;

        case 'close_fee_epoch':
          result = await this.executeCloseFeeEpoch(wallet, payload);
          break;

        // Referral actions
        case 'set_referrer':
          result = await this.executeSetReferrer(wallet, payload);
          if (result.ok) this.referralRegistrations++;
          break;

        case 'claim_referral_rewards':
          result = await this.executeClaimReferralRewards(wallet);
          break;

        // Airdrop actions
        case 'claim_airdrop':
          result = await this.executeClaimAirdrop(wallet, payload);
          break;

        // XP/Points actions
        case 'claim_xp_points':
          result = await this.executeClaimXpPoints(wallet, payload);
          break;

        // Vesting actions
        case 'release_vested_tokens':
          result = await this.executeReleaseVestedTokens(wallet, payload);
          break;

        case 'noop':
          return { ok: true };

        default:
          return {
            ok: false,
            error: `Unknown action type: ${(payload as EltaAction).type}`,
          };
      }

      return trackGas(result);
    } catch (error) {
      return {
        ok: false,
        error: (error as Error).message,
      };
    }
  }

  async callRpc(method: string, params: unknown[] = []): Promise<unknown> {
    if (!this.publicClient) {
      throw new Error('Public client not initialized');
    }
    return this.publicClient.request({
      method: method as never,
      params: params as never,
    });
  }

  /**
   * Check if a bonding curve is active and not graduated
   */
  private async getCurveState(
    curveAddress: Address
  ): Promise<{ isActive: boolean; graduated: boolean }> {
    if (!this.publicClient) {
      return { isActive: false, graduated: false };
    }

    const stateAbi = [
      {
        name: 'state',
        type: 'function',
        stateMutability: 'view',
        inputs: [],
        outputs: [{ name: '', type: 'uint8' }],
      },
      {
        name: 'graduated',
        type: 'function',
        stateMutability: 'view',
        inputs: [],
        outputs: [{ name: '', type: 'bool' }],
      },
    ] as const;

    try {
      const [state, graduated] = await Promise.all([
        this.publicClient.readContract({
          address: curveAddress,
          abi: stateAbi,
          functionName: 'state',
        }),
        this.publicClient.readContract({
          address: curveAddress,
          abi: stateAbi,
          functionName: 'graduated',
        }),
      ]);
      // State enum: 0 = PENDING, 1 = ACTIVE, 2 = GRADUATED
      return { isActive: state === 1, graduated: graduated as boolean };
    } catch {
      return { isActive: false, graduated: false };
    }
  }

  /**
   * Execute buy app token action
   */
  private async executeBuyAppToken(
    wallet: AgentWallet,
    action: { appAddress: Address; eltaAmount: bigint; minTokensOut: bigint | undefined }
  ): Promise<ActionResult> {
    // Try to find the app in our tracked state
    let appState: AppState | undefined;
    for (const [_id, app] of this.createdApps) {
      if (app.tokenAddress === action.appAddress || app.curveAddress === action.appAddress) {
        appState = app;
        break;
      }
    }

    // If we have a bonding curve ABI and address, try real contract call
    const curveAbi = this.abis.get('AppBondingCurve');
    // Use deployed address first, fallback to state
    const eltaAddress = this.deployedAddresses.get('ELTA') ?? this.state?.elta;
    if (curveAbi && appState && this.publicClient && eltaAddress && eltaAddress !== zeroAddress) {
      // Check curve state before attempting buy
      const curveState = await this.getCurveState(appState.curveAddress);
      if (curveState.graduated) {
        // Update local state to reflect graduation
        appState.graduated = true;
        return { ok: false, error: 'Bonding curve has graduated - use Uniswap to trade' };
      }
      if (!curveState.isActive) {
        return { ok: false, error: 'Bonding curve is not active' };
      }

      try {
        // First approve ELTA spending with a large amount (avoid per-tx approvals)
        const approveAbi = [
          {
            name: 'approve',
            type: 'function',
            stateMutability: 'nonpayable',
            inputs: [
              { name: 'spender', type: 'address' },
              { name: 'amount', type: 'uint256' },
            ],
            outputs: [{ name: '', type: 'bool' }],
          },
        ] as const;

        // Approve max uint256 to avoid repeated approvals
        const maxApproval = BigInt(
          '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        );

        try {
          const approveHash = await wallet.client.writeContract({
            address: eltaAddress,
            abi: approveAbi,
            functionName: 'approve',
            args: [appState.curveAddress, maxApproval],
            chain: foundry,
            account: wallet.client.account!,
          });
          await this.publicClient.waitForTransactionReceipt({ hash: approveHash });
        } catch (approveError) {
          console.warn(`Approve failed: ${(approveError as Error).message}`);
          throw approveError;
        }

        // Then buy tokens: buy(eltaIn, minTokensOut, referrer)
        const hash = await wallet.client.writeContract({
          address: appState.curveAddress,
          abi: curveAbi,
          functionName: 'buy',
          args: [action.eltaAmount, action.minTokensOut ?? 0n, zeroAddress],
          chain: foundry,
          account: wallet.client.account!,
        });

        const receipt = await this.publicClient.waitForTransactionReceipt({ hash });

        // Parse AppGraduated event to detect graduation during this buy
        const graduationEvent = this.parseAppGraduatedEvent(receipt.logs, curveAbi);
        if (graduationEvent && appState) {
          appState.graduated = true;
          appState.totalRaised = graduationEvent.totalRaisedElta;
          console.log(
            `App graduated! appId=${appState.id}, totalRaised=${graduationEvent.totalRaisedElta}`
          );
        } else if (appState) {
          // Read actual reserveElta from curve to get accurate totalRaised
          try {
            const reserveAbi = [
              {
                name: 'reserveElta',
                type: 'function',
                stateMutability: 'view',
                inputs: [],
                outputs: [{ name: '', type: 'uint256' }],
              },
            ] as const;

            const actualReserveElta = (await this.publicClient.readContract({
              address: appState.curveAddress,
              abi: reserveAbi,
              functionName: 'reserveElta',
            })) as bigint;

            // reserveElta includes the 100 ELTA seed, subtract it for net raised
            const seedElta = BigInt(100e18);
            appState.totalRaised = actualReserveElta > seedElta ? actualReserveElta - seedElta : 0n;
          } catch {
            // Fallback: just add the input amount
            appState.totalRaised += action.eltaAmount;
          }

          // Re-check graduation state after the buy
          const curveStateAfter = await this.getCurveState(appState.curveAddress);
          if (curveStateAfter.graduated) {
            appState.graduated = true;
            console.log(`App graduated after buy! appId=${appState.id}`);
          }
        }

        // Track fees (2% fee on buys)
        const feeAmount = action.eltaAmount / 50n;
        this.cumulativeFeesCollected += feeAmount;

        return { ok: true, gasUsed: receipt.gasUsed };
      } catch (error) {
        console.warn(`Contract buy failed: ${(error as Error).message}`);
      }
    }

    // Fallback: Simulate buy
    if (appState) {
      appState.totalRaised += action.eltaAmount;
      // Track fees (simulate 2% fee)
      const feeAmount = action.eltaAmount / 50n;
      this.cumulativeFeesCollected += feeAmount;
    }

    return {
      ok: true,
      gasUsed: 150000n,
    };
  }

  /**
   * Execute sell app token action
   *
   * NOTE: The bonding curve is BUY-ONLY. Selling is only possible after graduation
   * when the app has migrated to Uniswap. For simulation purposes, we use fallback
   * logic to simulate selling behavior.
   */
  private async executeSellAppToken(
    _wallet: AgentWallet,
    action: { appAddress: Address; tokenAmount: bigint; minEltaOut: bigint | undefined }
  ): Promise<ActionResult> {
    // Try to find the app in our tracked state
    let appState: AppState | undefined;
    for (const [_id, app] of this.createdApps) {
      if (app.tokenAddress === action.appAddress || app.curveAddress === action.appAddress) {
        appState = app;
        break;
      }
    }

    // Check if app has graduated (selling only works post-graduation via Uniswap)
    if (appState && appState.graduated) {
      // TODO: Implement Uniswap sell via router for graduated apps
      // For now, fall through to simulation
    }

    // Bonding curve is buy-only, so we simulate sell behavior
    // In reality, users can only sell after graduation on Uniswap
    if (appState) {
      const eltaOut = (action.tokenAmount * appState.tokenPrice) / parseEther('1');
      // Track fees (simulate 2% fee)
      const feeAmount = eltaOut / 50n;
      this.cumulativeFeesCollected += feeAmount;
    }

    return {
      ok: true,
      gasUsed: 150000n,
    };
  }

  /**
   * Execute create app action
   */
  private async executeCreateApp(
    wallet: AgentWallet,
    action: { name: string; symbol: string; metadataUri: string | undefined }
  ): Promise<ActionResult> {
    // Use AppFactory for app creation (InAppContent721Factory/ContentStoreFactory for content modules)
    const factoryAddress = this.deployedAddresses.get('AppFactory');
    const eltaAddress = this.deployedAddresses.get('ELTA');

    // If we have the real AppFactory, try to call it
    if (factoryAddress && factoryAddress !== zeroAddress && this.publicClient && eltaAddress) {
      const abi = this.abis.get('AppFactory');
      if (abi) {
        try {
          // First, approve ELTA for the factory (creation fee + seed)
          // AppFactory requires ELTA approval for creationFee + seedElta
          const approvalAmount = parseEther('1000'); // Generous approval for fees
          const approveAbi = [
            {
              name: 'approve',
              type: 'function',
              stateMutability: 'nonpayable',
              inputs: [
                { name: 'spender', type: 'address' },
                { name: 'amount', type: 'uint256' },
              ],
              outputs: [{ name: '', type: 'bool' }],
            },
          ] as const;

          const approveHash = await wallet.client.writeContract({
            address: eltaAddress,
            abi: approveAbi,
            functionName: 'approve',
            args: [factoryAddress, approvalAmount],
            chain: foundry,
            account: wallet.client.account!,
          });
          await this.publicClient.waitForTransactionReceipt({ hash: approveHash });

          // createApp(name, symbol, supply, description, imageURI, website, operators)
          const hash = await wallet.client.writeContract({
            address: factoryAddress,
            abi,
            functionName: 'createApp',
            args: [
              action.name,
              action.symbol,
              0n, // supply - 0 for default
              '', // description - set via metadata later
              '', // imageURI - set via metadata later
              '', // website - set via metadata later
              [], // operators - empty array
            ],
            chain: foundry,
            account: wallet.client.account!,
          });

          const receipt = await this.publicClient.waitForTransactionReceipt({ hash });

          // Parse AppCreated event to get real addresses
          const appCreatedEvent = this.parseAppCreatedEvent(receipt.logs, abi);
          if (appCreatedEvent) {
            // Store real app state with real addresses
            const appState: AppState = {
              id: Number(appCreatedEvent.appId),
              name: action.name,
              symbol: action.symbol,
              creator: wallet.address,
              tokenAddress: appCreatedEvent.token,
              curveAddress: appCreatedEvent.curve,
              graduated: false,
              totalRaised: 0n,
              tokenPrice: parseEther('0.001'),
              tokenSupply: parseEther('1000000'),
            };
            this.createdApps.set(appCreatedEvent.appId.toString(), appState);
            console.log(
              `App created on-chain: appId=${appCreatedEvent.appId}, token=${appCreatedEvent.token}, curve=${appCreatedEvent.curve}`
            );

            // Activate the bonding curve so users can buy tokens
            // Try to activate immediately - if time hasn't advanced enough, activation will fail silently
            await this.tryActivateBondingCurve(appCreatedEvent.curve, wallet);

            // Set FeeCollector on the bonding curve for fee routing
            // Must use deployer wallet since setFeeCollector requires governance (which is the deployer)
            if (this.deployerWallet && this.anvil) {
              const deployerWalletWrapper: AgentWallet = {
                address: this.deployerWallet.account?.address ?? zeroAddress,
                privateKey: this.anvil.privateKeys[0] as `0x${string}`,
                client: this.deployerWallet,
              };
              await this.trySetFeeCollector(appCreatedEvent.curve, deployerWalletWrapper);
            }
          } else {
            // Fallback to internal tracking if event parsing fails
            await this.createAppInternal(action.name, action.symbol);
          }

          // Refresh world state
          this.state = await this.fetchWorldState();
          this.updateMetricsSync();

          return { ok: true, gasUsed: receipt.gasUsed };
        } catch (error) {
          // Contract call failed, fall back to simulation
          console.warn(`Contract createApp failed: ${(error as Error).message}`);
        }
      }
    }

    // Fallback: Create simulated app state
    const appState = await this.createAppInternal(action.name, action.symbol);
    if (!appState) {
      return { ok: false, error: 'Failed to create app' };
    }

    // Refresh world state
    this.state = await this.fetchWorldState();
    this.updateMetricsSync();

    return {
      ok: true,
      gasUsed: 500000n,
    };
  }

  /**
   * Get lock details for an address from VeELTA contract
   * Uses cache to avoid repeated contract reads
   */
  private async getVeEltaLockDetails(
    userAddress: Address
  ): Promise<{ principal: bigint; unlockTime: bigint; isExpired: boolean } | null> {
    // Check cache first
    const cached = this.lockStateCache.get(userAddress);
    if (cached) {
      // Return cached state - we don't track principal in cache but can infer from hasLock
      return {
        principal: cached.hasLock ? 1n : 0n, // Non-zero if has lock
        unlockTime: cached.unlockTime,
        isExpired: false, // Assume not expired in cache (simulation time is different)
      };
    }

    const veEltaAddress = this.deployedAddresses.get('VeELTA');
    if (!veEltaAddress || !this.publicClient) {
      return null;
    }

    try {
      const getLockDetailsAbi = [
        {
          name: 'getLockDetails',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'user', type: 'address' }],
          outputs: [
            { name: 'principal', type: 'uint256' },
            { name: 'unlockTime', type: 'uint64' },
            { name: 'veBalance', type: 'uint256' },
            { name: 'isExpired', type: 'bool' },
          ],
        },
      ] as const;

      const result = await this.publicClient.readContract({
        address: veEltaAddress,
        abi: getLockDetailsAbi,
        functionName: 'getLockDetails',
        args: [userAddress],
      });

      const principal = result[0] as bigint;
      const unlockTime = result[1] as bigint;
      const isExpired = result[3] as boolean;

      // Update cache
      this.lockStateCache.set(userAddress, {
        hasLock: principal > 0n && !isExpired,
        unlockTime,
      });

      return {
        principal,
        unlockTime,
        isExpired,
      };
    } catch {
      return null;
    }
  }

  /**
   * Execute lock veELTA action
   * If user already has a lock, automatically increases amount instead
   */
  private async executeLockVeElta(
    wallet: AgentWallet,
    action: { amount: bigint; duration: number }
  ): Promise<ActionResult> {
    const veEltaAddress = this.deployedAddresses.get('VeELTA');
    const eltaAddress = this.deployedAddresses.get('ELTA');

    if (!veEltaAddress || !eltaAddress || !this.publicClient) {
      return { ok: false, error: 'VeELTA or ELTA contract not deployed' };
    }

    try {
      // Check if user already has a lock
      const lockDetails = await this.getVeEltaLockDetails(wallet.address);

      if (lockDetails && lockDetails.principal > 0n && !lockDetails.isExpired) {
        // User already has an active lock - increase amount instead
        return await this.executeIncreaseAmount(wallet, { additionalAmount: action.amount });
      }

      // First approve ELTA for VeELTA
      const approveAbi = [
        {
          name: 'approve',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'spender', type: 'address' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [{ name: '', type: 'bool' }],
        },
      ] as const;

      const approveHash = await wallet.client.writeContract({
        address: eltaAddress,
        abi: approveAbi,
        functionName: 'approve',
        args: [veEltaAddress, action.amount],
        chain: foundry,
        account: wallet.client.account!,
      });
      await this.publicClient.waitForTransactionReceipt({ hash: approveHash });

      // Calculate unlock time from duration
      const currentBlock = await this.publicClient.getBlock();
      const unlockTime = BigInt(currentBlock.timestamp) + BigInt(action.duration);

      // Call lock(amount, unlockTime)
      const lockAbi = [
        {
          name: 'lock',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'amount', type: 'uint256' },
            { name: 'unlockTime', type: 'uint64' },
          ],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: veEltaAddress,
        abi: lockAbi,
        functionName: 'lock',
        args: [action.amount, unlockTime],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });

      // Update cache - user now has a lock
      this.lockStateCache.set(wallet.address, {
        hasLock: true,
        unlockTime,
      });

      // Update world state
      if (this.state) {
        this.state.totalVeEltaLocked += action.amount;
      }

      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Lock veELTA failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute unlock veELTA action
   */
  private async executeUnlockVeElta(wallet: AgentWallet): Promise<ActionResult> {
    const veEltaAddress = this.deployedAddresses.get('VeELTA');

    if (!veEltaAddress || !this.publicClient) {
      return { ok: false, error: 'VeELTA contract not deployed' };
    }

    try {
      const unlockAbi = [
        {
          name: 'unlock',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: veEltaAddress,
        abi: unlockAbi,
        functionName: 'unlock',
        args: [],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });

      // Invalidate cache - user no longer has a lock
      this.lockStateCache.delete(wallet.address);

      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Unlock veELTA failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute extend lock action
   */
  private async executeExtendLock(
    wallet: AgentWallet,
    action: { newUnlockTime: number }
  ): Promise<ActionResult> {
    const veEltaAddress = this.deployedAddresses.get('VeELTA');

    if (!veEltaAddress || !this.publicClient) {
      return { ok: false, error: 'VeELTA contract not deployed' };
    }

    try {
      // Check if user has an active lock
      const lockDetails = await this.getVeEltaLockDetails(wallet.address);
      if (!lockDetails || lockDetails.principal === 0n) {
        return { ok: false, error: 'No active lock to extend' };
      }

      // Verify new unlock time is greater than current
      if (BigInt(action.newUnlockTime) <= lockDetails.unlockTime) {
        return { ok: false, error: 'New unlock time must be greater than current' };
      }

      const extendAbi = [
        {
          name: 'extendLock',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'newUnlockTime', type: 'uint64' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: veEltaAddress,
        abi: extendAbi,
        functionName: 'extendLock',
        args: [BigInt(action.newUnlockTime)],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Extend lock failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute increase amount action
   */
  private async executeIncreaseAmount(
    wallet: AgentWallet,
    action: { additionalAmount: bigint }
  ): Promise<ActionResult> {
    const veEltaAddress = this.deployedAddresses.get('VeELTA');
    const eltaAddress = this.deployedAddresses.get('ELTA');

    if (!veEltaAddress || !eltaAddress || !this.publicClient) {
      return { ok: false, error: 'VeELTA or ELTA contract not deployed' };
    }

    try {
      // Check if user has an active (non-expired) lock
      const lockDetails = await this.getVeEltaLockDetails(wallet.address);
      if (!lockDetails || lockDetails.principal === 0n) {
        return { ok: false, error: 'No active lock to increase' };
      }
      if (lockDetails.isExpired) {
        return { ok: false, error: 'Lock has expired, cannot increase amount' };
      }

      // First approve ELTA for VeELTA
      const approveAbi = [
        {
          name: 'approve',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'spender', type: 'address' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [{ name: '', type: 'bool' }],
        },
      ] as const;

      const approveHash = await wallet.client.writeContract({
        address: eltaAddress,
        abi: approveAbi,
        functionName: 'approve',
        args: [veEltaAddress, action.additionalAmount],
        chain: foundry,
        account: wallet.client.account!,
      });
      await this.publicClient.waitForTransactionReceipt({ hash: approveHash });

      // Call increaseAmount(amount)
      const increaseAbi = [
        {
          name: 'increaseAmount',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'amount', type: 'uint256' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: veEltaAddress,
        abi: increaseAbi,
        functionName: 'increaseAmount',
        args: [action.additionalAmount],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });

      // Update world state
      if (this.state) {
        this.state.totalVeEltaLocked += action.additionalAmount;
      }

      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Increase amount failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute stake app token action
   */
  private async executeStakeAppToken(
    wallet: AgentWallet,
    action: { appId: string; appAddress: Address; amount: bigint }
  ): Promise<ActionResult> {
    // Find the app to get its staking vault address
    const appState = this.createdApps.get(action.appId);
    if (!appState) {
      return { ok: false, error: `App ${action.appId} not found` };
    }

    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    // Get vault address from AppFactory
    const factoryAddress = this.deployedAddresses.get('AppFactory');
    if (!factoryAddress) {
      return { ok: false, error: 'AppFactory not deployed' };
    }

    try {
      // Read vault address from factory
      const getVaultAbi = [
        {
          name: 'getApp',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'appId', type: 'uint256' }],
          outputs: [
            { name: 'token', type: 'address' },
            { name: 'vault', type: 'address' },
            { name: 'curve', type: 'address' },
            { name: 'creator', type: 'address' },
          ],
        },
      ] as const;

      const appData = (await this.publicClient.readContract({
        address: factoryAddress,
        abi: getVaultAbi,
        functionName: 'getApp',
        args: [BigInt(appState.id)],
      })) as [Address, Address, Address, Address];

      const vaultAddress = appData[1];
      const tokenAddress = appData[0];

      if (vaultAddress === zeroAddress) {
        return { ok: false, error: 'No staking vault for this app' };
      }

      // First approve app token for vault
      const approveAbi = [
        {
          name: 'approve',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'spender', type: 'address' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [{ name: '', type: 'bool' }],
        },
      ] as const;

      const approveHash = await wallet.client.writeContract({
        address: tokenAddress,
        abi: approveAbi,
        functionName: 'approve',
        args: [vaultAddress, action.amount],
        chain: foundry,
        account: wallet.client.account!,
      });
      await this.publicClient.waitForTransactionReceipt({ hash: approveHash });

      // Call stake(amount) on the vault
      const stakeAbi = [
        {
          name: 'stake',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'amount', type: 'uint256' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: vaultAddress,
        abi: stakeAbi,
        functionName: 'stake',
        args: [action.amount],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Stake app token failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute unstake app token action
   */
  private async executeUnstakeAppToken(
    wallet: AgentWallet,
    action: { appId: string; appAddress: Address; amount: bigint }
  ): Promise<ActionResult> {
    const appState = this.createdApps.get(action.appId);
    if (!appState) {
      return { ok: false, error: `App ${action.appId} not found` };
    }

    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    const factoryAddress = this.deployedAddresses.get('AppFactory');
    if (!factoryAddress) {
      return { ok: false, error: 'AppFactory not deployed' };
    }

    try {
      // Read vault address from factory
      const getVaultAbi = [
        {
          name: 'getApp',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'appId', type: 'uint256' }],
          outputs: [
            { name: 'token', type: 'address' },
            { name: 'vault', type: 'address' },
            { name: 'curve', type: 'address' },
            { name: 'creator', type: 'address' },
          ],
        },
      ] as const;

      const appData = (await this.publicClient.readContract({
        address: factoryAddress,
        abi: getVaultAbi,
        functionName: 'getApp',
        args: [BigInt(appState.id)],
      })) as [Address, Address, Address, Address];

      const vaultAddress = appData[1];

      if (vaultAddress === zeroAddress) {
        return { ok: false, error: 'No staking vault for this app' };
      }

      // Call unstake(amount) on the vault
      const unstakeAbi = [
        {
          name: 'unstake',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'amount', type: 'uint256' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: vaultAddress,
        abi: unstakeAbi,
        functionName: 'unstake',
        args: [action.amount],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Unstake app token failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute claim rewards action (veELTA rewards from RewardsDistributor)
   */
  private async executeClaimRewards(
    wallet: AgentWallet,
    _action: { epoch?: number }
  ): Promise<ActionResult> {
    const rewardsDistributorAddress = this.deployedAddresses.get('RewardsDistributor');

    if (!rewardsDistributorAddress || !this.publicClient) {
      return { ok: false, error: 'RewardsDistributor not deployed' };
    }

    try {
      // Call claimVeFromLast() which automatically claims from user's last claimed epoch
      const claimAbi = [
        {
          name: 'claimVeFromLast',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: rewardsDistributorAddress,
        abi: claimAbi,
        functionName: 'claimVeFromLast',
        args: [],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Claim rewards failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute claim app rewards action (staking rewards from AppRewardsDistributor)
   */
  private async executeClaimAppRewards(
    wallet: AgentWallet,
    action: { appId: string; appAddress: Address }
  ): Promise<ActionResult> {
    const appRewardsDistributorAddress = this.deployedAddresses.get('AppRewardsDistributor');
    const appState = this.createdApps.get(action.appId);

    if (!appRewardsDistributorAddress || !this.publicClient || !appState) {
      return { ok: false, error: 'AppRewardsDistributor not deployed or app not found' };
    }

    const factoryAddress = this.deployedAddresses.get('AppFactory');
    if (!factoryAddress) {
      return { ok: false, error: 'AppFactory not deployed' };
    }

    try {
      // Get vault address from factory
      const getVaultAbi = [
        {
          name: 'getApp',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'appId', type: 'uint256' }],
          outputs: [
            { name: 'token', type: 'address' },
            { name: 'vault', type: 'address' },
            { name: 'curve', type: 'address' },
            { name: 'creator', type: 'address' },
          ],
        },
      ] as const;

      const appData = (await this.publicClient.readContract({
        address: factoryAddress,
        abi: getVaultAbi,
        functionName: 'getApp',
        args: [BigInt(appState.id)],
      })) as [Address, Address, Address, Address];

      const vaultAddress = appData[1];

      if (vaultAddress === zeroAddress) {
        return { ok: false, error: 'No staking vault for this app' };
      }

      // Get total epochs for this vault
      const epochCountAbi = [
        {
          name: 'epochCount',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'vault', type: 'address' }],
          outputs: [{ name: '', type: 'uint256' }],
        },
      ] as const;

      const epochCount = (await this.publicClient.readContract({
        address: appRewardsDistributorAddress,
        abi: epochCountAbi,
        functionName: 'epochCount',
        args: [vaultAddress],
      })) as bigint;

      if (epochCount === 0n) {
        return { ok: true, gasUsed: 0n }; // No epochs to claim
      }

      // Call claim(vault, toEpoch) to claim all available epochs
      const claimAbi = [
        {
          name: 'claim',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'vault', type: 'address' },
            { name: 'toEpoch', type: 'uint256' },
          ],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: appRewardsDistributorAddress,
        abi: claimAbi,
        functionName: 'claim',
        args: [vaultAddress, epochCount],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Claim app rewards failed: ${(error as Error).message}` };
    }
  }

  /**
   * Get Anvil URL
   */
  getAnvilUrl(): string {
    if (!this.anvil) {
      throw new Error('EltaPack not initialized');
    }
    return this.anvil.url;
  }

  /**
   * Get public client
   */
  getPublicClient(): PublicClient {
    if (!this.publicClient) {
      throw new Error('EltaPack not initialized');
    }
    return this.publicClient;
  }

  /**
   * Take a snapshot of current state
   */
  async snapshot(): Promise<string> {
    if (!this.anvil) {
      throw new Error('EltaPack not initialized');
    }
    return anvilRpc.snapshot(this.anvil.url);
  }

  /**
   * Revert to a previous snapshot
   */
  async revert(snapshotId: string): Promise<void> {
    if (!this.anvil) {
      throw new Error('EltaPack not initialized');
    }
    await anvilRpc.revert(this.anvil.url, snapshotId);
    // Refresh state after revert
    this.state = await this.fetchWorldState();
  }

  // ============================================
  // Public Helper Methods for Agents
  // ============================================

  /**
   * Get claimable rewards epochs for an agent from RewardsDistributor
   * Returns the number of epochs available to claim, or 0 if none
   */
  async getClaimableRewardsEpochs(agentId: string): Promise<{
    hasClaimableRewards: boolean;
    lastClaimed: bigint;
    totalEpochs: bigint;
  }> {
    const wallet = this.agentWallets.get(agentId);
    const rewardsDistributorAddress = this.deployedAddresses.get('RewardsDistributor');

    if (!wallet || !rewardsDistributorAddress || !this.publicClient) {
      return { hasClaimableRewards: false, lastClaimed: 0n, totalEpochs: 0n };
    }

    try {
      // Get the current epoch count
      const epochCountAbi = [
        {
          name: 'veEpochCount',
          type: 'function',
          stateMutability: 'view',
          inputs: [],
          outputs: [{ name: '', type: 'uint256' }],
        },
      ] as const;

      const totalEpochs = (await this.publicClient.readContract({
        address: rewardsDistributorAddress,
        abi: epochCountAbi,
        functionName: 'veEpochCount',
      })) as bigint;

      // Get the user's last claimed epoch
      const lastClaimedAbi = [
        {
          name: 'veLastClaimed',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'user', type: 'address' }],
          outputs: [{ name: '', type: 'uint256' }],
        },
      ] as const;

      const lastClaimed = (await this.publicClient.readContract({
        address: rewardsDistributorAddress,
        abi: lastClaimedAbi,
        functionName: 'veLastClaimed',
        args: [wallet.address],
      })) as bigint;

      return {
        hasClaimableRewards: lastClaimed < totalEpochs && totalEpochs > 0n,
        lastClaimed,
        totalEpochs,
      };
    } catch {
      return { hasClaimableRewards: false, lastClaimed: 0n, totalEpochs: 0n };
    }
  }

  /**
   * Get the staked balance for an agent in a specific app's staking vault
   */
  async getAgentStakedBalance(agentId: string, appId: string): Promise<bigint> {
    const wallet = this.agentWallets.get(agentId);
    const appState = this.createdApps.get(appId);
    const factoryAddress = this.deployedAddresses.get('AppFactory');

    if (!wallet || !appState || !factoryAddress || !this.publicClient) {
      return 0n;
    }

    try {
      // Get vault address from factory
      const getVaultAbi = [
        {
          name: 'getApp',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'appId', type: 'uint256' }],
          outputs: [
            { name: 'token', type: 'address' },
            { name: 'vault', type: 'address' },
            { name: 'curve', type: 'address' },
            { name: 'creator', type: 'address' },
          ],
        },
      ] as const;

      const appData = (await this.publicClient.readContract({
        address: factoryAddress,
        abi: getVaultAbi,
        functionName: 'getApp',
        args: [BigInt(appState.id)],
      })) as [Address, Address, Address, Address];

      const vaultAddress = appData[1];
      if (vaultAddress === zeroAddress) {
        return 0n;
      }

      // Query vault for user's staked balance
      const balanceOfAbi = [
        {
          name: 'balanceOf',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'account', type: 'address' }],
          outputs: [{ name: '', type: 'uint256' }],
        },
      ] as const;

      const stakedBalance = (await this.publicClient.readContract({
        address: vaultAddress,
        abi: balanceOfAbi,
        functionName: 'balanceOf',
        args: [wallet.address],
      })) as bigint;

      return stakedBalance;
    } catch {
      return 0n;
    }
  }

  /**
   * Get proposal state from the Governor contract
   * Returns: 0=Pending, 1=Active, 2=Canceled, 3=Defeated, 4=Succeeded, 5=Queued, 6=Expired, 7=Executed
   */
  async getProposalState(proposalId: bigint): Promise<number | null> {
    const governorAddress = this.deployedAddresses.get('ElataGovernor');
    if (!governorAddress || !this.publicClient) {
      return null;
    }

    try {
      const stateAbi = [
        {
          name: 'state',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'proposalId', type: 'uint256' }],
          outputs: [{ name: '', type: 'uint8' }],
        },
      ] as const;

      const state = (await this.publicClient.readContract({
        address: governorAddress,
        abi: stateAbi,
        functionName: 'state',
        args: [proposalId],
      })) as number;

      return state;
    } catch {
      return null;
    }
  }

  /**
   * Check if an agent has already voted on a proposal
   */
  async hasVotedOnProposal(agentId: string, proposalId: bigint): Promise<boolean> {
    const wallet = this.agentWallets.get(agentId);
    const governorAddress = this.deployedAddresses.get('ElataGovernor');

    if (!wallet || !governorAddress || !this.publicClient) {
      return false;
    }

    try {
      const hasVotedAbi = [
        {
          name: 'hasVoted',
          type: 'function',
          stateMutability: 'view',
          inputs: [
            { name: 'proposalId', type: 'uint256' },
            { name: 'account', type: 'address' },
          ],
          outputs: [{ name: '', type: 'bool' }],
        },
      ] as const;

      const hasVoted = (await this.publicClient.readContract({
        address: governorAddress,
        abi: hasVotedAbi,
        functionName: 'hasVoted',
        args: [proposalId, wallet.address],
      })) as boolean;

      return hasVoted;
    } catch {
      return false;
    }
  }

  /**
   * Get app rewards claimable epochs for an agent
   */
  async getAppClaimableEpochs(
    agentId: string,
    appId: string
  ): Promise<{
    hasClaimableRewards: boolean;
    lastClaimed: bigint;
    totalEpochs: bigint;
  }> {
    const wallet = this.agentWallets.get(agentId);
    const appState = this.createdApps.get(appId);
    const factoryAddress = this.deployedAddresses.get('AppFactory');
    const appRewardsDistributorAddress = this.deployedAddresses.get('AppRewardsDistributor');

    if (
      !wallet ||
      !appState ||
      !factoryAddress ||
      !appRewardsDistributorAddress ||
      !this.publicClient
    ) {
      return { hasClaimableRewards: false, lastClaimed: 0n, totalEpochs: 0n };
    }

    try {
      // Get vault address from factory
      const getVaultAbi = [
        {
          name: 'getApp',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'appId', type: 'uint256' }],
          outputs: [
            { name: 'token', type: 'address' },
            { name: 'vault', type: 'address' },
            { name: 'curve', type: 'address' },
            { name: 'creator', type: 'address' },
          ],
        },
      ] as const;

      const appData = (await this.publicClient.readContract({
        address: factoryAddress,
        abi: getVaultAbi,
        functionName: 'getApp',
        args: [BigInt(appState.id)],
      })) as [Address, Address, Address, Address];

      const vaultAddress = appData[1];
      if (vaultAddress === zeroAddress) {
        return { hasClaimableRewards: false, lastClaimed: 0n, totalEpochs: 0n };
      }

      // Get total epochs for this vault
      const epochCountAbi = [
        {
          name: 'epochCount',
          type: 'function',
          stateMutability: 'view',
          inputs: [{ name: 'vault', type: 'address' }],
          outputs: [{ name: '', type: 'uint256' }],
        },
      ] as const;

      const totalEpochs = (await this.publicClient.readContract({
        address: appRewardsDistributorAddress,
        abi: epochCountAbi,
        functionName: 'epochCount',
        args: [vaultAddress],
      })) as bigint;

      // Get user's last claimed epoch for this vault
      const lastClaimedAbi = [
        {
          name: 'lastClaimed',
          type: 'function',
          stateMutability: 'view',
          inputs: [
            { name: 'vault', type: 'address' },
            { name: 'user', type: 'address' },
          ],
          outputs: [{ name: '', type: 'uint256' }],
        },
      ] as const;

      const lastClaimed = (await this.publicClient.readContract({
        address: appRewardsDistributorAddress,
        abi: lastClaimedAbi,
        functionName: 'lastClaimed',
        args: [vaultAddress, wallet.address],
      })) as bigint;

      return {
        hasClaimableRewards: lastClaimed < totalEpochs && totalEpochs > 0n,
        lastClaimed,
        totalEpochs,
      };
    } catch {
      return { hasClaimableRewards: false, lastClaimed: 0n, totalEpochs: 0n };
    }
  }

  /**
   * Activate a bonding curve by advancing time past activation delay and calling activate()
   */
  private async tryActivateBondingCurve(curveAddress: Address, wallet: AgentWallet): Promise<void> {
    if (!this.publicClient || !this.anvil) return;

    try {
      // Get the bonding curve ABI to read activation time
      const curveAbi = this.abis.get('AppBondingCurve');
      if (!curveAbi) {
        console.warn('No AppBondingCurve ABI available for activation');
        return;
      }

      // Get the activation time from the curve
      const activationTime = (await this.publicClient.readContract({
        address: curveAddress,
        abi: curveAbi,
        functionName: 'activationTime',
      })) as bigint;

      // Check current time
      const currentBlock = await this.publicClient.getBlock();
      const currentTime = currentBlock.timestamp;

      // Advance time if needed
      if (currentTime < activationTime) {
        const timeToAdvance = Number(activationTime - currentTime) + 1;
        await anvilRpc.increaseTime(this.anvil.url, timeToAdvance);
        await anvilRpc.mine(this.anvil.url);
      }

      // Now call activate()
      const activateAbi = [
        {
          name: 'activate',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: curveAddress,
        abi: activateAbi,
        functionName: 'activate',
        args: [],
        chain: foundry,
        account: wallet.client.account!,
      });
      await this.publicClient.waitForTransactionReceipt({ hash });

      console.log(`Activated bonding curve at ${curveAddress}`);
    } catch (error) {
      // Activation may fail for other reasons (already active, etc)
      console.warn(`Could not activate curve at ${curveAddress}: ${(error as Error).message}`);
    }
  }

  /**
   * Set FeeCollector on a bonding curve for fee routing
   */
  private async trySetFeeCollector(curveAddress: Address, wallet: AgentWallet): Promise<void> {
    if (!this.publicClient) return;

    const feeCollectorAddress = this.deployedAddresses.get('FeeCollector');
    if (!feeCollectorAddress || feeCollectorAddress === zeroAddress) {
      console.warn('FeeCollector not deployed, skipping setFeeCollector');
      return;
    }

    try {
      const setFeeCollectorAbi = [
        {
          name: 'setFeeCollector',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: '_feeCollector', type: 'address' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: curveAddress,
        abi: setFeeCollectorAbi,
        functionName: 'setFeeCollector',
        args: [feeCollectorAddress],
        chain: foundry,
        account: wallet.client.account!,
      });
      await this.publicClient.waitForTransactionReceipt({ hash });

      console.log(`Set FeeCollector on curve ${curveAddress}`);
    } catch (error) {
      console.warn(`Could not set FeeCollector on curve ${curveAddress}: ${(error as Error).message}`);
    }
  }

  // ============================================
  // Tournament Execute Methods
  // ============================================

  /**
   * Execute enter tournament action
   */
  private async executeEnterTournament(
    wallet: AgentWallet,
    action: { tournamentAddress: Address; entryToken: Address; entryAmount: bigint }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      // First approve the entry token
      const approveAbi = [
        {
          name: 'approve',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'spender', type: 'address' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [{ name: '', type: 'bool' }],
        },
      ] as const;

      const approveHash = await wallet.client.writeContract({
        address: action.entryToken,
        abi: approveAbi,
        functionName: 'approve',
        args: [action.tournamentAddress, action.entryAmount],
        chain: foundry,
        account: wallet.client.account!,
      });
      await this.publicClient.waitForTransactionReceipt({ hash: approveHash });

      // Enter the tournament
      const enterAbi = [
        {
          name: 'enter',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.tournamentAddress,
        abi: enterAbi,
        functionName: 'enter',
        args: [],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Enter tournament failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute claim tournament prize action
   */
  private async executeClaimTournamentPrize(
    wallet: AgentWallet,
    action: { tournamentAddress: Address; proof: `0x${string}`[]; amount: bigint }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      const claimAbi = [
        {
          name: 'claim',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'proof', type: 'bytes32[]' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.tournamentAddress,
        abi: claimAbi,
        functionName: 'claim',
        args: [action.proof, action.amount],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Claim tournament prize failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute create tournament action
   */
  private async executeCreateTournament(
    wallet: AgentWallet,
    action: {
      appId: string;
      entryToken: Address;
      entryFee: bigint;
      startTime: bigint;
      endTime: bigint;
      maxParticipants: bigint;
      prizePoolBps: bigint;
    }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    const tournamentFactoryAddress = this.deployedAddresses.get('TournamentFactory');
    if (!tournamentFactoryAddress) {
      return { ok: false, error: 'TournamentFactory not deployed' };
    }

    try {
      const createAbi = [
        {
          name: 'createTournament',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'appId', type: 'uint256' },
            { name: 'entryToken', type: 'address' },
            { name: 'entryFee', type: 'uint256' },
            { name: 'startTime', type: 'uint256' },
            { name: 'endTime', type: 'uint256' },
            { name: 'maxParticipants', type: 'uint256' },
            { name: 'prizePoolBps', type: 'uint256' },
          ],
          outputs: [{ name: 'tournament', type: 'address' }],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: tournamentFactoryAddress,
        abi: createAbi,
        functionName: 'createTournament',
        args: [
          BigInt(action.appId),
          action.entryToken,
          action.entryFee,
          action.startTime,
          action.endTime,
          action.maxParticipants,
          action.prizePoolBps,
        ],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Create tournament failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute finalize tournament action
   */
  private async executeFinalizeTournament(
    wallet: AgentWallet,
    action: { tournamentAddress: Address; winnersRoot: `0x${string}` }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      const finalizeAbi = [
        {
          name: 'finalize',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'winnersRoot', type: 'bytes32' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.tournamentAddress,
        abi: finalizeAbi,
        functionName: 'finalize',
        args: [action.winnersRoot],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Finalize tournament failed: ${(error as Error).message}` };
    }
  }

  // ============================================
  // Content/NFT Execute Methods
  // ============================================

  /**
   * Execute purchase content action
   */
  private async executePurchaseContent(
    wallet: AgentWallet,
    action: {
      contentStoreAddress: Address;
      contentId: bigint;
      paymentToken: Address;
      maxPrice: bigint;
    }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      // Approve payment token
      const approveAbi = [
        {
          name: 'approve',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'spender', type: 'address' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [{ name: '', type: 'bool' }],
        },
      ] as const;

      const approveHash = await wallet.client.writeContract({
        address: action.paymentToken,
        abi: approveAbi,
        functionName: 'approve',
        args: [action.contentStoreAddress, action.maxPrice],
        chain: foundry,
        account: wallet.client.account!,
      });
      await this.publicClient.waitForTransactionReceipt({ hash: approveHash });

      // Purchase the content
      const purchaseAbi = [
        {
          name: 'purchase',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'contentId', type: 'uint256' }],
          outputs: [{ name: 'tokenId', type: 'uint256' }],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.contentStoreAddress,
        abi: purchaseAbi,
        functionName: 'purchase',
        args: [action.contentId],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Purchase content failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute list content action (operator only)
   */
  private async executeListContent(
    wallet: AgentWallet,
    action: {
      contentStoreAddress: Address;
      contentUri: string;
      price: bigint;
      paymentTokenType: 0 | 1 | 2;
      maxSupply: bigint;
    }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      // Contract uses PaymentTokenType enum: 0=APP, 1=ELTA, 2=USDC
      const listAbi = [
        {
          name: 'listContent',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'uri', type: 'string' },
            { name: 'price', type: 'uint256' },
            { name: 'paymentTokenType', type: 'uint8' },
            { name: 'maxSupply', type: 'uint256' },
          ],
          outputs: [{ name: 'contentId', type: 'uint256' }],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.contentStoreAddress,
        abi: listAbi,
        functionName: 'listContent',
        args: [action.contentUri, action.price, action.paymentTokenType, action.maxSupply],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `List content failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute list content with time window action
   */
  private async executeListContentWithTimeWindow(
    wallet: AgentWallet,
    action: {
      contentStoreAddress: Address;
      contentUri: string;
      price: bigint;
      paymentTokenType: 0 | 1 | 2;
      maxSupply: bigint;
      startTime: bigint;
      endTime: bigint;
    }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      const listAbi = [
        {
          name: 'listContentWithTimeWindow',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'uri', type: 'string' },
            { name: 'price', type: 'uint256' },
            { name: 'paymentTokenType', type: 'uint8' },
            { name: 'maxSupply', type: 'uint256' },
            { name: 'startTime', type: 'uint256' },
            { name: 'endTime', type: 'uint256' },
          ],
          outputs: [{ name: 'contentId', type: 'uint256' }],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.contentStoreAddress,
        abi: listAbi,
        functionName: 'listContentWithTimeWindow',
        args: [
          action.contentUri,
          action.price,
          action.paymentTokenType,
          action.maxSupply,
          action.startTime,
          action.endTime,
        ],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return {
        ok: false,
        error: `List content with time window failed: ${(error as Error).message}`,
      };
    }
  }

  /**
   * Execute deactivate content action
   */
  private async executeDeactivateContent(
    wallet: AgentWallet,
    action: { contentStoreAddress: Address; contentId: bigint }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      const deactivateAbi = [
        {
          name: 'deactivateContent',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'contentId', type: 'uint256' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.contentStoreAddress,
        abi: deactivateAbi,
        functionName: 'deactivateContent',
        args: [action.contentId],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Deactivate content failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute reactivate content action
   */
  private async executeReactivateContent(
    wallet: AgentWallet,
    action: { contentStoreAddress: Address; contentId: bigint }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      const reactivateAbi = [
        {
          name: 'reactivateContent',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'contentId', type: 'uint256' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.contentStoreAddress,
        abi: reactivateAbi,
        functionName: 'reactivateContent',
        args: [action.contentId],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Reactivate content failed: ${(error as Error).message}` };
    }
  }

  // ============================================
  // Governance Execute Methods
  // ============================================

  /**
   * Execute create proposal action
   */
  private async executeCreateProposal(
    wallet: AgentWallet,
    action: {
      targets: Address[];
      values: bigint[];
      calldatas: `0x${string}`[];
      description: string;
    }
  ): Promise<ActionResult> {
    const governorAddress = this.deployedAddresses.get('ElataGovernor');
    if (!governorAddress || !this.publicClient) {
      return { ok: false, error: 'Governor contract not deployed' };
    }

    try {
      const proposeAbi = [
        {
          name: 'propose',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'targets', type: 'address[]' },
            { name: 'values', type: 'uint256[]' },
            { name: 'calldatas', type: 'bytes[]' },
            { name: 'description', type: 'string' },
          ],
          outputs: [{ name: 'proposalId', type: 'uint256' }],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: governorAddress,
        abi: proposeAbi,
        functionName: 'propose',
        args: [action.targets, action.values, action.calldatas, action.description],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Create proposal failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute cast vote action
   */
  private async executeCastVote(
    wallet: AgentWallet,
    action: { proposalId: bigint; support: 0 | 1 | 2; reason?: string }
  ): Promise<ActionResult> {
    const governorAddress = this.deployedAddresses.get('ElataGovernor');
    if (!governorAddress || !this.publicClient) {
      return { ok: false, error: 'Governor contract not deployed' };
    }

    try {
      if (action.reason) {
        const voteWithReasonAbi = [
          {
            name: 'castVoteWithReason',
            type: 'function',
            stateMutability: 'nonpayable',
            inputs: [
              { name: 'proposalId', type: 'uint256' },
              { name: 'support', type: 'uint8' },
              { name: 'reason', type: 'string' },
            ],
            outputs: [{ name: '', type: 'uint256' }],
          },
        ] as const;

        const hash = await wallet.client.writeContract({
          address: governorAddress,
          abi: voteWithReasonAbi,
          functionName: 'castVoteWithReason',
          args: [action.proposalId, action.support, action.reason],
          chain: foundry,
          account: wallet.client.account!,
        });

        const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
        return { ok: true, gasUsed: receipt.gasUsed };
      } else {
        const voteAbi = [
          {
            name: 'castVote',
            type: 'function',
            stateMutability: 'nonpayable',
            inputs: [
              { name: 'proposalId', type: 'uint256' },
              { name: 'support', type: 'uint8' },
            ],
            outputs: [{ name: '', type: 'uint256' }],
          },
        ] as const;

        const hash = await wallet.client.writeContract({
          address: governorAddress,
          abi: voteAbi,
          functionName: 'castVote',
          args: [action.proposalId, action.support],
          chain: foundry,
          account: wallet.client.account!,
        });

        const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
        return { ok: true, gasUsed: receipt.gasUsed };
      }
    } catch (error) {
      return { ok: false, error: `Cast vote failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute queue proposal action
   */
  private async executeQueueProposal(
    wallet: AgentWallet,
    action: { proposalId: bigint }
  ): Promise<ActionResult> {
    const governorAddress = this.deployedAddresses.get('ElataGovernor');
    if (!governorAddress || !this.publicClient) {
      return { ok: false, error: 'Governor contract not deployed' };
    }

    try {
      const queueAbi = [
        {
          name: 'queue',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'proposalId', type: 'uint256' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: governorAddress,
        abi: queueAbi,
        functionName: 'queue',
        args: [action.proposalId],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Queue proposal failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute execute proposal action
   */
  private async executeExecuteProposal(
    wallet: AgentWallet,
    action: { proposalId: bigint }
  ): Promise<ActionResult> {
    const governorAddress = this.deployedAddresses.get('ElataGovernor');
    if (!governorAddress || !this.publicClient) {
      return { ok: false, error: 'Governor contract not deployed' };
    }

    try {
      const executeAbi = [
        {
          name: 'execute',
          type: 'function',
          stateMutability: 'payable',
          inputs: [{ name: 'proposalId', type: 'uint256' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: governorAddress,
        abi: executeAbi,
        functionName: 'execute',
        args: [action.proposalId],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Execute proposal failed: ${(error as Error).message}` };
    }
  }

  // ============================================
  // Fee Pipeline Execute Methods
  // ============================================

  /**
   * Execute sweep fees action
   */
  private async executeSweepFees(
    wallet: AgentWallet,
    action: { curveAddress: Address }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      const sweepAbi = [
        {
          name: 'sweepFees',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.curveAddress,
        abi: sweepAbi,
        functionName: 'sweepFees',
        args: [],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Sweep fees failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute close fee epoch action
   * Calls FeeManager.closeEpoch(appId) to process fees and convert to USDC
   * @param action.appId - The app ID to close epoch for (0 for protocol fees, 1+ for app-specific fees)
   */
  private async executeCloseFeeEpoch(
    wallet: AgentWallet,
    action: { appId: number }
  ): Promise<ActionResult> {
    const feeManagerAddress = this.deployedAddresses.get('FeeManager');
    if (!feeManagerAddress || !this.publicClient) {
      return { ok: false, error: 'FeeManager contract not deployed' };
    }

    try {
      const closeEpochAbi = [
        {
          name: 'closeEpoch',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'appId', type: 'uint256' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: feeManagerAddress,
        abi: closeEpochAbi,
        functionName: 'closeEpoch',
        args: [BigInt(action.appId)],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Close fee epoch failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute sweep ELTA from FeeCollector to FeeManager
   * This is step 2 of the fee pipeline after sweepFees on bonding curves
   */
  private async executeSweepEltaToFeeManager(
    wallet: AgentWallet,
    action: { appId: number }
  ): Promise<ActionResult> {
    const feeCollectorAddress = this.deployedAddresses.get('FeeCollector');
    if (!feeCollectorAddress || !this.publicClient) {
      return { ok: false, error: 'FeeCollector contract not deployed' };
    }

    try {
      const sweepEltaAbi = [
        {
          name: 'sweepElta',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'appId', type: 'uint256' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: feeCollectorAddress,
        abi: sweepEltaAbi,
        functionName: 'sweepElta',
        args: [BigInt(action.appId)],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Sweep ELTA to FeeManager failed: ${(error as Error).message}` };
    }
  }

  // ============================================
  // Referral Execute Methods
  // ============================================

  /**
   * Execute set referrer action
   */
  private async executeSetReferrer(
    wallet: AgentWallet,
    action: { referrer: Address }
  ): Promise<ActionResult> {
    const referralRegistryAddress = this.deployedAddresses.get('ReferralRegistry');
    if (!referralRegistryAddress || !this.publicClient) {
      return { ok: false, error: 'ReferralRegistry contract not deployed' };
    }

    try {
      const setReferrerAbi = [
        {
          name: 'setReferrer',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [{ name: 'referrer', type: 'address' }],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: referralRegistryAddress,
        abi: setReferrerAbi,
        functionName: 'setReferrer',
        args: [action.referrer],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Set referrer failed: ${(error as Error).message}` };
    }
  }

  /**
   * Execute claim referral rewards action
   */
  private async executeClaimReferralRewards(wallet: AgentWallet): Promise<ActionResult> {
    const referralRegistryAddress = this.deployedAddresses.get('ReferralRegistry');
    if (!referralRegistryAddress || !this.publicClient) {
      return { ok: false, error: 'ReferralRegistry contract not deployed' };
    }

    try {
      const claimAbi = [
        {
          name: 'claimRewards',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: referralRegistryAddress,
        abi: claimAbi,
        functionName: 'claimRewards',
        args: [],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Claim referral rewards failed: ${(error as Error).message}` };
    }
  }

  // ============================================
  // Airdrop Execute Methods
  // ============================================

  /**
   * Execute claim airdrop action
   */
  private async executeClaimAirdrop(
    wallet: AgentWallet,
    action: { campaignId: bigint; proof: `0x${string}`[]; amount: bigint }
  ): Promise<ActionResult> {
    const airdropDistributorAddress = this.deployedAddresses.get('AirdropDistributor');
    if (!airdropDistributorAddress || !this.publicClient) {
      return { ok: false, error: 'AirdropDistributor contract not deployed' };
    }

    try {
      const claimAbi = [
        {
          name: 'claim',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'campaignId', type: 'uint256' },
            { name: 'proof', type: 'bytes32[]' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: airdropDistributorAddress,
        abi: claimAbi,
        functionName: 'claim',
        args: [action.campaignId, action.proof, action.amount],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Claim airdrop failed: ${(error as Error).message}` };
    }
  }

  // ============================================
  // XP/Points Execute Methods
  // ============================================

  /**
   * Execute claim XP points action
   */
  private async executeClaimXpPoints(
    wallet: AgentWallet,
    action: { proof: `0x${string}`[]; amount: bigint }
  ): Promise<ActionResult> {
    const elataPointsAddress =
      this.deployedAddresses.get('ElataXP') ?? this.deployedAddresses.get('ElataPoints');
    if (!elataPointsAddress || !this.publicClient) {
      return { ok: false, error: 'ElataPoints contract not deployed' };
    }

    try {
      const claimAbi = [
        {
          name: 'claimPoints',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'proof', type: 'bytes32[]' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: elataPointsAddress,
        abi: claimAbi,
        functionName: 'claimPoints',
        args: [action.proof, action.amount],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Claim XP points failed: ${(error as Error).message}` };
    }
  }

  // ============================================
  // Vesting Execute Methods
  // ============================================

  /**
   * Execute release vested tokens action
   */
  private async executeReleaseVestedTokens(
    wallet: AgentWallet,
    action: { vestingWalletAddress: Address }
  ): Promise<ActionResult> {
    if (!this.publicClient) {
      return { ok: false, error: 'Public client not initialized' };
    }

    try {
      const releaseAbi = [
        {
          name: 'release',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [],
          outputs: [],
        },
      ] as const;

      const hash = await wallet.client.writeContract({
        address: action.vestingWalletAddress,
        abi: releaseAbi,
        functionName: 'release',
        args: [],
        chain: foundry,
        account: wallet.client.account!,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return { ok: true, gasUsed: receipt.gasUsed };
    } catch (error) {
      return { ok: false, error: `Release vested tokens failed: ${(error as Error).message}` };
    }
  }

  /**
   * Parse AppCreated event from transaction logs
   */
  private parseAppCreatedEvent(
    logs: Log[],
    abi: Abi
  ): { appId: bigint; token: Address; curve: Address } | null {
    try {
      for (const log of logs) {
        try {
          const decoded = decodeEventLog({
            abi,
            data: log.data,
            topics: log.topics,
          });

          if (
            decoded.eventName === 'AppCreated' &&
            decoded.args &&
            typeof decoded.args === 'object'
          ) {
            const args = decoded.args as unknown as {
              appId: bigint;
              creator: Address;
              token: Address;
              vault: Address;
              curve: Address;
              vestingWallet: Address;
              ecosystemVault: Address;
              curveShare: bigint;
            };
            if (args.appId !== undefined && args.token && args.curve) {
              return {
                appId: args.appId,
                token: args.token,
                curve: args.curve,
              };
            }
          }
        } catch {
          // This log is not the event we're looking for, continue
          continue;
        }
      }
    } catch (error) {
      console.warn(`Failed to parse AppCreated event: ${(error as Error).message}`);
    }
    return null;
  }

  /**
   * Parse AppGraduated event from transaction logs
   * This event is emitted when a bonding curve reaches its graduation threshold
   */
  private parseAppGraduatedEvent(
    logs: Log[],
    abi: Abi
  ): { appId: bigint; totalRaisedElta: bigint; finalSupply: bigint } | null {
    try {
      for (const log of logs) {
        try {
          const decoded = decodeEventLog({
            abi,
            data: log.data,
            topics: log.topics,
          });

          if (
            decoded.eventName === 'AppGraduated' &&
            decoded.args &&
            typeof decoded.args === 'object'
          ) {
            const args = decoded.args as unknown as {
              appId: bigint;
              totalRaisedElta: bigint;
              finalSupply: bigint;
            };
            if (args.appId !== undefined && args.totalRaisedElta !== undefined) {
              return {
                appId: args.appId,
                totalRaisedElta: args.totalRaisedElta,
                finalSupply: args.finalSupply ?? 0n,
              };
            }
          }
        } catch {
          // This log is not the event we're looking for, continue
          continue;
        }
      }
    } catch (error) {
      console.warn(`Failed to parse AppGraduated event: ${(error as Error).message}`);
    }
    return null;
  }
}

/**
 * Create an EltaPack instance
 */
export function createEltaPack(config: EltaPackConfig): EltaPack {
  return new EltaPack(config);
}
