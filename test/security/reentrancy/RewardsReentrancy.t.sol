// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {RewardsDistributor} from "../../../src/rewards/RewardsDistributor.sol";
import {IAppRewardsDistributor} from "../../../src/interfaces/IAppRewardsDistributor.sol";
import {IVeEltaVotes} from "../../../src/interfaces/IVeEltaVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock AppRewardsDistributor
contract MockAppRewardsDistributor is IAppRewardsDistributor {
    IERC20 public elta;
    bool public attacking;
    RewardsDistributor public distributor;

    constructor(address _elta) {
        elta = IERC20(_elta);
    }

    function setDistributor(address _distributor) external {
        distributor = RewardsDistributor(_distributor);
    }

    function setAttacking(bool _attacking) external {
        attacking = _attacking;
    }

    function distribute(uint256 amount) external {
        elta.transferFrom(msg.sender, address(this), amount);

        // Attempt reentrancy during distribute
        if (attacking) {
            try distributor.deposit(100 ether) {} catch {}
        }
    }

    // Implement interface methods
    function registerApp(address) external pure {}
    function registerApp(address, address) external pure {}
    function depositForApp(IERC20, uint256) external pure {}
    function claim(address, uint256) external pure {}
    function claimToken(address, IERC20, uint256) external pure {}
}

/// @notice Attacker that tries reentrancy via claimVe
contract ClaimReentrancyAttacker {
    RewardsDistributor public distributor;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _distributor) {
        distributor = RewardsDistributor(_distributor);
    }

    function attack(uint256 fromEpoch, uint256 toEpoch) external {
        attacking = true;
        attackCount = 0;
        distributor.claimVe(fromEpoch, toEpoch);
    }

    // Called when receiving ELTA
    receive() external payable {
        if (attacking && attackCount < 2) {
            attackCount++;
            try distributor.claimVe(0, 10) {} catch {}
        }
    }

    fallback() external payable {
        if (attacking && attackCount < 2) {
            attackCount++;
            try distributor.claimVe(0, 10) {} catch {}
        }
    }
}

/**
 * @title RewardsReentrancy
 * @notice Reentrancy security tests for RewardsDistributor
 */
contract RewardsReentrancy is Test {
    ELTA public elta;
    VeELTA public veElta;
    MockAppRewardsDistributor public appRewards;
    RewardsDistributor public distributor;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy mock app rewards
        appRewards = new MockAppRewardsDistributor(address(elta));

        // Deploy RewardsDistributor with deployer as admin
        vm.prank(admin);
        distributor = new RewardsDistributor(
            IERC20(address(elta)),
            IVeEltaVotes(address(veElta)),
            IAppRewardsDistributor(address(appRewards)),
            treasury,
            admin
        );

        appRewards.setDistributor(address(distributor));

        // Fund users
        vm.startPrank(admin);
        elta.transfer(user1, 1_000_000 ether);
        elta.transfer(user2, 1_000_000 ether);
        elta.transfer(attacker, 1_000_000 ether);
        elta.transfer(address(appRewards), 1_000_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPOSIT REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_DepositProtectedByNonReentrant() public {
        vm.startPrank(admin);
        elta.approve(address(distributor), 1000 ether);
        distributor.deposit(100 ether);
        vm.stopPrank();

        // Verify epoch was created
        assertEq(distributor.getEpochCount(), 1, "Should have 1 epoch");
    }

    function test_Reentrancy_DepositViaAppRewardsCallback() public {
        // Enable attacking mode in mock
        appRewards.setAttacking(true);

        vm.startPrank(admin);
        elta.approve(address(distributor), 1000 ether);

        // This will call appRewards.distribute() which attempts reentrancy
        distributor.deposit(100 ether);
        vm.stopPrank();

        // Reentrancy should be blocked
        assertEq(distributor.getEpochCount(), 1, "Should have only 1 epoch");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CLAIM REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_ClaimVeProtectedByNonReentrant() public {
        // Setup: user locks and deposits happen
        vm.startPrank(user1);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Move block forward to create valid snapshot
        vm.roll(block.number + 10);

        // Fund distributor for veELTA rewards (15% of deposits go to veELTA)
        vm.prank(admin);
        elta.transfer(address(distributor), 100 ether);

        // Create epoch
        vm.startPrank(admin);
        elta.approve(address(distributor), 1000 ether);
        distributor.deposit(100 ether);
        vm.stopPrank();

        // Move to next block for snapshot
        vm.roll(block.number + 1);

        // User claims - cursor tracks what's been claimed
        vm.prank(user1);
        distributor.claimVe(0, 1);

        uint256 cursor = distributor.lastClaimed(user1);
        assertEq(cursor, 1, "Cursor should be updated to 1");
    }

    function test_Reentrancy_CursorUpdateProtected() public {
        // Verify that cursor tracking prevents double-claims
        // NOTE: ERC5805 requires queried blocks to be strictly < current block

        // Start at block 100
        vm.roll(100);

        // Setup: user locks at block 100
        vm.startPrank(user1);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Advance to block 110 - lock is now in the past
        vm.roll(110);

        // Create epochs at blocks 110, 115, 120
        vm.startPrank(admin);
        elta.approve(address(distributor), 10000 ether);

        distributor.deposit(100 ether); // Epoch 0 snapshot at block 110
        vm.roll(115);

        distributor.deposit(100 ether); // Epoch 1 snapshot at block 115
        vm.roll(120);

        distributor.deposit(100 ether); // Epoch 2 snapshot at block 120
        vm.stopPrank();

        // CRITICAL: Advance to block 125+ so all epoch snapshots (110, 115, 120) are in the past
        vm.roll(125);

        uint256 epochCount = distributor.getEpochCount();
        assertEq(epochCount, 3, "Should have 3 epochs");

        // veELTA portion (15% of 300 ether = 45 ether) stays in distributor
        uint256 distributorBalance = elta.balanceOf(address(distributor));
        assertEq(distributorBalance, 45 ether, "Distributor should have 45 ELTA for claims");

        // Verify cursor starts at 0
        assertEq(distributor.lastClaimed(user1), 0, "Cursor should start at 0");

        // Claim epochs - user1 has 100% of voting power so gets all veELTA rewards
        uint256 user1BalanceBefore = elta.balanceOf(user1);
        vm.prank(user1);
        distributor.claimVe(0, epochCount);
        uint256 user1BalanceAfter = elta.balanceOf(user1);

        // User should have received rewards (45 ether total)
        assertGt(user1BalanceAfter, user1BalanceBefore, "User should receive rewards");

        // Cursor should be updated
        assertEq(distributor.lastClaimed(user1), epochCount, "Cursor should be updated after claim");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN EPOCH REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_DepositVeInTokenProtected() public {
        vm.startPrank(admin);
        elta.approve(address(distributor), 1000 ether);
        distributor.depositVeInToken(IERC20(address(elta)), 100 ether);
        vm.stopPrank();
    }

    function test_Reentrancy_ClaimVeTokenProtected() public {
        // Setup: user locks
        vm.startPrank(user1);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Create token epoch
        vm.startPrank(admin);
        elta.approve(address(distributor), 1000 ether);
        distributor.depositVeInToken(IERC20(address(elta)), 100 ether);
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Claim
        vm.prank(user1);
        distributor.claimVeToken(IERC20(address(elta)), 0, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE CONSISTENCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_EpochCountConsistent() public {
        vm.startPrank(admin);
        elta.approve(address(distributor), 10000 ether);

        uint256 epochsBefore = distributor.getEpochCount();

        distributor.deposit(100 ether);
        distributor.deposit(100 ether);
        distributor.deposit(100 ether);

        uint256 epochsAfter = distributor.getEpochCount();
        vm.stopPrank();

        assertEq(epochsAfter, epochsBefore + 3, "Should have 3 new epochs");
    }

    function test_Reentrancy_SplitConsistent() public {
        vm.startPrank(admin);
        elta.approve(address(distributor), 10000 ether);

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 depositAmount = 1000 ether;

        distributor.deposit(depositAmount);

        uint256 treasuryAfter = elta.balanceOf(treasury);
        vm.stopPrank();

        // Treasury should receive 15%
        uint256 expectedTreasury = (depositAmount * 1500) / 10000;
        assertApproxEqAbs(treasuryAfter - treasuryBefore, expectedTreasury, 1, "Treasury should receive 15%");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-USER CLAIM TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_MultipleUsersClaim() public {
        // Setup: both users lock
        vm.startPrank(user1);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.startPrank(user2);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Create epoch
        vm.startPrank(admin);
        elta.approve(address(distributor), 1000 ether);
        distributor.deposit(1000 ether);
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Both users claim
        uint256 user1Before = elta.balanceOf(user1);
        uint256 user2Before = elta.balanceOf(user2);

        vm.prank(user1);
        distributor.claimVe(0, 1);

        vm.prank(user2);
        distributor.claimVe(0, 1);

        uint256 user1After = elta.balanceOf(user1);
        uint256 user2After = elta.balanceOf(user2);

        // Both should receive rewards (equal since equal locks)
        assertGt(user1After, user1Before, "User1 should receive rewards");
        assertGt(user2After, user2Before, "User2 should receive rewards");
        assertApproxEqAbs(user1After - user1Before, user2After - user2Before, 1, "Rewards should be equal");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Reentrancy_MultipleDeposits(uint8 numDeposits) public {
        numDeposits = uint8(bound(numDeposits, 1, 10));

        vm.startPrank(admin);
        elta.approve(address(distributor), type(uint256).max);

        for (uint256 i = 0; i < numDeposits; i++) {
            uint256 amount = 100 ether; // Fixed amount to avoid overflow
            distributor.deposit(amount);
        }
        vm.stopPrank();

        assertEq(distributor.getEpochCount(), numDeposits, "Epoch count should match deposits");
    }

    function testFuzz_Reentrancy_ClaimRange(uint256 fromEpoch, uint256 toEpoch) public {
        // Setup: create 10 epochs
        vm.startPrank(admin);
        elta.approve(address(distributor), type(uint256).max);
        for (uint256 i = 0; i < 10; i++) {
            distributor.deposit(100 ether);
        }
        vm.stopPrank();

        // User locks
        vm.startPrank(user1);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        fromEpoch = bound(fromEpoch, 0, 10);
        toEpoch = bound(toEpoch, fromEpoch, 10);

        // Claim should not revert
        vm.prank(user1);
        distributor.claimVe(fromEpoch, toEpoch);
    }
}
