// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {console, TestHelper} from "test/TestHelper.sol";
import {WellFunctionHelper} from "./WellFunctionHelper.sol";
import {ConstantProduct2} from "src/functions/ConstantProduct2.sol";

/// @dev Tests the {ConstantProduct2} Well function directly.
contract ConstantProduct2Test is WellFunctionHelper {
    /// State A: Same decimals
    uint STATE_A_B0 = 10 * 1e18;
    uint STATE_A_B1 = 10 * 1e18;
    uint STATE_A_LP = 10 * 1e24;

    /// State B: Different decimals
    uint STATE_B_B0 = 1 * 1e18;
    uint STATE_B_B1 = 1250 * 1e6;
    uint STATE_B_LP = 35_355_339_059_327_376_220;

    /// State C: Similar decimals
    uint STATE_C_B0 = 20 * 1e18;
    uint STATE_C_B1 = 31_250_000_000_000_000_000; // 3.125e19
    uint STATE_C_LP = 25 * 1e24;

    //////////// SETUP ////////////

    function setUp() public {
        _function = new ConstantProduct2();
        _data = "";
    }

    function test_metadata() public {
        assertEq(_function.name(), "Constant Product");
        assertEq(_function.symbol(), "CP");
    }

    //////////// LP TOKEN SUPPLY ////////////

    /// @dev reverts when trying to calculate lp token supply with < 2 reserves
    function test_getLpTokenSupply_minBalancesLength() public {
        check_getLpTokenSupply_minBalancesLength(2);
    }

    /// @dev calcLpTokenSupply: same decimals, manual calc for 2 equal reserves
    function test_getLpTokenSupply_sameDecimals() public {
        uint[] memory reserves = new uint[](2);
        reserves[0] = STATE_A_B0;
        reserves[1] = STATE_A_B1;
        assertEq(
            _function.calcLpTokenSupply(reserves, _data),
            STATE_A_LP // sqrt(10e18 * 10e18) * 2
        );
    }

    /// @dev calcLpTokenSupply: diff decimals
    function test_getLpTokenSupply_diffDecimals() public {
        uint[] memory reserves = new uint[](2);
        reserves[0] = STATE_B_B0; // ex. 1 WETH
        reserves[1] = STATE_B_B1; // ex. 1250 BEAN
        assertEq(
            _function.calcLpTokenSupply(reserves, _data),
            STATE_B_LP // sqrt(1e18 * 1250e6) * 2
        );
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
        assertEq(
            _function.calcReserve(reserves, 0, STATE_A_LP, _data),
            STATE_A_B0 // (20e18/2) ^ 2 / 10e18 = 10e18
        );

        // find reserves[1]
        reserves[0] = STATE_A_B0;
        reserves[1] = 0;
        assertEq(_function.calcReserve(reserves, 1, STATE_A_LP, _data), STATE_A_B1);

        /// STATE C
        // find reserves[1]
        reserves[0] = STATE_C_B0;
        reserves[1] = 0;
        assertEq(
            _function.calcReserve(reserves, 1, STATE_C_LP, _data),
            STATE_C_B1 // (50e18/2) ^ 2 / 20e18 = 31.25e19
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
        assertEq(
            _function.calcReserve(reserves, 0, STATE_B_LP, _data),
            STATE_B_B0 // (70710678118654 / 2)^2 / 1250e6 = ~1e18
        );

        // find reserves[1]
        reserves[0] = STATE_B_B0; // placeholder
        reserves[1] = 0; // ex. 1250 BEAN
        assertEq(
            _function.calcReserve(reserves, 1, STATE_B_LP, _data),
            STATE_B_B1 // (70710678118654 / 2)^2 / 1e18 = 1250e6
        );
    }

    function test_fuzz_constantProduct(uint x, uint y) public {
        uint[] memory reserves = new uint[](2);
        bytes memory _data = new bytes(0);
        // TODO - relax assumption
        reserves[0] = bound(x, 1, 1e32);
        reserves[1] = bound(y, 1, 1e32);
        uint lpTokenSupply = _function.calcLpTokenSupply(reserves, _data);
        console.log("lpTokenSupply", lpTokenSupply);
        uint reserve0 = _function.calcReserve(reserves, 0, lpTokenSupply, _data);
        uint reserve1 = _function.calcReserve(reserves, 1, lpTokenSupply, _data);
        if (reserves[0] < 1e12) {
            assertApproxEqAbs(reserve0, reserves[0], 2);
        } else {
            assertApproxEqRel(reserve0, reserves[0], 2e6);
        }
        if (reserves[1] < 1e12) {
            assertApproxEqAbs(reserve1, reserves[1], 2);
        } else {
            assertApproxEqRel(reserve1, reserves[1], 2e6);
        }
    }
}
