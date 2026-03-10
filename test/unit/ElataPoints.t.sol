// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElataPoints} from "../../src/experience/ElataPoints.sol";
import {Errors} from "../../src/utils/Errors.sol";
import "forge-std/Test.sol";

contract ElataPointsTest is Test {
    ElataPoints public points;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public minter = makeAddr("minter");

    function setUp() public {
        points = new ElataPoints(admin);
    }

    function test_Deployment() public {
        assertEq(points.name(), "Elata Points");
        assertEq(points.symbol(), "POINTS");
        assertEq(points.decimals(), 18);
        assertEq(points.totalSupply(), 0);

        assertTrue(points.hasRole(points.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(points.hasRole(points.POINTS_OPERATOR_ROLE(), admin));
    }

    function test_RevertWhen_DeploymentZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new ElataPoints(address(0));
    }

    function test_Award() public {
        uint256 amount = 1000 ether;

        vm.prank(admin);
        points.award(user1, amount);

        assertEq(points.balanceOf(user1), amount);
        assertEq(points.totalSupply(), amount);

        // Check that user is auto-delegated to self
        assertEq(points.delegates(user1), user1);
        assertEq(points.getVotes(user1), amount);
    }

    function test_RevertWhen_AwardZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        points.award(address(0), 1000 ether);
    }

    function test_RevertWhen_AwardZeroAmount() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(admin);
        points.award(user1, 0);
    }

    function test_RevertWhen_AwardUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        points.award(user1, 1000 ether);
    }

    function test_Revoke() public {
        uint256 amount = 1000 ether;
        uint256 revokeAmount = 300 ether;

        vm.startPrank(admin);
        points.award(user1, amount);
        points.revoke(user1, revokeAmount);
        vm.stopPrank();

        assertEq(points.balanceOf(user1), amount - revokeAmount);
        assertEq(points.totalSupply(), amount - revokeAmount);
        assertEq(points.getVotes(user1), amount - revokeAmount);
    }

    function test_RevertWhen_RevokeZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        points.revoke(address(0), 1000 ether);
    }

    function test_RevertWhen_RevokeZeroAmount() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(admin);
        points.revoke(user1, 0);
    }

    function test_RevertWhen_RevokeUnauthorized() public {
        vm.prank(admin);
        points.award(user1, 1000 ether);

        vm.expectRevert();
        vm.prank(user1);
        points.revoke(user1, 500 ether);
    }

    function test_TransfersDisabled() public {
        vm.prank(admin);
        points.award(user1, 1000 ether);

        vm.expectRevert(Errors.TransfersDisabled.selector);
        vm.prank(user1);
        points.transfer(user2, 500 ether);
    }

    function test_TransferFromDisabled() public {
        vm.startPrank(admin);
        points.award(user1, 1000 ether);
        vm.stopPrank();

        vm.prank(user1);
        points.approve(user2, 500 ether);

        vm.expectRevert(Errors.TransfersDisabled.selector);
        vm.prank(user2);
        points.transferFrom(user1, user2, 500 ether);
    }

    function test_GetPastXP() public {
        uint256 amount1 = 1000 ether;
        uint256 amount2 = 500 ether;

        vm.prank(admin);
        points.award(user1, amount1);

        vm.roll(block.number + 1);
        uint256 block1 = block.number - 1; // Previous block

        vm.prank(admin);
        points.award(user1, amount2);

        vm.roll(block.number + 1);
        uint256 block2 = block.number - 1; // Previous block

        // Check that past XP is tracked (may have decay applied)
        assertGt(points.getPastPoints(user1, block1), 0);
        assertGt(points.getPastPoints(user1, block2), 0);
    }

    function test_Delegation() public {
        vm.prank(admin);
        points.award(user1, 1000 ether);

        // User should be auto-delegated to self
        assertEq(points.delegates(user1), user1);

        // User can delegate to someone else
        vm.prank(user1);
        points.delegate(user2);

        assertEq(points.delegates(user1), user2);
        assertEq(points.getVotes(user1), 0);
        assertEq(points.getVotes(user2), 1000 ether);
    }

    function test_Permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        vm.prank(admin);
        points.award(owner, 1000 ether);

        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    points.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                            ),
                            owner,
                            user1,
                            500 ether,
                            points.nonces(owner),
                            deadline
                        )
                    )
                )
            )
        );

        points.permit(owner, user1, 500 ether, deadline, v, r, s);
        assertEq(points.allowance(owner, user1), 500 ether);
    }

    function test_AdminCanAwardXP() public {
        // Test that admin (who has POINTS_OPERATOR_ROLE by default) can award XP
        vm.prank(admin);
        points.award(user1, 1000 ether);

        assertEq(points.balanceOf(user1), 1000 ether);
        assertEq(points.totalSupply(), 1000 ether);

        // Verify auto-delegation occurred
        assertEq(points.delegates(user1), user1);
        assertEq(points.getVotes(user1), 1000 ether);
    }

    function test_RevokeMinterRole() public {
        vm.startPrank(admin);
        points.grantRole(points.POINTS_OPERATOR_ROLE(), minter);
        points.revokeRole(points.POINTS_OPERATOR_ROLE(), minter);
        vm.stopPrank();

        assertFalse(points.hasRole(points.POINTS_OPERATOR_ROLE(), minter));

        vm.expectRevert();
        vm.prank(minter);
        points.award(user1, 1000 ether);
    }

    function test_MultipleAwards() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 300 ether;
        uint256 amount3 = 200 ether;

        vm.startPrank(admin);
        points.award(user1, amount1);
        points.award(user1, amount2);
        points.award(user2, amount3);
        vm.stopPrank();

        assertEq(points.balanceOf(user1), amount1 + amount2);
        assertEq(points.balanceOf(user2), amount3);
        assertEq(points.totalSupply(), amount1 + amount2 + amount3);
    }

    function testFuzz_Award(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(admin);
        points.award(user1, amount);

        assertEq(points.balanceOf(user1), amount);
        assertEq(points.getVotes(user1), amount);
    }

    function testFuzz_Revoke(uint256 awardAmount, uint256 revokeAmount) public {
        awardAmount = bound(awardAmount, 1, type(uint128).max);
        revokeAmount = bound(revokeAmount, 1, awardAmount);

        vm.startPrank(admin);
        points.award(user1, awardAmount);
        points.revoke(user1, revokeAmount);
        vm.stopPrank();

        assertEq(points.balanceOf(user1), awardAmount - revokeAmount);
        assertEq(points.getVotes(user1), awardAmount - revokeAmount);
    }
}
