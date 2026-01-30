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

// Rewards
import {RewardsDistributor} from "../src/rewards/RewardsDistributor.sol";
import {AppRewardsDistributor} from "../src/rewards/AppRewardsDistributor.sol";
import {AppFeeRouter} from "../src/fees/AppFeeRouter.sol";

// Fee Pipeline
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {FeeManager} from "../src/fees/FeeManager.sol";
import {FeeSwapper} from "../src/fees/FeeSwapper.sol";
import {TreasuryUSDCVault} from "../src/fees/TreasuryUSDCVault.sol";

// Additional Modules
import {ProtocolConfig} from "../src/core/ProtocolConfig.sol";
import {ReferralRegistry} from "../src/modules/ReferralRegistry.sol";
import {AirdropDistributor} from "../src/modules/AirdropDistributor.sol";

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
import {IVeEltaVotes} from "../src/interfaces/IVeEltaVotes.sol";
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
        // Rewards
        RewardsDistributor rewardsDistributor;
        AppRewardsDistributor appRewardsDistributor;
        AppFeeRouter appFeeRouter;
        // Fee Pipeline
        FeeCollector feeCollector;
        FeeManager feeManager;
        FeeSwapper feeSwapper;
        TreasuryUSDCVault treasuryVault;
        // Additional Modules
        ProtocolConfig protocolConfig;
        ReferralRegistry referralRegistry;
        AirdropDistributor airdropDistributor;
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

        // ===== PHASE 5: Deploy Rewards Architecture =====
        console2.log("\n[5/8] Deploying Rewards Architecture (70/15/15)...");

        // AppRewardsDistributor
        contracts.appRewardsDistributor = new AppRewardsDistributor(contracts.elta, deployer, deployer);
        console2.log("   AppRewardsDistributor:", address(contracts.appRewardsDistributor));

        // RewardsDistributor (central hub)
        contracts.rewardsDistributor = new RewardsDistributor(
            contracts.elta,
            IVeEltaVotes(address(contracts.veElta)),
            IAppRewardsDistributor(address(contracts.appRewardsDistributor)),
            treasury,
            deployer
        );
        console2.log("   RewardsDistributor:", address(contracts.rewardsDistributor));

        // AppFeeRouter
        contracts.appFeeRouter =
            new AppFeeRouter(contracts.elta, IRewardsDistributor(address(contracts.rewardsDistributor)), deployer);
        console2.log("   AppFeeRouter:", address(contracts.appFeeRouter));

        // ===== PHASE 6: Deploy App Framework =====
        console2.log("\n[6/8] Deploying App Framework...");

        // AppFactory
        contracts.appFactory = new AppFactory(
            IERC20(address(contracts.elta)),
            IUniswapV2Router02(address(contracts.uniswapRouter)),
            treasury,
            IAppFeeRouter(address(contracts.appFeeRouter)),
            IAppRewardsDistributor(address(contracts.appRewardsDistributor)),
            IRewardsDistributor(address(contracts.rewardsDistributor)),
            IElataPoints(address(contracts.xp)),
            deployer,
            deployer
        );
        console2.log("   AppFactory:", address(contracts.appFactory));

        // InAppContent721Factory
        contracts.content721Factory = new InAppContent721Factory(address(contracts.elta), deployer, treasury);
        console2.log("   InAppContent721Factory:", address(contracts.content721Factory));

        // ContentStoreFactory
        contracts.contentStoreFactory = new ContentStoreFactory(
            address(contracts.elta),
            address(contracts.usdc),
            deployer,
            treasury,
            address(contracts.appFeeRouter),
            500 // 5% default protocol fee
        );
        console2.log("   ContentStoreFactory:", address(contracts.contentStoreFactory));

        // TournamentFactory
        contracts.tournamentFactory = new TournamentFactory(deployer, treasury);
        console2.log("   TournamentFactory:", address(contracts.tournamentFactory));

        // ===== PHASE 7: Deploy Fee Pipeline =====
        console2.log("\n[7/8] Deploying Fee Pipeline...");

        // TreasuryUSDCVault (deploy first, feeManager set later)
        contracts.treasuryVault = new TreasuryUSDCVault(
            address(contracts.usdc),
            deployer,
            treasury,
            address(0) // Will set feeManager after deployment
        );
        console2.log("   TreasuryUSDCVault:", address(contracts.treasuryVault));

        // FeeManager
        contracts.feeManager = new FeeManager(
            address(contracts.elta),
            address(contracts.usdc),
            deployer,
            deployer, // governance
            address(contracts.appRewardsDistributor),
            address(contracts.rewardsDistributor),
            address(contracts.treasuryVault),
            FEE_EPOCH_LENGTH
        );
        console2.log("   FeeManager:", address(contracts.feeManager));

        // Set FeeManager on TreasuryVault
        contracts.treasuryVault.setFeeManager(address(contracts.feeManager));

        // Set swap router on FeeManager
        contracts.feeManager.setSwapRouter(address(contracts.uniswapRouter));

        // FeeSwapper (use deployer as governance for local so we can configure immediately)
        contracts.feeSwapper = new FeeSwapper(
            address(contracts.elta),
            deployer,
            deployer, // Use deployer as governance for local testing
            address(contracts.feeManager)
        );
        console2.log("   FeeSwapper:", address(contracts.feeSwapper));

        // FeeCollector (now with FeeSwapper)
        contracts.feeCollector = new FeeCollector(
            address(contracts.elta), deployer, address(contracts.feeManager), address(contracts.feeSwapper)
        );
        console2.log("   FeeCollector:", address(contracts.feeCollector));

        // Authorize Uniswap router in FeeSwapper
        contracts.feeSwapper.setRouterAllowed(address(contracts.uniswapRouter), true);

        // ===== PHASE 7.5: Deploy Additional Modules =====
        console2.log("\n[7.5/8] Deploying Additional Modules...");

        // ProtocolConfig
        contracts.protocolConfig = new ProtocolConfig(deployer, address(contracts.timelock));
        console2.log("   ProtocolConfig:", address(contracts.protocolConfig));

        // ReferralRegistry (500 bps = 5% referral fee)
        contracts.referralRegistry = new ReferralRegistry(deployer, address(contracts.elta), 500);
        console2.log("   ReferralRegistry:", address(contracts.referralRegistry));

        // AirdropDistributor
        contracts.airdropDistributor = new AirdropDistributor(deployer, deployer);
        console2.log("   AirdropDistributor:", address(contracts.airdropDistributor));

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

        // Rewards distributor role
        contracts.rewardsDistributor
            .grantRole(contracts.rewardsDistributor.DISTRIBUTOR_ROLE(), address(contracts.appFeeRouter));

        // AppRewards factory role
        contracts.appRewardsDistributor
            .grantRole(contracts.appRewardsDistributor.FACTORY_ROLE(), address(contracts.appFactory));

        // ===== Wire FeeManager for USDC conversion =====
        // Set feeManager on RewardsDistributor so treasury fees route through it
        contracts.rewardsDistributor.setFeeManager(address(contracts.feeManager));

        // Make RewardsDistributor an authorized depositor on FeeManager
        contracts.feeManager.setDepositor(address(contracts.rewardsDistributor), true);

        // Make FeeCollector an authorized depositor on FeeManager
        contracts.feeManager.setDepositor(address(contracts.feeCollector), true);

        // Wire ReferralRegistry to FeeManager
        contracts.feeManager.setReferralRegistry(address(contracts.referralRegistry));

        // ===== Wire AppFactory with additional modules =====
        // Wire ProtocolConfig
        contracts.appFactory.setProtocolConfig(address(contracts.protocolConfig));

        // Wire FeeCollector
        contracts.appFactory.setFeeCollector(address(contracts.feeCollector));

        // Wire ReferralRegistry
        contracts.appFactory.setReferralRegistry(address(contracts.referralRegistry));
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
            '    "RewardsDistributor": "',
            vm.toString(address(contracts.rewardsDistributor)),
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
            '    "InAppContent721Factory": "',
            vm.toString(address(contracts.content721Factory)),
            '",\n',
            '    "ContentStoreFactory": "',
            vm.toString(address(contracts.contentStoreFactory)),
            '",\n',
            '    "TournamentFactory": "',
            vm.toString(address(contracts.tournamentFactory)),
            '",\n',
            '    "AppRewardsDistributor": "',
            vm.toString(address(contracts.appRewardsDistributor)),
            '",\n',
            '    "AppFeeRouter": "',
            vm.toString(address(contracts.appFeeRouter)),
            '",\n',
            // Fee Pipeline
            '    "FeeCollector": "',
            vm.toString(address(contracts.feeCollector)),
            '",\n',
            '    "FeeManager": "',
            vm.toString(address(contracts.feeManager)),
            '",\n',
            '    "FeeSwapper": "',
            vm.toString(address(contracts.feeSwapper)),
            '",\n',
            '    "TreasuryUSDCVault": "',
            vm.toString(address(contracts.treasuryVault)),
            '",\n',
            // Additional Modules
            '    "ProtocolConfig": "',
            vm.toString(address(contracts.protocolConfig)),
            '",\n',
            '    "ReferralRegistry": "',
            vm.toString(address(contracts.referralRegistry)),
            '",\n',
            '    "AirdropDistributor": "',
            vm.toString(address(contracts.airdropDistributor)),
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
        console2.log("  FeeManager:              ", address(contracts.feeManager));
        console2.log("  TreasuryUSDCVault:       ", address(contracts.treasuryVault));
        console2.log("\nExternal:");
        console2.log("  MockUSDC:                ", address(contracts.usdc));
        console2.log("  UniswapV2Router:         ", address(contracts.uniswapRouter));
        console2.log("  ELTA/USDC Pair:          ", contracts.eltaUsdcPair);
        console2.log("\n==================================");
        console2.log("\nSimulation can now track USDC revenue!");
        console2.log("Initial ELTA price: $0.10 (10M ELTA / 1M USDC)");
    }
}
