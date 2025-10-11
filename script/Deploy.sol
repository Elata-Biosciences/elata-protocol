// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ELTA } from "../src/token/ELTA.sol";
import { ElataXP } from "../src/experience/ElataXP.sol";
import { VeELTA } from "../src/staking/VeELTA.sol";
import { LotPool } from "../src/governance/LotPool.sol";
import { RewardsDistributor } from "../src/rewards/RewardsDistributor.sol";
import { AppRewardsDistributor } from "../src/rewards/AppRewardsDistributor.sol";
import { AppFeeRouter } from "../src/fees/AppFeeRouter.sol";
import { ElataGovernor } from "../src/governance/ElataGovernor.sol";
import { ElataTimelock } from "../src/governance/ElataTimelock.sol";
import { AppFactory } from "../src/apps/AppFactory.sol";
import { AppModuleFactory } from "../src/apps/AppModuleFactory.sol";
import { TournamentFactory } from "../src/apps/TournamentFactory.sol";
import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";
import { IAppRewardsDistributor } from "../src/interfaces/IAppRewardsDistributor.sol";
import { IAppFeeRouter } from "../src/interfaces/IAppFeeRouter.sol";
import { IVeEltaVotes } from "../src/interfaces/IVeEltaVotes.sol";
import { IRewardsDistributor } from "../src/interfaces/IRewardsDistributor.sol";

/**
 * @title Deploy
 * @notice Complete deployment script for Elata Protocol with Economic Upgrade V2
 * @dev Deploys the entire protocol with new rewards architecture in correct order
 *
 * Deployment Order:
 * 1. Core Tokens (ELTA, XP)
 * 2. VeELTA (ERC20Votes)
 * 3. Governance (Governor, Timelock)
 * 4. Funding (LotPool)
 * 5. Rewards Architecture (AppRewardsDistributor, RewardsDistributor, AppFeeRouter)
 * 6. App Launch (AppFactory with auto-stake)
 * 7. Utilities (AppModuleFactory, TournamentFactory)
 * 8. Permissions & Configuration
 *
 * Environment Variables Required:
 * - ADMIN_MSIG: Governance multisig address
 * - INITIAL_TREASURY: Treasury address
 * - UNISWAP_V2_ROUTER: Uniswap router address (network-specific)
 */
contract Deploy is Script {
    // Configuration - Set via environment variables
    address public ADMIN_MSIG = vm.envAddress("ADMIN_MSIG");
    address public INITIAL_TREASURY = vm.envAddress("INITIAL_TREASURY");

    // Token configuration
    uint256 public constant INITIAL_MINT = 10_000_000 ether; // 10M ELTA initial
    uint256 public constant MAX_SUPPLY = 77_000_000 ether; // 77M ELTA total cap

    // Governance configuration
    uint256 public constant TIMELOCK_DELAY = 48 hours;

    struct ProtocolContracts {
        ELTA token;
        ElataXP xp;
        VeELTA staking;
        LotPool funding;
        AppRewardsDistributor appRewardsDistributor;
        RewardsDistributor rewards;
        AppFeeRouter appFeeRouter;
        TimelockController timelock;
        ElataGovernor governor;
        AppFactory appFactory;
        AppModuleFactory appModuleFactory;
        TournamentFactory tournamentFactory;
    }

    event ProtocolDeployed(
        address indexed token,
        address indexed staking,
        address indexed xp,
        address funding,
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

        console2.log("=== ELATA PROTOCOL DEPLOYMENT ===");
        console2.log("Admin:", ADMIN_MSIG);
        console2.log("Treasury:", INITIAL_TREASURY);
        console2.log("Network:", block.chainid);
        console2.log("=====================================\n");

        // ===== STEP 1: Deploy Core Tokens =====
        console2.log("[1/9] Deploying Core Tokens...");
        protocol.token =
            new ELTA("ELTA", "ELTA", ADMIN_MSIG, INITIAL_TREASURY, INITIAL_MINT, MAX_SUPPLY);
        console2.log("   ELTA deployed at:", address(protocol.token));

        protocol.xp = new ElataXP(ADMIN_MSIG);
        console2.log("   ElataXP deployed at:", address(protocol.xp));

        // ===== STEP 2: Deploy VeELTA (ERC20Votes) =====
        console2.log("\n[2/9] Deploying VeELTA (ERC20Votes)...");
        protocol.staking = new VeELTA(protocol.token, ADMIN_MSIG);
        console2.log("   VeELTA deployed at:", address(protocol.staking));

        // ===== STEP 3: Deploy Governance =====
        console2.log("\n[3/9] Deploying Governance...");
        protocol.timelock = _deployTimelock();
        console2.log("   Timelock deployed at:", address(protocol.timelock));

        protocol.governor = new ElataGovernor(protocol.token);
        console2.log("   Governor deployed at:", address(protocol.governor));

        // ===== STEP 4: Deploy Funding =====
        console2.log("\n[4/9] Deploying Funding System...");
        protocol.funding = new LotPool(protocol.token, protocol.xp, ADMIN_MSIG);
        console2.log("   LotPool deployed at:", address(protocol.funding));

        // ===== STEP 5: Deploy Rewards Architecture (Economic Upgrade V2) =====
        console2.log("\n[5/9] Deploying Rewards Architecture (70/15/15)...");

        // 5a. AppRewardsDistributor (receives 70% for app stakers)
        protocol.appRewardsDistributor =
            new AppRewardsDistributor(protocol.token, ADMIN_MSIG, address(0)); // Factory set later
        console2.log(
            "   AppRewardsDistributor deployed at:", address(protocol.appRewardsDistributor)
        );

        // 5b. RewardsDistributor (central hub with 70/15/15 split)
        protocol.rewards = new RewardsDistributor(
            protocol.token,
            IVeEltaVotes(address(protocol.staking)),
            IAppRewardsDistributor(address(protocol.appRewardsDistributor)),
            INITIAL_TREASURY,
            ADMIN_MSIG
        );
        console2.log("   RewardsDistributor deployed at:", address(protocol.rewards));
        console2.log("   - 70% to app stakers");
        console2.log("   - 15% to veELTA stakers");
        console2.log("   - 15% to treasury");

        // 5c. AppFeeRouter (collects trading fees)
        protocol.appFeeRouter = new AppFeeRouter(
            protocol.token, IRewardsDistributor(address(protocol.rewards)), ADMIN_MSIG
        );
        console2.log("   AppFeeRouter deployed at:", address(protocol.appFeeRouter));
        console2.log("   Fee rate: 100 bps (1%)");

        // ===== STEP 6: Deploy App Launch Framework =====
        console2.log("\n[6/9] Deploying App Launch Framework...");

        address routerAddress = vm.envOr(
            "UNISWAP_V2_ROUTER",
            address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) // Mainnet default
        );

        if (routerAddress != address(0)) {
            protocol.appFactory = new AppFactory(
                protocol.token,
                IUniswapV2Router02(routerAddress),
                INITIAL_TREASURY,
                IAppFeeRouter(address(protocol.appFeeRouter)),
                IAppRewardsDistributor(address(protocol.appRewardsDistributor)),
                ADMIN_MSIG
            );
            console2.log("   AppFactory deployed at:", address(protocol.appFactory));
            console2.log("   Uniswap Router:", routerAddress);
        } else {
            console2.log("   AppFactory skipped (no router configured)");
        }

        // ===== STEP 7: Deploy App Utilities =====
        console2.log("\n[7/9] Deploying App Utilities...");

        protocol.appModuleFactory =
            new AppModuleFactory(address(protocol.token), ADMIN_MSIG, INITIAL_TREASURY);
        console2.log("   AppModuleFactory deployed at:", address(protocol.appModuleFactory));

        protocol.tournamentFactory = new TournamentFactory(ADMIN_MSIG, INITIAL_TREASURY);
        console2.log("   TournamentFactory deployed at:", address(protocol.tournamentFactory));

        // ===== STEP 8: Configure Permissions =====
        console2.log("\n[8/9] Configuring Permissions...");
        _configurePermissions(protocol);
        console2.log("   Permissions configured");

        // ===== STEP 9: Save Deployment Addresses =====
        console2.log("\n[9/9] Saving Deployment Addresses...");
        _saveDeploymentAddresses(protocol);

        // Log completion
        _logDeployment(protocol);

        // Emit deployment event
        emit ProtocolDeployed(
            address(protocol.token),
            address(protocol.staking),
            address(protocol.xp),
            address(protocol.funding),
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

        return new ElataTimelock(TIMELOCK_DELAY, proposers, executors, ADMIN_MSIG);
    }

    /**
     * @dev Configures initial permissions and roles
     */
    function _configurePermissions(ProtocolContracts memory protocol) internal {
        // Governance: Grant proposer/executor roles to governor
        protocol.timelock.grantRole(protocol.timelock.PROPOSER_ROLE(), address(protocol.governor));
        protocol.timelock.grantRole(protocol.timelock.EXECUTOR_ROLE(), address(protocol.governor));

        // XP: Grant operator role to funding system
        protocol.xp.grantRole(protocol.xp.XP_OPERATOR_ROLE(), address(protocol.funding));

        // Rewards: Grant DISTRIBUTOR_ROLE to AppFeeRouter
        protocol.rewards.grantRole(
            protocol.rewards.DISTRIBUTOR_ROLE(), address(protocol.appFeeRouter)
        );

        // AppRewards: Grant FACTORY_ROLE to AppFactory
        if (address(protocol.appFactory) != address(0)) {
            protocol.appRewardsDistributor.grantRole(
                protocol.appRewardsDistributor.FACTORY_ROLE(), address(protocol.appFactory)
            );
        }
    }

    /**
     * @dev Saves deployment addresses to JSON file
     */
    function _saveDeploymentAddresses(ProtocolContracts memory protocol) internal {
        string memory json = "deploymentData";

        vm.serializeAddress(json, "elta", address(protocol.token));
        vm.serializeAddress(json, "xp", address(protocol.xp));
        vm.serializeAddress(json, "veElta", address(protocol.staking));
        vm.serializeAddress(json, "funding", address(protocol.funding));
        vm.serializeAddress(json, "appRewardsDistributor", address(protocol.appRewardsDistributor));
        vm.serializeAddress(json, "rewardsDistributor", address(protocol.rewards));
        vm.serializeAddress(json, "appFeeRouter", address(protocol.appFeeRouter));
        vm.serializeAddress(json, "governor", address(protocol.governor));
        vm.serializeAddress(json, "timelock", address(protocol.timelock));
        vm.serializeAddress(json, "appFactory", address(protocol.appFactory));
        vm.serializeAddress(json, "appModuleFactory", address(protocol.appModuleFactory));
        vm.serializeAddress(json, "tournamentFactory", address(protocol.tournamentFactory));
        vm.serializeAddress(json, "admin", ADMIN_MSIG);
        vm.serializeAddress(json, "treasury", INITIAL_TREASURY);

        string memory finalJson = vm.serializeString(json, "network", _getNetworkName());

        string memory filename =
            string.concat("./deployments/", _getNetworkName(), "-deployment.json");

        vm.writeJson(finalJson, filename);
        console2.log("   Deployment saved to:", filename);
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
        console2.log("LotPool Funding:         ", address(protocol.funding));
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
        console2.log("3. Update frontend with contract addresses");
        console2.log("4. Grant additional roles as needed");
        console2.log("==================");
    }
}
