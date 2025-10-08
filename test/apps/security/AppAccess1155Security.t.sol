// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { AppAccess1155 } from "../../../src/apps/AppAccess1155.sol";
import { AppToken } from "../../../src/apps/AppToken.sol";
import { AppStakingVault } from "../../../src/apps/AppStakingVault.sol";

/**
 * @title AppAccess1155Security
 * @notice Comprehensive security testing for AppAccess1155
 * @dev Tests reentrancy, overflow, underflow, access control, and edge cases
 */
contract AppAccess1155SecurityTest is Test {
    AppAccess1155 public access;
    AppToken public appToken;
    AppStakingVault public vault;

    address public owner = makeAddr("owner");
    address public attacker = makeAddr("attacker");
    address public user1 = makeAddr("user1");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        appToken = new AppToken("TestApp", "TEST", 18, MAX_SUPPLY, owner, admin);
        vault = new AppStakingVault(address(appToken), owner);
        access = new AppAccess1155(
            address(appToken),
            address(vault),
            owner,
            "https://metadata.test/"
        );

        // Mint tokens to users
        vm.startPrank(admin);
        appToken.mint(user1, 10000 ether);
        appToken.mint(attacker, 10000 ether);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // REENTRANCY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ReentrancyProtection_Purchase() public {
        // Configure item
        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://item1");

        // Create malicious contract that attempts reentrancy
        ReentrancyAttacker attackContract = new ReentrancyAttacker(access, appToken);
        
        vm.prank(admin);
        appToken.mint(address(attackContract), 1000 ether);

        // Attempt reentrancy attack (should fail)
        vm.expectRevert();
        attackContract.attack(1, 1);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // INTEGER OVERFLOW/UNDERFLOW TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_NoOverflow_PriceCalculation() public {
        // Set max price
        vm.prank(owner);
        access.setItem(1, type(uint256).max, false, true, 0, 0, 0, "ipfs://item1");

        // Attempt to purchase should fail due to insufficient balance, not overflow
        vm.startPrank(user1);
        appToken.approve(address(access), type(uint256).max);
        
        vm.expectRevert(); // Will revert on burnFrom due to insufficient balance
        access.purchase(1, 2, bytes32(0)); // Would overflow if not protected
        vm.stopPrank();
    }

    function test_Security_NoUnderflow_SupplyTracking() public {
        // This tests that minted count doesn't underflow
        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 10, "ipfs://item1");

        // Purchase up to max
        vm.startPrank(user1);
        appToken.approve(address(access), 1000 ether);
        access.purchase(1, 10, bytes32(0));
        vm.stopPrank();

        // Try to purchase more (should fail cleanly)
        vm.startPrank(attacker);
        appToken.approve(address(access), 1000 ether);
        vm.expectRevert(AppAccess1155.SupplyExceeded.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ACCESS CONTROL TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_OnlyOwnerCanSetItem() public {
        vm.expectRevert();
        vm.prank(attacker);
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://item1");
    }

    function test_Security_OnlyOwnerCanToggleSoulbound() public {
        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://item1");

        vm.expectRevert();
        vm.prank(attacker);
        access.toggleSoulbound(1, true);
    }

    function test_Security_OnlyOwnerCanSetFeatureGate() public {
        vm.expectRevert();
        vm.prank(attacker);
        access.setFeatureGate(
            keccak256("premium"),
            AppAccess1155.FeatureGate({
                minStake: 1000 ether,
                requiredItem: 0,
                requireBoth: false,
                active: true
            })
        );
    }

    // ────────────────────────────────────────────────────────────────────────────
    // SOULBOUND ENFORCEMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_SoulboundCannotBeTransferred() public {
        // Configure soulbound item
        vm.prank(owner);
        access.setItem(1, 100 ether, true, true, 0, 0, 100, "ipfs://item1");

        // Purchase
        vm.startPrank(user1);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));

        // Attempt transfer (should fail)
        vm.expectRevert(AppAccess1155.SoulboundTransfer.selector);
        access.safeTransferFrom(user1, attacker, 1, 1, "");
        vm.stopPrank();
    }

    function test_Security_SoulboundCannotBeBatchTransferred() public {
        // Configure soulbound item
        vm.prank(owner);
        access.setItem(1, 100 ether, true, true, 0, 0, 100, "ipfs://item1");

        // Purchase
        vm.startPrank(user1);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));

        // Attempt batch transfer (should fail)
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 1;
        amounts[0] = 1;

        vm.expectRevert(AppAccess1155.SoulboundTransfer.selector);
        access.safeBatchTransferFrom(user1, attacker, ids, amounts, "");
        vm.stopPrank();
    }

    function test_Security_CanToggleSoulboundAfterMint() public {
        // Configure non-soulbound item
        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://item1");

        // Purchase
        vm.startPrank(user1);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        // Owner makes it soulbound
        vm.prank(owner);
        access.toggleSoulbound(1, true);

        // Now transfer should fail
        vm.startPrank(user1);
        vm.expectRevert(AppAccess1155.SoulboundTransfer.selector);
        access.safeTransferFrom(user1, attacker, 1, 1, "");
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // BURN MECHANISM TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_PurchaseActuallyBurns() public {
        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://item1");

        uint256 initialSupply = appToken.totalSupply();
        uint256 initialBalance = appToken.balanceOf(user1);

        vm.startPrank(user1);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        // Verify tokens were actually burned (supply decreased)
        assertEq(appToken.totalSupply(), initialSupply - 100 ether);
        assertEq(appToken.balanceOf(user1), initialBalance - 100 ether);
    }

    function test_Security_CannotPurchaseWithoutApproval() public {
        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://item1");

        // Don't approve tokens
        vm.expectRevert();
        vm.prank(user1);
        access.purchase(1, 1, bytes32(0));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // TIME WINDOW TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotPurchaseBeforeStart() public {
        uint64 startTime = uint64(block.timestamp + 1000);

        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, startTime, 0, 100, "ipfs://item1");

        vm.startPrank(user1);
        appToken.approve(address(access), 100 ether);
        vm.expectRevert(AppAccess1155.PurchaseTooEarly.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_Security_CannotPurchaseAfterEnd() public {
        uint64 endTime = uint64(block.timestamp + 1000);

        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, endTime, 100, "ipfs://item1");

        vm.warp(block.timestamp + 1001);

        vm.startPrank(user1);
        appToken.approve(address(access), 100 ether);
        vm.expectRevert(AppAccess1155.PurchaseTooLate.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_Security_TimeWindowEdgeCases() public {
        uint64 startTime = uint64(block.timestamp + 100);
        uint64 endTime = uint64(block.timestamp + 200);

        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, startTime, endTime, 100, "ipfs://item1");

        // At exact start time (should work)
        vm.warp(startTime);
        vm.startPrank(user1);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));

        // At exact end time (should work)
        vm.warp(endTime);
        appToken.approve(address(access), 100 ether);
        access.purchase(1, 1, bytes32(0));

        // One second after end (should fail)
        vm.warp(endTime + 1);
        appToken.approve(address(access), 100 ether);
        vm.expectRevert(AppAccess1155.PurchaseTooLate.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // SUPPLY CAP TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_SupplyCapEnforced() public {
        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 5, "ipfs://item1");

        vm.startPrank(user1);
        appToken.approve(address(access), 1000 ether);
        
        // Purchase up to cap
        access.purchase(1, 5, bytes32(0));

        // Attempt to purchase more (should fail)
        vm.expectRevert(AppAccess1155.SupplyExceeded.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_Security_SupplyCapRaceCondition() public {
        // Test that multiple purchases can't exceed cap via race
        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 10, "ipfs://item1");

        // User1 purchases 8
        vm.startPrank(user1);
        appToken.approve(address(access), 1000 ether);
        access.purchase(1, 8, bytes32(0));
        vm.stopPrank();

        // Attacker tries to purchase 5 (only 2 left)
        vm.startPrank(attacker);
        appToken.approve(address(access), 1000 ether);
        vm.expectRevert(AppAccess1155.SupplyExceeded.selector);
        access.purchase(1, 5, bytes32(0));
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // VIEW FUNCTION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ViewFunctionsNoSideEffects() public {
        vm.prank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://item1");

        // Call view functions
        access.checkPurchaseEligibility(user1, 1, 5);
        access.getPurchaseCost(1, 5);
        access.getRemainingSupply(1);
        access.checkFeatureAccess(user1, keccak256("premium"), 0);

        // Verify state hasn't changed
        (, , , , , , uint64 minted, ) = access.items(1);
        assertEq(minted, 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EDGE CASE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ZeroPriceItem() public {
        vm.prank(owner);
        access.setItem(1, 0, false, true, 0, 0, 100, "ipfs://item1");

        // Should be able to purchase for free
        vm.prank(user1);
        access.purchase(1, 1, bytes32(0));

        assertEq(access.balanceOf(user1, 1), 1);
    }

    function test_Security_InactiveItemCannotBePurchased() public {
        vm.prank(owner);
        access.setItem(1, 100 ether, false, false, 0, 0, 100, "ipfs://item1");

        vm.startPrank(user1);
        appToken.approve(address(access), 100 ether);
        vm.expectRevert(AppAccess1155.ItemInactive.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_Security_CanDeactivateAndReactivate() public {
        vm.startPrank(owner);
        access.setItem(1, 100 ether, false, true, 0, 0, 100, "ipfs://item1");
        
        // Deactivate
        access.setItemActive(1, false);
        vm.stopPrank();

        // Cannot purchase
        vm.startPrank(user1);
        appToken.approve(address(access), 100 ether);
        vm.expectRevert(AppAccess1155.ItemInactive.selector);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        // Reactivate
        vm.prank(owner);
        access.setItemActive(1, true);

        // Can purchase now
        vm.startPrank(user1);
        access.purchase(1, 1, bytes32(0));
        vm.stopPrank();

        assertEq(access.balanceOf(user1, 1), 1);
    }
}

// Malicious contract for reentrancy testing
contract ReentrancyAttacker {
    AppAccess1155 public access;
    AppToken public token;
    bool public attacking;

    constructor(AppAccess1155 _access, AppToken _token) {
        access = _access;
        token = _token;
    }

    function attack(uint256 id, uint256 amount) external {
        token.approve(address(access), type(uint256).max);
        attacking = true;
        access.purchase(id, amount, bytes32(0));
    }

    // Reentrancy attempt via ERC1155 callback
    function onERC1155Received(
        address,
        address,
        uint256 id,
        uint256,
        bytes memory
    ) external returns (bytes4) {
        if (attacking) {
            attacking = false;
            // Attempt reentrancy
            access.purchase(id, 1, bytes32(0));
        }
        return this.onERC1155Received.selector;
    }
}

