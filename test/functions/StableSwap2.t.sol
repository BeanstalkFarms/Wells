/**
 * SPDX-License-Identifier: MIT
 **/
pragma solidity ^0.8.17;

import "test/TestHelper.sol";
import {WellFunctionHelper} from "./WellFunctionHelper.sol";
import "src/functions/StableSwap2.sol";
import "src/libraries/LibMath.sol";

/// @dev Tests the {StableSwap2} Well function directly.
contract StableSwap2Test is WellFunctionHelper {
    using LibMath for uint;

    /// State A: Same decimals
    uint STATE_A_B0 = 10 * 1e18;
    uint STATE_A_B1 = 10 * 1e18;
    uint STATE_A_LP = 632455532000000000000000;

    /// State B: Different decimals
    uint STATE_B_B0 = 1 * 1e18;
    uint STATE_B_B1 = 1250 * 1e6;
    uint STATE_B_LP = 316227765920888330820;

    /// State C: Similar decimals
    uint STATE_C_B0 = 20 * 1e18;
    uint STATE_C_B1 = 31250000000000000000; // 3.125e19
    uint STATE_C_LP = 1619725742782257883348752;

    //////////// SETUP ////////////

    function setUp() public {
        _function = new StableSwap2(3);
        _data = "";
    }

    function approxReserveCheck(uint a, uint b) public {
        assertApproxEqAbs(
            a,
            b,
            b / 100000
        );
    }

    function test_metadata() public {
        assertEq(_function.name(), "Stable Swap");
        assertEq(_function.symbol(), "SS");
    }

    //////////// LP TOKEN SUPPLY ////////////

    /// @dev calcLpTokenSupply: same decimals, manual calc for 2 equal reserves
    function test_getLpTokenSupply_sameDecimals() public {
        uint[] memory reserves = new uint[](2);
        reserves[0] = STATE_A_B0;
        reserves[1] = STATE_A_B1;

        assertEq(_function.calcLpTokenSupply(reserves, _data), STATE_A_LP);

        reserves[0] = STATE_C_B0;
        reserves[1] = STATE_C_B1;

        assertEq(_function.calcLpTokenSupply(reserves, _data), STATE_C_LP);
    }

    /// @dev calcLpTokenSupply: diff decimals
    function test_getLpTokenSupply_diffDecimals() public {
        uint[] memory reserves = new uint[](2);
        reserves[0] = STATE_B_B0;
        reserves[1] = STATE_B_B1;

        assertEq(_function.calcLpTokenSupply(reserves, _data), STATE_B_LP);
    }

    //////////// BALANCES ////////////

    /// @dev getBalance: same decimals, both positions
    /// Matches example in {testLpTokenSupplySameDecimals}.
    function test_getBalance_sameDecimals() public {
        uint[] memory reserves = new uint[](2);

        /// STATE A
        // find reserves[0]
        reserves[0] = 0;
        reserves[1] = STATE_A_B1;
        approxReserveCheck(
            _function.calcReserve(reserves, 0, STATE_A_LP, _data),
            STATE_A_B0
        );

        // find reserves[1]
        reserves[0] = STATE_A_B0;
        reserves[1] = 0;
        approxReserveCheck(
            _function.calcReserve(reserves, 1, STATE_A_LP, _data),
            STATE_A_B1
        );

        /// STATE C
        // find reserves[1]
        reserves[0] = STATE_C_B0; 
        reserves[1] = 0;
        approxReserveCheck(
            _function.calcReserve(reserves, 1, STATE_C_LP, _data),
            STATE_C_B1
        );
    }

    /// @dev getBalance: diff decimals, both positions
    /// Matches example in {testLpTokenSupplyDiffDecimals}.
    function test_getBalance_diffDecimals() public {
        uint[] memory reserves = new uint[](2);

        /// STATE B
        // find reserves[0]
        reserves[0] = 0;
        reserves[1] = STATE_B_B1;
        approxReserveCheck(
            _function.calcReserve(reserves, 0, STATE_B_LP, _data),
            STATE_B_B0
        );

        // find reserves[1]
        reserves[0] = STATE_B_B0;
        reserves[1] = 0;
        approxReserveCheck(
            _function.calcReserve(reserves, 1, STATE_B_LP, _data),
            STATE_B_B1
        );
    }
}
