// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract AppTokenTest is Test {
    AppToken public token;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public minter = makeAddr("minter");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    event AppMetadataUpdated(string description, string imageURI, string website);
    event MintingFinalized();
    event Minted(address indexed to, uint256 amount);

    function setUp() public {
        token = new AppToken("TestApp Token", "TEST", 18, MAX_SUPPLY, creator, admin);
    }

    function test_Deployment() public {
        assertEq(token.name(), "TestApp Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.decimals(), 18);
        assertEq(token.maxSupply(), MAX_SUPPLY);
        assertEq(token.appCreator(), creator);
        assertEq(token.totalSupply(), 0);

        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
    }

    function test_RevertWhen_DeploymentZeroAddress() public {
        vm.expectRevert("Zero address");
        new AppToken("Test", "TEST", 18, MAX_SUPPLY, address(0), admin);

        vm.expectRevert("Zero address");
        new AppToken("Test", "TEST", 18, MAX_SUPPLY, creator, address(0));
    }

    function test_RevertWhen_DeploymentInvalidSupply() public {
        vm.expectRevert("Invalid supply");
        new AppToken("Test", "TEST", 18, 0, creator, admin);
    }

    function test_Mint() public {
        uint256 amount = 1_000_000 ether;

        vm.prank(admin);
        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function test_RevertWhen_MintUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        token.mint(user1, 1000 ether);
    }

    function test_RevertWhen_MintExceedsSupply() public {
        vm.expectRevert(AppToken.SupplyCapExceeded.selector);
        vm.prank(admin);
        token.mint(user1, MAX_SUPPLY + 1);
    }

    function test_MintUpToSupplyCap() public {
        vm.prank(admin);
        token.mint(user1, MAX_SUPPLY);

        assertEq(token.totalSupply(), MAX_SUPPLY);

        // Try to mint one more token
        vm.expectRevert(AppToken.SupplyCapExceeded.selector);
        vm.prank(admin);
        token.mint(user1, 1);
    }

    function test_Burn() public {
        // Mint tokens first
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        // User burns their tokens
        vm.prank(user1);
        token.burn(500 ether);

        assertEq(token.balanceOf(user1), 500 ether);
        assertEq(token.totalSupply(), 500 ether);
    }

    function test_UpdateMetadata() public {
        string memory description = "Revolutionary EEG game";
        string memory imageURI = "ipfs://QmHash123";
        string memory website = "https://testapp.com";

        vm.expectEmit(true, true, true, true);
        emit AppMetadataUpdated(description, imageURI, website);

        vm.prank(creator);
        token.updateMetadata(description, imageURI, website);

        assertEq(token.appDescription(), description);
        assertEq(token.appImageURI(), imageURI);
        assertEq(token.appWebsite(), website);
    }

    function test_RevertWhen_UpdateMetadataUnauthorized() public {
        vm.expectRevert(AppToken.OnlyCreator.selector);
        vm.prank(user1);
        token.updateMetadata("Unauthorized", "", "");
    }

    function test_AdminCanMint() public {
        // Admin (who has MINTER_ROLE by default) can mint
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        assertEq(token.balanceOf(user1), 1000 ether);
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
    }

    function test_MinterRoleManagement() public {
        // Verify admin has minter role initially
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));

        // Admin can revoke their own minter role
        vm.prank(admin);
        token.revokeMinter(admin);

        assertFalse(token.hasRole(token.MINTER_ROLE(), admin));

        // Admin can no longer mint after revoking role
        vm.expectRevert();
        vm.prank(admin);
        token.mint(user1, 1000 ether);
    }

    function test_StandardERC20Functions() public {
        // Mint tokens to users
        vm.startPrank(admin);
        token.mint(user1, 1000 ether);
        token.mint(user2, 500 ether);
        vm.stopPrank();

        // Test transfer
        vm.prank(user1);
        token.transfer(user2, 200 ether);

        assertEq(token.balanceOf(user1), 800 ether);
        assertEq(token.balanceOf(user2), 700 ether);

        // Test approval and transferFrom
        vm.prank(user1);
        token.approve(user2, 300 ether);

        vm.prank(user2);
        token.transferFrom(user1, user2, 300 ether);

        assertEq(token.balanceOf(user1), 500 ether);
        assertEq(token.balanceOf(user2), 1000 ether);
    }

    function test_BurnFrom() public {
        // Mint and approve
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        vm.prank(user1);
        token.approve(user2, 500 ether);

        // Burn from allowance
        vm.prank(user2);
        token.burnFrom(user1, 300 ether);

        assertEq(token.balanceOf(user1), 700 ether);
        assertEq(token.totalSupply(), 700 ether);
        assertEq(token.allowance(user1, user2), 200 ether);
    }

    function testFuzz_Mint(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY);

        vm.prank(admin);
        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function testFuzz_Burn(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, MAX_SUPPLY);
        burnAmount = bound(burnAmount, 1, mintAmount);

        vm.prank(admin);
        token.mint(user1, mintAmount);

        vm.prank(user1);
        token.burn(burnAmount);

        assertEq(token.balanceOf(user1), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    function test_MetadataUpdates() public {
        // Initial metadata should be empty
        assertEq(token.appDescription(), "");
        assertEq(token.appImageURI(), "");
        assertEq(token.appWebsite(), "");

        // Update metadata multiple times
        vm.startPrank(creator);

        token.updateMetadata("Version 1", "ipfs://v1", "https://v1.com");
        assertEq(token.appDescription(), "Version 1");

        token.updateMetadata("Version 2", "ipfs://v2", "https://v2.com");
        assertEq(token.appDescription(), "Version 2");
        assertEq(token.appImageURI(), "ipfs://v2");
        assertEq(token.appWebsite(), "https://v2.com");

        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FINALIZE MINTING TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_FinalizeMinting() public {
        assertFalse(token.mintingFinalized());

        vm.expectEmit(true, true, true, true);
        emit MintingFinalized();

        vm.prank(admin);
        token.finalizeMinting();

        assertTrue(token.mintingFinalized());
    }

    function test_RevertWhen_MintAfterFinalize() public {
        vm.prank(admin);
        token.finalizeMinting();

        vm.expectRevert(AppToken.MintingAlreadyFinalized.selector);
        vm.prank(admin);
        token.mint(user1, 1000 ether);
    }

    function test_RevertWhen_FinalizeMintingUnauthorized() public {
        vm.expectRevert();
        vm.prank(user1);
        token.finalizeMinting();
    }

    function test_MintBeforeFinalize() public {
        // Mint should work before finalize
        vm.prank(admin);
        token.mint(user1, 1000 ether);
        assertEq(token.balanceOf(user1), 1000 ether);

        // Finalize
        vm.prank(admin);
        token.finalizeMinting();

        // Mint should fail after finalize
        vm.expectRevert(AppToken.MintingAlreadyFinalized.selector);
        vm.prank(admin);
        token.mint(user1, 1000 ether);
    }

    function test_PermitFunctionality() public {
        // Test that permit extension is available
        assertEq(token.DOMAIN_SEPARATOR(), token.DOMAIN_SEPARATOR());
        assertEq(token.nonces(user1), 0);
    }
}
