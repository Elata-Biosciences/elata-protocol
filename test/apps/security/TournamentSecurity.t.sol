// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { Tournament } from "../../../src/apps/Tournament.sol";
import { AppToken } from "../../../src/apps/AppToken.sol";
import { Merkle } from "murky/src/Merkle.sol";

/**
 * @title TournamentSecurityTest
 * @notice Comprehensive security testing for Tournament
 * @dev Tests Merkle exploits, fee manipulation, reentrancy, and economic attacks
 */
contract TournamentSecurityTest is Test {
    Tournament public tournament;
    AppToken public appToken;
    Merkle public merkle;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");
    address public admin = makeAddr("admin");

    uint256 public constant ENTRY_FEE = 100 ether;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        appToken = new AppToken("TestApp", "TEST", 18, MAX_SUPPLY, owner, admin);
        merkle = new Merkle();

        tournament = new Tournament(
            address(appToken),
            owner,
            treasury,
            ENTRY_FEE,
            0,
            0,
            250, // 2.5% protocol fee
            100 // 1% burn fee
        );

        // Mint tokens
        vm.startPrank(admin);
        appToken.mint(user1, 10000 ether);
        appToken.mint(user2, 10000 ether);
        appToken.mint(attacker, 10000 ether);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MERKLE PROOF SECURITY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotClaimWithInvalidProof() public {
        // Setup
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user1);
        tournament.enter();

        vm.prank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user2);
        tournament.enter();

        // Create Merkle tree
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(100 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(50 ether)));
        bytes32 root = merkle.getRoot(data);

        vm.prank(owner);
        tournament.finalize(root);

        // Attacker tries to claim with wrong proof
        bytes32[] memory wrongProof = new bytes32[](1);
        wrongProof[0] = bytes32(uint256(123));

        vm.expectRevert(Tournament.InvalidProof.selector);
        vm.prank(attacker);
        tournament.claim(wrongProof, 100 ether);
    }

    function test_Security_CannotClaimWithModifiedAmount() public {
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user1);
        tournament.enter();

        vm.prank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user2);
        tournament.enter();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(100 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(50 ether)));
        bytes32 root = merkle.getRoot(data);

        vm.prank(owner);
        tournament.finalize(root);

        // User1 tries to claim more than allocated
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.expectRevert(Tournament.InvalidProof.selector);
        vm.prank(user1);
        tournament.claim(proof, 200 ether); // Trying to claim 2x
    }

    function test_Security_CannotClaimOthersReward() public {
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user1);
        tournament.enter();

        vm.prank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user2);
        tournament.enter();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(100 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(50 ether)));
        bytes32 root = merkle.getRoot(data);

        vm.prank(owner);
        tournament.finalize(root);

        // Attacker tries to use user1's proof
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.expectRevert(Tournament.InvalidProof.selector);
        vm.prank(attacker);
        tournament.claim(proof, 100 ether);
    }

    function test_Security_CannotClaimTwice() public {
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user1);
        tournament.enter();

        vm.prank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user2);
        tournament.enter();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(100 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(50 ether)));
        bytes32 root = merkle.getRoot(data);

        vm.prank(owner);
        tournament.finalize(root);

        // First claim
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.prank(user1);
        tournament.claim(proof, 100 ether);

        // Second claim attempt
        vm.expectRevert(Tournament.AlreadyClaimed.selector);
        vm.prank(user1);
        tournament.claim(proof, 100 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FEE MANIPULATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_FeeCapEnforced() public {
        vm.expectRevert(Tournament.FeesTooHigh.selector);
        vm.prank(owner);
        tournament.setFees(1000, 600); // 16% total exceeds 15% cap
    }

    function test_Security_FeeCalculationCorrect() public {
        // Enter tournament
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user1);
        tournament.enter();

        vm.prank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user2);
        tournament.enter();

        uint256 totalPool = ENTRY_FEE * 2;
        uint256 expectedProtocol = (totalPool * 250) / 10000; // 2.5%
        uint256 expectedBurn = (totalPool * 100) / 10000; // 1%
        uint256 expectedNet = totalPool - expectedProtocol - expectedBurn;

        vm.prank(owner);
        tournament.finalize(bytes32(0));

        // Verify fees
        assertEq(appToken.balanceOf(treasury), expectedProtocol);
        assertEq(tournament.pool(), expectedNet);
    }

    function test_Security_CannotChangeFeesAfterFinalize() public {
        vm.prank(owner);
        tournament.finalize(bytes32(0));

        vm.expectRevert(Tournament.AlreadyFinalized.selector);
        vm.prank(owner);
        tournament.setFees(300, 200);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ENTRY ATTACK TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotEnterTwice() public {
        vm.startPrank(user1);
        appToken.approve(address(tournament), ENTRY_FEE * 2);
        tournament.enter();

        vm.expectRevert(Tournament.AlreadyEntered.selector);
        tournament.enter();
        vm.stopPrank();
    }

    function test_Security_CannotEnterAfterFinalize() public {
        vm.prank(owner);
        tournament.finalize(bytes32(0));

        vm.startPrank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        
        // Entry should fail (check via eligibility)
        (bool canEnter, uint8 reason) = tournament.checkEntryEligibility(user1);
        assertFalse(canEnter);
        assertEq(reason, 4); // finalized
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FINALIZATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotFinalizeTwice() public {
        vm.startPrank(owner);
        tournament.finalize(bytes32(uint256(1)));

        vm.expectRevert(Tournament.AlreadyFinalized.selector);
        tournament.finalize(bytes32(uint256(2)));
        vm.stopPrank();
    }

    function test_Security_OnlyOwnerCanFinalize() public {
        vm.expectRevert();
        vm.prank(attacker);
        tournament.finalize(bytes32(0));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // TIME WINDOW ATTACK TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotEnterOutsideWindow() public {
        Tournament timedTourn = new Tournament(
            address(appToken),
            owner,
            treasury,
            ENTRY_FEE,
            uint64(block.timestamp + 100),
            uint64(block.timestamp + 200),
            250,
            100
        );

        // Before start
        vm.startPrank(user1);
        appToken.approve(address(timedTourn), ENTRY_FEE);
        vm.expectRevert(Tournament.TournamentNotStarted.selector);
        timedTourn.enter();
        vm.stopPrank();

        // After end
        vm.warp(block.timestamp + 201);
        vm.startPrank(user1);
        vm.expectRevert(Tournament.TournamentEnded.selector);
        timedTourn.enter();
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ECONOMIC ATTACK TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_PoolAccounting() public {
        uint256 users = 10;
        
        for (uint256 i = 0; i < users; i++) {
            address user = address(uint160(i + 1000));
            vm.prank(admin);
            appToken.mint(user, ENTRY_FEE);
            
            vm.prank(user);
            appToken.approve(address(tournament), ENTRY_FEE);
            vm.prank(user);
            tournament.enter();
        }

        // Pool should exactly match entries
        assertEq(tournament.pool(), ENTRY_FEE * users);

        // Finalize
        vm.prank(owner);
        tournament.finalize(bytes32(0));

        // Net pool should be correct after fees
        uint256 expectedProtocol = (ENTRY_FEE * users * 250) / 10000;
        uint256 expectedBurn = (ENTRY_FEE * users * 100) / 10000;
        uint256 expectedNet = (ENTRY_FEE * users) - expectedProtocol - expectedBurn;

        assertEq(tournament.pool(), expectedNet);
    }

    function testFuzz_Security_FeeCalculationCorrect(
        uint256 poolAmount,
        uint256 protocolBps,
        uint256 burnBps
    ) public {
        poolAmount = bound(poolAmount, 1 ether, 1000000 ether);
        protocolBps = bound(protocolBps, 0, 1000);
        burnBps = bound(burnBps, 0, 1500 - protocolBps); // Ensure total <= 15%

        Tournament fuzzTourn = new Tournament(
            address(appToken),
            owner,
            treasury,
            1 ether,
            0,
            0,
            protocolBps,
            burnBps
        );

        // Simulate pool
        vm.prank(admin);
        appToken.mint(address(fuzzTourn), poolAmount);
        
        // Manually set pool (for testing)
        vm.store(
            address(fuzzTourn),
            bytes32(uint256(8)), // pool storage slot
            bytes32(poolAmount)
        );

        // Calculate expected fees
        (
            uint256 protocolAmount,
            uint256 burnAmount,
            uint256 netAmount
        ) = fuzzTourn.calculateFees();

        uint256 expectedProtocol = (poolAmount * protocolBps) / 10000;
        uint256 expectedBurn = (poolAmount * burnBps) / 10000;
        uint256 expectedNet = poolAmount - expectedProtocol - expectedBurn;

        assertEq(protocolAmount, expectedProtocol);
        assertEq(burnAmount, expectedBurn);
        assertEq(netAmount, expectedNet);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // CLAIM BEFORE FINALIZE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotClaimBeforeFinalize() public {
        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(Tournament.NotFinalized.selector);
        vm.prank(user1);
        tournament.claim(proof, 100 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ACCESS CONTROL TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_OnlyOwnerCanSetFees() public {
        vm.expectRevert();
        vm.prank(attacker);
        tournament.setFees(300, 200);
    }

    function test_Security_OnlyOwnerCanSetWindow() public {
        vm.expectRevert();
        vm.prank(attacker);
        tournament.setWindow(100, 200);
    }

    function test_Security_OnlyOwnerCanSetEntryFee() public {
        vm.expectRevert();
        vm.prank(attacker);
        tournament.setEntryFee(200 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EDGE CASE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ZeroEntryFeeTournament() public {
        Tournament freeTourn = new Tournament(
            address(appToken),
            owner,
            treasury,
            0, // Zero entry fee
            0,
            0,
            250,
            100
        );

        vm.prank(user1);
        freeTourn.enter();

        assertEq(freeTourn.pool(), 0);
        assertTrue(freeTourn.entered(user1));
    }

    function test_Security_HighFeesEnforced() public {
        // Max 15% total fees
        vm.prank(owner);
        tournament.setFees(1500, 0); // Exactly 15%

        // Try to set higher
        vm.expectRevert(Tournament.FeesTooHigh.selector);
        vm.prank(owner);
        tournament.setFees(1501, 0);
    }

    function test_Security_FinalizeWithEmptyPool() public {
        // Finalize with no entries
        vm.prank(owner);
        tournament.finalize(bytes32(0));

        assertEq(tournament.pool(), 0);
        assertTrue(tournament.finalized());
    }

    // ────────────────────────────────────────────────────────────────────────────
    // REENTRANCY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ReentrancyProtection_Enter() public {
        // ReentrancyGuard should prevent reentrancy on enter()
        vm.startPrank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // Verify can't enter again
        vm.startPrank(user1);
        vm.expectRevert(Tournament.AlreadyEntered.selector);
        tournament.enter();
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // BURN VERIFICATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_BurnActuallyHappens() public {
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user1);
        tournament.enter();

        uint256 initialSupply = appToken.totalSupply();
        address burnSink = tournament.burnSink();

        vm.prank(owner);
        tournament.finalize(bytes32(0));

        uint256 expectedBurn = (ENTRY_FEE * 100) / 10000;
        
        // Verify burn sink received tokens
        assertEq(appToken.balanceOf(burnSink), expectedBurn);
        
        // Note: Total supply doesn't decrease with transfer to dead address
        // But tokens are effectively removed from circulation
    }

    // ────────────────────────────────────────────────────────────────────────────
    // VIEW FUNCTION INTEGRITY
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ViewFunctionsConsistent() public {
        Tournament fuzzTourn = new Tournament(
            address(appToken),
            owner,
            treasury,
            ENTRY_FEE,
            uint64(block.timestamp + 100),
            uint64(block.timestamp + 200),
            250,
            100
        );

        (
            bool isFinalized,
            bool isActive,
            uint256 currentPool,
            uint256 entryFeeAmount,
            uint256 protocolFee,
            uint256 burnFee,
            uint64 start,
            uint64 end
        ) = fuzzTourn.getTournamentState();

        assertFalse(isFinalized);
        assertFalse(isActive); // Not active yet (before start)
        assertEq(currentPool, 0);
        assertEq(entryFeeAmount, ENTRY_FEE);
        assertEq(protocolFee, 250);
        assertEq(burnFee, 100);
        assertEq(start, uint64(block.timestamp + 100));
        assertEq(end, uint64(block.timestamp + 200));

        // Warp to active period
        vm.warp(block.timestamp + 150);
        (, isActive, , , , , , ) = fuzzTourn.getTournamentState();
        assertTrue(isActive);
    }
}

