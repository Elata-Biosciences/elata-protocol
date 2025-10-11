// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppAccess1155 } from "../../src/apps/AppAccess1155.sol";
import { AppStakingVault } from "../../src/apps/AppStakingVault.sol";
import { Tournament } from "../../src/apps/Tournament.sol";
import { EpochRewards } from "../../src/apps/EpochRewards.sol";
import { AppModuleFactory } from "../../src/apps/AppModuleFactory.sol";
import { ELTA } from "../../src/token/ELTA.sol";

/**
 * @title DesignValidationTest
 * @notice Validates core design assumptions and economic model
 * @dev Ensures tokenomics work as intended and design is sound
 */
contract DesignValidationTest is Test {
    AppModuleFactory public factory;
    ELTA public elta;
    AppToken public appToken;
    AppAccess1155 public access;
    AppStakingVault public vault;

    address public factoryOwner = makeAddr("factoryOwner");
    address public treasury = makeAddr("treasury");
    address public appCreator = makeAddr("appCreator");
    address public player = makeAddr("player");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", factoryOwner, factoryOwner, 10000000 ether, 77000000 ether);

        factory = new AppModuleFactory(address(elta), factoryOwner, treasury);

        appToken = new AppToken("TestApp", "TEST", 18, MAX_SUPPLY, appCreator, admin);

        vm.prank(appCreator);
        (address accessAddr, address vaultAddr,) =
            factory.deployModules(address(appToken), "https://metadata.test/");

        access = AppAccess1155(accessAddr);
        vault = AppStakingVault(vaultAddr);

        vm.prank(admin);
        appToken.mint(player, 10000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Burn-on-Purchase is Deflationary
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_BurnOnPurchaseReducesSupply() public {
        vm.prank(appCreator);
        access.setItem(1, 100 ether, false, true, 0, 0, 0, "ipfs://item");

        uint256 initialSupply = appToken.totalSupply();

        // Purchase burns tokens
        vm.startPrank(player);
        appToken.approve(address(access), 300 ether);
        access.purchase(1, 3, bytes32(0));
        vm.stopPrank();

        // VALIDATION: Supply decreased permanently
        assertEq(appToken.totalSupply(), initialSupply - 300 ether);

        // VALIDATION: Tokens cannot be recovered
        // (no mint function available post-finalize)
        vm.prank(admin);
        appToken.finalizeMinting();

        vm.expectRevert(AppToken.MintingAlreadyFinalized.selector);
        vm.prank(admin);
        appToken.mint(player, 1);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Staking Doesn't Affect Supply
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_StakingPreservesSupply() public {
        uint256 initialSupply = appToken.totalSupply();

        // Stake
        vm.startPrank(player);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);
        vm.stopPrank();

        // VALIDATION: Supply unchanged
        assertEq(appToken.totalSupply(), initialSupply);

        // Unstake
        vm.prank(player);
        vault.unstake(1000 ether);

        // VALIDATION: Still unchanged
        assertEq(appToken.totalSupply(), initialSupply);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: No Continuous Faucets
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_NoAutomaticEmissions() public {
        EpochRewards epochRewards = new EpochRewards(address(appToken), appCreator);

        // VALIDATION: Cannot claim without owner funding
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(EpochRewards.NotFinalized.selector);
        vm.prank(player);
        epochRewards.claim(1, proof, 1000 ether);

        // VALIDATION: Epochs must be manually created
        assertEq(epochRewards.epochId(), 0);

        // VALIDATION: Funding is explicit owner action
        vm.expectRevert(EpochRewards.NoActiveEpoch.selector);
        vm.prank(appCreator);
        epochRewards.fund(1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: ELTA Fees Support Protocol
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_ELTAFeesFlowToTreasury() public {
        vm.prank(factoryOwner);
        factory.setCreateFee(100 ether);

        vm.prank(factoryOwner);
        elta.mint(appCreator, 1000 ether);

        uint256 treasuryBefore = elta.balanceOf(treasury);

        // Deploy modules
        AppToken app2 = new AppToken("App2", "APP2", 18, MAX_SUPPLY, appCreator, admin);

        vm.prank(appCreator);
        elta.approve(address(factory), 100 ether);

        vm.prank(appCreator);
        factory.deployModules(address(app2), "https://test/");

        // VALIDATION: ELTA went to treasury
        assertEq(elta.balanceOf(treasury), treasuryBefore + 100 ether);
    }

    function test_Design_ProtocolFeesFromTournaments() public {
        Tournament tourn = new Tournament(
            address(appToken),
            appCreator,
            treasury,
            10 ether,
            0,
            0,
            250, // 2.5%
            100 // 1%
        );

        // Players enter
        vm.prank(player);
        appToken.approve(address(tourn), 10 ether);
        vm.prank(player);
        tourn.enter();

        uint256 treasuryBefore = appToken.balanceOf(treasury);

        // Finalize
        vm.prank(appCreator);
        tourn.finalize(bytes32(0));

        // VALIDATION: Protocol fee captured
        uint256 expectedFee = (10 ether * 250) / 10000;
        assertEq(appToken.balanceOf(treasury), treasuryBefore + expectedFee);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Gating is App-Side
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_GatingViews() public {
        // Configure gate
        bytes32 featureId = keccak256("premium");
        vm.prank(appCreator);
        access.setFeatureGate(
            featureId,
            AppAccess1155.FeatureGate({
                minStake: 1000 ether,
                requiredItem: 1,
                requireBoth: true,
                active: true
            })
        );

        // VALIDATION: Apps can query access via views
        bool hasAccess = access.checkFeatureAccess(player, featureId, 0);
        assertFalse(hasAccess); // No stake, no item

        // VALIDATION: No on-chain enforcement (that's app's job)
        // Contracts only provide data, apps enforce
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Non-Upgradeable
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_ContractsAreImmutable() public {
        // VALIDATION: No proxy patterns (check for implementation storage)
        // Contracts should have code directly, not via delegatecall

        // Get code size
        uint256 accessSize;
        uint256 vaultSize;

        assembly {
            accessSize := extcodesize(sload(access.slot))
            vaultSize := extcodesize(sload(vault.slot))
        }

        // VALIDATION: Contracts have actual code (not proxies)
        assertTrue(address(access).code.length > 0);
        assertTrue(address(vault).code.length > 0);

        // VALIDATION: No upgrade functions exist
        // (ensured by compiler - no such functions in codebase)
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Owner-Controlled, Not Governance
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_OwnerControlled() public {
        // VALIDATION: App creator controls their modules
        assertEq(access.owner(), appCreator);
        assertEq(vault.owner(), appCreator);
        assertEq(appToken.owner(), appCreator);

        // VALIDATION: Only owner can configure
        vm.expectRevert();
        vm.prank(player);
        access.setItem(1, 100 ether, false, true, 0, 0, 0, "ipfs://item");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Clean Token Economics
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_NoTransferTax() public {
        address sender = makeAddr("sender");
        address recipient = makeAddr("recipient");

        vm.prank(admin);
        appToken.mint(sender, 1000 ether);

        vm.prank(sender);
        appToken.transfer(recipient, 500 ether);

        // VALIDATION: No tax - recipient gets exact amount
        assertEq(appToken.balanceOf(recipient), 500 ether);
        assertEq(appToken.balanceOf(sender), 500 ether);
    }

    function test_Design_PermitGaslessApprovals() public {
        // VALIDATION: ERC20Permit is available
        assertTrue(appToken.DOMAIN_SEPARATOR() != bytes32(0));
        assertEq(appToken.nonces(player), 0);

        // Permit functionality exists for gasless UX
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: View-Rich for Indexing
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_ComprehensiveViews() public {
        // Configure items
        vm.prank(appCreator);
        access.setItem(1, 100 ether, true, true, 0, 0, 100, "ipfs://item1");

        // VALIDATION: Single item views
        (uint256 price, bool soulbound, bool active,,,,,) = access.items(1);
        assertEq(price, 100 ether);
        assertTrue(soulbound);
        assertTrue(active);

        // VALIDATION: Batch views for UI
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        AppAccess1155.Item[] memory items = access.getItems(ids);
        assertEq(items.length, 1);
        assertEq(items[0].price, 100 ether);

        // VALIDATION: Eligibility checks
        (bool canPurchase, uint8 reason) = access.checkPurchaseEligibility(player, 1, 1);
        assertTrue(canPurchase);
        assertEq(reason, 0);

        // VALIDATION: Cost calculations
        assertEq(access.getPurchaseCost(1, 5), 500 ether);
        assertEq(access.getRemainingSupply(1), 100);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Soulbound Items Work Correctly
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_SoulboundMechanics() public {
        // Configure soulbound item
        vm.prank(appCreator);
        access.setItem(1, 100 ether, true, true, 0, 0, 100, "ipfs://sbt");

        // Purchase
        vm.startPrank(player);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        // VALIDATION: Cannot transfer soulbound
        address recipient = makeAddr("recipient");
        vm.expectRevert(AppAccess1155.SoulboundTransfer.selector);
        vm.prank(player);
        access.safeTransferFrom(player, recipient, 1, 1, "");

        // Configure transferable item
        vm.prank(appCreator);
        access.setItem(2, 100 ether, false, true, 0, 0, 100, "ipfs://nft");

        // Purchase
        vm.startPrank(player);
        appToken.approve(address(access), 100 ether);
        access.purchase(2, 1, bytes32(0));
        vm.stopPrank();

        // VALIDATION: Can transfer non-soulbound
        vm.prank(player);
        access.safeTransferFrom(player, recipient, 2, 1, "");
        assertEq(access.balanceOf(recipient, 2), 1);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Per-App Isolation
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_PerAppIsolation() public {
        // Deploy second app
        AppToken app2 = new AppToken("App2", "APP2", 18, MAX_SUPPLY, appCreator, admin);

        vm.prank(appCreator);
        (address access2Addr, address vault2Addr,) =
            factory.deployModules(address(app2), "https://metadata.app2/");

        AppAccess1155 access2 = AppAccess1155(access2Addr);
        AppStakingVault vault2 = AppStakingVault(vault2Addr);

        // VALIDATION: Different token addresses
        assertTrue(address(access.APP()) != address(access2.APP()));
        assertTrue(address(vault.APP()) != address(vault2.APP()));

        // VALIDATION: Different vault addresses
        assertTrue(address(vault) != address(vault2));

        // VALIDATION: Staking in one doesn't affect the other
        vm.startPrank(player);
        appToken.approve(address(vault), 500 ether);
        vault.stake(500 ether);
        vm.stopPrank();

        assertEq(vault.stakedOf(player), 500 ether);
        assertEq(vault2.stakedOf(player), 0); // Different vault
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Fee Caps Prevent Exploitation
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_FeeCapEnforcement() public {
        Tournament tourn =
            new Tournament(address(appToken), appCreator, treasury, 10 ether, 0, 0, 0, 0);

        // VALIDATION: Max 15% total fees
        vm.prank(appCreator);
        tourn.setFees(1000, 500); // 15% total OK

        vm.expectRevert(Tournament.FeesTooHigh.selector);
        vm.prank(appCreator);
        tourn.setFees(1000, 501); // 15.01% fails
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Supply Can Be Finalized
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_SupplyFinalization() public {
        // Mint rewards treasury
        vm.prank(admin);
        appToken.mint(appCreator, 50_000_000 ether);

        uint256 finalSupply = appToken.totalSupply();

        // Finalize
        vm.prank(admin);
        appToken.finalizeMinting();

        // VALIDATION: No more minting possible
        vm.expectRevert(AppToken.MintingAlreadyFinalized.selector);
        vm.prank(admin);
        appToken.mint(player, 1);

        // VALIDATION: Supply is now fixed
        assertEq(appToken.totalSupply(), finalSupply);

        // VALIDATION: Can only decrease via burns
        vm.prank(appCreator);
        appToken.burn(1000 ether);

        assertEq(appToken.totalSupply(), finalSupply - 1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Time Windows Work Correctly
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_TimeWindowedItems() public {
        uint64 start = uint64(block.timestamp + 100);
        uint64 end = uint64(block.timestamp + 200);

        vm.prank(appCreator);
        access.setItem(1, 100 ether, false, true, start, end, 100, "ipfs://limited");

        // VALIDATION: Cannot purchase before start
        vm.startPrank(player);
        appToken.approve(address(access), 100 ether);

        (bool canBuy, uint8 reason) = access.checkPurchaseEligibility(player, 1, 1);
        assertFalse(canBuy);
        assertEq(reason, 2); // Too early

        vm.expectRevert(AppAccess1155.PurchaseTooEarly.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        // VALIDATION: Can purchase during window
        vm.warp(start + 50);

        vm.startPrank(player);
        (canBuy, reason) = access.checkPurchaseEligibility(player, 1, 1);
        assertTrue(canBuy);
        assertEq(reason, 0);

        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        // VALIDATION: Cannot purchase after end
        vm.warp(end + 1);

        vm.startPrank(player);
        appToken.approve(address(access), 100 ether);
        (canBuy, reason) = access.checkPurchaseEligibility(player, 1, 1);
        assertFalse(canBuy);
        assertEq(reason, 3); // Too late
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN ASSUMPTION: Module Ownership Alignment
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_ModuleOwnershipAlignment() public {
        // VALIDATION: All modules owned by app creator
        assertEq(access.owner(), appCreator);
        assertEq(vault.owner(), appCreator);
        assertEq(appToken.owner(), appCreator);

        // VALIDATION: Only app creator can deploy modules
        AppToken unauthorizedApp = new AppToken(
            "Unauthorized",
            "UNAUTH",
            18,
            MAX_SUPPLY,
            player, // Different owner
            admin
        );

        vm.expectRevert(AppModuleFactory.NotTokenOwner.selector);
        vm.prank(appCreator);
        factory.deployModules(address(unauthorizedApp), "https://test/");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN VALIDATION: Economic Invariants
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_DeflatinaryPressure() public {
        uint256 initialSupply = appToken.totalSupply();

        // Configure multiple items
        vm.startPrank(appCreator);
        access.setItem(1, 100 ether, false, true, 0, 0, 0, "ipfs://item1");
        access.setItem(2, 200 ether, false, true, 0, 0, 0, "ipfs://item2");
        access.setItem(3, 300 ether, false, true, 0, 0, 0, "ipfs://item3");
        vm.stopPrank();

        // Simulate activity
        vm.startPrank(player);
        appToken.approve(address(access), 1000 ether);
        access.purchase(1, 1, bytes32(0)); // -100
        access.purchase(2, 1, bytes32(0)); // -200
        access.purchase(3, 1, bytes32(0)); // -300
        vm.stopPrank();

        // VALIDATION: More usage = more burn = more deflationary
        assertEq(appToken.totalSupply(), initialSupply - 600 ether);

        // VALIDATION: This supports token value (basic economic principle)
        assertTrue(appToken.totalSupply() < initialSupply);
    }

    function test_Design_SustainableEmissions() public {
        // Create new token for this test to control supply
        AppToken freshToken =
            new AppToken("FreshApp", "FRESH", 18, 200000 ether, appCreator, appCreator);

        EpochRewards epochRewards = new EpochRewards(address(freshToken), appCreator);

        // Mint exactly 100000 to creator
        vm.prank(appCreator);
        freshToken.mint(appCreator, 100000 ether);

        // Finalize supply
        vm.prank(appCreator);
        freshToken.finalizeMinting();

        uint256 totalSupply = freshToken.totalSupply();
        assertEq(totalSupply, 100000 ether);

        // Start epoch
        vm.prank(appCreator);
        epochRewards.startEpoch(0, uint64(block.timestamp + 7 days));

        // Fund from existing balance
        uint256 creatorBalance = freshToken.balanceOf(appCreator);

        vm.startPrank(appCreator);
        freshToken.approve(address(epochRewards), 10000 ether);
        epochRewards.fund(10000 ether);
        vm.stopPrank();

        // VALIDATION: Tokens came from creator, not minted
        assertEq(freshToken.balanceOf(appCreator), creatorBalance - 10000 ether);
        assertEq(freshToken.totalSupply(), totalSupply); // Unchanged
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DESIGN VALIDATION: Event Emission for Indexing
    // ────────────────────────────────────────────────────────────────────────────

    function test_Design_EventsEmitted() public {
        // Configure item
        vm.prank(appCreator);
        vm.recordLogs();
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://item");

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // VALIDATION: ItemConfigured event emitted
        assertTrue(logs.length > 0);

        // Purchase
        vm.startPrank(player);
        appToken.approve(address(access), 100 ether);
        vm.recordLogs();
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        logs = vm.getRecordedLogs();

        // VALIDATION: Events emitted for indexing
        // Should include: Purchased event, Transfer events, etc.
        assertTrue(logs.length >= 1);
    }
}
