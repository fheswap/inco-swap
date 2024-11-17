// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IConfidentialERC20 {
    function transferFrom(
        address from,
        address to,
        euint64 encryptedAmount
    ) external returns (bool);

    function transfer(address to, euint64 amount) external returns (bool);

    function _mint(euint64 amount) external;
}
