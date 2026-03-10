// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../../src/contributors/ContributorSplitFactory.sol";
import {IContributorSplit} from "../../src/interfaces/IContributorSplit.sol";
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
}

/// @notice Mock App Token for swap testing
contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App", "MAPP") {
        _mint(msg.sender, 100_000_000 ether);
    }
}

/**
 * @title FeePipelineSecurity
 * @notice Red team security tests for FeeCollector + FeeSwapper
 */
contract FeePipelineSecurity is Test {
    ELTA public elta;
    MockUSDC public usdc;
    MockAppToken public appToken;
    FeeCollector public feeCollector;
    FeeSwapper public feeSwapper;
    AppRegistry public appRegistry;
    ContributorSplitFactory public splitFactory;
    address public split;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy tokens
        vm.prank(admin);
        elta = new ELTA(admin);
        usdc = new MockUSDC();
        appToken = new MockAppToken();

        // Deploy AppRegistry (required by FeeSwapper routing)
        appRegistry = new AppRegistry(governance, address(this));
        // Deploy FeeSwapper (unified router + swap helper)
        feeSwapper = new FeeSwapper(address(elta), admin, governance, treasury, address(appRegistry));

        splitFactory = new ContributorSplitFactory(governance, address(this));

        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](1);
        contributors[0] = IContributorSplit.Contributor({account: attacker, shares: 10_000});
        split = splitFactory.createSplit(0, attacker, address(feeSwapper), contributors);
        appRegistry.registerApp(0, attacker, split, "ipfs://meta");

        // Deploy FeeCollector
        feeCollector = new FeeCollector(address(elta), admin, address(feeSwapper), address(feeSwapper));

        // Fund attacker
        vm.prank(admin);
        elta.transfer(attacker, 100_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE COLLECTOR SECURITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotDepositZeroAmount() public {
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);

        vm.expectRevert(FeeCollector.InvalidAmount.selector);
        feeCollector.depositElta(0, 0);
        vm.stopPrank();
    }

    function test_Security_UnauthorizedSweep() public {
        // Deposit some fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);
        feeCollector.depositElta(0, 1000 ether);
        vm.stopPrank();

        // Sweep is permissionless, but funds route to treasury
        uint256 treasuryBefore = elta.balanceOf(treasury);
        feeCollector.sweepElta(0);
        uint256 treasuryAfter = elta.balanceOf(treasury);

        // Funds should go to treasury, not attacker
        assertGt(treasuryAfter, treasuryBefore, "Funds should go to treasury");
    }

    function test_Security_CannotExtractFundsDirectly() public {
        // Deposit fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);
        feeCollector.depositElta(0, 1000 ether);
        vm.stopPrank();

        // Try to withdraw directly (no such function)
        // FeeCollector has no withdraw function - funds only go via sweep
        uint256 collectorBalance = elta.balanceOf(address(feeCollector));
        assertEq(collectorBalance, 1000 ether, "Funds should be in collector");
    }

    function test_Security_DoubleDepositAccounting() public {
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 2000 ether);

        // Deposit twice
        feeCollector.depositElta(0, 500 ether);
        feeCollector.depositElta(0, 500 ether);

        // Check accounting
        uint256 pending = feeCollector.pendingEltaFees(0, FeeKind.TRADING_FEE);
        assertEq(pending, 1000 ether, "Should track both deposits");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE SWAPPER SECURITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyAdminCanSetTreasury() public {
        vm.expectRevert(FeeSwapper.OnlyAdmin.selector);
        vm.prank(attacker);
        feeSwapper.setTreasury(attacker);
    }

    function test_Security_OnlyGovernanceCanSetRouter() public {
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        vm.prank(attacker);
        feeSwapper.setRouterAllowed(attacker, true);
    }

    function test_Security_CannotSwapWithUnallowedRouter() public {
        // Fund swapper - use the deployer who has tokens
        appToken.transfer(address(feeSwapper), 1000 ether);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Try to swap with unallowed router
        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        feeSwapper.swapFromBalance(0, FeeKind.TRANSFER_TAX, address(appToken), 100 ether, 0, attacker, path);
    }

    function test_Security_SwapperMinThresholdEnforced() public {
        // Set high threshold
        vm.prank(governance);
        feeSwapper.setMinSwapThreshold(100 ether);

        // Fund swapper - deployer has tokens
        appToken.transfer(address(feeSwapper), 1000 ether);

        // Allow a router
        vm.prank(governance);
        feeSwapper.setRouterAllowed(makeAddr("router"), true);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Try to swap below threshold
        vm.expectRevert(FeeSwapper.BelowMinSwapThreshold.selector);
        feeSwapper.swapFromBalance(0, FeeKind.TRANSFER_TAX, address(appToken), 10 ether, 0, makeAddr("router"), path);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_DepositAmount(uint256 amount) public {
        amount = bound(amount, 1 ether, 50_000 ether);

        vm.startPrank(attacker);
        elta.approve(address(feeCollector), amount);
        feeCollector.depositElta(0, amount);
        vm.stopPrank();

        uint256 pending = feeCollector.pendingEltaFees(0, FeeKind.TRADING_FEE);
        assertEq(pending, amount, "Pending should match deposit");
    }

    function testFuzz_Security_MultipleAppDeposits(uint256 appId1, uint256 appId2, uint256 amount1, uint256 amount2)
        public
    {
        appId1 = bound(appId1, 0, 100);
        appId2 = bound(appId2, 0, 100);
        amount1 = bound(amount1, 1 ether, 25_000 ether);
        amount2 = bound(amount2, 1 ether, 25_000 ether);

        vm.startPrank(attacker);
        elta.approve(address(feeCollector), amount1 + amount2);

        feeCollector.depositElta(appId1, amount1);
        feeCollector.depositElta(appId2, amount2);
        vm.stopPrank();

        // Verify per-app accounting
        if (appId1 == appId2) {
            assertEq(
                feeCollector.pendingEltaFees(appId1, FeeKind.TRADING_FEE), amount1 + amount2, "Same app should sum"
            );
        } else {
            assertEq(feeCollector.pendingEltaFees(appId1, FeeKind.TRADING_FEE), amount1, "App 1 amount correct");
            assertEq(feeCollector.pendingEltaFees(appId2, FeeKind.TRADING_FEE), amount2, "App 2 amount correct");
        }
    }
}
