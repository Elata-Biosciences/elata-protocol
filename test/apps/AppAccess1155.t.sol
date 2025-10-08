// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { AppAccess1155 } from "../../src/apps/AppAccess1155.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppStakingVault } from "../../src/apps/AppStakingVault.sol";

contract AppAccess1155Test is Test {
    AppAccess1155 public access;
    AppToken public appToken;
    AppStakingVault public vault;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public admin = makeAddr("admin");

    uint256 public constant ITEM_PRICE = 100 ether;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    event ItemConfigured(uint256 indexed id, AppAccess1155.Item item);
    event Purchased(
        address indexed user,
        uint256 indexed id,
        uint256 amount,
        uint256 cost
    );
    event SoulboundToggled(uint256 indexed id, bool soulbound);
    event FeatureGateSet(bytes32 indexed featureId, AppAccess1155.FeatureGate gate);

    function setUp() public {
        // Deploy app token
        appToken = new AppToken("TestApp", "TEST", 18, MAX_SUPPLY, owner, admin);

        // Deploy staking vault
        vault = new AppStakingVault(address(appToken), owner);

        // Deploy access control
        access = new AppAccess1155(
            address(appToken),
            address(vault),
            owner,
            "https://metadata.test/"
        );

        // Mint tokens to users
        vm.startPrank(admin);
        appToken.mint(user1, 10000 ether);
        appToken.mint(user2, 10000 ether);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public {
        assertEq(address(access.APP()), address(appToken));
        assertEq(address(access.STAKING()), address(vault));
        assertEq(access.owner(), owner);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ITEM CONFIGURATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_SetItem() public {
        vm.prank(owner);
        access.setItem(
            1, // id
            ITEM_PRICE, // price
            false, // not soulbound
            true, // active
            0, // no start time
            0, // no end time
            100, // max supply
            "ipfs://item1"
        );

        (
            uint256 price,
            bool soulbound,
            bool active,
            uint64 startTime,
            uint64 endTime,
            uint64 maxSupply,
            uint64 minted,
            string memory uri_
        ) = access.items(1);

        assertEq(price, ITEM_PRICE);
        assertFalse(soulbound);
        assertTrue(active);
        assertEq(startTime, 0);
        assertEq(endTime, 0);
        assertEq(maxSupply, 100);
        assertEq(minted, 0);
        assertEq(uri_, "ipfs://item1");
    }

    function test_RevertWhen_SetItemUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 100, "ipfs://item1");
    }

    function test_SetItemActive() public {
        // Configure item
        vm.startPrank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 100, "ipfs://item1");

        // Deactivate
        access.setItemActive(1, false);
        vm.stopPrank();

        (, , bool active, , , , , ) = access.items(1);
        assertFalse(active);
    }

    function test_ToggleSoulbound() public {
        vm.startPrank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 100, "ipfs://item1");

        vm.expectEmit(true, true, true, true);
        emit SoulboundToggled(1, true);

        access.toggleSoulbound(1, true);
        vm.stopPrank();

        (, bool soulbound, , , , , , ) = access.items(1);
        assertTrue(soulbound);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // PURCHASE TESTS (BURN-ON-PURCHASE)
    // ────────────────────────────────────────────────────────────────────────────

    function test_Purchase() public {
        // Configure item
        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 100, "ipfs://item1");

        uint256 amount = 5;
        uint256 cost = ITEM_PRICE * amount;
        uint256 initialSupply = appToken.totalSupply();

        // Approve and purchase
        vm.startPrank(user1);
        appToken.approve(address(access), cost);

        vm.expectEmit(true, true, true, true);
        emit Purchased(user1, 1, amount, cost);

        access.purchase(1, amount, bytes32(0));
        vm.stopPrank();

        // Verify NFT balance
        assertEq(access.balanceOf(user1, 1), amount);

        // Verify tokens were burned
        assertEq(appToken.totalSupply(), initialSupply - cost);

        // Verify minted count
        (, , , , , , uint64 minted, ) = access.items(1);
        assertEq(minted, amount);
    }

    function test_RevertWhen_PurchaseInactiveItem() public {
        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, false, 0, 0, 100, "ipfs://item1");

        vm.startPrank(user1);
        appToken.approve(address(access), ITEM_PRICE);

        vm.expectRevert(AppAccess1155.ItemInactive.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_RevertWhen_PurchaseTooEarly() public {
        uint64 startTime = uint64(block.timestamp + 1000);

        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, true, startTime, 0, 100, "ipfs://item1");

        vm.startPrank(user1);
        appToken.approve(address(access), ITEM_PRICE);

        vm.expectRevert(AppAccess1155.PurchaseTooEarly.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_RevertWhen_PurchaseTooLate() public {
        uint64 endTime = uint64(block.timestamp + 1000);

        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, endTime, 100, "ipfs://item1");

        // Warp past end time
        vm.warp(block.timestamp + 1001);

        vm.startPrank(user1);
        appToken.approve(address(access), ITEM_PRICE);

        vm.expectRevert(AppAccess1155.PurchaseTooLate.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_RevertWhen_PurchaseExceedsSupply() public {
        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 10, "ipfs://item1");

        vm.startPrank(user1);
        appToken.approve(address(access), ITEM_PRICE * 11);

        vm.expectRevert(AppAccess1155.SupplyExceeded.selector);
        access.purchase(1, 11, bytes32(0));
        vm.stopPrank();
    }

    function test_PurchaseUpToMaxSupply() public {
        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 10, "ipfs://item1");

        // Purchase exactly max supply
        vm.startPrank(user1);
        appToken.approve(address(access), ITEM_PRICE * 10);
        access.purchase(1, 10, bytes32(0));
        vm.stopPrank();

        assertEq(access.balanceOf(user1, 1), 10);

        // Try to purchase one more
        vm.startPrank(user2);
        appToken.approve(address(access), ITEM_PRICE);
        vm.expectRevert(AppAccess1155.SupplyExceeded.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // SOULBOUND TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_SoulboundTransferBlocked() public {
        // Configure soulbound item
        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, true, true, 0, 0, 100, "ipfs://item1");

        // Purchase
        vm.startPrank(user1);
        appToken.approve(address(access), ITEM_PRICE);
        access.purchase(1, 1, bytes32(0));

        // Try to transfer (should fail)
        vm.expectRevert(AppAccess1155.SoulboundTransfer.selector);
        access.safeTransferFrom(user1, user2, 1, 1, "");
        vm.stopPrank();
    }

    function test_TransferableItemCanMove() public {
        // Configure transferable item
        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 100, "ipfs://item1");

        // Purchase
        vm.startPrank(user1);
        appToken.approve(address(access), ITEM_PRICE);
        access.purchase(1, 1, bytes32(0));

        // Transfer (should succeed)
        access.safeTransferFrom(user1, user2, 1, 1, "");
        vm.stopPrank();

        assertEq(access.balanceOf(user1, 1), 0);
        assertEq(access.balanceOf(user2, 1), 1);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FEATURE GATE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_SetFeatureGate() public {
        bytes32 featureId = keccak256("premium_mode");

        AppAccess1155.FeatureGate memory gate = AppAccess1155.FeatureGate({
            minStake: 1000 ether,
            requiredItem: 1,
            requireBoth: true,
            active: true
        });

        vm.expectEmit(true, true, true, true);
        emit FeatureGateSet(featureId, gate);

        vm.prank(owner);
        access.setFeatureGate(featureId, gate);

        (uint256 minStake, uint256 requiredItem, bool requireBoth, bool active) =
            access.gates(featureId);

        assertEq(minStake, 1000 ether);
        assertEq(requiredItem, 1);
        assertTrue(requireBoth);
        assertTrue(active);
    }

    function test_RevertWhen_SetFeatureGateUnauthorized() public {
        bytes32 featureId = keccak256("premium_mode");

        AppAccess1155.FeatureGate memory gate = AppAccess1155.FeatureGate({
            minStake: 1000 ether,
            requiredItem: 0,
            requireBoth: false,
            active: true
        });

        vm.expectRevert();
        vm.prank(user1);
        access.setFeatureGate(featureId, gate);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // URI TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_URI() public {
        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 100, "ipfs://custom1");

        assertEq(access.uri(1), "ipfs://custom1");
    }

    function test_URIFallsBackToBase() public {
        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 100, "");

        // Should use base URI
        assertEq(access.uri(1), "https://metadata.test/");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUZZ TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_Purchase(uint256 amount) public {
        amount = bound(amount, 1, 100);

        vm.prank(owner);
        access.setItem(1, ITEM_PRICE, false, true, 0, 0, 0, "ipfs://item1");

        uint256 cost = ITEM_PRICE * amount;

        vm.startPrank(user1);
        appToken.approve(address(access), cost);
        access.purchase(1, amount, bytes32(0));
        vm.stopPrank();

        assertEq(access.balanceOf(user1, 1), amount);
    }
}

