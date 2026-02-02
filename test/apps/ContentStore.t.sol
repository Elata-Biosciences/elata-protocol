// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppToken} from "../../src/apps/AppToken.sol";
import {InAppContent721} from "../../src/apps/InAppContent721.sol";
import {ContentStore, PaymentTokenType} from "../../src/apps/ContentStore.sol";
import "forge-std/Test.sol";

contract ContentStoreTest is Test {
    AppToken public appToken;
    InAppContent721 public content721;
    ContentStore public store;

    address public owner = makeAddr("owner");
    address public admin = makeAddr("admin");
    address public feeCollector = makeAddr("feeCollector");
    address public treasury = makeAddr("treasury");
    address public elta = makeAddr("elta");
    address public usdc = makeAddr("usdc");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant APP_ID = 1;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;
    uint256 public constant PROTOCOL_FEE_BPS = 500; // 5%
    uint256 public constant CONTENT_PRICE = 100 ether;

    event ContentListed(uint256 indexed contentId, string uri, uint256 price, uint256 maxSupply);
    event ContentPurchased(
        uint256 indexed contentId, address indexed buyer, uint256 tokenId, uint256 price, uint256 protocolFee
    );
    event ContentDeactivated(uint256 indexed contentId);
    event ContentReactivated(uint256 indexed contentId);
    event RevenueWithdrawn(address indexed to, uint256 amount);

    function setUp() public {
        // Deploy app token
        appToken = new AppToken(
            AppToken.InitParams({
                name: "TestApp",
                symbol: "TEST",
                decimals: 18,
                maxSupply: MAX_SUPPLY,
                creator: owner,
                admin: admin,
                governance: address(1),
                appRewardsDistributor: address(1),
                rewardsDistributor: address(1),
                treasury: address(1)
            })
        );

        // Deploy content 721
        content721 = new InAppContent721(
            APP_ID,
            "Test Content",
            "TCNT",
            owner,
            address(0), // Minter will be set to store
            "ipfs://QmContract"
        );

        // Deploy content store using InitConfig struct
        store = new ContentStore(
            ContentStore.InitConfig({
                appId: APP_ID,
                appToken: address(appToken),
                elta: elta,
                usdc: usdc,
                treasury: treasury,
                content721: address(content721),
                admin: owner,
                feeCollector: feeCollector,
                protocolFeeBps: PROTOCOL_FEE_BPS
            })
        );

        // Set store as minter
        vm.prank(owner);
        content721.setMinter(address(store));

        // Mint tokens to users
        vm.startPrank(admin);
        appToken.mint(user1, 10000 ether);
        appToken.mint(user2, 10000 ether);
        vm.stopPrank();

        // Mock feeCollector to accept deposits
        vm.mockCall(feeCollector, abi.encodeWithSignature("depositAppToken(uint256,address,uint256)"), abi.encode());
    }

    // Helper function to create ContentStore InitConfig
    function _createStoreConfig(
        address _appToken,
        address _content721,
        address _admin,
        address _feeCollector,
        uint256 _protocolFeeBps
    ) internal view returns (ContentStore.InitConfig memory) {
        return ContentStore.InitConfig({
            appId: APP_ID,
            appToken: _appToken,
            elta: elta,
            usdc: usdc,
            treasury: treasury,
            content721: _content721,
            admin: _admin,
            feeCollector: _feeCollector,
            protocolFeeBps: _protocolFeeBps
        });
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public {
        assertEq(store.appId(), APP_ID);
        assertEq(address(store.appToken()), address(appToken));
        assertEq(address(store.content721()), address(content721));
        assertTrue(store.hasRole(store.MODULE_ADMIN_ROLE(), owner));
        assertTrue(store.hasRole(store.MODULE_OPERATOR_ROLE(), owner));
        assertEq(store.feeCollector(), feeCollector);
        assertEq(store.protocolFeeBps(), PROTOCOL_FEE_BPS);
        assertEq(store.contentCount(), 0);
    }

    function test_RevertWhen_DeployWithZeroAppToken() public {
        vm.expectRevert(ContentStore.ZeroAddress.selector);
        new ContentStore(_createStoreConfig(address(0), address(content721), owner, feeCollector, PROTOCOL_FEE_BPS));
    }

    function test_RevertWhen_DeployWithZeroContent721() public {
        vm.expectRevert(ContentStore.ZeroAddress.selector);
        new ContentStore(_createStoreConfig(address(appToken), address(0), owner, feeCollector, PROTOCOL_FEE_BPS));
    }

    function test_RevertWhen_DeployWithInvalidFeeBps() public {
        vm.expectRevert(ContentStore.InvalidFeeBps.selector);
        new ContentStore(_createStoreConfig(address(appToken), address(content721), owner, feeCollector, 1501));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // LISTING TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_ListContent() public {
        string memory uri = "ipfs://QmContent";
        uint256 maxSupply = 100;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ContentListed(0, uri, CONTENT_PRICE, maxSupply);
        uint256 contentId = store.listContent(uri, CONTENT_PRICE, maxSupply, PaymentTokenType.APP);

        assertEq(contentId, 0);
        assertEq(store.contentCount(), 1);

        ContentStore.Content memory content = store.getContent(0);

        assertEq(content.uri, uri);
        assertEq(content.price, CONTENT_PRICE);
        assertEq(content.maxSupply, maxSupply);
        assertEq(content.minted, 0);
        assertTrue(content.active);
    }

    function test_ListUnlimitedContent() public {
        vm.prank(owner);
        uint256 contentId = store.listContent("ipfs://QmUnlimited", CONTENT_PRICE, 0, PaymentTokenType.APP);

        ContentStore.Content memory content = store.getContent(contentId);
        assertEq(content.maxSupply, 0);
    }

    function test_RevertWhen_ListWithZeroPrice() public {
        vm.expectRevert(ContentStore.ZeroPrice.selector);
        vm.prank(owner);
        store.listContent("ipfs://Qm", 0, 100, PaymentTokenType.APP);
    }

    function test_RevertWhen_NonOperatorLists() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", user1, store.MODULE_OPERATOR_ROLE()
            )
        );
        vm.prank(user1);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 100, PaymentTokenType.APP);
    }

    function test_DeactivateContent() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 100, PaymentTokenType.APP);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ContentDeactivated(0);
        store.deactivateContent(0);

        ContentStore.Content memory content = store.getContent(0);
        assertFalse(content.active);
    }

    function test_ReactivateContent() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 100, PaymentTokenType.APP);

        vm.prank(owner);
        store.deactivateContent(0);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ContentReactivated(0);
        store.reactivateContent(0);

        ContentStore.Content memory content = store.getContent(0);
        assertTrue(content.active);
    }

    function test_RevertWhen_DeactivateNonexistent() public {
        vm.expectRevert(ContentStore.ContentDoesNotExist.selector);
        vm.prank(owner);
        store.deactivateContent(999);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // PURCHASE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Purchase() public {
        // List content
        vm.prank(owner);
        store.listContent("ipfs://QmContent", CONTENT_PRICE, 100, PaymentTokenType.APP);

        // Approve and purchase
        vm.startPrank(user1);
        appToken.approve(address(store), CONTENT_PRICE);

        uint256 expectedProtocolFee = (CONTENT_PRICE * PROTOCOL_FEE_BPS) / 10000;

        vm.expectEmit(true, true, true, true);
        emit ContentPurchased(0, user1, 0, CONTENT_PRICE, expectedProtocolFee);

        uint256 tokenId = store.purchase(0);
        vm.stopPrank();

        // Verify token minted
        assertEq(tokenId, 0);
        assertEq(content721.ownerOf(0), user1);

        // Verify minted count incremented
        ContentStore.Content memory content = store.getContent(0);
        assertEq(content.minted, 1);

        // Verify creator revenue
        uint256 expectedCreatorRevenue = CONTENT_PRICE - expectedProtocolFee;
        assertEq(store.creatorRevenue(PaymentTokenType.APP), expectedCreatorRevenue);
    }

    function test_PurchaseMultipleTimes() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 0, PaymentTokenType.APP); // unlimited

        // User1 purchases
        vm.startPrank(user1);
        appToken.approve(address(store), CONTENT_PRICE * 2);
        store.purchase(0);
        store.purchase(0);
        vm.stopPrank();

        // User2 purchases
        vm.startPrank(user2);
        appToken.approve(address(store), CONTENT_PRICE);
        store.purchase(0);
        vm.stopPrank();

        ContentStore.Content memory content = store.getContent(0);
        assertEq(content.minted, 3);
        assertEq(content721.ownerOf(0), user1);
        assertEq(content721.ownerOf(1), user1);
        assertEq(content721.ownerOf(2), user2);
    }

    function test_RevertWhen_PurchaseNonexistent() public {
        vm.expectRevert(ContentStore.ContentDoesNotExist.selector);
        vm.prank(user1);
        store.purchase(999);
    }

    function test_RevertWhen_PurchaseDeactivated() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 100, PaymentTokenType.APP);

        vm.prank(owner);
        store.deactivateContent(0);

        vm.startPrank(user1);
        appToken.approve(address(store), CONTENT_PRICE);
        vm.expectRevert(ContentStore.ContentNotActive.selector);
        store.purchase(0);
        vm.stopPrank();
    }

    function test_RevertWhen_MaxSupplyReached() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 1, PaymentTokenType.APP); // max 1

        // First purchase succeeds
        vm.startPrank(user1);
        appToken.approve(address(store), CONTENT_PRICE * 2);
        store.purchase(0);

        // Second purchase fails
        vm.expectRevert(ContentStore.MaxSupplyReached.selector);
        store.purchase(0);
        vm.stopPrank();
    }

    function test_PurchaseWithNoFeeCollector() public {
        // Deploy store with no fee collector
        ContentStore noFeeStore = new ContentStore(
            _createStoreConfig(address(appToken), address(content721), owner, address(0), PROTOCOL_FEE_BPS)
        );

        // Update minter
        vm.prank(owner);
        content721.setMinter(address(noFeeStore));

        // List content
        vm.prank(owner);
        noFeeStore.listContent("ipfs://Qm", CONTENT_PRICE, 100, PaymentTokenType.APP);

        // Purchase - all goes to creator since no fee collector
        vm.startPrank(user1);
        appToken.approve(address(noFeeStore), CONTENT_PRICE);
        noFeeStore.purchase(0);
        vm.stopPrank();

        // All revenue goes to creator
        assertEq(noFeeStore.creatorRevenue(PaymentTokenType.APP), CONTENT_PRICE);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // REVENUE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_WithdrawRevenue() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 100, PaymentTokenType.APP);

        vm.startPrank(user1);
        appToken.approve(address(store), CONTENT_PRICE);
        store.purchase(0);
        vm.stopPrank();

        uint256 expectedRevenue = CONTENT_PRICE - (CONTENT_PRICE * PROTOCOL_FEE_BPS / 10000);
        address recipient = makeAddr("recipient");

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit RevenueWithdrawn(recipient, expectedRevenue);
        store.withdrawRevenue(recipient, PaymentTokenType.APP);

        assertEq(appToken.balanceOf(recipient), expectedRevenue);
        assertEq(store.creatorRevenue(PaymentTokenType.APP), 0);
    }

    function test_RevertWhen_WithdrawToZeroAddress() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 100, PaymentTokenType.APP);

        vm.startPrank(user1);
        appToken.approve(address(store), CONTENT_PRICE);
        store.purchase(0);
        vm.stopPrank();

        vm.expectRevert(ContentStore.ZeroAddress.selector);
        vm.prank(owner);
        store.withdrawRevenue(address(0), PaymentTokenType.APP);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ADMIN TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_SetProtocolFeeBps() public {
        vm.prank(owner);
        store.setProtocolFeeBps(1000);

        assertEq(store.protocolFeeBps(), 1000);
    }

    function test_RevertWhen_SetFeeBpsTooHigh() public {
        vm.expectRevert(ContentStore.InvalidFeeBps.selector);
        vm.prank(owner);
        store.setProtocolFeeBps(1501);
    }

    function test_SetFeeCollector() public {
        address newCollector = makeAddr("newCollector");

        vm.prank(owner);
        store.setFeeCollector(newCollector);

        assertEq(store.feeCollector(), newCollector);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // VIEW TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_CanPurchase() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 100, PaymentTokenType.APP);

        (bool canPurchase_, uint8 reason) = store.canPurchase(0);
        assertTrue(canPurchase_);
        assertEq(reason, 0);
    }

    function test_CannotPurchaseNonexistent() public {
        (bool canPurchase_, uint8 reason) = store.canPurchase(999);
        assertFalse(canPurchase_);
        assertEq(reason, 1);
    }

    function test_CannotPurchaseDeactivated() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 100, PaymentTokenType.APP);

        vm.prank(owner);
        store.deactivateContent(0);

        (bool canPurchase_, uint8 reason) = store.canPurchase(0);
        assertFalse(canPurchase_);
        assertEq(reason, 2);
    }

    function test_CannotPurchaseSoldOut() public {
        vm.prank(owner);
        store.listContent("ipfs://Qm", CONTENT_PRICE, 1, PaymentTokenType.APP);

        vm.startPrank(user1);
        appToken.approve(address(store), CONTENT_PRICE);
        store.purchase(0);
        vm.stopPrank();

        (bool canPurchase_, uint8 reason) = store.canPurchase(0);
        assertFalse(canPurchase_);
        assertEq(reason, 3);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUZZ TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_PurchaseWithVariableFees(uint256 price, uint256 feeBps) public {
        price = bound(price, 1 ether, 10000 ether);
        feeBps = bound(feeBps, 0, 1500);

        // Deploy store with variable fee
        ContentStore varStore =
            new ContentStore(_createStoreConfig(address(appToken), address(content721), owner, feeCollector, feeBps));

        vm.prank(owner);
        content721.setMinter(address(varStore));

        // List content
        vm.prank(owner);
        varStore.listContent("ipfs://Qm", price, 0, PaymentTokenType.APP);

        // Mint tokens to user
        vm.prank(admin);
        appToken.mint(user1, price);

        // Purchase
        vm.startPrank(user1);
        appToken.approve(address(varStore), price);
        varStore.purchase(0);
        vm.stopPrank();

        // Verify revenue calculation
        uint256 expectedProtocolFee = (price * feeBps) / 10000;
        uint256 expectedCreatorRevenue = price - expectedProtocolFee;
        assertEq(varStore.creatorRevenue(PaymentTokenType.APP), expectedCreatorRevenue);
    }

    function testFuzz_MultipleListings(uint8 listingCount) public {
        listingCount = uint8(bound(listingCount, 1, 50));

        for (uint256 i = 0; i < listingCount; i++) {
            vm.prank(owner);
            store.listContent(
                string(abi.encodePacked("ipfs://Qm", i)),
                CONTENT_PRICE + i * 1 ether,
                i == 0 ? 0 : i * 10,
                PaymentTokenType.APP
            );
        }

        assertEq(store.contentCount(), listingCount);
    }
}
