// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { EpochRewards } from "../../src/apps/EpochRewards.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { Merkle } from "murky/src/Merkle.sol";

contract EpochRewardsTest is Test {
    EpochRewards public rewards;
    AppToken public appToken;
    Merkle public merkle;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    event EpochStarted(uint256 indexed id, uint64 start, uint64 end);
    event EpochFunded(uint256 indexed id, uint256 amount);
    event EpochFinalized(uint256 indexed id, bytes32 root);
    event Claimed(uint256 indexed id, address indexed user, uint256 amount);

    function setUp() public {
        appToken = new AppToken("TestApp", "TEST", 18, MAX_SUPPLY, owner, admin);
        rewards = new EpochRewards(address(appToken), owner);
        merkle = new Merkle();

        // Mint tokens to owner for funding
        vm.prank(admin);
        appToken.mint(owner, 100000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public {
        assertEq(address(rewards.APP()), address(appToken));
        assertEq(rewards.owner(), owner);
        assertEq(rewards.epochId(), 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EPOCH MANAGEMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_StartEpoch() public {
        uint64 start = uint64(block.timestamp);
        uint64 end = uint64(block.timestamp + 7 days);

        vm.expectEmit(true, true, true, true);
        emit EpochStarted(1, start, end);

        vm.prank(owner);
        rewards.startEpoch(start, end);

        assertEq(rewards.epochId(), 1);

        (
            uint64 epochStart,
            uint64 epochEnd,
            bytes32 merkleRoot,
            uint256 totalFunded,
            uint256 totalClaimed
        ) = rewards.epochs(1);

        assertEq(epochStart, start);
        assertEq(epochEnd, end);
        assertEq(merkleRoot, 0);
        assertEq(totalFunded, 0);
        assertEq(totalClaimed, 0);
    }

    function test_RevertWhen_StartEpochInvalidWindow() public {
        vm.expectRevert(EpochRewards.InvalidWindow.selector);
        vm.prank(owner);
        rewards.startEpoch(100, 50); // end before start
    }

    function test_RevertWhen_StartEpochUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
    }

    function test_MultipleEpochs() public {
        vm.startPrank(owner);

        // Epoch 1
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        assertEq(rewards.epochId(), 1);

        // Epoch 2
        rewards.startEpoch(0, uint64(block.timestamp + 14 days));
        assertEq(rewards.epochId(), 2);

        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUNDING TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Fund() public {
        // Start epoch
        vm.prank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        uint256 fundAmount = 10000 ether;

        vm.startPrank(owner);
        appToken.approve(address(rewards), fundAmount);

        vm.expectEmit(true, true, true, true);
        emit EpochFunded(1, fundAmount);

        rewards.fund(fundAmount);
        vm.stopPrank();

        (,,, uint256 totalFunded,) = rewards.epochs(1);
        assertEq(totalFunded, fundAmount);
    }

    function test_FundMultipleTimes() public {
        vm.prank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        vm.startPrank(owner);
        appToken.approve(address(rewards), 15000 ether);

        rewards.fund(5000 ether);
        rewards.fund(10000 ether);
        vm.stopPrank();

        (,,, uint256 totalFunded,) = rewards.epochs(1);
        assertEq(totalFunded, 15000 ether);
    }

    function test_RevertWhen_FundWithoutEpoch() public {
        vm.expectRevert(EpochRewards.NoActiveEpoch.selector);
        vm.prank(owner);
        rewards.fund(1000 ether);
    }

    function test_RevertWhen_FundUnauthorized() public {
        vm.prank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        vm.expectRevert();
        vm.prank(user1);
        rewards.fund(1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FINALIZATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_FinalizeEpoch() public {
        // Start and fund epoch
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(10000 ether);

        // Create Merkle tree
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(6000 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(4000 ether)));
        bytes32 root = merkle.getRoot(data);

        vm.expectEmit(true, true, true, true);
        emit EpochFinalized(1, root);

        rewards.finalizeEpoch(root);
        vm.stopPrank();

        (,, bytes32 storedRoot,,) = rewards.epochs(1);
        assertEq(storedRoot, root);
    }

    function test_RevertWhen_FinalizeEpochWithoutEpoch() public {
        vm.expectRevert(EpochRewards.NoActiveEpoch.selector);
        vm.prank(owner);
        rewards.finalizeEpoch(bytes32(uint256(1)));
    }

    function test_RevertWhen_FinalizeEpochTwice() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        rewards.finalizeEpoch(bytes32(uint256(1)));

        vm.expectRevert(EpochRewards.AlreadyFinalized.selector);
        rewards.finalizeEpoch(bytes32(uint256(2)));
        vm.stopPrank();
    }

    function test_RevertWhen_FinalizeEpochUnauthorized() public {
        vm.prank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        vm.expectRevert();
        vm.prank(user1);
        rewards.finalizeEpoch(bytes32(uint256(1)));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // CLAIM TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Claim() public {
        // Setup epoch
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(10000 ether);

        // Create and finalize
        uint256 user1Reward = 6000 ether;
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, user1Reward));
        data[1] = keccak256(abi.encodePacked(user2, uint256(4000 ether)));
        bytes32 root = merkle.getRoot(data);
        rewards.finalizeEpoch(root);
        vm.stopPrank();

        // User1 claims
        bytes32[] memory proof = merkle.getProof(data, 0);

        vm.expectEmit(true, true, true, true);
        emit Claimed(1, user1, user1Reward);

        vm.prank(user1);
        rewards.claim(1, proof, user1Reward);

        assertEq(appToken.balanceOf(user1), user1Reward);
        assertTrue(rewards.claimed(1, user1));

        (,,,, uint256 totalClaimed) = rewards.epochs(1);
        assertEq(totalClaimed, user1Reward);
    }

    function test_MultipleUsersClaim() public {
        // Setup
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 10000 ether);
        rewards.fund(10000 ether);

        bytes32[] memory data = new bytes32[](3);
        data[0] = keccak256(abi.encodePacked(user1, uint256(5000 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(3000 ether)));
        data[2] = keccak256(abi.encodePacked(user3, uint256(2000 ether)));
        bytes32 root = merkle.getRoot(data);
        rewards.finalizeEpoch(root);
        vm.stopPrank();

        // User1 claims
        bytes32[] memory proof1 = merkle.getProof(data, 0);
        vm.prank(user1);
        rewards.claim(1, proof1, 5000 ether);

        // User2 claims
        bytes32[] memory proof2 = merkle.getProof(data, 1);
        vm.prank(user2);
        rewards.claim(1, proof2, 3000 ether);

        // User3 claims
        bytes32[] memory proof3 = merkle.getProof(data, 2);
        vm.prank(user3);
        rewards.claim(1, proof3, 2000 ether);

        assertEq(appToken.balanceOf(user1), 5000 ether);
        assertEq(appToken.balanceOf(user2), 3000 ether);
        assertEq(appToken.balanceOf(user3), 2000 ether);

        (,,,, uint256 totalClaimed) = rewards.epochs(1);
        assertEq(totalClaimed, 10000 ether);
    }

    function test_RevertWhen_ClaimNotFinalized() public {
        vm.prank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(EpochRewards.NotFinalized.selector);
        vm.prank(user1);
        rewards.claim(1, proof, 1000 ether);
    }

    function test_RevertWhen_ClaimTwice() public {
        // Setup
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 8000 ether);
        rewards.fund(8000 ether);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(5000 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(3000 ether)));
        bytes32 root = merkle.getRoot(data);
        rewards.finalizeEpoch(root);
        vm.stopPrank();

        // First claim
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.prank(user1);
        rewards.claim(1, proof, 5000 ether);

        // Second claim attempt
        vm.expectRevert(EpochRewards.AlreadyClaimed.selector);
        vm.prank(user1);
        rewards.claim(1, proof, 5000 ether);
    }

    function test_RevertWhen_ClaimInvalidProof() public {
        vm.startPrank(owner);
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        appToken.approve(address(rewards), 8000 ether);
        rewards.fund(8000 ether);

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(5000 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(3000 ether)));
        bytes32 root = merkle.getRoot(data);
        rewards.finalizeEpoch(root);
        vm.stopPrank();

        // Try to claim wrong amount
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.expectRevert(EpochRewards.InvalidProof.selector);
        vm.prank(user1);
        rewards.claim(1, proof, 3000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // INTEGRATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_MultipleEpochsIsolation() public {
        // Create multiple epochs and verify they're isolated
        vm.startPrank(owner);

        // Epoch 1
        rewards.startEpoch(0, uint64(block.timestamp + 7 days));
        assertEq(rewards.epochId(), 1);
        appToken.approve(address(rewards), 5000 ether);
        rewards.fund(5000 ether);
        bytes32 root1 = bytes32(uint256(1));
        rewards.finalizeEpoch(root1);

        // Epoch 2
        rewards.startEpoch(0, uint64(block.timestamp + 14 days));
        assertEq(rewards.epochId(), 2);
        appToken.approve(address(rewards), 3000 ether);
        rewards.fund(3000 ether);
        bytes32 root2 = bytes32(uint256(2));
        rewards.finalizeEpoch(root2);

        vm.stopPrank();

        // Verify epochs are properly isolated
        (uint64 start1, uint64 end1, bytes32 storedRoot1, uint256 funded1,) = rewards.epochs(1);
        (uint64 start2, uint64 end2, bytes32 storedRoot2, uint256 funded2,) = rewards.epochs(2);

        // Epoch 1 checks
        assertEq(start1, 0);
        assertEq(end1, uint64(block.timestamp + 7 days));
        assertEq(storedRoot1, root1);
        assertEq(funded1, 5000 ether);

        // Epoch 2 checks
        assertEq(start2, 0);
        assertEq(end2, uint64(block.timestamp + 14 days));
        assertEq(storedRoot2, root2);
        assertEq(funded2, 3000 ether);

        // Roots are different
        assertTrue(root1 != root2);
    }
}
