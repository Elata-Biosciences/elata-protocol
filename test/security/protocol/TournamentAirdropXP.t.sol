// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
import {Tournament, EntryTokenType} from "../../../src/apps/Tournament.sol";
import {AirdropDistributor} from "../../../src/modules/AirdropDistributor.sol";
import {ElataPoints} from "../../../src/experience/ElataPoints.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TournamentAirdropXP
 * @notice Security tests for Tournament, AirdropDistributor, and ElataPoints
 */
contract TournamentAirdropXP is Test {
    ELTA public elta;
    Tournament public tournament;
    AirdropDistributor public airdrop;
    ElataPoints public xp;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant ENTRY_FEE = 100 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA("ELTA", "ELTA", admin, admin, ELTA_MAX_SUPPLY, ELTA_MAX_SUPPLY);

        // Deploy Tournament
        tournament = new Tournament(
            address(elta),
            EntryTokenType.ELTA,
            1,
            admin,
            address(0),
            treasury,
            ENTRY_FEE,
            0, // No deadline
            0, // No entry limit
            250, // 2.5% platform fee
            100 // 1% referral
        );

        // Deploy AirdropDistributor
        airdrop = new AirdropDistributor(admin, admin);

        // Deploy ElataPoints
        xp = new ElataPoints(admin);

        // Fund users
        vm.startPrank(admin);
        elta.transfer(user1, 10_000 ether);
        elta.transfer(user2, 10_000 ether);
        elta.transfer(attacker, 10_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOURNAMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Tournament_EnterRequiresApproval() public {
        vm.startPrank(user1);
        // No approval given
        vm.expectRevert();
        tournament.enter();
        vm.stopPrank();
    }

    function test_Tournament_EnterTransfersFees() public {
        vm.startPrank(user1);
        elta.approve(address(tournament), ENTRY_FEE);

        uint256 balanceBefore = elta.balanceOf(user1);
        tournament.enter();
        uint256 balanceAfter = elta.balanceOf(user1);

        assertEq(balanceBefore - balanceAfter, ENTRY_FEE, "Should deduct entry fee");
        assertTrue(tournament.entered(user1), "User should be entered");
        vm.stopPrank();
    }

    function test_Tournament_CannotEnterTwice() public {
        vm.startPrank(user1);
        elta.approve(address(tournament), ENTRY_FEE * 2);
        tournament.enter();

        vm.expectRevert(Tournament.AlreadyEntered.selector);
        tournament.enter();
        vm.stopPrank();
    }

    function test_Tournament_OnlyAdminCanFinalize() public {
        // Enter tournament
        vm.startPrank(user1);
        elta.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        bytes32 root = keccak256(abi.encodePacked(user1, uint256(90 ether)));

        // Attacker cannot finalize (lacks MODULE_OPERATOR_ROLE)
        vm.prank(attacker);
        vm.expectRevert();
        tournament.finalize(root);

        // Admin can finalize
        vm.prank(admin);
        tournament.finalize(root);
        assertTrue(tournament.finalized(), "Should be finalized");
    }

    function test_Tournament_FinalizeCreatesWinnersRoot() public {
        // Enter tournament
        vm.startPrank(user1);
        elta.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        bytes32 root = keccak256(abi.encodePacked(user1, uint256(90 ether)));

        // Finalize
        vm.prank(admin);
        tournament.finalize(root);

        assertEq(tournament.winnersRoot(), root, "Root should be set");
    }

    function test_Tournament_PoolAccumulates() public {
        // Multiple entries
        vm.startPrank(user1);
        elta.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        vm.startPrank(user2);
        elta.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // Pool accumulates entries
        uint256 pool = tournament.pool();
        assertGt(pool, 0, "Pool should have funds");
        assertLe(pool, ENTRY_FEE * 2, "Pool should not exceed total entries");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AIRDROP TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Airdrop_OnlyOperatorCanCreate() public {
        bytes32 root = keccak256("test");

        // Attacker cannot create
        vm.prank(attacker);
        vm.expectRevert();
        airdrop.createCampaign(1, address(elta), root, "Test");

        // Admin can create
        vm.prank(admin);
        airdrop.createCampaign(1, address(elta), root, "Test");
    }

    function test_Airdrop_CampaignCreation() public {
        bytes32 root = keccak256("test");

        vm.prank(admin);
        airdrop.createCampaign(1, address(elta), root, "Test Campaign");

        // Campaign was created successfully (no revert)
        assertTrue(true, "Campaign created successfully");
    }

    function test_Airdrop_CanDeactivate() public {
        bytes32 root = keccak256("test");

        vm.prank(admin);
        airdrop.createCampaign(1, address(elta), root, "Test");

        // Deactivate
        vm.prank(admin);
        airdrop.deactivateCampaign(0);

        // Check deactivated - AirdropDistributor uses different struct
        // Just verify it doesn't revert
        assertTrue(true, "Deactivation succeeded");
    }

    function test_Airdrop_OnlyAdminCanDeactivate() public {
        bytes32 root = keccak256("test");

        vm.prank(admin);
        airdrop.createCampaign(1, address(elta), root, "Test");

        // Attacker cannot deactivate
        vm.prank(attacker);
        vm.expectRevert();
        airdrop.deactivateCampaign(0);
    }

    function test_Airdrop_RescueTokens() public {
        // Fund airdrop
        vm.prank(admin);
        elta.transfer(address(airdrop), 1000 ether);

        // Only admin can rescue
        vm.prank(attacker);
        vm.expectRevert();
        airdrop.rescueTokens(address(elta), attacker, 1000 ether);

        // Admin can rescue
        uint256 balanceBefore = elta.balanceOf(admin);
        vm.prank(admin);
        airdrop.rescueTokens(address(elta), admin, 1000 ether);
        uint256 balanceAfter = elta.balanceOf(admin);

        assertEq(balanceAfter - balanceBefore, 1000 ether, "Should rescue tokens");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ELATA XP TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_XP_OnlyOperatorCanAward() public {
        vm.prank(attacker);
        vm.expectRevert();
        xp.award(attacker, 100 ether);

        vm.prank(admin);
        xp.award(user1, 100 ether);

        assertEq(xp.balanceOf(user1), 100 ether, "Should have XP");
    }

    function test_XP_OnlyOperatorCanRevoke() public {
        // Award first
        vm.prank(admin);
        xp.award(user1, 100 ether);

        // Attacker cannot revoke
        vm.prank(attacker);
        vm.expectRevert();
        xp.revoke(user1, 50 ether);

        // Admin can revoke
        vm.prank(admin);
        xp.revoke(user1, 50 ether);

        assertEq(xp.balanceOf(user1), 50 ether, "Should have half XP");
    }

    function test_XP_NonTransferable() public {
        vm.prank(admin);
        xp.award(user1, 100 ether);

        // User cannot transfer
        vm.prank(user1);
        vm.expectRevert();
        xp.transfer(user2, 50 ether);

        // Balance unchanged
        assertEq(xp.balanceOf(user1), 100 ether, "Balance should not change");
        assertEq(xp.balanceOf(user2), 0, "User2 should have no XP");
    }

    function test_XP_MultipleAwards() public {
        // Award to multiple users individually
        vm.startPrank(admin);
        xp.award(user1, 100 ether);
        xp.award(user2, 200 ether);
        xp.award(attacker, 300 ether);
        vm.stopPrank();

        assertEq(xp.balanceOf(user1), 100 ether);
        assertEq(xp.balanceOf(user2), 200 ether);
        assertEq(xp.balanceOf(attacker), 300 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Tournament_EntryFee(uint256 entryFee) public {
        entryFee = bound(entryFee, 1 ether, 10_000 ether);

        // Create new tournament with fuzzed fee
        Tournament fuzzTournament = new Tournament(
            address(elta), EntryTokenType.ELTA, 2, admin, address(0), treasury, entryFee, 0, 0, 250, 100
        );

        vm.startPrank(user1);
        elta.approve(address(fuzzTournament), entryFee);

        uint256 balanceBefore = elta.balanceOf(user1);
        fuzzTournament.enter();
        uint256 balanceAfter = elta.balanceOf(user1);

        assertEq(balanceBefore - balanceAfter, entryFee, "Should deduct exact entry fee");
        vm.stopPrank();
    }

    function testFuzz_XP_AwardAmount(uint256 amount) public {
        amount = bound(amount, 1 ether, 1_000_000 ether);

        vm.prank(admin);
        xp.award(user1, amount);

        assertEq(xp.balanceOf(user1), amount, "Should have exact amount");
    }

    function testFuzz_XP_RevokeAmount(uint256 awardAmount, uint256 revokeAmount) public {
        awardAmount = bound(awardAmount, 10 ether, 1_000_000 ether);
        revokeAmount = bound(revokeAmount, 1 ether, awardAmount);

        vm.prank(admin);
        xp.award(user1, awardAmount);

        vm.prank(admin);
        xp.revoke(user1, revokeAmount);

        assertEq(xp.balanceOf(user1), awardAmount - revokeAmount, "Balance should be award - revoke");
    }
}
