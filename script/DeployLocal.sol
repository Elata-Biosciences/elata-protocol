// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DeployLocal
 * @notice Complete local deployment for Elata Protocol with full fee pipeline
 * @dev Deploys everything needed for simulation and local development:
 *      - Mock USDC and WETH
 *      - Real Uniswap V2 (Factory, Router, Pair)
 *      - Full Elata protocol (ELTA, VeELTA, AppFactory, etc.)
 *      - Complete fee pipeline (FeeCollector, FeeManager, TreasuryUSDCVault)
 *      - ELTA/USDC liquidity pool
 *
 * Usage:
 *   forge script script/DeployLocal.sol:DeployLocal --rpc-url http://127.0.0.1:8545 --broadcast
 */

import {Script, console2} from "forge-std/Script.sol";

// Core protocol
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../src/staking/VeELTA.sol";
import {ElataPoints} from "../src/experience/ElataPoints.sol";
import {ElataGovernor} from "../src/governance/ElataGovernor.sol";
import {ElataTimelock} from "../src/governance/ElataTimelock.sol";
import {AppFactory} from "../src/apps/AppFactory.sol";
import {InAppContent721Factory} from "../src/apps/InAppContent721Factory.sol";
import {ContentStoreFactory} from "../src/apps/ContentStoreFactory.sol";
import {TournamentFactory} from "../src/apps/TournamentFactory.sol";

// Trading fee config (no yield distribution)
import {AppFeeRouter} from "../src/fees/AppFeeRouter.sol";

// Fee Pipeline
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {FeeSwapper} from "../src/fees/FeeSwapper.sol";
import {AppRegistry} from "../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../src/contributors/ContributorSplitFactory.sol";

// Additional Modules
import {ProtocolConfig} from "../src/core/ProtocolConfig.sol";

// Mocks
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

// External (Uniswap V2)
import {UniswapV2Factory} from "./external/UniswapV2Factory.sol";
import {UniswapV2Router} from "./external/UniswapV2Router.sol";

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
import {IAppFeeRouter} from "../src/interfaces/IAppFeeRouter.sol";
import {IAppRewardsDistributor} from "../src/interfaces/IAppRewardsDistributor.sol";
import {IRewardsDistributor} from "../src/interfaces/IRewardsDistributor.sol";
import {IElataPoints} from "../src/interfaces/IElataPoints.sol";

contract DeployLocal is Script {
    // Configuration
    uint256 public constant TIMELOCK_DELAY = 1 hours; // Shorter for local testing
    uint256 public constant INITIAL_LIQUIDITY_ELTA = 10_000_000 ether; // 10M ELTA
    uint256 public constant INITIAL_LIQUIDITY_USDC = 1_000_000e6; // 1M USDC ($0.10/ELTA)
    uint256 public constant FEE_EPOCH_LENGTH = 1 hours; // Short epoch for testing

    struct LocalContracts {
        // Core Protocol
        ELTA elta;
        VeELTA veElta;
        ElataPoints xp;
        ElataGovernor governor;
        TimelockController timelock;
        AppFactory appFactory;
        InAppContent721Factory content721Factory;
        ContentStoreFactory contentStoreFactory;
        TournamentFactory tournamentFactory;
        // Trading fee config
        AppFeeRouter appFeeRouter;
        // Fee Pipeline
        FeeCollector feeCollector;
        FeeSwapper feeSwapper;
        AppRegistry appRegistry;
        ContributorSplitFactory contributorSplitFactory;
        // Additional Modules
        ProtocolConfig protocolConfig;
        // External Mocks
        MockUSDC usdc;
        MockWETH weth;
        UniswapV2Factory uniswapFactory;
        UniswapV2Router uniswapRouter;
        address eltaUsdcPair;
    }

    function run() external returns (LocalContracts memory contracts) {
        vm.startBroadcast();

        address deployer = msg.sender;
        address treasury = deployer; // Use deployer as treasury for local

        console2.log("=== ELATA LOCAL DEPLOYMENT ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("==============================\n");

        // ===== PHASE 1: Deploy Mocks =====
        console2.log("[1/8] Deploying Mock Tokens...");
        contracts.usdc = new MockUSDC();
        contracts.weth = new MockWETH();
        console2.log("   MockUSDC:", address(contracts.usdc));
        console2.log("   MockWETH:", address(contracts.weth));

        // ===== PHASE 2: Deploy Uniswap V2 =====
        console2.log("\n[2/8] Deploying Uniswap V2...");
        contracts.uniswapFactory = new UniswapV2Factory(deployer);
        contracts.uniswapRouter = new UniswapV2Router(address(contracts.uniswapFactory), address(contracts.weth));
        console2.log("   UniswapV2Factory:", address(contracts.uniswapFactory));
        console2.log("   UniswapV2Router:", address(contracts.uniswapRouter));

        // ===== PHASE 3: Deploy Core Protocol =====
        console2.log("\n[3/8] Deploying Core Protocol...");

        // ELTA Token
        contracts.elta = new ELTA(treasury);
        console2.log("   ELTA:", address(contracts.elta));

        // ElataPoints (XP)
        contracts.xp = new ElataPoints(deployer);
        console2.log("   ElataPoints:", address(contracts.xp));

        // VeELTA
        contracts.veElta = new VeELTA(contracts.elta, deployer);
        console2.log("   VeELTA:", address(contracts.veElta));

        // ===== PHASE 4: Deploy Governance =====
        console2.log("\n[4/8] Deploying Governance...");
        contracts.timelock = _deployTimelock(deployer);
        contracts.governor = new ElataGovernor(IVotes(address(contracts.veElta)), address(contracts.timelock));
        console2.log("   Timelock:", address(contracts.timelock));
        console2.log("   Governor:", address(contracts.governor));

        // ===== PHASE 5: Deploy Trading Fee Config =====
        console2.log("\n[5/8] Deploying Trading Fee Config...");

        // AppFeeRouter is now only a global feeBps source of truth (no yield distribution).
        contracts.appFeeRouter = new AppFeeRouter(contracts.elta, deployer);
        console2.log("   AppFeeRouter:", address(contracts.appFeeRouter));

        // ===== PHASE 6: Deploy App Framework =====
        console2.log("\n[6/8] Deploying App Framework...");

        // AppFactory
        contracts.appFactory = new AppFactory(
            IERC20(address(contracts.elta)),
            IUniswapV2Router02(address(contracts.uniswapRouter)),
            treasury,
            IAppFeeRouter(address(contracts.appFeeRouter)),
            IAppRewardsDistributor(address(0)),
            IRewardsDistributor(address(0)),
            IElataPoints(address(contracts.xp)),
            deployer,
            deployer
        );
        console2.log("   AppFactory:", address(contracts.appFactory));

        // AppRegistry (use deployer as governance for local testing)
        contracts.appRegistry = new AppRegistry(deployer, address(contracts.appFactory));
        console2.log("   AppRegistry:", address(contracts.appRegistry));

        // ContributorSplitFactory (required for Phase-A tokenless app creation)
        contracts.contributorSplitFactory = new ContributorSplitFactory(deployer, address(contracts.appFactory));
        console2.log("   ContributorSplitFactory:", address(contracts.contributorSplitFactory));

        // InAppContent721Factory
        contracts.content721Factory =
            new InAppContent721Factory(address(contracts.elta), address(contracts.appRegistry), deployer, treasury);
        console2.log("   InAppContent721Factory:", address(contracts.content721Factory));

        // ContentStoreFactory
        contracts.contentStoreFactory = new ContentStoreFactory(
            address(contracts.elta),
            address(contracts.usdc),
            address(contracts.weth),
            address(contracts.appRegistry),
            deployer,
            treasury,
            address(0) // feeSwapper set after FeeSwapper deploy
        );
        console2.log("   ContentStoreFactory:", address(contracts.contentStoreFactory));

        // TournamentFactory
        contracts.tournamentFactory = new TournamentFactory(deployer, treasury);
        console2.log("   TournamentFactory:", address(contracts.tournamentFactory));

        // ===== PHASE 7: Deploy Fee Pipeline =====
        console2.log("\n[7/8] Deploying Fee Pipeline...");

        // FeeSwapper (use deployer as governance for local so we can configure immediately)
        contracts.feeSwapper = new FeeSwapper(
            address(contracts.elta),
            deployer,
            deployer, // Use deployer as governance for local testing
            treasury,
            address(contracts.appRegistry)
        );
        console2.log("   FeeSwapper:", address(contracts.feeSwapper));

        // FeeCollector (now with FeeSwapper)
        contracts.feeCollector = new FeeCollector(
            address(contracts.elta), deployer, address(contracts.feeSwapper), address(contracts.feeSwapper)
        );
        console2.log("   FeeCollector:", address(contracts.feeCollector));

        // Authorize Uniswap router in FeeSwapper
        contracts.feeSwapper.setRouterAllowed(address(contracts.uniswapRouter), true);

        // Wire FeeSwapper into ContentStoreFactory for 80/20 routing.
        contracts.contentStoreFactory.setFeeSwapper(address(contracts.feeSwapper));

        // ===== PHASE 7.5: Deploy Additional Modules =====
        console2.log("\n[7.5/8] Deploying Additional Modules...");

        // ProtocolConfig
        contracts.protocolConfig = new ProtocolConfig(deployer, address(contracts.timelock));
        console2.log("   ProtocolConfig:", address(contracts.protocolConfig));

        // ===== PHASE 8: Setup Liquidity & Permissions =====
        console2.log("\n[8/8] Setting up Liquidity & Permissions...");

        // Create ELTA/USDC pair and add liquidity
        contracts.eltaUsdcPair = _setupLiquidity(contracts, deployer);
        console2.log("   ELTA/USDC Pair:", contracts.eltaUsdcPair);
        console2.log("   Initial price: $0.10/ELTA");

        // Configure permissions
        _configurePermissions(contracts);
        console2.log("   Permissions configured");

        // Save deployment addresses
        _saveDeploymentAddresses(contracts, deployer);

        // Log summary
        _logDeployment(contracts);

        vm.stopBroadcast();
    }

    function _deployTimelock(address admin) internal returns (TimelockController) {
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Will be set to governor
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute
        return new ElataTimelock(TIMELOCK_DELAY, proposers, executors, admin);
    }

    function _setupLiquidity(LocalContracts memory contracts, address deployer) internal returns (address pair) {
        // Mint USDC for liquidity
        contracts.usdc.mint(deployer, INITIAL_LIQUIDITY_USDC);

        // Approve router
        contracts.elta.approve(address(contracts.uniswapRouter), INITIAL_LIQUIDITY_ELTA);
        contracts.usdc.approve(address(contracts.uniswapRouter), INITIAL_LIQUIDITY_USDC);

        // Add liquidity
        contracts.uniswapRouter
            .addLiquidity(
                address(contracts.elta),
                address(contracts.usdc),
                INITIAL_LIQUIDITY_ELTA,
                INITIAL_LIQUIDITY_USDC,
                0,
                0,
                deployer,
                block.timestamp + 1 hours
            );

        // Get pair address
        pair = contracts.uniswapFactory.getPair(address(contracts.elta), address(contracts.usdc));
    }

    function _configurePermissions(LocalContracts memory contracts) internal {
        // Governance roles
        contracts.timelock.grantRole(contracts.timelock.PROPOSER_ROLE(), address(contracts.governor));
        contracts.timelock.grantRole(contracts.timelock.EXECUTOR_ROLE(), address(contracts.governor));

        // XP operator role for local development
        contracts.xp.grantRole(contracts.xp.POINTS_OPERATOR_ROLE(), msg.sender);

        // ===== Wire AppFactory with additional modules =====
        // vNext: canonical app registry + per-app split factory + fee swapper.
        contracts.appFactory.setAppRegistry(address(contracts.appRegistry));
        contracts.appFactory.setContributorSplitFactory(address(contracts.contributorSplitFactory));
        contracts.appFactory.setFeeSwapper(address(contracts.feeSwapper));

        // Wire ProtocolConfig
        contracts.appFactory.setProtocolConfig(address(contracts.protocolConfig));

        // Wire FeeCollector
        contracts.appFactory.setFeeCollector(address(contracts.feeCollector));
    }

    function _saveDeploymentAddresses(LocalContracts memory contracts, address deployer) internal {
        string memory json = string.concat(
            "{\n",
            '  "network": "localhost",\n',
            '  "chainId": 31337,\n',
            '  "deployer": "',
            vm.toString(deployer),
            '",\n',
            '  "contracts": {\n',
            // Core Protocol
            '    "ELTA": "',
            vm.toString(address(contracts.elta)),
            '",\n',
            '    "ElataPoints": "',
            vm.toString(address(contracts.xp)),
            '",\n',
            '    "VeELTA": "',
            vm.toString(address(contracts.veElta)),
            '",\n',
            '    "ElataTimelock": "',
            vm.toString(address(contracts.timelock)),
            '",\n',
            '    "ElataGovernor": "',
            vm.toString(address(contracts.governor)),
            '",\n',
            '    "AppFactory": "',
            vm.toString(address(contracts.appFactory)),
            '",\n',
            '    "AppRegistry": "',
            vm.toString(address(contracts.appRegistry)),
            '",\n',
            '    "ContributorSplitFactory": "',
            vm.toString(address(contracts.contributorSplitFactory)),
            '",\n',
            '    "InAppContent721Factory": "',
            vm.toString(address(contracts.content721Factory)),
            '",\n',
            '    "ContentStoreFactory": "',
            vm.toString(address(contracts.contentStoreFactory)),
            '",\n',
            '    "TournamentFactory": "',
            vm.toString(address(contracts.tournamentFactory)),
            '",\n',
            '    "AppFeeRouter": "',
            vm.toString(address(contracts.appFeeRouter)),
            '",\n',
            // Fee Pipeline
            '    "FeeCollector": "',
            vm.toString(address(contracts.feeCollector)),
            '",\n',
            '    "FeeSwapper": "',
            vm.toString(address(contracts.feeSwapper)),
            '",\n',
            // Additional Modules
            '    "ProtocolConfig": "',
            vm.toString(address(contracts.protocolConfig)),
            '",\n',
            // External
            '    "MockUSDC": "',
            vm.toString(address(contracts.usdc)),
            '",\n',
            '    "MockWETH": "',
            vm.toString(address(contracts.weth)),
            '",\n',
            '    "UniswapV2Factory": "',
            vm.toString(address(contracts.uniswapFactory)),
            '",\n',
            '    "UniswapV2Router": "',
            vm.toString(address(contracts.uniswapRouter)),
            '",\n',
            '    "ELTA_USDC_Pair": "',
            vm.toString(contracts.eltaUsdcPair),
            '"\n',
            "  }\n",
            "}\n"
        );

        vm.writeFile("./deployments/local.json", json);
        console2.log("   Deployment saved to: ./deployments/local.json");
    }

    function _logDeployment(LocalContracts memory contracts) internal pure {
        console2.log("\n=== LOCAL DEPLOYMENT COMPLETE ===");
        console2.log("\nCore Protocol:");
        console2.log("  ELTA:                    ", address(contracts.elta));
        console2.log("  VeELTA:                  ", address(contracts.veElta));
        console2.log("  AppFactory:              ", address(contracts.appFactory));
        console2.log("\nFee Pipeline:");
        console2.log("  FeeCollector:            ", address(contracts.feeCollector));
        console2.log("  FeeSwapper:              ", address(contracts.feeSwapper));
        console2.log("\nExternal:");
        console2.log("  MockUSDC:                ", address(contracts.usdc));
        console2.log("  UniswapV2Router:         ", address(contracts.uniswapRouter));
        console2.log("  ELTA/USDC Pair:          ", contracts.eltaUsdcPair);
        console2.log("\n==================================");
        console2.log("\nSimulation can now track USDC revenue!");
        console2.log("Initial ELTA price: $0.10 (10M ELTA / 1M USDC)");
    }
}
