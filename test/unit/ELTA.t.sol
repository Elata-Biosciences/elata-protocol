// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Elata Protocol — elata.bio
// Author: wkyleg.eth

import {ELTA} from "../../src/token/ELTA.sol";
import "forge-std/Test.sol";

contract ELTATest is Test {
    ELTA public elta;

    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant MAX_SUPPLY = 77_000_000 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        elta = new ELTA(treasury);
    }

    function test_Deployment() public view {
        assertEq(elta.name(), "Elata");
        assertEq(elta.symbol(), "ELTA");
        assertEq(elta.decimals(), 18);
        assertEq(elta.totalSupply(), MAX_SUPPLY);
        assertEq(elta.balanceOf(treasury), MAX_SUPPLY);
        assertEq(elta.MAX_SUPPLY(), MAX_SUPPLY);
    }

    function test_RevertWhen_DeploymentZeroAddress() public {
        vm.expectRevert("ELTA: zero address");
        new ELTA(address(0));
    }

    function test_Burn() public {
        vm.startPrank(treasury);
        elta.burn(1000 ether);

        assertEq(elta.balanceOf(treasury), MAX_SUPPLY - 1000 ether);
        assertEq(elta.totalSupply(), MAX_SUPPLY - 1000 ether);
        vm.stopPrank();
    }

    function test_BurnFrom() public {
        vm.prank(treasury);
        elta.approve(user1, 1000 ether);

        vm.prank(user1);
        elta.burnFrom(treasury, 1000 ether);

        assertEq(elta.balanceOf(treasury), MAX_SUPPLY - 1000 ether);
        assertEq(elta.totalSupply(), MAX_SUPPLY - 1000 ether);
    }

    function test_Transfer() public {
        vm.prank(treasury);
        elta.transfer(user1, 1000 ether);

        assertEq(elta.balanceOf(user1), 1000 ether);
        assertEq(elta.balanceOf(treasury), MAX_SUPPLY - 1000 ether);
    }

    function test_Approve() public {
        vm.prank(treasury);
        elta.approve(user1, 1000 ether);

        assertEq(elta.allowance(treasury, user1), 1000 ether);
    }

    function test_TransferFrom() public {
        vm.prank(treasury);
        elta.approve(user1, 1000 ether);

        vm.prank(user1);
        elta.transferFrom(treasury, user2, 1000 ether);

        assertEq(elta.balanceOf(user2), 1000 ether);
        assertEq(elta.balanceOf(treasury), MAX_SUPPLY - 1000 ether);
    }

    function test_Permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        // Transfer some ELTA to owner
        vm.prank(treasury);
        elta.transfer(owner, 1000 ether);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = 500 ether;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    elta.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                            ),
                            owner,
                            user1,
                            amount,
                            elta.nonces(owner),
                            deadline
                        )
                    )
                )
            )
        );

        elta.permit(owner, user1, amount, deadline, v, r, s);
        assertEq(elta.allowance(owner, user1), amount);
    }

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY);

        vm.prank(treasury);
        elta.transfer(user1, amount);

        assertEq(elta.balanceOf(user1), amount);
        assertEq(elta.balanceOf(treasury), MAX_SUPPLY - amount);
    }

    function testFuzz_Burn(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY);

        vm.prank(treasury);
        elta.burn(amount);

        assertEq(elta.balanceOf(treasury), MAX_SUPPLY - amount);
        assertEq(elta.totalSupply(), MAX_SUPPLY - amount);
    }
}
