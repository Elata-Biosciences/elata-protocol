// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AirdropDistributor} from "../../src/modules/AirdropDistributor.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title AirdropDistributorTest
 * @notice Unit tests for AirdropDistributor contract
 * @dev Tests Merkle-based airdrop claims for ecosystem pool distribution
 *
 * Per Protocol Changes document section 10.2:
 * - Ecosystem pool distributed via Merkle airdrops
 * - Developer incentives from ecosystem vault
 */
contract AirdropDistributorTest is Test {
    AirdropDistributor public distributor;
    MockToken public appToken;

    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator");

    // Test users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public attacker = makeAddr("attacker");

    uint256 public constant APP_ID = 1;
    uint256 public constant AIRDROP_AMOUNT = 1_000_000 ether;

    // Merkle tree data (pre-computed)
    // Tree: Alice gets 100k, Bob gets 50k, Charlie gets 25k
    bytes32 public merkleRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    bytes32[] public charlieProof;

    uint256 public aliceAmount = 100_000 ether;
    uint256 public bobAmount = 50_000 ether;
    uint256 public charlieAmount = 25_000 ether;

    function setUp() public {
        appToken = new MockToken("App Token", "APP");

        distributor = new AirdropDistributor(admin, operator);

        // Fund distributor
        appToken.mint(address(distributor), AIRDROP_AMOUNT);

        // Compute Merkle tree
        // Leaf: keccak256(abi.encodePacked(address, amount))
        bytes32 leafAlice = keccak256(abi.encodePacked(alice, aliceAmount));
        bytes32 leafBob = keccak256(abi.encodePacked(bob, bobAmount));
        bytes32 leafCharlie = keccak256(abi.encodePacked(charlie, charlieAmount));

        // Simple 3-leaf tree (pad with zero for balanced tree)
        bytes32 zero = bytes32(0);

        // Level 1: Hash pairs
        bytes32 hash01 = _hashPair(leafAlice, leafBob);
        bytes32 hash23 = _hashPair(leafCharlie, zero);

        // Root
        merkleRoot = _hashPair(hash01, hash23);

        // Proofs
        aliceProof = new bytes32[](2);
        aliceProof[0] = leafBob;
        aliceProof[1] = hash23;

        bobProof = new bytes32[](2);
        bobProof[0] = leafAlice;
        bobProof[1] = hash23;

        charlieProof = new bytes32[](2);
        charlieProof[0] = zero;
        charlieProof[1] = hash01;
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // =========== Deployment Tests ===========

    function test_Deploy() public view {
        assertEq(distributor.admin(), admin);
        assertEq(distributor.operator(), operator);
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert(AirdropDistributor.ZeroAddress.selector);
        new AirdropDistributor(address(0), operator);
    }

    function test_RevertWhen_DeployWithZeroOperator() public {
        vm.expectRevert(AirdropDistributor.ZeroAddress.selector);
        new AirdropDistributor(admin, address(0));
    }

    // =========== Campaign Creation Tests ===========

    function test_OperatorCanCreateCampaign() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test Airdrop");

        assertEq(campaignId, 0);

        (uint256 appId, address token, bytes32 root, string memory name, uint256 totalClaimed, bool active) =
            distributor.getCampaign(campaignId);

        assertEq(appId, APP_ID);
        assertEq(token, address(appToken));
        assertEq(root, merkleRoot);
        assertEq(name, "Test Airdrop");
        assertEq(totalClaimed, 0);
        assertTrue(active);
    }

    function test_AdminCanCreateCampaign() public {
        vm.prank(admin);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Admin Campaign");
        assertEq(campaignId, 0);
    }

    function test_RevertWhen_UnauthorizedCreatesCampaign() public {
        vm.expectRevert(AirdropDistributor.Unauthorized.selector);
        vm.prank(attacker);
        distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Attacker Campaign");
    }

    function test_RevertWhen_CreateCampaignWithZeroToken() public {
        vm.expectRevert(AirdropDistributor.ZeroAddress.selector);
        vm.prank(operator);
        distributor.createCampaign(APP_ID, address(0), merkleRoot, "Bad Campaign");
    }

    function test_RevertWhen_CreateCampaignWithZeroRoot() public {
        vm.expectRevert(AirdropDistributor.InvalidRoot.selector);
        vm.prank(operator);
        distributor.createCampaign(APP_ID, address(appToken), bytes32(0), "Bad Campaign");
    }

    // =========== Claim Tests ===========

    function test_ValidClaim() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        uint256 balanceBefore = appToken.balanceOf(alice);

        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        uint256 balanceAfter = appToken.balanceOf(alice);
        assertEq(balanceAfter - balanceBefore, aliceAmount);
    }

    function test_ClaimEmitsEvent() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.expectEmit(true, true, true, true);
        emit AirdropDistributor.Claimed(campaignId, alice, aliceAmount);

        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);
    }

    function test_MultipleUsersClaim() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        vm.prank(bob);
        distributor.claim(campaignId, bobAmount, bobProof);

        vm.prank(charlie);
        distributor.claim(campaignId, charlieAmount, charlieProof);

        assertEq(appToken.balanceOf(alice), aliceAmount);
        assertEq(appToken.balanceOf(bob), bobAmount);
        assertEq(appToken.balanceOf(charlie), charlieAmount);
    }

    function test_RevertWhen_DoubleClaim() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        vm.expectRevert(AirdropDistributor.AlreadyClaimed.selector);
        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);
    }

    function test_RevertWhen_InvalidProof() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.expectRevert(AirdropDistributor.InvalidProof.selector);
        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, bobProof); // Wrong proof
    }

    function test_RevertWhen_WrongAmount() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.expectRevert(AirdropDistributor.InvalidProof.selector);
        vm.prank(alice);
        distributor.claim(campaignId, bobAmount, aliceProof); // Wrong amount
    }

    function test_RevertWhen_ClaimFromInactiveCampaign() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.prank(admin);
        distributor.deactivateCampaign(campaignId);

        vm.expectRevert(AirdropDistributor.CampaignInactive.selector);
        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);
    }

    // =========== Campaign Management Tests ===========

    function test_AdminCanDeactivateCampaign() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.prank(admin);
        distributor.deactivateCampaign(campaignId);

        (,,,,, bool active) = distributor.getCampaign(campaignId);
        assertFalse(active);
    }

    function test_RevertWhen_NonAdminDeactivates() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.expectRevert(AirdropDistributor.Unauthorized.selector);
        vm.prank(attacker);
        distributor.deactivateCampaign(campaignId);
    }

    // =========== Admin Functions Tests ===========

    function test_AdminCanSetOperator() public {
        address newOperator = makeAddr("newOperator");

        vm.prank(admin);
        distributor.setOperator(newOperator);

        assertEq(distributor.operator(), newOperator);
    }

    function test_AdminCanTransferAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        distributor.setAdmin(newAdmin);

        assertEq(distributor.admin(), newAdmin);
    }

    function test_AdminCanRescueTokens() public {
        // Create a campaign and have Alice claim
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        // Deactivate and rescue remaining tokens
        vm.prank(admin);
        distributor.deactivateCampaign(campaignId);

        uint256 remaining = appToken.balanceOf(address(distributor));
        address treasury = makeAddr("treasury");

        vm.prank(admin);
        distributor.rescueTokens(address(appToken), treasury, remaining);

        assertEq(appToken.balanceOf(treasury), remaining);
    }

    // =========== View Functions Tests ===========

    function test_HasClaimed() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        assertFalse(distributor.hasClaimed(campaignId, alice));

        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        assertTrue(distributor.hasClaimed(campaignId, alice));
    }

    function test_TotalClaimed() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        vm.prank(bob);
        distributor.claim(campaignId, bobAmount, bobProof);

        (,,,, uint256 totalClaimed,) = distributor.getCampaign(campaignId);
        assertEq(totalClaimed, aliceAmount + bobAmount);
    }

    function test_CampaignCount() public {
        assertEq(distributor.campaignCount(), 0);

        vm.startPrank(operator);
        distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Campaign 1");
        distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Campaign 2");
        distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Campaign 3");
        vm.stopPrank();

        assertEq(distributor.campaignCount(), 3);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_ClaimAmount(uint256 amount) public {
        // Bound to reasonable amounts
        amount = bound(amount, 1 ether, 100_000 ether);

        // Create leaf for fuzz amount
        bytes32 leaf = keccak256(abi.encodePacked(alice, amount));
        bytes32 root = leaf; // Single-leaf tree

        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), root, "Fuzz Test");

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        distributor.claim(campaignId, amount, proof);

        assertEq(appToken.balanceOf(alice), amount);
    }
}
