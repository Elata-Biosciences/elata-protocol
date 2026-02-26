// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAppRegistry {
    struct AppInfo {
        address ownerSafe;
        address contributorSplit;
        address appToken; // optional; zero if not launched
        address bondingCurve; // optional; zero if not launched
        string metadataURI;
        bool tokenLaunched;
        bool paused;
    }

    event AppRegistered(
        uint256 indexed appId, address indexed ownerSafe, address indexed contributorSplit, string metadataURI
    );
    event AppOwnerUpdated(uint256 indexed appId, address indexed oldOwnerSafe, address indexed newOwnerSafe);
    event AppMetadataURIUpdated(uint256 indexed appId, string oldURI, string newURI);
    event AppContributorSplitUpdated(uint256 indexed appId, address indexed oldSplit, address indexed newSplit);

    event AppTokenLaunched(uint256 indexed appId, address indexed appToken, address indexed bondingCurve);
    event AppPaused(uint256 indexed appId, bool paused);
    event GovernanceTransferred(address indexed oldGov, address indexed newGov);
    event AppFactoryUpdated(address indexed oldFactory, address indexed newFactory);

    function getApp(uint256 appId) external view returns (AppInfo memory);
    function ownerSafeOf(uint256 appId) external view returns (address);
    function contributorSplitOf(uint256 appId) external view returns (address);

    function appFactory() external view returns (address);
    function governance() external view returns (address);

    // Governance-only
    function setPaused(uint256 appId, bool paused) external;
    function setAppFactory(address newFactory) external;
    function transferGovernance(address newGovernance) external;

    // App ownerSafe-only
    function setOwnerSafe(uint256 appId, address newOwnerSafe) external;
    function setMetadataURI(uint256 appId, string calldata newURI) external;
    function setContributorSplit(uint256 appId, address newContributorSplit) external;

    // AppFactory-only
    function registerApp(uint256 appId, address ownerSafe, address contributorSplit, string calldata metadataURI)
        external;
    function setTokenAndCurve(uint256 appId, address appToken, address bondingCurve) external;
}

