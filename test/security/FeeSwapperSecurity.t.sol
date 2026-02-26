// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockELTA is ERC20 {
    constructor() ERC20("Mock ELTA", "ELTA") {
        _mint(msg.sender, 77_000_000 ether);
    }
}

contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App Token", "MAPP") {
        _mint(msg.sender, 10_000_000 ether);
    }
}

contract MockUniswapV2Router {
    MockELTA public elta;
    uint256 public exchangeRate = 10; // 1 app token = 10 ELTA

    constructor(address _elta) {
        elta = MockELTA(_elta);
    }

    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = amountIn * exchangeRate;
        require(amountOut >= amountOutMin, "Insufficient output");
        elta.transfer(to, amountOut);
    }
}

contract FeeSwapperSecurity is Test {
    FeeSwapper swapper;
    MockELTA elta;
    MockAppToken appToken;
    MockUniswapV2Router router;
    AppRegistry registry;

    address admin = makeAddr("admin");
    address governance = makeAddr("governance");
    address treasury = makeAddr("treasury");
    address attacker = makeAddr("attacker");
    address caller = makeAddr("caller");

    function setUp() public {
        elta = new MockELTA();
        appToken = new MockAppToken();
        router = new MockUniswapV2Router(address(elta));
        registry = new AppRegistry(governance, address(this));

        // Give router ELTA for swaps
        elta.transfer(address(router), 10_000_000 ether);

        swapper = new FeeSwapper(address(elta), admin, governance, treasury, address(registry));

        vm.prank(governance);
        swapper.setRouterAllowed(address(router), true);

        appToken.transfer(caller, 100_000 ether);
    }

    function test_Security_OnlyAllowlistedRoutersAccepted() public {
        address badRouter = makeAddr("badRouter");
        uint256 amountIn = 1000 ether;

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);
        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        swapper.swap(0, FeeKind.TRANSFER_TAX, address(appToken), amountIn, 0, badRouter, path);
        vm.stopPrank();
    }

    function test_Security_SandwichAttackMitigatedByMinOut() public {
        uint256 amountIn = 1000 ether;
        uint256 expectedOut = amountIn * router.exchangeRate();
        uint256 minOut = (expectedOut * 95) / 100;

        // Sandwich simulation: rate worsens before swap executes
        router.setExchangeRate(5);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);
        vm.expectRevert(); // router enforces amountOutMin
        swapper.swap(0, FeeKind.TRANSFER_TAX, address(appToken), amountIn, minOut, address(router), path);
        vm.stopPrank();
    }

    function test_Security_PathMustEndInElta() public {
        uint256 amountIn = 1000 ether;

        address[] memory badPath = new address[](2);
        badPath[0] = address(appToken);
        badPath[1] = address(appToken);

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector));
        swapper.swap(0, FeeKind.TRANSFER_TAX, address(appToken), amountIn, 0, address(router), badPath);
        vm.stopPrank();
    }

    function test_Security_MinSwapThresholdPreventsDustAttacks() public {
        vm.prank(governance);
        swapper.setMinSwapThreshold(10 ether);

        // Dust amount into swapper, then attempt swapFromBalance
        appToken.transfer(address(swapper), 1 ether);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.expectRevert(FeeSwapper.BelowMinSwapThreshold.selector);
        swapper.swapFromBalance(0, FeeKind.TRANSFER_TAX, address(appToken), 1 ether, 0, address(router), path);
    }

    function test_Security_OnlyGovernanceCanSetRouter() public {
        vm.prank(attacker);
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        swapper.setRouterAllowed(makeAddr("router2"), true);
    }
}

