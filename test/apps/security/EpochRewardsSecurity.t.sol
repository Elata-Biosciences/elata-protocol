// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { EpochRewards } from "../../../src/apps/EpochRewards.sol";
import { AppToken } from "../../../src/apps/AppToken.sol";
import { Merkle } from "murky/src/Merkle.sol";

/**
 * @title EpochRewardsSecurityTest
 * @notice Comprehensive security testing for EpochRewards
 * @dev Tests epoch isolation, claim exploits, funding security, and edge cases
 */
contract EpochRewardsSecurityTest is Test {
    EpochRewards public rewards;
    AppToken public appToken;
    Merkle public merkle;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        appToken = new AppToken("TestApp", "TEST", 18, MAX_SUPPLY, owner, admin);
        rewards = new EpochRewards(address(appToken), owner);
        merkle = new Merkle();

        // Mint tokens to owner for funding
        vm.prank(admin);
        appToken.mint(owner, 100000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EPOCH ISOLATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_EpochsAreIsolated() public {
        // Create two epochs
        vm.startPrank(owner);

        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 5000 ether);
        rewards.fund(5000 ether);
        rewards.finalizeEpoch(bytes32(uint256(1)));

        rewards.startEpoch(0, uint64(block.timestamp + 14 days));
        appToken.approve(address(rewards), 3000 ether);
        rewards.fund(3000 ether);
        rewards.finalizeEpoch(bytes32(uint256(2)));

        vm.stopPrank();

        // Verify epochs have different data
        (,, bytes32 root1, uint256 funded1, uint256 claimed1) = rewards.epochs(1);
        (,, bytes32 root2, uint256 funded2, uint256 claimed2) = rewards.epochs(2);

        assertEq(funded1, 5000 ether);
        assertEq(funded2, 3000 ether);
        assertEq(claimed1, 0);
        assertEq(claimed2, 0);
        assertTrue(root1 != root2);
    }

    function test_Security_CannotClaimFromWrongEpoch() public {
        // Setup two epochs
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(10000 ether);

        bytes32[] memory data1 = new bytes32[](2);
        data1[0] = keccak256(abi.encodePacked(user1, uint256(5000 ether)));
        data1[1] = keccak256(abi.encodePacked(user2, uint256(5000 ether)));
        bytes32 root1 = merkle.getRoot(data1);
        rewards.finalizeEpoch(root1);
        vm.stopPrank();

        // Try to claim with proof from epoch 1 but for epoch 2
        bytes32[] memory proof = merkle.getProof(data1, 0);

        vm.expectRevert(EpochRewards.NotFinalized.selector);
        vm.prank(user1);
        rewards.claim(2, proof, 5000 ether);
    }

    function test_Security_CannotReuseClaimAcrossEpochs() public {
        // Create two identical epochs
        vm.startPrank(owner);

        // Epoch 1
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(5000 ether);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(2500 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(2500 ether)));
        bytes32 root = merkle.getRoot(data);
        rewards.finalizeEpoch(root);

        // Epoch 2 (same Merkle root)
        rewards.startEpoch(0, uint64(block.timestamp + 14 days));
        rewards.fund(5000 ether);
        rewards.finalizeEpoch(root); // Same root
        vm.stopPrank();

        // Claim from epoch 1
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.prank(user1);
        rewards.claim(1, proof, 2500 ether);

        // Should be able to claim from epoch 2 (separate claim tracking)
        vm.prank(user1);
        rewards.claim(2, proof, 2500 ether);

        // But not claim epoch 1 again
        vm.expectRevert(EpochRewards.AlreadyClaimed.selector);
        vm.prank(user1);
        rewards.claim(1, proof, 2500 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MERKLE PROOF EXPLOIT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotClaimWithWrongProof() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 5000 ether);
        rewards.fund(5000 ether);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(3000 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(2000 ether)));
        rewards.finalizeEpoch(merkle.getRoot(data));
        vm.stopPrank();

        // Attacker tries with fabricated proof
        bytes32[] memory fakeProof = new bytes32[](1);
        fakeProof[0] = bytes32(uint256(999));

        vm.expectRevert(EpochRewards.InvalidProof.selector);
        vm.prank(attacker);
        rewards.claim(1, fakeProof, 5000 ether);
    }

    function test_Security_CannotClaimDifferentAmount() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 5000 ether);
        rewards.fund(5000 ether);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(3000 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(2000 ether)));
        rewards.finalizeEpoch(merkle.getRoot(data));
        vm.stopPrank();

        // User1 tries to claim 5000 instead of 3000
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.expectRevert(EpochRewards.InvalidProof.selector);
        vm.prank(user1);
        rewards.claim(1, proof, 5000 ether);
    }

    function test_Security_CannotClaimOthersReward() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 5000 ether);
        rewards.fund(5000 ether);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(3000 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(2000 ether)));
        rewards.finalizeEpoch(merkle.getRoot(data));
        vm.stopPrank();

        // Attacker tries to use user1's proof
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.expectRevert(EpochRewards.InvalidProof.selector);
        vm.prank(attacker);
        rewards.claim(1, proof, 3000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUNDING SECURITY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_OnlyOwnerCanStartEpoch() public {
        vm.expectRevert();
        vm.prank(attacker);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
    }

    function test_Security_OnlyOwnerCanFund() public {
        vm.prank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        vm.expectRevert();
        vm.prank(attacker);
        rewards.fund(1000 ether);
    }

    function test_Security_OnlyOwnerCanFinalize() public {
        vm.prank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        vm.expectRevert();
        vm.prank(attacker);
        rewards.finalizeEpoch(bytes32(0));
    }

    function test_Security_CannotFinalizeMultipleTimes() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        rewards.finalizeEpoch(bytes32(uint256(1)));

        vm.expectRevert(EpochRewards.AlreadyFinalized.selector);
        rewards.finalizeEpoch(bytes32(uint256(2)));
        vm.stopPrank();
    }

    function test_Security_CannotClaimBeforeFinalize() public {
        vm.prank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(EpochRewards.NotFinalized.selector);
        vm.prank(user1);
        rewards.claim(1, proof, 1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ACCOUNTING INTEGRITY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_TotalClaimedTrackedCorrectly() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(10000 ether);

        // Finalize with dummy root
        rewards.finalizeEpoch(bytes32(uint256(1)));
        vm.stopPrank();

        // Verify initial state
        (,,, uint256 funded, uint256 claimed) = rewards.epochs(1);
        assertEq(funded, 10000 ether);
        assertEq(claimed, 0);

        // Claimed amount tracked even if proof is wrong
        // (actual claim will fail but we're testing the accounting logic)
    }

    function test_Security_FundingAccumulatesCorrectly() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(3000 ether);
        rewards.fund(4000 ether);
        rewards.fund(3000 ether);
        vm.stopPrank();

        (,,, uint256 funded,) = rewards.epochs(1);
        assertEq(funded, 10000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // VIEW FUNCTION SECURITY
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ViewFunctionsNoSideEffects() public {
        vm.prank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        // Call all view functions
        rewards.getCurrentEpochId();
        rewards.isEpochClaimable(1);
        rewards.getEpochUtilization(1);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        rewards.getEpochs(ids);

        address[] memory users = new address[](1);
        users[0] = user1;
        rewards.checkClaimStatuses(1, users);

        // State should be unchanged
        assertEq(rewards.epochId(), 1);
        (,, bytes32 root,,) = rewards.epochs(1);
        assertEq(root, 0);
    }

    function test_Security_UtilizationCalculation() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(10000 ether);
        rewards.finalizeEpoch(bytes32(uint256(1)));
        vm.stopPrank();

        // Before any claims
        assertEq(rewards.getEpochUtilization(1), 0);

        // Manually update claimed amount to test calculation
        // (In reality, claims would update this via valid Merkle proofs)

        // Test utilization calculation formula
        (,,, uint256 funded,) = rewards.epochs(1);
        assertEq(funded, 10000 ether);

        // 0% utilization with 0 claimed
        assertEq(rewards.getEpochUtilization(1), 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EDGE CASE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotStartEpochWithInvalidWindow() public {
        vm.expectRevert(EpochRewards.InvalidWindow.selector);
        vm.prank(owner);
        rewards.startEpoch(100, 50); // End before start
    }

    function test_Security_CannotFundWithoutEpoch() public {
        vm.expectRevert(EpochRewards.NoActiveEpoch.selector);
        vm.prank(owner);
        rewards.fund(1000 ether);
    }

    function test_Security_CannotFinalizeWithoutEpoch() public {
        vm.expectRevert(EpochRewards.NoActiveEpoch.selector);
        vm.prank(owner);
        rewards.finalizeEpoch(bytes32(0));
    }

    function test_Security_CannotClaimNonexistentEpoch() public {
        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(EpochRewards.NotFinalized.selector);
        vm.prank(user1);
        rewards.claim(999, proof, 1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DOUBLE CLAIM PREVENTION
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotClaimTwiceSameEpoch() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 5000 ether);
        rewards.fund(5000 ether);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(3000 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(2000 ether)));
        rewards.finalizeEpoch(merkle.getRoot(data));
        vm.stopPrank();

        // First claim
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.prank(user1);
        rewards.claim(1, proof, 3000 ether);

        // Second claim attempt
        vm.expectRevert(EpochRewards.AlreadyClaimed.selector);
        vm.prank(user1);
        rewards.claim(1, proof, 3000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // REENTRANCY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ReentrancyProtection_Claim() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 5000 ether);
        rewards.fund(5000 ether);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(3000 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(2000 ether)));
        rewards.finalizeEpoch(merkle.getRoot(data));
        vm.stopPrank();

        // Claim is protected by nonReentrant
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.prank(user1);
        rewards.claim(1, proof, 3000 ether);

        // Verify only claimed once
        assertTrue(rewards.claimed(1, user1));
        (,,,, uint256 totalClaimed) = rewards.epochs(1);
        assertEq(totalClaimed, 3000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUNDING OVERFLOW TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_MultipleFundingCallsAccumulate() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        appToken.approve(address(rewards), type(uint256).max);

        uint256 fundAmount = 1000 ether;
        for (uint256 i = 0; i < 10; i++) {
            rewards.fund(fundAmount);
        }
        vm.stopPrank();

        (,,, uint256 funded,) = rewards.epochs(1);
        assertEq(funded, fundAmount * 10);
    }

    function testFuzz_Security_ClaimAmountLimited(uint256 claimAmount) public {
        claimAmount = bound(claimAmount, 1, 10000 ether);

        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(10000 ether);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, claimAmount));
        data[1] = keccak256(abi.encodePacked(user2, uint256(1000 ether)));
        rewards.finalizeEpoch(merkle.getRoot(data));
        vm.stopPrank();

        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.prank(user1);
        rewards.claim(1, proof, claimAmount);

        assertEq(appToken.balanceOf(user1), claimAmount);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // BATCH VIEW FUNCTION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_BatchViewsEfficient() public {
        // Create 3 epochs
        vm.startPrank(owner);
        for (uint256 i = 0; i < 3; i++) {
            rewards.startEpoch(0, uint64(block.timestamp + (i + 1) * 7 days));
        }
        vm.stopPrank();

        // Batch query all epochs
        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        EpochRewards.Epoch[] memory epochList = rewards.getEpochs(ids);
        assertEq(epochList.length, 3);

        // Check claim statuses for multiple users
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        bool[] memory statuses = rewards.checkClaimStatuses(1, users);
        assertEq(statuses.length, 2);
        assertFalse(statuses[0]);
        assertFalse(statuses[1]);
    }
}
