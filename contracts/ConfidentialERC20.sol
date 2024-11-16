// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "fhevm/gateway/GatewayCaller.sol";

contract ConfidentialERC20 is Ownable2Step, GatewayCaller {
    // Events for Transfer, Approval, Mint, and Decryption
    event Transfer(address indexed from, address indexed to);
    event Approval(address indexed owner, address indexed spender);
    event Mint(address indexed to, uint64 amount);
    event UserBalanceDecrypted(address indexed user, uint64 decryptedAmount);

    uint64 public _totalSupply;
    string public _name;
    string public _symbol;
    uint8 public constant decimals = 6;

    // Mappings for balances and allowances
    mapping(address => euint64) internal balances;
    mapping(address => mapping(address => euint64)) internal allowances;

    // Constructor to set the token name, symbol, and owner
    constructor() Ownable(msg.sender) {
        _name = "Confidential USD";
        _symbol = "CUSD";
    }

    // Mint function to create tokens and add to the owner's balance
    function mint(uint64 mintedAmount) public virtual onlyOwner {
        balances[owner()] = TFHE.add(balances[owner()], mintedAmount);
        TFHE.allow(balances[owner()], address(this));
        TFHE.allow(balances[owner()], owner());
        _totalSupply += mintedAmount;
        emit Mint(owner(), mintedAmount);
    }

    // Overloaded _mint function to allow encrypted token minting
    function _mint(einput encryptedAmount, bytes calldata inputProof) public virtual onlyOwner {
        balances[msg.sender] = TFHE.add(balances[msg.sender], TFHE.asEuint64(encryptedAmount, inputProof));
        TFHE.allow(balances[msg.sender], address(this));
        TFHE.allow(balances[msg.sender], owner());
        TFHE.allow(balances[msg.sender], msg.sender);
    }

    // Transfer function for EOAs using encrypted inputs
    function transfer(address to, einput encryptedAmount, bytes calldata inputProof) public virtual returns (bool) {
        transfer(to, TFHE.asEuint64(encryptedAmount, inputProof));
        return true;
    }

    // Transfer function for contracts
    function transfer(address to, euint64 amount) public virtual returns (bool) {
        require(TFHE.isSenderAllowed(amount));
        ebool canTransfer = TFHE.le(amount, balances[msg.sender]);
        _transfer(msg.sender, to, amount, canTransfer);
        return true;
    }

    // Retrieves the balance handle of a specified wallet
    function balanceOf(address wallet) public view virtual returns (euint64) {
        return balances[wallet];
    }

    // Approve function for EOAs with encrypted inputs
    function approve(address spender, einput encryptedAmount, bytes calldata inputProof) public virtual returns (bool) {
        approve(spender, TFHE.asEuint64(encryptedAmount, inputProof));
        return true;
    }

    // Approve function for contracts
    function approve(address spender, euint64 amount) public virtual returns (bool) {
        require(TFHE.isSenderAllowed(amount));
        _approve(msg.sender, spender, amount);
        emit Approval(msg.sender, spender);
        return true;
    }

    // Retrieves the allowance handle for a spender
    function allowance(address owner, address spender) public view virtual returns (euint64) {
        return _allowance(owner, spender);
    }

    // TransferFrom function for EOAs with encrypted inputs
    function transferFrom(
        address from,
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (bool) {
        transferFrom(from, to, TFHE.asEuint64(encryptedAmount, inputProof));
        return true;
    }

    // TransferFrom function for contracts
    function transferFrom(address from, address to, euint64 amount) public virtual returns (bool) {
        require(TFHE.isSenderAllowed(amount));
        ebool isTransferable = _updateAllowance(from, msg.sender, amount);
        _transfer(from, to, amount, isTransferable);
        return true;
    }

    // Internal function to handle allowance approvals
    function _approve(address owner, address spender, euint64 amount) internal virtual {
        allowances[owner][spender] = amount;
        TFHE.allow(amount, address(this));
        TFHE.allow(amount, owner);
        TFHE.allow(amount, spender);
    }

    // Internal function to retrieve an allowance handle
    function _allowance(address owner, address spender) internal view virtual returns (euint64) {
        return allowances[owner][spender];
    }

    // Internal function to update an allowance securely
    function _updateAllowance(address owner, address spender, euint64 amount) internal virtual returns (ebool) {
        euint64 currentAllowance = _allowance(owner, spender);
        ebool allowedTransfer = TFHE.le(amount, currentAllowance);
        ebool canTransfer = TFHE.le(amount, balances[owner]);
        ebool isTransferable = TFHE.and(canTransfer, allowedTransfer);
        _approve(owner, spender, TFHE.select(isTransferable, TFHE.sub(currentAllowance, amount), currentAllowance));
        return isTransferable;
    }

    // Internal transfer function for encrypted token transfer
    function _transfer(address from, address to, euint64 amount, ebool isTransferable) internal virtual {
        euint64 transferValue = TFHE.select(isTransferable, amount, TFHE.asEuint64(0));
        euint64 newBalanceTo = TFHE.add(balances[to], transferValue);
        balances[to] = newBalanceTo;
        TFHE.allow(newBalanceTo, address(this));
        TFHE.allow(newBalanceTo, to);

        euint64 newBalanceFrom = TFHE.sub(balances[from], transferValue);
        balances[from] = newBalanceFrom;
        TFHE.allow(newBalanceFrom, address(this));
        TFHE.allow(newBalanceFrom, from);

        emit Transfer(from, to);
    }

    // Owner-only function to request decryption of a user's balance
    function requestUserBalanceDecryption(address user) public onlyOwner returns (uint256) {
        euint64 encryptedBalance = balances[user];
        TFHE.allow(encryptedBalance, address(this));

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(encryptedBalance);

        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.onDecryptionCallback.selector,
            0,
            block.timestamp + 100,
            false
        );
        addParamsAddress(requestId, user);
        return requestId;
    }

    // Callback function to handle decrypted balance for a user
    function onDecryptionCallback(uint256 requestId, uint64 decryptedAmount) public onlyGateway returns (bool) {
        address[] memory params = getParamsAddress(requestId);
        emit UserBalanceDecrypted(params[0], decryptedAmount);
        return true;
    }
}
