// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Router02 } from "../../interfaces/IUniswapV2Router02.sol";
import { IAppFeeRouter } from "../../interfaces/IAppFeeRouter.sol";
import { AppToken } from "../AppToken.sol";
import { AppBondingCurve } from "../AppBondingCurve.sol";
import { AppStakingVault } from "../AppStakingVault.sol";

/**
 * @title AppDeploymentLib V2
 * @notice Library for deploying app tokens, vaults, and bonding curves
 * @dev Extracted from AppFactory to reduce contract size
 *
 * Changes from V1:
 * - Added vault deployment
 * - Creator share 10% → 50% (auto-staked)
 * - Added appFeeRouter parameter
 */
library AppDeploymentLib {
    /**
     * @notice Deploy token, vault, curve, and initialize with auto-stake
     * @return tokenAddr Deployed token address
     * @return vaultAddr Deployed vault address
     * @return curveAddr Deployed curve address
     */
    function deployTokenVaultAndCurve(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 tokenSupply,
        address creator,
        address factory,
        uint256 appId,
        IERC20 elta,
        IUniswapV2Router02 router,
        uint256 targetRaised,
        uint256 lpLockDuration,
        address treasury,
        uint256 protocolFeeRate,
        IAppFeeRouter appFeeRouter,
        uint256 seedElta
    ) external returns (address tokenAddr, address vaultAddr, address curveAddr) {
        // 1) Deploy token
        AppToken token = new AppToken(name, symbol, decimals, tokenSupply, creator, factory);
        tokenAddr = address(token);

        // 2) Deploy vault (must happen after token)
        AppStakingVault vault = new AppStakingVault(name, symbol, IERC20(tokenAddr), factory);
        vaultAddr = address(vault);

        // 3) Deploy curve (now with appFeeRouter)
        AppBondingCurve curve = new AppBondingCurve(
            appId,
            factory,
            elta,
            token,
            router,
            targetRaised,
            lpLockDuration,
            creator,
            treasury,
            protocolFeeRate,
            appFeeRouter
        );
        curveAddr = address(curve);

        // 4) Mint & split supply: 50% creator (auto-staked), 50% curve
        uint256 creatorShare = tokenSupply / 2; // 50%
        uint256 curveShare = tokenSupply - creatorShare;

        // Mint creator share to factory (will be staked below)
        token.mint(factory, creatorShare);

        // Mint curve share to curve
        token.mint(curveAddr, curveShare);

        // 5) Auto-stake creator share (factory stakes on behalf of creator)
        // NOTE: This requires factory to call vault.stakeFor() after deployment
        // Cannot do here because we're in a library call and don't have token approval

        // 6) Finalize token permissions
        token.revokeMinter(factory);
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), creator);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), factory);

        // 7) Vault ownership will be transferred by factory AFTER staking
        // Factory keeps ownership temporarily to call stakeFor()

        // 8) Initialize curve
        require(elta.transfer(curveAddr, seedElta), "Transfer failed");
        curve.initializeCurve(seedElta, curveShare);
    }
}
