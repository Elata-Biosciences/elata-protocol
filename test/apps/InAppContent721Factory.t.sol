// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "../../src/apps/InAppContent721.sol";
import {InAppContent721Factory} from "../../src/apps/InAppContent721Factory.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {ELTA} from "elta/ELTA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

contract InAppContent721FactoryTest is Test {
    InAppContent721Factory public factory;
    ELTA public elta;
    AppToken public appToken;

    address public factoryOwner = makeAddr("factoryOwner");
    address public treasury = makeAddr("treasury");
    address public appCreator = makeAddr("appCreator");
    address public user1 = makeAddr("user1");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
    uint256 public constant CREATE_FEE = 50 ether;
    uint256 public constant APP_ID = 1;

    event Content721Deployed(address indexed appToken, address indexed content721, uint256 appId);
    event TreasurySet(address treasury);
    event FeeSet(uint256 fee);

    function setUp() public {
        // Deploy ELTA
        elta = new ELTA(factoryOwner);

        // Deploy factory
        factory = new InAppContent721Factory(address(elta), factoryOwner, treasury);

        // Deploy app token
        appToken = new AppToken(
            AppToken.InitParams({
                name: "TestApp",
                symbol: "TEST",
                decimals: 18,
                maxSupply: MAX_SUPPLY,
                creator: appCreator,
                admin: admin,
                governance: address(1),
                appRewardsDistributor: address(1),
                rewardsDistributor: address(1),
                treasury: address(1)
            })
        );

        // Transfer ELTA to app creator for fees
        vm.prank(factoryOwner);
        elta.transfer(appCreator, 1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public view {
        assertEq(factory.ELTA(), address(elta));
        assertEq(factory.owner(), factoryOwner);
        assertEq(factory.treasury(), treasury);
        assertEq(factory.createFeeELTA(), 0);
    }

    function test_DeploymentWithZeroELTA() public {
        InAppContent721Factory noFeeFactory = new InAppContent721Factory(address(0), factoryOwner, treasury);
        assertEq(noFeeFactory.ELTA(), address(0));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // CONTENT721 DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_DeployContent721() public {
        vm.expectEmit(true, false, false, true);
        emit Content721Deployed(address(appToken), address(0), APP_ID);

        vm.prank(appCreator);
        address content721 =
            factory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        // Verify address is non-zero
        assertTrue(content721 != address(0));

        // Verify registry
        assertEq(factory.content721ByApp(address(appToken)), content721);

        // Verify InAppContent721 ownership
        assertEq(InAppContent721(content721).owner(), appCreator);
        assertEq(InAppContent721(content721).minter(), address(0)); // Minter not set yet
        assertEq(InAppContent721(content721).appId(), APP_ID);
        assertEq(InAppContent721(content721).name(), "Test Content");
        assertEq(InAppContent721(content721).symbol(), "TCNT");
        assertEq(InAppContent721(content721).contractURI(), "ipfs://contract");
    }

    function test_DeployContent721WithELTAFee() public {
        // Set fee
        vm.prank(factoryOwner);
        factory.setCreateFee(CREATE_FEE);

        // Approve ELTA
        vm.prank(appCreator);
        elta.approve(address(factory), CREATE_FEE);

        uint256 treasuryBalanceBefore = elta.balanceOf(treasury);
        uint256 creatorBalanceBefore = elta.balanceOf(appCreator);

        vm.prank(appCreator);
        factory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        // Verify fee was transferred
        assertEq(elta.balanceOf(treasury), treasuryBalanceBefore + CREATE_FEE);
        assertEq(elta.balanceOf(appCreator), creatorBalanceBefore - CREATE_FEE);
    }

    function test_RevertWhen_DeployContent721NotTokenOwner() public {
        vm.expectRevert(InAppContent721Factory.NotTokenOwner.selector);
        vm.prank(user1);
        factory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");
    }

    function test_RevertWhen_DeployContent721Twice() public {
        vm.prank(appCreator);
        factory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        vm.expectRevert(InAppContent721Factory.AlreadyDeployed.selector);
        vm.prank(appCreator);
        factory.deployContent721(APP_ID, address(appToken), "Test Content 2", "TCNT2", "ipfs://contract2");
    }

    function test_RevertWhen_DeployContent721WithoutELTAApproval() public {
        vm.prank(factoryOwner);
        factory.setCreateFee(CREATE_FEE);

        // Don't approve ELTA
        vm.expectRevert();
        vm.prank(appCreator);
        factory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");
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
    // VIEW FUNCTION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_GetContent721() public {
        vm.prank(appCreator);
        address content721 =
            factory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        assertEq(factory.getContent721(address(appToken)), content721);
    }

    function test_GetContent721NonExistent() public view {
        assertEq(factory.getContent721(address(0x123)), address(0));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // INTEGRATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_MultipleAppsDeployContent721() public {
        // Create second app token
        AppToken appToken2 = new AppToken(
            AppToken.InitParams({
                name: "TestApp2",
                symbol: "TEST2",
                decimals: 18,
                maxSupply: MAX_SUPPLY,
                creator: appCreator,
                admin: admin,
                governance: address(1),
                appRewardsDistributor: address(1),
                rewardsDistributor: address(1),
                treasury: address(1)
            })
        );

        // Deploy content721 for first app
        vm.prank(appCreator);
        address content721_1 =
            factory.deployContent721(APP_ID, address(appToken), "App1 Content", "APP1", "ipfs://app1");

        // Deploy content721 for second app
        vm.prank(appCreator);
        address content721_2 = factory.deployContent721(2, address(appToken2), "App2 Content", "APP2", "ipfs://app2");

        // Verify both are registered correctly
        assertEq(factory.content721ByApp(address(appToken)), content721_1);
        assertEq(factory.content721ByApp(address(appToken2)), content721_2);

        // Verify they're different
        assertTrue(content721_1 != content721_2);
    }

    function test_DeployContent721WithZeroFee() public {
        // Fee is already 0 by default
        assertEq(factory.createFeeELTA(), 0);

        // Should work without approval
        vm.prank(appCreator);
        factory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");
    }

    function test_DeployContent721WithFactoryELTADisabled() public {
        // Factory with ELTA disabled
        InAppContent721Factory noEltaFactory = new InAppContent721Factory(address(0), factoryOwner, treasury);

        vm.prank(factoryOwner);
        noEltaFactory.setCreateFee(100 ether); // Set fee (but ELTA is disabled)

        // Should work without ELTA transfer
        vm.prank(appCreator);
        noEltaFactory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");
    }

    function test_OwnerCanSetMinterAfterDeployment() public {
        // Deploy content721
        vm.prank(appCreator);
        address content721 =
            factory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        // Owner can set minter
        address minter = makeAddr("minter");
        vm.prank(appCreator);
        InAppContent721(content721).setMinter(minter);

        assertEq(InAppContent721(content721).minter(), minter);
    }
}
