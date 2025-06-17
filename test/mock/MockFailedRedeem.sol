// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice A mock contract that intentionally rejects ETH transfers.
contract MockFailedRedeem {
    // Called when ETH is sent with no calldata
    receive() external payable {
        revert("Cannot accept ETH");
    }

    // Called when ETH is sent with calldata (fallback)
    fallback() external payable {
        revert("Cannot accept ETH");
    }
}
