// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AppFactory } from "../src/apps/AppFactory.sol";
import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";

// Mock ELTA token for local development
contract MockELTA is ERC20 {
    constructor() ERC20("Elata Token", "ELTA") {
        // Mint 1M ELTA to deployer for testing
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock Uniswap V2 Router for local development
contract MockUniswapV2Router {
    address public factory;

    constructor() {
        factory = address(this); // Self as factory for simplicity
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Mock implementation - just return the desired amounts
        return (amountADesired, amountBDesired, amountADesired + amountBDesired);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOutMin;
        return amounts;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        // Simple 1:1 mock exchange rate
        amounts[path.length - 1] = amountIn;
        return amounts;
    }
}

// Mock Uniswap V2 Factory
contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // Create a simple mock pair address
        pair = address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB)))));
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        return pair;
    }
}

contract DeployLocal is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying to local network...");
        console.log("Deployer:", deployer);

        // Deploy mock ELTA token
        MockELTA elta = new MockELTA();
        console.log("Mock ELTA deployed at:", address(elta));

        // Deploy mock Uniswap contracts
        MockUniswapV2Factory uniFactory = new MockUniswapV2Factory();
        MockUniswapV2Router uniRouter = new MockUniswapV2Router();
        console.log("Mock Uniswap Factory deployed at:", address(uniFactory));
        console.log("Mock Uniswap Router deployed at:", address(uniRouter));

        // Deploy AppFactory
        AppFactory appFactory = new AppFactory(
            elta,
            IUniswapV2Router02(address(uniRouter)),
            deployer, // treasury
            deployer // admin
        );
        console.log("AppFactory deployed at:", address(appFactory));

        // Mint additional ELTA to some test accounts for easier testing
        address[] memory testAccounts = new address[](3);
        testAccounts[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil account #1
        testAccounts[1] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Anvil account #2
        testAccounts[2] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // Anvil account #3

        for (uint256 i = 0; i < testAccounts.length; i++) {
            elta.mint(testAccounts[i], 100_000 * 10 ** elta.decimals());
            console.log("Minted 100k ELTA to:", testAccounts[i]);
        }

        vm.stopBroadcast();

        // Log deployment info for frontend
        console.log("\n=== Deployment Complete ===");
        console.log("Network: Anvil (localhost:8545)");
        console.log("Chain ID: 31337");
        console.log("\nContract Addresses:");
        console.log("ELTA:", address(elta));
        console.log("AppFactory:", address(appFactory));
        console.log("UniswapV2Router:", address(uniRouter));
        console.log("\nUpdate your .env.local with these addresses:");
        console.log("NEXT_PUBLIC_ELTA_ADDRESS_LOCALHOST=%s", address(elta));
        console.log("NEXT_PUBLIC_APP_FACTORY_ADDRESS_LOCALHOST=%s", address(appFactory));
        console.log("NEXT_PUBLIC_UNISWAP_ROUTER_ADDRESS_LOCALHOST=%s", address(uniRouter));

        console.log("\nTest accounts with ELTA:");
        console.log("Deployer: %s (1M ELTA)", deployer);
        for (uint256 i = 0; i < testAccounts.length; i++) {
            console.log("Account %d: %s (100k ELTA)", i + 1, testAccounts[i]);
        }
    }
}
