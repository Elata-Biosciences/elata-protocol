// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "../../src/apps/InAppContent721.sol";
import {ContentStore, PaymentTokenType} from "../../src/apps/ContentStore.sol";
import {AppModuleFactory} from "../../src/apps/AppModuleFactory.sol";
import {AppStakingVault} from "../../src/apps/AppStakingVault.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {ELTA} from "elta/ELTA.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

contract MockUSDC is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }
}

contract AppModuleFactoryTest is Test {
    AppModuleFactory public factory;
    ELTA public elta;
    MockUSDC public usdc;
    AppToken public appToken;
    AppStakingVault public defaultVault;
    FeeCollector public feeCollector;

    address public factoryOwner = makeAddr("factoryOwner");
    address public treasury = makeAddr("treasury");
    address public feeManager = makeAddr("feeManager");
    address public feeSwapper = makeAddr("feeSwapper");
    address public appCreator = makeAddr("appCreator");
    address public user1 = makeAddr("user1");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
    uint256 public constant CREATE_FEE = 50 ether;
    uint256 public constant APP_ID = 1;
    uint256 public constant DEFAULT_PROTOCOL_FEE_BPS = 500; // 5%

    event ModulesDeployed(address indexed appToken, address content721, address contentStore);
    event TreasurySet(address treasury);
    event FeeCollectorSet(address feeCollector);
    event FeeSet(uint256 fee);
    event DefaultProtocolFeeBpsSet(uint256 bps);

    function setUp() public {
        // Deploy ELTA
        elta = new ELTA(factoryOwner);

        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy FeeCollector
        feeCollector = new FeeCollector(address(elta), admin, feeManager, feeSwapper);

        // Deploy factory
        factory = new AppModuleFactory(
            address(elta), address(usdc), factoryOwner, treasury, address(feeCollector), DEFAULT_PROTOCOL_FEE_BPS
        );

        // Deploy app token
        appToken = new AppToken(
            "TestApp", "TEST", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Deploy default vault (simulating what AppFactory does)
        defaultVault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), appCreator);

        // Transfer ELTA to app creator for fees
        vm.prank(factoryOwner);
        elta.transfer(appCreator, 1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public view {
        assertEq(factory.ELTA(), address(elta));
        assertEq(factory.USDC(), address(usdc));
        assertEq(factory.owner(), factoryOwner);
        assertEq(factory.treasury(), treasury);
        assertEq(factory.feeCollector(), address(feeCollector));
        assertEq(factory.defaultProtocolFeeBps(), DEFAULT_PROTOCOL_FEE_BPS);
        assertEq(factory.createFeeELTA(), 0);
    }

    function test_DeploymentWithZeroELTA() public {
        AppModuleFactory noFeeFactory = new AppModuleFactory(
            address(0), address(usdc), factoryOwner, treasury, address(feeCollector), DEFAULT_PROTOCOL_FEE_BPS
        );

        assertEq(noFeeFactory.ELTA(), address(0));
    }

    function test_RevertWhen_DeploymentWithInvalidProtocolFee() public {
        vm.expectRevert(AppModuleFactory.InvalidProtocolFeeBps.selector);
        new AppModuleFactory(address(elta), address(usdc), factoryOwner, treasury, address(feeCollector), 2000); // > 15%
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MODULE DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_DeployModules() public {
        vm.expectEmit(true, false, false, false);
        emit ModulesDeployed(address(appToken), address(0), address(0));

        vm.prank(appCreator);
        (address content721, address contentStore) =
            factory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        // Verify addresses are non-zero
        assertTrue(content721 != address(0));
        assertTrue(contentStore != address(0));

        // Verify registry
        assertEq(factory.content721ByApp(address(appToken)), content721);
        assertEq(factory.contentStoreByApp(address(appToken)), contentStore);

        // Verify InAppContent721 ownership and minter
        assertEq(InAppContent721(content721).owner(), appCreator);
        assertEq(InAppContent721(content721).minter(), contentStore);
        assertEq(InAppContent721(content721).appId(), APP_ID);
        assertEq(InAppContent721(content721).name(), "Test Content");
        assertEq(InAppContent721(content721).symbol(), "TCNT");

        // Verify ContentStore configuration
        ContentStore store = ContentStore(contentStore);
        assertTrue(store.hasRole(store.DEFAULT_ADMIN_ROLE(), appCreator));
        assertTrue(store.hasRole(store.MODULE_ADMIN_ROLE(), appCreator));
        assertTrue(store.hasRole(store.MODULE_OPERATOR_ROLE(), appCreator));
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
        factory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        // Verify fee was transferred
        assertEq(elta.balanceOf(treasury), treasuryBalanceBefore + CREATE_FEE);
        assertEq(elta.balanceOf(appCreator), creatorBalanceBefore - CREATE_FEE);
    }

    function test_RevertWhen_DeployModulesNotTokenOwner() public {
        vm.expectRevert(AppModuleFactory.NotTokenOwner.selector);
        vm.prank(user1);
        factory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");
    }

    function test_RevertWhen_DeployModulesTwice() public {
        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        vm.expectRevert(AppModuleFactory.ModuleAlreadyExists.selector);
        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test Content 2", "TCNT2", "ipfs://contract2");
    }

    function test_RevertWhen_DeployModulesWithoutELTAApproval() public {
        vm.prank(factoryOwner);
        factory.setCreateFee(CREATE_FEE);

        // Don't approve ELTA
        vm.expectRevert();
        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");
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

    function test_SetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.expectEmit(true, true, true, true);
        emit FeeCollectorSet(newFeeCollector);

        vm.prank(factoryOwner);
        factory.setFeeCollector(newFeeCollector);

        assertEq(factory.feeCollector(), newFeeCollector);
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

    function test_SetDefaultProtocolFeeBps() public {
        uint256 newBps = 1000; // 10%

        vm.expectEmit(true, true, true, true);
        emit DefaultProtocolFeeBpsSet(newBps);

        vm.prank(factoryOwner);
        factory.setDefaultProtocolFeeBps(newBps);

        assertEq(factory.defaultProtocolFeeBps(), newBps);
    }

    function test_RevertWhen_SetDefaultProtocolFeeBpsTooHigh() public {
        vm.expectRevert(AppModuleFactory.InvalidProtocolFeeBps.selector);
        vm.prank(factoryOwner);
        factory.setDefaultProtocolFeeBps(2000); // > 15%
    }

    // ────────────────────────────────────────────────────────────────────────────
    // GET MODULES TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_GetModules() public {
        vm.prank(appCreator);
        (address content721, address contentStore) =
            factory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        (address retrievedContent721, address retrievedContentStore) = factory.getModules(address(appToken));

        assertEq(retrievedContent721, content721);
        assertEq(retrievedContentStore, contentStore);
    }

    function test_GetModulesNonExistent() public view {
        (address content721, address contentStore) = factory.getModules(address(0x123));

        assertEq(content721, address(0));
        assertEq(contentStore, address(0));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // INTEGRATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_MultipleAppsDeployModules() public {
        // Create second app token
        AppToken appToken2 = new AppToken(
            "TestApp2", "TEST2", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Deploy modules for first app
        vm.prank(appCreator);
        (address content721_1, address contentStore1) =
            factory.deployModules(APP_ID, address(appToken), "App1 Content", "APP1", "ipfs://app1");

        // Deploy modules for second app
        vm.prank(appCreator);
        (address content721_2, address contentStore2) =
            factory.deployModules(2, address(appToken2), "App2 Content", "APP2", "ipfs://app2");

        // Verify both are registered correctly
        assertEq(factory.content721ByApp(address(appToken)), content721_1);
        assertEq(factory.contentStoreByApp(address(appToken)), contentStore1);
        assertEq(factory.content721ByApp(address(appToken2)), content721_2);
        assertEq(factory.contentStoreByApp(address(appToken2)), contentStore2);

        // Verify they're different
        assertTrue(content721_1 != content721_2);
        assertTrue(contentStore1 != contentStore2);
    }

    function test_DeployModulesAndListContent() public {
        // Deploy modules
        vm.prank(appCreator);
        (, address contentStore) =
            factory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        // List content
        vm.prank(appCreator);
        uint256 contentId =
            ContentStore(contentStore).listContent("ipfs://content1", 100 ether, 10, PaymentTokenType.APP);

        // Verify content was listed
        ContentStore.Content memory content = ContentStore(contentStore).getContent(contentId);
        assertEq(content.price, 100 ether);
        assertEq(content.maxSupply, 10);
        assertTrue(content.active);
    }

    function test_DeployModulesAndMintViaPurchase() public {
        // Deploy modules
        vm.prank(appCreator);
        (address content721, address contentStore) =
            factory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");

        // List content
        vm.prank(appCreator);
        uint256 contentId =
            ContentStore(contentStore).listContent("ipfs://content1", 100 ether, 10, PaymentTokenType.APP);

        // Mint tokens to user
        vm.prank(admin);
        appToken.mint(user1, 1000 ether);

        // User purchases content
        vm.startPrank(user1);
        appToken.approve(contentStore, 100 ether);
        uint256 tokenId = ContentStore(contentStore).purchase(contentId);
        vm.stopPrank();

        // Verify token was minted
        assertEq(InAppContent721(content721).ownerOf(tokenId), user1);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EDGE CASES
    // ────────────────────────────────────────────────────────────────────────────

    function test_DeployModulesWithZeroFee() public {
        // Fee is already 0 by default
        assertEq(factory.createFeeELTA(), 0);

        // Should work without approval
        vm.prank(appCreator);
        factory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");
    }

    function test_DeployModulesWithFactoryELTADisabled() public {
        // Factory with ELTA disabled
        AppModuleFactory noEltaFactory = new AppModuleFactory(
            address(0), address(usdc), factoryOwner, treasury, address(feeCollector), DEFAULT_PROTOCOL_FEE_BPS
        );

        vm.prank(factoryOwner);
        noEltaFactory.setCreateFee(100 ether); // Set fee (but ELTA is disabled)

        // Should work without ELTA transfer
        vm.prank(appCreator);
        noEltaFactory.deployModules(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");
    }
}
