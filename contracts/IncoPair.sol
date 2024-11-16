// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import "fhevm/gateway/GatewayCaller.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./interfaces/IConfidentialERC20.sol";
import "./ConfidentialERC20.sol";

contract IncoPair is GatewayCaller, ConfidentialERC20 {
    IConfidentialERC20 public immutable token0;
    IConfidentialERC20 public immutable token1;

    euint64 public reserve0;
    euint64 public reserve1;

    constructor(IConfidentialERC20 _token0, IConfidentialERC20 _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    /**
     * Naively adding to reserve0 and reserve1
     * send LP token to sender
     */
    function addLiquidity(
        einput _addToken0Amount,
        bytes calldata inputProof0,
        einput _addToken1Amount,
        bytes calldata inputProof1
    ) public {
        address sender = msg.sender;
        euint64 token0Amount = TFHE.asEuint64(_addToken0Amount, inputProof0);
        euint64 token1Amount = TFHE.asEuint64(_addToken1Amount, inputProof1);

        // transfer token0 and token1 to this contract from sender
        token0.transferFrom(sender, address(this), token0Amount);
        token1.transferFrom(sender, address(this), token1Amount);

        reserve0 = TFHE.add(reserve0, token0Amount);
        reserve1 = TFHE.add(reserve1, token1Amount);
    }
    // remove liquidity

    // swap
}
