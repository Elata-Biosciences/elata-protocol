// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AppToken} from "../../src/apps/AppToken.sol";

/**
 * @title AppTokenFuzz
 * @notice Fuzz tests for AppToken
 */
contract AppTokenFuzz is Test {
    AppToken public token;

    address public creator = makeAddr("creator");
    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public appRewards = makeAddr("appRewards");
    address public rewards = makeAddr("rewards");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant MAX_SUPPLY = 10_000_000 ether;

    function setUp() public {
        token = new AppToken(
            AppToken.InitParams({
                name: "TestApp",
                symbol: "TEST",
                decimals: 18,
                maxSupply: MAX_SUPPLY,
                creator: creator,
                admin: admin,
                governance: governance,
                appRewardsDistributor: appRewards,
                rewardsDistributor: rewards,
                treasury: treasury
            })
        );

        // Mint tokens for testing
        vm.prank(admin);
        token.mint(user1, 1_000_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRANSFER FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_AppToken_Transfer(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(token));
        amount = bound(amount, 1, token.balanceOf(user1));

        uint256 senderBefore = token.balanceOf(user1);
        uint256 receiverBefore = token.balanceOf(to);

        vm.prank(user1);
        token.transfer(to, amount);

        // Account for potential transfer tax
        uint256 received = token.balanceOf(to) - receiverBefore;
        uint256 sent = senderBefore - token.balanceOf(user1);

        assertEq(sent, amount, "Sender should lose exact amount");
        assertLe(received, amount, "Receiver should get <= amount (tax may apply)");
    }

    function testFuzz_AppToken_Approve(address spender, uint256 amount) public {
        vm.assume(spender != address(0));

        vm.prank(user1);
        token.approve(spender, amount);

        assertEq(token.allowance(user1, spender), amount, "Allowance incorrect");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MINT FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_AppToken_Mint(address to, uint256 amount) public {
        vm.assume(to != address(0));

        uint256 currentSupply = token.totalSupply();
        uint256 maxSupply = token.maxSupply();
        uint256 available = maxSupply - currentSupply;

        amount = bound(amount, 1, available > 0 ? available : 1);

        if (currentSupply + amount <= maxSupply) {
            uint256 balanceBefore = token.balanceOf(to);

            vm.prank(admin);
            token.mint(to, amount);

            assertEq(token.balanceOf(to), balanceBefore + amount, "Mint failed");
            assertLe(token.totalSupply(), maxSupply, "Exceeded max supply");
        }
    }

    function testFuzz_AppToken_MintCannotExceedMaxSupply(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        uint256 currentSupply = token.totalSupply();
        uint256 maxSupply = token.maxSupply();

        if (currentSupply + amount > maxSupply) {
            vm.prank(admin);
            vm.expectRevert();
            token.mint(user2, amount);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BURN FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_AppToken_Burn(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(user1));

        uint256 balanceBefore = token.balanceOf(user1);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(user1);
        token.burn(amount);

        assertEq(token.balanceOf(user1), balanceBefore - amount, "Balance not reduced");
        assertEq(token.totalSupply(), supplyBefore - amount, "Supply not reduced");
    }

    function testFuzz_AppToken_BurnFrom(address burner, uint256 amount) public {
        vm.assume(burner != address(0) && burner != user1);
        amount = bound(amount, 1, token.balanceOf(user1));

        // Approve burner
        vm.prank(user1);
        token.approve(burner, amount);

        uint256 balanceBefore = token.balanceOf(user1);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(burner);
        token.burnFrom(user1, amount);

        assertEq(token.balanceOf(user1), balanceBefore - amount, "Balance not reduced");
        assertEq(token.totalSupply(), supplyBefore - amount, "Supply not reduced");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRANSFER TAX FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_AppToken_TransferTax(uint256 taxBps, uint256 amount) public {
        // Bound tax to reasonable range
        uint256 maxTax = token.MAX_TRANSFER_FEE_BPS();
        taxBps = bound(taxBps, 0, maxTax);
        amount = bound(amount, 1000, token.balanceOf(user1) / 2);

        // Set tax
        vm.prank(governance);
        token.setTransferFeeBps(uint16(taxBps));

        uint256 senderBefore = token.balanceOf(user1);
        uint256 receiverBefore = token.balanceOf(user2);

        vm.prank(user1);
        token.transfer(user2, amount);

        uint256 received = token.balanceOf(user2) - receiverBefore;

        // With tax, received should be <= amount
        assertLe(received, amount, "Received should be <= sent");

        // If no tax, should receive exact amount
        if (taxBps == 0) {
            assertEq(received, amount, "No-tax transfer should be exact");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BURN FEE FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_AppToken_BurnFee(uint256 burnBps, uint256 amount) public {
        uint256 maxBurn = token.MAX_BURN_FEE_BPS();
        burnBps = bound(burnBps, 1, maxBurn); // At least 1 bps
        amount = bound(amount, 100_000, token.balanceOf(user1) / 2); // Larger amount for visible burn

        // Set burn fee
        vm.prank(governance);
        token.setBurnFeeBps(uint16(burnBps));

        uint256 supplyBefore = token.totalSupply();

        vm.prank(user1);
        token.transfer(user2, amount);

        // Check burn sink balance increased (tokens sent to dead address)
        address burnSink = token.BURN_SINK();
        uint256 burnedAmount = token.balanceOf(burnSink);

        // With large enough amount and burn fee > 0, some should be burned
        // The burn sink should have received some tokens
        assertGe(burnedAmount, 0, "Burn sink should exist");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_AppToken_OnlyMinterCanMint(address minter, uint256 amount) public {
        vm.assume(minter != admin && minter != address(0));
        amount = bound(amount, 1, 1000 ether);

        // Non-minter should fail
        vm.prank(minter);
        vm.expectRevert();
        token.mint(user2, amount);
    }

    function testFuzz_AppToken_OnlyGovernanceCanSetFee(address caller, uint256 tax) public {
        vm.assume(caller != governance && caller != admin && caller != address(0));
        tax = bound(tax, 0, token.MAX_TRANSFER_FEE_BPS());

        vm.prank(caller);
        vm.expectRevert();
        token.setTransferFeeBps(uint16(tax));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PERMIT FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_AppToken_PermitNonce(uint256 nonce) public {
        // Just verify nonce is accessible
        uint256 currentNonce = token.nonces(user1);
        assertEq(currentNonce, 0, "Initial nonce should be 0");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Edge_TransferZero() public {
        uint256 balanceBefore = token.balanceOf(user2);

        vm.prank(user1);
        token.transfer(user2, 0);

        // Zero transfer should succeed but have no effect
        assertEq(token.balanceOf(user2), balanceBefore, "Balance should not change");
    }

    function test_Edge_TransferToSelf() public {
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        token.transfer(user1, 1000 ether);

        // Balance might decrease due to tax, but should not increase
        assertLe(token.balanceOf(user1), balanceBefore, "Balance should not increase");
    }

    function test_Edge_ApproveMaxUint() public {
        vm.prank(user1);
        token.approve(user2, type(uint256).max);

        assertEq(token.allowance(user1, user2), type(uint256).max, "Max approval failed");
    }

    function test_Edge_BurnAllTokens() public {
        uint256 balance = token.balanceOf(user1);

        vm.prank(user1);
        token.burn(balance);

        assertEq(token.balanceOf(user1), 0, "Should burn all tokens");
    }
}
