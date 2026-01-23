// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "../../src/apps/InAppContent721.sol";
import "forge-std/Test.sol";

contract InAppContent721Test is Test {
    InAppContent721 public content;

    address public owner = makeAddr("owner");
    address public minter = makeAddr("minter");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant APP_ID = 1;
    string public constant NAME = "Test Content";
    string public constant SYMBOL = "TCNT";
    string public constant CONTRACT_URI = "ipfs://QmContract";
    string public constant TOKEN_URI_1 = "ipfs://QmToken1";
    string public constant TOKEN_URI_2 = "ipfs://QmToken2";

    event MinterUpdated(address indexed oldMinter, address indexed newMinter);
    event ContractURIUpdated(string oldURI, string newURI);
    event TokenMetadataUpdated(uint256 indexed tokenId, string uri);
    event DefaultRoyaltySet(address indexed receiver, uint96 feeNumerator);

    function setUp() public {
        content = new InAppContent721(APP_ID, NAME, SYMBOL, owner, minter, CONTRACT_URI);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public {
        assertEq(content.appId(), APP_ID);
        assertEq(content.name(), NAME);
        assertEq(content.symbol(), SYMBOL);
        assertEq(content.owner(), owner);
        assertEq(content.minter(), minter);
        assertEq(content.contractURI(), CONTRACT_URI);
        assertEq(content.totalSupply(), 0);
        assertEq(content.nextTokenId(), 0);
    }

    function test_RevertWhen_DeployWithZeroOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new InAppContent721(APP_ID, NAME, SYMBOL, address(0), minter, CONTRACT_URI);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MINTING TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Mint() public {
        vm.prank(minter);
        vm.expectEmit(true, true, true, true);
        emit TokenMetadataUpdated(0, TOKEN_URI_1);
        uint256 tokenId = content.mint(user1, TOKEN_URI_1);

        assertEq(tokenId, 0);
        assertEq(content.ownerOf(0), user1);
        assertEq(content.tokenURI(0), TOKEN_URI_1);
        assertEq(content.totalSupply(), 1);
    }

    function test_MintMultiple() public {
        vm.startPrank(minter);
        uint256 token1 = content.mint(user1, TOKEN_URI_1);
        uint256 token2 = content.mint(user2, TOKEN_URI_2);
        vm.stopPrank();

        assertEq(token1, 0);
        assertEq(token2, 1);
        assertEq(content.ownerOf(0), user1);
        assertEq(content.ownerOf(1), user2);
        assertEq(content.totalSupply(), 2);
    }

    function test_BatchMint() public {
        string[] memory uris = new string[](3);
        uris[0] = "ipfs://QmA";
        uris[1] = "ipfs://QmB";
        uris[2] = "ipfs://QmC";

        vm.prank(minter);
        uint256[] memory tokenIds = content.batchMint(user1, uris);

        assertEq(tokenIds.length, 3);
        assertEq(tokenIds[0], 0);
        assertEq(tokenIds[1], 1);
        assertEq(tokenIds[2], 2);

        for (uint256 i = 0; i < 3; i++) {
            assertEq(content.ownerOf(tokenIds[i]), user1);
            assertEq(content.tokenURI(tokenIds[i]), uris[i]);
        }
        assertEq(content.totalSupply(), 3);
    }

    function test_RevertWhen_MintByNonMinter() public {
        vm.expectRevert(InAppContent721.NotMinter.selector);
        vm.prank(user1);
        content.mint(user1, TOKEN_URI_1);
    }

    function test_RevertWhen_MintToZeroAddress() public {
        vm.expectRevert(InAppContent721.ZeroAddress.selector);
        vm.prank(minter);
        content.mint(address(0), TOKEN_URI_1);
    }

    function test_RevertWhen_BatchMintToZeroAddress() public {
        string[] memory uris = new string[](1);
        uris[0] = TOKEN_URI_1;

        vm.expectRevert(InAppContent721.ZeroAddress.selector);
        vm.prank(minter);
        content.batchMint(address(0), uris);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ADMIN TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_SetMinter() public {
        address newMinter = makeAddr("newMinter");

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit MinterUpdated(minter, newMinter);
        content.setMinter(newMinter);

        assertEq(content.minter(), newMinter);

        // New minter can mint
        vm.prank(newMinter);
        content.mint(user1, TOKEN_URI_1);
        assertEq(content.ownerOf(0), user1);
    }

    function test_SetContractURI() public {
        string memory newURI = "ipfs://QmNewContract";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ContractURIUpdated(CONTRACT_URI, newURI);
        content.setContractURI(newURI);

        assertEq(content.contractURI(), newURI);
    }

    function test_SetTokenURI() public {
        vm.prank(minter);
        content.mint(user1, TOKEN_URI_1);

        string memory newURI = "ipfs://QmUpdated";

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TokenMetadataUpdated(0, newURI);
        content.setTokenURI(0, newURI);

        assertEq(content.tokenURI(0), newURI);
    }

    function test_RevertWhen_SetTokenURIForNonexistentToken() public {
        vm.expectRevert(InAppContent721.TokenDoesNotExist.selector);
        vm.prank(owner);
        content.setTokenURI(999, "ipfs://QmFake");
    }

    function test_RevertWhen_NonOwnerSetsContractURI() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        content.setContractURI("bad");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ROYALTY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_SetDefaultRoyalty() public {
        uint96 royaltyBps = 500; // 5%

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit DefaultRoyaltySet(owner, royaltyBps);
        content.setDefaultRoyalty(owner, royaltyBps);

        // Mint a token
        vm.prank(minter);
        content.mint(user1, TOKEN_URI_1);

        // Check royalty
        (address receiver, uint256 amount) = content.royaltyInfo(0, 10000);
        assertEq(receiver, owner);
        assertEq(amount, 500); // 5% of 10000
    }

    function test_SetTokenRoyalty() public {
        vm.prank(minter);
        content.mint(user1, TOKEN_URI_1);

        uint96 royaltyBps = 250; // 2.5%

        vm.prank(owner);
        content.setTokenRoyalty(0, user2, royaltyBps);

        (address receiver, uint256 amount) = content.royaltyInfo(0, 10000);
        assertEq(receiver, user2);
        assertEq(amount, 250);
    }

    function test_RevertWhen_RoyaltyTooHigh() public {
        vm.expectRevert(InAppContent721.InvalidRoyalty.selector);
        vm.prank(owner);
        content.setDefaultRoyalty(owner, 1001); // > 10%
    }

    function test_DeleteDefaultRoyalty() public {
        vm.prank(owner);
        content.setDefaultRoyalty(owner, 500);

        vm.prank(owner);
        content.deleteDefaultRoyalty();

        vm.prank(minter);
        content.mint(user1, TOKEN_URI_1);

        (address receiver, uint256 amount) = content.royaltyInfo(0, 10000);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // INTERFACE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_SupportsInterfaces() public {
        // ERC721
        assertTrue(content.supportsInterface(0x80ac58cd));
        // ERC721Metadata
        assertTrue(content.supportsInterface(0x5b5e139f));
        // ERC2981
        assertTrue(content.supportsInterface(0x2a55205a));
        // ERC165
        assertTrue(content.supportsInterface(0x01ffc9a7));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // TRANSFER TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Transfer() public {
        vm.prank(minter);
        content.mint(user1, TOKEN_URI_1);

        vm.prank(user1);
        content.transferFrom(user1, user2, 0);

        assertEq(content.ownerOf(0), user2);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUZZ TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_MintMultiple(uint8 count) public {
        vm.assume(count > 0 && count <= 100);

        for (uint256 i = 0; i < count; i++) {
            vm.prank(minter);
            content.mint(user1, string(abi.encodePacked("ipfs://Qm", i)));
        }

        assertEq(content.totalSupply(), count);
        assertEq(content.balanceOf(user1), count);
    }

    function testFuzz_RoyaltyCalculation(uint96 bps, uint256 salePrice) public {
        bps = uint96(bound(bps, 0, 1000)); // max 10%
        salePrice = bound(salePrice, 0, type(uint128).max); // avoid overflow

        vm.prank(owner);
        content.setDefaultRoyalty(owner, bps);

        vm.prank(minter);
        content.mint(user1, TOKEN_URI_1);

        (address receiver, uint256 amount) = content.royaltyInfo(0, salePrice);

        assertEq(receiver, owner);
        assertEq(amount, (salePrice * bps) / 10000);
    }
}
