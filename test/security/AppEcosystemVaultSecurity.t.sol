// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AppEcosystemVault} from "../../src/vesting/AppEcosystemVault.sol";
import {AirdropDistributor} from "../../src/modules/AirdropDistributor.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock ERC20 for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Malicious token that attempts reentrancy on transfer
contract ReentrantToken is ERC20 {
    AppEcosystemVault public vault;
    address public attackRecipient;
    uint256 public attackAmount;
    bool public attacking;

    constructor() ERC20("Reentrant", "REENT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setAttackParams(AppEcosystemVault _vault, address _recipient, uint256 _amount) external {
        vault = _vault;
        attackRecipient = _recipient;
        attackAmount = _amount;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (attacking) {
            return super.transfer(to, amount);
        }

        // Attempt reentrancy on transfer
        if (address(vault) != address(0) && !attacking) {
            attacking = true;
            try vault.withdraw(attackRecipient, attackAmount) {
            // If this succeeds, reentrancy protection failed
            }
                catch {
                // Expected - reentrancy guard should block
            }
            attacking = false;
        }

        return super.transfer(to, amount);
    }
}

/// @notice Token with callback that attempts withdrawAny reentrancy
contract ReentrantTokenAny is ERC20 {
    AppEcosystemVault public vault;
    address public tokenToWithdraw;
    address public attackRecipient;
    uint256 public attackAmount;
    bool public attacking;

    constructor() ERC20("ReentrantAny", "REENTANY") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setAttackParams(AppEcosystemVault _vault, address _token, address _recipient, uint256 _amount) external {
        vault = _vault;
        tokenToWithdraw = _token;
        attackRecipient = _recipient;
        attackAmount = _amount;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (attacking) {
            return super.transfer(to, amount);
        }

        if (address(vault) != address(0) && !attacking) {
            attacking = true;
            try vault.withdrawAny(tokenToWithdraw, attackRecipient, attackAmount) {
            // Reentrancy attack succeeded - this is bad
            }
                catch {
                // Expected - reentrancy guard should block
            }
            attacking = false;
        }

        return super.transfer(to, amount);
    }
}

/**
 * @title AppEcosystemVaultSecurity
 * @notice Security tests for AppEcosystemVault - access control, fund safety, reentrancy
 * @dev Tests attack vectors for the ecosystem token custody contract
 */
contract AppEcosystemVaultSecurity is Test {
    AppEcosystemVault public vault;
    MockToken public token;
    MockToken public otherToken;

    address public admin = makeAddr("admin");
    address public attacker = makeAddr("attacker");
    address public recipient = makeAddr("recipient");
    address public newAdmin = makeAddr("newAdmin");

    uint256 public constant APP_ID = 1;
    uint256 public constant INITIAL_BALANCE = 250_000 ether;

    function setUp() public {
        token = new MockToken("App Token", "APP");
        otherToken = new MockToken("Other Token", "OTHER");

        vault = new AppEcosystemVault(APP_ID, address(token), admin);

        // Fund vault
        token.mint(address(vault), INITIAL_BALANCE);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyAdminCanWithdraw() public {
        uint256 amount = 50_000 ether;

        // Attacker cannot withdraw
        vm.prank(attacker);
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vault.withdraw(recipient, amount);

        // Random address cannot withdraw
        vm.prank(makeAddr("random"));
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vault.withdraw(recipient, amount);

        // Admin can withdraw
        vm.prank(admin);
        vault.withdraw(recipient, amount);
        assertEq(token.balanceOf(recipient), amount);
    }

    function test_Security_OnlyAdminCanWithdrawAny() public {
        // Fund vault with other token
        otherToken.mint(address(vault), 10_000 ether);

        // Attacker cannot withdraw
        vm.prank(attacker);
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vault.withdrawAny(address(otherToken), recipient, 5_000 ether);

        // Admin can withdraw
        vm.prank(admin);
        vault.withdrawAny(address(otherToken), recipient, 5_000 ether);
        assertEq(otherToken.balanceOf(recipient), 5_000 ether);
    }

    function test_Security_AdminTransferTakesEffectImmediately() public {
        // Transfer admin
        vm.prank(admin);
        vault.setAdmin(newAdmin);

        // New admin immediately has access
        vm.prank(newAdmin);
        vault.withdraw(recipient, 10_000 ether);
        assertEq(token.balanceOf(recipient), 10_000 ether);
    }

    function test_Security_OldAdminCannotActAfterTransfer() public {
        // Transfer admin
        vm.prank(admin);
        vault.setAdmin(newAdmin);

        // Old admin immediately loses access
        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vault.withdraw(recipient, 10_000 ether);

        // Old admin cannot change admin back
        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vault.setAdmin(admin);
    }

    function test_Security_OnlyAdminCanSetAdmin() public {
        // Attacker cannot set admin
        vm.prank(attacker);
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vault.setAdmin(attacker);

        // Admin still admin
        assertEq(vault.admin(), admin);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUND SAFETY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotWithdrawMoreThanBalance() public {
        uint256 excessAmount = INITIAL_BALANCE + 1;

        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.InsufficientBalance.selector);
        vault.withdraw(recipient, excessAmount);
    }

    function test_Security_WithdrawToZeroAddressBlocked() public {
        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.ZeroAddress.selector);
        vault.withdraw(address(0), 10_000 ether);
    }

    function test_Security_ZeroAmountWithdrawBlocked() public {
        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.ZeroAmount.selector);
        vault.withdraw(recipient, 0);
    }

    function test_Security_PartialWithdrawLeavesRemainder() public {
        uint256 withdrawAmount = 100_000 ether;
        uint256 expectedRemainder = INITIAL_BALANCE - withdrawAmount;

        vm.prank(admin);
        vault.withdraw(recipient, withdrawAmount);

        assertEq(vault.balance(), expectedRemainder);
        assertEq(token.balanceOf(address(vault)), expectedRemainder);
    }

    function test_Security_WithdrawAnyChecksBalance() public {
        otherToken.mint(address(vault), 10_000 ether);

        // Cannot withdraw more than balance
        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.InsufficientBalance.selector);
        vault.withdrawAny(address(otherToken), recipient, 10_001 ether);

        // Exact balance works
        vm.prank(admin);
        vault.withdrawAny(address(otherToken), recipient, 10_000 ether);
    }

    function test_Security_WithdrawAnyZeroAddressChecks() public {
        otherToken.mint(address(vault), 10_000 ether);

        // Token address cannot be zero
        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.ZeroAddress.selector);
        vault.withdrawAny(address(0), recipient, 1000 ether);

        // Recipient cannot be zero
        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.ZeroAddress.selector);
        vault.withdrawAny(address(otherToken), address(0), 1000 ether);
    }

    function test_Security_WithdrawAnyZeroAmountBlocked() public {
        otherToken.mint(address(vault), 10_000 ether);

        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.ZeroAmount.selector);
        vault.withdrawAny(address(otherToken), recipient, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REENTRANCY PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ReentrancyOnWithdraw() public {
        // Deploy vault with reentrant token as primary token
        ReentrantToken reentrantToken = new ReentrantToken();
        AppEcosystemVault reentrantVault = new AppEcosystemVault(APP_ID, address(reentrantToken), admin);

        reentrantToken.mint(address(reentrantVault), 100_000 ether);

        // Setup attack params - try to withdraw again during transfer
        reentrantToken.setAttackParams(reentrantVault, attacker, 50_000 ether);

        // Admin withdraws - should complete without reentrancy
        vm.prank(admin);
        reentrantVault.withdraw(recipient, 50_000 ether);

        // Only one withdrawal should have happened
        assertEq(reentrantToken.balanceOf(recipient), 50_000 ether);
        assertEq(reentrantToken.balanceOf(attacker), 0); // Reentrant call failed
        assertEq(reentrantVault.balance(), 50_000 ether);
    }

    function test_Security_ReentrancyOnWithdrawAny() public {
        // Deploy reentrant token that tries to call withdrawAny
        ReentrantTokenAny reentrantToken = new ReentrantTokenAny();
        MockToken primaryToken = new MockToken("Primary", "PRI");

        AppEcosystemVault reentrantVault = new AppEcosystemVault(APP_ID, address(primaryToken), admin);

        reentrantToken.mint(address(reentrantVault), 100_000 ether);
        primaryToken.mint(address(reentrantVault), 50_000 ether);

        // Setup attack - try to withdraw primary token during reentrant token transfer
        reentrantToken.setAttackParams(reentrantVault, address(primaryToken), attacker, 25_000 ether);

        // Admin withdraws reentrant token - should complete without reentrancy
        vm.prank(admin);
        reentrantVault.withdrawAny(address(reentrantToken), recipient, 50_000 ether);

        // Only the intended withdrawal should have happened
        assertEq(reentrantToken.balanceOf(recipient), 50_000 ether);
        assertEq(primaryToken.balanceOf(attacker), 0); // Reentrant call failed
    }

    function test_Security_MaliciousTokenCannotExploitWithdraw() public {
        // Even with a malicious token, the vault should be safe
        ReentrantToken maliciousToken = new ReentrantToken();
        AppEcosystemVault maliciousVault = new AppEcosystemVault(APP_ID, address(maliciousToken), admin);

        maliciousToken.mint(address(maliciousVault), 100_000 ether);
        maliciousToken.setAttackParams(maliciousVault, attacker, 100_000 ether);

        // Multiple withdrawals, all should be atomic
        vm.startPrank(admin);
        maliciousVault.withdraw(recipient, 30_000 ether);
        maliciousVault.withdraw(recipient, 30_000 ether);
        maliciousVault.withdraw(recipient, 30_000 ether);
        vm.stopPrank();

        // All withdrawals went to recipient, none to attacker
        assertEq(maliciousToken.balanceOf(recipient), 90_000 ether);
        assertEq(maliciousToken.balanceOf(attacker), 0);
        assertEq(maliciousVault.balance(), 10_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEGRATION SECURITY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_VaultIntegratesWithAirdropDistributor() public {
        // Deploy airdrop distributor
        AirdropDistributor distributor = new AirdropDistributor(admin, admin);

        // Admin withdraws from vault to distributor
        vm.prank(admin);
        vault.withdraw(address(distributor), 100_000 ether);

        // Distributor now has the tokens
        assertEq(token.balanceOf(address(distributor)), 100_000 ether);

        // Create campaign with those tokens
        bytes32 root = keccak256(abi.encodePacked(recipient, uint256(50_000 ether)));
        vm.prank(admin);
        distributor.createCampaign(APP_ID, address(token), root, "From Vault");

        // Claim works
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(recipient);
        distributor.claim(0, 50_000 ether, proof);

        assertEq(token.balanceOf(recipient), 50_000 ether);
    }

    function test_Security_MultipleWithdrawDestinations() public {
        address dest1 = makeAddr("dest1");
        address dest2 = makeAddr("dest2");
        address dest3 = makeAddr("dest3");

        vm.startPrank(admin);
        vault.withdraw(dest1, 50_000 ether);
        vault.withdraw(dest2, 75_000 ether);
        vault.withdraw(dest3, 25_000 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(dest1), 50_000 ether);
        assertEq(token.balanceOf(dest2), 75_000 ether);
        assertEq(token.balanceOf(dest3), 25_000 ether);
        assertEq(vault.balance(), INITIAL_BALANCE - 150_000 ether);
    }

    function test_Security_EmergencyRecoveryOfStuckTokens() public {
        // Someone accidentally sends random tokens to vault
        MockToken stuckToken = new MockToken("Stuck", "STUCK");
        stuckToken.mint(address(vault), 1_000_000 ether);

        // Admin can recover them
        vm.prank(admin);
        vault.withdrawAny(address(stuckToken), recipient, 1_000_000 ether);

        assertEq(stuckToken.balanceOf(recipient), 1_000_000 ether);
        assertEq(stuckToken.balanceOf(address(vault)), 0);

        // Primary token unaffected
        assertEq(vault.balance(), INITIAL_BALANCE);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_WithdrawalAmounts(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        uint256 balanceBefore = vault.balance();

        vm.prank(admin);
        vault.withdraw(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(vault.balance(), balanceBefore - amount);
    }

    function testFuzz_Security_SequentialWithdrawals(uint256 amount1, uint256 amount2, uint256 amount3) public {
        uint256 total = INITIAL_BALANCE;

        // Bound each withdrawal to remaining balance
        amount1 = bound(amount1, 1, total / 3);
        amount2 = bound(amount2, 1, total / 3);
        amount3 = bound(amount3, 1, total / 3);

        vm.startPrank(admin);
        vault.withdraw(recipient, amount1);
        vault.withdraw(recipient, amount2);
        vault.withdraw(recipient, amount3);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), amount1 + amount2 + amount3);
        assertEq(vault.balance(), INITIAL_BALANCE - amount1 - amount2 - amount3);
    }

    function testFuzz_Security_AdminTransferChain(address admin1, address admin2, address admin3) public {
        vm.assume(admin1 != address(0) && admin2 != address(0) && admin3 != address(0));
        vm.assume(admin1 != admin2 && admin2 != admin3 && admin1 != admin3);

        // Chain of admin transfers
        vm.prank(admin);
        vault.setAdmin(admin1);

        vm.prank(admin1);
        vault.setAdmin(admin2);

        vm.prank(admin2);
        vault.setAdmin(admin3);

        // Only admin3 has access now
        assertEq(vault.admin(), admin3);

        vm.prank(admin3);
        vault.withdraw(recipient, 1000 ether);

        // Previous admins all locked out
        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vault.withdraw(recipient, 1000 ether);

        vm.prank(admin1);
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vault.withdraw(recipient, 1000 ether);

        vm.prank(admin2);
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vault.withdraw(recipient, 1000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_DrainEntireBalance() public {
        // Admin can withdraw entire balance
        vm.prank(admin);
        vault.withdraw(recipient, INITIAL_BALANCE);

        assertEq(vault.balance(), 0);
        assertEq(token.balanceOf(recipient), INITIAL_BALANCE);

        // Cannot withdraw more
        vm.prank(admin);
        vm.expectRevert(AppEcosystemVault.InsufficientBalance.selector);
        vault.withdraw(recipient, 1);
    }

    function test_Security_BalanceOfView() public {
        otherToken.mint(address(vault), 5_000 ether);

        // balanceOf returns correct amounts for different tokens
        assertEq(vault.balanceOf(address(token)), INITIAL_BALANCE);
        assertEq(vault.balanceOf(address(otherToken)), 5_000 ether);

        // After withdrawal
        vm.prank(admin);
        vault.withdrawAny(address(otherToken), recipient, 3_000 ether);

        assertEq(vault.balanceOf(address(otherToken)), 2_000 ether);
    }
}
