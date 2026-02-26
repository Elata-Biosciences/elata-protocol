// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {AppFeeRouter} from "../../src/fees/AppFeeRouter.sol";

import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {ContributorSplit} from "../../src/contributors/ContributorSplit.sol";
import {IContributorSplit} from "../../src/interfaces/IContributorSplit.sol";

import {AppBondingCurve} from "../../src/apps/AppBondingCurve.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {ContentStore, PaymentTokenType} from "../../src/apps/ContentStore.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../../src/interfaces/IElataPoints.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";

contract MockERC20 is ERC20 {
    uint8 internal immutable _decimals;

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 18) {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract MockPoints {
    mapping(address => uint256) public balanceOf;

    function setBalance(address a, uint256 v) external {
        balanceOf[a] = v;
    }
}

contract MockRouterFactoryOnly {
    address public immutable factory;

    constructor(address f) {
        factory = f;
    }
}

contract MockContent721 {
    uint256 public nextId;

    function mint(address, string memory) external returns (uint256 tokenId) {
        tokenId = nextId++;
    }
}

contract RevertingSplit {
    function onFeeReceived(FeeKind, address, uint256, address) external pure {
        revert("onFeeReceived should not be called");
    }
}

contract FeeSplit80_20Test is Test {
    uint256 internal constant APP_ID = 1;

    address internal admin = makeAddr("admin");
    address internal governance = makeAddr("governance");
    address internal treasury = makeAddr("treasury");
    address internal ownerSafe = makeAddr("ownerSafe");
    address internal contributor = makeAddr("contributor");
    address internal buyer = makeAddr("buyer");
    address internal lp = makeAddr("lp");

    MockERC20 internal elta;
    MockERC20 internal usdc;
    MockWETH internal weth;

    AppRegistry internal registry;
    ContributorSplit internal split;
    FeeSwapper internal swapper;
    FeeCollector internal collector;

    function setUp() public {
        elta = new MockERC20("Elata", "ELTA", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockWETH();

        // Registry is constructed with appFactory = this test contract.
        registry = new AppRegistry(governance, address(this));

        swapper = new FeeSwapper(address(elta), admin, governance, treasury, address(registry));
        collector = new FeeCollector(address(elta), admin, address(swapper), address(swapper));

        // Real ContributorSplit so we can validate pull-based releases.
        split = new ContributorSplit();
        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](1);
        contributors[0] = IContributorSplit.Contributor({account: contributor, shares: 10_000});
        split.initialize(APP_ID, ownerSafe, address(swapper), 200, contributors);

        registry.registerApp(APP_ID, ownerSafe, address(split), "ipfs://meta");

        // Fund buyer with assets.
        elta.mint(buyer, 1_000_000 ether);
        usdc.mint(buyer, 1_000_000e6);
        vm.deal(buyer, 100 ether);
    }

    function test_TradingFee_SweepsAndRoutes80_20() public {
        // Minimal router mock: constructor only needs router.factory().
        address mockFactory = makeAddr("uniFactory");
        MockRouterFactoryOnly router = new MockRouterFactoryOnly(mockFactory);

        // FeeBps source of truth (no yield distribution).
        AppFeeRouter feeRouter = new AppFeeRouter(elta, governance);

        // Mock XP contract so early-buy XP gate passes.
        MockPoints points = new MockPoints();
        points.setBalance(buyer, 1_000_000 ether);

        AppToken token = new AppToken(
            AppToken.InitParams({
                name: "App",
                symbol: "APP",
                decimals: 18,
                maxSupply: 1_000_000 ether,
                creator: ownerSafe,
                admin: address(this),
                governance: governance,
                appRewardsDistributor: address(0),
                rewardsDistributor: address(0),
                treasury: treasury
            })
        );

        AppBondingCurve curve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: APP_ID,
                factory: address(this),
                elta: elta,
                token: token,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: 1_000_000 ether, // avoid graduation
                lpLockDuration: 365 days,
                lpBeneficiary: ownerSafe,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(feeRouter)),
                elataPoints: IElataPoints(address(points)),
                governance: governance,
                activationDelay: 0,
                maxDuration: 365 days,
                creator: ownerSafe,
                feeCollector: address(collector),
                referralRegistry: address(0)
            })
        );

        // Seed reserves + fund curve with tokens.
        token.mint(address(curve), 100_000 ether);
        curve.initializeCurve(100 ether, 100_000 ether);

        curve.activate();

        uint256 eltaIn = 10 ether;
        vm.startPrank(buyer);
        elta.approve(address(curve), type(uint256).max);
        curve.buy(eltaIn, 0, address(0));
        vm.stopPrank();

        uint256 fee = curve.pendingFees();
        assertGt(fee, 0, "expected non-zero trading fee");

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 splitBefore = elta.balanceOf(address(split));

        curve.sweepFees();
        collector.sweepElta(APP_ID, FeeKind.TRADING_FEE);

        uint256 treasuryDelta = elta.balanceOf(treasury) - treasuryBefore;
        uint256 splitDelta = elta.balanceOf(address(split)) - splitBefore;

        assertEq(treasuryDelta, (fee * 2000) / 10_000, "treasury take mismatch");
        assertEq(splitDelta, fee - treasuryDelta, "split take mismatch");
    }

    function test_TransferTax_SweepsAndRoutes80_20_InAppToken() public {
        AppToken token = new AppToken(
            AppToken.InitParams({
                name: "App",
                symbol: "APP",
                decimals: 18,
                maxSupply: 1_000_000 ether,
                creator: ownerSafe,
                admin: address(this),
                governance: address(this),
                appRewardsDistributor: address(0),
                rewardsDistributor: address(0),
                treasury: treasury
            })
        );

        token.setFeeCollector(address(collector), APP_ID);
        token.setLiquidityPool(lp, true);

        token.mint(buyer, 10_000 ether);

        vm.prank(buyer);
        token.transfer(lp, 1_000 ether);

        uint256 pending = collector.pendingAppTokenFees(APP_ID, FeeKind.TRANSFER_TAX, address(token));
        assertGt(pending, 0, "expected pending transfer tax");

        uint256 treasuryBefore = token.balanceOf(treasury);
        uint256 splitBefore = token.balanceOf(address(split));

        collector.sweepAppToken(APP_ID, FeeKind.TRANSFER_TAX, address(token));

        uint256 treasuryDelta = token.balanceOf(treasury) - treasuryBefore;
        uint256 splitDelta = token.balanceOf(address(split)) - splitBefore;

        assertEq(treasuryDelta, (pending * 2000) / 10_000, "treasury take mismatch");
        assertEq(splitDelta, pending - treasuryDelta, "split take mismatch");
    }

    function test_ContentSale_Routes80_20_ForAllPaymentTypes() public {
        MockContent721 content721 = new MockContent721();

        // ContentStore admin/operator is ownerSafe.
        ContentStore store = new ContentStore(
            ContentStore.InitConfig({
                appId: APP_ID,
                appToken: address(0),
                elta: address(elta),
                usdc: address(usdc),
                weth: address(weth),
                content721: address(content721),
                appRegistry: address(registry),
                factory: address(0),
                admin: ownerSafe,
                feeSwapper: address(swapper)
            })
        );

        // Attach app token for APP payments.
        AppToken token = new AppToken(
            AppToken.InitParams({
                name: "App",
                symbol: "APP",
                decimals: 18,
                maxSupply: 1_000_000 ether,
                creator: ownerSafe,
                admin: address(this),
                governance: address(this),
                appRewardsDistributor: address(0),
                rewardsDistributor: address(0),
                treasury: treasury
            })
        );
        token.mint(buyer, 10_000 ether);

        // Registry says token is launched and matches.
        registry.setTokenAndCurve(APP_ID, address(token), makeAddr("bondingCurve"));

        vm.prank(ownerSafe);
        store.setAppToken(address(token));

        // List 4 content items.
        vm.startPrank(ownerSafe);
        uint256 cNative = store.listContent("ipfs://native", 1 ether, 0, PaymentTokenType.NATIVE);
        uint256 cElta = store.listContent("ipfs://elta", 10 ether, 0, PaymentTokenType.ELTA);
        uint256 cUsdc = store.listContent("ipfs://usdc", 100e6, 0, PaymentTokenType.USDC);
        uint256 cApp = store.listContent("ipfs://app", 100 ether, 0, PaymentTokenType.APP);
        vm.stopPrank();

        // NATIVE (wrapped to WETH)
        {
            uint256 treasuryBefore = weth.balanceOf(treasury);
            uint256 splitBefore = weth.balanceOf(address(split));

            vm.prank(buyer);
            store.purchaseWithToken{value: 1 ether}(cNative, PaymentTokenType.NATIVE);

            uint256 treasuryDelta = weth.balanceOf(treasury) - treasuryBefore;
            uint256 splitDelta = weth.balanceOf(address(split)) - splitBefore;
            assertEq(treasuryDelta, 0.2 ether);
            assertEq(splitDelta, 0.8 ether);
        }

        // ELTA
        {
            uint256 treasuryBefore = elta.balanceOf(treasury);
            uint256 splitBefore = elta.balanceOf(address(split));

            vm.startPrank(buyer);
            elta.approve(address(store), type(uint256).max);
            store.purchaseWithToken(cElta, PaymentTokenType.ELTA);
            vm.stopPrank();

            uint256 treasuryDelta = elta.balanceOf(treasury) - treasuryBefore;
            uint256 splitDelta = elta.balanceOf(address(split)) - splitBefore;
            assertEq(treasuryDelta, 2 ether);
            assertEq(splitDelta, 8 ether);
        }

        // USDC
        {
            uint256 treasuryBefore = usdc.balanceOf(treasury);
            uint256 splitBefore = usdc.balanceOf(address(split));

            vm.startPrank(buyer);
            usdc.approve(address(store), type(uint256).max);
            store.purchaseWithToken(cUsdc, PaymentTokenType.USDC);
            vm.stopPrank();

            uint256 treasuryDelta = usdc.balanceOf(treasury) - treasuryBefore;
            uint256 splitDelta = usdc.balanceOf(address(split)) - splitBefore;
            assertEq(treasuryDelta, 20e6);
            assertEq(splitDelta, 80e6);
        }

        // APP
        {
            uint256 treasuryBefore = token.balanceOf(treasury);
            uint256 splitBefore = token.balanceOf(address(split));

            vm.startPrank(buyer);
            token.approve(address(store), type(uint256).max);
            store.purchaseWithToken(cApp, PaymentTokenType.APP);
            vm.stopPrank();

            uint256 treasuryDelta = token.balanceOf(treasury) - treasuryBefore;
            uint256 splitDelta = token.balanceOf(address(split)) - splitBefore;
            assertEq(treasuryDelta, 20 ether);
            assertEq(splitDelta, 80 ether);
        }
    }

    function test_PausedApp_Routes100PercentToTreasury() public {
        uint256 appId = 2;
        registry.registerApp(appId, ownerSafe, address(new RevertingSplit()), "ipfs://meta2");

        vm.prank(governance);
        registry.setPaused(appId, true);

        usdc.mint(buyer, 100e6);
        vm.startPrank(buyer);
        usdc.approve(address(swapper), type(uint256).max);
        swapper.accrue(appId, FeeKind.CONTENT_SALE, address(usdc), 100e6, buyer);
        vm.stopPrank();

        assertEq(usdc.balanceOf(treasury), 100e6, "paused app should route all to treasury");
    }
}

