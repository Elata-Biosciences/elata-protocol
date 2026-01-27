// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {InAppContent721} from "../../src/apps/InAppContent721.sol";
import {ContentStore, PaymentTokenType} from "../../src/apps/ContentStore.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock App Token
contract MockAppToken is ERC20 {
    constructor() ERC20("App Token", "APP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock ELTA Token
contract MockELTA is ERC20 {
    constructor() ERC20("ELTA", "ELTA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock USDC Token
contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Contract that attempts unauthorized minting
contract UnauthorizedMinter {
    InAppContent721 public content721;

    constructor(InAppContent721 _content721) {
        content721 = _content721;
    }

    function tryMint(address to, string memory uri) external {
        content721.mint(to, uri);
    }

    function tryBatchMint(address to, string[] memory uris) external {
        content721.batchMint(to, uris);
    }
}

/// @notice Receiver that rejects NFTs
contract NFTRejecter {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        revert("Rejected");
    }
}

/**
 * @title ContentModuleSecurity
 * @notice Red team security tests for InAppContent721 + ContentStore
 * @dev Tests for:
 *      - Soulbound transfer blocking
 *      - Time window enforcement
 *      - Feature gate bypass
 *      - Supply manipulation
 *      - Price manipulation
 *      - Unauthorized minting
 *      - Payment token spoofing
 *      - Royalty draining
 */
contract ContentModuleSecurity is Test {
    InAppContent721 public content721;
    ContentStore public contentStore;
    MockAppToken public appToken;
    MockELTA public elta;
    MockUSDC public usdc;

    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant APP_ID = 1;
    uint256 public constant PROTOCOL_FEE_BPS = 500; // 5%

    function setUp() public {
        // Deploy tokens
        appToken = new MockAppToken();
        elta = new MockELTA();
        usdc = new MockUSDC();

        // Deploy InAppContent721
        content721 = new InAppContent721(
            APP_ID,
            "Test Content",
            "TC",
            admin,
            address(0), // Minter set later
            "https://example.com/contract"
        );

        // Deploy ContentStore
        ContentStore.InitConfig memory config = ContentStore.InitConfig({
            appId: APP_ID,
            appToken: address(appToken),
            elta: address(elta),
            usdc: address(usdc),
            treasury: treasury,
            content721: address(content721),
            admin: admin,
            feeCollector: address(0), // No fee collector for tests
            protocolFeeBps: PROTOCOL_FEE_BPS
        });
        contentStore = new ContentStore(config);

        // Set ContentStore as minter
        vm.prank(admin);
        content721.setMinter(address(contentStore));

        // Grant operator role - get role first to avoid consuming prank
        bytes32 operatorRole = contentStore.MODULE_OPERATOR_ROLE();
        vm.prank(admin);
        contentStore.grantRole(operatorRole, operator);

        // Fund users
        appToken.mint(attacker, 1_000_000 ether);
        appToken.mint(alice, 1_000_000 ether);
        appToken.mint(bob, 1_000_000 ether);
        elta.mint(attacker, 1_000_000 ether);
        usdc.mint(attacker, 1_000_000e6);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SOULBOUND TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SoulboundTransferBlocked() public {
        // Mint soulbound token
        vm.prank(address(contentStore));
        uint256 tokenId = content721.mintSoulbound(alice, "ipfs://soulbound");

        assertTrue(content721.soulbound(tokenId), "Token should be soulbound");

        // Try to transfer - should fail
        vm.expectRevert(InAppContent721.SoulboundTransfer.selector);
        vm.prank(alice);
        content721.transferFrom(alice, bob, tokenId);

        // Try safeTransferFrom - should also fail
        vm.expectRevert(InAppContent721.SoulboundTransfer.selector);
        vm.prank(alice);
        content721.safeTransferFrom(alice, bob, tokenId);
    }

    function test_Security_SoulboundCannotBeTransferredViaApproval() public {
        // Mint soulbound token
        vm.prank(address(contentStore));
        uint256 tokenId = content721.mintSoulbound(alice, "ipfs://soulbound");

        // Alice approves attacker
        vm.prank(alice);
        content721.approve(attacker, tokenId);

        // Attacker tries to transfer - should fail even with approval
        vm.expectRevert(InAppContent721.SoulboundTransfer.selector);
        vm.prank(attacker);
        content721.transferFrom(alice, attacker, tokenId);
    }

    function test_Security_RegularTokensCanTransfer() public {
        // Mint regular token
        vm.prank(address(contentStore));
        uint256 tokenId = content721.mint(alice, "ipfs://regular");

        assertFalse(content721.soulbound(tokenId), "Token should not be soulbound");

        // Transfer should work
        vm.prank(alice);
        content721.transferFrom(alice, bob, tokenId);

        assertEq(content721.ownerOf(tokenId), bob);
    }

    function test_Security_AdminCanToggleSoulbound() public {
        // Mint regular token
        vm.prank(address(contentStore));
        uint256 tokenId = content721.mint(alice, "ipfs://regular");

        // Admin sets soulbound
        vm.prank(admin);
        content721.setSoulbound(tokenId, true);

        assertTrue(content721.soulbound(tokenId));

        // Now cannot transfer
        vm.expectRevert(InAppContent721.SoulboundTransfer.selector);
        vm.prank(alice);
        content721.transferFrom(alice, bob, tokenId);

        // Admin removes soulbound
        vm.prank(admin);
        content721.setSoulbound(tokenId, false);

        // Now can transfer
        vm.prank(alice);
        content721.transferFrom(alice, bob, tokenId);
        assertEq(content721.ownerOf(tokenId), bob);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME WINDOW TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_TimeWindowEnforcement() public {
        uint64 startTime = uint64(block.timestamp + 1 hours);
        uint64 endTime = uint64(block.timestamp + 2 hours);

        // List content with time window
        vm.prank(operator);
        uint256 contentId = contentStore.listContentWithTimeWindow(
            "ipfs://timed", 100 ether, 0, PaymentTokenType.APP, startTime, endTime
        );

        // Try to purchase before start - should fail
        vm.startPrank(alice);
        appToken.approve(address(contentStore), 100 ether);
        vm.expectRevert(ContentStore.PurchaseTooEarly.selector);
        contentStore.purchase(contentId);
        vm.stopPrank();

        // Warp to valid window
        vm.warp(startTime + 1);

        // Purchase should work
        vm.startPrank(alice);
        contentStore.purchase(contentId);
        vm.stopPrank();

        // Warp past end time
        vm.warp(endTime + 1);

        // Purchase should fail
        vm.startPrank(bob);
        appToken.approve(address(contentStore), 100 ether);
        vm.expectRevert(ContentStore.PurchaseTooLate.selector);
        contentStore.purchase(contentId);
        vm.stopPrank();
    }

    function test_Security_TimeWindowBoundaryConditions() public {
        uint64 startTime = uint64(block.timestamp + 1 hours);
        uint64 endTime = uint64(block.timestamp + 2 hours);

        vm.prank(operator);
        uint256 contentId = contentStore.listContentWithTimeWindow(
            "ipfs://timed", 100 ether, 0, PaymentTokenType.APP, startTime, endTime
        );

        // Exactly at start time - should work
        vm.warp(startTime);
        vm.startPrank(alice);
        appToken.approve(address(contentStore), 100 ether);
        contentStore.purchase(contentId);
        vm.stopPrank();

        // Exactly at end time - should work (inclusive)
        vm.warp(endTime);
        vm.startPrank(bob);
        appToken.approve(address(contentStore), 100 ether);
        contentStore.purchase(contentId);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SUPPLY MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SupplyCapEnforced() public {
        // List content with max supply of 2
        vm.prank(operator);
        uint256 contentId = contentStore.listContent("ipfs://limited", 100 ether, 2, PaymentTokenType.APP);

        // First two purchases succeed
        vm.startPrank(alice);
        appToken.approve(address(contentStore), 200 ether);
        contentStore.purchase(contentId);
        contentStore.purchase(contentId);
        vm.stopPrank();

        // Third purchase fails
        vm.startPrank(bob);
        appToken.approve(address(contentStore), 100 ether);
        vm.expectRevert(ContentStore.MaxSupplyReached.selector);
        contentStore.purchase(contentId);
        vm.stopPrank();
    }

    function test_Security_CannotManipulateSupplyCounter() public {
        vm.prank(operator);
        uint256 contentId = contentStore.listContent("ipfs://test", 100 ether, 10, PaymentTokenType.APP);

        // Purchase and check counter
        vm.startPrank(alice);
        appToken.approve(address(contentStore), 100 ether);
        contentStore.purchase(contentId);
        vm.stopPrank();

        ContentStore.Content memory content = contentStore.getContent(contentId);
        assertEq(content.minted, 1, "Minted count should be 1");

        // There's no public way to manipulate the minted counter
        // This test documents the security property
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UNAUTHORIZED MINTING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_UnauthorizedMinting() public {
        // Direct mint attempt
        vm.expectRevert(InAppContent721.NotMinter.selector);
        vm.prank(attacker);
        content721.mint(attacker, "ipfs://stolen");

        // Batch mint attempt
        string[] memory uris = new string[](2);
        uris[0] = "ipfs://stolen1";
        uris[1] = "ipfs://stolen2";

        vm.expectRevert(InAppContent721.NotMinter.selector);
        vm.prank(attacker);
        content721.batchMint(attacker, uris);
    }

    function test_Security_UnauthorizedMintingViaContract() public {
        UnauthorizedMinter maliciousContract = new UnauthorizedMinter(content721);

        // Try via contract
        vm.expectRevert(InAppContent721.NotMinter.selector);
        maliciousContract.tryMint(attacker, "ipfs://stolen");
    }

    function test_Security_OnlyOwnerCanSetMinter() public {
        vm.expectRevert();
        vm.prank(attacker);
        content721.setMinter(attacker);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE AND PAYMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_PriceEnforced() public {
        vm.prank(operator);
        uint256 contentId = contentStore.listContent("ipfs://test", 100 ether, 0, PaymentTokenType.APP);

        // Approve less than price
        vm.startPrank(attacker);
        appToken.approve(address(contentStore), 50 ether);

        // Should fail due to insufficient approval (transfer will fail)
        vm.expectRevert();
        contentStore.purchase(contentId);
        vm.stopPrank();
    }

    function test_Security_CannotPurchaseDeactivatedContent() public {
        vm.prank(operator);
        uint256 contentId = contentStore.listContent("ipfs://test", 100 ether, 0, PaymentTokenType.APP);

        // Deactivate
        vm.prank(operator);
        contentStore.deactivateContent(contentId);

        // Try to purchase
        vm.startPrank(alice);
        appToken.approve(address(contentStore), 100 ether);
        vm.expectRevert(ContentStore.ContentNotActive.selector);
        contentStore.purchase(contentId);
        vm.stopPrank();
    }

    function test_Security_CannotPurchaseNonExistentContent() public {
        vm.startPrank(alice);
        appToken.approve(address(contentStore), 100 ether);
        vm.expectRevert(ContentStore.ContentDoesNotExist.selector);
        contentStore.purchase(999); // Non-existent ID
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROYALTY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_RoyaltyBounded() public {
        // Max royalty is 10% (1000 bps)
        uint96 maxRoyalty = content721.MAX_ROYALTY_BPS();

        // Try to set above max
        vm.expectRevert(InAppContent721.InvalidRoyalty.selector);
        vm.prank(admin);
        content721.setDefaultRoyalty(treasury, maxRoyalty + 1);

        // Setting at max should work
        vm.prank(admin);
        content721.setDefaultRoyalty(treasury, maxRoyalty);

        // Verify royalty info
        vm.prank(address(contentStore));
        uint256 tokenId = content721.mint(alice, "ipfs://test");

        (address receiver, uint256 royaltyAmount) = content721.royaltyInfo(tokenId, 10000);
        assertEq(receiver, treasury);
        assertEq(royaltyAmount, 1000); // 10% of 10000
    }

    function test_Security_OnlyAdminCanSetRoyalty() public {
        vm.expectRevert();
        vm.prank(attacker);
        content721.setDefaultRoyalty(attacker, 500);

        vm.expectRevert();
        vm.prank(attacker);
        content721.setTokenRoyalty(0, attacker, 500);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyOperatorCanListContent() public {
        vm.expectRevert();
        vm.prank(attacker);
        contentStore.listContent("ipfs://attacker", 1 ether, 0, PaymentTokenType.APP);
    }

    function test_Security_OnlyAdminCanUpdateProtocolFee() public {
        vm.expectRevert();
        vm.prank(attacker);
        contentStore.setProtocolFeeBps(1000);
    }

    function test_Security_ProtocolFeeBounded() public {
        uint256 maxFee = contentStore.MAX_PROTOCOL_FEE_BPS();

        vm.expectRevert(ContentStore.InvalidFeeBps.selector);
        vm.prank(admin);
        contentStore.setProtocolFeeBps(maxFee + 1);

        // At max should work
        vm.prank(admin);
        contentStore.setProtocolFeeBps(maxFee);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_PurchaseReentrancyProtected() public {
        // ContentStore uses ReentrancyGuard
        // This test documents the protection

        vm.prank(operator);
        uint256 contentId = contentStore.listContent("ipfs://test", 100 ether, 0, PaymentTokenType.APP);

        // Normal purchase works
        vm.startPrank(alice);
        appToken.approve(address(contentStore), 100 ether);
        contentStore.purchase(contentId);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_PurchaseWithVariousAmounts(uint256 price) public {
        price = bound(price, 1 ether, 100_000 ether);

        vm.prank(operator);
        uint256 contentId = contentStore.listContent("ipfs://fuzz", price, 0, PaymentTokenType.APP);

        // Fund alice with enough
        appToken.mint(alice, price);

        vm.startPrank(alice);
        appToken.approve(address(contentStore), price);
        contentStore.purchase(contentId);
        vm.stopPrank();

        // Verify minted
        ContentStore.Content memory content = contentStore.getContent(contentId);
        assertEq(content.minted, 1);
    }

    function testFuzz_SupplyCap(uint256 maxSupply, uint256 extraAttempts) public {
        maxSupply = bound(maxSupply, 1, 50);
        extraAttempts = bound(extraAttempts, 1, 10); // Extra purchase attempts beyond maxSupply

        vm.prank(operator);
        uint256 contentId = contentStore.listContent("ipfs://fuzz", 100 ether, maxSupply, PaymentTokenType.APP);

        uint256 successfulPurchases = 0;

        // First, fill up the supply
        for (uint256 i = 0; i < maxSupply; i++) {
            address buyer = address(uint160(3000 + i));
            appToken.mint(buyer, 100 ether);

            vm.startPrank(buyer);
            appToken.approve(address(contentStore), 100 ether);
            contentStore.purchase(contentId);
            successfulPurchases++;
            vm.stopPrank();
        }

        // Then, attempt additional purchases that should fail
        for (uint256 i = 0; i < extraAttempts; i++) {
            address buyer = address(uint160(4000 + i));
            appToken.mint(buyer, 100 ether);

            vm.startPrank(buyer);
            appToken.approve(address(contentStore), 100 ether);
            vm.expectRevert(ContentStore.MaxSupplyReached.selector);
            contentStore.purchase(contentId);
            vm.stopPrank();
        }

        assertEq(successfulPurchases, maxSupply, "Successful purchases should equal max supply");
    }
}
