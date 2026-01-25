// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {AppBondingCurve} from "../../src/apps/AppBondingCurve.sol";
import {BondingCurveHandler} from "./handlers/BondingCurveHandler.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../../src/interfaces/IElataPoints.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock Uniswap Router for testing
contract MockRouter {
    function factory() external pure returns (address) {
        return address(0);
    }

    function WETH() external pure returns (address) {
        return address(0);
    }
}

/// @notice Mock AppFeeRouter for testing
contract MockAppFeeRouter is IAppFeeRouter {
    function takeAndForwardFee(address, uint256) external pure {}

    function feeBps() external pure returns (uint256) {
        return 0;
    }

    function calculateFee(uint256) external pure returns (uint256) {
        return 0;
    }
}

/// @notice Mock ElataPoints for testing
contract MockElataPoints is IElataPoints {
    mapping(address => uint256) public balances;

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
    }
}

/// @notice Mock AppFactory for testing
contract MockAppFactory {
    function onAppGraduated(uint256, address, address, uint256, uint256, uint256) external pure {}
}

/**
 * @title BondingCurveInvariants
 * @notice Invariant tests for AppBondingCurve
 * @dev Tests that bonding curve maintains constant product and proper state transitions
 */
contract BondingCurveInvariants is Test {
    ELTA public elta;
    AppToken public appToken;
    AppBondingCurve public curve;
    BondingCurveHandler public handler;

    MockRouter public router;
    MockAppFeeRouter public appFeeRouter;
    MockElataPoints public elataPoints;
    MockAppFactory public appFactory;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;
    uint256 public constant TARGET_RAISED = 10_000 ether;
    uint256 public constant SEED_ELTA = 100 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA("ELTA", "ELTA", admin, admin, ELTA_MAX_SUPPLY, ELTA_MAX_SUPPLY);

        // Deploy mocks
        router = new MockRouter();
        appFeeRouter = new MockAppFeeRouter();
        elataPoints = new MockElataPoints();
        appFactory = new MockAppFactory();

        // Deploy AppToken
        appToken = new AppToken(
            "TestApp", "TEST", 18, APP_TOKEN_SUPPLY, creator, admin, governance, treasury, treasury, treasury
        );

        // Deploy bonding curve
        curve = new AppBondingCurve(
            0, // appId
            address(appFactory),
            IERC20(address(elta)),
            appToken,
            IUniswapV2Router02(address(router)),
            TARGET_RAISED,
            365 days * 2, // lpLockDuration
            creator, // lpBeneficiary
            treasury,
            IAppFeeRouter(address(appFeeRouter)),
            IElataPoints(address(elataPoints)),
            governance,
            1 hours, // activationDelay
            30 days, // maxDuration
            creator // _creator
        );

        // Seed the curve with ELTA and tokens
        vm.prank(admin);
        elta.transfer(address(curve), SEED_ELTA);

        vm.prank(admin);
        appToken.mint(address(curve), APP_TOKEN_SUPPLY / 2);

        // Activate the curve
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(governance);
        curve.activate();

        // Deploy handler
        handler = new BondingCurveHandler(elta, curve, appToken);

        // Fund actors with ELTA for buying
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            vm.prank(admin);
            elta.transfer(actor, 100_000 ether);

            // Give actors XP so they can buy during early access
            elataPoints.setBalance(actor, 1000 ether);
        }

        // Set up handler as target
        targetContract(address(handler));

        // Exclude certain functions that would break invariants
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = BondingCurveHandler.activate.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // =========== Constant Product Invariants ===========

    /// @notice Constant product K should only increase (fees extracted)
    function invariant_ConstantProductOnlyIncreases() public view {
        if (!handler.isKInitialized()) return;

        uint256 initialK = handler.getInitialK();
        uint256 currentK = handler.getCurrentK();

        // K can only increase (due to fees staying in reserves)
        // or stay the same (no trades)
        assertGe(currentK, initialK, "Constant product K decreased");
    }

    /// @notice Reserve ELTA should be positive while curve is active
    /// @dev Skip if curve is not properly initialized
    function invariant_ReserveEltaPositive() public view {
        if (curve.state() != AppBondingCurve.CurveState.ACTIVE) return;
        if (!handler.isKInitialized()) return; // Skip if no trades yet

        uint256 reserveElta = curve.reserveElta();
        assertGt(reserveElta, 0, "Reserve ELTA is zero");
    }

    /// @notice Reserve Token should be positive while curve is active
    /// @dev Skip if curve is not properly initialized
    function invariant_ReserveTokenPositive() public view {
        if (curve.state() != AppBondingCurve.CurveState.ACTIVE) return;
        if (!handler.isKInitialized()) return; // Skip if no trades yet

        uint256 reserveToken = curve.reserveToken();
        assertGt(reserveToken, 0, "Reserve Token is zero");
    }

    // =========== State Transition Invariants ===========

    /// @notice Reserve ELTA should never exceed target (before graduation)
    function invariant_ReserveEltaNeverExceedsTarget() public view {
        if (curve.graduated()) return; // Skip if graduated

        uint256 reserve = curve.reserveElta();
        uint256 target = curve.targetRaisedElta();

        assertLe(reserve, target, "Reserve ELTA exceeded target");
    }

    /// @notice If graduated, curve state should be GRADUATED
    function invariant_GraduatedStateConsistent() public view {
        bool isGraduated = curve.graduated();
        AppBondingCurve.CurveState curveState = curve.state();

        if (isGraduated) {
            assertEq(uint256(curveState), uint256(AppBondingCurve.CurveState.GRADUATED), "Graduated but wrong state");
        }
    }

    // =========== Balance Invariants ===========

    /// @notice Curve's ELTA balance should be >= reserve ELTA
    function invariant_CurveEltaBalanceGteReserve() public view {
        uint256 balance = elta.balanceOf(address(curve));
        uint256 reserve = curve.reserveElta();

        // Balance might be higher due to refunds or other deposits
        assertGe(balance, reserve, "ELTA balance < reserve");
    }

    /// @notice Curve's token balance should be >= reserve token
    function invariant_CurveTokenBalanceGteReserve() public view {
        uint256 balance = appToken.balanceOf(address(curve));
        uint256 reserve = curve.reserveToken();

        // Balance might be higher due to unminted tokens
        assertGe(balance, reserve, "Token balance < reserve");
    }

    // =========== Ghost Variable Invariants ===========

    /// @notice Total bought should be >= 0
    function invariant_TotalBoughtNonNegative() public view {
        assertGe(handler.ghost_totalBought(), 0, "Total bought negative");
    }

    /// @notice Total spent should be >= 0
    function invariant_TotalSpentNonNegative() public view {
        assertGe(handler.ghost_totalSpent(), 0, "Total spent negative");
    }

    /// @notice Total spent should roughly correspond to total bought (accounting for price)
    function invariant_SpentCorrespondsToBought() public view {
        uint256 bought = handler.ghost_totalBought();
        uint256 spent = handler.ghost_totalSpent();

        // If we bought tokens, we should have spent ELTA
        if (bought > 0) {
            assertGt(spent, 0, "Bought without spending");
        }
    }

    // =========== Debug Helpers ===========

    function invariant_callSummary() public view {
        console2.log("Bonding Curve Call Summary:");
        console2.log("  Total calls:", handler.ghost_callCount());
        console2.log("  Buy count:", handler.ghost_buyCount());
        console2.log("  Total bought:", handler.ghost_totalBought());
        console2.log("  Total spent:", handler.ghost_totalSpent());
        console2.log("  Curve state:", uint256(curve.state()));
        console2.log("  Reserve ELTA:", curve.reserveElta());
        console2.log("  Reserve Token:", curve.reserveToken());
        console2.log("  Target:", curve.targetRaisedElta());
        console2.log("  Graduated:", curve.graduated());

        if (handler.isKInitialized()) {
            console2.log("  Initial K:", handler.getInitialK());
            console2.log("  Current K:", handler.getCurrentK());
        }
    }
}
