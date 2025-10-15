// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppStakingVault } from "../../src/apps/AppStakingVault.sol";
import { AppRewardsDistributor } from "../../src/rewards/AppRewardsDistributor.sol";

contract AppRewardsDistributorTest is Test {
    ELTA public elta;
    AppRewardsDistributor public distributor;

    AppToken public token1;
    AppToken public token2;
    AppStakingVault public vault1;
    AppStakingVault public vault2;

    address public governance = address(0x1);
    address public factory = address(0x2);
    address public rewardsSource = address(0x3);
    address public alice = address(0x4);
    address public bob = address(0x5);

    event AppRegistered(address indexed vault);
    event AppPaused(address indexed vault, bool paused);
    event AppRemoved(address indexed vault);
    event AppDistributed(uint256 indexed blockNumber, uint256 totalAmount, uint256 activeApps);
    event AppClaim(
        address indexed vault,
        address indexed user,
        uint256 fromEpoch,
        uint256 toEpoch,
        uint256 amount
    );

    function setUp() public {
        // Deploy ELTA
        elta = new ELTA("ELTA", "ELTA", governance, governance, 1_000_000 ether, 0);

        // Deploy distributor
        distributor = new AppRewardsDistributor(elta, governance, factory);

        // Deploy app 1
        token1 = new AppToken(
            "Game1",
            "GM1",
            18,
            1_000_000 ether,
            alice,
            address(this),
            address(1),
            address(1),
            address(1),
            address(1)
        );
        vault1 = new AppStakingVault("Game1", "GM1", token1, alice);
        token1.mint(address(this), 1_000_000 ether);

        // Deploy app 2
        token2 = new AppToken(
            "Game2",
            "GM2",
            18,
            1_000_000 ether,
            bob,
            address(this),
            address(1),
            address(1),
            address(1),
            address(1)
        );
        vault2 = new AppStakingVault("Game2", "GM2", token2, bob);
        token2.mint(address(this), 1_000_000 ether);

        // Fund users with app tokens
        token1.transfer(alice, 100_000 ether);
        token1.transfer(bob, 100_000 ether);
        token2.transfer(alice, 100_000 ether);
        token2.transfer(bob, 100_000 ether);

        // Make vaults exempt from transfer fees
        token1.setTransferFeeExempt(address(vault1), true);
        token2.setTransferFeeExempt(address(vault2), true);

        // Fund rewards source with ELTA (extra for transfer fees)
        vm.prank(governance);
        elta.transfer(rewardsSource, 200_000 ether);

        // Approve distributor
        vm.prank(rewardsSource);
        elta.approve(address(distributor), type(uint256).max);

        // Users approve vaults
        vm.prank(alice);
        token1.approve(address(vault1), type(uint256).max);
        vm.prank(alice);
        token2.approve(address(vault2), type(uint256).max);
        vm.prank(bob);
        token1.approve(address(vault1), type(uint256).max);
        vm.prank(bob);
        token2.approve(address(vault2), type(uint256).max);
    }

    function test_InitialState() public view {
        assertEq(address(distributor.ELTA()), address(elta));
        assertEq(distributor.getVaultCount(), 0);
    }

    function test_RegisterApp() public {
        vm.expectEmit(true, false, false, false);
        emit AppRegistered(address(vault1));

        vm.prank(factory);
        distributor.registerApp(address(vault1));

        assertTrue(distributor.isVault(address(vault1)));
        assertTrue(distributor.isActive(address(vault1)));
        assertEq(distributor.getVaultCount(), 1);
        assertEq(distributor.vaults(0), address(vault1));
    }

    function test_RegisterApp_RevertIfNotFactory() public {
        vm.prank(alice);
        vm.expectRevert();
        distributor.registerApp(address(vault1));
    }

    function test_RegisterApp_RevertIfExists() public {
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        vm.prank(factory);
        vm.expectRevert(AppRewardsDistributor.VaultExists.selector);
        distributor.registerApp(address(vault1));
    }

    function test_PauseApp() public {
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        vm.expectEmit(true, false, false, true);
        emit AppPaused(address(vault1), true);

        vm.prank(governance);
        distributor.pauseApp(address(vault1), true);

        assertFalse(distributor.isActive(address(vault1)));

        // Unpause
        vm.prank(governance);
        distributor.pauseApp(address(vault1), false);

        assertTrue(distributor.isActive(address(vault1)));
    }

    function test_RemoveApp() public {
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        vm.expectEmit(true, false, false, false);
        emit AppRemoved(address(vault1));

        vm.prank(governance);
        distributor.removeApp(address(vault1));

        assertFalse(distributor.isActive(address(vault1)));
    }

    function test_Distribute_SingleVault() public {
        // Register vault
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        // Alice stakes
        vm.prank(alice);
        vault1.stake(1000 ether);

        // Distribute rewards
        uint256 rewardAmount = 100 ether;

        vm.expectEmit(true, false, false, true);
        emit AppDistributed(block.number, rewardAmount, 1);

        vm.prank(rewardsSource);
        distributor.distribute(rewardAmount);

        // Check epoch created
        assertEq(distributor.getEpochCount(address(vault1)), 1);
        (uint256 blockNumber, uint256 amount, uint256 totalStaked) =
            distributor.epochs(address(vault1), 0);
        assertEq(blockNumber, block.number);
        assertEq(amount, rewardAmount); // 100% to single vault
        assertEq(totalStaked, 1000 ether);
    }

    function test_Distribute_MultipleVaults_EqualStakes() public {
        // Register vaults
        vm.prank(factory);
        distributor.registerApp(address(vault1));
        vm.prank(factory);
        distributor.registerApp(address(vault2));

        // Equal stakes
        vm.prank(alice);
        vault1.stake(1000 ether);
        vm.prank(bob);
        vault2.stake(1000 ether);

        // Distribute rewards
        uint256 rewardAmount = 100 ether;

        vm.prank(rewardsSource);
        distributor.distribute(rewardAmount);

        // Check both vaults got equal share
        (, uint256 amount1,) = distributor.epochs(address(vault1), 0);
        (, uint256 amount2,) = distributor.epochs(address(vault2), 0);

        assertEq(amount1, 50 ether);
        assertEq(amount2, 50 ether);
    }

    function test_Distribute_MultipleVaults_UnequalStakes() public {
        // Register vaults
        vm.prank(factory);
        distributor.registerApp(address(vault1));
        vm.prank(factory);
        distributor.registerApp(address(vault2));

        // Unequal stakes: vault1 has 75%, vault2 has 25%
        vm.prank(alice);
        vault1.stake(3000 ether);
        vm.prank(bob);
        vault2.stake(1000 ether);

        // Distribute rewards
        uint256 rewardAmount = 100 ether;

        vm.prank(rewardsSource);
        distributor.distribute(rewardAmount);

        // Check proportional distribution
        (, uint256 amount1,) = distributor.epochs(address(vault1), 0);
        (, uint256 amount2,) = distributor.epochs(address(vault2), 0);

        assertEq(amount1, 75 ether); // 75%
        assertEq(amount2, 25 ether); // 25%
    }

    function test_Distribute_SkipsPausedVaults() public {
        // Register vaults
        vm.prank(factory);
        distributor.registerApp(address(vault1));
        vm.prank(factory);
        distributor.registerApp(address(vault2));

        // Stakes
        vm.prank(alice);
        vault1.stake(1000 ether);
        vm.prank(bob);
        vault2.stake(1000 ether);

        // Pause vault1
        vm.prank(governance);
        distributor.pauseApp(address(vault1), true);

        // Distribute rewards
        uint256 rewardAmount = 100 ether;

        vm.prank(rewardsSource);
        distributor.distribute(rewardAmount);

        // Only vault2 should get rewards
        assertEq(distributor.getEpochCount(address(vault1)), 0);
        assertEq(distributor.getEpochCount(address(vault2)), 1);

        (, uint256 amount2,) = distributor.epochs(address(vault2), 0);
        assertEq(amount2, rewardAmount); // 100% to vault2
    }

    function test_Distribute_ZeroStake() public {
        // Register vault
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        // No stakes (totalSupply = 0)

        // Distribute rewards
        vm.prank(rewardsSource);
        distributor.distribute(100 ether);

        // Epoch created but with 0 amount
        assertEq(distributor.getEpochCount(address(vault1)), 1);
        (, uint256 amount,) = distributor.epochs(address(vault1), 0);
        assertEq(amount, 0);
    }

    function test_Claim_SingleEpoch() public {
        // Start from higher block to avoid Foundry initial block issues
        vm.roll(100);

        // Setup: register, stake
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        vm.prank(alice);
        vault1.stake(1000 ether);

        // Roll forward 2 blocks to ensure stake snapshot is well in past
        vm.roll(102);

        // Distribute (records snapshot at block 102)
        vm.prank(rewardsSource);
        distributor.distribute(100 ether);

        // Roll forward 2 blocks so distribute snapshot is well in past
        vm.roll(104);

        // Alice claims
        uint256 aliceBalanceBefore = elta.balanceOf(alice);

        vm.expectEmit(true, true, false, true);
        emit AppClaim(address(vault1), alice, 0, 1, 100 ether);

        vm.prank(alice);
        distributor.claim(address(vault1), 1);

        assertEq(elta.balanceOf(alice), aliceBalanceBefore + 100 ether);
        assertEq(distributor.userCursor(alice, address(vault1)), 1);
    }

    function test_Claim_MultipleUsers() public {
        vm.roll(100);

        // Setup: register, multiple stakes
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        // Alice stakes 60%, Bob stakes 40%
        vm.prank(alice);
        vault1.stake(600 ether);
        vm.prank(bob);
        vault1.stake(400 ether);

        // Roll so stakes are in past
        vm.roll(102);

        vm.prank(rewardsSource);
        distributor.distribute(100 ether);

        vm.roll(104);

        // Alice claims
        vm.prank(alice);
        distributor.claim(address(vault1), 1);
        assertEq(elta.balanceOf(alice), 60 ether);

        // Bob claims
        vm.prank(bob);
        distributor.claim(address(vault1), 1);
        assertEq(elta.balanceOf(bob), 40 ether);
    }

    function test_Claim_MultipleEpochs() public {
        vm.roll(100);

        // Setup
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        vm.prank(alice);
        vault1.stake(1000 ether);

        // Roll so stake is in past
        vm.roll(102);

        // Distribute 3 epochs (each at explicit block)
        vm.prank(rewardsSource);
        distributor.distribute(100 ether);
        vm.roll(104);

        vm.prank(rewardsSource);
        distributor.distribute(100 ether);
        vm.roll(106);

        vm.prank(rewardsSource);
        distributor.distribute(100 ether);
        vm.roll(108);

        // Alice claims all
        vm.prank(alice);
        distributor.claim(address(vault1), 3);

        assertEq(elta.balanceOf(alice), 300 ether);
        assertEq(distributor.userCursor(alice, address(vault1)), 3);
    }

    function test_Claim_GasBounded() public {
        vm.roll(100);

        // Setup
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        vm.prank(alice);
        vault1.stake(1000 ether);

        // Roll so stake is in past
        vm.roll(102);

        // Distribute 150 epochs
        uint256 currentBlock = 102;
        for (uint256 i = 0; i < 150; i++) {
            vm.prank(rewardsSource);
            distributor.distribute(1 ether);
            currentBlock += 2;
            vm.roll(currentBlock);
        }

        // First claim: processes max 100 epochs
        vm.prank(alice);
        distributor.claim(address(vault1), 150);

        assertEq(elta.balanceOf(alice), 100 ether);
        assertEq(distributor.userCursor(alice, address(vault1)), 100);

        // Second claim: processes remaining 50
        vm.prank(alice);
        distributor.claim(address(vault1), 150);

        assertEq(elta.balanceOf(alice), 150 ether);
        assertEq(distributor.userCursor(alice, address(vault1)), 150);
    }

    function test_Claim_SkipsEpochsWithZeroStake() public {
        vm.roll(100);

        // Setup
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        // Alice stakes
        vm.prank(alice);
        vault1.stake(1000 ether);
        vm.roll(102); // Stake in past

        // Distribute epoch 0
        vm.prank(rewardsSource);
        distributor.distribute(100 ether);
        vm.roll(104);

        // Alice unstakes
        vm.prank(alice);
        vault1.unstake(1000 ether);
        vm.roll(106); // Unstake in past

        // Distribute epoch 1 (she has no stake)
        vm.prank(rewardsSource);
        distributor.distribute(100 ether);
        vm.roll(108);

        // Alice re-stakes
        vm.prank(alice);
        vault1.stake(1000 ether);
        vm.roll(110); // Re-stake in past

        // Distribute epoch 2
        vm.prank(rewardsSource);
        distributor.distribute(100 ether);
        vm.roll(112);

        // Alice claims
        vm.prank(alice);
        distributor.claim(address(vault1), 3);

        // Should only get epochs 0 and 2
        assertEq(elta.balanceOf(alice), 200 ether);
    }

    function test_ClaimMultiple() public {
        vm.roll(100);

        // Setup two vaults
        vm.prank(factory);
        distributor.registerApp(address(vault1));
        vm.prank(factory);
        distributor.registerApp(address(vault2));

        // Alice stakes in both
        vm.prank(alice);
        vault1.stake(1000 ether);
        vm.prank(alice);
        vault2.stake(1000 ether);

        // Roll so stakes are in past
        vm.roll(102);

        // Distribute to both
        vm.prank(rewardsSource);
        distributor.distribute(100 ether);
        vm.roll(104);

        // Alice claims from both vaults at once
        address[] memory vaults = new address[](2);
        vaults[0] = address(vault1);
        vaults[1] = address(vault2);

        uint256[] memory toEpochs = new uint256[](2);
        toEpochs[0] = 1;
        toEpochs[1] = 1;

        vm.prank(alice);
        distributor.claimMultiple(vaults, toEpochs);

        // Each vault got 50 ELTA (50% each), Alice had 100% of each
        assertEq(elta.balanceOf(alice), 100 ether);
    }

    function test_EstimatePendingRewards() public {
        vm.roll(100);

        // Setup
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        vm.prank(alice);
        vault1.stake(600 ether);
        vm.prank(bob);
        vault1.stake(400 ether);

        // Roll so stakes are in past
        vm.roll(102);

        vm.prank(rewardsSource);
        distributor.distribute(100 ether);
        vm.roll(104);

        // Estimate
        uint256 alicePending = distributor.estimatePendingRewards(alice, address(vault1));
        uint256 bobPending = distributor.estimatePendingRewards(bob, address(vault1));

        assertEq(alicePending, 60 ether);
        assertEq(bobPending, 40 ether);
    }

    function test_GetUnclaimedRange() public {
        vm.prank(factory);
        distributor.registerApp(address(vault1));

        vm.prank(alice);
        vault1.stake(1000 ether);

        // Distribute 5 epochs
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(rewardsSource);
            distributor.distribute(10 ether);
        }

        (uint256 from, uint256 to) = distributor.getUnclaimedRange(alice, address(vault1));
        assertEq(from, 0);
        assertEq(to, 5);

        // Claim first 3
        vm.roll(block.number + 1);
        vm.prank(alice);
        distributor.claim(address(vault1), 3);

        (from, to) = distributor.getUnclaimedRange(alice, address(vault1));
        assertEq(from, 3);
        assertEq(to, 5);
    }

    function test_GetAllVaults() public {
        vm.prank(factory);
        distributor.registerApp(address(vault1));
        vm.prank(factory);
        distributor.registerApp(address(vault2));

        address[] memory vaults = distributor.getAllVaults();
        assertEq(vaults.length, 2);
        assertEq(vaults[0], address(vault1));
        assertEq(vaults[1], address(vault2));
    }
}
