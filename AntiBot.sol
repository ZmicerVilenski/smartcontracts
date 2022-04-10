// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AntiBot is Ownable {
    bool private _initialized;
    bool private _restrictionActive;
    uint256 private _tradingStart;
    uint256 private _maxTransferAmount;
    uint256 private constant _txDelay = 50;
    mapping(address => uint256) private _previousTx;
    mapping(address => bool) public isWhitelisted;

    event TradingTimeChanged(uint256 tradingTime);
    event RestrictionActiveChanged(bool active);
    event MaxTransferAmountChanged(uint256 maxTransferAmount);
    event Whitelisted(address indexed account, bool isWhitelisted);

    function initAntibot(uint256 tradingStart, uint256 maxTransferAmount)
        external
        onlyOwner
    {
        require(!_initialized, "AntiBot: Already initialized");
        _initialized = true;
        _restrictionActive = true;
        _tradingStart = tradingStart;
        _maxTransferAmount = maxTransferAmount;
        isWhitelisted[owner()] = true;

        emit RestrictionActiveChanged(_restrictionActive);
        emit TradingTimeChanged(_tradingStart);
        emit MaxTransferAmountChanged(_maxTransferAmount);
        emit Whitelisted(owner(), true);
    }

    function setTradingStart(uint256 time) external onlyOwner {
        require(_tradingStart > block.timestamp, "AntiBot: To late");
        _tradingStart = time;
        emit TradingTimeChanged(_tradingStart);
    }

    function setMaxTransferAmount(uint256 amount) external onlyOwner {
        _maxTransferAmount = amount;
        emit MaxTransferAmountChanged(_maxTransferAmount);
    }

    function setRestrictionActive(bool active) external onlyOwner {
        _restrictionActive = active;
        emit RestrictionActiveChanged(_restrictionActive);
    }

    function addToWhitelist(address account, bool whitelisted)
        external
        onlyOwner
    {
        require(account != address(0), "Zero address");
        isWhitelisted[account] = whitelisted;
        emit MarkedWhitelisted(account, whitelisted);
    }

    modifier antiBot(
        address sender,
        address recipient,
        uint256 amount
    ) {
        if (
            _restrictionActive &&
            !isWhitelisted[recipient] &&
            !isWhitelisted[sender]
        ) {
            require(
                block.timestamp >= _tradingStart,
                "AntiBot: Transfers disabled"
            );

            if (_maxTransferAmount > 0) {
                require(
                    amount <= _maxTransferAmount,
                    "AntiBot: Limit exceeded"
                );
            }

            require(
                _previousTx[recipient] + _txDelay <= block.timestamp,
                "AntiBot: 50 sec/tx allowed"
            );
            _previousTx[recipient] = block.timestamp;

            require(
                _previousTx[sender] + _txDelay <= block.timestamp,
                "AntiBot: 50 sec/tx allowed"
            );
            _previousTx[sender] = block.timestamp;
        }
        _;
    }
}
