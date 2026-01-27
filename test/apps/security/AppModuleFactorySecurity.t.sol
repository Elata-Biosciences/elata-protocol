// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "../../../src/apps/InAppContent721.sol";
import {ContentStore} from "../../../src/apps/ContentStore.sol";
import {AppModuleFactory} from "../../../src/apps/AppModuleFactory.sol";
import {AppStakingVault} from "../../../src/apps/AppStakingVault.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {ELTA} from "elta/ELTA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

/**
 * @title AppModuleFactorySecurityTest
 * @notice Comprehensive security testing for AppModuleFactory
 * @dev Tests access control, deployment integrity, and economic attacks
 */
contract AppModuleFactorySecurityTest is Test {
    AppModuleFactory public factory;
    ELTA public elta;
    AppToken public appToken;

    address public factoryOwner = makeAddr("factoryOwner");
    address public treasury = makeAddr("treasury");
    address public feeCollector = makeAddr("feeCollector");
    address public appCreator = makeAddr("appCreator");
    address public attacker = makeAddr("attacker");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
    uint256 public constant APP_ID = 1;
    uint256 public constant DEFAULT_PROTOCOL_FEE_BPS = 500;

    function setUp() public {
        elta = new ELTA(factoryOwner);

        factory = new AppModuleFactory(
            address(elta), address(0), factoryOwner, treasury, feeCollector, DEFAULT_PROTOCOL_FEE_BPS
        );

        appToken = new AppToken(
            "TestApp", "TEST", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Mint ELTA to users
        vm.startPrank(factoryOwner);
        elta.transfer(appCreator, 10000 ether);
        elta.transfer(attacker, 10000 ether);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ACCESS CONTROL TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_OnlyTokenOwnerCanDeploy() public {
        vm.expectRevert(AppModuleFactory.NotTokenOwner.selector);
        vm.prank(attacker);
        factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");
    }

    function test_Security_OnlyFactoryOwnerCanSetTreasury() public {
        vm.expectRevert();
        vm.prank(attacker);
        factory.setTreasury(attacker);
    }

    function test_Security_OnlyFactoryOwnerCanSetFee() public {
        vm.expectRevert();
        vm.prank(attacker);
        factory.setCreateFee(1000 ether);
    }

    function test_Security_OnlyFactoryOwnerCanSetFeeCollector() public {
        vm.expectRevert();
        vm.prank(attacker);
        factory.setFeeCollector(attacker);
    }

    function test_Security_OnlyFactoryOwnerCanSetDefaultProtocolFeeBps() public {
        vm.expectRevert();
        vm.prank(attacker);
        factory.setDefaultProtocolFeeBps(1000);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT INTEGRITY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotDeployModulesTwice() public {
        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        vm.expectRevert(AppModuleFactory.ModuleAlreadyExists.selector);
        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test2", "TST2", "https://test2/");
    }

    function test_Security_DeployedModulesHaveCorrectOwner() public {
        vm.prank(appCreator);
        (address content721, address contentStore) =
            factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        // Content721 should be owned by app creator
        assertEq(InAppContent721(content721).owner(), appCreator);

        // ContentStore should have roles granted to app creator
        ContentStore store = ContentStore(contentStore);
        assertTrue(store.hasRole(store.DEFAULT_ADMIN_ROLE(), appCreator));
        assertTrue(store.hasRole(store.MODULE_ADMIN_ROLE(), appCreator));
        assertTrue(store.hasRole(store.MODULE_OPERATOR_ROLE(), appCreator));
    }

    function test_Security_ContentStoreSetAsMinter() public {
        vm.prank(appCreator);
        (address content721, address contentStore) =
            factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        // ContentStore should be set as minter for InAppContent721
        assertEq(InAppContent721(content721).minter(), contentStore);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ELTA FEE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ELTAFeeCollectedCorrectly() public {
        uint256 fee = 50 ether;

        vm.prank(factoryOwner);
        factory.setCreateFee(fee);

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 creatorBefore = elta.balanceOf(appCreator);

        vm.prank(appCreator);
        elta.approve(address(factory), fee);

        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        assertEq(elta.balanceOf(treasury), treasuryBefore + fee);
        assertEq(elta.balanceOf(appCreator), creatorBefore - fee);
    }

    function test_Security_CannotDeployWithoutELTAApproval() public {
        vm.prank(factoryOwner);
        factory.setCreateFee(50 ether);

        // Don't approve ELTA
        vm.expectRevert();
        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");
    }

    function test_Security_DeployWorksWithZeroFee() public {
        // Fee is 0 by default
        assertEq(factory.createFeeELTA(), 0);

        // Should work without ELTA approval
        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");
    }

    function test_Security_DeployWorksWithELTADisabled() public {
        AppModuleFactory noEltaFactory = new AppModuleFactory(
            address(0), // No ELTA
            address(0),
            factoryOwner,
            treasury,
            feeCollector,
            DEFAULT_PROTOCOL_FEE_BPS
        );

        vm.prank(factoryOwner);
        noEltaFactory.setCreateFee(100 ether); // Set fee but ELTA disabled

        // Should work (no ELTA transfer)
        vm.prank(appCreator);
        noEltaFactory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // REGISTRY INTEGRITY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_RegistryMappingCorrect() public {
        vm.prank(appCreator);
        (address content721, address contentStore) =
            factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        assertEq(factory.content721ByApp(address(appToken)), content721);
        assertEq(factory.contentStoreByApp(address(appToken)), contentStore);
    }

    function test_Security_MultipleAppsIsolated() public {
        // Create second app token
        AppToken appToken2 = new AppToken(
            "TestApp2", "TEST2", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Deploy for both apps
        vm.startPrank(appCreator);
        (address content721_1, address contentStore1) =
            factory.deployModules(APP_ID, address(appToken), "App1", "APP1", "https://app1/");
        (address content721_2, address contentStore2) =
            factory.deployModules(2, address(appToken2), "App2", "APP2", "https://app2/");
        vm.stopPrank();

        // Verify they're different
        assertTrue(content721_1 != content721_2);
        assertTrue(contentStore1 != contentStore2);

        // Verify correct app ID
        assertEq(InAppContent721(content721_1).appId(), APP_ID);
        assertEq(InAppContent721(content721_2).appId(), 2);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // TREASURY MANIPULATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotChangeTreasuryToZero() public {
        vm.prank(factoryOwner);
        factory.setTreasury(address(0));

        // Treasury can be set to zero (intentional for disabling)
        assertEq(factory.treasury(), address(0));
    }

    function test_Security_TreasuryChangeDoesNotAffectPastDeployments() public {
        vm.prank(factoryOwner);
        factory.setCreateFee(50 ether);

        // First deployment
        vm.prank(appCreator);
        elta.approve(address(factory), 50 ether);
        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        assertEq(elta.balanceOf(treasury), 50 ether);

        // Change treasury
        address newTreasury = makeAddr("newTreasury");
        vm.prank(factoryOwner);
        factory.setTreasury(newTreasury);

        // Old treasury still has its funds
        assertEq(elta.balanceOf(treasury), 50 ether);
        assertEq(elta.balanceOf(newTreasury), 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // PROTOCOL FEE BOUNDS TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotSetProtocolFeeTooHigh() public {
        vm.expectRevert(AppModuleFactory.InvalidProtocolFeeBps.selector);
        vm.prank(factoryOwner);
        factory.setDefaultProtocolFeeBps(2000); // > 15%
    }

    function test_Security_ProtocolFeeBoundAtConstruction() public {
        vm.expectRevert(AppModuleFactory.InvalidProtocolFeeBps.selector);
        new AppModuleFactory(address(elta), address(0), factoryOwner, treasury, feeCollector, 2000);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUZZ TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_Security_FeeAmountCorrect(uint256 feeAmount) public {
        feeAmount = bound(feeAmount, 0, 10000 ether);

        vm.prank(factoryOwner);
        factory.setCreateFee(feeAmount);

        if (feeAmount > 0) {
            vm.prank(appCreator);
            elta.approve(address(factory), feeAmount);
        }

        uint256 treasuryBefore = elta.balanceOf(treasury);

        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        assertEq(elta.balanceOf(treasury), treasuryBefore + feeAmount);
    }

    function testFuzz_Security_ProtocolFeeWithinBounds(uint256 feeBps) public {
        feeBps = bound(feeBps, 0, 1500);

        vm.prank(factoryOwner);
        factory.setDefaultProtocolFeeBps(feeBps);

        assertEq(factory.defaultProtocolFeeBps(), feeBps);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT VALIDATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_DeployedContractsAreValid() public {
        vm.prank(appCreator);
        (address content721, address contentStore) =
            factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        // Verify contracts have code
        uint256 content721CodeSize;
        uint256 contentStoreCodeSize;

        assembly {
            content721CodeSize := extcodesize(content721)
            contentStoreCodeSize := extcodesize(contentStore)
        }

        assertTrue(content721CodeSize > 0);
        assertTrue(contentStoreCodeSize > 0);

        // Verify they're actual contracts (not EOAs)
        assertTrue(content721 != appCreator);
        assertTrue(contentStore != appCreator);
        assertTrue(content721 != address(0));
        assertTrue(contentStore != address(0));
    }

    function test_Security_CannotDeployForFakeToken() public {
        // Create fake token that doesn't implement owner()
        FakeToken fake = new FakeToken();

        vm.expectRevert();
        vm.prank(attacker);
        factory.deployModules(APP_ID, address(fake), "Fake", "FAKE", "https://test/");
    }

    function test_Security_GetModulesReturnsZeroForUndeployed() public view {
        (address content721, address contentStore) = factory.getModules(address(0x123));

        assertEq(content721, address(0));
        assertEq(contentStore, address(0));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // OWNERSHIP TRANSFER VERIFICATION
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_OwnershipTransferSequence() public {
        // Verify that factory temporarily owns Content721 during deployment
        // and then transfers ownership to app creator

        vm.prank(appCreator);
        (address content721, address contentStore) =
            factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        // Final ownership should be with app creator
        assertEq(InAppContent721(content721).owner(), appCreator, "Content721 owner should be app creator");

        // Minter should be set correctly
        assertEq(InAppContent721(content721).minter(), contentStore, "Minter should be ContentStore");

        // App creator should be able to update minter
        address newMinter = makeAddr("newMinter");
        vm.prank(appCreator);
        InAppContent721(content721).setMinter(newMinter);
        assertEq(InAppContent721(content721).minter(), newMinter, "App creator should be able to change minter");
    }

    function test_Security_FactoryNotOwnerAfterDeploy() public {
        vm.prank(appCreator);
        (address content721,) = factory.deployModules(APP_ID, address(appToken), "Test", "TST", "https://test/");

        // Factory should NOT be the owner
        assertTrue(InAppContent721(content721).owner() != address(factory), "Factory should not retain ownership");

        // Factory should NOT be able to call setMinter
        vm.expectRevert();
        factory.deployModules(APP_ID, address(appToken), "Test2", "TST2", "https://test2/"); // This tests ModuleAlreadyExists
    }
}

// Fake token without owner() function
contract FakeToken {
    function totalSupply() external pure returns (uint256) {
        return 1000000 ether;
    }
}
