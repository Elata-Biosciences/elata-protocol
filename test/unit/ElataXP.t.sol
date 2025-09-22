// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ElataXP } from "../../src/experience/ElataXP.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract ElataXPTest is Test {
    ElataXP public xp;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public minter = makeAddr("minter");

    function setUp() public {
        xp = new ElataXP(admin);
    }

    function test_Deployment() public {
        assertEq(xp.name(), "Elata XP");
        assertEq(xp.symbol(), "ELTAXP");
        assertEq(xp.decimals(), 18);
        assertEq(xp.totalSupply(), 0);
        assertEq(xp.DECAY_WINDOW(), 14 days);
        assertEq(xp.MIN_DECAY_INTERVAL(), 1 hours);

        assertTrue(xp.hasRole(xp.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(xp.hasRole(xp.XP_MINTER_ROLE(), admin));
        assertTrue(xp.hasRole(xp.KEEPER_ROLE(), admin));
    }

    function test_RevertWhen_DeploymentZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new ElataXP(address(0));
    }

    function test_Award() public {
        uint256 amount = 1000 ether;

        vm.prank(admin);
        xp.award(user1, amount);

        assertEq(xp.balanceOf(user1), amount);
        assertEq(xp.totalSupply(), amount);

        // Check that user is auto-delegated to self
        assertEq(xp.delegates(user1), user1);
        assertEq(xp.getVotes(user1), amount);
    }

    function test_RevertWhen_AwardZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        xp.award(address(0), 1000 ether);
    }

    function test_RevertWhen_AwardZeroAmount() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(admin);
        xp.award(user1, 0);
    }

    function test_RevertWhen_AwardUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        xp.award(user1, 1000 ether);
    }

    function test_Revoke() public {
        uint256 amount = 1000 ether;
        uint256 revokeAmount = 300 ether;

        vm.startPrank(admin);
        xp.award(user1, amount);
        xp.revoke(user1, revokeAmount);
        vm.stopPrank();

        assertEq(xp.balanceOf(user1), amount - revokeAmount);
        assertEq(xp.totalSupply(), amount - revokeAmount);
        assertEq(xp.getVotes(user1), amount - revokeAmount);
    }

    function test_RevertWhen_RevokeZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        xp.revoke(address(0), 1000 ether);
    }

    function test_RevertWhen_RevokeZeroAmount() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(admin);
        xp.revoke(user1, 0);
    }

    function test_RevertWhen_RevokeUnauthorized() public {
        vm.prank(admin);
        xp.award(user1, 1000 ether);

        vm.expectRevert();
        vm.prank(user1);
        xp.revoke(user1, 500 ether);
    }

    function test_TransfersDisabled() public {
        vm.prank(admin);
        xp.award(user1, 1000 ether);

        vm.expectRevert(Errors.TransfersDisabled.selector);
        vm.prank(user1);
        xp.transfer(user2, 500 ether);
    }

    function test_TransferFromDisabled() public {
        vm.startPrank(admin);
        xp.award(user1, 1000 ether);
        vm.stopPrank();

        vm.prank(user1);
        xp.approve(user2, 500 ether);

        vm.expectRevert(Errors.TransfersDisabled.selector);
        vm.prank(user2);
        xp.transferFrom(user1, user2, 500 ether);
    }

    function test_GetPastXP() public {
        uint256 amount1 = 1000 ether;
        uint256 amount2 = 500 ether;

        vm.prank(admin);
        xp.award(user1, amount1);

        vm.roll(block.number + 1);
        uint256 block1 = block.number - 1; // Previous block

        vm.prank(admin);
        xp.award(user1, amount2);

        vm.roll(block.number + 1);
        uint256 block2 = block.number - 1; // Previous block

        assertEq(xp.getPastXP(user1, block1), amount1);
        assertEq(xp.getPastXP(user1, block2), amount1 + amount2);
    }

    function test_Delegation() public {
        vm.prank(admin);
        xp.award(user1, 1000 ether);

        // User should be auto-delegated to self
        assertEq(xp.delegates(user1), user1);

        // User can delegate to someone else
        vm.prank(user1);
        xp.delegate(user2);

        assertEq(xp.delegates(user1), user2);
        assertEq(xp.getVotes(user1), 0);
        assertEq(xp.getVotes(user2), 1000 ether);
    }

    function test_Permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        vm.prank(admin);
        xp.award(owner, 1000 ether);

        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    xp.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                            ),
                            owner,
                            user1,
                            500 ether,
                            xp.nonces(owner),
                            deadline
                        )
                    )
                )
            )
        );

        xp.permit(owner, user1, 500 ether, deadline, v, r, s);
        assertEq(xp.allowance(owner, user1), 500 ether);
    }

    function test_AdminCanAwardXP() public {
        // Test that admin (who has XP_MINTER_ROLE by default) can award XP
        vm.prank(admin);
        xp.award(user1, 1000 ether);

        assertEq(xp.balanceOf(user1), 1000 ether);
        assertEq(xp.totalSupply(), 1000 ether);

        // Verify auto-delegation occurred
        assertEq(xp.delegates(user1), user1);
        assertEq(xp.getVotes(user1), 1000 ether);
    }

    function test_RevokeMinterRole() public {
        vm.startPrank(admin);
        xp.grantRole(xp.XP_MINTER_ROLE(), minter);
        xp.revokeRole(xp.XP_MINTER_ROLE(), minter);
        vm.stopPrank();

        assertFalse(xp.hasRole(xp.XP_MINTER_ROLE(), minter));

        vm.expectRevert();
        vm.prank(minter);
        xp.award(user1, 1000 ether);
    }

    function test_MultipleAwards() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 300 ether;
        uint256 amount3 = 200 ether;

        vm.startPrank(admin);
        xp.award(user1, amount1);
        xp.award(user1, amount2);
        xp.award(user2, amount3);
        vm.stopPrank();

        assertEq(xp.balanceOf(user1), amount1 + amount2);
        assertEq(xp.balanceOf(user2), amount3);
        assertEq(xp.totalSupply(), amount1 + amount2 + amount3);
    }

    function test_CheckpointTracking() public {
        vm.prank(admin);
        xp.award(user1, 1000 ether);

        vm.roll(block.number + 1);
        uint256 block1 = block.number - 1;

        vm.roll(block.number + 4);
        vm.prank(admin);
        xp.award(user1, 500 ether);

        vm.roll(block.number + 1);
        uint256 block2 = block.number - 1;

        vm.roll(block.number + 2);
        vm.prank(admin);
        xp.revoke(user1, 200 ether);

        vm.roll(block.number + 1);
        uint256 block3 = block.number - 1;

        // Check historical balances
        assertEq(xp.getPastXP(user1, block1), 1000 ether);
        assertEq(xp.getPastXP(user1, block2), 1500 ether);
        assertEq(xp.getPastXP(user1, block3), 1300 ether);
        assertEq(xp.balanceOf(user1), 1300 ether);
    }

    function test_XPDecayMechanism() public {
        vm.prank(admin);
        xp.award(user1, 1000 ether);

        // At start, effective balance should equal actual balance
        assertEq(xp.effectiveBalance(user1), 1000 ether);

        // After 7 days (half decay window), effective balance should be ~50%
        vm.warp(block.timestamp + 7 days);
        uint256 halfDecayBalance = xp.effectiveBalance(user1);
        assertApproxEqRel(halfDecayBalance, 500 ether, 0.01e18);

        // After 14 days (full decay window), effective balance should be 0
        vm.warp(block.timestamp + 7 days);
        assertEq(xp.effectiveBalance(user1), 0);

        // Actual balance should still be 1000 until decay is applied
        assertEq(xp.balanceOf(user1), 1000 ether);

        // Apply decay
        xp.updateUserDecay(user1);
        assertEq(xp.balanceOf(user1), 0);
    }

    function test_BatchDecayUpdate() public {
        // Give XP to multiple users
        vm.startPrank(admin);
        xp.award(user1, 1000 ether);
        xp.award(user2, 500 ether);
        vm.stopPrank();

        // Fast forward past decay window
        vm.warp(block.timestamp + 15 days);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        // Wait for initial interval to pass
        vm.warp(block.timestamp + 2 hours);

        vm.prank(admin);
        xp.batchUpdateDecay(users);

        assertEq(xp.balanceOf(user1), 0);
        assertEq(xp.balanceOf(user2), 0);
    }

    function testFuzz_Award(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(admin);
        xp.award(user1, amount);

        assertEq(xp.balanceOf(user1), amount);
        assertEq(xp.getVotes(user1), amount);
    }

    function testFuzz_Revoke(uint256 awardAmount, uint256 revokeAmount) public {
        awardAmount = bound(awardAmount, 1, type(uint128).max);
        revokeAmount = bound(revokeAmount, 1, awardAmount);

        vm.startPrank(admin);
        xp.award(user1, awardAmount);
        xp.revoke(user1, revokeAmount);
        vm.stopPrank();

        assertEq(xp.balanceOf(user1), awardAmount - revokeAmount);
        assertEq(xp.getVotes(user1), awardAmount - revokeAmount);
    }
}
