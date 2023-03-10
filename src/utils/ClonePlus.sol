// SPDX-License-Identifier: BSD
pragma solidity ^0.8.4;

import {Clone} from "./Clone.sol";
import {IERC20} from "oz/token/ERC20/utils/SafeERC20.sol";

/// @title ClonePlus
/// @notice Extends Clone with additional helper functions
contract ClonePlus is Clone {
    uint private constant ONE_WORD = 0x20;

    /// @notice Reads a IERC20 array stored in the immutable args.
    /// @param argOffset The offset of the arg in the packed data
    /// @param arrLen Number of elements in the array
    /// @return arr The array
    function _getArgIERC20Array(uint argOffset, uint arrLen) internal pure returns (IERC20[] memory arr) {
        uint offset = _getImmutableArgsOffset() + argOffset;
        arr = new IERC20[](arrLen);

        // solhint-disable-next-line no-inline-assembly
        assembly {
            calldatacopy(add(arr, ONE_WORD), offset, shl(5, arrLen))
        }
    }

    /// @notice Reads a bytes data stored in the immutable args.
    /// @param argOffset The offset of the arg in the packed data
    /// @param bytesLen Number of bytes in the data
    /// @return data the bytes data
    function _getArgBytes(uint argOffset, uint bytesLen) internal pure returns (bytes memory data) {
        if (bytesLen == 0) return data;
        uint offset = _getImmutableArgsOffset() + argOffset;
        data = new bytes(bytesLen);

        // solhint-disable-next-line no-inline-assembly
        assembly {
            calldatacopy(add(data, ONE_WORD), offset, shl(5, bytesLen))
        }
    }
}
