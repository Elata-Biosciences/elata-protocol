// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { AppToken } from "../src/apps/AppToken.sol";
import { AppModuleFactory } from "../src/apps/AppModuleFactory.sol";
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

        // 2. Set creation fee (optional)
        if (createFeeELTA > 0 && eltaAddress != address(0)) {
            factory.setCreateFee(createFeeELTA);
            console.log("Set createFeeELTA to:", createFeeELTA);
        }

        vm.stopBroadcast();

        // Log deployment info
        console.log("\n=== Deployment Complete ===");
        console.log("AppModuleFactory:", address(factory));
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

        // 2. Deploy AppModuleFactory
        AppModuleFactory factory = new AppModuleFactory(
            address(elta),
            deployer,
            treasury
        );
        console.log("AppModuleFactory deployed at:", address(factory));

        // 3. Deploy AppToken for the app
        AppToken appToken = new AppToken(
            "NeuroPong Token",
            "NPONG",
            18,
            1_000_000_000 ether, // 1B max supply
            appCreator,
            appCreator // App creator is also admin
        );
        console.log("AppToken deployed at:", address(appToken));

        // 4. Mint initial supply to creator's rewards treasury
        appToken.mint(appCreator, 100_000_000 ether); // 100M for rewards
        console.log("Minted 100M tokens to creator");

        // 5. Finalize minting (optional - locks supply permanently)
        // appToken.finalizeMinting();
        // console.log("Minting finalized");

        // 6. Deploy modules via factory
        (address access1155, address stakingVault) = factory.deployModules(
            address(appToken),
            "https://metadata.neuropong.game/"
        );
        console.log("AppAccess1155 deployed at:", access1155);
        console.log("AppStakingVault deployed at:", stakingVault);

        // 7. Configure a sample item (Season Pass)
        AppAccess1155(access1155).setItem(
            1, // ID
            100 ether, // Price: 100 tokens
            true, // Soulbound
            true, // Active
            0, // No start time
            0, // No end time
            10000, // Max 10,000 passes
            "ipfs://QmSeasonPass1"
        );
        console.log("Configured Season Pass (ID: 1)");

        // 8. Set a feature gate (Premium Mode)
        bytes32 premiumFeature = keccak256("premium_mode");
        AppAccess1155.FeatureGate memory gate = AppAccess1155.FeatureGate({
            minStake: 1000 ether, // Need 1000 tokens staked
            requiredItem: 1, // Need Season Pass
            requireBoth: true, // Need both stake AND pass
            active: true
        });
        AppAccess1155(access1155).setFeatureGate(premiumFeature, gate);
        console.log("Set premium_mode feature gate");

        // 9. Deploy Tournament (optional)
        Tournament tournament = new Tournament(
            address(appToken),
            appCreator,
            treasury,
            10 ether, // Entry fee
            0, // Start immediately
            0, // No end time
            250, // 2.5% protocol fee
            100 // 1% burn fee
        );
        console.log("Tournament deployed at:", address(tournament));

        // 10. Deploy EpochRewards (optional)
        EpochRewards rewards = new EpochRewards(address(appToken), appCreator);
        console.log("EpochRewards deployed at:", address(rewards));

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Deployment Summary ===");
        console.log("ELTA:", address(elta));
        console.log("AppModuleFactory:", address(factory));
        console.log("AppToken:", address(appToken));
        console.log("AppAccess1155:", access1155);
        console.log("AppStakingVault:", stakingVault);
        console.log("Tournament:", address(tournament));
        console.log("EpochRewards:", address(rewards));
        console.log("\nNext steps:");
        console.log("1. Users can purchase Season Pass by calling AppAccess1155.purchase()");
        console.log("2. Users can stake tokens via AppStakingVault.stake()");
        console.log("3. Users meeting requirements can access premium_mode");
        console.log("4. Tournament entry via Tournament.enter()");
        console.log("5. Epoch rewards via EpochRewards.startEpoch() + fund() + finalizeEpoch()");
    }
}

