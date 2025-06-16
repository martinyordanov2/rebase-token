// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "lib/forge-std/src/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 immutable transferAmount = 2e18;

    function setUp() external {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    // Test if interest accrues linearly after a deposit.
    function testDepositLinear(uint256 amount) public {
        // Constrain the fuzzed 'amount' to a practical range.
        // Min: 0.00001 ETH (1e5 wei), Max: type(uint96).max to avoid overflows.
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        //deposit
        vm.deal(user, amount);
        vm.stopPrank();
        //check our rebase token balance
        //warp the time and check the balance again
        //warp the time again by the same amount and check the balance again
    }

    //test mint();
    function testMintFailsIfCalledByUnauthorizedRole() public {
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.mint(user, transferAmount);
        vm.stopPrank();
    }

    function testMintCanBeCalledByAuthorizedRole() public {
        vm.startPrank(address(vault));
        rebaseToken.mint(user, transferAmount);

        uint256 userBalance = rebaseToken.balanceOf(user);
        assertEq(userBalance, transferAmount);
        vm.stopPrank();
    }

    //test burn();
    function testBurnFailsIfCalledByUnauthorizedRole() public {
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.burn(user, transferAmount);
        vm.stopPrank();
    }

    function testBurnCanBeCalledByAuthorizedRole() public {
        vm.startPrank(address(vault));
        rebaseToken.mint(user, transferAmount);

        rebaseToken.burn(user, transferAmount);
        uint256 userBalance = rebaseToken.balanceOf(user);
        assertEq(userBalance, 0);
        vm.stopPrank();
    }
}
