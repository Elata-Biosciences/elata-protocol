// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { AppModuleFactory } from "../../src/apps/AppModuleFactory.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppAccess1155 } from "../../src/apps/AppAccess1155.sol";
import { AppStakingVault } from "../../src/apps/AppStakingVault.sol";
import { ELTA } from "../../src/token/ELTA.sol";

contract AppModuleFactoryTest is Test {
    AppModuleFactory public factory;
    ELTA public elta;
    AppToken public appToken;

    address public factoryOwner = makeAddr("factoryOwner");
    address public treasury = makeAddr("treasury");
    address public appCreator = makeAddr("appCreator");
    address public user1 = makeAddr("user1");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
    uint256 public constant CREATE_FEE = 50 ether;

    event ModulesDeployed(
        address indexed appToken,
        address access1155,
        address stakingVault,
        address epochRewards
    );
    event TreasurySet(address treasury);
    event FeeSet(uint256 fee);

    function setUp() public {
        // Deploy ELTA
        elta = new ELTA(
            "ELTA",
            "ELTA",
            factoryOwner,
            factoryOwner,
            1000000 ether,
            77000000 ether
        );

        // Deploy factory
        factory = new AppModuleFactory(address(elta), factoryOwner, treasury);

        // Deploy app token
        appToken = new AppToken(
            "TestApp",
            "TEST",
            18,
            MAX_SUPPLY,
            appCreator,
            admin
        );

        // Mint ELTA to app creator for fees
        vm.prank(factoryOwner);
        elta.mint(appCreator, 1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public {
        assertEq(factory.ELTA(), address(elta));
        assertEq(factory.owner(), factoryOwner);
        assertEq(factory.treasury(), treasury);
        assertEq(factory.createFeeELTA(), 0);
    }

    function test_DeploymentWithZeroELTA() public {
        AppModuleFactory noFeeFactory = new AppModuleFactory(
            address(0),
            factoryOwner,
            treasury
        );

        assertEq(noFeeFactory.ELTA(), address(0));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MODULE DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_DeployModules() public {
        string memory baseURI = "https://metadata.test/";

        vm.expectEmit(true, false, false, false);
        emit ModulesDeployed(address(appToken), address(0), address(0), address(0));

        vm.prank(appCreator);
        (address access1155, address staking, address epochs) = factory.deployModules(
            address(appToken),
            baseURI
        );

        // Verify addresses are non-zero
        assertTrue(access1155 != address(0));
        assertTrue(staking != address(0));
        assertTrue(epochs != address(0));

        // Verify registry
        (address storedAccess, address storedStaking, address storedEpochs) =
            factory.modulesByApp(address(appToken));
        assertEq(storedAccess, access1155);
        assertEq(storedStaking, staking);
        assertEq(storedEpochs, epochs);

        // Verify ownership
        assertEq(AppAccess1155(access1155).owner(), appCreator);
        assertEq(AppStakingVault(staking).owner(), appCreator);

        // Verify connections
        assertEq(address(AppAccess1155(access1155).APP()), address(appToken));
        assertEq(address(AppAccess1155(access1155).STAKING()), staking);
        assertEq(address(AppStakingVault(staking).APP()), address(appToken));
    }

    function test_EpochRewardsDeployment() public {
        vm.prank(appCreator);
        (, , address epochs) = factory.deployModules(
            address(appToken),
            "https://test/"
        );

        // Verify epoch rewards deployed correctly
        assertTrue(epochs != address(0));
    }

    function test_DeployModulesWithELTAFee() public {
        // Set fee
        vm.prank(factoryOwner);
        factory.setCreateFee(CREATE_FEE);

        // Approve ELTA
        vm.prank(appCreator);
        elta.approve(address(factory), CREATE_FEE);

        uint256 treasuryBalanceBefore = elta.balanceOf(treasury);
        uint256 creatorBalanceBefore = elta.balanceOf(appCreator);

        vm.prank(appCreator);
        factory.deployModules(address(appToken), "https://metadata.test/");

        // Verify fee was transferred
        assertEq(elta.balanceOf(treasury), treasuryBalanceBefore + CREATE_FEE);
        assertEq(elta.balanceOf(appCreator), creatorBalanceBefore - CREATE_FEE);
    }

    function test_RevertWhen_DeployModulesNotTokenOwner() public {
        vm.expectRevert(AppModuleFactory.NotTokenOwner.selector);
        vm.prank(user1);
        factory.deployModules(address(appToken), "https://metadata.test/");
    }

    function test_RevertWhen_DeployModulesTwice() public {
        vm.prank(appCreator);
        factory.deployModules(address(appToken), "https://metadata.test/");

        vm.expectRevert(AppModuleFactory.ModulesAlreadyExist.selector);
        vm.prank(appCreator);
        factory.deployModules(address(appToken), "https://metadata.test/");
    }

    function test_RevertWhen_DeployModulesWithoutELTAApproval() public {
        vm.prank(factoryOwner);
        factory.setCreateFee(CREATE_FEE);

        // Don't approve ELTA
        vm.expectRevert();
        vm.prank(appCreator);
        factory.deployModules(address(appToken), "https://metadata.test/");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ADMIN FUNCTION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit(true, true, true, true);
        emit TreasurySet(newTreasury);

        vm.prank(factoryOwner);
        factory.setTreasury(newTreasury);

        assertEq(factory.treasury(), newTreasury);
    }

    function test_RevertWhen_SetTreasuryUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        factory.setTreasury(makeAddr("newTreasury"));
    }

    function test_SetCreateFee() public {
        uint256 newFee = 100 ether;

        vm.expectEmit(true, true, true, true);
        emit FeeSet(newFee);

        vm.prank(factoryOwner);
        factory.setCreateFee(newFee);

        assertEq(factory.createFeeELTA(), newFee);
    }

    function test_RevertWhen_SetCreateFeeUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        factory.setCreateFee(100 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // INTEGRATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_MultipleAppsDeployModules() public {
        // Create second app token
        AppToken appToken2 = new AppToken(
            "TestApp2",
            "TEST2",
            18,
            MAX_SUPPLY,
            appCreator,
            admin
        );

        // Deploy modules for first app
        vm.prank(appCreator);
        (address access1, address stake1, address epochs1) = factory.deployModules(
            address(appToken),
            "https://app1.test/"
        );

        // Deploy modules for second app
        vm.prank(appCreator);
        (address access2, address stake2, address epochs2) = factory.deployModules(
            address(appToken2),
            "https://app2.test/"
        );

        // Verify both are registered correctly
        (address storedAccess1, address storedStake1, address storedEpochs1) =
            factory.modulesByApp(address(appToken));
        assertEq(storedAccess1, access1);
        assertEq(storedStake1, stake1);
        assertEq(storedEpochs1, epochs1);

        (address storedAccess2, address storedStake2, address storedEpochs2) =
            factory.modulesByApp(address(appToken2));
        assertEq(storedAccess2, access2);
        assertEq(storedStake2, stake2);
        assertEq(storedEpochs2, epochs2);

        // Verify they're different
        assertTrue(access1 != access2);
        assertTrue(stake1 != stake2);
    }

    function test_DeployModulesAndConfigureItems() public {
        // Deploy modules
        vm.prank(appCreator);
        (address access1155, , ) = factory.deployModules(
            address(appToken),
            "https://metadata.test/"
        );

        // Configure an item
        vm.prank(appCreator);
        AppAccess1155(access1155).setItem(
            1, // id
            100 ether, // price
            false, // not soulbound
            true, // active
            0, // no start time
            0, // no end time
            100, // max supply
            "ipfs://item1"
        );

        // Verify item was configured
        (uint256 price, , bool active, , , , , ) =
            AppAccess1155(access1155).items(1);
        assertEq(price, 100 ether);
        assertTrue(active);
    }

    function test_DeployModulesAndStake() public {
        // Mint tokens to user
        vm.prank(admin);
        appToken.mint(user1, 1000 ether);

        // Deploy modules
        vm.prank(appCreator);
        (, address stakingVault, ) = factory.deployModules(
            address(appToken),
            "https://metadata.test/"
        );

        // User stakes
        vm.startPrank(user1);
        appToken.approve(stakingVault, 500 ether);
        AppStakingVault(stakingVault).stake(500 ether);
        vm.stopPrank();

        // Verify stake
        assertEq(AppStakingVault(stakingVault).stakedOf(user1), 500 ether);
        assertEq(AppStakingVault(stakingVault).totalStaked(), 500 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EDGE CASES
    // ────────────────────────────────────────────────────────────────────────────

    function test_DeployModulesWithZeroFee() public {
        // Fee is already 0 by default
        assertEq(factory.createFeeELTA(), 0);

        // Should work without approval
        vm.prank(appCreator);
        factory.deployModules(address(appToken), "https://metadata.test/");
    }

    function test_DeployModulesWithFactoryELTADisabled() public {
        // Factory with ELTA disabled
        AppModuleFactory noEltaFactory = new AppModuleFactory(
            address(0),
            factoryOwner,
            treasury
        );

        vm.prank(factoryOwner);
        noEltaFactory.setCreateFee(100 ether); // Set fee (but ELTA is disabled)

        // Should work without ELTA transfer
        vm.prank(appCreator);
        noEltaFactory.deployModules(address(appToken), "https://metadata.test/");
    }
}

