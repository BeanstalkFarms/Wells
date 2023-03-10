/**
 * SPDX-License-Identifier: MIT
 **/

pragma solidity ^0.8.17;

import "src/interfaces/IWellFunction.sol";
import "src/libraries/LibMath.sol";

/**
 * @author Publius
 * @title Gas efficient Stable Swap pricing function for Wells with 2 tokens.
 *
 * Stable Swap Wells with 2 tokens use the formula:
 *  `b_0^a * b_1 + b_0 * b_1^a = 2 * (s / 2)^(a+1)`
 *
 * Where:
 *  `s` is the supply of LP tokens
 *  `b_i` is the reserve at index `i`
 *  The 2 in `s / 2` follows from the fact that there are 2 tokens in the Well
 */
contract StableSwap2 is IWellFunction {
    using LibMath for uint;

    uint constant EXP_PRECISION = 1e18;

    uint private a;

    constructor(uint _a) {
        a = _a;
    }

    /// @dev `s = ((b_0^a * b_1 + b_0 * b_1^a) / 2)^(1/(a+1)) * 2`
    function calcLpTokenSupply(
        uint[] calldata reserves,
        bytes calldata
    ) external view override returns (uint lpTokenSupply) {
        uint _a = (reserves[0] * reserves[1] * EXP_PRECISION).nthRoot(a + 1);
        uint _b = (((reserves[0] ** (a - 1)) + (reserves[1] ** (a - 1))) / 2)
            .nthRoot(a + 1);
        lpTokenSupply = _a * _b * 2;
    }

    /// @dev `b_i^a * b_j + b_i * b_j^a = 2 * (s / 2)^(a+1)`
    function calcReserve(
        uint[] calldata reserves,
        uint j,
        uint lpTokenSupply,
        bytes calldata
    ) external view override returns (uint reserve) {
        uint round;
        if (lpTokenSupply < 1e20) {
            round = lpTokenSupply.nthRoot(3);
        } else if (lpTokenSupply < 1e24) {
            round = 1e7;
        } else if (lpTokenSupply < 1e28) {
            round = 1e9;
        } else if (lpTokenSupply < 1e32) {
            round = 1e12;
        } else if (lpTokenSupply < 1e36) {
            round = 1e15;
        } else {
            round = 1e18;
        }
        uint r = ((lpTokenSupply / round / 2) ** (a + 1)) * 2;

        uint y = reserves[j == 1 ? 0 : 1] / round;
        reserve = _get_y(y, y, r) * round;
    }

    function name() external pure override returns (string memory) {
        return "Stable Swap";
    }

    function symbol() external pure override returns (string memory) {
        return "SS";
    }

    function _f(uint x0, uint y, uint d) internal view returns (uint) {
        uint dsqrt1 = d.sqrt();
        uint dsqrt2 = d / dsqrt1;
        return
            (((y * (x0 ** (a - 1))) / dsqrt1) * x0) /
            dsqrt2 +
            (((x0 * (y ** (a - 1))) / dsqrt1) * y) /
            dsqrt2;
    }

    function _d(uint x0, uint y) internal view returns (uint) {
        return a * y * (x0 ** (a - 1)) + y ** a;
    }

    function _get_y(uint x, uint y, uint r) internal view returns (uint) {
        for (uint i = 0; i < 255; i++) {
            uint x_prev = x;
            uint d = _d(x, y);
            uint k = _f(x, y, d);
            if (k < r / 1e18 / d) {
                uint dx = (r / 1e18 / d - k);
                x = x + dx;
            } else {
                uint dx = (k - r / 1e18 / d);
                x = x - dx;
            }
            if (x > x_prev) {
                if (x - x_prev <= 1) {
                    return x;
                }
            } else {
                if (x_prev - x <= 1) {
                    return x;
                }
            }
        }
        return x;
    }
}
