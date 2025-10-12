// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { RewardsDistributor } from "../../src/rewards/RewardsDistributor.sol";
import { AppRewardsDistributor } from "../../src/rewards/AppRewardsDistributor.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { IVeEltaVotes } from "../../src/interfaces/IVeEltaVotes.sol";
import { IAppRewardsDistributor } from "../../src/interfaces/IAppRewardsDistributor.sol";
import { Errors } from "../../src/utils/Errors.sol";

/**
 * @title RewardsDistributor V2 Tests
 * @notice Unit tests for the new on-chain snapshot-based rewards system
 * @dev V2 architecture is completely different from V1:
 *      - No Merkle roots
 *      - 70/15/15 automatic split
 *      - On-chain snapshot claims
 *      - veELTA epochs at deposit block
 *
 * NOTE: Original V1 tests removed. V2-specific tests below.
 * For comprehensive integration tests, see test/integration/RevenueFlow.t.sol
 */
contract RewardsDistributorTest is Test {
    RewardsDistributor public rewardsDistributor;
    AppRewardsDistributor public appRewardsDistributor;
    VeELTA public veElta;
    ELTA public elta;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public factory = makeAddr("factory");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public revenueSource = makeAddr("revenueSource");

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 0);

        // Deploy veELTA
        veElta = new VeELTA(elta, admin);

        // Deploy AppRewardsDistributor
        appRewardsDistributor = new AppRewardsDistributor(elta, admin, factory);

        // Deploy RewardsDistributor with all dependencies
        rewardsDistributor = new RewardsDistributor(
            elta,
            IVeEltaVotes(address(veElta)),
            IAppRewardsDistributor(address(appRewardsDistributor)),
            treasury,
            admin
        );

        // Grant DISTRIBUTOR_ROLE to revenueSource
        rewardsDistributor.grantRole(rewardsDistributor.DISTRIBUTOR_ROLE(), revenueSource);

        vm.stopPrank();

        // Fund revenue source
        vm.prank(treasury);
        elta.transfer(revenueSource, 100_000 ether);

        // Approve
        vm.prank(revenueSource);
        elta.approve(address(rewardsDistributor), type(uint256).max);
    }

    function test_Deployment() public view {
        assertEq(address(rewardsDistributor.ELTA()), address(elta));
        assertEq(address(rewardsDistributor.veELTA()), address(veElta));
        assertEq(
            address(rewardsDistributor.appRewardsDistributor()), address(appRewardsDistributor)
        );
        assertEq(rewardsDistributor.treasury(), treasury);
        assertEq(rewardsDistributor.BIPS_APP(), 7000); // 70%
        assertEq(rewardsDistributor.BIPS_VEELTA(), 1500); // 15%
        assertEq(rewardsDistributor.BIPS_TREASURY(), 1500); // 15%
    }

    function test_Deposit_70_15_15_Split() public {
        uint256 depositAmount = 1000 ether;
        uint256 treasuryBefore = elta.balanceOf(treasury);

        vm.prank(revenueSource);
        rewardsDistributor.deposit(depositAmount);

        // Treasury should receive 15% immediately
        uint256 expectedTreasury = (depositAmount * 1500) / 10_000;
        assertEq(elta.balanceOf(treasury), treasuryBefore + expectedTreasury);

        // veELTA epoch should be created
        assertEq(rewardsDistributor.getEpochCount(), 1);
        (uint256 blockNumber, uint256 veAmount) = rewardsDistributor.getEpoch(0);
        assertEq(blockNumber, block.number);
        uint256 expectedVe = (depositAmount * 1500) / 10_000;
        assertEq(veAmount, expectedVe);
    }

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(admin);
        rewardsDistributor.setTreasury(newTreasury);

        assertEq(rewardsDistributor.treasury(), newTreasury);
    }

    function test_SetPaused() public {
        assertFalse(rewardsDistributor.paused());

        vm.prank(admin);
        rewardsDistributor.setPaused(true);

        assertTrue(rewardsDistributor.paused());

        // Deposit should fail when paused
        vm.prank(revenueSource);
        vm.expectRevert(RewardsDistributor.OnlyWhenNotPaused.selector);
        rewardsDistributor.deposit(100 ether);
    }

    // NOTE: More comprehensive tests in test/integration/RevenueFlow.t.sol
}
