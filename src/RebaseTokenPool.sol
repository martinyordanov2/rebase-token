// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@ccip/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from "@ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol"; //we cant use the openzeppelin one
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

// User wants to bridge 100 RebaseTokens from Chain A to Chain B
// Chain A pool burns the 100 tokens and captures user's 5% interest rate
// Cross-chain message carries: amount=100, userInterestRate=5%
// Chain B pool receives message and mints 100 tokens to user with 5% rate preserved

//The key challenge it solves is preserving each user's individual interest rate when tokens move between chains.
contract RebaseTokenPool is TokenPool {
    constructor(IERC20 _token, address[] memory _allowlist, address _rmnProxy, address _router)
        TokenPool(_token, 18, _allowlist, _rmnProxy, _router)
    {}
    
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut){
            //Validates the transfer using inherited validation logic
            _validateLockOrBurn(lockOrBurnIn);
            // Burn the tokens on the source chain. This returns their userAccumulatedInterest before the tokens were burned (in case all tokens were burned, we don't want to send 0 cross-chain)   
            uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
            //Burns the tokens from the pool's address (tokens are transferred to the pool first, then burned)
            IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);
            //Encodes the interest rate into destPoolData so it can be sent to the destination chain & returns the destination token address and the encoded user data
            lockOrBurnOut = Pool.LockOrBurnOutV1({
                destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
                destPoolData: abi.encode(userInterestRate)
            });
        }

    //Validates the incoming transfer
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory){
            _validateReleaseOrMint(releaseOrMintIn);
            //Decodes the user's interest rate from the source chain data
            uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
            //Mints new tokens to the recipient with their original interest rate preserved
            IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount, userInterestRate);
            //Returns the amount minted
            return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
        }
}
