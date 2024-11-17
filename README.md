## How our  swap works

Due to the limitation of the TFHE’s `div` function of which it only allows division by plaintext, a naive implementation of AMM’s bonding curve algorithm cannot be implemented directly. 

As such, we take a novel approach in providing an alternative solution at implementing the `swap` function. 

We take a three step approach instead of the traditional single step swap approach in traditional AMMs of which a single swap function is splitted into `preswap` ,`triggerSwap` and finally `executeSwap` 

The idea of our approach to `swap` will be to batch multiple swap transactions and to only perform the AMM calculation once. By doing so, we are able to ‘mix’ the inputs and outputs of a swap across a few transactions. ie. Should Alice and Bob swapped for 1usdc and 5usdc for Eth respectively, we will take the grand sum of inputs which is 6usdc to be the token in into the AMM calculation. Let’s say the token out in this case be 18eth for example, this 18eth can be shared by Alice and Bob in correspondent to their token in. As a result, Alice will receive 3eth and Bob will receive 15Eth

The `preSwap` stage will attempt to gather user’s swap intent. Storing the tokenIn as maps to the users address as `euint64` which is an encrypted value. At this stage, No one is able to know how much token the user is intending to swap

Once a certain batch threshold is reached, the `triggerSwap` function can be called. `triggerSwap` will request for a global decrypt on the reserves of token0 and token1 of the pool. This value will be used as the denominator of our bonding curve calculation.

Once the calculation is done by Inco’s MPC network, a callback will be initiate to the `executeSwap` function. `executeSwap` will contain the bonding curve calculation and finally distribute the tokenOuts to each users in corresponding to the user’s tokenIns value
