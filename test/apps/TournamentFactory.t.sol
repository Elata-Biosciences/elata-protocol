// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { TournamentFactory } from "../../src/apps/TournamentFactory.sol";
import { Tournament } from "../../src/apps/Tournament.sol";
import { AppToken } from "../../src/apps/AppToken.sol";

contract TournamentFactoryTest is Test {
    TournamentFactory public factory;
    AppToken public appToken;

    address public factoryOwner = makeAddr("factoryOwner");
    address public treasury = makeAddr("treasury");
    address public appCreator = makeAddr("appCreator");
    address public user1 = makeAddr("user1");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    event TournamentCreated(
        address indexed appToken,
        address indexed tournament,
        address indexed creator,
        uint256 entryFee,
        uint64 startTime,
        uint64 endTime
    );

    function setUp() public {
        factory = new TournamentFactory(factoryOwner, treasury);
        appToken = new AppToken(
            "TestApp",
            "TEST",
            18,
            MAX_SUPPLY,
            appCreator,
            admin,
            address(1),
            address(1),
            address(1),
            address(1)
        );
    }

    function test_Deployment() public {
        assertEq(factory.owner(), factoryOwner);
        assertEq(factory.treasury(), treasury);
        assertEq(factory.defaultProtocolFeeBps(), 250);
        assertEq(factory.defaultBurnFeeBps(), 100);
    }

    function test_CreateTournament() public {
        vm.prank(appCreator);
        address tournament = factory.createTournament(address(appToken), 10 ether, 0, 0);

        assertTrue(tournament != address(0));
        assertEq(Tournament(tournament).owner(), appCreator);
        assertEq(address(Tournament(tournament).APP()), address(appToken));
        assertEq(Tournament(tournament).entryFee(), 10 ether);
        assertEq(Tournament(tournament).protocolFeeBps(), 250);
        assertEq(Tournament(tournament).burnFeeBps(), 100);
    }

    function test_CreateTournamentWithCustomFees() public {
        vm.prank(appCreator);
        address tournament = factory.createTournamentWithFees(
            address(appToken),
            20 ether,
            uint64(block.timestamp),
            uint64(block.timestamp + 7 days),
            300, // 3% protocol fee
            200 // 2% burn fee
        );

        assertEq(Tournament(tournament).protocolFeeBps(), 300);
        assertEq(Tournament(tournament).burnFeeBps(), 200);
    }

    function test_RevertWhen_NotTokenOwner() public {
        vm.expectRevert(TournamentFactory.NotTokenOwner.selector);
        vm.prank(user1);
        factory.createTournament(address(appToken), 10 ether, 0, 0);
    }

    function test_RevertWhen_FeesTooHigh() public {
        vm.expectRevert(TournamentFactory.InvalidFees.selector);
        vm.prank(appCreator);
        factory.createTournamentWithFees(
            address(appToken),
            10 ether,
            0,
            0,
            1000,
            600 // Total > 15%
        );
    }

    function test_MultipleTournamentsForSameApp() public {
        // Create first tournament
        vm.prank(appCreator);
        address tourn1 = factory.createTournament(
            address(appToken), 10 ether, 0, uint64(block.timestamp + 7 days)
        );

        // Create second tournament
        vm.prank(appCreator);
        address tourn2 = factory.createTournament(
            address(appToken),
            20 ether,
            uint64(block.timestamp + 7 days),
            uint64(block.timestamp + 14 days)
        );

        // Verify both exist and are different
        assertTrue(tourn1 != tourn2);

        // Verify registry
        address[] memory appTournaments = factory.getAppTournaments(address(appToken));
        assertEq(appTournaments.length, 2);
        assertEq(appTournaments[0], tourn1);
        assertEq(appTournaments[1], tourn2);
    }

    function test_GetCreatorTournaments() public {
        // Create multiple tournaments
        vm.startPrank(appCreator);
        address tourn1 = factory.createTournament(address(appToken), 10 ether, 0, 0);
        address tourn2 = factory.createTournament(address(appToken), 20 ether, 0, 0);
        vm.stopPrank();

        address[] memory creatorTournaments = factory.getCreatorTournaments(appCreator);
        assertEq(creatorTournaments.length, 2);
        assertEq(creatorTournaments[0], tourn1);
        assertEq(creatorTournaments[1], tourn2);
    }

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(factoryOwner);
        factory.setTreasury(newTreasury);

        assertEq(factory.treasury(), newTreasury);
    }

    function test_SetDefaultFees() public {
        vm.prank(factoryOwner);
        factory.setDefaultFees(300, 200);

        assertEq(factory.defaultProtocolFeeBps(), 300);
        assertEq(factory.defaultBurnFeeBps(), 200);
    }

    function test_RevertWhen_SetDefaultFeesTooHigh() public {
        vm.expectRevert(TournamentFactory.InvalidFees.selector);
        vm.prank(factoryOwner);
        factory.setDefaultFees(1000, 600);
    }
}
