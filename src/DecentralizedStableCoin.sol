// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Decentralized Stable Coin
 * @author Constantin Andrei Todirascu
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to EUR
 * 
 * This contract is ment to be governed by DSGEngine. This contract is just the ERC20 implementation of our stable coin system.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
     error DecentralizedStableCoin__MustBeMostThenZero();
     error DecentralizedStableCoin__BurnAmountExceedsBalance();
     error DecentralizedStableCoin__NotZeroAddress();

    constructor(address _owner) ERC20("DecentralizedStableCoin", "DSC") Ownable(_owner) {
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
          revert DecentralizedStableCoin__MustBeMostThenZero();
        }
        if (balance < _amount) {
          revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        _mint(_to, _amount);
        if (_amount <= 0) {
          revert DecentralizedStableCoin__MustBeMostThenZero();
        }
        if (_to == address(0)) {
          revert DecentralizedStableCoin__NotZeroAddress();
        }
        return true;
    }

}