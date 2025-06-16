The fundamental idea is to create a system where users can deposit an underlying asset (for example, ETH or a stablecoin like WETH) into a central smart contract, which we'll refer to as the `Vault`. In exchange for their deposit, users receive `rebase tokens`. These `rebase tokens` are special; they represent the user's proportional share of the total underlying assets held within the `Vault`, including any interest or rewards that accrue over time.

### Understanding Rebase Token Mechanics

The defining characteristic of a rebase token is how its supply adjusts, directly impacting a holder's balance.

* **Dynamic Balances:** The `balanceOf(address user)` function, a standard ERC20 view function, will be designed to return a *dynamic* value. This means that when a user queries their balance, it will appear to increase over time, reflecting their share of accrued interest or rewards. In our specific implementation, this increase will be calculated *linearly* with time.

* **`balanceOf`** **is a View Function (Gas Efficiency):** It's crucial to understand that the `balanceOf` function *shows* the user's current theoretical balance, including dynamically calculated interest. However, calling `balanceOf` itself does *not* execute a state-changing transaction on the blockchain. It doesn't mint new tokens with every call, as that would incur gas costs for simply viewing a balance. This design is critical for gas efficiency.

* **State Update on Interaction:** The actual *minting* of the accrued interest (i.e., updating the user's on-chain token amount) will occur strategically *before* a user performs any state-changing action with their tokens. These actions include:

  * Depositing more underlying assets (minting more rebase tokens).

  * Withdrawing/redeeming their underlying assets (burning rebase tokens).

  * Transferring their rebase tokens to another address.

  * (In the future) Bridging their tokens to another chain.

  The mechanism works as follows: When a user initiates one of these actions, the contract will first check the time elapsed since their last interaction. It then calculates the interest accrued to that user during this period, based on their specific interest rate (more on this below). These newly calculated interest tokens are then *minted* to the user's recorded balance *on-chain*. Only *after* this balance update does the contract proceed to execute the user's original requested action (e.g., transfer, burn) with their now up-to-date balance.
## Illustrating the Interest Rate Flow

Let's visualize how this interest rate mechanism plays out for different users at different times:

1. **Initial User Deposit (User 1):**

   * `User 1` deposits ETH into the `Vault Contract`.

   * The `Vault Contract` communicates with the `Rebase Token` contract.

   * Let's assume the `Rebase Token` contract currently has its `globalInterestRate` set to 0.05 (or 5%).

   * The `Rebase Token` contract records that `User 1's Interest Rate` is 0.05. This rate is now locked in for User 1's initial deposit.

   * The `Vault Contract` mints and sends the corresponding amount of `rebase tokens` to `User 1`.

2. **Owner Adjusts Global Rate:**

   * Sometime later, an `Owner` (or governance) interacts with the `Rebase Token` contract.

   * The `Owner` decides to *decrease* the `globalInterestRate`, for example, from 0.05 down to 0.04 (4%).

3. **New User Deposit (User 2):**

   * Now, `User 2` decides to deposit ETH into the `Vault Contract`.

   * The `Vault Contract` again communicates with the `Rebase Token` contract.

   * The `Rebase Token` contract's `globalInterestRate` is now 0.04.

   * The `Rebase Token` contract records that `User 2's Interest Rate` is 0.04. This is User 2's locked-in rate.

   * The `Vault Contract` mints and sends `rebase tokens` to `User 2`.

4. **Outcome and Further Rate Adjustments:**

   * As time progresses, `User 1` will continue to accrue interest based on their higher, locked-in rate of 0.05.

   * `User 2`, having deposited later, will accrue interest based on their lower, locked-in rate of 0.04. This clearly demonstrates the early adopter incentive.

   * If the `Owner` were to decrease the `globalInterestRate` again, say to 0.02, it would not affect the already locked-in rates for `User 1` (still 0.05) or `User 2` (still 0.04). Any new depositors after this change would receive the 0.02 rate.
