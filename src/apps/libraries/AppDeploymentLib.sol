// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Router02 } from "../../interfaces/IUniswapV2Router02.sol";
import { IAppFeeRouter } from "../../interfaces/IAppFeeRouter.sol";
import { AppToken } from "../AppToken.sol";
import { AppBondingCurve } from "../AppBondingCurve.sol";
import { AppStakingVault } from "../AppStakingVault.sol";

/**
 * @title AppDeploymentLib
 * @notice Library for deploying app tokens, vaults, and bonding curves
 * @dev Extracted from AppFactory to reduce contract size
 *
 * Features:
 * - Deploys token, vault, and bonding curve in one call
 * - Creator receives 50% of supply auto-staked in vault
 * - Remaining 50% goes to bonding curve for public sale
 * - Uses struct pattern to avoid stack too deep errors
 */
library AppDeploymentLib {
    struct DeploymentParams {
        string name;
        string symbol;
        uint8 decimals;
        uint256 tokenSupply;
        address creator;
        address factory;
        uint256 appId;
        IERC20 elta;
        IUniswapV2Router02 router;
        uint256 targetRaised;
        uint256 lpLockDuration;
        address treasury;
        uint256 protocolFeeRate;
        IAppFeeRouter appFeeRouter;
        uint256 seedElta;
    }

    /**
     * @notice Deploy token, vault, curve, and initialize with auto-stake
     * @param params Deployment parameters struct
     * @return tokenAddr Deployed token address
     * @return vaultAddr Deployed vault address
     * @return curveAddr Deployed curve address
     */
    function deployTokenVaultAndCurve(DeploymentParams calldata params)
        external
        returns (address tokenAddr, address vaultAddr, address curveAddr)
    {
        // 1) Deploy token
        tokenAddr = _deployToken(params);

        // 2) Deploy vault
        vaultAddr = _deployVault(params, tokenAddr);

        // 3) Deploy curve
        curveAddr = _deployCurve(params, tokenAddr);

        // 4) Mint & configure
        _mintAndConfigure(params, tokenAddr, curveAddr);
    }

    function _deployToken(DeploymentParams calldata params) private returns (address) {
        AppToken token = new AppToken(
            params.name,
            params.symbol,
            params.decimals,
            params.tokenSupply,
            params.creator,
            params.factory
        );
        return address(token);
    }

    function _deployVault(DeploymentParams calldata params, address tokenAddr)
        private
        returns (address)
    {
        AppStakingVault vault =
            new AppStakingVault(params.name, params.symbol, IERC20(tokenAddr), params.factory);
        return address(vault);
    }

    function _deployCurve(DeploymentParams calldata params, address tokenAddr)
        private
        returns (address)
    {
        AppToken token = AppToken(tokenAddr);
        AppBondingCurve curve = new AppBondingCurve(
            params.appId,
            params.factory,
            params.elta,
            token,
            params.router,
            params.targetRaised,
            params.lpLockDuration,
            params.creator,
            params.treasury,
            params.protocolFeeRate,
            params.appFeeRouter
        );
        return address(curve);
    }

    function _mintAndConfigure(
        DeploymentParams calldata params,
        address tokenAddr,
        address curveAddr
    ) private {
        AppToken token = AppToken(tokenAddr);

        // Calculate shares
        uint256 creatorShare = params.tokenSupply / 2;
        uint256 curveShare = params.tokenSupply - creatorShare;

        // Mint tokens
        token.mint(params.factory, creatorShare);
        token.mint(curveAddr, curveShare);

        // Finalize permissions
        token.revokeMinter(params.factory);
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), params.creator);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), params.factory);

        // Initialize curve
        require(params.elta.transfer(curveAddr, params.seedElta), "Transfer failed");
        AppBondingCurve(curveAddr).initializeCurve(params.seedElta, curveShare);
    }
}
