// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppFactory} from "../src/apps/AppFactory.sol";
import {AppModuleFactory} from "../src/apps/AppModuleFactory.sol";
import {TournamentFactory} from "../src/apps/TournamentFactory.sol";
import {ElataXP} from "../src/experience/ElataXP.sol";
import {AppFeeRouter} from "../src/fees/AppFeeRouter.sol";
import {ElataGovernor} from "../src/governance/ElataGovernor.sol";
import {ElataTimelock} from "../src/governance/ElataTimelock.sol";
import {IAppFeeRouter} from "../src/interfaces/IAppFeeRouter.sol";
import {IAppRewardsDistributor} from "../src/interfaces/IAppRewardsDistributor.sol";
import {IElataXP} from "../src/interfaces/IElataXP.sol";
import {IRewardsDistributor} from "../src/interfaces/IRewardsDistributor.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
import {IVeEltaVotes} from "../src/interfaces/IVeEltaVotes.sol";
import {AppRewardsDistributor} from "../src/rewards/AppRewardsDistributor.sol";
import {RewardsDistributor} from "../src/rewards/RewardsDistributor.sol";
import {VeELTA} from "../src/staking/VeELTA.sol";
import {ELTA} from "../src/token/ELTA.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Script.sol";

/**
 * @title Deploy
 * @notice Complete deployment script for Elata Protocol with Economic Upgrade V2
 * @dev Deploys the entire protocol with new rewards architecture in correct order
 *
 * Deployment Order:
 * 1. Core Tokens (ELTA, XP)
 * 2. VeELTA (ERC20Votes)
 * 3. Governance (Governor, Timelock)
 * 4. Rewards Architecture (AppRewardsDistributor, RewardsDistributor, AppFeeRouter)
 * 5. App Launch (AppFactory with auto-stake)
 * 6. Utilities (AppModuleFactory, TournamentFactory)
 * 7. Permissions & Configuration
 *
 * Environment Variables Required:
 * - ADMIN_MSIG: Governance multisig address
 * - INITIAL_TREASURY: Treasury address
 * - UNISWAP_V2_ROUTER: Uniswap router address (network-specific)
 */
// Minimal local mocks (used when deploying to Anvil without a router)
contract MockUniswapV2Router {
    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }
}

contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        pair = address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB, block.timestamp)))));
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        allPairs.push(pair);
        return pair;
    }
}

contract Deploy is Script {
    // Configuration - Set via environment variables
    // Defaults to broadcaster if not provided
    address public ADMIN_MSIG = vm.envOr("ADMIN_MSIG", address(0));
    address public INITIAL_TREASURY = vm.envOr("INITIAL_TREASURY", address(0));

    // Token configuration
    uint256 public constant INITIAL_MINT = 10_000_000 ether; // 10M ELTA initial
    uint256 public constant MAX_SUPPLY = 77_000_000 ether; // 77M ELTA total cap

    // Governance configuration
    uint256 public constant TIMELOCK_DELAY = 48 hours;

    // Resolved values (set in run()) for reuse in helpers
    address internal _resolvedAdmin;
    address internal _resolvedTreasury;

    struct ProtocolContracts {
        ELTA token;
        ElataXP xp;
        VeELTA staking;
        AppRewardsDistributor appRewardsDistributor;
        RewardsDistributor rewards;
        AppFeeRouter appFeeRouter;
        TimelockController timelock;
        ElataGovernor governor;
        AppFactory appFactory;
        AppModuleFactory appModuleFactory;
        TournamentFactory tournamentFactory;
        address uniswapV2Factory;
        address uniswapV2Router;
    }

    event ProtocolDeployed(
        address indexed token,
        address indexed staking,
        address indexed xp,
        address appRewardsDistributor,
        address rewards,
        address appFeeRouter,
        address governor,
        address timelock,
        address appFactory,
        address appModuleFactory,
        address tournamentFactory
    );

    function run() external returns (ProtocolContracts memory protocol) {
        vm.startBroadcast();

        // Initial admin is always the deployer (for permission configuration)
        // Final admin (multisig) is set after configuration
        address initialAdmin = msg.sender;
        address finalAdmin = ADMIN_MSIG != address(0) ? ADMIN_MSIG : msg.sender;
        address treasury = INITIAL_TREASURY != address(0) ? INITIAL_TREASURY : finalAdmin;

        _resolvedAdmin = finalAdmin; // Store final admin for transfer
        _resolvedTreasury = treasury;

        console2.log("=== ELATA PROTOCOL DEPLOYMENT ===");
        console2.log("Deployer:", initialAdmin);
        console2.log("Final Admin:", finalAdmin);
        console2.log("Treasury:", treasury);
        console2.log("Network:", block.chainid);
        console2.log("=====================================\n");

        // ===== STEP 1: Deploy Core Tokens =====
        console2.log("[1/9] Deploying Core Tokens...");
        protocol.token = new ELTA("ELTA", "ELTA", initialAdmin, treasury, INITIAL_MINT, MAX_SUPPLY);
        console2.log("   ELTA deployed at:", address(protocol.token));

        protocol.xp = new ElataXP(initialAdmin);
        console2.log("   ElataXP deployed at:", address(protocol.xp));

        // ===== STEP 2: Deploy VeELTA (ERC20Votes) =====
        console2.log("\n[2/9] Deploying VeELTA (ERC20Votes)...");
        protocol.staking = new VeELTA(protocol.token, initialAdmin);
        console2.log("   VeELTA deployed at:", address(protocol.staking));

        // ===== STEP 3: Deploy Governance =====
        console2.log("\n[3/8] Deploying Governance...");
        protocol.timelock = _deployTimelock();
        console2.log("   Timelock deployed at:", address(protocol.timelock));

        // Governor uses veELTA for voting power (IVotes interface)
        protocol.governor = new ElataGovernor(IVotes(address(protocol.staking)), address(protocol.timelock));
        console2.log("   Governor deployed at:", address(protocol.governor));

        // ===== STEP 4: Deploy Rewards Architecture (Economic Upgrade V2) =====
        console2.log("\n[4/8] Deploying Rewards Architecture (70/15/15)...");

        // 5a. AppRewardsDistributor (receives 70% for app stakers)
        // AppRewardsDistributor requires a non-zero factory in constructor.
        // Use initialAdmin as initial factory; grant FACTORY_ROLE to AppFactory after it is deployed.
        protocol.appRewardsDistributor = new AppRewardsDistributor(protocol.token, initialAdmin, initialAdmin);
        console2.log("   AppRewardsDistributor deployed at:", address(protocol.appRewardsDistributor));

        // 5b. RewardsDistributor (central hub with 70/15/15 split)
        protocol.rewards = new RewardsDistributor(
            protocol.token,
            IVeEltaVotes(address(protocol.staking)),
            IAppRewardsDistributor(address(protocol.appRewardsDistributor)),
            treasury,
            initialAdmin
        );
        console2.log("   RewardsDistributor deployed at:", address(protocol.rewards));
        console2.log("   - 70% to app stakers");
        console2.log("   - 15% to veELTA stakers");
        console2.log("   - 15% to treasury");

        // 5c. AppFeeRouter (collects trading fees)
        protocol.appFeeRouter =
            new AppFeeRouter(protocol.token, IRewardsDistributor(address(protocol.rewards)), initialAdmin);
        console2.log("   AppFeeRouter deployed at:", address(protocol.appFeeRouter));
        console2.log("   Fee rate: 100 bps (1%)");

        // ===== STEP 5: Deploy App Launch Framework =====
        console2.log("\n[5/8] Deploying App Launch Framework...");

        address routerAddress = vm.envOr("UNISWAP_V2_ROUTER", address(0));

        // Auto-provision a mock router if none provided
        // Deploy mock for: Anvil (31337) and Base Sepolia (84532)
        bool isTestnet = block.chainid == 31337 || block.chainid == 84532;

        if (isTestnet && routerAddress == address(0)) {
            MockUniswapV2Factory mockFactory = new MockUniswapV2Factory();
            MockUniswapV2Router mockRouter = new MockUniswapV2Router(address(mockFactory));
            routerAddress = address(mockRouter);
            protocol.uniswapV2Factory = address(mockFactory);
            protocol.uniswapV2Router = routerAddress;
            console2.log("   Deployed MockUniswapV2Factory:", address(mockFactory));
            console2.log("   Deployed MockUniswapV2Router:", routerAddress);
        } else {
            protocol.uniswapV2Router = routerAddress;
        }

        // For mainnet deployments, require explicit router
        if (!isTestnet && routerAddress == address(0)) {
            revert("UNISWAP_V2_ROUTER not set for this network - mainnet requires explicit router");
        }

        if (routerAddress != address(0)) {
            // Deploy AppFactory with full parameters
            protocol.appFactory = new AppFactory(
                IERC20(address(protocol.token)),
                IUniswapV2Router02(routerAddress),
                treasury,
                IAppFeeRouter(address(protocol.appFeeRouter)),
                IAppRewardsDistributor(address(protocol.appRewardsDistributor)),
                IRewardsDistributor(address(protocol.rewards)),
                IElataXP(address(protocol.xp)),
                initialAdmin,
                initialAdmin
            );
            console2.log("   AppFactory deployed at:", address(protocol.appFactory));
        } else {
            console2.log("   AppFactory skipped (no router configured)");
        }

        // ===== STEP 6: Deploy App Utilities =====
        console2.log("\n[6/8] Deploying App Utilities...");

        // AppModuleFactory: Now only deploys AppAccess1155 (vault already created by AppFactory)
        protocol.appModuleFactory = new AppModuleFactory(address(protocol.token), initialAdmin, treasury);
        console2.log("   AppModuleFactory deployed at:", address(protocol.appModuleFactory));

        protocol.tournamentFactory = new TournamentFactory(initialAdmin, treasury);
        console2.log("   TournamentFactory deployed at:", address(protocol.tournamentFactory));

        // ===== STEP 7: Configure Permissions =====
        console2.log("\n[7/8] Configuring Permissions...");
        _configurePermissions(protocol);
        console2.log("   Permissions configured");

        // ===== STEP 8: Transfer Admin to Multisig =====
        if (initialAdmin != finalAdmin) {
            console2.log("\n[8/8] Transferring Admin to Multisig...");
            _transferAdminToMultisig(protocol, initialAdmin, finalAdmin);
            console2.log("   Admin transferred to:", finalAdmin);
        } else {
            console2.log("\n[8/8] Admin Transfer Skipped (deployer is final admin)");
        }

        // ===== Save Deployment Addresses =====
        console2.log("\nSaving Deployment Addresses...");
        _saveDeploymentAddresses(protocol);

        // Log completion
        _logDeployment(protocol);

        // Emit deployment event
        emit ProtocolDeployed(
            address(protocol.token),
            address(protocol.staking),
            address(protocol.xp),
            address(protocol.appRewardsDistributor),
            address(protocol.rewards),
            address(protocol.appFeeRouter),
            address(protocol.governor),
            address(protocol.timelock),
            address(protocol.appFactory),
            address(protocol.appModuleFactory),
            address(protocol.tournamentFactory)
        );

        vm.stopBroadcast();
    }

    /**
     * @dev Deploys timelock controller with standard configuration
     */
    function _deployTimelock() internal returns (TimelockController) {
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Will be set to governor after deployment

        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        // Deploy with msg.sender (deployer) as initial admin
        // Will be transferred to multisig later
        return new ElataTimelock(TIMELOCK_DELAY, proposers, executors, msg.sender);
    }

    /**
     * @dev Configures initial permissions and roles
     */
    function _configurePermissions(ProtocolContracts memory protocol) internal {
        // Governance: Grant proposer/executor roles to governor
        protocol.timelock.grantRole(protocol.timelock.PROPOSER_ROLE(), address(protocol.governor));
        protocol.timelock.grantRole(protocol.timelock.EXECUTOR_ROLE(), address(protocol.governor));

        // XP: For local development, grant operator role to deployer for seeding
        if (block.chainid == 31337) protocol.xp.grantRole(protocol.xp.XP_OPERATOR_ROLE(), msg.sender);

        // XP: Grant initial operators from env (XP_OPERATOR_1 .. XP_OPERATOR_10)
        for (uint256 i = 1; i <= 10; i++) {
            string memory key = string.concat("XP_OPERATOR_", vm.toString(i));
            address op = vm.envOr(key, address(0));
            if (op != address(0)) protocol.xp.grantRole(protocol.xp.XP_OPERATOR_ROLE(), op);
        }

        // Rewards: Grant DISTRIBUTOR_ROLE to AppFeeRouter
        protocol.rewards.grantRole(protocol.rewards.DISTRIBUTOR_ROLE(), address(protocol.appFeeRouter));

        // AppRewards: Grant FACTORY_ROLE to AppFactory
        if (address(protocol.appFactory) != address(0)) {
            protocol.appRewardsDistributor
                .grantRole(protocol.appRewardsDistributor.FACTORY_ROLE(), address(protocol.appFactory));
        }
    }

    /**
     * @dev Transfers admin rights from deployer to multisig
     * @dev Only transfers if multisig is different from deployer (preserves local dev setup)
     */
    function _transferAdminToMultisig(ProtocolContracts memory protocol, address from, address to) internal {
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;

        // Transfer ELTA admin
        protocol.token.grantRole(DEFAULT_ADMIN_ROLE, to);
        protocol.token.revokeRole(DEFAULT_ADMIN_ROLE, from);

        // Transfer ElataXP admin
        protocol.xp.grantRole(DEFAULT_ADMIN_ROLE, to);
        protocol.xp.revokeRole(DEFAULT_ADMIN_ROLE, from);

        // Transfer VeELTA admin
        protocol.staking.grantRole(DEFAULT_ADMIN_ROLE, to);
        protocol.staking.revokeRole(DEFAULT_ADMIN_ROLE, from);

        // Transfer RewardsDistributor admin
        protocol.rewards.grantRole(DEFAULT_ADMIN_ROLE, to);
        protocol.rewards.revokeRole(DEFAULT_ADMIN_ROLE, from);

        // Transfer AppRewardsDistributor admin
        protocol.appRewardsDistributor.grantRole(DEFAULT_ADMIN_ROLE, to);
        protocol.appRewardsDistributor.revokeRole(DEFAULT_ADMIN_ROLE, from);

        // Transfer Timelock admin
        protocol.timelock.grantRole(DEFAULT_ADMIN_ROLE, to);
        protocol.timelock.revokeRole(DEFAULT_ADMIN_ROLE, from);

        // Transfer AppFactory admin
        if (address(protocol.appFactory) != address(0)) {
            protocol.appFactory.grantRole(DEFAULT_ADMIN_ROLE, to);
            protocol.appFactory.revokeRole(DEFAULT_ADMIN_ROLE, from);
        }

        // Transfer AppModuleFactory ownership (uses Ownable, not AccessControl)
        if (address(protocol.appModuleFactory) != address(0)) {
            protocol.appModuleFactory.transferOwnership(to);
        }

        // Transfer TournamentFactory ownership (uses Ownable, not AccessControl)
        protocol.tournamentFactory.transferOwnership(to);
    }

    /**
     * @dev Saves deployment addresses to JSON file
     */
    function _saveDeploymentAddresses(ProtocolContracts memory protocol) internal {
        // Build JSON string (match structure used by local deploy for appstore tooling)
        string memory json = string.concat(
            "{\n",
            '  "network": "',
            _getNetworkName(),
            '",\n',
            '  "chainId": ',
            vm.toString(block.chainid),
            ",\n",
            '  "deployer": "',
            vm.toString(_resolvedAdmin),
            '",\n',
            '  "contracts": {\n',
            '    "ELTA": "',
            vm.toString(address(protocol.token)),
            '",\n',
            '    "ElataXP": "',
            vm.toString(address(protocol.xp)),
            '",\n',
            '    "VeELTA": "',
            vm.toString(address(protocol.staking)),
            '",\n',
            '    "RewardsDistributor": "',
            vm.toString(address(protocol.rewards)),
            '",\n',
            '    "ElataTimelock": "',
            vm.toString(address(protocol.timelock)),
            '",\n',
            '    "ElataGovernor": "',
            vm.toString(address(protocol.governor)),
            '",\n',
            '    "AppFactory": "',
            vm.toString(address(protocol.appFactory)),
            '",\n',
            '    "AppModuleFactory": "',
            vm.toString(address(protocol.appModuleFactory)),
            '",\n',
            '    "TournamentFactory": "',
            vm.toString(address(protocol.tournamentFactory)),
            '",\n',
            '    "AppRewardsDistributor": "',
            vm.toString(address(protocol.appRewardsDistributor)),
            '",\n',
            '    "AppFeeRouter": "',
            vm.toString(address(protocol.appFeeRouter)),
            '",\n',
            '    "UniswapV2Factory": "',
            vm.toString(protocol.uniswapV2Factory),
            '",\n',
            '    "UniswapV2Router": "',
            vm.toString(protocol.uniswapV2Router),
            '"\n',
            "  }\n",
            "}\n"
        );

        string memory filename = string.concat("./deployments/", _getNetworkName(), "-deployment.json");

        vm.writeFile(filename, json);
        console2.log("   Deployment saved to:", filename);

        // Also maintain legacy local path for appstore config script
        if (block.chainid == 31337) {
            vm.writeFile("./deployments/local.json", json);
            console2.log("   Deployment saved to: ./deployments/local.json");
        }
    }

    /**
     * @dev Gets network name from chain ID
     */
    function _getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;

        if (chainId == 1) return "mainnet";
        if (chainId == 5) return "goerli";
        if (chainId == 11155111) return "sepolia";
        if (chainId == 8453) return "base";
        if (chainId == 84531) return "base-goerli";
        if (chainId == 84532) return "base-sepolia";
        if (chainId == 31337) return "localhost";

        return "unknown";
    }

    /**
     * @dev Logs all deployment addresses for verification
     */
    function _logDeployment(ProtocolContracts memory protocol) internal view {
        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("ELTA Token:              ", address(protocol.token));
        console2.log("ElataXP:                 ", address(protocol.xp));
        console2.log("VeELTA Staking:          ", address(protocol.staking));
        console2.log("AppRewardsDistributor:   ", address(protocol.appRewardsDistributor));
        console2.log("RewardsDistributor:      ", address(protocol.rewards));
        console2.log("AppFeeRouter:            ", address(protocol.appFeeRouter));
        console2.log("Governor:                ", address(protocol.governor));
        console2.log("Timelock:                ", address(protocol.timelock));
        console2.log("App Factory:             ", address(protocol.appFactory));
        console2.log("App Module Factory:      ", address(protocol.appModuleFactory));
        console2.log("Tournament Factory:      ", address(protocol.tournamentFactory));
        console2.log("================================");

        // Next steps
        console2.log("\n=== NEXT STEPS ===");
        console2.log("1. Verify contracts on block explorer");
        console2.log("2. Test end-to-end on testnet");
        console2.log(
            "3. Update appstore env/ABIs with contract addresses (npm run dev:config, then npm run sync-abi in elata-appstore)"
        );
        console2.log("4. Grant additional roles as needed");
        console2.log("==================");
    }
}
