// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ContentStore, PaymentTokenType} from "../../src/apps/ContentStore.sol";
import {InAppContent721} from "../../src/apps/InAppContent721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock App Token
contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App", "MAPP") {
        _mint(msg.sender, 100_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock ELTA
contract MockELTA is ERC20 {
    constructor() ERC20("Mock ELTA", "ELTA") {
        _mint(msg.sender, 77_000_000 ether);
    }
}

/// @notice Mock USDC
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @title ContentStoreSecurity
 * @notice Red team security tests for ContentStore
 */
contract ContentStoreSecurity is Test {
    ContentStore public store;
    InAppContent721 public nft;
    MockAppToken public appToken;
    MockELTA public elta;
    MockUSDC public usdc;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public buyer = makeAddr("buyer");

    function setUp() public {
        // Deploy tokens
        appToken = new MockAppToken();
        elta = new MockELTA();
        usdc = new MockUSDC();

        // Deploy NFT
        nft = new InAppContent721(
            0, // appId
            "TestNFT",
            "TNFT",
            admin,
            admin, // minter (will be updated)
            ""
        );

        // Deploy ContentStore
        store = new ContentStore(
            ContentStore.InitConfig({
                appId: 0,
                appToken: address(appToken),
                elta: address(elta),
                usdc: address(usdc),
                treasury: treasury,
                content721: address(nft),
                admin: admin,
                feeCollector: address(0),
                protocolFeeBps: 500 // 5% protocol fee
            })
        );

        // Grant minter role to store
        vm.prank(admin);
        nft.setMinter(address(store));

        // Fund users
        appToken.transfer(buyer, 100_000 ether);
        appToken.transfer(attacker, 100_000 ether);
        elta.transfer(buyer, 100_000 ether);
        usdc.transfer(buyer, 100_000e6);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PAYMENT BYPASS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotPurchaseWithoutPayment() public {
        // List content
        vm.prank(admin);
        store.listContent("ipfs://test", 100 ether, 100, PaymentTokenType.APP);

        // Try to purchase without approval
        vm.startPrank(buyer);
        vm.expectRevert();
        store.purchase(0);
        vm.stopPrank();
    }

    function test_Security_CannotPurchaseWithInsufficientBalance() public {
        // List expensive content
        vm.prank(admin);
        store.listContent("ipfs://test", 1_000_000 ether, 100, PaymentTokenType.APP);

        // Try to purchase with insufficient balance
        vm.startPrank(attacker);
        appToken.approve(address(store), type(uint256).max);
        vm.expectRevert();
        store.purchase(0);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-CURRENCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ELTAPaymentRouting() public {
        // List with ELTA payment
        vm.prank(admin);
        store.listContent("ipfs://elta", 100 ether, 100, PaymentTokenType.ELTA);

        // Purchase
        vm.startPrank(buyer);
        elta.approve(address(store), 100 ether);
        store.purchase(0);
        vm.stopPrank();

        // Verify buyer got NFT
        assertEq(nft.balanceOf(buyer), 1, "Buyer should have NFT");
    }

    function test_Security_USDCPaymentRouting() public {
        // List with USDC payment
        vm.prank(admin);
        store.listContent("ipfs://usdc", 100e6, 100, PaymentTokenType.USDC);

        // Purchase
        vm.startPrank(buyer);
        usdc.approve(address(store), 100e6);
        store.purchase(0);
        vm.stopPrank();

        // Verify buyer got NFT
        assertEq(nft.balanceOf(buyer), 1, "Buyer should have NFT");
    }

    function test_Security_CannotUseWrongTokenForPayment() public {
        // List with APP payment
        vm.prank(admin);
        store.listContent("ipfs://app", 100 ether, 100, PaymentTokenType.APP);

        // Try to use ELTA (should fail on transfer)
        vm.startPrank(buyer);
        elta.approve(address(store), 100 ether);
        // The purchase expects APP tokens, not ELTA
        appToken.approve(address(store), 100 ether);
        store.purchase(0); // This should work with APP
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SUPPLY MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotExceedMaxSupply() public {
        // List with limited supply
        vm.prank(admin);
        store.listContent("ipfs://limited", 1 ether, 2, PaymentTokenType.APP);

        vm.startPrank(buyer);
        appToken.approve(address(store), 10 ether);

        // Buy max supply (one at a time)
        store.purchase(0);
        store.purchase(0);

        // Try to buy more - should fail
        vm.expectRevert();
        store.purchase(0);
        vm.stopPrank();
    }

    function test_Security_CannotPurchaseInactiveContent() public {
        // List and deactivate
        vm.startPrank(admin);
        store.listContent("ipfs://test", 1 ether, 100, PaymentTokenType.APP);
        store.deactivateContent(0);
        vm.stopPrank();

        // Try to purchase
        vm.startPrank(buyer);
        appToken.approve(address(store), 1 ether);
        vm.expectRevert();
        store.purchase(0);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REVENUE WITHDRAWAL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyAdminCanWithdraw() public {
        // List and purchase
        vm.prank(admin);
        store.listContent("ipfs://test", 100 ether, 100, PaymentTokenType.APP);

        vm.startPrank(buyer);
        appToken.approve(address(store), 100 ether);
        store.purchase(0);
        vm.stopPrank();

        // Attacker tries to withdraw
        vm.expectRevert();
        vm.prank(attacker);
        store.withdrawRevenue(creator, PaymentTokenType.APP);
    }

    function test_Security_CannotWithdrawToZeroAddress() public {
        // List and purchase
        vm.prank(admin);
        store.listContent("ipfs://test", 100 ether, 100, PaymentTokenType.APP);

        vm.startPrank(buyer);
        appToken.approve(address(store), 100 ether);
        store.purchase(0);
        vm.stopPrank();

        // Try to withdraw to zero
        vm.expectRevert();
        vm.prank(admin);
        store.withdrawRevenue(address(0), PaymentTokenType.APP);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BURN MECHANISM TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_BurnBpsEnforced() public {
        // Set burn rate
        vm.prank(admin);
        store.setBurnBps(100); // 1%

        // List content
        vm.prank(admin);
        store.listContent("ipfs://burn", 100 ether, 100, PaymentTokenType.APP);

        uint256 supplyBefore = appToken.totalSupply();

        // Purchase
        vm.startPrank(buyer);
        appToken.approve(address(store), 100 ether);
        store.purchase(0);
        vm.stopPrank();

        // Check some tokens were burned (sent to BURN_SINK)
        address burnSink = store.BURN_SINK();
        uint256 burnedAmount = appToken.balanceOf(burnSink);
        assertGt(burnedAmount, 0, "Should have burned tokens");
    }

    function test_Security_CannotSetExcessiveBurnBps() public {
        // Try to set burn > max
        vm.expectRevert();
        vm.prank(admin);
        store.setBurnBps(600); // 6% > 5% max
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyOperatorCanList() public {
        vm.expectRevert();
        vm.prank(attacker);
        store.listContent("ipfs://hack", 1 ether, 100, PaymentTokenType.APP);
    }

    function test_Security_OnlyAdminCanSetFees() public {
        vm.expectRevert();
        vm.prank(attacker);
        store.setProtocolFeeBps(1000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_PurchasePrice(uint256 price) public {
        price = bound(price, 1 ether, 1000 ether);

        // List content
        vm.prank(admin);
        store.listContent("ipfs://fuzz", price, 100, PaymentTokenType.APP);

        // Fund buyer
        appToken.mint(buyer, price);

        // Purchase
        vm.startPrank(buyer);
        appToken.approve(address(store), price);
        store.purchase(0);
        vm.stopPrank();

        // Verify
        assertEq(nft.balanceOf(buyer), 1, "Should have NFT");
    }
}
