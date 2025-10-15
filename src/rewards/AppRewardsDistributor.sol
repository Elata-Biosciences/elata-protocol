// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AppRewardsDistributor
 * @author Elata Protocol
 * @notice Distributes ELTA rewards to app stakers using on-chain snapshots
 * @dev Receives 70% of protocol revenues and distributes proportionally to app vaults
 *
 * Key Features:
 * - Registry of active app vaults (AppStakingVault addresses)
 * - Per-vault epochs with block snapshots
 * - Weight by total staked (vault.totalSupply() at distribution block)
 * - On-chain pro-rata claims via getPastVotes()
 * - Gas-bounded claims (max 100 epochs per call)
 * - Per-user cursor tracking to prevent double-claims
 *
 * Architecture:
 * 1. Factory registers new app vaults
 * 2. RewardsDistributor calls distribute() with 70% of revenue
 * 3. Allocate ELTA proportionally to vaults by totalSupply()
 * 4. Users claim via getPastVotes() at epoch blockNumber
 *
 * Governance:
 * - FACTORY_ROLE: Register new vaults at app creation
 * - GOVERNANCE_ROLE: Pause/unpause vaults, update weights
 */
interface IStakeVaultVotes {
    function totalSupply() external view returns (uint256);
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
}

contract AppRewardsDistributor is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    error VaultExists();
    error UnknownVault();
    error NoEpochs();

    IERC20 public immutable ELTA;

    /// @notice Registry of all vaults
    address[] public vaults;

    /// @notice Vault existence check
    mapping(address => bool) public isVault;

    /// @notice Vault active status (inactive = paused/removed)
    mapping(address => bool) public isActive;

    /// @notice Token to vault mapping (for fee-on-transfer rewards)
    mapping(address => address) public tokenToVault;

    /// @notice Per-vault epoch data
    struct AppEpoch {
        uint256 blockNumber; // Snapshot block
        uint256 amount; // ELTA allocated to this vault
        uint256 totalStaked; // vault.totalSupply() at blockNumber
    }

    mapping(address => AppEpoch[]) public epochs;

    /// @notice Per-user claim cursor (user => vault => lastClaimedIndex)
    mapping(address => mapping(address => uint256)) public userCursor;

    /// @notice App token reward epochs (vault => token => epochs)
    /// @dev Separate from ELTA epochs to avoid mixing reward types
    mapping(address => mapping(IERC20 => AppEpoch[])) public tokenEpochs;

    /// @notice Per-user claim cursor for token epochs (user => vault => token => lastClaimedIndex)
    mapping(address => mapping(address => mapping(IERC20 => uint256))) public tokenCursor;

    event AppRegistered(address indexed vault);
    event AppPaused(address indexed vault, bool paused);
    event AppRemoved(address indexed vault);
    event AppDistributed(uint256 indexed blockNumber, uint256 totalAmount, uint256 activeApps);
    event AppClaim(
        address indexed vault,
        address indexed user,
        uint256 fromEpoch,
        uint256 toEpoch,
        uint256 amount
    );

    /**
     * @notice Initialize app rewards distributor
     * @param _elta ELTA token address
     * @param _governance Governance address
     * @param _factory Factory address
     */
    constructor(IERC20 _elta, address _governance, address _factory) {
        require(address(_elta) != address(0), "Zero ELTA");
        require(_governance != address(0), "Zero gov");
        require(_factory != address(0), "Zero factory");

        ELTA = _elta;
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        _grantRole(GOVERNANCE_ROLE, _governance);
        _grantRole(FACTORY_ROLE, _factory);
    }

    /**
     * @notice Register new app vault (factory only)
     * @param vault Address of AppStakingVault
     * @param token Address of the app token
     */
    function registerApp(address vault, address token) external onlyRole(FACTORY_ROLE) {
        if (isVault[vault]) revert VaultExists();
        require(token != address(0), "Zero token");

        isVault[vault] = true;
        isActive[vault] = true;
        vaults.push(vault);
        tokenToVault[token] = vault;

        emit AppRegistered(vault);
    }

    /**
     * @notice Legacy registerApp for backward compatibility
     * @param vault Address of AppStakingVault
     */
    function registerApp(address vault) external onlyRole(FACTORY_ROLE) {
        if (isVault[vault]) revert VaultExists();

        isVault[vault] = true;
        isActive[vault] = true;
        vaults.push(vault);

        emit AppRegistered(vault);
    }

    /**
     * @notice Pause/unpause an app vault (governance only)
     * @param vault Vault address
     * @param paused True to pause, false to unpause
     */
    function pauseApp(address vault, bool paused) external onlyRole(GOVERNANCE_ROLE) {
        if (!isVault[vault]) revert UnknownVault();

        isActive[vault] = !paused;
        emit AppPaused(vault, paused);
    }

    /**
     * @notice Remove app from active distribution (governance only)
     * @dev Vault remains in registry for historical claims but gets no new rewards
     * @param vault Vault address
     */
    function removeApp(address vault) external onlyRole(GOVERNANCE_ROLE) {
        if (!isVault[vault]) revert UnknownVault();

        isActive[vault] = false;
        emit AppRemoved(vault);
    }

    /**
     * @notice Distribute ELTA rewards across active vaults
     * @dev Called by RewardsDistributor with 70% of protocol revenue
     * @param amount Total ELTA to distribute
     */
    function distribute(uint256 amount) external {
        ELTA.safeTransferFrom(msg.sender, address(this), amount);

        uint256 totalWeight;
        uint256 n = vaults.length;

        // Calculate total weight (sum of totalSupply across active vaults)
        for (uint256 i; i < n; ++i) {
            address vault = vaults[i];
            if (!isActive[vault]) continue;

            totalWeight += IStakeVaultVotes(vault).totalSupply();
        }

        uint256 blockNumber = block.number;
        uint256 activeCount;

        // Allocate proportionally to each vault
        for (uint256 i; i < n; ++i) {
            address vault = vaults[i];
            if (!isActive[vault]) continue;

            uint256 vaultTotalStaked = IStakeVaultVotes(vault).totalSupply();
            uint256 vaultShare = (totalWeight == 0) ? 0 : (amount * vaultTotalStaked) / totalWeight;

            epochs[vault].push(
                AppEpoch({
                    blockNumber: blockNumber,
                    amount: vaultShare,
                    totalStaked: vaultTotalStaked
                })
            );

            activeCount++;
        }

        emit AppDistributed(blockNumber, amount, activeCount);
    }

    /**
     * @notice Deposit app tokens as rewards for a specific app (fee-on-transfer)
     * @dev Called by AppToken when transfer fees are collected
     * @param token App token address
     * @param amount Amount of app tokens to distribute
     */
    function depositForApp(IERC20 token, uint256 amount) external {
        // Find vault for this token
        address vault = tokenToVault[address(token)];
        require(vault != address(0), "Unknown token");

        // Pull tokens from caller (AppToken contract)
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Create epoch denominated in this token (separate from ELTA epochs)
        uint256 totalStaked = IStakeVaultVotes(vault).totalSupply();
        tokenEpochs[vault][token].push(
            AppEpoch({ blockNumber: block.number, amount: amount, totalStaked: totalStaked })
        );
    }

    /**
     * @notice Claim rewards for a specific vault
     * @dev Bounded to 100 epochs per call for gas safety
     * @param vault Vault address to claim from
     * @param toEpoch Claim up to this epoch (exclusive)
     */
    function claim(address vault, uint256 toEpoch) external {
        AppEpoch[] storage vaultEpochs = epochs[vault];
        if (vaultEpochs.length == 0) revert NoEpochs();

        uint256 fromEpoch = userCursor[msg.sender][vault];
        uint256 endEpoch = toEpoch > vaultEpochs.length ? vaultEpochs.length : toEpoch;

        // Gas-bounded loop (max 100 epochs)
        uint256 maxEpoch = fromEpoch + 100;
        if (endEpoch > maxEpoch) endEpoch = maxEpoch;

        uint256 totalClaim;

        for (uint256 i = fromEpoch; i < endEpoch; ++i) {
            AppEpoch storage epoch = vaultEpochs[i];

            // Skip if epoch has no rewards or no stakers
            if (epoch.totalStaked == 0 || epoch.amount == 0) continue;

            // Get user's stake at epoch block
            uint256 userStake = IStakeVaultVotes(vault).getPastVotes(msg.sender, epoch.blockNumber);
            if (userStake == 0) continue;

            // Pro-rata calculation
            totalClaim += (epoch.amount * userStake) / epoch.totalStaked;
        }

        userCursor[msg.sender][vault] = endEpoch;

        if (totalClaim > 0) {
            ELTA.safeTransfer(msg.sender, totalClaim);
        }

        emit AppClaim(vault, msg.sender, fromEpoch, endEpoch, totalClaim);
    }

    /**
     * @notice Claim from multiple vaults in one transaction
     * @param vaultList Array of vault addresses
     * @param toEpochs Array of target epochs (one per vault)
     */
    function claimMultiple(address[] calldata vaultList, uint256[] calldata toEpochs) external {
        require(vaultList.length == toEpochs.length, "Length mismatch");

        for (uint256 i; i < vaultList.length; ++i) {
            address vault = vaultList[i];
            AppEpoch[] storage vaultEpochs = epochs[vault];
            if (vaultEpochs.length == 0) continue;

            uint256 fromEpoch = userCursor[msg.sender][vault];
            uint256 endEpoch = toEpochs[i] > vaultEpochs.length ? vaultEpochs.length : toEpochs[i];

            // Gas-bounded
            uint256 maxEpoch = fromEpoch + 100;
            if (endEpoch > maxEpoch) endEpoch = maxEpoch;

            uint256 totalClaim;

            for (uint256 j = fromEpoch; j < endEpoch; ++j) {
                AppEpoch storage epoch = vaultEpochs[j];
                if (epoch.totalStaked == 0 || epoch.amount == 0) continue;

                uint256 userStake =
                    IStakeVaultVotes(vault).getPastVotes(msg.sender, epoch.blockNumber);
                if (userStake == 0) continue;

                totalClaim += (epoch.amount * userStake) / epoch.totalStaked;
            }

            userCursor[msg.sender][vault] = endEpoch;

            if (totalClaim > 0) {
                ELTA.safeTransfer(msg.sender, totalClaim);
            }

            emit AppClaim(vault, msg.sender, fromEpoch, endEpoch, totalClaim);
        }
    }

    /**
     * @notice Get number of epochs for a vault
     * @param vault Vault address
     * @return Number of epochs
     */
    function getEpochCount(address vault) external view returns (uint256) {
        return epochs[vault].length;
    }

    /**
     * @notice Get user's unclaimed epoch range for a vault
     * @param user User address
     * @param vault Vault address
     * @return fromEpoch Starting epoch to claim
     * @return toEpoch Ending epoch (exclusive)
     */
    function getUnclaimedRange(address user, address vault)
        external
        view
        returns (uint256 fromEpoch, uint256 toEpoch)
    {
        fromEpoch = userCursor[user][vault];
        toEpoch = epochs[vault].length;
    }

    /**
     * @notice Claim token rewards for a specific vault
     * @dev Bounded to 100 epochs per call for gas safety
     * @param vault Vault address to claim from
     * @param token Token to claim
     * @param toEpoch Claim up to this epoch (exclusive)
     */
    function claimToken(address vault, IERC20 token, uint256 toEpoch) external {
        AppEpoch[] storage vaultTokenEpochs = tokenEpochs[vault][token];
        if (vaultTokenEpochs.length == 0) return; // No epochs to claim

        uint256 fromEpoch = tokenCursor[msg.sender][vault][token];
        uint256 endEpoch = toEpoch > vaultTokenEpochs.length ? vaultTokenEpochs.length : toEpoch;

        // Gas-bounded loop (max 100 epochs)
        uint256 maxEpoch = fromEpoch + 100;
        if (endEpoch > maxEpoch) endEpoch = maxEpoch;

        uint256 totalClaim;

        for (uint256 i = fromEpoch; i < endEpoch; ++i) {
            AppEpoch storage epoch = vaultTokenEpochs[i];

            // Skip if epoch has no rewards or no stakers
            if (epoch.totalStaked == 0 || epoch.amount == 0) continue;

            // Get user's stake at epoch block
            uint256 userStake = IStakeVaultVotes(vault).getPastVotes(msg.sender, epoch.blockNumber);
            if (userStake == 0) continue;

            // Pro-rata calculation
            totalClaim += (epoch.amount * userStake) / epoch.totalStaked;
        }

        tokenCursor[msg.sender][vault][token] = endEpoch;

        if (totalClaim > 0) {
            token.safeTransfer(msg.sender, totalClaim);
        }

        emit AppClaim(vault, msg.sender, fromEpoch, endEpoch, totalClaim);
    }

    /**
     * @notice Get total number of registered vaults
     * @return Number of vaults
     */
    function getVaultCount() external view returns (uint256) {
        return vaults.length;
    }

    /**
     * @notice Get list of all vaults
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory) {
        return vaults;
    }

    /**
     * @notice Estimate pending rewards for a user in a vault
     * @dev This is a view function estimation; actual claim may differ due to rounding
     * @param user User address
     * @param vault Vault address
     * @return estimated Estimated claimable amount
     */
    function estimatePendingRewards(address user, address vault)
        external
        view
        returns (uint256 estimated)
    {
        AppEpoch[] storage vaultEpochs = epochs[vault];
        uint256 fromEpoch = userCursor[user][vault];
        uint256 endEpoch = vaultEpochs.length;

        for (uint256 i = fromEpoch; i < endEpoch && i < fromEpoch + 100; ++i) {
            AppEpoch storage epoch = vaultEpochs[i];
            if (epoch.totalStaked == 0 || epoch.amount == 0) continue;

            uint256 userStake = IStakeVaultVotes(vault).getPastVotes(user, epoch.blockNumber);
            if (userStake == 0) continue;

            estimated += (epoch.amount * userStake) / epoch.totalStaked;
        }
    }
}
