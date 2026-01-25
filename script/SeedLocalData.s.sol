// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "../src/apps/InAppContent721.sol";
import {ContentStore, PaymentTokenType} from "../src/apps/ContentStore.sol";
import {AppFactory} from "../src/apps/AppFactory.sol";
import {AppModuleFactory} from "../src/apps/AppModuleFactory.sol";
import {AppStakingVault} from "../src/apps/AppStakingVault.sol";
import {AppToken} from "../src/apps/AppToken.sol";
import {ElataPoints} from "../src/experience/ElataPoints.sol";
import {VeELTA} from "../src/staking/VeELTA.sol";
import {ELTA} from "../src/token/ELTA.sol";
import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @title SeedLocalData
 * @notice Seeds local deployment with realistic test data
 * @dev Creates apps, distributes XP, creates staking positions, and starts funding rounds
 *
 * Contract addresses are auto-discovered from most recent deployment on the network
 */
contract SeedLocalData is Script {
    struct TestApp {
        uint256 appId;
        address token;
        address content721;
        address contentStore;
        address stakingVault;
        string name;
        string symbol;
    }

    // Addresses are loaded dynamically from deployments/local.json (written by Deploy.sol)
    address ELTA_ADDRESS;
    address XP_ADDRESS;
    address STAKING_ADDRESS;
    address APP_FACTORY_ADDRESS;
    address APP_MODULE_FACTORY_ADDRESS;

    function run() external {
        // Use Anvil account #0
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        vm.startBroadcast(deployerPrivateKey);

        console2.log("\n=================================================");
        console2.log("       SEEDING LOCAL BLOCKCHAIN WITH DATA");
        console2.log("=================================================\n");

        // Load addresses from deployments/local.json
        _loadAddresses();

        // Step 1: Award XP to test users
        console2.log("[1/4] Awarding XP to test users...");
        _awardTestXP();

        // Step 2: Create staking positions
        console2.log("[2/4] Creating test staking positions...");
        _createStakingPositions();

        // Step 3: Create test apps
        console2.log("[3/4] Creating test apps...");
        TestApp[] memory apps = _createTestApps();

        // Step 4: Configure app economies
        console2.log("[4/4] Configuring app economies...");
        _configureAppEconomies(apps);

        vm.stopBroadcast();

        console2.log("\n=================================================");
        console2.log("            SEED DATA COMPLETE");
        console2.log("=================================================\n");

        _printSeedSummary(apps);
    }

    function _loadAddresses() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/local.json");
        string memory json = vm.readFile(path);

        // Read required addresses
        ELTA_ADDRESS = stdJson.readAddress(json, ".contracts.ELTA");
        XP_ADDRESS = stdJson.readAddress(json, ".contracts.ElataPoints");
        STAKING_ADDRESS = stdJson.readAddress(json, ".contracts.VeELTA");
        APP_FACTORY_ADDRESS = stdJson.readAddress(json, ".contracts.AppFactory");
        APP_MODULE_FACTORY_ADDRESS = stdJson.readAddress(json, ".contracts.AppModuleFactory");

        require(ELTA_ADDRESS != address(0), "ELTA address missing");
        require(XP_ADDRESS != address(0), "XP address missing");
        require(STAKING_ADDRESS != address(0), "VeELTA address missing");
        require(APP_MODULE_FACTORY_ADDRESS != address(0), "AppModuleFactory address missing");

        // AppFactory is required for creating apps; allow zero to skip app creation
        if (APP_FACTORY_ADDRESS == address(0)) {
            console2.log("[WARN] AppFactory not deployed; skipping app creation steps");
        }
    }

    function _awardTestXP() internal {
        ElataPoints xp = ElataPoints(XP_ADDRESS);

        console2.log("       XP contract at:", address(xp));
        console2.log("       Sender:", msg.sender);

        // Test accounts
        address[] memory users = new address[](5);
        users[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        users[1] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        users[2] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
        users[3] = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
        users[4] = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;

        // Award different amounts of XP to simulate activity levels
        uint256[] memory xpAmounts = new uint256[](5);
        xpAmounts[0] = 5000 ether; // Power user
        xpAmounts[1] = 3000 ether; // Active user
        xpAmounts[2] = 1500 ether; // Regular user
        xpAmounts[3] = 800 ether; // Casual user
        xpAmounts[4] = 300 ether; // New user

        console2.log("       Starting XP awards...");
        for (uint256 i = 0; i < users.length; i++) {
            console2.log("       Awarding to user", i, ":", users[i]);
            xp.award(users[i], xpAmounts[i]);
            console2.log("       Awarded", xpAmounts[i] / 1 ether, "XP to", users[i]);
        }
    }

    function _createStakingPositions() internal {
        ELTA elta = ELTA(ELTA_ADDRESS);
        VeELTA staking = VeELTA(STAKING_ADDRESS);

        // Create one staking position for the deployer
        // NOTE: VeELTA only allows one lock per address
        uint256 amount = 10000 ether; // 10K ELTA
        uint256 duration = 104 weeks; // 2 years

        elta.approve(address(staking), amount);
        staking.lock(amount, uint64(block.timestamp + duration));
        console2.log("       Created lock: %s ELTA for %s weeks", amount / 1 ether, duration / 1 weeks);
    }

    function _createTestApps() internal returns (TestApp[] memory) {
        ELTA elta = ELTA(ELTA_ADDRESS);
        if (APP_FACTORY_ADDRESS == address(0)) {
            // If no factory, return empty array
            return new TestApp[](0);
        }
        AppFactory factory = AppFactory(APP_FACTORY_ADDRESS);
        AppModuleFactory moduleFactory = AppModuleFactory(APP_MODULE_FACTORY_ADDRESS);

        TestApp[] memory apps = new TestApp[](3);

        // App 1: NeuroPong
        apps[0] = _createSingleApp(
            elta,
            factory,
            moduleFactory,
            "NeuroPong Token",
            "NPONG",
            "EEG-controlled Pong game with competitive multiplayer",
            "ipfs://QmNeuroPong"
        );

        // App 2: MindfulBreath
        apps[1] = _createSingleApp(
            elta,
            factory,
            moduleFactory,
            "MindfulBreath Token",
            "BREATH",
            "Meditation and breathing exercises with EEG feedback",
            "ipfs://QmMindfulBreath"
        );

        // App 3: FocusTrainer
        apps[2] = _createSingleApp(
            elta,
            factory,
            moduleFactory,
            "FocusTrainer Token",
            "FOCUS",
            "Attention training with real-time neurofeedback",
            "ipfs://QmFocusTrainer"
        );

        return apps;
    }

    function _createSingleApp(
        ELTA elta,
        AppFactory factory,
        AppModuleFactory moduleFactory,
        string memory name,
        string memory symbol,
        string memory description,
        string memory imageURI
    ) internal returns (TestApp memory app) {
        // Get creation cost (seedElta + creationFee)
        uint256 totalCost = factory.seedElta() + factory.creationFee();

        // Approve and create app
        elta.approve(address(factory), totalCost);
        app.appId = factory.createApp(
            name,
            symbol,
            0, // Use default supply
            description,
            imageURI,
            "https://app.elata.bio",
            new address[](0)
        );

        // Get app token address (apps mapping returns the full struct as tuple)
        // App struct: creator, token, vault, curve, vestingWallet, ecosystemVault, pair, locker,
        // createdAt, graduatedAt, graduated, totalRaised, finalSupply
        (, app.token,,,,,,,,,,,) = factory.apps(app.appId);
        app.name = name;
        app.symbol = symbol;

        console2.log("       Created app:", name, "at", app.token);

        // Deploy utility modules (InAppContent721 + ContentStore)
        elta.approve(address(moduleFactory), 0); // No fee for now

        // Note: vault is already deployed by AppFactory, get it from the app struct
        (,, address vaultAddr,,,,,,,,,,) = AppFactory(APP_FACTORY_ADDRESS).apps(app.appId);
        (address content721, address contentStore) = moduleFactory.deployModules(
            app.appId,
            app.token,
            string.concat(app.name, " Content"),
            string.concat(symbol, "-CNT"),
            string.concat("ipfs://", symbol, "/contract")
        );
        app.content721 = content721;
        app.contentStore = contentStore;
        app.stakingVault = vaultAddr;

        console2.log("       Deployed modules: InAppContent721 + ContentStore");

        return app;
    }

    function _configureAppEconomies(TestApp[] memory apps) internal {
        // Configure each app with content listings
        for (uint256 i = 0; i < apps.length; i++) {
            _configureSingleApp(apps[i]);
        }
    }

    function _configureSingleApp(TestApp memory app) internal {
        ContentStore store = ContentStore(app.contentStore);

        // Create tiered content listings for each app

        // Content 1: Basic Pass
        store.listContent(
            string.concat("ipfs://", app.symbol, "/basic-pass"),
            10 ether, // price: 10 tokens
            10000, // max supply
            PaymentTokenType.APP
        );

        // Content 2: Premium Pass
        store.listContent(
            string.concat("ipfs://", app.symbol, "/premium-pass"),
            50 ether, // price: 50 tokens
            1000, // limited supply
            PaymentTokenType.APP
        );

        // Content 3: Legendary Pass (very rare)
        store.listContent(
            string.concat("ipfs://", app.symbol, "/legendary-pass"),
            200 ether, // price: 200 tokens
            100, // very limited
            PaymentTokenType.APP
        );

        console2.log("       Listed 3 content items for", app.name);

        // Set up a feature gate (premium feature requires 100 tokens staked OR content ID 1)
        store.setFeatureGate(
            keccak256("premium_features"),
            100 ether, // minStake: 100 tokens
            1, // requiredContentId: content ID 1 (Basic Pass)
            false, // requireBoth: false (either one works)
            true // active
        );

        console2.log("       Configured feature gate for", app.name);
    }

    function _printSeedSummary(TestApp[] memory apps) internal pure {
        console2.log("SUMMARY:");
        console2.log("--------");
        console2.log("- 5 test users with XP (300-5000 XP)");
        console2.log("- 1 staking position (10K ELTA)");
        console2.log("- 3 test apps with full economies:");

        for (uint256 i = 0; i < apps.length; i++) {
            console2.log("  ", string.concat(vm.toString(i + 1), ". ", apps[i].name, " (", apps[i].symbol, ")"));
        }

        console2.log("");
        console2.log("Ready for development! Start the App Store frontend:");
        console2.log("  cd ../elata-appstore && npm run local:full");
        console2.log("");
    }
}
