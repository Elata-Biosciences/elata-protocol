// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "../utils/Errors.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RewardsDistributor
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Central revenue hub that splits incoming ELTA fees across protocol stakeholders.
 * @dev All protocol revenues flow through deposit(), which applies a fixed 70/15/15 split:
 *      70% to AppRewardsDistributor for app stakers, 15% to a veELTA epoch pool, and 15%
 *      transferred immediately to the treasury. VeELTA holders claim their share via claimVe(),
 *      which computes pro-rata entitlements using on-chain ERC20Votes snapshots taken at each
 *      deposit block. Claims are gas-bounded to 100 epochs per call with cursor tracking to
 *      prevent double-claims. An emergency pause capability exists for incident response.
 */
import {IAppRewardsDistributor} from "../interfaces/IAppRewardsDistributor.sol";
import {IFeeManager} from "../interfaces/IFeeManager.sol";
import {IVeEltaVotes} from "../interfaces/IVeEltaVotes.sol";

contract RewardsDistributor is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    error InvalidSplit();
    error OnlyWhenNotPaused();

    IERC20 public immutable ELTA;
    IVeEltaVotes public immutable veELTA;
    IAppRewardsDistributor public immutable appRewardsDistributor;

    address public treasury;

    /// @notice FeeManager for USDC conversion of treasury fees
    address public feeManager;

    /// @notice Split configuration in basis points (must sum to 10,000)
    uint256 public constant BIPS_APP = 7000; // 70%
    uint256 public constant BIPS_VEELTA = 1500; // 15%
    uint256 public constant BIPS_TREASURY = 1500; // 15%

    /// @notice veELTA reward epochs
    struct Epoch {
        uint256 blockNumber; // Snapshot block
        uint256 amount; // ELTA allocated to veELTA stakers
    }

    Epoch[] public veEpochs;

    /// @notice User claim cursor for veELTA epochs
    mapping(address => uint256) public lastClaimed;

    /// @notice Token-denominated veELTA epochs (token => epochs)
    /// @dev For app token transfer fees distributed to veELTA holders
    mapping(IERC20 => Epoch[]) public tokenEpochs;

    /// @notice User claim cursor for token epochs (user => token => lastClaimedIndex)
    mapping(address => mapping(IERC20 => uint256)) public tokenLastClaimed;

    /// @notice Paused state
    bool public paused;

    event RevenueSplit(
        uint256 indexed blockNumber, uint256 totalAmount, uint256 appAmount, uint256 veAmount, uint256 treasuryAmount
    );
    event VeEpochCreated(uint256 indexed epochId, uint256 blockNumber, uint256 amount);
    event VeRewardsClaimed(address indexed user, uint256 fromEpoch, uint256 toEpoch, uint256 amount);
    event VeTokenEpochCreated(address indexed token, uint256 indexed epochId, uint256 blockNumber, uint256 amount);
    event VeTokenRewardsClaimed(
        address indexed user, address indexed token, uint256 fromEpoch, uint256 toEpoch, uint256 amount
    );
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);
    event EmergencyPause(bool paused);

    /**
     * @notice Initialize rewards distributor
     * @param _elta ELTA token address
     * @param _veELTA veELTA voting token address
     * @param _appRewardsDistributor App rewards distributor address
     * @param _treasury Treasury address
     * @param _admin Admin address for roles
     */
    constructor(
        IERC20 _elta,
        IVeEltaVotes _veELTA,
        IAppRewardsDistributor _appRewardsDistributor,
        address _treasury,
        address _admin
    ) {
        if (address(_elta) == address(0)) revert Errors.ZeroAddress();
        if (address(_veELTA) == address(0)) revert Errors.ZeroAddress();
        if (address(_appRewardsDistributor) == address(0)) revert Errors.ZeroAddress();
        if (_treasury == address(0)) revert Errors.ZeroAddress();
        if (_admin == address(0)) revert Errors.ZeroAddress();

        // Validate split adds to 100%
        if (BIPS_APP + BIPS_VEELTA + BIPS_TREASURY != 10_000) revert InvalidSplit();

        ELTA = _elta;
        veELTA = _veELTA;
        appRewardsDistributor = _appRewardsDistributor;
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(TREASURY_ROLE, _admin);
    }

    /**
     * @notice Modifier to check if not paused
     */
    modifier whenNotPaused() {
        if (paused) revert OnlyWhenNotPaused();
        _;
    }

    /**
     * @notice Universal entry for all protocol ELTA revenues
     * @dev Splits 70% app / 15% veELTA / 15% treasury
     * @param amount Total ELTA revenue to distribute
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert Errors.InvalidAmount();

        ELTA.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate splits
        uint256 appAmount = (amount * BIPS_APP) / 10_000;
        uint256 veAmount = (amount * BIPS_VEELTA) / 10_000;
        uint256 treasuryAmount = amount - appAmount - veAmount; // Avoid rounding issues

        // 1) Distribute to app stakers (70%)
        ELTA.approve(address(appRewardsDistributor), appAmount);
        appRewardsDistributor.distribute(appAmount);

        // 2) Record veELTA epoch (15%)
        veEpochs.push(Epoch({blockNumber: block.number, amount: veAmount}));
        emit VeEpochCreated(veEpochs.length - 1, block.number, veAmount);

        // 3) Transfer to treasury (15%) - route through FeeManager for USDC conversion
        if (feeManager != address(0)) {
            // Route through FeeManager for USDC conversion
            ELTA.approve(feeManager, treasuryAmount);
            IFeeManager(feeManager).depositEltaForApp(0, treasuryAmount); // appId 0 = protocol fees
        } else {
            // Fallback: direct transfer to treasury
            ELTA.safeTransfer(treasury, treasuryAmount);
        }

        emit RevenueSplit(block.number, amount, appAmount, veAmount, treasuryAmount);
    }

    /**
     * @notice Claim veELTA rewards across epochs
     * @dev Uses on-chain snapshots via getPastVotes()
     * @param fromEpoch Starting epoch index
     * @param toEpoch Ending epoch index (exclusive)
     */
    function claimVe(uint256 fromEpoch, uint256 toEpoch) external nonReentrant whenNotPaused {
        uint256 totalEpochs = veEpochs.length;
        if (fromEpoch >= totalEpochs) return;

        uint256 endEpoch = toEpoch > totalEpochs ? totalEpochs : toEpoch;

        // Gas-bounded loop (max 100 epochs)
        uint256 maxEpoch = fromEpoch + 100;
        if (endEpoch > maxEpoch) endEpoch = maxEpoch;

        uint256 totalClaim;

        for (uint256 i = fromEpoch; i < endEpoch; ++i) {
            Epoch storage epoch = veEpochs[i];

            uint256 userVotes = veELTA.getPastVotes(msg.sender, epoch.blockNumber);
            if (userVotes == 0) continue;

            uint256 totalVotes = veELTA.getPastTotalSupply(epoch.blockNumber);
            if (totalVotes == 0) continue;

            // Pro-rata calculation
            totalClaim += (epoch.amount * userVotes) / totalVotes;
        }

        lastClaimed[msg.sender] = endEpoch;

        if (totalClaim > 0) ELTA.safeTransfer(msg.sender, totalClaim);

        emit VeRewardsClaimed(msg.sender, fromEpoch, endEpoch, totalClaim);
    }

    /**
     * @notice Convenience function to claim from last claimed to latest
     * @dev Automatically uses lastClaimed cursor
     */
    function claimVeFromLast() external {
        uint256 fromEpoch = lastClaimed[msg.sender];
        uint256 toEpoch = veEpochs.length;
        this.claimVe(fromEpoch, toEpoch);
    }

    /**
     * @notice Deposit arbitrary ERC20 tokens as veELTA rewards (from app token transfer fees)
     * @dev Called by AppToken when transfer fees are collected for veELTA share
     * @param token Token address
     * @param amount Amount to deposit
     */
    function depositVeInToken(IERC20 token, uint256 amount) external whenNotPaused {
        if (amount == 0) revert Errors.InvalidAmount();
        require(address(token) != address(0), "Zero token");

        token.safeTransferFrom(msg.sender, address(this), amount);

        tokenEpochs[token].push(Epoch({blockNumber: block.number, amount: amount}));

        emit VeTokenEpochCreated(address(token), tokenEpochs[token].length - 1, block.number, amount);
    }

    /**
     * @notice Claim veELTA rewards in a specific token
     * @dev Uses on-chain snapshots via getPastVotes()
     * @param token Token to claim
     * @param fromEpoch Starting epoch index
     * @param toEpoch Ending epoch index (exclusive)
     */
    function claimVeToken(IERC20 token, uint256 fromEpoch, uint256 toEpoch) external nonReentrant whenNotPaused {
        Epoch[] storage epochs = tokenEpochs[token];
        uint256 totalEpochs = epochs.length;
        if (fromEpoch >= totalEpochs) return;

        uint256 endEpoch = toEpoch > totalEpochs ? totalEpochs : toEpoch;

        // Gas-bounded loop (max 100 epochs)
        uint256 maxEpoch = fromEpoch + 100;
        if (endEpoch > maxEpoch) endEpoch = maxEpoch;

        uint256 totalClaim;

        for (uint256 i = fromEpoch; i < endEpoch; ++i) {
            Epoch storage epoch = epochs[i];

            uint256 userVotes = veELTA.getPastVotes(msg.sender, epoch.blockNumber);
            if (userVotes == 0) continue;

            uint256 totalVotes = veELTA.getPastTotalSupply(epoch.blockNumber);
            if (totalVotes == 0) continue;

            // Pro-rata calculation
            totalClaim += (epoch.amount * userVotes) / totalVotes;
        }

        tokenLastClaimed[msg.sender][token] = endEpoch;

        if (totalClaim > 0) token.safeTransfer(msg.sender, totalClaim);

        emit VeTokenRewardsClaimed(msg.sender, address(token), fromEpoch, endEpoch, totalClaim);
    }

    /**
     * @notice Convenience function to claim token rewards from last claimed to latest
     * @param token Token to claim
     */
    function claimVeTokenFromLast(IERC20 token) external {
        uint256 fromEpoch = tokenLastClaimed[msg.sender][token];
        uint256 toEpoch = tokenEpochs[token].length;
        this.claimVeToken(token, fromEpoch, toEpoch);
    }

    /**
     * @notice Update treasury address (governance only)
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(TREASURY_ROLE) {
        if (newTreasury == address(0)) revert Errors.ZeroAddress();

        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    /**
     * @notice Update fee manager address for USDC conversion
     * @param newFeeManager New fee manager address (can be zero to disable)
     */
    function setFeeManager(address newFeeManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit FeeManagerUpdated(feeManager, newFeeManager);
        feeManager = newFeeManager;
    }

    /**
     * @notice Emergency pause/unpause
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyRole(PAUSER_ROLE) {
        paused = _paused;
        emit EmergencyPause(_paused);
    }

    /**
     * @notice Get total number of veELTA epochs
     * @return Number of epochs
     */
    function getEpochCount() external view returns (uint256) {
        return veEpochs.length;
    }

    /**
     * @notice Get unclaimed epoch range for a user
     * @param user User address
     * @return fromEpoch Starting epoch
     * @return toEpoch Ending epoch (exclusive)
     */
    function getUnclaimedRange(address user) external view returns (uint256 fromEpoch, uint256 toEpoch) {
        fromEpoch = lastClaimed[user];
        toEpoch = veEpochs.length;
    }

    /**
     * @notice Estimate pending veELTA rewards for a user
     * @dev View function estimation; may differ from actual claim due to rounding
     * @param user User address
     * @return estimated Estimated claimable amount
     */
    function estimatePendingVeRewards(address user) external view returns (uint256 estimated) {
        uint256 fromEpoch = lastClaimed[user];
        uint256 endEpoch = veEpochs.length;

        // Cap at 100 epochs for gas safety
        if (endEpoch > fromEpoch + 100) endEpoch = fromEpoch + 100;

        for (uint256 i = fromEpoch; i < endEpoch; ++i) {
            Epoch storage epoch = veEpochs[i];

            uint256 userVotes = veELTA.getPastVotes(user, epoch.blockNumber);
            if (userVotes == 0) continue;

            uint256 totalVotes = veELTA.getPastTotalSupply(epoch.blockNumber);
            if (totalVotes == 0) continue;

            estimated += (epoch.amount * userVotes) / totalVotes;
        }
    }

    /**
     * @notice Get epoch details
     * @param epochId Epoch index
     * @return blockNumber Snapshot block
     * @return amount ELTA allocated
     */
    function getEpoch(uint256 epochId) external view returns (uint256 blockNumber, uint256 amount) {
        if (epochId >= veEpochs.length) return (0, 0);
        Epoch storage epoch = veEpochs[epochId];
        return (epoch.blockNumber, epoch.amount);
    }

    /**
     * @notice Get multiple epochs in batch
     * @param startId Starting epoch index
     * @param count Number of epochs to fetch
     * @return epochs Array of epochs
     */
    function getEpochsBatch(uint256 startId, uint256 count) external view returns (Epoch[] memory epochs) {
        uint256 totalEpochs = veEpochs.length;
        if (startId >= totalEpochs) return new Epoch[](0);

        uint256 endId = startId + count;
        if (endId > totalEpochs) endId = totalEpochs;

        uint256 actualCount = endId - startId;
        epochs = new Epoch[](actualCount);

        for (uint256 i; i < actualCount; ++i) {
            epochs[i] = veEpochs[startId + i];
        }
    }
}
