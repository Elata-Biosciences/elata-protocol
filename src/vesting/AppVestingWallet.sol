// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AppVestingWallet
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Vesting wallet for team token allocations with cliff and linear vesting.
 * @dev Holds a single ERC20 token on behalf of a beneficiary. No tokens vest during the cliff period;
 *      after the cliff, tokens vest linearly until the end of the vesting duration. Anyone may trigger
 *      release(), which transfers vested tokens to the beneficiary. The admin may update the beneficiary
 *      address (e.g., for multisig rotation). There is no early-unlock or rescue mechanism.
 */
contract AppVestingWallet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error InvalidDuration();
    error Unauthorized();

    // =========== Events ===========
    event TokensReleased(address indexed token, uint256 amount);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    // =========== State ===========

    /// @notice App ID this vesting wallet belongs to
    uint256 public immutable appId;

    /// @notice Token being vested
    address public immutable token;

    /// @notice Start timestamp of vesting schedule
    uint64 public immutable start;

    /// @notice Cliff duration before any tokens vest
    uint64 public immutable cliff;

    /// @notice Total vesting duration (after cliff)
    uint64 public immutable duration;

    /// @notice Current beneficiary receiving vested tokens
    address public beneficiary;

    /// @notice Admin who can update beneficiary
    address public admin;

    /// @notice Total tokens already released
    uint256 public released;

    // =========== Constructor ===========

    /**
     * @notice Create a new vesting wallet
     * @param _appId App ID for metadata attribution
     * @param _token Token to be vested
     * @param _beneficiary Initial beneficiary (team multisig)
     * @param _start Start timestamp (usually block.timestamp at app creation)
     * @param _cliff Cliff duration in seconds (e.g., 90 days)
     * @param _duration Vesting duration after cliff in seconds (e.g., 730 days)
     * @param _admin Admin address who can update beneficiary
     */
    constructor(
        uint256 _appId,
        address _token,
        address _beneficiary,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        address _admin
    ) {
        if (_token == address(0)) revert ZeroAddress();
        if (_beneficiary == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();
        if (_duration == 0) revert InvalidDuration();

        appId = _appId;
        token = _token;
        beneficiary = _beneficiary;
        start = _start;
        cliff = _cliff;
        duration = _duration;
        admin = _admin;
    }

    // =========== Core Functions ===========

    /**
     * @notice Release vested tokens to beneficiary
     * @dev Permissionless - anyone can trigger, but tokens always go to beneficiary
     */
    function release() external nonReentrant {
        uint256 amount = releasable();
        if (amount == 0) return;

        released += amount;

        IERC20(token).safeTransfer(beneficiary, amount);

        emit TokensReleased(token, amount);
    }

    // =========== Admin Functions ===========

    /**
     * @notice Update the beneficiary address
     * @param _newBeneficiary New beneficiary address
     * @dev Only callable by admin (for multisig rotation)
     */
    function setBeneficiary(address _newBeneficiary) external {
        if (msg.sender != admin) revert Unauthorized();
        if (_newBeneficiary == address(0)) revert ZeroAddress();

        address oldBeneficiary = beneficiary;
        beneficiary = _newBeneficiary;

        emit BeneficiaryUpdated(oldBeneficiary, _newBeneficiary);
    }

    /**
     * @notice Transfer admin role
     * @param _newAdmin New admin address
     * @dev Only callable by current admin
     */
    function setAdmin(address _newAdmin) external {
        if (msg.sender != admin) revert Unauthorized();
        if (_newAdmin == address(0)) revert ZeroAddress();

        address oldAdmin = admin;
        admin = _newAdmin;

        emit AdminUpdated(oldAdmin, _newAdmin);
    }

    // =========== View Functions ===========

    /**
     * @notice Get amount of tokens that can be released right now
     * @return Amount of releasable tokens
     */
    function releasable() public view returns (uint256) {
        return vestedAmount() - released;
    }

    /**
     * @notice Get total amount of tokens that have vested so far
     * @return Total vested amount
     */
    function vestedAmount() public view returns (uint256) {
        return _vestingSchedule(totalTokenBalance() + released, uint64(block.timestamp));
    }

    /**
     * @notice Get current token balance in wallet
     * @return Current balance
     */
    function totalTokenBalance() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Get end timestamp of vesting schedule
     * @return End timestamp (start + cliff + duration)
     */
    function end() public view returns (uint256) {
        return start + cliff + duration;
    }

    // =========== Internal Functions ===========

    /**
     * @notice Calculate vested amount based on linear schedule with cliff
     * @param totalAllocation Total tokens allocated for vesting
     * @param timestamp Current timestamp
     * @return Amount vested at timestamp
     */
    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp) internal view returns (uint256) {
        // Before start
        if (timestamp < start) {
            return 0;
        }

        uint256 elapsed = timestamp - start;

        // Before cliff ends
        if (elapsed < cliff) {
            return 0;
        }

        // Time elapsed after cliff
        uint256 vestedTime = elapsed - cliff;

        // After full vesting
        if (vestedTime >= duration) {
            return totalAllocation;
        }

        // Linear vesting: (totalAllocation * vestedTime) / duration
        return (totalAllocation * vestedTime) / duration;
    }
}
