#!/usr/bin/env python3
"""
Bonding Curve Reference Implementation for Differential Testing

This Python script provides a reference implementation of the Elata bonding curve
math for comparison against the Solidity implementation via FFI.

Usage:
    python bonding_curve_reference.py <function> <args...>
    
Functions:
    tokens_out <elta_in> <reserve_elta> <reserve_token>
    elta_in <tokens_desired> <reserve_elta> <reserve_token>
    price <reserve_elta> <reserve_token>
"""

import sys
from decimal import Decimal, getcontext

# Set high precision for calculations
getcontext().prec = 78  # Match Solidity uint256 precision


def get_tokens_out(elta_in: int, reserve_elta: int, reserve_token: int) -> int:
    """
    Calculate tokens out for a given ELTA input using constant product formula.
    
    Constant product: x * y = k
    newX = x + eltaIn
    newY = k / newX
    tokensOut = y - newY
    
    Args:
        elta_in: Amount of ELTA to spend
        reserve_elta: Current ELTA reserve (x)
        reserve_token: Current token reserve (y)
    
    Returns:
        Amount of tokens received
    """
    if elta_in == 0 or reserve_elta == 0 or reserve_token == 0:
        return 0
    
    # Use Decimal for high precision
    k = Decimal(reserve_elta) * Decimal(reserve_token)
    new_reserve_elta = Decimal(reserve_elta) + Decimal(elta_in)
    new_reserve_token = k // new_reserve_elta  # Integer division like Solidity
    
    tokens_out = reserve_token - int(new_reserve_token)
    return max(0, tokens_out)


def get_elta_in_for_tokens(tokens_desired: int, reserve_elta: int, reserve_token: int) -> int:
    """
    Calculate ELTA needed for desired token amount.
    
    Inverse of constant product formula:
    k = x * y
    newY = y - tokensDesired
    newX = k / newY
    eltaIn = newX - x
    
    Args:
        tokens_desired: Amount of tokens desired
        reserve_elta: Current ELTA reserve (x)
        reserve_token: Current token reserve (y)
    
    Returns:
        Amount of ELTA needed
    """
    if tokens_desired == 0 or reserve_elta == 0 or reserve_token == 0:
        return 0
    
    if tokens_desired >= reserve_token:
        # Can't buy more than reserve
        return 2**256 - 1  # Max uint256
    
    k = Decimal(reserve_elta) * Decimal(reserve_token)
    new_reserve_token = Decimal(reserve_token) - Decimal(tokens_desired)
    new_reserve_elta = k // new_reserve_token  # Integer division
    
    # Add 1 for rounding up (to ensure we get at least the desired tokens)
    elta_in = int(new_reserve_elta) - reserve_elta + 1
    return max(0, elta_in)


def get_current_price(reserve_elta: int, reserve_token: int) -> int:
    """
    Calculate current marginal price.
    
    Price = x/y scaled by 1e18
    
    Args:
        reserve_elta: Current ELTA reserve (x)
        reserve_token: Current token reserve (y)
    
    Returns:
        Price scaled by 1e18
    """
    if reserve_token == 0:
        return 0
    
    # Price = (reserveElta * 1e18) / reserveToken
    price = (reserve_elta * 10**18) // reserve_token
    return price


def get_k(reserve_elta: int, reserve_token: int) -> int:
    """
    Calculate constant product k.
    
    Args:
        reserve_elta: Current ELTA reserve (x)
        reserve_token: Current token reserve (y)
    
    Returns:
        k = x * y
    """
    return reserve_elta * reserve_token


def simulate_buy(elta_in: int, reserve_elta: int, reserve_token: int) -> tuple:
    """
    Simulate a buy and return new reserves.
    
    Returns:
        (tokens_out, new_reserve_elta, new_reserve_token)
    """
    tokens_out = get_tokens_out(elta_in, reserve_elta, reserve_token)
    new_reserve_elta = reserve_elta + elta_in
    new_reserve_token = reserve_token - tokens_out
    return (tokens_out, new_reserve_elta, new_reserve_token)


def main():
    if len(sys.argv) < 2:
        print("Usage: python bonding_curve_reference.py <function> <args...>", file=sys.stderr)
        sys.exit(1)
    
    function = sys.argv[1]
    
    try:
        if function == "tokens_out":
            if len(sys.argv) != 5:
                print("Usage: tokens_out <elta_in> <reserve_elta> <reserve_token>", file=sys.stderr)
                sys.exit(1)
            elta_in = int(sys.argv[2])
            reserve_elta = int(sys.argv[3])
            reserve_token = int(sys.argv[4])
            result = get_tokens_out(elta_in, reserve_elta, reserve_token)
            # Output as hex for easy parsing in Solidity
            print(hex(result))
        
        elif function == "elta_in":
            if len(sys.argv) != 5:
                print("Usage: elta_in <tokens_desired> <reserve_elta> <reserve_token>", file=sys.stderr)
                sys.exit(1)
            tokens_desired = int(sys.argv[2])
            reserve_elta = int(sys.argv[3])
            reserve_token = int(sys.argv[4])
            result = get_elta_in_for_tokens(tokens_desired, reserve_elta, reserve_token)
            print(hex(result))
        
        elif function == "price":
            if len(sys.argv) != 4:
                print("Usage: price <reserve_elta> <reserve_token>", file=sys.stderr)
                sys.exit(1)
            reserve_elta = int(sys.argv[2])
            reserve_token = int(sys.argv[3])
            result = get_current_price(reserve_elta, reserve_token)
            print(hex(result))
        
        elif function == "k":
            if len(sys.argv) != 4:
                print("Usage: k <reserve_elta> <reserve_token>", file=sys.stderr)
                sys.exit(1)
            reserve_elta = int(sys.argv[2])
            reserve_token = int(sys.argv[3])
            result = get_k(reserve_elta, reserve_token)
            print(hex(result))
        
        elif function == "simulate_buy":
            if len(sys.argv) != 5:
                print("Usage: simulate_buy <elta_in> <reserve_elta> <reserve_token>", file=sys.stderr)
                sys.exit(1)
            elta_in = int(sys.argv[2])
            reserve_elta = int(sys.argv[3])
            reserve_token = int(sys.argv[4])
            tokens_out, new_x, new_y = simulate_buy(elta_in, reserve_elta, reserve_token)
            # Output as ABI-encoded tuple (each value as 32-byte hex)
            print(hex(tokens_out).zfill(66))  # Pad to 32 bytes
            print(hex(new_x).zfill(66))
            print(hex(new_y).zfill(66))
        
        else:
            print(f"Unknown function: {function}", file=sys.stderr)
            sys.exit(1)
    
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
