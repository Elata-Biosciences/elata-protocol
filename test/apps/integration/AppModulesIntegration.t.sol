// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { AppToken } from "../../../src/apps/AppToken.sol";
import { AppAccess1155 } from "../../../src/apps/AppAccess1155.sol";
import { AppStakingVault } from "../../../src/apps/AppStakingVault.sol";
import { Tournament } from "../../../src/apps/Tournament.sol";
import { EpochRewards } from "../../../src/apps/EpochRewards.sol";
import { AppModuleFactory } from "../../../src/apps/AppModuleFactory.sol";
import { ELTA } from "../../../src/token/ELTA.sol";
import { Merkle } from "murky/src/Merkle.sol";

/**
 * @title AppModulesIntegrationTest
 * @notice Complete integration tests for app token utility system
 * @dev Tests real-world workflows and cross-contract interactions
 */
contract AppModulesIntegrationTest is Test {
    AppModuleFactory public factory;
    ELTA public elta;
    AppToken public appToken;
    AppAccess1155 public access;
    AppStakingVault public vault;
    Tournament public tournament;
    EpochRewards public rewards;
    Merkle public merkle;

    address public factoryOwner = makeAddr("factoryOwner");
    address public treasury = makeAddr("treasury");
    address public appCreator = makeAddr("appCreator");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
    uint256 public constant CREATE_FEE = 50 ether;

    event FeatureAccessGranted(address indexed user, string feature);

    function setUp() public {
        merkle = new Merkle();

        // Deploy ELTA
        elta = new ELTA("ELTA", "ELTA", factoryOwner, factoryOwner, 10000000 ether, 77000000 ether);

        // Deploy factory
        factory = new AppModuleFactory(address(elta), factoryOwner, treasury);

        vm.prank(factoryOwner);
        factory.setCreateFee(CREATE_FEE);

        // Deploy app token
        appToken = new AppToken("NeuroPong", "NPONG", 18, MAX_SUPPLY, appCreator, admin);

        // Mint initial rewards treasury
        vm.prank(admin);
        appToken.mint(appCreator, 100_000_000 ether);

        // Deploy modules
        vm.prank(factoryOwner);
        elta.mint(appCreator, 1000 ether);

        vm.prank(appCreator);
        elta.approve(address(factory), CREATE_FEE);

        vm.prank(appCreator);
        (address accessAddr, address vaultAddr,) =
            factory.deployModules(address(appToken), "https://metadata.neuropong.game/");

        access = AppAccess1155(accessAddr);
        vault = AppStakingVault(vaultAddr);

        // Deploy tournament and rewards
        tournament =
            new Tournament(address(appToken), appCreator, treasury, 10 ether, 0, 0, 250, 100);

        rewards = new EpochRewards(address(appToken), appCreator);

        // Mint tokens to players
        vm.startPrank(admin);
        appToken.mint(player1, 10000 ether);
        appToken.mint(player2, 10000 ether);
        appToken.mint(player3, 10000 ether);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FULL WORKFLOW INTEGRATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Integration_CompleteAppLaunch() public {
        // Sanity check: verify all modules deployed correctly
        assertEq(address(access.APP()), address(appToken));
        assertEq(address(vault.APP()), address(appToken));
        assertEq(access.owner(), appCreator);
        assertEq(vault.owner(), appCreator);

        // Verify factory fee was paid
        assertEq(elta.balanceOf(treasury), CREATE_FEE);

        // Verify registry
        (address storedAccess, address storedVault, address storedEpochs) =
            factory.modulesByApp(address(appToken));
        assertEq(storedAccess, address(access));
        assertEq(storedVault, address(vault));
        assertTrue(storedEpochs != address(0));
    }

    function test_Integration_SeasonPassPurchaseAndStaking() public {
        // Configure season pass
        vm.prank(appCreator);
        access.setItem(
            1, // Season Pass
            100 ether,
            true, // Soulbound
            true,
            0,
            0,
            10000,
            "ipfs://season-pass-1"
        );

        uint256 initialSupply = appToken.totalSupply();

        // Player1 purchases season pass
        vm.startPrank(player1);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, keccak256("season_1"));
        vm.stopPrank();

        // Verify purchase
        assertEq(access.balanceOf(player1, 1), 1);

        // Verify tokens burned
        assertEq(appToken.totalSupply(), initialSupply - 100 ether);

        // Player1 stakes
        vm.startPrank(player1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);
        vm.stopPrank();

        assertEq(vault.stakedOf(player1), 1000 ether);
    }

    function test_Integration_FeatureGatingFullFlow() public {
        // Setup: Configure premium feature requiring stake + pass
        vm.prank(appCreator);
        access.setItem(1, 100 ether, true, true, 0, 0, 1000, "ipfs://pass");

        bytes32 premiumFeature = keccak256("premium_mode");
        vm.prank(appCreator);
        access.setFeatureGate(
            premiumFeature,
            AppAccess1155.FeatureGate({
                minStake: 500 ether,
                requiredItem: 1,
                requireBoth: true,
                active: true
            })
        );

        // Player1: No access (nothing)
        bool hasAccess = access.checkFeatureAccess(player1, premiumFeature, 0);
        assertFalse(hasAccess);

        // Player1: Stake but no pass (still no access)
        vm.startPrank(player1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);
        vm.stopPrank();

        hasAccess = access.checkFeatureAccess(player1, premiumFeature, vault.stakedOf(player1));
        assertFalse(hasAccess); // Need both

        // Player1: Buy pass
        vm.startPrank(player1);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        // Now has access
        hasAccess = access.checkFeatureAccess(player1, premiumFeature, vault.stakedOf(player1));
        assertTrue(hasAccess);
    }

    function test_Integration_TournamentFullWorkflow() public {
        // Configure premium tournament (requires stake)
        bytes32 tourneyAccess = keccak256("tournament_access");
        vm.prank(appCreator);
        access.setFeatureGate(
            tourneyAccess,
            AppAccess1155.FeatureGate({
                minStake: 100 ether,
                requiredItem: 0,
                requireBoth: false,
                active: true
            })
        );

        // Note: Tournament owner is appCreator

        // Players stake to qualify
        vm.startPrank(player1);
        appToken.approve(address(vault), 100 ether);
        vault.stake(100 ether);
        vm.stopPrank();

        vm.startPrank(player2);
        appToken.approve(address(vault), 100 ether);
        vault.stake(100 ether);
        vm.stopPrank();

        // Verify access
        assertTrue(access.checkFeatureAccess(player1, tourneyAccess, 100 ether));

        // Players enter tournament
        vm.prank(player1);
        appToken.approve(address(tournament), 10 ether);
        vm.prank(player1);
        tournament.enter();

        vm.prank(player2);
        appToken.approve(address(tournament), 10 ether);
        vm.prank(player2);
        tournament.enter();

        assertEq(tournament.pool(), 20 ether);

        // Verify tournament state
        (bool isFinalized, bool isActive, uint256 pool,,,,,) = tournament.getTournamentState();
        assertFalse(isFinalized);
        assertTrue(isActive);
        assertEq(pool, 20 ether);

        // Finalize (Merkle claim testing is in unit tests)
        vm.prank(appCreator);
        tournament.finalize(bytes32(uint256(1)));

        // Verify protocol fees collected
        uint256 expectedProtocol = (20 ether * 250) / 10000;
        assertEq(appToken.balanceOf(treasury), expectedProtocol);
    }

    function test_Integration_SeasonalRewardsFullFlow() public {
        // Owner starts season 1
        vm.startPrank(appCreator);
        rewards.startEpoch(uint64(block.timestamp), uint64(block.timestamp + 30 days));

        // Fund with 50K tokens
        appToken.approve(address(rewards), 50000 ether);
        rewards.fund(50000 ether);

        // Verify epoch state
        (uint64 start, uint64 end, bytes32 root, uint256 funded, uint256 claimed) =
            rewards.epochs(1);
        assertEq(start, uint64(block.timestamp));
        assertEq(end, uint64(block.timestamp + 30 days));
        assertEq(root, 0); // Not finalized yet
        assertEq(funded, 50000 ether);
        assertEq(claimed, 0);

        // Finalize (Merkle claim testing is in unit tests)
        rewards.finalizeEpoch(bytes32(uint256(1)));
        vm.stopPrank();

        // Verify finalized
        assertTrue(rewards.isEpochClaimable(1));
        assertEq(rewards.getEpochUtilization(1), 0); // 0% claimed so far
    }

    function test_Integration_MultipleAppsCoexist() public {
        // Deploy second app
        AppToken app2 = new AppToken("BrainWaves", "BWAVE", 18, MAX_SUPPLY, appCreator, admin);

        // Mint ELTA for second deployment
        vm.prank(factoryOwner);
        elta.mint(appCreator, CREATE_FEE);

        vm.prank(appCreator);
        elta.approve(address(factory), CREATE_FEE);

        vm.prank(appCreator);
        (address access2Addr, address vault2Addr,) =
            factory.deployModules(address(app2), "https://metadata.brainwaves/");

        AppAccess1155 access2 = AppAccess1155(access2Addr);
        AppStakingVault vault2 = AppStakingVault(vault2Addr);

        // Verify both apps work independently
        assertEq(address(access.APP()), address(appToken));
        assertEq(address(access2.APP()), address(app2));

        // Configure items for both apps
        vm.startPrank(appCreator);
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://app1-item");
        access2.setItem(1, 200 ether, false, true, 0, 0, 100, "ipfs://app2-item");
        vm.stopPrank();

        // Mint app2 tokens
        vm.prank(admin);
        app2.mint(player1, 10000 ether);

        // Player can interact with both
        vm.startPrank(player1);

        // Buy from app1
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));

        // Buy from app2
        app2.approve(address(access2), 200 ether);
        access2.purchase(1, 1, bytes32(0));

        vm.stopPrank();

        assertEq(access.balanceOf(player1, 1), 1);
        assertEq(access2.balanceOf(player1, 1), 1);
    }

    function test_Integration_StakeGateUnstakeFlow() public {
        // Configure premium feature (stake only)
        bytes32 premium = keccak256("premium");
        vm.prank(appCreator);
        access.setFeatureGate(
            premium,
            AppAccess1155.FeatureGate({
                minStake: 1000 ether,
                requiredItem: 0,
                requireBoth: false,
                active: true
            })
        );

        // Player1 doesn't have access
        assertFalse(access.checkFeatureAccess(player1, premium, 0));

        // Player1 stakes
        vm.startPrank(player1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);
        vm.stopPrank();

        // Now has access
        assertTrue(access.checkFeatureAccess(player1, premium, vault.stakedOf(player1)));

        // Player1 unstakes partially
        vm.prank(player1);
        vault.unstake(500 ether);

        // Loses access
        assertFalse(access.checkFeatureAccess(player1, premium, vault.stakedOf(player1)));

        // Stakes back
        vm.startPrank(player1);
        appToken.approve(address(vault), 500 ether);
        vault.stake(500 ether);
        vm.stopPrank();

        // Regains access
        assertTrue(access.checkFeatureAccess(player1, premium, vault.stakedOf(player1)));
    }

    function test_Integration_EconomicLoop() public {
        // Track token flow through the ecosystem
        uint256 initialCreatorBalance = appToken.balanceOf(appCreator);
        uint256 initialSupply = appToken.totalSupply();

        // Configure item
        vm.prank(appCreator);
        access.setItem(1, 100 ether, false, true, 0, 0, 0, "ipfs://item");

        // Players purchase (burns tokens)
        vm.startPrank(player1);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        vm.startPrank(player2);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        // Supply decreased by 200 tokens (deflationary!)
        assertEq(appToken.totalSupply(), initialSupply - 200 ether);

        // Creator distributes rewards via epoch
        vm.startPrank(appCreator);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(10000 ether);
        rewards.finalizeEpoch(bytes32(uint256(1)));
        vm.stopPrank();

        // Verify epoch funded (claims tested in unit tests)
        (,,, uint256 funded,) = rewards.epochs(1);
        assertEq(funded, 10000 ether);

        // Net result: 200 burned from purchases
        // Rewards are funded from existing supply (no new minting)
        assertEq(appToken.totalSupply(), initialSupply - 200 ether);
    }

    function test_Integration_TieredAccessSystem() public {
        // Setup tiered system
        vm.startPrank(appCreator);

        // Bronze pass (cheap, transferable)
        access.setItem(1, 50 ether, false, true, 0, 0, 0, "ipfs://bronze");

        // Silver pass (moderate, soulbound)
        access.setItem(2, 200 ether, true, true, 0, 0, 5000, "ipfs://silver");

        // Gold pass (expensive, soulbound, limited)
        access.setItem(3, 500 ether, true, true, 0, 0, 1000, "ipfs://gold");

        // Bronze feature (just pass)
        access.setFeatureGate(
            keccak256("bronze"),
            AppAccess1155.FeatureGate({
                minStake: 0,
                requiredItem: 1,
                requireBoth: false,
                active: true
            })
        );

        // Silver feature (pass + 100 stake)
        access.setFeatureGate(
            keccak256("silver"),
            AppAccess1155.FeatureGate({
                minStake: 100 ether,
                requiredItem: 2,
                requireBoth: true,
                active: true
            })
        );

        // Gold feature (pass + 500 stake)
        access.setFeatureGate(
            keccak256("gold"),
            AppAccess1155.FeatureGate({
                minStake: 500 ether,
                requiredItem: 3,
                requireBoth: true,
                active: true
            })
        );
        vm.stopPrank();

        // Player1 progresses through tiers
        vm.startPrank(player1);

        // Buy bronze
        appToken.approve(address(access), 50 ether);
        access.purchase(1, 1, bytes32(0));
        assertTrue(access.checkFeatureAccess(player1, keccak256("bronze"), 0));

        // Buy silver + stake
        appToken.approve(address(access), 200 ether);
        access.purchase(2, 1, bytes32(0));
        appToken.approve(address(vault), 100 ether);
        vault.stake(100 ether);
        assertTrue(access.checkFeatureAccess(player1, keccak256("silver"), vault.stakedOf(player1)));

        // Buy gold + stake more
        appToken.approve(address(access), 500 ether);
        access.purchase(3, 1, bytes32(0));
        appToken.approve(address(vault), 400 ether);
        vault.stake(400 ether);
        assertTrue(access.checkFeatureAccess(player1, keccak256("gold"), vault.stakedOf(player1)));
        vm.stopPrank();

        // Verify all tier ownership
        assertEq(access.balanceOf(player1, 1), 1);
        assertEq(access.balanceOf(player1, 2), 1);
        assertEq(access.balanceOf(player1, 3), 1);
        assertEq(vault.stakedOf(player1), 500 ether);
    }

    function test_Integration_CompleteSeason() public {
        // Month-long season with passes, staking, tournament, and rewards

        // Phase 1: Season launch
        vm.startPrank(appCreator);
        access.setItem(
            1,
            100 ether,
            true,
            true,
            uint64(block.timestamp),
            uint64(block.timestamp + 30 days),
            5000,
            "ipfs://season-1-pass"
        );
        vm.stopPrank();

        // Phase 2: Players buy passes
        vm.startPrank(player1);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        vm.startPrank(player2);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        // Phase 3: Players stake for benefits
        vm.startPrank(player1);
        appToken.approve(address(vault), 500 ether);
        vault.stake(500 ether);
        vm.stopPrank();

        // Phase 4: Mid-season tournament
        vm.startPrank(player1);
        appToken.approve(address(tournament), 10 ether);
        tournament.enter();
        vm.stopPrank();

        vm.startPrank(player2);
        appToken.approve(address(tournament), 10 ether);
        tournament.enter();
        vm.stopPrank();

        // Verify tournament pool
        assertEq(tournament.pool(), 20 ether);

        // Finalize tournament
        vm.prank(appCreator);
        tournament.finalize(bytes32(uint256(1)));

        // Phase 5: End-of-season rewards
        vm.startPrank(appCreator);
        rewards.startEpoch(uint64(block.timestamp), uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 20000 ether);
        rewards.fund(20000 ether);
        rewards.finalizeEpoch(bytes32(uint256(2)));
        vm.stopPrank();

        // Verify complete season flow
        // - Passes sold (burns 200 tokens)
        // - Players staked (500 locked)
        // - Tournament ran (20 entry fees, with protocol/burn fees)
        // - Rewards funded (20000 from creator treasury)

        // Verify all systems functional
        assertEq(access.balanceOf(player1, 1), 1); // Has pass
        assertEq(access.balanceOf(player2, 1), 1); // Has pass
        assertEq(vault.stakedOf(player1), 500 ether); // Has stake
        assertTrue(tournament.entered(player1)); // Entered tournament
        assertTrue(rewards.isEpochClaimable(1)); // Rewards ready
    }

    // ────────────────────────────────────────────────────────────────────────────
    // SANITY CHECK TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Sanity_TokenSupplyNeverIncreases() public {
        uint256 initialSupply = appToken.totalSupply();

        // Configure and sell items
        vm.prank(appCreator);
        access.setItem(1, 100 ether, false, true, 0, 0, 0, "ipfs://item");

        vm.startPrank(player1);
        appToken.approve(address(access), 300 ether);
        access.purchase(1, 3, bytes32(0));
        vm.stopPrank();

        // Supply should only decrease
        assertTrue(appToken.totalSupply() <= initialSupply);
        assertEq(appToken.totalSupply(), initialSupply - 300 ether);
    }

    function test_Sanity_StakingDoesNotChangeSupply() public {
        uint256 initialSupply = appToken.totalSupply();

        // Players stake
        vm.startPrank(player1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);
        vm.stopPrank();

        // Supply unchanged
        assertEq(appToken.totalSupply(), initialSupply);

        // Unstake
        vm.prank(player1);
        vault.unstake(1000 ether);

        // Still unchanged
        assertEq(appToken.totalSupply(), initialSupply);
    }

    function test_Sanity_AllModulesOwnedByCreator() public {
        // Verify ownership alignment
        assertEq(access.owner(), appCreator);
        assertEq(vault.owner(), appCreator);
        assertEq(appToken.owner(), appCreator);
        assertEq(tournament.owner(), appCreator);
        assertEq(rewards.owner(), appCreator);
    }

    function test_Sanity_ELTAFlowsToTreasury() public {
        uint256 treasuryBefore = elta.balanceOf(treasury);

        // Deploy another app (pays ELTA fee)
        AppToken app2 = new AppToken("App2", "APP2", 18, MAX_SUPPLY, appCreator, admin);

        vm.prank(appCreator);
        elta.approve(address(factory), CREATE_FEE);

        vm.prank(appCreator);
        factory.deployModules(address(app2), "https://test/");

        assertEq(elta.balanceOf(treasury), treasuryBefore + CREATE_FEE);
    }

    function test_Sanity_ProtocolFeesAccumulate() public {
        uint256 treasuryBefore = appToken.balanceOf(treasury);

        // Players enter tournament
        vm.prank(player1);
        appToken.approve(address(tournament), 10 ether);
        vm.prank(player1);
        tournament.enter();

        vm.prank(player2);
        appToken.approve(address(tournament), 10 ether);
        vm.prank(player2);
        tournament.enter();

        // Finalize
        vm.prank(appCreator);
        tournament.finalize(bytes32(0));

        // Protocol fee should be in treasury
        uint256 expectedFee = (20 ether * 250) / 10000;
        assertEq(appToken.balanceOf(treasury), treasuryBefore + expectedFee);
    }
}
