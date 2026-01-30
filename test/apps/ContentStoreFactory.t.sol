// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "../../src/apps/InAppContent721.sol";
import {ContentStore, PaymentTokenType} from "../../src/apps/ContentStore.sol";
import {ContentStoreFactory} from "../../src/apps/ContentStoreFactory.sol";
import {InAppContent721Factory} from "../../src/apps/InAppContent721Factory.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {ELTA} from "elta/ELTA.sol";
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

contract ContentStoreFactoryTest is Test {
    ContentStoreFactory public factory;
    InAppContent721Factory public content721Factory;
    ELTA public elta;
    MockUSDC public usdc;
    AppToken public appToken;
    FeeCollector public feeCollector;
    InAppContent721 public content721;

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

    event ContentStoreDeployed(address indexed appToken, address indexed contentStore, address indexed content721);
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

        // Deploy factories
        content721Factory = new InAppContent721Factory(address(elta), factoryOwner, treasury);
        factory = new ContentStoreFactory(
            address(elta), address(usdc), factoryOwner, treasury, address(feeCollector), DEFAULT_PROTOCOL_FEE_BPS
        );

        // Deploy app token
        appToken = new AppToken(
            "TestApp", "TEST", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Deploy content721 for the app
        vm.prank(appCreator);
        address content721Addr =
            content721Factory.deployContent721(APP_ID, address(appToken), "Test Content", "TCNT", "ipfs://contract");
        content721 = InAppContent721(content721Addr);

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
        ContentStoreFactory noFeeFactory = new ContentStoreFactory(
            address(0), address(usdc), factoryOwner, treasury, address(feeCollector), DEFAULT_PROTOCOL_FEE_BPS
        );
        assertEq(noFeeFactory.ELTA(), address(0));
    }

    function test_RevertWhen_DeploymentWithInvalidProtocolFee() public {
        vm.expectRevert(ContentStoreFactory.InvalidProtocolFeeBps.selector);
        new ContentStoreFactory(
            address(elta),
            address(usdc),
            factoryOwner,
            treasury,
            address(feeCollector),
            2000 // > 15%
        );
    }

    // ────────────────────────────────────────────────────────────────────────────
    // CONTENTSTORE DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_DeployContentStore() public {
        vm.expectEmit(true, false, true, false);
        emit ContentStoreDeployed(address(appToken), address(0), address(content721));

        vm.prank(appCreator);
        address contentStore = factory.deployContentStore(APP_ID, address(appToken), address(content721));

        // Manually set minter (factory no longer does this automatically)
        vm.prank(appCreator);
        content721.setMinter(contentStore);

        // Verify address is non-zero
        assertTrue(contentStore != address(0));

        // Verify registry
        assertEq(factory.contentStoreByApp(address(appToken)), contentStore);

        // Verify ContentStore configuration
        ContentStore store = ContentStore(contentStore);
        assertTrue(store.hasRole(store.DEFAULT_ADMIN_ROLE(), appCreator));
        assertTrue(store.hasRole(store.MODULE_ADMIN_ROLE(), appCreator));
        assertTrue(store.hasRole(store.MODULE_OPERATOR_ROLE(), appCreator));

        // Verify minter was set on content721
        assertEq(content721.minter(), contentStore);
    }

    function test_DeployContentStoreForNewApp() public {
        // Create a new app token
        AppToken appToken2 = new AppToken(
            "TestApp2", "TEST2", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Deploy content721 for the new app (ContentStore requires content721)
        vm.prank(appCreator);
        address content721Addr2 =
            content721Factory.deployContent721(2, address(appToken2), "Test Content 2", "TCNT2", "ipfs://contract2");

        vm.prank(appCreator);
        address contentStore = factory.deployContentStore(2, address(appToken2), content721Addr2);

        // Manually set minter
        vm.prank(appCreator);
        InAppContent721(content721Addr2).setMinter(contentStore);

        // Verify address is non-zero
        assertTrue(contentStore != address(0));

        // Verify registry
        assertEq(factory.contentStoreByApp(address(appToken2)), contentStore);
    }

    function test_DeployContentStoreWithELTAFee() public {
        // Create a new app token
        AppToken appToken2 = new AppToken(
            "TestApp2", "TEST2", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Deploy content721 for the new app (ContentStore requires content721)
        vm.prank(appCreator);
        address content721Addr2 =
            content721Factory.deployContent721(2, address(appToken2), "Test Content 2", "TCNT2", "ipfs://contract2");

        // Set fee
        vm.prank(factoryOwner);
        factory.setCreateFee(CREATE_FEE);

        // Approve ELTA
        vm.prank(appCreator);
        elta.approve(address(factory), CREATE_FEE);

        uint256 treasuryBalanceBefore = elta.balanceOf(treasury);
        uint256 creatorBalanceBefore = elta.balanceOf(appCreator);

        vm.prank(appCreator);
        factory.deployContentStore(2, address(appToken2), content721Addr2);

        // Verify fee was transferred
        assertEq(elta.balanceOf(treasury), treasuryBalanceBefore + CREATE_FEE);
        assertEq(elta.balanceOf(appCreator), creatorBalanceBefore - CREATE_FEE);
    }

    function test_RevertWhen_DeployContentStoreNotTokenOwner() public {
        vm.expectRevert(ContentStoreFactory.NotTokenOwner.selector);
        vm.prank(user1);
        factory.deployContentStore(APP_ID, address(appToken), address(content721));
    }

    function test_RevertWhen_DeployContentStoreNotContent721Owner() public {
        // Create a new content721 owned by someone else
        InAppContent721 otherContent721 =
            new InAppContent721(APP_ID, "Other", "OTHER", user1, address(0), "ipfs://other");

        vm.expectRevert(ContentStoreFactory.NotContent721Owner.selector);
        vm.prank(appCreator);
        factory.deployContentStore(APP_ID, address(appToken), address(otherContent721));
    }

    function test_RevertWhen_DeployContentStoreTwice() public {
        vm.prank(appCreator);
        address contentStore = factory.deployContentStore(APP_ID, address(appToken), address(content721));

        // Manually set minter
        vm.prank(appCreator);
        content721.setMinter(contentStore);

        vm.expectRevert(ContentStoreFactory.AlreadyDeployed.selector);
        vm.prank(appCreator);
        factory.deployContentStore(APP_ID, address(appToken), address(content721));
    }

    function test_RevertWhen_DeployContentStoreWithoutELTAApproval() public {
        // Create a new app token
        AppToken appToken2 = new AppToken(
            "TestApp2", "TEST2", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Deploy content721 for the new app (ContentStore requires content721)
        vm.prank(appCreator);
        address content721Addr2 =
            content721Factory.deployContent721(2, address(appToken2), "Test Content 2", "TCNT2", "ipfs://contract2");

        vm.prank(factoryOwner);
        factory.setCreateFee(CREATE_FEE);

        // Don't approve ELTA
        vm.expectRevert();
        vm.prank(appCreator);
        factory.deployContentStore(2, address(appToken2), content721Addr2);
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
        vm.expectRevert(ContentStoreFactory.InvalidProtocolFeeBps.selector);
        vm.prank(factoryOwner);
        factory.setDefaultProtocolFeeBps(2000); // > 15%
    }

    // ────────────────────────────────────────────────────────────────────────────
    // VIEW FUNCTION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_GetContentStore() public {
        vm.prank(appCreator);
        address contentStore = factory.deployContentStore(APP_ID, address(appToken), address(content721));

        // Manually set minter
        vm.prank(appCreator);
        content721.setMinter(contentStore);

        assertEq(factory.getContentStore(address(appToken)), contentStore);
    }

    function test_GetContentStoreNonExistent() public view {
        assertEq(factory.getContentStore(address(0x123)), address(0));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // INTEGRATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_FullWorkflow_DeployBothModules() public {
        // Create a new app token
        AppToken appToken2 = new AppToken(
            "TestApp2", "TEST2", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Step 1: Deploy content721 via InAppContent721Factory
        vm.prank(appCreator);
        address newContent721 =
            content721Factory.deployContent721(2, address(appToken2), "App2 Content", "APP2", "ipfs://app2");

        // Step 2: Deploy content store via ContentStoreFactory
        vm.prank(appCreator);
        address contentStore = factory.deployContentStore(2, address(appToken2), newContent721);

        // Step 3: Manually set minter on content721 (required step after factory deployment)
        vm.prank(appCreator);
        InAppContent721(newContent721).setMinter(contentStore);

        // Verify everything is set up correctly
        assertEq(InAppContent721(newContent721).minter(), contentStore);
        assertEq(content721Factory.content721ByApp(address(appToken2)), newContent721);
        assertEq(factory.contentStoreByApp(address(appToken2)), contentStore);
    }

    function test_DeployContentStoreAndListContent() public {
        vm.prank(appCreator);
        address contentStore = factory.deployContentStore(APP_ID, address(appToken), address(content721));

        // Manually set minter
        vm.prank(appCreator);
        content721.setMinter(contentStore);

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

    function test_DeployContentStoreAndMintViaPurchase() public {
        vm.prank(appCreator);
        address contentStore = factory.deployContentStore(APP_ID, address(appToken), address(content721));

        // Manually set minter (required for content721 to accept mints from ContentStore)
        vm.prank(appCreator);
        content721.setMinter(contentStore);

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
        assertEq(content721.ownerOf(tokenId), user1);
    }

    function test_MultipleAppsDeployContentStores() public {
        // Create second app token
        AppToken appToken2 = new AppToken(
            "TestApp2", "TEST2", 18, MAX_SUPPLY, appCreator, admin, address(1), address(1), address(1), address(1)
        );

        // Deploy content721 for second app (ContentStore requires content721)
        vm.prank(appCreator);
        address content721Addr2 =
            content721Factory.deployContent721(2, address(appToken2), "Test Content 2", "TCNT2", "ipfs://contract2");

        // Deploy content stores for both apps
        vm.prank(appCreator);
        address contentStore1 = factory.deployContentStore(APP_ID, address(appToken), address(content721));

        // Manually set minter for first app
        vm.prank(appCreator);
        content721.setMinter(contentStore1);

        vm.prank(appCreator);
        address contentStore2 = factory.deployContentStore(2, address(appToken2), content721Addr2);

        // Manually set minter for second app
        vm.prank(appCreator);
        InAppContent721(content721Addr2).setMinter(contentStore2);

        // Verify both are registered correctly
        assertEq(factory.contentStoreByApp(address(appToken)), contentStore1);
        assertEq(factory.contentStoreByApp(address(appToken2)), contentStore2);

        // Verify they're different
        assertTrue(contentStore1 != contentStore2);
    }

    function test_DeployContentStoreWithZeroFee() public {
        // Fee is already 0 by default
        assertEq(factory.createFeeELTA(), 0);

        // Should work without approval
        vm.prank(appCreator);
        address contentStore = factory.deployContentStore(APP_ID, address(appToken), address(content721));

        // Manually set minter
        vm.prank(appCreator);
        content721.setMinter(contentStore);
    }

    function test_DeployContentStoreWithFactoryELTADisabled() public {
        // Factory with ELTA disabled
        ContentStoreFactory noEltaFactory = new ContentStoreFactory(
            address(0), address(usdc), factoryOwner, treasury, address(feeCollector), DEFAULT_PROTOCOL_FEE_BPS
        );

        vm.prank(factoryOwner);
        noEltaFactory.setCreateFee(100 ether); // Set fee (but ELTA is disabled)

        // Should work without ELTA transfer
        vm.prank(appCreator);
        address contentStore = noEltaFactory.deployContentStore(APP_ID, address(appToken), address(content721));

        // Manually set minter
        vm.prank(appCreator);
        content721.setMinter(contentStore);
    }
}
