// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "lib/forge-std/src/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/access/AccessControl.sol";
import {MockFailedRedeem} from "test/mock/MockFailedRedeem.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");
    uint256 immutable transferAmount = 2e18;
    uint256 private newInterestRate = 4e10;

    function setUp() external {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    // User deposits 1 ETH and receives 1 rETH.
    // You (the owner or protocol) send an additional 1 ETH into the vault via addRewardstoVault().
    // Now, the vault has 2 ETH, but only 1 rETH in circulation.
    // When the user redeems 1 rETH, they get 2 ETH back → this simulates interest or yield.
    function addRewardstoVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    //test deposit(); Test if interest accrues linearly after a deposit.
    function testDepositLinear(uint256 amount) public {
        // Constrain the fuzzed 'amount' to a practical range.
        // Min: 0.00001 ETH (1e5 wei), Max: type(uint96).max to avoid overflows.
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        //deposit
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        //check our rebase token balance
        uint256 startingBalance = rebaseToken.balanceOf(user);
        console2.log(startingBalance);
        assertEq(startingBalance, amount);
        //warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startingBalance);
        //warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startingBalance, 1);
        vm.stopPrank();
    }

    //test redeem();
    function testRedeemFailsIfTransferReverts() public {
        MockFailedRedeem mockFailedRedeem = new MockFailedRedeem();
        vm.deal(address(vault), transferAmount);

        vm.startPrank(address(vault)); // Vault is the only one that can mint
        rebaseToken.mint(address(mockFailedRedeem), transferAmount, rebaseToken.getInterestRate());
        vm.stopPrank();

        vm.expectRevert(Vault.Vault__RedeemFailed.selector);
        vm.prank(address(mockFailedRedeem));
        vault.redeem(transferAmount);
    }

    function testUserCanRedeemNow(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        //note here we don't have to add rewards to the vault bcz we are redeeming right away
        vault.redeem(type(uint256).max); // get the full balance not just the amount
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertEq(endBalance, 0);
        vm.stopPrank();
    }

    function testUserCanRedeemAfterTime(uint256 amount, uint256 time) public {
        amount = bound(amount, 1e5, type(uint96).max);
        time = bound(time, 1000, type(uint96).max);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        vm.warp(block.timestamp + time);
        uint256 balanceAfterTime = rebaseToken.balanceOf(user);

        //add rewards to the vault
        vm.deal(owner, balanceAfterTime - amount);
        vm.prank(owner);
        addRewardstoVault(balanceAfterTime - amount);

        //redeem
        vm.prank(user);
        vault.redeem(type(uint256).max); //get the full balance not just the amount

        uint256 ethBalance = address(user).balance; //testing the final ETH balance of the user after redeeming, not their token balance.
        assertEq(ethBalance, balanceAfterTime);
        assertGt(ethBalance, amount);
    }

    //test transfer() & setInterestRate();
    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 balanceUser = rebaseToken.balanceOf(user);

        uint256 balanceUser2 = rebaseToken.balanceOf(user2);

        //changing the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(newInterestRate);

        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 balanceUserAfter = rebaseToken.balanceOf(user);
        uint256 balanceUser2After = rebaseToken.balanceOf(user2);

        assertEq(balanceUserAfter, balanceUser - amountToSend);
        assertEq(balanceUser2After, balanceUser2 + amountToSend);

        //check the user interest rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testTransferMaxAmountShouldSendFullBalance() public {
        uint256 initialAmount = 10 ether;

        // Mint tokens to the sender
        vm.startPrank(address(vault));
        rebaseToken.mint(user, initialAmount, rebaseToken.getInterestRate());
        vm.stopPrank();

        // Check balance before
        uint256 balanceBefore = rebaseToken.balanceOf(user);
        assertEq(balanceBefore, initialAmount);

        // Call transfer using type(uint256).max
        vm.prank(user);
        rebaseToken.transfer(user2, type(uint256).max); // This should transfer all user balance to owner

        // Check balances after
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);

        assertEq(userBalance, 0); // user should have 0
        assertEq(user2Balance, initialAmount); // user2 should get everything
    }

    function testInterestRateCanOnlyDecrease(uint256 interestRate) public {
        interestRate = bound(interestRate, rebaseToken.getInterestRate(), type(uint96).max);
        vm.prank(owner);

        vm.expectRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(interestRate);
    }

    function testOnlyOwnerCanChangeInterestRate() public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    //test transferFrom();
    function testTransferFromMaxAmountShouldSendFullBalance() public {
        // Mint tokens to the sender
        vm.startPrank(address(vault));
        rebaseToken.mint(user, transferAmount, rebaseToken.getInterestRate());
        vm.stopPrank();

        vm.prank(user);
        rebaseToken.approve(user2, type(uint256).max);

        // Check balance before
        uint256 balanceBefore = rebaseToken.balanceOf(user);
        assertEq(balanceBefore, transferAmount);

        // Call transfer using type(uint256).max
        vm.prank(user2);
        rebaseToken.transferFrom(user, user2, type(uint256).max);

        // Check balances after
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);

        assertEq(userBalance, 0); // user should have 0
        assertEq(user2Balance, transferAmount); // user2 should get everything
    }

    //test mint();
    function testMintFailsIfCalledByUnauthorizedRole() public {
        vm.startPrank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user, transferAmount, rebaseToken.getInterestRate());
        vm.stopPrank();
    }

    function testMintCanBeCalledByAuthorizedRole() public {
        vm.startPrank(address(vault));
        rebaseToken.mint(user, transferAmount, rebaseToken.getInterestRate());

        uint256 userBalance = rebaseToken.balanceOf(user);
        assertEq(userBalance, transferAmount);
        vm.stopPrank();
    }

    //test burn();
    function testBurnFailsIfCalledByUnauthorizedRole() public {
        vm.startPrank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, transferAmount);
        vm.stopPrank();
    }

    function testBurnCanBeCalledByAuthorizedRole() public {
        vm.startPrank(address(vault));
        rebaseToken.mint(user, transferAmount, rebaseToken.getInterestRate());

        rebaseToken.burn(user, transferAmount);
        uint256 userBalance = rebaseToken.balanceOf(user);
        assertEq(userBalance, 0);
        vm.stopPrank();
    }

    function testBurnMaximumAmount() public {
        // Mint tokens to the sender
        vm.startPrank(address(vault));
        rebaseToken.mint(user, transferAmount, rebaseToken.getInterestRate());

        // Check balance before
        uint256 balanceBefore = rebaseToken.balanceOf(user);
        assertEq(balanceBefore, transferAmount);

        rebaseToken.burn(user, type(uint256).max);

        // Check balances after
        uint256 userBalance = rebaseToken.balanceOf(user);
        vm.stopPrank();

        assertEq(userBalance, 0); // user should have 0
    }

    //test principleBalanceOf();
    function testGetPrincipleAmount() public {
        vm.deal(user, transferAmount);
        vm.prank(user);

        vault.deposit{value: transferAmount}();
        assertEq(rebaseToken.principleBalanceOf(user), transferAmount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principleBalanceOf(user), transferAmount);
    }

    //test getgetRebaseTokenAddress();
    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }
}
