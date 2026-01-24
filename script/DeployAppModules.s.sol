// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "../src/apps/InAppContent721.sol";
import {ContentStore, PaymentTokenType} from "../src/apps/ContentStore.sol";
import {AppModuleFactory} from "../src/apps/AppModuleFactory.sol";
import {AppStakingVault} from "../src/apps/AppStakingVault.sol";
import {AppToken} from "../src/apps/AppToken.sol";
import {Tournament} from "../src/apps/Tournament.sol";
import {TournamentFactory} from "../src/apps/TournamentFactory.sol";
import {ELTA} from "../src/token/ELTA.sol";
import "forge-std/Script.sol";

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
    address public usdcAddress;
    address public treasury;
    address public feeCollector;
    address public appCreator;
    uint256 public createFeeELTA = 50 ether;
    uint256 public defaultProtocolFeeBps = 500; // 5%

    function setUp() public {
        // Load from environment or use defaults
        eltaAddress = vm.envOr("ELTA_ADDRESS", address(0));
        usdcAddress = vm.envOr("USDC_ADDRESS", address(0));
        treasury = vm.envOr("TREASURY_ADDRESS", msg.sender);
        feeCollector = vm.envOr("FEE_COLLECTOR_ADDRESS", address(0));
        appCreator = vm.envOr("APP_CREATOR", msg.sender);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying App Modules with deployer:", deployer);
        console.log("ELTA Address:", eltaAddress);
        console.log("USDC Address:", usdcAddress);
        console.log("Treasury:", treasury);
        console.log("Fee Collector:", feeCollector);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy AppModuleFactory (deploys InAppContent721 + ContentStore)
        AppModuleFactory factory =
            new AppModuleFactory(eltaAddress, usdcAddress, deployer, treasury, feeCollector, defaultProtocolFeeBps);
        console.log("AppModuleFactory deployed at:", address(factory));

        // 2. Deploy TournamentFactory
        TournamentFactory tournamentFactory = new TournamentFactory(deployer, treasury);
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
        console.log("Default Protocol Fee:", factory.defaultProtocolFeeBps(), "bps");
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
        address feeCollector = vm.envOr("FEE_COLLECTOR_ADDRESS", address(0));
        address usdcAddress = vm.envOr("USDC_ADDRESS", address(0));

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
        AppModuleFactory factory =
            new AppModuleFactory(address(elta), usdcAddress, deployer, treasury, feeCollector, 500);
        console.log("AppModuleFactory deployed at:", address(factory));

        TournamentFactory tournamentFactory = new TournamentFactory(deployer, treasury);
        console.log("TournamentFactory deployed at:", address(tournamentFactory));

        // 3. Simulate app creation (normally via AppFactory)
        // TODO: Update AppToken constructor - see MIGRATION_GUIDE.md
        // Need to add: governance, appRewardsDistributor, rewardsDistributor, treasury
        // AppToken appToken = new AppToken(
        //     "NeuroPong Token", "NPONG", 18, 1_000_000_000 ether, appCreator, appCreator
        // );
        // console.log("AppToken deployed at:", address(appToken));

        // Mint creator treasury (10%)
        // appToken.mint(appCreator, 100_000_000 ether);
        console.log("AppToken deployment DISABLED - needs migration (see MIGRATION_GUIDE.md)");

        // Skip module deployment until AppToken is properly deployed

        console.log("\n=== Deployment Summary ===");
        console.log("ELTA:", address(elta));
        console.log("AppModuleFactory:", address(factory));
        console.log("TournamentFactory:", address(tournamentFactory));
        console.log("\nNote: App deployment disabled - see MIGRATION_GUIDE.md for updates needed");

        vm.stopBroadcast();
        return;

        /* COMMENTED OUT - Needs AppToken migration
        // 4. Deploy modules via AppModuleFactory
        // AppModuleFactory now deploys InAppContent721 + ContentStore
        uint256 appId = 1;
        (address content721, address contentStore) = factory.deployModules(
            appId,
            address(appToken),
            "NeuroPong Content",
            "NPONG-CNT",
            "ipfs://QmContractMetadata"
        );
        console.log("InAppContent721 deployed at:", content721);
        console.log("ContentStore deployed at:", contentStore);

        // 5. List sample content
        ContentStore(contentStore).listContent(
            "ipfs://QmSeasonPass",
            50 ether, // Price: 50 tokens
            10000, // Max 10,000
            PaymentTokenType.APP
        );
        console.log("Listed Season Pass content (50 tokens, max 10,000)");

        // 6. Set a feature gate
        bytes32 premiumFeature = keccak256("premium_mode");
        ContentStore(contentStore).setFeatureGate(
            premiumFeature,
            500 ether, // minStake: 500 tokens
            0, // requiredContentId: none (will use content purchases)
            false, // requireBoth: false (stake OR content)
            true // active
        );
        console.log("Set premium_mode feature gate (500 stake)");

        // 7. Deploy a tournament via TournamentFactory
        address tournament = tournamentFactory.createTournament(
            address(appToken),
            5 ether, // Entry fee: 5 tokens
            0, // Start immediately
            uint64(block.timestamp + 7 days) // 1 week duration
        );
        console.log("Tournament deployed at:", tournament);

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Deployment Summary ===");
        console.log("ELTA:", address(elta));
        console.log("AppModuleFactory:", address(factory));
        console.log("TournamentFactory:", address(tournamentFactory));
        console.log("AppToken:", address(appToken));
        console.log("InAppContent721:", content721);
        console.log("ContentStore:", contentStore);
        console.log("First Tournament:", tournament);
        console.log("\nCreator Treasury: 90M tokens remaining");
        console.log("\nNote: EpochRewards removed - use external airdrop services");
        console.log("\nNext steps:");
        console.log("1. Users purchase content (mints ERC-721 tokens)");
        console.log("2. Users stake tokens to unlock features via feature gates");
        console.log("3. Users enter tournament (5 token entry fee)");
        console.log("4. Creator finalizes tournament with winners Merkle root");
        console.log("5. Winners claim their rewards");
        console.log("6. Use external airdrop service for seasonal rewards if needed");
        */
    }
}
