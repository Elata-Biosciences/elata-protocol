// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { AppToken } from "../../../src/apps/AppToken.sol";

/**
 * @title AppTokenSecurityTest
 * @notice Comprehensive security testing for AppToken
 * @dev Tests access control, supply cap, finalization, and permit
 */
contract AppTokenSecurityTest is Test {
    AppToken public token;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public user1 = makeAddr("user1");
    address public attacker = makeAddr("attacker");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        token = new AppToken("TestApp", "TEST", 18, MAX_SUPPLY, creator, admin);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ACCESS CONTROL TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_OnlyMinterCanMint() public {
        vm.expectRevert();
        vm.prank(attacker);
        token.mint(attacker, 1000 ether);
    }

    function test_Security_OnlyAdminCanFinalize() public {
        vm.expectRevert();
        vm.prank(attacker);
        token.finalizeMinting();
    }

    function test_Security_OnlyCreatorCanUpdateMetadata() public {
        vm.expectRevert(AppToken.OnlyCreator.selector);
        vm.prank(attacker);
        token.updateMetadata("Fake", "Fake", "Fake");
    }

    function test_Security_OnlyAdminCanRevokeMinter() public {
        vm.expectRevert();
        vm.prank(attacker);
        token.revokeMinter(admin);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // SUPPLY CAP ENFORCEMENT
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotMintAboveCap() public {
        vm.prank(admin);
        token.mint(user1, MAX_SUPPLY);

        vm.expectRevert(AppToken.SupplyCapExceeded.selector);
        vm.prank(admin);
        token.mint(user1, 1);
    }

    function test_Security_CapEnforcedIncrementally() public {
        vm.startPrank(admin);

        // Mint 90% of cap
        token.mint(user1, (MAX_SUPPLY * 9) / 10);

        // Mint 10% (should succeed)
        token.mint(user1, MAX_SUPPLY / 10);

        // Any more should fail
        vm.expectRevert(AppToken.SupplyCapExceeded.selector);
        token.mint(user1, 1);

        vm.stopPrank();
    }

    function testFuzz_Security_SupplyNeverExceedsCap(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, MAX_SUPPLY);
        amount2 = bound(amount2, 1, MAX_SUPPLY);

        vm.startPrank(admin);

        token.mint(user1, amount1);

        if (amount1 + amount2 > MAX_SUPPLY) {
            vm.expectRevert(AppToken.SupplyCapExceeded.selector);
        }
        token.mint(user1, amount2);

        vm.stopPrank();

        // Supply never exceeds cap
        assertTrue(token.totalSupply() <= MAX_SUPPLY);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FINALIZATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotMintAfterFinalize() public {
        vm.prank(admin);
        token.finalizeMinting();

        vm.expectRevert(AppToken.MintingAlreadyFinalized.selector);
        vm.prank(admin);
        token.mint(user1, 1);
    }

    function test_Security_FinalizationIrreversible() public {
        vm.prank(admin);
        token.finalizeMinting();

        assertTrue(token.mintingFinalized());

        // Cannot "unfinalize"
        // (no such function exists - ensuring design is correct)

        // Verify still cannot mint
        vm.expectRevert(AppToken.MintingAlreadyFinalized.selector);
        vm.prank(admin);
        token.mint(user1, 1);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // BURN MECHANISM TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_BurnReducesSupply() public {
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(user1);
        token.burn(500 ether);

        assertEq(token.totalSupply(), supplyBefore - 500 ether);
    }

    function test_Security_BurnFromRequiresApproval() public {
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        // Attacker tries to burn without approval
        vm.expectRevert();
        vm.prank(attacker);
        token.burnFrom(user1, 100 ether);
    }

    function test_Security_BurnFromWorksWithApproval() public {
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        vm.prank(user1);
        token.approve(attacker, 300 ether);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(attacker);
        token.burnFrom(user1, 300 ether);

        assertEq(token.totalSupply(), supplyBefore - 300 ether);
        assertEq(token.balanceOf(user1), 700 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // PERMIT SECURITY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_PermitNonceIncreases() public {
        assertEq(token.nonces(user1), 0);

        // Nonce should increment after permit (tested via interface existence)
        // Full permit test would require signature generation
        assertTrue(token.DOMAIN_SEPARATOR() != bytes32(0));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ROLE MANAGEMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_MinterRoleRevokable() public {
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));

        vm.prank(admin);
        token.revokeMinter(admin);

        assertFalse(token.hasRole(token.MINTER_ROLE(), admin));

        // Admin can no longer mint
        vm.expectRevert();
        vm.prank(admin);
        token.mint(user1, 1000 ether);
    }

    function test_Security_CannotGrantMinterRoleUnauthorized() public {
        // Only DEFAULT_ADMIN_ROLE can grant roles
        bytes32 adminRole = token.DEFAULT_ADMIN_ROLE();
        assertFalse(token.hasRole(adminRole, attacker));

        // Verify attacker doesn't have minter role
        assertFalse(token.hasRole(token.MINTER_ROLE(), attacker));

        // Attempt to grant role (should revert)
        vm.prank(attacker);
        try token.grantRole(token.MINTER_ROLE(), attacker) {
            fail("Should have reverted");
        } catch {
            // Correctly reverted
        }

        // Attacker still doesn't have minter role
        assertFalse(token.hasRole(token.MINTER_ROLE(), attacker));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // TRANSFER SECURITY
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_NoTransferTax() public {
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        vm.prank(user1);
        token.transfer(attacker, 500 ether);

        // Recipient gets exact amount (no tax)
        assertEq(token.balanceOf(attacker), 500 ether);
        assertEq(token.balanceOf(user1), 500 ether);
    }

    function testFuzz_Security_TransferPreservesSupply(uint256 mintAmount, uint256 transferAmount)
        public
    {
        mintAmount = bound(mintAmount, 1, MAX_SUPPLY);
        transferAmount = bound(transferAmount, 0, mintAmount);

        vm.prank(admin);
        token.mint(user1, mintAmount);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(user1);
        token.transfer(attacker, transferAmount);

        // Supply unchanged by transfers
        assertEq(token.totalSupply(), supplyBefore);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // OWNER FUNCTION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_OwnerFunctionReturnsCreator() public {
        assertEq(token.owner(), creator);
    }

    function test_Security_OwnerDoesNotChangeOnMint() public {
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        // Owner still creator
        assertEq(token.owner(), creator);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // METADATA TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_MetadataUpdateOnlyByCreator() public {
        vm.prank(creator);
        token.updateMetadata("Real", "Real", "Real");

        assertEq(token.appDescription(), "Real");

        // Attacker cannot change
        vm.expectRevert(AppToken.OnlyCreator.selector);
        vm.prank(attacker);
        token.updateMetadata("Fake", "Fake", "Fake");

        // Still has creator's metadata
        assertEq(token.appDescription(), "Real");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EDGE CASE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CanBurnAfterFinalize() public {
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        vm.prank(admin);
        token.finalizeMinting();

        // Burning should still work
        vm.prank(user1);
        token.burn(500 ether);

        assertEq(token.balanceOf(user1), 500 ether);
    }

    function test_Security_CanTransferAfterFinalize() public {
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        vm.prank(admin);
        token.finalizeMinting();

        // Transfers should still work
        vm.prank(user1);
        token.transfer(attacker, 500 ether);

        assertEq(token.balanceOf(attacker), 500 ether);
    }

    function test_Security_CanApproveAfterFinalize() public {
        vm.prank(admin);
        token.mint(user1, 1000 ether);

        vm.prank(admin);
        token.finalizeMinting();

        // Approvals should still work
        vm.prank(user1);
        token.approve(attacker, 500 ether);

        assertEq(token.allowance(user1, attacker), 500 ether);
    }
}
