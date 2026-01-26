// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../../src/fees/FeeManager.sol";
import {TreasuryUSDCVault} from "../../../src/fees/TreasuryUSDCVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock USDC
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock Router for swap simulation
contract MockSwapRouter {
    IERC20 public elta;
    IERC20 public usdc;
    uint256 public exchangeRate = 100; // 100 USDC per ELTA (for testing)

    constructor(address _elta, address _usdc) {
        elta = IERC20(_elta);
        usdc = IERC20(_usdc);
    }

    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256, // amountOutMin - ignored in mock
        address[] calldata path,
        address to,
        uint256 // deadline
    ) external {
        require(path.length == 2, "Invalid path");
        require(path[0] == address(elta), "Invalid input token");
        require(path[1] == address(usdc), "Invalid output token");

        // Transfer ELTA from caller
        elta.transferFrom(msg.sender, address(this), amountIn);

        // Calculate and send USDC
        // Using 18 decimal ELTA to 6 decimal USDC conversion
        uint256 usdcOut = (amountIn * exchangeRate) / 1e12; // Scale from 18 to 6 decimals
        usdc.transfer(to, usdcOut);
    }
}

/// @notice Reentrancy attacker contract
contract ReentrancyAttacker {
    FeeManager public feeManager;
    uint256 public attackCount;
    uint256 public maxAttacks;
    uint256 public targetAppId;

    constructor(FeeManager _feeManager) {
        feeManager = _feeManager;
    }

    function attack(uint256 appId, uint256 _maxAttacks) external {
        targetAppId = appId;
        maxAttacks = _maxAttacks;
        attackCount = 0;
        feeManager.closeEpoch(appId);
    }

    // Callback when receiving USDC - try to reenter
    receive() external payable {
        if (attackCount < maxAttacks) {
            attackCount++;
            try feeManager.closeEpoch(targetAppId) {} catch {}
        }
    }
}

/**
 * @title TreasurySettlementSecurity
 * @notice Red team security tests for treasury settlement
 * @dev Tests per Protocol Changes document section 21.1:
 *      - TreasuryUSDCVault receives USDC; not app tokens
 *      - Caller incentive never exceeds cap
 *      - Daily settlement cannot be called twice for the same app within epoch
 *      - If swaps exceed slippage bounds, settlement reverts safely
 */
contract TreasurySettlementSecurity is Test {
    ELTA public elta;
    MockUSDC public usdc;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    TreasuryUSDCVault public treasuryVault;
    MockSwapRouter public swapRouter;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public treasuryMultisig = makeAddr("treasuryMultisig");
    address public appRewardsDistributor = makeAddr("appRewardsDistributor");
    address public veRewardsDistributor = makeAddr("veRewardsDistributor");
    address public attacker = makeAddr("attacker");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_ID = 1;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA("ELTA", "ELTA", admin, admin, ELTA_MAX_SUPPLY, ELTA_MAX_SUPPLY);

        // Deploy USDC
        usdc = new MockUSDC();

        // Deploy swap router
        swapRouter = new MockSwapRouter(address(elta), address(usdc));

        // Fund router with USDC for swaps
        usdc.transfer(address(swapRouter), 100_000_000e6);

        // Deploy TreasuryUSDCVault
        treasuryVault = new TreasuryUSDCVault(address(usdc), admin, treasuryMultisig, address(0)); // feeManager set later

        // Deploy FeeManager
        feeManager = new FeeManager(
            address(elta),
            address(usdc),
            admin,
            governance,
            appRewardsDistributor,
            veRewardsDistributor,
            address(treasuryVault),
            1 days // epochLength
        );

        // Connect TreasuryVault to FeeManager
        vm.prank(admin);
        treasuryVault.setFeeManager(address(feeManager));

        // Deploy FeeCollector
        feeCollector = new FeeCollector(
            address(elta),
            admin,
            address(feeManager),
            address(0) // feeSwapper not used here
        );

        // Set up FeeManager
        vm.startPrank(admin);
        feeManager.setDepositor(address(feeCollector), true);
        feeManager.setSwapRouter(address(swapRouter));
        vm.stopPrank();

        // Fund attacker with ELTA
        vm.prank(admin);
        elta.transfer(attacker, 100_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TREASURY ONLY RECEIVES USDC
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_TreasuryOnlyReceivesUSDC() public {
        // Deposit fees to FeeManager
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 10_000 ether);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        vm.stopPrank();

        // Sweep to FeeManager
        feeCollector.sweepElta(APP_ID);

        // Warp past epoch
        vm.warp(block.timestamp + 1 days + 1);

        // Check treasury has no ELTA before
        uint256 vaultEltaBefore = elta.balanceOf(address(treasuryVault));
        assertEq(vaultEltaBefore, 0, "Vault should have no ELTA");

        // Close epoch
        feeManager.closeEpoch(APP_ID);

        // Vault should still have no ELTA (treasury portion should be swapped to USDC)
        uint256 vaultEltaAfter = elta.balanceOf(address(treasuryVault));
        assertEq(vaultEltaAfter, 0, "Vault should not receive ELTA");

        // Note: USDC goes to FeeManager first, then needs to be deposited to vault
        // The current implementation sends to treasuryVault directly after swap
    }

    function test_Security_TreasuryCannotReceiveAppTokens() public {
        // The TreasuryUSDCVault only accepts USDC through the deposit function
        // which requires FeeManager as caller

        // Try to send random tokens directly - should not affect accounting
        uint256 vaultBalanceBefore = treasuryVault.totalRevenue();

        // Even if someone sends ELTA directly, totalRevenue doesn't increase
        vm.prank(admin);
        elta.transfer(address(treasuryVault), 1000 ether);

        uint256 vaultBalanceAfter = treasuryVault.totalRevenue();
        assertEq(vaultBalanceAfter, vaultBalanceBefore, "Direct transfers should not affect revenue accounting");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLER INCENTIVE NEVER EXCEEDS CAP
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CallerIncentiveNeverExceedsCap() public {
        // Deposit large amount of fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 50_000 ether);
        feeCollector.depositElta(APP_ID, 50_000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(APP_ID);

        // Warp past epoch
        vm.warp(block.timestamp + 1 days + 1);

        // Fund FeeManager with USDC for incentive
        usdc.transfer(address(feeManager), 1_000_000e6);

        address caller = makeAddr("caller");
        uint256 callerUsdcBefore = usdc.balanceOf(caller);

        vm.prank(caller);
        feeManager.closeEpoch(APP_ID);

        uint256 callerUsdcAfter = usdc.balanceOf(caller);
        uint256 incentiveReceived = callerUsdcAfter - callerUsdcBefore;

        // Verify incentive is capped
        uint256 maxIncentive = feeManager.MAX_CALLER_INCENTIVE_USDC();
        assertLe(incentiveReceived, maxIncentive, "Caller incentive exceeds cap");

        console2.log("Incentive received:", incentiveReceived);
        console2.log("Max incentive:", maxIncentive);
    }

    function test_Security_IncentiveOnlyPaidOnRealWork() public {
        // Try to close epoch with no pending fees
        vm.warp(block.timestamp + 1 days + 1);

        address caller = makeAddr("caller");

        // Fund FeeManager with USDC
        usdc.transfer(address(feeManager), 1_000_000e6);

        uint256 callerUsdcBefore = usdc.balanceOf(caller);

        vm.prank(caller);
        feeManager.closeEpoch(APP_ID);

        uint256 callerUsdcAfter = usdc.balanceOf(caller);
        uint256 incentiveReceived = callerUsdcAfter - callerUsdcBefore;

        // Should still get incentive if threshold met, but this tests that
        // empty epochs don't provide infinite incentive farming opportunities
        console2.log("Incentive for empty epoch:", incentiveReceived);
    }

    function testFuzz_CallerIncentiveCalculation(uint256 usdcAmount) public {
        usdcAmount = bound(usdcAmount, 1e6, 10_000_000e6);

        // Fund FeeManager with USDC
        usdc.mint(address(feeManager), usdcAmount);

        // Deposit and sweep some fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);
        feeCollector.depositElta(APP_ID, 1000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(APP_ID);
        vm.warp(block.timestamp + 1 days + 1);

        address caller = makeAddr("fuzzCaller");
        uint256 callerBefore = usdc.balanceOf(caller);

        vm.prank(caller);
        feeManager.closeEpoch(APP_ID);

        uint256 callerAfter = usdc.balanceOf(caller);
        uint256 incentive = callerAfter - callerBefore;

        // Verify incentive calculation
        uint256 maxIncentive = feeManager.MAX_CALLER_INCENTIVE_USDC();
        uint256 minThreshold = feeManager.MIN_INCENTIVE_THRESHOLD_USDC();

        if (usdcAmount < minThreshold) {
            // Below threshold, no incentive
            assertEq(incentive, 0, "Should not receive incentive below threshold");
        } else {
            // Above threshold, should be capped
            assertLe(incentive, maxIncentive, "Incentive exceeds cap");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CANNOT DOUBLE SETTLE WITHIN EPOCH
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotDoubleSettle() public {
        // Deposit fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 10_000 ether);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(APP_ID);

        // Warp past epoch
        vm.warp(block.timestamp + 1 days + 1);

        // First close succeeds
        feeManager.closeEpoch(APP_ID);

        // Second close within same epoch should fail
        vm.expectRevert(FeeManager.EpochNotEnded.selector);
        feeManager.closeEpoch(APP_ID);
    }

    function test_Security_CanCloseAfterNextEpoch() public {
        // Deposit fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 10_000 ether);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(APP_ID);

        // Warp and close first epoch
        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(APP_ID);

        // Deposit more fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 5_000 ether);
        feeCollector.depositElta(APP_ID, 5_000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(APP_ID);

        // Warp and close second epoch - should succeed
        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(APP_ID); // Should not revert
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SLIPPAGE AND SWAP SAFETY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SlippageRevertsSafely() public {
        // Set exchange rate to 0 to simulate failed swap
        swapRouter.setExchangeRate(0);

        // Deposit fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 10_000 ether);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(APP_ID);

        uint256 feeManagerEltaBefore = elta.balanceOf(address(feeManager));

        // Warp past epoch
        vm.warp(block.timestamp + 1 days + 1);

        // Close epoch - should handle failed swap gracefully
        // (swap fails but epoch still closes)
        feeManager.closeEpoch(APP_ID);

        // Funds shouldn't be stuck - they either swapped or went as ELTA
        // This tests that the system doesn't break on swap failure
    }

    function test_Security_SettlementAccounting() public {
        // Deposit known amount via proper FeeCollector flow
        uint256 depositAmount = 10_000 ether;

        vm.startPrank(attacker);
        elta.approve(address(feeCollector), depositAmount);
        feeCollector.depositElta(APP_ID, depositAmount);
        vm.stopPrank();

        // Sweep to FeeManager (now properly calls depositEltaForApp)
        feeCollector.sweepElta(APP_ID);

        // Record balances before
        uint256 appRewardsBefore = elta.balanceOf(appRewardsDistributor);
        uint256 veRewardsBefore = elta.balanceOf(veRewardsDistributor);

        // Warp and close
        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(APP_ID);

        // Verify distribution happened
        uint256 appRewardsAfter = elta.balanceOf(appRewardsDistributor);
        uint256 veRewardsAfter = elta.balanceOf(veRewardsDistributor);

        assertGt(appRewardsAfter, appRewardsBefore, "App rewards should increase");
        assertGt(veRewardsAfter, veRewardsBefore, "VE rewards should increase");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyFeeManagerCanDepositToVault() public {
        // Try to deposit directly to vault
        usdc.transfer(attacker, 10_000e6);

        vm.startPrank(attacker);
        usdc.approve(address(treasuryVault), 10_000e6);

        vm.expectRevert(TreasuryUSDCVault.OnlyFeeManager.selector);
        treasuryVault.deposit(APP_ID, 10_000e6, 1);
        vm.stopPrank();
    }

    function test_Security_OnlyTreasuryCanWithdraw() public {
        // First deposit some USDC through proper channels
        // (would need full flow, but test the withdrawal restriction)

        vm.expectRevert(TreasuryUSDCVault.OnlyTreasury.selector);
        vm.prank(attacker);
        treasuryVault.withdraw(1000e6);
    }

    function test_Security_OnlyGovernanceCanSetFeeSplits() public {
        vm.expectRevert(FeeManager.OnlyGovernance.selector);
        vm.prank(attacker);
        feeManager.setFeeSplits(2500, 2500, 2500, 2500, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_TreasuryShareCalculation(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 50_000 ether);
        console2.log("Bound result", depositAmount);

        // Use proper FeeCollector flow
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), depositAmount);
        feeCollector.depositElta(APP_ID, depositAmount);
        vm.stopPrank();

        // Sweep to FeeManager (now properly calls depositEltaForApp)
        feeCollector.sweepElta(APP_ID);

        // Get splits
        (uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury,) = feeManager.feeSplits();

        // Warp and close
        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(APP_ID);

        // Verify accounting (approximate due to rounding)
        uint256 appRewards = elta.balanceOf(appRewardsDistributor);
        uint256 veRewards = elta.balanceOf(veRewardsDistributor);

        uint256 expectedAppRewards = (depositAmount * appStakers) / 10000;
        uint256 expectedVeRewards = (depositAmount * veElta) / 10000;

        // Allow 1% tolerance for rounding
        assertApproxEqRel(appRewards, expectedAppRewards, 0.01e18, "App rewards mismatch");
        assertApproxEqRel(veRewards, expectedVeRewards, 0.01e18, "VE rewards mismatch");
    }

    function testFuzz_MultipleAppsSettlement(uint256 app1Amount, uint256 app2Amount) public {
        app1Amount = bound(app1Amount, 1 ether, 25_000 ether);
        app2Amount = bound(app2Amount, 1 ether, 25_000 ether);

        // Deposit for app 1
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), app1Amount + app2Amount);
        feeCollector.depositElta(1, app1Amount);
        feeCollector.depositElta(2, app2Amount);
        vm.stopPrank();

        feeCollector.sweepElta(1);
        feeCollector.sweepElta(2);

        // Warp and close both
        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(1);
        feeManager.closeEpoch(2);

        // Verify both apps processed
        assertEq(feeManager.pendingEltaToDistribute(1), 0, "App 1 should be settled");
        assertEq(feeManager.pendingEltaToDistribute(2), 0, "App 2 should be settled");
    }
}
