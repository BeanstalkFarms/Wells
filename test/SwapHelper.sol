// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {TestHelper, IERC20, Balances, Call, MockToken, Well, console, Snapshot} from "test/TestHelper.sol";
import {MockFunctionBad} from "mocks/functions/MockFunctionBad.sol";
import {IWellFunction} from "src/interfaces/IWellFunction.sol";

/**
 * @dev Stores the expected change in balance for User & Well throughout a Swap.
 *
 * Gives upstream tests a way to specify expected changes based on the presence
 * of transfer fees. When a token involved in a swap incurs a fee on transfer,
 * one or both of the following is true:
 *
 *  `wellReceives` < `userSpends`
 *  `userReceives` < `wellSends`
 */
struct SwapAction {
    uint i; // input token index
    uint j; // output token index
    uint userSpends;
    uint wellReceives;
    uint wellSends;
    uint userReceives;
}

/**
 * @dev Provides common assertions when testing Swaps.
 *
 * NOTE: Uses globals inherited from TestHelper.
 */
contract SwapHelper is TestHelper {
    event AddLiquidity(uint[] amounts, uint lpAmountOut, address recipient);
    event Swap(IERC20 fromToken, IERC20 toToken, uint amountIn, uint amountOut, address recipient);

    /// @dev Default Swap behavior assuming zero fee on transfer
    function beforeSwapFrom(uint i, uint j, uint amountIn) internal returns (Snapshot memory, SwapAction memory) {
        SwapAction memory act;

        act.i = i;
        act.j = j;
        act.userSpends = amountIn;
        act.wellReceives = amountIn;
        act.wellSends = well.getSwapOut(tokens[i], tokens[j], amountIn);
        act.userReceives = act.wellSends;

        return beforeSwapFrom(act);
    }

    function beforeSwapFrom(SwapAction memory act) internal returns (Snapshot memory, SwapAction memory) {
        Snapshot memory bef = _newSnapshot();

        vm.expectEmit(true, true, true, true, address(well));
        emit Swap(tokens[act.i], tokens[act.j], act.wellReceives, act.wellSends, user);

        return (bef, act);
    }

    function afterSwapFrom(Snapshot memory bef, SwapAction memory act) public {
        Snapshot memory aft = _newSnapshot();
        uint i = act.i;
        uint j = act.j;

        // Check balances accounting
        assertEq(bef.user.tokens[i] - aft.user.tokens[i], act.userSpends, "Incorrect token[i] User balance");
        assertEq(aft.well.tokens[i], bef.well.tokens[i] + act.wellReceives, "Incorrect token[i] Well balance");
        assertEq(aft.well.tokens[j], bef.well.tokens[j] - act.wellSends, "Incorrect token[j] Well balance");
        assertEq(aft.user.tokens[j] - bef.user.tokens[j], act.userReceives, "Incorrect token[j] User balance");

        // Check that reserves were updated
        uint[] memory reserves = well.getReserves();
        assertEq(aft.reserves[i], bef.reserves[i] + act.wellReceives, "Incorrect token[i] Well reserve");
        assertEq(aft.reserves[j], bef.reserves[i] - act.wellSends, "Incorrect token[i] Well reserve");

        // Check that no other balances or reserves were changed
        for (uint k = 0; k < reserves.length; ++k) {
            if (k == i || k == j) continue;
            assertEq(aft.well.tokens[k], bef.well.tokens[k], "token[k] Well balance changed unexpectedly");
            assertEq(aft.reserves[k], bef.reserves[k], "token[k] Well reserve changed unexpectedly");
        }
    }
}
