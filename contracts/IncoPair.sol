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

    euint64 public eReserve0;
    euint64 public eReserve1;

    uint256 public constant batchSwapThreshold = 5;
    uint256 public swapCounter = 0;
    bool public lock = false;
    euint64 public eCumulativeToken0;
    euint64 public eCumulativeToken1;
    mapping(address => euint64) public eUserCumulativeToken0;
    mapping(address => euint64) public eUserCumulativeToken1;
    address[] public swapUsers;

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

        eReserve0 = TFHE.add(eReserve0, token0Amount);
        eReserve1 = TFHE.add(eReserve1, token1Amount);

        ebool isTotalSupplyZero = TFHE.eq(_totalSupply, TFHE.asEuint64(0));

        // if totalSupply = 0
        euint64 liquidityIfZero = TFHE.mul(token0Amount, token1Amount);

        // TODO: apply proper math here
        euint64 liquidityIfAmount0 = token0Amount;
        euint64 liquidityIfAmount1 = token1Amount;

        euint64 liquidityIfNotZero = TFHE.min(
            liquidityIfAmount0,
            liquidityIfAmount1
        );

        // mint lp token to msg sender
        euint64 liquidity = TFHE.select(
            isTotalSupplyZero,
            liquidityIfZero,
            liquidityIfNotZero
        );
        _mint(liquidity);
    }

    // remove liquidity
    function removeLiquidity(
        einput _toBurnInput,
        bytes calldata inputProof
    ) public {
        euint64 toBurn = TFHE.asEuint64(_toBurnInput, inputProof);
        _burn(toBurn);

        // TODO: to calculate how to return appropriate amount of tokens back to the user
    }

    function mockAddLiquidity(
        einput _addToken0Amount,
        bytes calldata inputProof0,
        einput _addToken1Amount,
        bytes calldata inputProof1
    ) public {
        euint64 token0Amount = TFHE.asEuint64(_addToken0Amount, inputProof0);
        euint64 token1Amount = TFHE.asEuint64(_addToken1Amount, inputProof1);
        eReserve0 = token0Amount;
        eReserve1 = token1Amount;
    }

    // swap
    // TODOs: add TFHE.allow()
    function preSwap(
        einput _amount0In,
        bytes calldata input0Proof,
        einput _amount1In,
        bytes calldata input1Proof
    ) public {
        require(lock == false);
        euint64 eAmount0In = TFHE.asEuint64(_amount0In, input0Proof);
        euint64 eAmount1In = TFHE.asEuint64(_amount1In, input1Proof);

        eUserCumulativeToken0[msg.sender] = TFHE.add(
            eUserCumulativeToken0[msg.sender],
            eAmount0In
        );
        eUserCumulativeToken1[msg.sender] = TFHE.add(
            eUserCumulativeToken1[msg.sender],
            eAmount1In
        );
        eCumulativeToken0 = TFHE.add(eCumulativeToken0, eAmount0In);
        eCumulativeToken1 = TFHE.add(eCumulativeToken1, eAmount1In);

        swapUsers.push(msg.sender);

        swapCounter++;
    }

    function triggerSwap() public returns (uint256) {
        lock = true;
        require(swapCounter >= batchSwapThreshold);
        uint256[] memory cts = new uint256[](4);
        // eReserve0, eReserve1, ecumulativeAmountIn0, ecumulativeAmountIn1
        cts[0] = Gateway.toUint256(eReserve0);
        cts[1] = Gateway.toUint256(eReserve1);
        cts[2] = Gateway.toUint256(eCumulativeToken0);
        cts[3] = Gateway.toUint256(eCumulativeToken1);

        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.executeSwap.selector,
            0,
            block.timestamp + 100,
            false
        );

        swapCounter = 0;
        return requestId;
    }

    function executeSwap(
        uint256 requestId,
        uint256 reserve0,
        uint256 reserve1,
        uint256 cumulativeToken0,
        uint256 cumulativeToken1
    ) public onlyGateway returns (bool) {
        lock = false;

        // calculate amoutToken1Out from amountToken0In
        uint256 amountToken1Out = getAmountOut(
            cumulativeToken0,
            reserve0,
            reserve1
        );

        // update reserve0 and reserve1
        reserve0 += cumulativeToken0;
        reserve1 -= amountToken1Out;

        // calculate amoutToken0Out from amountToken1In
        uint256 amountToken0Out = getAmountOut(
            cumulativeToken1,
            reserve1,
            reserve0
        );

        reserve0 -= amountToken0Out;
        reserve1 += cumulativeToken1;

        // update eReserve0 and eReserve1
        eReserve0 = TFHE.asEuint64(reserve0);
        eReserve1 = TFHE.asEuint64(reserve1);

        // distribute
        for (uint i = 0; i < swapUsers.length; i++) {
            address swapUser = swapUsers[0];
            euint64 userToken0 = TFHE.mul(
                TFHE.asEuint64(amountToken0Out),
                TFHE.div(
                    eUserCumulativeToken0[swapUser],
                    uint8(cumulativeToken0)
                )
            );
            euint64 userToken1 = TFHE.mul(
                TFHE.asEuint64(amountToken1Out),
                TFHE.div(
                    eUserCumulativeToken1[swapUser],
                    uint8(cumulativeToken1)
                )
            );
            token0.transfer(swapUser, userToken0);
            token1.transfer(swapUser, userToken1);

            eUserCumulativeToken0[swapUser] = TFHE.asEuint64(0);
            eUserCumulativeToken1[swapUser] = TFHE.asEuint64(0);

            // set counter, ecumulativeAmountIn0, ecumulativeAmountIn1, users ecumulativeAmountIn0, users ecumulativeAmountIn1 to Zero
        }

        swapCounter = 0;
        eCumulativeToken0 = TFHE.asEuint64(0);
        eCumulativeToken1 = TFHE.asEuint64(0);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 numerator = amountIn * reserveOut;
        uint256 denominator = reserveIn + amountIn;
        amountOut = numerator / denominator;

        return amountOut;
    }
}
