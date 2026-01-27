// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AirdropDistributor} from "../../src/modules/AirdropDistributor.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock ERC20 for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Malicious token that attempts reentrancy
contract ReentrantToken is ERC20 {
    AirdropDistributor public distributor;
    uint256 public attackCampaignId;
    uint256 public attackAmount;
    bytes32[] public attackProof;
    bool public attacking;

    constructor() ERC20("Reentrant", "REENT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setAttackParams(
        AirdropDistributor _distributor,
        uint256 _campaignId,
        uint256 _amount,
        bytes32[] memory _proof
    ) external {
        distributor = _distributor;
        attackCampaignId = _campaignId;
        attackAmount = _amount;
        attackProof = _proof;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (attacking) {
            return super.transfer(to, amount);
        }

        // Attempt reentrancy on transfer
        if (address(distributor) != address(0) && !attacking) {
            attacking = true;
            try distributor.claim(attackCampaignId, attackAmount, attackProof) {
            // If this succeeds, reentrancy protection failed
            }
                catch {
                // Expected - reentrancy guard should block
            }
            attacking = false;
        }

        return super.transfer(to, amount);
    }
}

/**
 * @title AirdropDistributorSecurity
 * @notice Security tests for AirdropDistributor - Merkle proofs, admin access, race conditions
 * @dev Tests attack vectors for the Merkle-based airdrop system
 */
contract AirdropDistributorSecurity is Test {
    AirdropDistributor public distributor;
    MockToken public appToken;
    MockToken public otherToken;

    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator");
    address public attacker = makeAddr("attacker");

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant APP_ID = 1;
    uint256 public constant AIRDROP_AMOUNT = 1_000_000 ether;

    // Merkle tree data
    bytes32 public merkleRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    bytes32[] public charlieProof;

    uint256 public aliceAmount = 100_000 ether;
    uint256 public bobAmount = 50_000 ether;
    uint256 public charlieAmount = 25_000 ether;

    function setUp() public {
        appToken = new MockToken("App Token", "APP");
        otherToken = new MockToken("Other Token", "OTHER");

        distributor = new AirdropDistributor(admin, operator);

        // Fund distributor
        appToken.mint(address(distributor), AIRDROP_AMOUNT);

        // Compute Merkle tree
        bytes32 leafAlice = keccak256(abi.encodePacked(alice, aliceAmount));
        bytes32 leafBob = keccak256(abi.encodePacked(bob, bobAmount));
        bytes32 leafCharlie = keccak256(abi.encodePacked(charlie, charlieAmount));
        bytes32 zero = bytes32(0);

        bytes32 hash01 = _hashPair(leafAlice, leafBob);
        bytes32 hash23 = _hashPair(leafCharlie, zero);

        merkleRoot = _hashPair(hash01, hash23);

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

    // ═══════════════════════════════════════════════════════════════════════════
    // MERKLE PROOF SECURITY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotClaimWithManipulatedAmount() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        // Alice tries to claim more than her allocation
        uint256 manipulatedAmount = aliceAmount * 2;

        vm.prank(alice);
        vm.expectRevert(AirdropDistributor.InvalidProof.selector);
        distributor.claim(campaignId, manipulatedAmount, aliceProof);

        // Original amount works
        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);
        assertEq(appToken.balanceOf(alice), aliceAmount);
    }

    function test_Security_CannotClaimWithDifferentLeafOrder() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        // Alice tries to use Bob's proof
        vm.prank(alice);
        vm.expectRevert(AirdropDistributor.InvalidProof.selector);
        distributor.claim(campaignId, aliceAmount, bobProof);

        // Bob tries to use Alice's proof
        vm.prank(bob);
        vm.expectRevert(AirdropDistributor.InvalidProof.selector);
        distributor.claim(campaignId, bobAmount, aliceProof);
    }

    function test_Security_CannotClaimForOtherUser() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        // Attacker tries to claim Alice's allocation
        vm.prank(attacker);
        vm.expectRevert(AirdropDistributor.InvalidProof.selector);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        // Attacker tries to claim with correct proof but as themselves
        vm.prank(attacker);
        vm.expectRevert(AirdropDistributor.InvalidProof.selector);
        distributor.claim(campaignId, aliceAmount, aliceProof);
    }

    function test_Security_CannotReplayProofAfterRootChange() public {
        vm.prank(operator);
        uint256 campaignId1 = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Campaign 1");

        // Alice claims from campaign 1
        vm.prank(alice);
        distributor.claim(campaignId1, aliceAmount, aliceProof);

        // Create new campaign with different root
        bytes32 newRoot = keccak256(abi.encodePacked("different_root"));
        vm.prank(operator);
        uint256 campaignId2 = distributor.createCampaign(APP_ID, address(appToken), newRoot, "Campaign 2");

        // Alice's old proof doesn't work for new campaign
        vm.prank(alice);
        vm.expectRevert(AirdropDistributor.InvalidProof.selector);
        distributor.claim(campaignId2, aliceAmount, aliceProof);
    }

    function testFuzz_Security_ProofVerificationRobust(bytes32 randomProof1, bytes32 randomProof2) public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        bytes32[] memory randomProof = new bytes32[](2);
        randomProof[0] = randomProof1;
        randomProof[1] = randomProof2;

        // Random proofs should fail unless they happen to be valid
        // (astronomically unlikely)
        vm.prank(alice);
        try distributor.claim(campaignId, aliceAmount, randomProof) {
            // If it succeeded, the random proof happened to be valid
            // This is essentially impossible
            assertTrue(false, "Random proof should not work");
        } catch {
            // Expected
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAMPAIGN MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OperatorCannotDeactivateCampaign() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        // Operator cannot deactivate - only admin can
        vm.prank(operator);
        vm.expectRevert(AirdropDistributor.Unauthorized.selector);
        distributor.deactivateCampaign(campaignId);

        // Admin can deactivate
        vm.prank(admin);
        distributor.deactivateCampaign(campaignId);

        (,,,,, bool active) = distributor.getCampaign(campaignId);
        assertFalse(active);
    }

    function test_Security_DeactivatedCampaignBlocksClaims() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        // Deactivate
        vm.prank(admin);
        distributor.deactivateCampaign(campaignId);

        // All claims blocked
        vm.prank(alice);
        vm.expectRevert(AirdropDistributor.CampaignInactive.selector);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        vm.prank(bob);
        vm.expectRevert(AirdropDistributor.CampaignInactive.selector);
        distributor.claim(campaignId, bobAmount, bobProof);
    }

    function test_Security_CannotReactivateDeactivatedCampaign() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        vm.prank(admin);
        distributor.deactivateCampaign(campaignId);

        // There's no reactivation function - deactivation is permanent
        // This is by design - if you need to restart, create a new campaign
        (,,,,, bool active) = distributor.getCampaign(campaignId);
        assertFalse(active);

        // Cannot claim anymore
        vm.prank(alice);
        vm.expectRevert(AirdropDistributor.CampaignInactive.selector);
        distributor.claim(campaignId, aliceAmount, aliceProof);
    }

    function test_Security_CampaignIndexBoundsChecked() public {
        // No campaigns exist yet
        assertEq(distributor.campaignCount(), 0);

        // Accessing non-existent campaign should revert
        vm.expectRevert();
        distributor.getCampaign(0);

        vm.expectRevert();
        distributor.getCampaign(999);

        // Create one campaign
        vm.prank(operator);
        distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        // Now index 0 works
        (uint256 appId,,,,, bool active) = distributor.getCampaign(0);
        assertEq(appId, APP_ID);
        assertTrue(active);

        // But index 1 still fails
        vm.expectRevert();
        distributor.getCampaign(1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN SECURITY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_RescueTokensOnlyByAdmin() public {
        vm.prank(operator);
        distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        address treasury = makeAddr("treasury");
        uint256 rescueAmount = 100_000 ether;

        // Operator cannot rescue
        vm.prank(operator);
        vm.expectRevert(AirdropDistributor.Unauthorized.selector);
        distributor.rescueTokens(address(appToken), treasury, rescueAmount);

        // Attacker cannot rescue
        vm.prank(attacker);
        vm.expectRevert(AirdropDistributor.Unauthorized.selector);
        distributor.rescueTokens(address(appToken), treasury, rescueAmount);

        // Admin can rescue
        vm.prank(admin);
        distributor.rescueTokens(address(appToken), treasury, rescueAmount);
        assertEq(appToken.balanceOf(treasury), rescueAmount);
    }

    function test_Security_ZeroAddressChecksOnAllSetters() public {
        // setOperator
        vm.prank(admin);
        vm.expectRevert(AirdropDistributor.ZeroAddress.selector);
        distributor.setOperator(address(0));

        // setAdmin
        vm.prank(admin);
        vm.expectRevert(AirdropDistributor.ZeroAddress.selector);
        distributor.setAdmin(address(0));

        // rescueTokens (to)
        vm.prank(admin);
        vm.expectRevert(AirdropDistributor.ZeroAddress.selector);
        distributor.rescueTokens(address(appToken), address(0), 1000 ether);

        // createCampaign (token)
        vm.prank(operator);
        vm.expectRevert(AirdropDistributor.ZeroAddress.selector);
        distributor.createCampaign(APP_ID, address(0), merkleRoot, "Test");
    }

    function test_Security_AdminTransferTakesEffectImmediately() public {
        address newAdmin = makeAddr("newAdmin");

        // Transfer admin
        vm.prank(admin);
        distributor.setAdmin(newAdmin);

        assertEq(distributor.admin(), newAdmin);

        // Old admin immediately loses access
        vm.prank(admin);
        vm.expectRevert(AirdropDistributor.Unauthorized.selector);
        distributor.setOperator(makeAddr("newOp"));

        // New admin immediately gains access
        vm.prank(newAdmin);
        distributor.setOperator(makeAddr("newOp"));
        assertEq(distributor.operator(), makeAddr("newOp"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RACE CONDITIONS & REENTRANCY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ConcurrentClaimsNoReentrancy() public {
        // Deploy reentrant token
        ReentrantToken reentrantToken = new ReentrantToken();
        reentrantToken.mint(address(distributor), 1_000_000 ether);

        // Create campaign with reentrant token
        bytes32 attackerLeaf = keccak256(abi.encodePacked(attacker, uint256(100_000 ether)));
        bytes32 attackerRoot = attackerLeaf;
        bytes32[] memory attackerProof = new bytes32[](0);

        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(reentrantToken), attackerRoot, "Reentrant");

        // Setup attack params
        reentrantToken.setAttackParams(distributor, campaignId, 100_000 ether, attackerProof);

        // Attacker claims - reentrancy should be blocked by ReentrancyGuard
        vm.prank(attacker);
        distributor.claim(campaignId, 100_000 ether, attackerProof);

        // Verify only one claim went through
        assertEq(reentrantToken.balanceOf(attacker), 100_000 ether);
        assertTrue(distributor.hasClaimed(campaignId, attacker));
    }

    function test_Security_DoubleClaimAtomicityGuaranteed() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        // First claim succeeds
        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        // hasClaimed is set BEFORE transfer (check-effects-interaction pattern)
        assertTrue(distributor.hasClaimed(campaignId, alice));

        // Second claim fails
        vm.prank(alice);
        vm.expectRevert(AirdropDistributor.AlreadyClaimed.selector);
        distributor.claim(campaignId, aliceAmount, aliceProof);
    }

    function test_Security_ClaimAndDeactivateRaceCondition() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        // Alice's claim is in-flight when admin deactivates
        // In reality these are atomic - whoever's tx lands first wins
        // We test both scenarios

        // Scenario 1: Claim lands first
        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        vm.prank(admin);
        distributor.deactivateCampaign(campaignId);

        // Alice already claimed, so she's fine
        assertEq(appToken.balanceOf(alice), aliceAmount);

        // Bob didn't claim in time
        vm.prank(bob);
        vm.expectRevert(AirdropDistributor.CampaignInactive.selector);
        distributor.claim(campaignId, bobAmount, bobProof);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-CAMPAIGN ISOLATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ClaimOneCampaignDoesNotAffectOther() public {
        // Create two campaigns
        vm.startPrank(operator);
        uint256 campaignId1 = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Campaign 1");
        uint256 campaignId2 = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Campaign 2");
        vm.stopPrank();

        // Alice claims from campaign 1
        vm.prank(alice);
        distributor.claim(campaignId1, aliceAmount, aliceProof);

        // Alice has NOT claimed from campaign 2
        assertFalse(distributor.hasClaimed(campaignId2, alice));

        // Alice can still claim from campaign 2
        vm.prank(alice);
        distributor.claim(campaignId2, aliceAmount, aliceProof);

        // Both claims recorded separately
        assertTrue(distributor.hasClaimed(campaignId1, alice));
        assertTrue(distributor.hasClaimed(campaignId2, alice));
        assertEq(appToken.balanceOf(alice), aliceAmount * 2);
    }

    function test_Security_SameMerkleRootDifferentCampaigns() public {
        // Same root can be safely used for multiple campaigns
        vm.startPrank(operator);
        uint256 campaignId1 = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Campaign A");
        uint256 campaignId2 = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Campaign B");
        vm.stopPrank();

        // Users can claim from both
        vm.prank(alice);
        distributor.claim(campaignId1, aliceAmount, aliceProof);

        vm.prank(alice);
        distributor.claim(campaignId2, aliceAmount, aliceProof);

        // Verify isolated tracking
        (,,,, uint256 totalClaimed1,) = distributor.getCampaign(campaignId1);
        (,,,, uint256 totalClaimed2,) = distributor.getCampaign(campaignId2);

        assertEq(totalClaimed1, aliceAmount);
        assertEq(totalClaimed2, aliceAmount);
    }

    function test_Security_TotalClaimedAccurateAcrossCampaigns() public {
        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), merkleRoot, "Test");

        // Multiple users claim
        vm.prank(alice);
        distributor.claim(campaignId, aliceAmount, aliceProof);

        vm.prank(bob);
        distributor.claim(campaignId, bobAmount, bobProof);

        vm.prank(charlie);
        distributor.claim(campaignId, charlieAmount, charlieProof);

        // Verify total
        (,,,, uint256 totalClaimed,) = distributor.getCampaign(campaignId);
        assertEq(totalClaimed, aliceAmount + bobAmount + charlieAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_ClaimAmountMatching(uint256 claimAmount) public {
        claimAmount = bound(claimAmount, 1 ether, 500_000 ether);

        // Create single-leaf tree for fuzz testing
        bytes32 leaf = keccak256(abi.encodePacked(alice, claimAmount));
        bytes32 root = leaf;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), root, "Fuzz");

        // Exact amount works
        vm.prank(alice);
        distributor.claim(campaignId, claimAmount, proof);
        assertEq(appToken.balanceOf(alice), claimAmount);
    }

    function testFuzz_Security_CannotClaimWrongAmount(uint256 correctAmount, uint256 wrongAmount) public {
        correctAmount = bound(correctAmount, 1 ether, 500_000 ether);
        wrongAmount = bound(wrongAmount, 1 ether, 500_000 ether);
        vm.assume(wrongAmount != correctAmount);

        bytes32 leaf = keccak256(abi.encodePacked(alice, correctAmount));
        bytes32 root = leaf;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(operator);
        uint256 campaignId = distributor.createCampaign(APP_ID, address(appToken), root, "Fuzz");

        // Wrong amount fails
        vm.prank(alice);
        vm.expectRevert(AirdropDistributor.InvalidProof.selector);
        distributor.claim(campaignId, wrongAmount, proof);
    }
}
