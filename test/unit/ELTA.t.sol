// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract ELTATest is Test {
    ELTA public elta;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public minter = makeAddr("minter");

    uint256 public constant INITIAL_MINT = 10_000_000 ether;
    uint256 public constant MAX_SUPPLY = 77_000_000 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, INITIAL_MINT, MAX_SUPPLY);
    }

    function test_Deployment() public {
        assertEq(elta.name(), "ELTA");
        assertEq(elta.symbol(), "ELTA");
        assertEq(elta.decimals(), 18);
        assertEq(elta.totalSupply(), INITIAL_MINT);
        assertEq(elta.balanceOf(treasury), INITIAL_MINT);
        assertEq(elta.MAX_SUPPLY(), MAX_SUPPLY);

        assertTrue(elta.hasRole(elta.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(elta.hasRole(elta.MINTER_ROLE(), admin));
    }

    function test_RevertWhen_DeploymentZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new ELTA("ELTA", "ELTA", address(0), treasury, INITIAL_MINT, MAX_SUPPLY);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new ELTA("ELTA", "ELTA", admin, address(0), INITIAL_MINT, MAX_SUPPLY);
    }

    function test_Mint() public {
        vm.prank(admin);
        elta.mint(user1, 1000 ether);

        assertEq(elta.balanceOf(user1), 1000 ether);
        assertEq(elta.totalSupply(), INITIAL_MINT + 1000 ether);
    }

    function test_RevertWhen_MintUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        elta.mint(user1, 1000 ether);
    }

    function test_RevertWhen_MintToZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        elta.mint(address(0), 1000 ether);
    }

    function test_RevertWhen_MintExceedsCap() public {
        vm.startPrank(admin);

        // Mint up to cap
        uint256 remaining = MAX_SUPPLY - INITIAL_MINT;
        elta.mint(user1, remaining);

        // Try to mint 1 more token
        vm.expectRevert(Errors.CapExceeded.selector);
        elta.mint(user1, 1);

        vm.stopPrank();
    }

    function test_Burn() public {
        vm.startPrank(treasury);
        elta.burn(1000 ether);

        assertEq(elta.balanceOf(treasury), INITIAL_MINT - 1000 ether);
        assertEq(elta.totalSupply(), INITIAL_MINT - 1000 ether);
        vm.stopPrank();
    }

    function test_BurnFrom() public {
        vm.prank(treasury);
        elta.approve(user1, 1000 ether);

        vm.prank(user1);
        elta.burnFrom(treasury, 1000 ether);

        assertEq(elta.balanceOf(treasury), INITIAL_MINT - 1000 ether);
        assertEq(elta.totalSupply(), INITIAL_MINT - 1000 ether);
    }

    function test_Transfer() public {
        vm.prank(treasury);
        elta.transfer(user1, 1000 ether);

        assertEq(elta.balanceOf(user1), 1000 ether);
        assertEq(elta.balanceOf(treasury), INITIAL_MINT - 1000 ether);
    }

    function test_Permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        vm.prank(admin);
        elta.mint(owner, 1000 ether);

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

    function test_Delegation() public {
        vm.prank(treasury);
        elta.delegate(user1);

        assertEq(elta.delegates(treasury), user1);
        assertEq(elta.getVotes(user1), INITIAL_MINT);
    }

    function test_Checkpoints() public {
        vm.prank(treasury);
        elta.delegate(treasury); // self-delegate

        vm.roll(block.number + 1);
        uint256 block1 = block.number - 1;

        vm.prank(admin);
        elta.mint(treasury, 1000 ether);

        vm.roll(block.number + 1);
        uint256 block2 = block.number - 1;

        // Checkpoint system is working - verify past votes are tracked
        assertGt(elta.getPastVotes(treasury, block1), 0);
        assertGt(elta.getPastVotes(treasury, block2), 0);
    }

    function test_AdminCanMint() public {
        // Test that admin (who has MINTER_ROLE by default) can mint
        vm.prank(admin);
        elta.mint(user1, 1000 ether);

        assertEq(elta.balanceOf(user1), 1000 ether);
        assertEq(elta.totalSupply(), INITIAL_MINT + 1000 ether);
    }

    function test_RevokeMinterRole() public {
        vm.startPrank(admin);
        elta.grantRole(elta.MINTER_ROLE(), minter);
        elta.revokeRole(elta.MINTER_ROLE(), minter);
        vm.stopPrank();

        assertFalse(elta.hasRole(elta.MINTER_ROLE(), minter));

        vm.expectRevert();
        vm.prank(minter);
        elta.mint(user1, 1000 ether);
    }

    function testFuzz_MintWithinCap(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY - INITIAL_MINT);

        vm.prank(admin);
        elta.mint(user1, amount);

        assertEq(elta.balanceOf(user1), amount);
        assertEq(elta.totalSupply(), INITIAL_MINT + amount);
    }

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        vm.prank(treasury);
        elta.transfer(user1, amount);

        assertEq(elta.balanceOf(user1), amount);
        assertEq(elta.balanceOf(treasury), INITIAL_MINT - amount);
    }
}
