// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ElataXP } from "../../src/experience/ElataXP.sol";
import { Errors } from "../../src/utils/Errors.sol";
import "forge-std/Test.sol";

contract ElataXP_Merkle_Test is Test {
    event XPClaimed(uint256 indexed distributionId, address indexed user, uint256 amount);
    event XPAwarded(address indexed user, uint256 amount);

    ElataXP xp;
    address admin = address(0xA11CE);
    address userA = address(0xBEEF);
    address operator2 = address(0xD00D);
    bytes32 root;

    function setUp() public {
        xp = new ElataXP(admin);
        vm.prank(admin);
        // Simple two-leaf tree root for leaves L1 and L2 sorted then hashed
        // L1 = keccak256(abi.encodePacked(userA, uint256(100)))
        bytes32 l1 = keccak256(abi.encodePacked(userA, uint256(100)));
        bytes32 l2 = keccak256(abi.encodePacked(address(0xCAFE), uint256(50)));
        (bytes32 a, bytes32 b) = l1 < l2 ? (l1, l2) : (l2, l1);
        root = keccak256(abi.encodePacked(a, b));
        xp.setMerkleRoot(root, bytes32(0));
    }

    function test_claim_success() public {
        uint256 id = xp.currentDistributionId();
        // proof for l1 in a two-leaf tree is just sibling l2
        bytes32 sibling = keccak256(abi.encodePacked(address(0xCAFE), uint256(50)));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;

        vm.expectEmit(true, true, true, true, address(xp));
        emit XPClaimed(id, userA, 100);
        vm.expectEmit(true, true, true, true, address(xp));
        emit XPAwarded(userA, 100);

        vm.prank(userA);
        xp.claimXP(id, 100, proof);
        assertTrue(xp.hasClaimed(id, userA));
        assertEq(xp.balanceOf(userA), 100);
    }

    function test_claim_reject_double() public {
        uint256 id = xp.currentDistributionId();
        bytes32 sibling = keccak256(abi.encodePacked(address(0xCAFE), uint256(50)));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;

        vm.startPrank(userA);
        xp.claimXP(id, 100, proof);
        vm.expectRevert(ElataXP.AlreadyClaimed.selector);
        xp.claimXP(id, 100, proof);
        vm.stopPrank();
    }

    function test_claim_invalid_distribution() public {
        bytes32[] memory proof;
        vm.prank(userA);
        vm.expectRevert(ElataXP.InvalidDistribution.selector);
        xp.claimXP(999, 100, proof);
    }

    function test_claim_zero_amount_reverts() public {
        uint256 id = xp.currentDistributionId();
        bytes32 sibling = keccak256(abi.encodePacked(address(0xCAFE), uint256(50)));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;
        vm.prank(userA);
        vm.expectRevert(Errors.InvalidAmount.selector);
        xp.claimXP(id, 0, proof);
    }

    function test_claim_invalid_proof_reverts() public {
        uint256 id = xp.currentDistributionId();
        // wrong sibling
        bytes32 wrongSibling = keccak256(abi.encodePacked(address(0xBEEF), uint256(100))); // not correct sibling
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = wrongSibling;
        vm.prank(userA);
        vm.expectRevert(ElataXP.InvalidProof.selector);
        xp.claimXP(id, 100, badProof);
    }

    function test_only_operator_can_setMerkleRoot() public {
        // non-operator should revert via AccessControl
        vm.expectRevert();
        xp.setMerkleRoot(bytes32(uint256(123)), bytes32(0));

        // grant operator2 and succeed
        vm.startPrank(admin);
        xp.grantRole(xp.XP_OPERATOR_ROLE(), operator2);
        vm.stopPrank();

        vm.prank(operator2);
        xp.setMerkleRoot(bytes32(uint256(456)), bytes32(0));
        assertEq(xp.currentDistributionId(), 2);
    }

    function test_operator_rotation() public {
        // grant operator2 and revoke admin in a single prank session
        vm.startPrank(admin);
        xp.grantRole(xp.XP_OPERATOR_ROLE(), operator2);
        xp.revokeRole(xp.XP_OPERATOR_ROLE(), admin);
        vm.stopPrank();
        // now only operator2 can set root
        vm.expectRevert();
        xp.setMerkleRoot(bytes32(uint256(1)), bytes32(0));
        vm.prank(operator2);
        xp.setMerkleRoot(bytes32(uint256(2)), bytes32(0));
        assertEq(xp.currentDistributionId(), 2);
    }

    function test_multiple_distributions_independent_claims() public {
        // id 1 set in setUp: userA has 100, sibling is for 0xCAFE:50
        uint256 id1 = xp.currentDistributionId();
        bytes32 sibling1 = keccak256(abi.encodePacked(address(0xCAFE), uint256(50)));
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = sibling1;

        // create a second distribution (two leaves again)
        bytes32 l1 = keccak256(abi.encodePacked(userA, uint256(25)));
        bytes32 l2 = keccak256(abi.encodePacked(address(0xABCD), uint256(75)));
        (bytes32 a, bytes32 b) = l1 < l2 ? (l1, l2) : (l2, l1);
        bytes32 root2 = keccak256(abi.encodePacked(a, b));
        vm.prank(admin);
        xp.setMerkleRoot(root2, bytes32(0));
        uint256 id2 = xp.currentDistributionId();
        // proof for userA in id2 is sibling l2
        bytes32[] memory proof2 = new bytes32[](1);
        proof2[0] = l2;

        // claim id1 and id2 independently
        vm.expectEmit(true, true, true, true, address(xp));
        emit XPClaimed(id1, userA, 100);
        vm.expectEmit(true, true, true, true, address(xp));
        emit XPAwarded(userA, 100);
        vm.prank(userA);
        xp.claimXP(id1, 100, proof1);
        vm.expectEmit(true, true, true, true, address(xp));
        emit XPClaimed(id2, userA, 25);
        vm.expectEmit(true, true, true, true, address(xp));
        emit XPAwarded(userA, 25);
        vm.prank(userA);
        xp.claimXP(id2, 25, proof2);

        assertTrue(xp.hasClaimed(id1, userA));
        assertTrue(xp.hasClaimed(id2, userA));
        assertEq(xp.balanceOf(userA), 125);
    }

    function test_gas_snapshot_claim() public {
        uint256 id = xp.currentDistributionId();
        bytes32 sibling = keccak256(abi.encodePacked(address(0xCAFE), uint256(50)));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;
        vm.prank(userA);
        uint256 gasBefore = gasleft();
        xp.claimXP(id, 100, proof);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("claimXP gas used", gasUsed);
        assertTrue(gasUsed > 0);
    }
}
