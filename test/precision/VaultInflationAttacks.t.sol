// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {AppStakingVault} from "../../src/apps/AppStakingVault.sol";
import {PrecisionFixtures} from "../fixtures/PrecisionFixtures.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VaultInflationAttacks
 * @notice Tests for ERC4626-style share inflation and first depositor attacks
 * @dev AppStakingVault uses 1:1 shares - tests verify this is safe from manipulation
 *
 * Key findings from analysis:
 * - Shares are minted 1:1 with deposits
 * - No first depositor protection exists
 * - Shares are non-transferable (soulbound)
 *
 * Attack vectors tested:
 * - First depositor donation attacks
 * - Share dilution via direct transfers
 * - Front-running first deposit
 * - Dust deposit griefing
 */
contract VaultInflationAttacks is Test, PrecisionFixtures {
    AppToken public appToken;
    AppStakingVault public vault;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public victim = makeAddr("victim");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;

    function setUp() public {
        // Deploy AppToken
        appToken = new AppToken(
            "TestApp", "TEST", 18, APP_TOKEN_SUPPLY, creator, admin, governance, treasury, treasury, treasury
        );

        // Mint initial supply
        vm.prank(admin);
        appToken.mint(admin, APP_TOKEN_SUPPLY);

        // Deploy AppStakingVault
        vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), admin);

        // Distribute tokens
        vm.startPrank(admin);
        appToken.transfer(attacker, 1_000_000 ether);
        appToken.transfer(victim, 1_000_000 ether);
        appToken.transfer(user1, 1_000_000 ether);
        appToken.transfer(user2, 1_000_000 ether);
        vm.stopPrank();

        // Approve vault
        vm.prank(attacker);
        appToken.approve(address(vault), type(uint256).max);
        vm.prank(victim);
        appToken.approve(address(vault), type(uint256).max);
        vm.prank(user1);
        appToken.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        appToken.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FIRST DEPOSITOR ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test classic first depositor inflation attack
    /// @dev In vulnerable ERC4626 vaults, attacker can:
    ///      1. Deposit 1 wei, get 1 share
    ///      2. Donate large amount directly
    ///      3. Victim deposits, gets diluted shares
    ///      But AppStakingVault uses 1:1 shares, so this doesn't work
    function test_Attack_FirstDepositorInflation_NotEffective() public {
        // Step 1: Attacker deposits 1 wei as first depositor
        vm.prank(attacker);
        vault.stake(1);

        assertEq(vault.balanceOf(attacker), 1, "Attacker should have 1 share");
        assertEq(vault.totalSupply(), 1, "Total supply should be 1");

        // Step 2: Attacker donates 1000 tokens directly to vault
        vm.prank(attacker);
        appToken.transfer(address(vault), 1000 ether);

        // Vault now has 1000 ether + 1 wei tokens, but only 1 share exists

        // Step 3: Victim deposits 500 tokens
        uint256 victimDeposit = 500 ether;
        vm.prank(victim);
        vault.stake(victimDeposit);

        // With 1:1 shares, victim gets exactly 500e18 shares
        assertEq(vault.balanceOf(victim), victimDeposit, "Victim should get 1:1 shares");

        // Step 4: Verify victim can withdraw full amount
        vm.prank(victim);
        vault.unstake(victimDeposit);

        assertEq(appToken.balanceOf(victim), 1_000_000 ether, "Victim should recover full deposit");
    }

    /// @notice Test that direct donation doesn't affect share price
    function test_Attack_DonationDoesNotAffectShares() public {
        // User1 deposits
        uint256 deposit1 = 1000 ether;
        vm.prank(user1);
        vault.stake(deposit1);

        // Attacker donates directly
        vm.prank(attacker);
        appToken.transfer(address(vault), 5000 ether);

        // User2 deposits same amount
        uint256 deposit2 = 1000 ether;
        vm.prank(user2);
        vault.stake(deposit2);

        // Both users should have same shares (1:1)
        assertEq(vault.balanceOf(user1), deposit1, "User1 shares incorrect");
        assertEq(vault.balanceOf(user2), deposit2, "User2 shares incorrect");

        // Both can withdraw their full deposits
        vm.prank(user1);
        vault.unstake(deposit1);
        vm.prank(user2);
        vault.unstake(deposit2);

        assertEq(appToken.balanceOf(user1), 1_000_000 ether, "User1 should recover deposit");
        assertEq(appToken.balanceOf(user2), 1_000_000 ether, "User2 should recover deposit");

        // Donated tokens remain in vault (no one claims them)
        assertEq(appToken.balanceOf(address(vault)), 5000 ether, "Donation should remain");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FRONT-RUNNING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test front-running victim's first deposit
    function test_Attack_FrontRunFirstDeposit() public {
        // Scenario: Victim plans to be first depositor with 1000 tokens
        // Attacker sees tx in mempool and front-runs

        // Attacker front-runs with minimal deposit
        vm.prank(attacker);
        vault.stake(1);

        // Victim's tx executes after
        uint256 victimDeposit = 1000 ether;
        vm.prank(victim);
        vault.stake(victimDeposit);

        // With 1:1 shares, victim is unaffected
        assertEq(vault.balanceOf(victim), victimDeposit, "Victim gets correct shares");

        // Verify withdrawal
        vm.prank(victim);
        vault.unstake(victimDeposit);
        assertEq(appToken.balanceOf(victim), 1_000_000 ether, "Victim recovers full amount");
    }

    /// @notice Test front-running with donation
    function test_Attack_FrontRunWithDonation() public {
        // Attacker front-runs
        vm.prank(attacker);
        vault.stake(1);

        // Attacker immediately donates to try to dilute
        vm.prank(attacker);
        appToken.transfer(address(vault), 100_000 ether);

        // Victim deposits
        uint256 victimDeposit = 50_000 ether;
        vm.prank(victim);
        vault.stake(victimDeposit);

        // Victim still gets 1:1 shares
        assertEq(vault.balanceOf(victim), victimDeposit, "Shares should be 1:1");

        // Victim can withdraw full amount
        vm.prank(victim);
        vault.unstake(victimDeposit);
        assertEq(appToken.balanceOf(victim), 1_000_000 ether, "Full recovery");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DUST DEPOSIT GRIEFING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test many 1 wei deposits don't break accounting
    function test_Attack_DustDepositGriefing() public {
        uint256 numDeposits = 100;

        // Make many 1 wei deposits
        for (uint256 i = 0; i < numDeposits; i++) {
            vm.prank(attacker);
            vault.stake(1);
        }

        assertEq(vault.balanceOf(attacker), numDeposits, "Should have numDeposits shares");
        assertEq(vault.totalSupply(), numDeposits, "Total supply should match");

        // Legitimate user deposits
        uint256 userDeposit = 1000 ether;
        vm.prank(user1);
        vault.stake(userDeposit);

        assertEq(vault.balanceOf(user1), userDeposit, "User should have correct shares");

        // User can withdraw fully
        vm.prank(user1);
        vault.unstake(userDeposit);
        assertEq(appToken.balanceOf(user1), 1_000_000 ether, "User recovers deposit");
    }

    /// @notice Test dust amounts from fixtures
    function test_Attack_DustAmountsFromFixtures() public {
        for (uint256 i = 0; i < fixtureDustAmount.length; i++) {
            uint256 amount = fixtureDustAmount[i];

            if (amount > appToken.balanceOf(attacker)) continue;

            uint256 sharesBefore = vault.balanceOf(attacker);

            vm.prank(attacker);
            vault.stake(amount);

            uint256 sharesAfter = vault.balanceOf(attacker);
            assertEq(sharesAfter - sharesBefore, amount, "Shares should be 1:1 for dust");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SHARE NON-TRANSFERABILITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify shares cannot be transferred
    function test_Security_SharesNonTransferable() public {
        // User1 stakes
        vm.prank(user1);
        vault.stake(1000 ether);

        // Try to transfer shares (should revert)
        vm.prank(user1);
        vm.expectRevert(); // Shares are soulbound
        vault.transfer(user2, 500 ether);
    }

    /// @notice Verify transferFrom also blocked
    function test_Security_SharesNoTransferFrom() public {
        vm.prank(user1);
        vault.stake(1000 ether);

        // Approve attacker
        vm.prank(user1);
        vault.approve(attacker, 1000 ether);

        // Try transferFrom (should revert)
        vm.prank(attacker);
        vm.expectRevert();
        vault.transferFrom(user1, attacker, 500 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKE/UNSTAKE PRECISION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test stake/unstake preserves exact amounts
    function testFuzz_Precision_StakeUnstakeExact(uint256 amount) public {
        amount = bound(amount, 1, 100_000 ether);

        uint256 balanceBefore = appToken.balanceOf(user1);

        vm.startPrank(user1);
        vault.stake(amount);
        assertEq(vault.balanceOf(user1), amount, "Shares should equal deposit");

        vault.unstake(amount);
        vm.stopPrank();

        uint256 balanceAfter = appToken.balanceOf(user1);
        assertEq(balanceAfter, balanceBefore, "Should recover exact amount");
    }

    /// @notice Test multiple stake/unstake cycles
    function test_Precision_MultipleCycles() public {
        uint256 cycles = 50;
        uint256 amount = 100 ether;

        uint256 initialBalance = appToken.balanceOf(user1);

        for (uint256 i = 0; i < cycles; i++) {
            vm.prank(user1);
            vault.stake(amount);

            vm.prank(user1);
            vault.unstake(amount);
        }

        assertEq(appToken.balanceOf(user1), initialBalance, "No value loss after cycles");
        assertEq(vault.balanceOf(user1), 0, "No shares remaining");
    }

    /// @notice Test partial unstakes
    function test_Precision_PartialUnstakes() public {
        uint256 totalStake = 1000 ether;

        vm.prank(user1);
        vault.stake(totalStake);

        // Unstake in parts
        vm.prank(user1);
        vault.unstake(300 ether);
        assertEq(vault.balanceOf(user1), 700 ether, "700 shares remaining");

        vm.prank(user1);
        vault.unstake(200 ether);
        assertEq(vault.balanceOf(user1), 500 ether, "500 shares remaining");

        vm.prank(user1);
        vault.unstake(500 ether);
        assertEq(vault.balanceOf(user1), 0, "No shares remaining");

        assertEq(appToken.balanceOf(user1), 1_000_000 ether, "Full recovery");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DONATION RECOVERY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify donated tokens can't be claimed by stakers
    function test_Security_DonationsNotClaimable() public {
        // User stakes
        vm.prank(user1);
        vault.stake(1000 ether);

        // Someone donates
        vm.prank(attacker);
        appToken.transfer(address(vault), 500 ether);

        // Vault balance is now 1500 ether
        assertEq(appToken.balanceOf(address(vault)), 1500 ether, "Vault has stake + donation");

        // User can only withdraw their stake
        vm.prank(user1);
        vault.unstake(1000 ether);

        assertEq(appToken.balanceOf(user1), 1_000_000 ether, "User gets only their stake");
        assertEq(appToken.balanceOf(address(vault)), 500 ether, "Donation remains");
    }

    /// @notice Test no one can extract donated tokens
    function test_Security_DonationsStuckForever() public {
        // Pure donation (no stakers)
        vm.prank(attacker);
        appToken.transfer(address(vault), 1000 ether);

        assertEq(vault.totalSupply(), 0, "No shares exist");
        assertEq(appToken.balanceOf(address(vault)), 1000 ether, "Tokens in vault");

        // New user stakes
        vm.prank(user1);
        vault.stake(500 ether);

        // User can only get their own tokens back
        vm.prank(user1);
        vault.unstake(500 ether);

        assertEq(appToken.balanceOf(user1), 1_000_000 ether, "Only own tokens");
        assertEq(appToken.balanceOf(address(vault)), 1000 ether, "Donation still stuck");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ZERO AMOUNT EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test zero stake reverts
    function test_Edge_ZeroStakeReverts() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.stake(0);
    }

    /// @notice Test zero unstake reverts
    function test_Edge_ZeroUnstakeReverts() public {
        vm.prank(user1);
        vault.stake(1000 ether);

        vm.prank(user1);
        vm.expectRevert();
        vault.unstake(0);
    }

    /// @notice Test unstaking more than balance reverts
    function test_Edge_UnstakeMoreThanBalance() public {
        vm.prank(user1);
        vault.stake(1000 ether);

        vm.prank(user1);
        vm.expectRevert();
        vault.unstake(1001 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VOTING POWER TESTS (ERC20Votes)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test staking grants voting power
    function test_Voting_StakeGrantsVotingPower() public {
        uint256 stakeAmount = 1000 ether;

        // Before staking
        assertEq(vault.getVotes(user1), 0, "No votes before stake");

        // Stake
        vm.prank(user1);
        vault.stake(stakeAmount);

        // After staking (auto-delegated to self)
        assertEq(vault.getVotes(user1), stakeAmount, "Votes equal stake");
    }

    /// @notice Test voting power is not diluted by donations
    function test_Voting_DonationDoesNotDilute() public {
        vm.prank(user1);
        vault.stake(1000 ether);

        uint256 votesBefore = vault.getVotes(user1);

        // Attacker donates
        vm.prank(attacker);
        appToken.transfer(address(vault), 5000 ether);

        uint256 votesAfter = vault.getVotes(user1);
        assertEq(votesAfter, votesBefore, "Votes unchanged by donation");
    }
}
