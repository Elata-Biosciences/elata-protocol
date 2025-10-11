// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AppFactoryViews
 * @author Elata Biosciences
 * @notice View functions for AppFactory (separated to reduce main contract size)
 * @dev Helper contract that reads AppFactory storage for efficient queries
 */
contract AppFactoryViews {
    // Reference to main factory
    address public immutable factory;

    struct App {
        address creator;
        address token;
        address curve;
        address pair;
        address locker;
        uint64 createdAt;
        uint64 graduatedAt;
        bool graduated;
        uint256 totalRaised;
        uint256 finalSupply;
    }

    constructor(address _factory) {
        require(_factory != address(0), "Zero address");
        factory = _factory;
    }

    /**
     * @notice Get app details
     * @param appId App ID
     * @return App struct
     */
    function getApp(uint256 appId) external view returns (App memory) {
        (
            address creator,
            address token,
            address curve,
            address pair,
            address locker,
            uint64 createdAt,
            uint64 graduatedAt,
            bool graduated,
            uint256 totalRaised,
            uint256 finalSupply
        ) = IAppFactoryState(factory).apps(appId);

        return App({
            creator: creator,
            token: token,
            curve: curve,
            pair: pair,
            locker: locker,
            createdAt: createdAt,
            graduatedAt: graduatedAt,
            graduated: graduated,
            totalRaised: totalRaised,
            finalSupply: finalSupply
        });
    }

    /**
     * @notice Get apps created by address
     * @param creator Creator address
     * @return Array of app IDs
     */
    function getCreatorApps(address creator) external view returns (uint256[] memory) {
        IAppFactoryState factoryState = IAppFactoryState(factory);
        
        // Get count by checking each appId (not ideal but works)
        uint256 appCount = factoryState.appCount();
        uint256 count = 0;
        
        // Count apps by this creator
        for (uint256 i = 0; i < appCount; i++) {
            (address appCreator,,,,,,,,, ) = factoryState.apps(i);
            if (appCreator == creator) count++;
        }
        
        // Build array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < appCount; i++) {
            (address appCreator,,,,,,,,, ) = factoryState.apps(i);
            if (appCreator == creator) {
                result[index] = i;
                index++;
            }
        }
        
        return result;
    }

    /**
     * @notice Get app ID from token address
     * @param token Token address
     * @return App ID
     */
    function getAppIdFromToken(address token) external view returns (uint256) {
        return IAppFactoryState(factory).tokenToAppId(token);
    }

    /**
     * @notice Get total cost to create an app
     * @return Total ELTA required (seedElta + creationFee)
     */
    function getTotalCreationCost() external view returns (uint256) {
        IAppFactoryState factoryState = IAppFactoryState(factory);
        return factoryState.seedElta() + factoryState.creationFee();
    }

    /**
     * @notice Get current launch parameters
     * @return seed Current seed ELTA amount
     * @return creation Current creation fee
     * @return target Target ELTA to raise
     * @return supply Default token supply
     * @return lpLock LP lock duration
     * @return decimals Default decimals
     * @return protocolFee Protocol fee rate in bps
     */
    function getParameters()
        external
        view
        returns (
            uint256 seed,
            uint256 creation,
            uint256 target,
            uint256 supply,
            uint256 lpLock,
            uint8 decimals,
            uint256 protocolFee
        )
    {
        IAppFactoryState factoryState = IAppFactoryState(factory);
        return (
            factoryState.seedElta(),
            factoryState.creationFee(),
            factoryState.targetRaisedElta(),
            factoryState.defaultSupply(),
            factoryState.lpLockDuration(),
            factoryState.defaultDecimals(),
            factoryState.protocolFeeRate()
        );
    }

    /**
     * @notice Get all graduated apps
     * @return Array of graduated app IDs
     */
    function getGraduatedApps() external view returns (uint256[] memory) {
        IAppFactoryState factoryState = IAppFactoryState(factory);
        uint256 appCount = factoryState.appCount();
        uint256 graduatedCount = 0;

        // Count graduated apps
        for (uint256 i = 0; i < appCount; i++) {
            (,,,,,, , bool isGrad,, ) = factoryState.apps(i);
            if (isGrad) graduatedCount++;
        }

        // Build array
        uint256[] memory graduatedList = new uint256[](graduatedCount);
        uint256 index = 0;

        for (uint256 i = 0; i < appCount; i++) {
            (,,,,,, , bool isGrad,, ) = factoryState.apps(i);
            if (isGrad) {
                graduatedList[index] = i;
                index++;
            }
        }

        return graduatedList;
    }

    /**
     * @notice Get launch statistics
     * @return totalApps Total apps created
     * @return graduatedApps Total graduated apps
     * @return totalValueLocked Total ELTA locked in curves
     * @return totalFeesCollected Total creation fees collected
     */
    function getLaunchStats()
        external
        view
        returns (
            uint256 totalApps,
            uint256 graduatedApps,
            uint256 totalValueLocked,
            uint256 totalFeesCollected
        )
    {
        IAppFactoryState factoryState = IAppFactoryState(factory);
        totalApps = factoryState.appCount();

        for (uint256 i = 0; i < totalApps; i++) {
            (,,,,,, , bool graduated, uint256 totalRaised, ) = factoryState.apps(i);
            if (graduated) {
                graduatedApps++;
                totalValueLocked += totalRaised;
            }
        }

        totalFeesCollected = graduatedApps * factoryState.creationFee(); // Approximation
    }
}

/**
 * @notice Interface for reading AppFactory state
 */
interface IAppFactoryState {
    function appCount() external view returns (uint256);
    function apps(uint256) external view returns (
        address creator,
        address token,
        address curve,
        address pair,
        address locker,
        uint64 createdAt,
        uint64 graduatedAt,
        bool graduated,
        uint256 totalRaised,
        uint256 finalSupply
    );
    function tokenToAppId(address) external view returns (uint256);
    function seedElta() external view returns (uint256);
    function creationFee() external view returns (uint256);
    function targetRaisedElta() external view returns (uint256);
    function defaultSupply() external view returns (uint256);
    function lpLockDuration() external view returns (uint256);
    function defaultDecimals() external view returns (uint8);
    function protocolFeeRate() external view returns (uint256);
}

