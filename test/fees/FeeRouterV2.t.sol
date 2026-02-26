// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../../src/contributors/ContributorSplitFactory.sol";
import {IContributorSplit} from "../../src/interfaces/IContributorSplit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeRouterV2Test is Test {
    MockToken token;

    address governance = makeAddr("governance");
    address treasury = makeAddr("treasury");
    address ownerSafe = makeAddr("ownerSafe");
    address contributorA = makeAddr("contributorA");
    address contributorB = makeAddr("contributorB");

    AppRegistry registry;
    ContributorSplitFactory splitFactory;
    FeeSwapper router;
    address split;

    uint256 constant APP_ID = 1;

    function setUp() public {
        token = new MockToken();

        vm.startPrank(governance);
        registry = new AppRegistry(governance, address(this));
        splitFactory = new ContributorSplitFactory(governance, address(this));
        router = new FeeSwapper(address(token), governance, governance, treasury, address(registry));
        vm.stopPrank();

        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](2);
        contributors[0] = IContributorSplit.Contributor({account: contributorA, shares: 50});
        contributors[1] = IContributorSplit.Contributor({account: contributorB, shares: 50});

        split = splitFactory.createSplit(APP_ID, ownerSafe, address(router), contributors);
        registry.registerApp(APP_ID, ownerSafe, split, "");
    }

    function test_AllFeeKindsSplitTreasuryTakeAndContributors() public {
        token.mint(address(this), 1000 ether);
        token.approve(address(router), 1000 ether);

        uint16 takeBps = router.defaultTreasuryTakeBps();
        uint256 expectedTreasury = (1000 ether * uint256(takeBps)) / 10_000;
        uint256 expectedSplit = 1000 ether - expectedTreasury;

        router.accrue(APP_ID, FeeKind.TRADING_FEE, address(token), 1000 ether, address(this));

        assertEq(token.balanceOf(treasury), expectedTreasury);
        assertEq(token.balanceOf(split), expectedSplit);
        assertEq(token.balanceOf(address(router)), 0);
    }

    function test_AppRevenueSplitsTreasuryTakeAndContributors() public {
        token.mint(address(this), 1000 ether);
        token.approve(address(router), 1000 ether);

        uint16 takeBps = router.defaultTreasuryTakeBps();
        uint256 expectedTreasury = (1000 ether * uint256(takeBps)) / 10_000;
        uint256 expectedSplit = 1000 ether - expectedTreasury;

        router.accrue(APP_ID, FeeKind.CONTENT_SALE, address(token), 1000 ether, address(this));

        assertEq(token.balanceOf(treasury), expectedTreasury);
        assertEq(token.balanceOf(split), expectedSplit);
        assertEq(token.balanceOf(address(router)), 0);
    }

    function test_PausedAppRoutesAllToTreasury() public {
        vm.prank(governance);
        registry.setPaused(APP_ID, true);

        token.mint(address(this), 1000 ether);
        token.approve(address(router), 1000 ether);

        router.accrue(APP_ID, FeeKind.OTHER, address(token), 1000 ether, address(this));

        assertEq(token.balanceOf(treasury), 1000 ether);
        assertEq(token.balanceOf(split), 0);
    }
}

