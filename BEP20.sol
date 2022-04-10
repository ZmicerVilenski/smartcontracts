// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./AntiBot.sol";

contract BEP20 is ERC20, Ownable, TransactionThrottler {
    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {
        _mint(msg.sender, 1500000000 * 10**18);
    }

    function getOwner() external view returns (address) {
        return owner();
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override antiBot(sender, recipient, amount) {
        super._transfer(sender, recipient, amount);
    }
}
