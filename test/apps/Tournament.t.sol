// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { Tournament } from "../../src/apps/Tournament.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { Merkle } from "murky/src/Merkle.sol";

contract TournamentTest is Test {
    Tournament public tournament;
    AppToken public appToken;
    Merkle public merkle;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public admin = makeAddr("admin");

    uint256 public constant ENTRY_FEE = 100 ether;
    uint256 public constant PROTOCOL_FEE_BPS = 250; // 2.5%
    uint256 public constant BURN_FEE_BPS = 100; // 1%
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    event Entered(address indexed user, uint256 fee);
    event Finalized(bytes32 winnersRoot, uint256 netPool, uint256 protocolFee, uint256 burned);
    event Claimed(address indexed user, uint256 amount);

    function setUp() public {
        appToken = new AppToken("TestApp", "TEST", 18, MAX_SUPPLY, owner, admin);
        merkle = new Merkle();

        tournament = new Tournament(
            address(appToken),
            owner,
            treasury,
            ENTRY_FEE,
            0, // start immediately
            0, // no end time
            PROTOCOL_FEE_BPS,
            BURN_FEE_BPS
        );

        // Mint tokens to users
        vm.startPrank(admin);
        appToken.mint(user1, 10000 ether);
        appToken.mint(user2, 10000 ether);
        appToken.mint(user3, 10000 ether);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public {
        assertEq(address(tournament.APP()), address(appToken));
        assertEq(tournament.owner(), owner);
        assertEq(tournament.protocolTreasury(), treasury);
        assertEq(tournament.entryFee(), ENTRY_FEE);
        assertEq(tournament.protocolFeeBps(), PROTOCOL_FEE_BPS);
        assertEq(tournament.burnFeeBps(), BURN_FEE_BPS);
        assertFalse(tournament.finalized());
    }

    function test_RevertWhen_DeploymentInvalidWindow() public {
        vm.expectRevert(Tournament.InvalidWindow.selector);
        new Tournament(
            address(appToken),
            owner,
            treasury,
            ENTRY_FEE,
            100, // start
            50, // end before start
            PROTOCOL_FEE_BPS,
            BURN_FEE_BPS
        );
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ENTRY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Enter() public {
        vm.startPrank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);

        vm.expectEmit(true, true, true, true);
        emit Entered(user1, ENTRY_FEE);

        tournament.enter();
        vm.stopPrank();

        assertTrue(tournament.entered(user1));
        assertEq(tournament.pool(), ENTRY_FEE);
    }

    function test_MultipleUsersEnter() public {
        // User1 enters
        vm.startPrank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // User2 enters
        vm.startPrank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // User3 enters
        vm.startPrank(user3);
        appToken.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        assertEq(tournament.pool(), ENTRY_FEE * 3);
    }

    function test_RevertWhen_EnterTwice() public {
        vm.startPrank(user1);
        appToken.approve(address(tournament), ENTRY_FEE * 2);
        tournament.enter();

        vm.expectRevert(Tournament.AlreadyEntered.selector);
        tournament.enter();
        vm.stopPrank();
    }

    function test_RevertWhen_EnterBeforeStart() public {
        Tournament futureTourn = new Tournament(
            address(appToken),
            owner,
            treasury,
            ENTRY_FEE,
            uint64(block.timestamp + 1000),
            0,
            PROTOCOL_FEE_BPS,
            BURN_FEE_BPS
        );

        vm.startPrank(user1);
        appToken.approve(address(futureTourn), ENTRY_FEE);

        vm.expectRevert(Tournament.TournamentNotStarted.selector);
        futureTourn.enter();
        vm.stopPrank();
    }

    function test_RevertWhen_EnterAfterEnd() public {
        Tournament pastTourn = new Tournament(
            address(appToken),
            owner,
            treasury,
            ENTRY_FEE,
            0,
            uint64(block.timestamp + 1000),
            PROTOCOL_FEE_BPS,
            BURN_FEE_BPS
        );

        vm.warp(block.timestamp + 1001);

        vm.startPrank(user1);
        appToken.approve(address(pastTourn), ENTRY_FEE);

        vm.expectRevert(Tournament.TournamentEnded.selector);
        pastTourn.enter();
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FINALIZATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Finalize() public {
        // Three users enter
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user1);
        tournament.enter();

        vm.prank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user2);
        tournament.enter();

        vm.prank(user3);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user3);
        tournament.enter();

        uint256 totalPool = ENTRY_FEE * 3;
        uint256 protocolFee = (totalPool * PROTOCOL_FEE_BPS) / 10_000;
        uint256 burnFee = (totalPool * BURN_FEE_BPS) / 10_000;
        uint256 netPool = totalPool - protocolFee - burnFee;

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(150 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(100 ether)));

        bytes32 root = merkle.getRoot(data);

        vm.expectEmit(true, true, true, true);
        emit Finalized(root, netPool, protocolFee, burnFee);

        vm.prank(owner);
        tournament.finalize(root);

        assertTrue(tournament.finalized());
        assertEq(tournament.winnersRoot(), root);
        assertEq(tournament.pool(), netPool);
        assertEq(appToken.balanceOf(treasury), protocolFee);
    }

    function test_RevertWhen_FinalizeUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        tournament.finalize(bytes32(0));
    }

    function test_RevertWhen_FinalizeTwice() public {
        vm.startPrank(owner);
        tournament.finalize(bytes32(uint256(1)));

        vm.expectRevert(Tournament.AlreadyFinalized.selector);
        tournament.finalize(bytes32(uint256(2)));
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // CLAIM TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Claim() public {
        // Setup: users enter
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user1);
        tournament.enter();

        vm.prank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user2);
        tournament.enter();

        // Generate Merkle tree
        uint256 user1Prize = 150 ether;
        uint256 user2Prize = 100 ether;

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, user1Prize));
        data[1] = keccak256(abi.encodePacked(user2, user2Prize));

        bytes32 root = merkle.getRoot(data);

        // Finalize
        vm.prank(owner);
        tournament.finalize(root);

        // User1 claims
        bytes32[] memory proof = merkle.getProof(data, 0);
        uint256 initialBalance = appToken.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit Claimed(user1, user1Prize);

        vm.prank(user1);
        tournament.claim(proof, user1Prize);

        assertEq(appToken.balanceOf(user1), initialBalance + user1Prize);
        assertTrue(tournament.claimed(user1));
    }

    function test_RevertWhen_ClaimBeforeFinalize() public {
        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(Tournament.NotFinalized.selector);
        vm.prank(user1);
        tournament.claim(proof, 100 ether);
    }

    function test_RevertWhen_ClaimTwice() public {
        // Setup and finalize
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE * 2);
        vm.prank(user1);
        tournament.enter();

        vm.prank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user2);
        tournament.enter();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(50 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(30 ether)));
        bytes32 root = merkle.getRoot(data);

        vm.prank(owner);
        tournament.finalize(root);

        // First claim
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.prank(user1);
        tournament.claim(proof, 50 ether);

        // Second claim attempt
        vm.expectRevert(Tournament.AlreadyClaimed.selector);
        vm.prank(user1);
        tournament.claim(proof, 50 ether);
    }

    function test_RevertWhen_ClaimWithInvalidProof() public {
        // Setup and finalize
        vm.prank(user1);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user1);
        tournament.enter();

        vm.prank(user2);
        appToken.approve(address(tournament), ENTRY_FEE);
        vm.prank(user2);
        tournament.enter();

        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(user1, uint256(50 ether)));
        data[1] = keccak256(abi.encodePacked(user2, uint256(40 ether)));
        bytes32 root = merkle.getRoot(data);

        vm.prank(owner);
        tournament.finalize(root);

        // Try to claim with wrong amount
        bytes32[] memory proof = merkle.getProof(data, 0);
        vm.expectRevert(Tournament.InvalidProof.selector);
        vm.prank(user1);
        tournament.claim(proof, 100 ether); // wrong amount
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ADMIN FUNCTION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_SetFees() public {
        vm.prank(owner);
        tournament.setFees(300, 200);

        assertEq(tournament.protocolFeeBps(), 300);
        assertEq(tournament.burnFeeBps(), 200);
    }

    function test_RevertWhen_SetFeesTooHigh() public {
        vm.expectRevert(Tournament.FeesTooHigh.selector);
        vm.prank(owner);
        tournament.setFees(1000, 600); // 16% total
    }

    function test_RevertWhen_SetFeesAfterFinalize() public {
        vm.prank(owner);
        tournament.finalize(bytes32(0));

        vm.expectRevert(Tournament.AlreadyFinalized.selector);
        vm.prank(owner);
        tournament.setFees(100, 50);
    }

    function test_SetWindow() public {
        uint64 newStart = uint64(block.timestamp + 100);
        uint64 newEnd = uint64(block.timestamp + 200);

        vm.prank(owner);
        tournament.setWindow(newStart, newEnd);

        assertEq(tournament.startTime(), newStart);
        assertEq(tournament.endTime(), newEnd);
    }

    function test_SetEntryFee() public {
        uint256 newFee = 200 ether;

        vm.prank(owner);
        tournament.setEntryFee(newFee);

        assertEq(tournament.entryFee(), newFee);
    }
}
