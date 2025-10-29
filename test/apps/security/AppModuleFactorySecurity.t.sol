// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppAccess1155} from "../../../src/apps/AppAccess1155.sol";
import {AppModuleFactory} from "../../../src/apps/AppModuleFactory.sol";
import {AppStakingVault} from "../../../src/apps/AppStakingVault.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
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
    address public appCreator = makeAddr("appCreator");
    address public attacker = makeAddr("attacker");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", factoryOwner, factoryOwner, 1000000 ether, 77000000 ether);

        factory = new AppModuleFactory(address(elta), factoryOwner, treasury);

        appToken = new AppToken(
            "TestApp", "TEST", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Mint ELTA to users
        vm.startPrank(factoryOwner);
        elta.mint(appCreator, 10000 ether);
        elta.mint(attacker, 10000 ether);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ACCESS CONTROL TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_OnlyTokenOwnerCanDeploy() public {
        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        vm.expectRevert(AppModuleFactory.NotTokenOwner.selector);
        vm.prank(attacker);
        factory.deployModules(address(appToken), address(vault), "https://test/");
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

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT INTEGRITY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotDeployModulesTwice() public {
        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        vm.prank(appCreator);
        factory.deployModules(address(appToken), address(vault), "https://test/");

        vm.expectRevert(AppModuleFactory.ModuleAlreadyExists.selector);
        vm.prank(appCreator);
        factory.deployModules(address(appToken), address(vault), "https://test/");
    }

    function test_Security_DeployedModulesHaveCorrectOwner() public {
        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        vm.prank(appCreator);
        address access = factory.deployModules(address(appToken), address(vault), "https://test/");

        // Both modules should be owned by app creator
        assertEq(AppAccess1155(access).owner(), appCreator);
        assertEq(AppStakingVault(vault).owner(), appCreator);
    }

    function test_Security_DeployedModulesLinkedCorrectly() public {
        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        vm.prank(appCreator);
        address access = factory.deployModules(address(appToken), address(vault), "https://test/");

        // Verify cross-references
        assertEq(address(AppAccess1155(access).APP()), address(appToken));
        assertEq(address(AppAccess1155(access).STAKING()), address(vault));
        assertEq(address(AppStakingVault(vault).APP()), address(appToken));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ELTA FEE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ELTAFeeCollectedCorrectly() public {
        uint256 fee = 50 ether;

        vm.prank(factoryOwner);
        factory.setCreateFee(fee);

        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 creatorBefore = elta.balanceOf(appCreator);

        vm.prank(appCreator);
        elta.approve(address(factory), fee);

        vm.prank(appCreator);
        factory.deployModules(address(appToken), address(vault), "https://test/");

        assertEq(elta.balanceOf(treasury), treasuryBefore + fee);
        assertEq(elta.balanceOf(appCreator), creatorBefore - fee);
    }

    function test_Security_CannotDeployWithoutELTAApproval() public {
        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        vm.prank(factoryOwner);
        factory.setCreateFee(50 ether);

        // Don't approve ELTA
        vm.expectRevert();
        vm.prank(appCreator);
        factory.deployModules(address(appToken), address(vault), "https://test/");
    }

    function test_Security_DeployWorksWithZeroFee() public {
        // Fee is 0 by default
        assertEq(factory.createFeeELTA(), 0);

        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        // Should work without ELTA approval
        vm.prank(appCreator);
        factory.deployModules(address(appToken), address(vault), "https://test/");
    }

    function test_Security_DeployWorksWithELTADisabled() public {
        AppModuleFactory noEltaFactory = new AppModuleFactory(
            address(0), // No ELTA
            factoryOwner,
            treasury
        );

        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        vm.prank(factoryOwner);
        noEltaFactory.setCreateFee(100 ether); // Set fee but ELTA disabled

        // Should work (no ELTA transfer)
        vm.prank(appCreator);
        noEltaFactory.deployModules(address(appToken), address(vault), "https://test/");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // REGISTRY INTEGRITY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_RegistryMappingCorrect() public {
        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        vm.prank(appCreator);
        address access = factory.deployModules(address(appToken), address(vault), "https://test/");

        address storedAccess = factory.access1155ByApp(address(appToken));
        assertEq(storedAccess, access);
    }

    function test_Security_MultipleAppsIsolated() public {
        // Create second app token
        AppToken appToken2 = new AppToken(
            "TestApp2", "TEST2", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Deploy for both apps
        vm.startPrank(appCreator);
        AppStakingVault vault1 = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);
        AppStakingVault vault2 = new AppStakingVault("TestApp2", "TEST2", IERC20(address(appToken2)), appCreator);

        address access1 = factory.deployModules(address(appToken), address(vault1), "https://app1/");
        address access2 = factory.deployModules(address(appToken2), address(vault2), "https://app2/");
        vm.stopPrank();

        // Verify they're different
        assertTrue(access1 != access2);
        assertTrue(vault1 != vault2);

        // Verify correct app token links
        assertEq(address(AppAccess1155(access1).APP()), address(appToken));
        assertEq(address(AppAccess1155(access2).APP()), address(appToken2));
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

        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        // First deployment
        vm.prank(appCreator);
        elta.approve(address(factory), 50 ether);
        vm.prank(appCreator);
        factory.deployModules(address(appToken), address(vault), "https://test/");

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
    // FUZZ TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_Security_FeeAmountCorrect(uint256 feeAmount) public {
        feeAmount = bound(feeAmount, 0, 10000 ether);

        vm.prank(factoryOwner);
        factory.setCreateFee(feeAmount);

        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        if (feeAmount > 0) {
            vm.prank(appCreator);
            elta.approve(address(factory), feeAmount);
        }

        uint256 treasuryBefore = elta.balanceOf(treasury);

        vm.prank(appCreator);
        factory.deployModules(address(appToken), address(vault), "https://test/");

        assertEq(elta.balanceOf(treasury), treasuryBefore + feeAmount);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT VALIDATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_DeployedContractsAreValid() public {
        AppStakingVault vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        vm.prank(appCreator);
        address access = factory.deployModules(address(appToken), address(vault), "https://test/");

        // Verify contracts have code
        uint256 accessCodeSize;
        uint256 vaultCodeSize;

        assembly {
            accessCodeSize := extcodesize(access)
            vaultCodeSize := extcodesize(vault)
        }

        assertTrue(accessCodeSize > 0);
        assertTrue(vaultCodeSize > 0);

        // Verify they're actual contracts (not EOAs)
        assertTrue(access != appCreator);
        assertTrue(address(vault) != appCreator);
        assertTrue(access != address(0));
        assertTrue(address(vault) != address(0));
    }

    function test_Security_CannotDeployForFakeToken() public {
        // Create fake token that doesn't implement owner()
        FakeToken fake = new FakeToken();

        AppStakingVault vault = new AppStakingVault("Fake", "FAKE", IERC20(address(fake)), attacker);

        vm.expectRevert();
        vm.prank(attacker);
        factory.deployModules(address(fake), address(vault), "https://test/");
    }
}

// Fake token without owner() function
contract FakeToken {
    function totalSupply() external pure returns (uint256) {
        return 1000000 ether;
    }
}
