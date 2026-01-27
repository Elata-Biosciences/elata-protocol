// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NetworkConfig
 * @notice Provides network-specific external contract addresses for deployment
 * @dev Centralized configuration for Uniswap, USDC, and WETH addresses per chain
 */
library NetworkConfig {
    struct Config {
        address uniswapV2Router;
        address uniswapV2Factory;
        address usdc;
        address weth;
        bool deployMocks; // true only for local development (Anvil)
    }

    /// @notice Returns the configuration for the current network
    /// @dev Reverts on unsupported networks to prevent accidental deployments
    function get() internal view returns (Config memory) {
        uint256 chainId = block.chainid;

        // Anvil / Local Development
        if (chainId == 31337) {
            return Config({
                uniswapV2Router: address(0),
                uniswapV2Factory: address(0),
                usdc: address(0),
                weth: address(0),
                deployMocks: true
            });
        }

        // Base Sepolia Testnet
        if (chainId == 84532) {
            return Config({
                uniswapV2Router: 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3,
                uniswapV2Factory: 0xF62c03E08ada871A0bEb309762E260a7a6a880E6,
                usdc: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,
                weth: 0x4200000000000000000000000000000000000006,
                deployMocks: false
            });
        }

        // Base Mainnet
        if (chainId == 8453) {
            return Config({
                uniswapV2Router: 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24,
                uniswapV2Factory: 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6,
                usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                weth: 0x4200000000000000000000000000000000000006,
                deployMocks: false
            });
        }

        // Ethereum Mainnet (for future use)
        if (chainId == 1) {
            return Config({
                uniswapV2Router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
                uniswapV2Factory: 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                deployMocks: false
            });
        }

        revert(string.concat("NetworkConfig: unsupported chainId ", _toString(chainId)));
    }

    /// @notice Returns true if the current network requires mock contracts
    function shouldDeployMocks() internal view returns (bool) {
        return get().deployMocks;
    }

    /// @notice Returns the network name for logging and file naming
    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;

        if (chainId == 1) return "mainnet";
        if (chainId == 5) return "goerli";
        if (chainId == 11155111) return "sepolia";
        if (chainId == 8453) return "base";
        if (chainId == 84531) return "base-goerli";
        if (chainId == 84532) return "base-sepolia";
        if (chainId == 31337) return "localhost";

        return "unknown";
    }

    /// @dev Simple uint to string conversion for error messages
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
