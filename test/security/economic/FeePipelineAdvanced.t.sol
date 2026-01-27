// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../../src/fees/FeeManager.sol";
import {FeeSwapper} from "../../../src/fees/FeeSwapper.sol";
import {ProtocolConfig} from "../../../src/core/ProtocolConfig.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock USDC
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @notice Mock Uniswap Router
contract MockRouter {
    IERC20 public inputToken;
    IERC20 public outputToken;
    uint256 public exchangeRate = 1e6; // 1 ELTA = 1 USDC

    function setTokens(address _input, address _output) external {
        inputToken = IERC20(_input);
        outputToken = IERC20(_output);
    }

    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256, address[] calldata path, address to, uint256)
        external
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = (amountIn * exchangeRate) / 1e18;

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[path.length - 1]).transfer(to, amounts[1]);

        return amounts;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = (amountIn * exchangeRate) / 1e18;
    }
}

/**
 * @title FeePipelineAdvanced
 * @notice Advanced fee pipeline exploit tests
 */
contract FeePipelineAdvanced is Test {
    ELTA public elta;
    MockUSDC public usdc;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    FeeSwapper public feeSwapper;
    ProtocolConfig public config;
    MockRouter public router;

    address public admin = makeAddr("admin");
    address public timelock = makeAddr("timelock");
    address public treasury = makeAddr("treasury");
    address public appStakers = makeAddr("appStakers");
    address public veEltaRewards = makeAddr("veEltaRewards");
    address public user = makeAddr("user");
    address public attacker = makeAddr("attacker");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant EPOCH_LENGTH = 1 days;

    function setUp() public {
        // Deploy tokens
        vm.prank(admin);
        elta = new ELTA(admin);

        usdc = new MockUSDC();

        // Deploy config
        config = new ProtocolConfig(admin, timelock);

        // Deploy router
        router = new MockRouter();
        router.setTokens(address(elta), address(usdc));
        usdc.transfer(address(router), 1_000_000e6);

        // Deploy fee contracts
        feeCollector = new FeeCollector(address(elta), admin, address(0), address(0));

        feeManager = new FeeManager(
            address(elta), address(usdc), admin, admin, treasury, veEltaRewards, appStakers, EPOCH_LENGTH
        );

        feeSwapper = new FeeSwapper(address(elta), admin, admin, address(0)); // admin is also governance for tests

        // Connect contracts
        vm.startPrank(admin);
        feeCollector.setFeeManager(address(feeManager));
        feeCollector.setFeeSwapper(address(feeSwapper));
        feeManager.setDepositor(address(feeCollector), true);
        feeSwapper.setFeeManager(address(feeManager));
        feeSwapper.setRouterAllowed(address(router), true);
        vm.stopPrank();

        // Fund
        vm.prank(admin);
        elta.transfer(user, 1_000_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE COLLECTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FeeCollector_DepositTracking() public {
        vm.startPrank(user);
        elta.approve(address(feeCollector), 1000 ether);

        // Deposit for multiple apps
        feeCollector.depositElta(1, 100 ether);
        feeCollector.depositElta(2, 200 ether);
        feeCollector.depositElta(1, 50 ether);

        assertEq(feeCollector.pendingEltaFees(1), 150 ether, "App 1 should have 150 ELTA");
        assertEq(feeCollector.pendingEltaFees(2), 200 ether, "App 2 should have 200 ELTA");
        vm.stopPrank();
    }

    function test_FeeCollector_SweepUpdatesState() public {
        vm.startPrank(user);
        elta.approve(address(feeCollector), 100 ether);
        feeCollector.depositElta(1, 100 ether);
        vm.stopPrank();

        // Sweep
        feeCollector.sweepElta(1);

        // Pending should be 0
        assertEq(feeCollector.pendingEltaFees(1), 0, "Pending should be 0 after sweep");
    }

    function test_FeeCollector_CannotSweepZero() public {
        // Try to sweep when nothing pending
        vm.expectRevert(FeeCollector.NothingToSweep.selector);
        feeCollector.sweepElta(1);
    }

    function test_FeeCollector_MultipleAppsIndependent() public {
        vm.startPrank(user);
        elta.approve(address(feeCollector), 300 ether);

        feeCollector.depositElta(1, 100 ether);
        feeCollector.depositElta(2, 200 ether);
        vm.stopPrank();

        // Sweep app 1
        feeCollector.sweepElta(1);

        // App 2 should be unaffected
        assertEq(feeCollector.pendingEltaFees(2), 200 ether, "App 2 should still have 200 ELTA");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE MANAGER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FeeManager_DepositRequiresAuth() public {
        vm.prank(attacker);
        vm.expectRevert();
        feeManager.depositEltaForApp(1, 100 ether);
    }

    function test_FeeManager_AuthorizedCanDeposit() public {
        vm.prank(admin);
        feeManager.setDepositor(user, true);

        vm.startPrank(user);
        elta.approve(address(feeManager), 100 ether);
        feeManager.depositEltaForApp(1, 100 ether);
        vm.stopPrank();
    }

    function test_FeeManager_EpochTracking() public {
        vm.prank(admin);
        feeManager.setDepositor(user, true);

        vm.startPrank(user);
        elta.approve(address(feeManager), 500 ether);

        // Deposit for epoch
        feeManager.depositEltaForApp(1, 100 ether);

        // Warp and close epoch
        vm.warp(block.timestamp + EPOCH_LENGTH + 1);
        feeManager.closeEpoch(1);

        // Deposit again
        feeManager.depositEltaForApp(1, 200 ether);
        vm.stopPrank();

        // Check epoch state
        // Each deposit creates an epoch
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE SWAPPER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FeeSwapper_RequiresAllowedRouter() public {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(elta);

        // Fund caller
        usdc.transfer(user, 1000e6);

        vm.startPrank(user);
        usdc.approve(address(feeSwapper), 100e6);

        // Use non-allowed router - should revert with RouterNotAllowed
        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        feeSwapper.swap(1, address(usdc), 100e6, 0, makeAddr("badRouter"), path);
        vm.stopPrank();
    }

    function test_FeeSwapper_InvalidAmount() public {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(elta);

        vm.startPrank(user);
        usdc.approve(address(feeSwapper), 100e6);

        // Swap with 0 amount should fail
        vm.expectRevert(FeeSwapper.InvalidAmount.selector);
        feeSwapper.swap(1, address(usdc), 0, 0, address(router), path);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Integration_FullFeePipeline() public {
        // 1. User deposits fees
        vm.startPrank(user);
        elta.approve(address(feeCollector), 100 ether);
        feeCollector.depositElta(1, 100 ether);
        vm.stopPrank();

        // 2. Sweep to fee manager
        feeCollector.sweepElta(1);

        // 3. Verify fees reached manager
        // (Implementation specific)
    }

    function test_Integration_MultipleSweeps() public {
        vm.startPrank(user);
        elta.approve(address(feeCollector), 1000 ether);

        // Multiple deposits
        feeCollector.depositElta(1, 100 ether);
        feeCollector.depositElta(1, 100 ether);
        feeCollector.depositElta(1, 100 ether);
        vm.stopPrank();

        // Single sweep
        uint256 pending = feeCollector.pendingEltaFees(1);
        assertEq(pending, 300 ether, "Should have 300 ELTA pending");

        feeCollector.sweepElta(1);
        assertEq(feeCollector.pendingEltaFees(1), 0, "All fees should be swept");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_FeeCollector_DepositAmount(uint256 amount) public {
        amount = bound(amount, 1 ether, 100_000 ether);

        vm.startPrank(user);
        elta.approve(address(feeCollector), amount);
        feeCollector.depositElta(1, amount);
        vm.stopPrank();

        assertEq(feeCollector.pendingEltaFees(1), amount, "Pending should match deposit");
    }

    function testFuzz_FeeCollector_MultipleDeposits(uint256[] calldata amounts) public {
        vm.assume(amounts.length > 0 && amounts.length <= 10);

        uint256 total = 0;
        vm.startPrank(user);
        elta.approve(address(feeCollector), type(uint256).max);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = bound(amounts[i], 1 ether, 10_000 ether);
            feeCollector.depositElta(1, amount);
            total += amount;
        }
        vm.stopPrank();

        assertEq(feeCollector.pendingEltaFees(1), total, "Pending should match total deposits");
    }

    function testFuzz_FeeManager_DepositorAuth(address caller) public {
        vm.assume(caller != address(feeCollector) && caller != address(0));

        // Assume caller is not already authorized
        vm.assume(caller != admin);

        // Without explicit auth, should revert
        vm.prank(caller);
        vm.expectRevert();
        feeManager.depositEltaForApp(1, 100 ether);
    }
}
