// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

/// @title Continuous Indexing Interface.
interface IContinuousIndexing {
    /**
     * @notice Emitted when the index is updated.
     * @param  index The new index.
     */
    event IndexUpdated(uint128 index);

    /**
     * @notice Emitted when the rate top be used going forward is updated.
     * @param  rate The current rate.
     */
    event RateUpdated(uint32 rate);

    /**
     * @notice Updates the latest index, the latest accrual time, and the latest rate in storage.
     * @return index The new stored index for computing present amounts from principal amounts.
     */
    function poke() external returns (uint128);

    /// @notice The current index that would be written to storage if `updateIndex` is called.
    function currentIndex() external view returns (uint128);

    /// @notice The latest updated index.
    function latestIndex() external view returns (uint128);

    /// @notice The latest timestamp when the index was updated.
    function latestUpdateTimestamp() external view returns (uint40);
}
