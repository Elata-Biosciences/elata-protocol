// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppFactory} from "../src/apps/AppFactory.sol";
import {InAppContent721Factory} from "../src/apps/InAppContent721Factory.sol";
import {ContentStoreFactory} from "../src/apps/ContentStoreFactory.sol";
import {TournamentFactory} from "../src/apps/TournamentFactory.sol";
import {ProtocolConfig} from "../src/core/ProtocolConfig.sol";
import {ElataPoints} from "../src/experience/ElataPoints.sol";
import {AppFeeRouter} from "../src/fees/AppFeeRouter.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {FeeSwapper} from "../src/fees/FeeSwapper.sol";
import {AppRegistry} from "../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../src/contributors/ContributorSplitFactory.sol";
import {ElataGovernor} from "../src/governance/ElataGovernor.sol";
import {ElataTimelock} from "../src/governance/ElataTimelock.sol";
import {IAppFeeRouter} from "../src/interfaces/IAppFeeRouter.sol";
import {IAppRewardsDistributor} from "../src/interfaces/IAppRewardsDistributor.sol";
import {IElataPoints} from "../src/interfaces/IElataPoints.sol";
import {IRewardsDistributor} from "../src/interfaces/IRewardsDistributor.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
import {VeELTA} from "../src/staking/VeELTA.sol";
import {ELTA} from "elta/ELTA.sol";
import {NetworkConfig} from "./config/NetworkConfig.sol";
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
 * Environment Variables:
 * - ADMIN_MSIG: Governance multisig address (optional, defaults to deployer)
 * - INITIAL_TREASURY: Treasury address (optional, defaults to ADMIN_MSIG)
 *
 * Network addresses (Uniswap, USDC, WETH) are configured in NetworkConfig.sol
 *
 * NOTE: For local development, use DeployLocal.sol instead which includes
 *       mock USDC, real Uniswap V2, and full fee pipeline setup.
 */
contract Deploy is Script {
    // Configuration - Set via environment variables
    // Defaults to broadcaster if not provided
    address public ADMIN_MSIG = vm.envOr("ADMIN_MSIG", address(0));
    address public INITIAL_TREASURY = vm.envOr("INITIAL_TREASURY", address(0));

    // Governance configuration
    uint256 public constant TIMELOCK_DELAY = 48 hours;

    // Resolved values (set in run()) for reuse in helpers
    address internal _resolvedAdmin;
    address internal _resolvedTreasury;

    struct ProtocolContracts {
        ELTA token;
        ElataPoints xp;
        VeELTA staking;
        AppFeeRouter appFeeRouter;
        TimelockController timelock;
        ElataGovernor governor;
        AppFactory appFactory;
        InAppContent721Factory content721Factory;
        ContentStoreFactory contentStoreFactory;
        TournamentFactory tournamentFactory;
        // Fee Pipeline (only deployed if USDC and Uniswap exist)
        FeeCollector feeCollector;
        FeeSwapper feeSwapper;
        AppRegistry appRegistry;
        ContributorSplitFactory contributorSplitFactory;
        // Additional Modules
        ProtocolConfig protocolConfig;
        // External addresses (from NetworkConfig)
        address uniswapV2Factory;
        address uniswapV2Router;
        address usdc;
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
        address content721Factory,
        address contentStoreFactory,
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
        protocol.token = new ELTA(treasury);
        console2.log("   ELTA deployed at:", address(protocol.token));

        protocol.xp = new ElataPoints(initialAdmin);
        console2.log("   ElataPoints deployed at:", address(protocol.xp));

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

        // ===== STEP 4: Deploy Trading Fee Config =====
        console2.log("\n[4/9] Deploying Trading Fee Config...");
        protocol.appFeeRouter = new AppFeeRouter(protocol.token, initialAdmin);
        console2.log("   AppFeeRouter deployed at:", address(protocol.appFeeRouter));
        console2.log("   Fee rate: 100 bps (1%)");

        // ===== STEP 5: Deploy App Launch Framework =====
        console2.log("\n[5/9] Deploying App Launch Framework...");

        // Get network-specific configuration
        NetworkConfig.Config memory networkConfig = NetworkConfig.get();
        address routerAddress = networkConfig.uniswapV2Router;

        // For local development, use DeployLocal.sol instead
        if (networkConfig.deployMocks) {
            console2.log("   NOTE: For local dev, use DeployLocal.sol which includes full infrastructure");
            console2.log("   Skipping AppFactory (no real Uniswap available)");
        }

        // Store external addresses
        protocol.uniswapV2Router = routerAddress;
        protocol.uniswapV2Factory = networkConfig.uniswapV2Factory;
        protocol.usdc = networkConfig.usdc;

        if (routerAddress != address(0)) {
            console2.log("   Using UniswapV2Router:", routerAddress);
            console2.log("   Using UniswapV2Factory:", networkConfig.uniswapV2Factory);
            // Deploy AppFactory with full parameters
            protocol.appFactory = new AppFactory(
                IERC20(address(protocol.token)),
                IUniswapV2Router02(routerAddress),
                treasury,
                IAppFeeRouter(address(protocol.appFeeRouter)),
                IAppRewardsDistributor(address(0)),
                IRewardsDistributor(address(0)),
                IElataPoints(address(protocol.xp)),
                initialAdmin,
                initialAdmin
            );
            console2.log("   AppFactory deployed at:", address(protocol.appFactory));

            // AppRegistry (governed by timelock, set to the deployed AppFactory)
            protocol.appRegistry = new AppRegistry(address(protocol.timelock), address(protocol.appFactory));
            console2.log("   AppRegistry deployed at:", address(protocol.appRegistry));

            // ContributorSplitFactory (used by AppFactory Phase-A app creation)
            protocol.contributorSplitFactory =
                new ContributorSplitFactory(address(protocol.timelock), address(protocol.appFactory));
            console2.log("   ContributorSplitFactory deployed at:", address(protocol.contributorSplitFactory));
        } else {
            console2.log("   AppFactory skipped (no router configured)");
        }

        // ===== STEP 6: Deploy App Utilities =====
        console2.log("\n[6/9] Deploying App Utilities...");

        // USDC address from NetworkConfig (address(0) for local dev)
        address usdcAddress = networkConfig.usdc;
        address wethAddress = networkConfig.weth;
        if (usdcAddress != address(0)) {
            console2.log("   Using USDC:", usdcAddress);
        }
        if (wethAddress != address(0)) {
            console2.log("   Using WETH:", wethAddress);
        }

        // InAppContent721Factory: Deploys NFT collections for apps
        protocol.content721Factory =
            new InAppContent721Factory(address(protocol.token), address(protocol.appRegistry), initialAdmin, treasury);
        console2.log("   InAppContent721Factory deployed at:", address(protocol.content721Factory));

        // ContentStoreFactory: Deploys sales contracts for apps
        protocol.contentStoreFactory = new ContentStoreFactory(
            address(protocol.token),
            usdcAddress,
            wethAddress,
            address(protocol.appRegistry),
            initialAdmin,
            treasury,
            address(0) // feeSwapper (set after FeeSwapper deployment)
        );
        console2.log("   ContentStoreFactory deployed at:", address(protocol.contentStoreFactory));

        protocol.tournamentFactory = new TournamentFactory(initialAdmin, treasury);
        console2.log("   TournamentFactory deployed at:", address(protocol.tournamentFactory));

        // ===== STEP 7: Deploy Fee Pipeline (if USDC and Uniswap available) =====
        if (usdcAddress != address(0) && routerAddress != address(0)) {
            console2.log("\n[7/9] Deploying Fee Pipeline...");

            // FeeSwapper
            protocol.feeSwapper = new FeeSwapper(
                // Deploy with governance = initialAdmin so we can do one-time setup
                // (e.g. router allowlist) during the deployment tx, then immediately hand
                // governance over to the timelock.
                address(protocol.token),
                initialAdmin,
                initialAdmin,
                treasury,
                address(protocol.appRegistry)
            );
            console2.log("   FeeSwapper deployed at:", address(protocol.feeSwapper));

            // FeeCollector (now with FeeSwapper)
            protocol.feeCollector = new FeeCollector(
                address(protocol.token), initialAdmin, address(protocol.feeSwapper), address(protocol.feeSwapper)
            );
            console2.log("   FeeCollector deployed at:", address(protocol.feeCollector));

            // Authorize Uniswap router in FeeSwapper
            protocol.feeSwapper.setRouterAllowed(routerAddress, true);

            // Hand FeeSwapper governance to the timelock for long-term control.
            protocol.feeSwapper.transferGovernance(address(protocol.timelock));

            // Wire FeeSwapper into ContentStoreFactory for 80/20 routing.
            protocol.contentStoreFactory.setFeeSwapper(address(protocol.feeSwapper));
        } else {
            console2.log("\n[7/9] Fee Pipeline skipped (requires USDC and Uniswap)");
            console2.log("   For local development, use DeployLocal.sol");
        }

        // ===== STEP 7.5: Deploy Additional Modules =====
        console2.log("\n[7.5/9] Deploying Additional Modules...");

        // ProtocolConfig
        protocol.protocolConfig = new ProtocolConfig(initialAdmin, address(protocol.timelock));
        console2.log("   ProtocolConfig deployed at:", address(protocol.protocolConfig));

        // ===== STEP 8: Configure Permissions =====
        console2.log("\n[8/9] Configuring Permissions...");
        _configurePermissions(protocol);
        console2.log("   Permissions configured");

        // ===== STEP 9: Transfer Admin to Multisig =====
        if (initialAdmin != finalAdmin) {
            console2.log("\n[9/9] Transferring Admin to Multisig...");
            _transferAdminToMultisig(protocol, initialAdmin, finalAdmin);
            console2.log("   Admin transferred to:", finalAdmin);
        } else {
            console2.log("\n[9/9] Admin Transfer Skipped (deployer is final admin)");
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
            address(0),
            address(0),
            address(protocol.appFeeRouter),
            address(protocol.governor),
            address(protocol.timelock),
            address(protocol.appFactory),
            address(protocol.content721Factory),
            address(protocol.contentStoreFactory),
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
        if (block.chainid == 31337) protocol.xp.grantRole(protocol.xp.POINTS_OPERATOR_ROLE(), msg.sender);

        // XP: Grant initial operators from env (XP_OPERATOR_1 .. XP_OPERATOR_10)
        for (uint256 i = 1; i <= 10; i++) {
            string memory key = string.concat("XP_OPERATOR_", vm.toString(i));
            address op = vm.envOr(key, address(0));
            if (op != address(0)) protocol.xp.grantRole(protocol.xp.POINTS_OPERATOR_ROLE(), op);
        }

        // No yield distributor roles to configure in the vNext 80/20 fee model.

        // ===== Wire AppFactory with additional modules =====
        if (address(protocol.appFactory) != address(0)) {
            // vNext: canonical app registry + per-app split factory + fee swapper.
            protocol.appFactory.setAppRegistry(address(protocol.appRegistry));
            protocol.appFactory.setContributorSplitFactory(address(protocol.contributorSplitFactory));
            if (address(protocol.feeSwapper) != address(0)) {
                protocol.appFactory.setFeeSwapper(address(protocol.feeSwapper));
            }

            // Wire ProtocolConfig
            if (address(protocol.protocolConfig) != address(0)) {
                protocol.appFactory.setProtocolConfig(address(protocol.protocolConfig));
            }

            // Wire FeeCollector
            if (address(protocol.feeCollector) != address(0)) {
                protocol.appFactory.setFeeCollector(address(protocol.feeCollector));
            }
        }
    }

    /**
     * @dev Transfers admin rights from deployer to multisig
     * @dev Only transfers if multisig is different from deployer (preserves local dev setup)
     */
    function _transferAdminToMultisig(ProtocolContracts memory protocol, address from, address to) internal {
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;

        // ELTA has no admin roles (trustless design)

        // Transfer ElataPoints admin
        protocol.xp.grantRole(DEFAULT_ADMIN_ROLE, to);
        protocol.xp.revokeRole(DEFAULT_ADMIN_ROLE, from);

        // Transfer VeELTA admin
        protocol.staking.grantRole(DEFAULT_ADMIN_ROLE, to);
        protocol.staking.revokeRole(DEFAULT_ADMIN_ROLE, from);

        // Transfer Timelock admin
        protocol.timelock.grantRole(DEFAULT_ADMIN_ROLE, to);
        protocol.timelock.revokeRole(DEFAULT_ADMIN_ROLE, from);

        // Transfer AppFactory admin
        if (address(protocol.appFactory) != address(0)) {
            protocol.appFactory.grantRole(DEFAULT_ADMIN_ROLE, to);
            protocol.appFactory.revokeRole(DEFAULT_ADMIN_ROLE, from);
        }

        // Transfer InAppContent721Factory ownership (uses Ownable, not AccessControl)
        if (address(protocol.content721Factory) != address(0)) {
            protocol.content721Factory.transferOwnership(to);
        }

        // Transfer ContentStoreFactory ownership (uses Ownable, not AccessControl)
        if (address(protocol.contentStoreFactory) != address(0)) {
            protocol.contentStoreFactory.transferOwnership(to);
        }

        // Transfer TournamentFactory ownership (uses Ownable, not AccessControl)
        protocol.tournamentFactory.transferOwnership(to);
    }

    /**
     * @dev Saves deployment addresses to JSON file
     */
    function _saveDeploymentAddresses(ProtocolContracts memory protocol) internal {
        // Build JSON string in parts to avoid stack too deep
        string memory part1 = string.concat(
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
            '    "ElataPoints": "',
            vm.toString(address(protocol.xp)),
            '",\n',
            '    "VeELTA": "',
            vm.toString(address(protocol.staking)),
            '",\n',
            '    "ElataTimelock": "',
            vm.toString(address(protocol.timelock)),
            '",\n',
            '    "ElataGovernor": "',
            vm.toString(address(protocol.governor)),
            '",\n'
        );

        string memory part2 = string.concat(
            '    "AppFactory": "',
            vm.toString(address(protocol.appFactory)),
            '",\n',
            '    "AppRegistry": "',
            vm.toString(address(protocol.appRegistry)),
            '",\n',
            '    "ContributorSplitFactory": "',
            vm.toString(address(protocol.contributorSplitFactory)),
            '",\n',
            '    "InAppContent721Factory": "',
            vm.toString(address(protocol.content721Factory)),
            '",\n',
            '    "ContentStoreFactory": "',
            vm.toString(address(protocol.contentStoreFactory)),
            '",\n',
            '    "TournamentFactory": "',
            vm.toString(address(protocol.tournamentFactory)),
            '",\n',
            '    "AppFeeRouter": "',
            vm.toString(address(protocol.appFeeRouter)),
            '",\n'
        );

        string memory part3 = string.concat(
            '    "FeeCollector": "',
            vm.toString(address(protocol.feeCollector)),
            '",\n',
            '    "FeeSwapper": "',
            vm.toString(address(protocol.feeSwapper)),
            '",\n',
            '    "ProtocolConfig": "',
            vm.toString(address(protocol.protocolConfig)),
            '",\n',
            '    "USDC": "',
            vm.toString(protocol.usdc),
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

        string memory json = string.concat(part1, part2, part3);
        string memory filename = string.concat("./deployments/", _getNetworkName(), "-deployment.json");

        vm.writeFile(filename, json);
        console2.log("   Deployment saved to:", filename);

        // Optional: write an additional, uniquely-named deployment artifact.
        // This is intended for real testnet deployments so fork simulations don't overwrite
        // the artifact your frontend ingests.
        //
        // Set `ELATA_DEPLOYMENT_TAG` to something like `20260219-2359-abc123`.
        string memory tag = vm.envOr("ELATA_DEPLOYMENT_TAG", string(""));
        if (bytes(tag).length != 0) {
            string memory tagged = string.concat("./deployments/", _getNetworkName(), "-", tag, ".json");
            vm.writeFile(tagged, json);
            console2.log("   Deployment saved to:", tagged);
        }

        // Also maintain legacy local path for appstore config script
        if (block.chainid == 31337) {
            vm.writeFile("./deployments/local.json", json);
            console2.log("   Deployment saved to: ./deployments/local.json");
        }
    }

    /**
     * @dev Gets network name from chain ID (delegated to NetworkConfig)
     */
    function _getNetworkName() internal view returns (string memory) {
        return NetworkConfig.getNetworkName();
    }

    /**
     * @dev Logs all deployment addresses for verification
     */
    function _logDeployment(ProtocolContracts memory protocol) internal pure {
        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("\nCore Protocol:");
        console2.log("  ELTA Token:              ", address(protocol.token));
        console2.log("  ElataPoints:             ", address(protocol.xp));
        console2.log("  VeELTA Staking:          ", address(protocol.staking));
        console2.log("  Governor:                ", address(protocol.governor));
        console2.log("  Timelock:                ", address(protocol.timelock));
        console2.log("  AppFeeRouter:            ", address(protocol.appFeeRouter));
        console2.log("\nApp Framework:");
        console2.log("  AppFactory:              ", address(protocol.appFactory));
        console2.log("  InAppContent721Factory:  ", address(protocol.content721Factory));
        console2.log("  ContentStoreFactory:     ", address(protocol.contentStoreFactory));
        console2.log("  TournamentFactory:       ", address(protocol.tournamentFactory));
        console2.log("\nFee Pipeline:");
        console2.log("  FeeCollector:            ", address(protocol.feeCollector));
        console2.log("  FeeSwapper:              ", address(protocol.feeSwapper));
        console2.log("\nAdditional Modules:");
        console2.log("  ProtocolConfig:          ", address(protocol.protocolConfig));
        console2.log("================================");

        // Next steps
        console2.log("\n=== NEXT STEPS ===");
        console2.log("1. Verify contracts on block explorer");
        console2.log("2. Test end-to-end on testnet");
        console2.log("3. Update appstore env/ABIs with contract addresses");
        console2.log("4. Grant additional roles as needed");
        console2.log("==================");
    }
}
