// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import "forge-std/Test.sol";

import { ContinuousIndexingMath } from "../../src/libs/ContinuousIndexingMath.sol";

// FOUNDRY_FUZZ_RUNS=100 forge test --match-path test/ExponentDifferential.t.sol --ffi -vvv

contract DifferentialTest is Test {
    function setUp() public {}

    function test_exp(uint128 x) public {
        vm.assume(x >= 1);
        vm.assume(x <= 4000);

        uint128 python = _ffi_exp(x);
        uint128 pade = ContinuousIndexingMath.exponent(uint72((x * ContinuousIndexingMath.EXP_ONE) / 1e4));

        assertApproxEqAbs(python, pade, 1e6);
    }

    function _ffi_exp(uint128 x) internal returns (uint128) {
        string[] memory inputs = new string[](3);
        inputs[0] = "python3";
        inputs[1] = "test/ffi/exponent.py";
        inputs[2] = _toString(x);

        bytes memory res = vm.ffi(inputs);

        return abi.decode(res, (uint128));
    }

    /// @dev Solmate https://github.com/transmissions11/solmate/blob/main/src/utils/LibString.sol
    function _toString(uint256 value) internal pure returns (string memory str) {
        /// @solidity memory-safe-assembly
        assembly {
            // The maximum value of a uint256 contains 78 digits (1 byte per digit), but we allocate 160 bytes
            // to keep the free memory pointer word aligned. We'll need 1 word for the length, 1 word for the
            // trailing zeros padding, and 3 other words for a max of 78 digits. In total: 5 * 32 = 160 bytes.
            let newFreeMemoryPointer := add(mload(0x40), 160)

            // Update the free memory pointer to avoid overriding our string.
            mstore(0x40, newFreeMemoryPointer)

            // Assign str to the end of the zone of newly allocated memory.
            str := sub(newFreeMemoryPointer, 32)

            // Clean the last word of memory it may not be overwritten.
            mstore(str, 0)

            // Cache the end of the memory to calculate the length later.
            let end := str

            // We write the string from rightmost digit to leftmost digit.
            // The following is essentially a do-while loop that also handles the zero case.
            // prettier-ignore
            for { let temp := value } 1 {} {
                // Move the pointer 1 byte to the left.
                str := sub(str, 1)

                // Write the character to the pointer.
                // The ASCII index of the '0' character is 48.
                mstore8(str, add(48, mod(temp, 10)))

                // Keep dividing temp until zero.
                temp := div(temp, 10)

                 // prettier-ignore
                if iszero(temp) { break }
            }

            // Compute and cache the final total length of the string.
            let length := sub(end, str)

            // Move the pointer 32 bytes leftwards to make room for the length.
            str := sub(str, 32)

            // Store the string's length at the start of memory allocated for our string.
            mstore(str, length)
        }
    }
}
