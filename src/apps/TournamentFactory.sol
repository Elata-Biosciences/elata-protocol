// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IOwnable } from "./Interfaces.sol";
import { Tournament } from "./Tournament.sol";

/**
 * @title TournamentFactory
 * @author Elata Protocol
 * @notice Factory for deploying tournament contracts with registry
 * @dev Allows app creators to easily deploy tournaments for their tokens
 *
 * Key Features:
 * - Token-owner restricted deployment
 * - Default parameter templates
 * - Tournament registry per app
 * - Extensible for future tournament types
 *
 * Usage:
 * 1. App creator calls createTournament() with their app token
 * 2. Factory deploys Tournament contract
 * 3. Creator owns tournament and can configure/finalize
 * 4. Registry tracks all tournaments per app for discovery
 */
contract TournamentFactory is Ownable {
    /// @notice Protocol treasury for tournament fees
    address public treasury;

    /// @notice Default protocol fee (250 = 2.5%)
    uint256 public defaultProtocolFeeBps = 250;

    /// @notice Default burn fee (100 = 1%)
    uint256 public defaultBurnFeeBps = 100;

    struct TournamentInfo {
        address tournament;
        address appToken;
        address creator;
        uint64 createdAt;
        bool finalized;
    }

    /// @notice All tournaments ever created
    TournamentInfo[] public tournaments;

    /// @notice Tournaments by app token
    mapping(address => address[]) public tournamentsByApp;

    /// @notice Tournaments by creator
    mapping(address => address[]) public tournamentsByCreator;

    event TournamentCreated(
        address indexed appToken,
        address indexed tournament,
        address indexed creator,
        uint256 entryFee,
        uint64 startTime,
        uint64 endTime
    );
    event TreasurySet(address treasury);
    event DefaultFeesSet(uint256 protocolFeeBps, uint256 burnFeeBps);

    error NotTokenOwner();
    error InvalidFees();

    /**
     * @notice Initialize tournament factory
     * @param initialOwner Factory owner (protocol)
     * @param treasury_ Protocol treasury address
     */
    constructor(address initialOwner, address treasury_) Ownable(initialOwner) {
        treasury = treasury_;
    }

    /**
     * @notice Set protocol treasury address
     * @param treasury_ New treasury address
     */
    function setTreasury(address treasury_) external onlyOwner {
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    /**
     * @notice Set default fee parameters
     * @param protocolFeeBps Default protocol fee in bps
     * @param burnFeeBps Default burn fee in bps
     */
    function setDefaultFees(uint256 protocolFeeBps, uint256 burnFeeBps)
        external
        onlyOwner
    {
        if (protocolFeeBps + burnFeeBps > 1500) revert InvalidFees();
        defaultProtocolFeeBps = protocolFeeBps;
        defaultBurnFeeBps = burnFeeBps;
        emit DefaultFeesSet(protocolFeeBps, burnFeeBps);
    }

    /**
     * @notice Create a tournament with default fees
     * @param appToken App token address
     * @param entryFee Entry fee in app tokens
     * @param startTime Tournament start time (0 = immediate)
     * @param endTime Tournament end time (0 = no end)
     * @return tournament Address of deployed tournament
     */
    function createTournament(
        address appToken,
        uint256 entryFee,
        uint64 startTime,
        uint64 endTime
    ) external returns (address tournament) {
        return createTournamentWithFees(
            appToken,
            entryFee,
            startTime,
            endTime,
            defaultProtocolFeeBps,
            defaultBurnFeeBps
        );
    }

    /**
     * @notice Create a tournament with custom fees
     * @param appToken App token address
     * @param entryFee Entry fee in app tokens
     * @param startTime Tournament start time (0 = immediate)
     * @param endTime Tournament end time (0 = no end)
     * @param protocolFeeBps Protocol fee in basis points
     * @param burnFeeBps Burn fee in basis points
     * @return tournamentAddr Address of deployed tournament
     */
    function createTournamentWithFees(
        address appToken,
        uint256 entryFee,
        uint64 startTime,
        uint64 endTime,
        uint256 protocolFeeBps,
        uint256 burnFeeBps
    ) public returns (address tournamentAddr) {
        // Verify caller is token owner
        if (IOwnable(appToken).owner() != msg.sender) {
            revert NotTokenOwner();
        }

        // Verify fees
        if (protocolFeeBps + burnFeeBps > 1500) {
            revert InvalidFees();
        }

        // Deploy tournament (creator becomes owner)
        tournamentAddr = address(
            new Tournament(
                appToken,
                msg.sender,
                treasury,
                entryFee,
                startTime,
                endTime,
                protocolFeeBps,
                burnFeeBps
            )
        );

        // Register tournament
        uint256 tournamentId = tournaments.length;
        tournaments.push(
            TournamentInfo({
                tournament: tournamentAddr,
                appToken: appToken,
                creator: msg.sender,
                createdAt: uint64(block.timestamp),
                finalized: false
            })
        );

        tournamentsByApp[appToken].push(tournamentAddr);
        tournamentsByCreator[msg.sender].push(tournamentAddr);

        emit TournamentCreated(
            appToken,
            tournamentAddr,
            msg.sender,
            entryFee,
            startTime,
            endTime
        );
    }

    // ────────────────────────────────────────────────────────────────────────────
    // VIEW FUNCTIONS
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Get all tournaments for an app
     * @param appToken App token address
     * @return Array of tournament addresses
     */
    function getAppTournaments(address appToken)
        external
        view
        returns (address[] memory)
    {
        return tournamentsByApp[appToken];
    }

    /**
     * @notice Get all tournaments by a creator
     * @param creator Creator address
     * @return Array of tournament addresses
     */
    function getCreatorTournaments(address creator)
        external
        view
        returns (address[] memory)
    {
        return tournamentsByCreator[creator];
    }

    /**
     * @notice Get total tournament count
     * @return Total number of tournaments created
     */
    function getTournamentCount() external view returns (uint256) {
        return tournaments.length;
    }

    /**
     * @notice Get tournament info by ID
     * @param tournamentId Tournament ID
     * @return Tournament info struct
     */
    function getTournamentInfo(uint256 tournamentId)
        external
        view
        returns (TournamentInfo memory)
    {
        return tournaments[tournamentId];
    }
}

