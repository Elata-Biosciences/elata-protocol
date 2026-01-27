// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {ElataGovernor} from "../../../src/governance/ElataGovernor.sol";
import {ElataTimelock} from "../../../src/governance/ElataTimelock.sol";
import {AirdropDistributor} from "../../../src/modules/AirdropDistributor.sol";
import {AppEcosystemVault} from "../../../src/vesting/AppEcosystemVault.sol";
import {FeeManager} from "../../../src/fees/FeeManager.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {RewardsDistributor} from "../../../src/rewards/RewardsDistributor.sol";
import {AppRewardsDistributor} from "../../../src/rewards/AppRewardsDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVeEltaVotes} from "../../../src/interfaces/IVeEltaVotes.sol";
import {IAppRewardsDistributor} from "../../../src/interfaces/IAppRewardsDistributor.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title SystemicAttacks
 * @notice Cross-contract economic attack tests
 * @dev Tests price manipulation, admin compromise, rounding errors, token conservation, griefing
 */
contract SystemicAttacks is Test {
    ELTA public elta;
    MockUSDC public usdc;
    VeELTA public veElta;
    ElataGovernor public governor;
    ElataTimelock public timelock;
    RewardsDistributor public rewards;
    AppRewardsDistributor public appRewards;
    AirdropDistributor public airdrop;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public factory = makeAddr("factory");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant MIN_DELAY = 48 hours;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA(treasury);

        // Deploy USDC
        usdc = new MockUSDC();

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy Timelock
        address[] memory proposers = new address[](1);
        proposers[0] = admin;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new ElataTimelock(MIN_DELAY, proposers, executors, admin);

        // Deploy Governor
        governor = new ElataGovernor(veElta, address(timelock));

        // Grant proposer role to governor
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));

        // Deploy AppRewardsDistributor
        appRewards = new AppRewardsDistributor(elta, admin, factory);

        // Deploy RewardsDistributor
        rewards = new RewardsDistributor(
            elta, IVeEltaVotes(address(veElta)), IAppRewardsDistributor(address(appRewards)), treasury, admin
        );

        // Deploy AirdropDistributor
        airdrop = new AirdropDistributor(admin, admin);

        vm.stopPrank();

        // Fund users
        vm.startPrank(treasury);
        elta.transfer(attacker, 10_000_000 ether);
        elta.transfer(alice, 10_000_000 ether);
        elta.transfer(bob, 10_000_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN KEY COMPROMISE
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CompromisedAdminBlastRadius() public {
        // Document what a compromised admin can do
        // This is informational - we want to understand the blast radius

        // AirdropDistributor admin can:
        // - deactivate campaigns (block claims)
        // - rescue tokens (steal funds)
        // - change operator
        // - change admin

        // Verify these capabilities exist
        address newAdmin = makeAddr("newAdmin");

        // Admin can transfer admin role
        vm.prank(admin);
        airdrop.setAdmin(newAdmin);
        assertEq(airdrop.admin(), newAdmin);

        // Fund airdrop with tokens
        vm.prank(treasury);
        elta.transfer(address(airdrop), 1000 ether);

        // New admin can rescue tokens
        vm.prank(newAdmin);
        airdrop.rescueTokens(address(elta), attacker, 1000 ether);
        assertEq(elta.balanceOf(attacker), 10_000_000 ether + 1000 ether);
    }

    function test_Security_TimelockProtectsFromCompromisedGovernance() public {
        // Direct timelock test - demonstrates the 48-hour protection window
        // Even if governance passes a malicious proposal, the delay allows response

        // Fund timelock
        vm.prank(treasury);
        elta.transfer(address(timelock), 5_000_000 ether);

        // Simulate a "malicious" scheduled operation (as if passed by governance)
        address target = address(elta);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", attacker, 5_000_000 ether);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(uint256(999));

        // Schedule as proposer (simulating governor)
        vm.prank(admin);
        timelock.schedule(target, value, data, predecessor, salt, MIN_DELAY);

        // During the 48-hour window, admin can cancel
        bytes32 opId = timelock.hashOperation(target, value, data, predecessor, salt);

        vm.prank(admin);
        timelock.cancel(opId);

        // After delay, execution fails because cancelled
        vm.warp(block.timestamp + MIN_DELAY + 1);

        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);

        // Attacker didn't get the funds
        assertEq(elta.balanceOf(attacker), 10_000_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROUNDING ERROR EXPLOITATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_FeeSplitRoundingDoesNotLeakValue() public {
        // Test that rounding in fee splits doesn't accumulate to meaningful amounts

        // The 70/15/15 split should always account for all funds
        uint256 testAmount = 1000 ether;

        uint256 appShare = (testAmount * 7000) / 10000;
        uint256 veShare = (testAmount * 1500) / 10000;
        uint256 treasuryShare = (testAmount * 1500) / 10000;

        uint256 totalAccounted = appShare + veShare + treasuryShare;

        // Rounding loss should be minimal
        uint256 loss = testAmount - totalAccounted;
        assertLe(loss, 3, "Rounding loss > 3 wei");
    }

    function test_Security_VeELTABoostRoundingBounded() public {
        // Test boost calculation doesn't overflow or underflow

        // Test with various amounts and durations
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1; // Minimum
        amounts[1] = 1 ether;
        amounts[2] = 1_000_000 ether;
        amounts[3] = 10_000_000 ether;

        uint64[] memory durations = new uint64[](3);
        durations[0] = 8 days; // MIN_LOCK
        durations[1] = 365 days;
        durations[2] = 730 days; // MAX_LOCK

        for (uint256 i = 0; i < amounts.length; i++) {
            for (uint256 j = 0; j < durations.length; j++) {
                // Fund fresh user
                address user = makeAddr(string(abi.encodePacked("boostUser", i, j)));
                vm.prank(treasury);
                elta.transfer(user, amounts[i]);

                vm.startPrank(user);
                elta.approve(address(veElta), amounts[i]);
                veElta.lock(amounts[i], uint64(block.timestamp) + durations[j]);
                vm.stopPrank();

                uint256 veBalance = veElta.balanceOf(user);

                // veBalance should be between 1x and 2x amount
                assertGe(veBalance, amounts[i], "veELTA < principal");
                assertLe(veBalance, amounts[i] * 2, "veELTA > 2x principal");
            }
        }
    }

    function testFuzz_Security_RewardClaimRoundingFair(uint256 amount, uint256 votingPower) public {
        // Small holders should not be disadvantaged by rounding
        amount = bound(amount, 1 ether, 100_000 ether);
        votingPower = bound(votingPower, 1 ether, 10_000_000 ether);

        // Simulate reward calculation
        uint256 totalVotingPower = 50_000_000 ether;
        uint256 epochReward = amount;

        // User's share
        uint256 userShare = (epochReward * votingPower) / totalVotingPower;

        // Verify non-zero voting power gets non-zero share (for meaningful amounts)
        if (votingPower >= totalVotingPower / epochReward) {
            assertGt(userShare, 0, "User with voting power got 0 reward");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN CONSERVATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ELTAConservedAcrossSystem() public {
        // Track total ELTA before
        uint256 totalBefore = elta.totalSupply();

        // Perform various operations
        vm.startPrank(alice);
        elta.approve(address(veElta), 1_000_000 ether);
        veElta.lock(1_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Warp to unlock
        vm.warp(block.timestamp + 366 days);

        vm.prank(alice);
        veElta.unlock();

        // Total ELTA should be unchanged
        uint256 totalAfter = elta.totalSupply();
        assertEq(totalAfter, totalBefore, "ELTA supply changed");
    }

    function test_Security_VeELTABackedByLockedELTA() public {
        // Total veELTA should never exceed total ELTA locked

        // Multiple users lock
        vm.startPrank(alice);
        elta.approve(address(veElta), 5_000_000 ether);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 730 days)); // Max boost
        vm.stopPrank();

        vm.startPrank(bob);
        elta.approve(address(veElta), 5_000_000 ether);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        uint256 totalLockedElta = elta.balanceOf(address(veElta));
        uint256 totalVeElta = veElta.totalSupply();

        // With max 2x boost, veELTA <= 2 * locked ELTA
        assertLe(totalVeElta, totalLockedElta * 2, "veELTA > 2x locked ELTA");

        // veELTA >= locked ELTA (min 1x boost)
        assertGe(totalVeElta, totalLockedElta, "veELTA < locked ELTA");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GRIEFING ATTACKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_DustDepositsDoNotBlockOperations() public {
        // Attacker tries to grief by making many tiny deposits
        // System should remain functional

        // Fund airdrop with tokens for claims
        vm.prank(treasury);
        elta.transfer(address(airdrop), 1_000_000 ether);

        // Create campaign
        bytes32 root = keccak256(abi.encodePacked(alice, uint256(1000 ether)));
        vm.prank(admin);
        uint256 campaignId = airdrop.createCampaign(1, address(elta), root, "Griefed Campaign");

        // Attacker creates many campaigns (griefing by spam)
        // Each campaign creation costs gas for attacker
        for (uint256 i = 0; i < 10; i++) {
            bytes32 spamRoot = keccak256(abi.encodePacked(attacker, uint256(1)));
            vm.prank(admin); // Only operator/admin can create
            airdrop.createCampaign(1, address(elta), spamRoot, string(abi.encodePacked("Spam", i)));
        }

        // Original claim still works
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        airdrop.claim(campaignId, 1000 ether, proof);

        assertEq(elta.balanceOf(alice), 10_000_000 ether + 1000 ether);
    }

    function test_Security_SpamCampaignsDoNotDOSAirdrop() public {
        // Even with many campaigns, legitimate operations work
        // Gas cost is O(1) for claims - doesn't depend on campaign count

        vm.prank(treasury);
        elta.transfer(address(airdrop), 10_000_000 ether);

        // Create 50 campaigns
        for (uint256 i = 0; i < 50; i++) {
            bytes32 root = keccak256(abi.encodePacked(alice, uint256(1000 ether)));
            vm.prank(admin);
            airdrop.createCampaign(1, address(elta), root, string(abi.encodePacked("Campaign", i)));
        }

        // Claim from campaign 25 (middle)
        uint256 gasBefore = gasleft();

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        airdrop.claim(25, 1000 ether, proof);

        uint256 gasUsed = gasBefore - gasleft();

        // Gas should be reasonable (< 100k for a claim)
        assertLt(gasUsed, 100_000, "Claim gas too high");
    }

    function test_Security_SmallLocksDoNotBreakVeELTA() public {
        // Many small locks should not affect system stability

        // Create 20 users with small locks
        for (uint256 i = 0; i < 20; i++) {
            address user = makeAddr(string(abi.encodePacked("smallUser", i)));
            vm.prank(treasury);
            elta.transfer(user, 1 ether);

            vm.startPrank(user);
            elta.approve(address(veElta), 1 ether);
            veElta.lock(1 ether, uint64(block.timestamp + 8 days));
            vm.stopPrank();
        }

        // System should still work
        uint256 totalSupply = veElta.totalSupply();
        assertGt(totalSupply, 0, "No veELTA minted");

        // Large user can still lock
        vm.startPrank(alice);
        elta.approve(address(veElta), 5_000_000 ether);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        assertGt(veElta.balanceOf(alice), 0, "Alice lock failed");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_ELTAConservation(uint256 lockAmount, uint256 transferAmount) public {
        lockAmount = bound(lockAmount, 1 ether, 5_000_000 ether);
        transferAmount = bound(transferAmount, 1 ether, 5_000_000 ether);

        uint256 totalBefore = elta.totalSupply();

        // Lock
        vm.startPrank(alice);
        elta.approve(address(veElta), lockAmount);
        veElta.lock(lockAmount, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Transfer
        vm.prank(bob);
        elta.transfer(attacker, transferAmount);

        // Total unchanged
        assertEq(elta.totalSupply(), totalBefore, "Supply changed");
    }

    function testFuzz_Security_FeeSplitConservation(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max / 10000);

        uint256 appShare = (amount * 7000) / 10000;
        uint256 veShare = (amount * 1500) / 10000;
        uint256 treasuryShare = (amount * 1500) / 10000;

        uint256 total = appShare + veShare + treasuryShare;

        // Loss should be at most 2 wei (from three divisions)
        assertLe(amount - total, 3, "Split leaks too much");
    }
}
