/**
 * SPDX-License-Identifier: MIT
 *
 */
pragma solidity ^0.8.17;

import "test/TestHelper.sol";

import {LibBytes16} from "src/libraries/LibBytes16.sol";

contract LibBytes16Test is TestHelper {
    uint constant NUM_RESERVES_MAX = 8;
    bytes32 constant RESERVES_STORAGE_SLOT = keccak256("reserves.storage.slot");

    /// @dev Store fuzzed reserves, re-read and compare.
    function testFuzz_storeAndReadBytes16(uint n, bytes16[8] memory _reserves) public {
        vm.assume(n <= NUM_RESERVES_MAX);

        // Use the first `n` reserves. Cast uint128 reserves -> uint256
        bytes16[] memory reserves = new bytes16[](n);
        for (uint i = 0; i < n; i++) {
            reserves[i] = _reserves[i];
        }
        LibBytes16.storeBytes16(RESERVES_STORAGE_SLOT, reserves);

        bytes32 slot = RESERVES_STORAGE_SLOT;
        bytes32 test;
        assembly {
            test := sload(slot)
        }
        console.logBytes32(test);
        assembly {
            test := sload(add(slot, 32))
        }
        console.logBytes32(test);

        // Re-read reserves and compare
        bytes16[] memory reserves2 = LibBytes16.readBytes16(RESERVES_STORAGE_SLOT, n);
        for (uint i = 0; i < reserves2.length; i++) {
            console.log(i);
            assertEq(reserves2[i], reserves[i], "ByteStorage: reserves mismatch");
        }
    }
}
