// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { AppToken } from "../src/apps/AppToken.sol";
import { AppModuleFactory } from "../src/apps/AppModuleFactory.sol";
import { TournamentFactory } from "../src/apps/TournamentFactory.sol";
import { AppAccess1155 } from "../src/apps/AppAccess1155.sol";
import { AppStakingVault } from "../src/apps/AppStakingVault.sol";
import { Tournament } from "../src/apps/Tournament.sol";
import { EpochRewards } from "../src/apps/EpochRewards.sol";
import { ELTA } from "../src/token/ELTA.sol";

/**
 * @title DeployAppModules
 * @notice Deployment script for Elata app utility modules
 * @dev Example usage:
 *      forge script script/DeployAppModules.s.sol:DeployAppModules \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          --verify
 */
contract DeployAppModules is Script {
    // Environment variables (set these before running)
    address public eltaAddress;
    address public treasury;
    address public appCreator;
    uint256 public createFeeELTA = 50 ether;

    function setUp() public {
        // Load from environment or use defaults
        eltaAddress = vm.envOr("ELTA_ADDRESS", address(0));
        treasury = vm.envOr("TREASURY_ADDRESS", msg.sender);
        appCreator = vm.envOr("APP_CREATOR", msg.sender);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying App Modules with deployer:", deployer);
        console.log("ELTA Address:", eltaAddress);
        console.log("Treasury:", treasury);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy AppModuleFactory
        AppModuleFactory factory = new AppModuleFactory(
            eltaAddress,
            deployer,
            treasury
        );
        console.log("AppModuleFactory deployed at:", address(factory));

        // 2. Deploy TournamentFactory
        TournamentFactory tournamentFactory = new TournamentFactory(
            deployer,
            treasury
        );
        console.log("TournamentFactory deployed at:", address(tournamentFactory));

        // 3. Set creation fee (optional)
        if (createFeeELTA > 0 && eltaAddress != address(0)) {
            factory.setCreateFee(createFeeELTA);
            console.log("Set createFeeELTA to:", createFeeELTA);
        }

        vm.stopBroadcast();

        // Log deployment info
        console.log("\n=== Deployment Complete ===");
        console.log("AppModuleFactory:", address(factory));
        console.log("TournamentFactory:", address(tournamentFactory));
        console.log("Treasury:", factory.treasury());
        console.log("Create Fee:", factory.createFeeELTA());
    }
}

/**
 * @title DeployFullExample
 * @notice Example deployment of complete app token ecosystem
 * @dev Demonstrates end-to-end deployment for a single app
 */
contract DeployFullExample is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address appCreator = deployer;

        console.log("Deploying Full App Example");
        console.log("Deployer/App Creator:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy or use existing ELTA
        ELTA elta = new ELTA(
            "ELTA",
            "ELTA",
            deployer,
            deployer,
            10_000_000 ether, // Initial mint
            77_000_000 ether // Max supply
        );
        console.log("ELTA deployed at:", address(elta));

        // 2. Deploy factories
        AppModuleFactory factory = new AppModuleFactory(
            address(elta),
            deployer,
            treasury
        );
        console.log("AppModuleFactory deployed at:", address(factory));

        TournamentFactory tournamentFactory = new TournamentFactory(
            deployer,
            treasury
        );
        console.log("TournamentFactory deployed at:", address(tournamentFactory));

        // 3. Simulate app creation (normally via AppFactory)
        // In production, creator calls appFactory.createApp() which:
        // - Deploys AppToken
        // - Mints 10% to creator, 90% to bonding curve
        // - Transfers admin role to creator
        // For this example, we manually create the token
        AppToken appToken = new AppToken(
            "NeuroPong Token",
            "NPONG",
            18,
            1_000_000_000 ether,
            appCreator,
            appCreator
        );
        console.log("AppToken deployed at:", address(appToken));

        // Mint creator treasury (10%)
        appToken.mint(appCreator, 100_000_000 ether);
        console.log("Minted 100M tokens (10%) to creator treasury");

        // 4. Deploy modules via AppModuleFactory
        (address access1155, address stakingVault, address epochRewards) = factory.deployModules(
            address(appToken),
            "https://metadata.neuropong.game/"
        );
        console.log("AppAccess1155 deployed at:", access1155);
        console.log("AppStakingVault deployed at:", stakingVault);
        console.log("EpochRewards deployed at:", epochRewards);

        // 5. Configure a sample item (Season Pass)
        AppAccess1155(access1155).setItem(
            1, // ID
            50 ether, // Price: 50 tokens
            true, // Soulbound
            true, // Active
            0, // No start time
            0, // No end time
            10000, // Max 10,000 passes
            "ipfs://QmSeasonPass1"
        );
        console.log("Configured Season Pass (ID: 1, Price: 50 tokens)");

        // 6. Set a feature gate (Premium Mode)
        bytes32 premiumFeature = keccak256("premium_mode");
        AppAccess1155.FeatureGate memory gate = AppAccess1155.FeatureGate({
            minStake: 500 ether, // Need 500 tokens staked
            requiredItem: 1, // Need Season Pass
            requireBoth: true, // Need both stake AND pass
            active: true
        });
        AppAccess1155(access1155).setFeatureGate(premiumFeature, gate);
        console.log("Set premium_mode feature gate (500 stake + pass)");

        // 7. Deploy a tournament via TournamentFactory
        address tournament = tournamentFactory.createTournament(
            address(appToken),
            5 ether, // Entry fee: 5 tokens
            0, // Start immediately
            uint64(block.timestamp + 7 days) // 1 week duration
        );
        console.log("Tournament deployed at:", tournament);

        // 8. Start first epoch for seasonal rewards
        EpochRewards(epochRewards).startEpoch(
            uint64(block.timestamp),
            uint64(block.timestamp + 30 days)
        );
        console.log("First 30-day epoch started");

        // 9. Fund epoch from creator treasury
        appToken.approve(epochRewards, 10_000_000 ether);
        EpochRewards(epochRewards).fund(10_000_000 ether);
        console.log("Epoch funded with 10M tokens from creator treasury");

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Deployment Summary ===");
        console.log("ELTA:", address(elta));
        console.log("AppModuleFactory:", address(factory));
        console.log("TournamentFactory:", address(tournamentFactory));
        console.log("AppToken:", address(appToken));
        console.log("AppAccess1155:", access1155);
        console.log("AppStakingVault:", stakingVault);
        console.log("EpochRewards:", epochRewards);
        console.log("First Tournament:", tournament);
        console.log("\nCreator Treasury: 90M tokens remaining for future rewards");
        console.log("\nNext steps:");
        console.log("1. Users purchase Season Pass (50 tokens, burns on purchase)");
        console.log("2. Users stake tokens to unlock premium_mode");
        console.log("3. Users enter tournament (5 token entry fee)");
        console.log("4. Creator finalizes tournament with winners Merkle root");
        console.log("5. Creator finalizes epoch with rewards Merkle root");
        console.log("6. Winners and players claim their rewards");
    }
}

