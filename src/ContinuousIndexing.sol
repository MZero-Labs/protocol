// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "./libs/UIntMath.sol";

import { IContinuousIndexing } from "./interfaces/IContinuousIndexing.sol";

import { ContinuousIndexingMath } from "./libs/ContinuousIndexingMath.sol";

abstract contract ContinuousIndexing is IContinuousIndexing {
    uint184 internal _latestIndex;
    uint24 internal _latestRate;
    uint48 internal _latestUpdateTimestamp;

    constructor() {
        _latestIndex = uint184(1 * ContinuousIndexingMath.EXP_BASE_SCALE);
        _latestUpdateTimestamp = uint48(block.timestamp);
    }

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    function updateIndex() public virtual returns (uint256 currentIndex_) {
        // NOTE: `currentIndex()` depends on `_latestRate`, so only update it after this.
        currentIndex_ = currentIndex();

        // NOTE: `_rate()` can depend on `_latestIndex` and `_latestUpdateTimestamp`, so only update them after this.
        uint256 rate_ = _rate();

        if (_latestUpdateTimestamp == block.timestamp && _latestRate == rate_) return currentIndex_;

        _latestIndex = UIntMath.safe184(currentIndex_);
        _latestRate = UIntMath.safe24(rate_);
        _latestUpdateTimestamp = UIntMath.safe48(block.timestamp);

        emit IndexUpdated(currentIndex_, _latestRate);
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    function currentIndex() public view virtual returns (uint256 currentIndex_) {
        return
            ContinuousIndexingMath.multiply(
                _latestIndex,
                ContinuousIndexingMath.getContinuousIndex(
                    ContinuousIndexingMath.convertFromBasisPoints(_latestRate),
                    block.timestamp - _latestUpdateTimestamp
                )
            );
    }

    function latestIndex() public view virtual returns (uint256 index_) {
        return _latestIndex;
    }

    function latestUpdateTimestamp() public view virtual returns (uint256 latestAccrualTime_) {
        return _latestUpdateTimestamp;
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _getPresentAmountAndUpdateIndex(uint256 principalAmount_) internal returns (uint256 presentAmount_) {
        return _getPresentAmount(principalAmount_, updateIndex());
    }

    function _getPrincipalAmountAndUpdateIndex(uint256 presentAmount_) internal returns (uint256 principalAmount_) {
        return _getPrincipalAmount(presentAmount_, updateIndex());
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function _getPresentAmount(
        uint256 principalAmount_,
        uint256 index_
    ) internal pure returns (uint256 presentAmount_) {
        return ContinuousIndexingMath.multiply(principalAmount_, index_);
    }

    function _getPrincipalAmount(
        uint256 presentAmount_,
        uint256 index_
    ) internal pure returns (uint256 principalAmount_) {
        return ContinuousIndexingMath.divide(presentAmount_, index_);
    }

    function _rate() internal view virtual returns (uint256 rate_);
}
