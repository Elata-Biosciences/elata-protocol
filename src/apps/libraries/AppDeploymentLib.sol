// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from "../../interfaces/IUniswapV2Router02.sol";
import {AppToken} from "../AppToken.sol";
import {AppBondingCurve} from "../AppBondingCurve.sol";

/**
 * @title AppDeploymentLib
 * @notice Library for deploying app tokens and bonding curves
 * @dev Extracted from AppFactory to reduce contract size
 */
library AppDeploymentLib {
    /**
     * @notice Deploy token, curve, and initialize
     * @return tokenAddr Deployed token address
     * @return curveAddr Deployed curve address
     */
    function deployTokenAndCurve(
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
        uint256 seedElta
    ) external returns (address tokenAddr, address curveAddr) {
        // Deploy token
        AppToken token = new AppToken(name, symbol, decimals, tokenSupply, creator, factory);
        tokenAddr = address(token);
        
        // Deploy curve
        AppBondingCurve curve = new AppBondingCurve(
            appId, factory, elta, token, router,
            targetRaised, lpLockDuration, treasury, treasury, protocolFeeRate
        );
        curveAddr = address(curve);
        
        // Mint & configure
        uint256 creatorAmt = tokenSupply / 10;
        token.mint(creator, creatorAmt);
        token.mint(curveAddr, tokenSupply - creatorAmt);
        token.revokeMinter(factory);
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), creator);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), factory);
        
        // Initialize curve
        require(elta.transfer(curveAddr, seedElta), "Transfer failed");
        curve.initializeCurve(seedElta, tokenSupply - creatorAmt);
    }
}

