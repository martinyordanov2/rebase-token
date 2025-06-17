// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/access/AccessControl.sol";

contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease();

    uint256 private constant PRECISION_FACTOR = 1e18; //this was changed because of truncation and simplicity to understand
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // 0,000000005 are added per second for 1 token ||
    mapping(address => uint256) private s_usersInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimeStamp;

    event InterestRateSet(uint256 oldInterestRate, uint256 _newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) AccessControl() {}

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // note the interest rate should only decrease
        if (_newInterestRate >= s_interestRate) {
            /// IF SOMETHING FAILS IT is BECAUSE I CHANGED IT
            revert RebaseToken__InterestRateCanOnlyDecrease();
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(s_interestRate, _newInterestRate);
    }

    //calculate the balance for the user including the interest that has accumulated since the last update:
    // (principle balance) + some interest that has accrued
    function balanceOf(address _user) public view override returns (uint256) {
        //get the current principle balance of the user (the number of tokens that have actually been minted to the user)
        //multiply the principle balance by the interest that has accumulated in the time since the balance was last updated
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR; // so we can get it back to 1e18
    }

    //Get the principle balance of the user. This is the number of tokens that have been currently minted by the user, not including any interest that has accrued since the last time the user interacted with the protocol.
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        if (_amount == type(uint256).max) {
            //dust check
            _amount = balanceOf(msg.sender);
        }
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        //if the user hasn't deposited or received any token previously they will inherit the interest rate
        if (balanceOf(_recipient) == 0) {
            s_usersInterestRate[_recipient] = s_usersInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        if (_amount == type(uint256).max) {
            //dust check
            _amount = balanceOf(_sender);
        }

        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        //if the user hasn't deposited or received any token previously, they will inherit the interest rate (design flaw)
        if (balanceOf(_recipient) == 0) {
            s_usersInterestRate[_recipient] = s_usersInterestRate[msg.sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to); // check if any interest is needed to be minted at the moment and we also AND set the last time we minted interest to them
        s_usersInterestRate[_to] = s_interestRate; //set the interest rate when a user mints
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // a standardized check to see if dust(leftover interest) is left when a user is redeeming their balance while waiting for their transaction to go through (latency/finality).
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        // Mints any existing interest that has accrued since the last time the user's balance was updated.
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    //mint the accrued interest to the user since the last time they interacted with the protococol. e.g. burn, mint, transfer etc...
    function _mintAccruedInterest(address _user) internal {
        // (1)find their current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2)calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set the users last updated timestamp
        s_userLastUpdatedTimeStamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    //calculate the interest that has accumulated since the last update
    //this is going to linear with time
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearIntrest)
    {
        //1. calculate the time since the last update
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimeStamp[_user];
        //2. calculate the amount of linear growth
        //principle amount + (principle amount + interest rate + time elapsed)
        //deposit 10 tokens, interest rate 0,5 tokens per second, time elapsed 2 seconds
        //10 + (10 * 0,5 * 2)
        //principle amount(1 + (user interest rate * time elapsed))
        linearIntrest = (PRECISION_FACTOR + (s_usersInterestRate[_user] * timeElapsed));

        //in the blockchain context 1ETH = 1e18
    }

    //Get the interest rate that is currently set for the contract. Any future depositors will receive this interest rate.
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    //Get the interest rate for the user
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_usersInterestRate[_user];
    }
    
}
