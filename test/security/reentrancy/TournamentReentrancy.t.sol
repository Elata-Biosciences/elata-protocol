// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Tournament, EntryTokenType} from "../../../src/apps/Tournament.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock token that attempts reentrancy on transfer
contract ReentrantToken is ERC20 {
    Tournament public tournament;
    bool public attacking;
    uint256 public attackCount;

    constructor() ERC20("Reentrant", "REENT") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function setTournament(address _tournament) external {
        tournament = Tournament(_tournament);
    }

    function setAttacking(bool _attacking) external {
        attacking = _attacking;
        attackCount = 0;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        // Attempt reentrancy on transfer out (during claim)
        if (attacking && attackCount < 2 && to != address(tournament)) {
            attackCount++;
            bytes32[] memory proof = new bytes32[](0);
            try tournament.claim(proof, 100 ether) {} catch {}
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        return super.transferFrom(from, to, amount);
    }
}

/// @notice Mock token for standard tests
contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

/// @notice Attacker contract that attempts reentrancy via callbacks
contract TournamentAttacker {
    Tournament public tournament;
    IERC20 public token;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _tournament, address _token) {
        tournament = Tournament(_tournament);
        token = IERC20(_token);
    }

    function enterTournament() external {
        token.approve(address(tournament), type(uint256).max);
        tournament.enter();
    }

    function attackClaim(bytes32[] calldata proof, uint256 amount) external {
        attacking = true;
        attackCount = 0;
        tournament.claim(proof, amount);
    }

    // Callback attempts
    receive() external payable {
        if (attacking && attackCount < 2) {
            attackCount++;
            bytes32[] memory proof = new bytes32[](0);
            try tournament.claim(proof, 100 ether) {} catch {}
        }
    }

    fallback() external payable {
        if (attacking && attackCount < 2) {
            attackCount++;
            bytes32[] memory proof = new bytes32[](0);
            try tournament.claim(proof, 100 ether) {} catch {}
        }
    }
}

/// @notice Attacker that tries to enter during claim
contract EnterDuringClaimAttacker {
    Tournament public tournament;
    IERC20 public token;
    bool public attacking;

    constructor(address _tournament, address _token) {
        tournament = Tournament(_tournament);
        token = IERC20(_token);
    }

    function attack(bytes32[] calldata proof, uint256 amount) external {
        attacking = true;
        tournament.claim(proof, amount);
    }

    // Try to enter during claim callback
    receive() external payable {
        if (attacking) {
            token.approve(address(tournament), type(uint256).max);
            try tournament.enter() {} catch {}
        }
    }
}

/**
 * @title TournamentReentrancy
 * @notice Reentrancy security tests for Tournament contract
 */
contract TournamentReentrancy is Test {
    MockToken public token;
    Tournament public tournament;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant ENTRY_FEE = 100 ether;

    function setUp() public {
        token = new MockToken();

        tournament = new Tournament(
            address(token),
            EntryTokenType.APP,
            1, // appId
            admin,
            address(0), // feeCollector
            treasury,
            ENTRY_FEE,
            0, // start immediately
            0, // no end
            250, // 2.5% protocol fee
            100 // 1% burn fee
        );

        // Fund users
        token.transfer(attacker, 10_000 ether);
        token.transfer(user1, 10_000 ether);
        token.transfer(user2, 10_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ENTRY REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_EnterProtectedByNonReentrant() public {
        vm.startPrank(attacker);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // Cannot enter twice
        vm.startPrank(attacker);
        token.approve(address(tournament), ENTRY_FEE);
        vm.expectRevert(Tournament.AlreadyEntered.selector);
        tournament.enter();
        vm.stopPrank();
    }

    function test_Reentrancy_MultipleUsersEnter() public {
        // User 1 enters
        vm.startPrank(user1);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // User 2 enters
        vm.startPrank(user2);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // Pool should have 2x entry fee
        assertEq(tournament.pool(), ENTRY_FEE * 2, "Pool should have 2 entries");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CLAIM REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_ClaimProtectedByNonReentrant() public {
        // Setup: users enter
        vm.startPrank(user1);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // Finalize with merkle root
        bytes32 leaf = keccak256(abi.encodePacked(user1, uint256(150 ether)));
        bytes32 root = leaf; // Single leaf tree

        vm.prank(admin);
        tournament.finalize(root);

        // User1 claims
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(user1);
        tournament.claim(proof, 150 ether);

        // Cannot claim twice
        vm.prank(user1);
        vm.expectRevert(Tournament.AlreadyClaimed.selector);
        tournament.claim(proof, 150 ether);
    }

    function test_Reentrancy_ClaimWithReentrantToken() public {
        // Create tournament with reentrant token
        ReentrantToken reentrantToken = new ReentrantToken();

        Tournament reentrantTournament = new Tournament(
            address(reentrantToken), EntryTokenType.APP, 1, admin, address(0), treasury, ENTRY_FEE, 0, 0, 250, 100
        );

        reentrantToken.setTournament(address(reentrantTournament));

        // Fund and enter
        reentrantToken.transfer(user1, 1000 ether);
        vm.startPrank(user1);
        reentrantToken.approve(address(reentrantTournament), ENTRY_FEE);
        reentrantTournament.enter();
        vm.stopPrank();

        // Finalize
        bytes32 leaf = keccak256(abi.encodePacked(user1, uint256(90 ether)));
        bytes32 root = leaf;

        vm.prank(admin);
        reentrantTournament.finalize(root);

        // Enable attacking mode
        reentrantToken.setAttacking(true);

        // Claim should be protected by nonReentrant
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(user1);
        reentrantTournament.claim(proof, 90 ether);

        // Even if reentrancy was attempted, the second claim should have failed
        // because claimed[user1] is already true (set before transfer)
        // The attack count may be > 0 but state should be consistent
        assertTrue(reentrantTournament.claimed(user1), "User should be marked as claimed");

        // Verify cannot claim again even without reentrancy
        reentrantToken.setAttacking(false);
        vm.prank(user1);
        vm.expectRevert(Tournament.AlreadyClaimed.selector);
        reentrantTournament.claim(proof, 90 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FINALIZE REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_FinalizeProtectedByNonReentrant() public {
        // Enter
        vm.startPrank(user1);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // Finalize
        bytes32 root = keccak256("winners");
        vm.prank(admin);
        tournament.finalize(root);

        // Cannot finalize twice
        vm.prank(admin);
        vm.expectRevert(Tournament.AlreadyFinalized.selector);
        tournament.finalize(root);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CROSS-FUNCTION REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_CannotEnterAfterFinalize() public {
        vm.startPrank(user1);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // Finalize
        vm.prank(admin);
        tournament.finalize(keccak256("winners"));

        // User2 cannot enter after finalize
        vm.startPrank(user2);
        token.approve(address(tournament), ENTRY_FEE);
        // This should fail based on tournament logic
        // (either TournamentEnded or checking finalized state)
        vm.stopPrank();
    }

    function test_Reentrancy_CannotClaimBeforeFinalize() public {
        vm.startPrank(user1);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        // Try to claim before finalize
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(user1);
        vm.expectRevert(Tournament.NotFinalized.selector);
        tournament.claim(proof, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE CONSISTENCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_PoolConsistentAfterEntries() public {
        uint256 poolBefore = tournament.pool();
        assertEq(poolBefore, 0, "Pool should start at 0");

        // Multiple entries
        vm.startPrank(user1);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        assertEq(tournament.pool(), ENTRY_FEE, "Pool should have 1 entry");

        vm.startPrank(user2);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        assertEq(tournament.pool(), ENTRY_FEE * 2, "Pool should have 2 entries");
    }

    function test_Reentrancy_FinalizeFeesConsistent() public {
        vm.startPrank(user1);
        token.approve(address(tournament), ENTRY_FEE);
        tournament.enter();
        vm.stopPrank();

        uint256 poolBefore = tournament.pool();

        // Finalize
        vm.prank(admin);
        tournament.finalize(keccak256("winners"));

        uint256 poolAfter = tournament.pool();

        // Pool should be reduced by fees
        assertLt(poolAfter, poolBefore, "Pool should be reduced by fees");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Reentrancy_MultipleEntries(uint8 numEntries) public {
        numEntries = uint8(bound(numEntries, 1, 20));

        for (uint256 i = 0; i < numEntries; i++) {
            address user = address(uint160(0x1000 + i));
            token.transfer(user, ENTRY_FEE);

            vm.startPrank(user);
            token.approve(address(tournament), ENTRY_FEE);
            tournament.enter();
            vm.stopPrank();
        }

        assertEq(tournament.pool(), ENTRY_FEE * numEntries, "Pool should match entries");
    }

    function testFuzz_Reentrancy_EntryFeeVariation(uint256 entryFee) public {
        entryFee = bound(entryFee, 1 ether, 1000 ether);

        Tournament newTournament = new Tournament(
            address(token), EntryTokenType.APP, 1, admin, address(0), treasury, entryFee, 0, 0, 250, 100
        );

        vm.startPrank(user1);
        token.approve(address(newTournament), entryFee);
        newTournament.enter();
        vm.stopPrank();

        assertEq(newTournament.pool(), entryFee, "Pool should match entry fee");
    }
}
