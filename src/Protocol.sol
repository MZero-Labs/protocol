// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SignatureChecker } from "./libs/SignatureChecker.sol";
import { InterestMath } from "./libs/InterestMath.sol";

import { IInterestRateModel } from "./interfaces/IInterestRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";
import { IProtocol } from "./interfaces/IProtocol.sol";
import { ISPOG } from "./interfaces/ISPOG.sol";

import { StatelessERC712 } from "./StatelessERC712.sol";
import { MToken } from "./MToken.sol";

/**
 * @title Protocol
 * @author M^ZERO LABS_
 * @notice Core protocol of M^ZERO ecosystem. TODO Add description.
 */
contract Protocol is IProtocol, StatelessERC712 {
    // TODO bit-packing
    struct CollateralBasic {
        uint256 amount;
        uint256 lastUpdated;
    }

    // TODO bit-packing
    struct MintRequest {
        uint256 amount;
        uint256 createdAt;
        address to;
    }

    /******************************************************************************************************************\
    |                                                SPOG Variables and Lists Names                                    |
    \******************************************************************************************************************/

    /// @notice The minters' list name in SPOG
    bytes32 public constant MINTERS_LIST_NAME = "minters";

    /// @notice The validators' list name in SPOG
    bytes32 public constant VALIDATORS_LIST_NAME = "validators";

    /// @notice The name of parameter in SPOG that defines number of signatures required for successful collateral update
    bytes32 public constant UPDATE_COLLATERAL_QUORUM = "updateCollateral_quorum";

    /// @notice The name of parameter in SPOG that required interval to update collateral
    bytes32 public constant UPDATE_COLLATERAL_INTERVAL = "updateCollateral_interval";

    /// @notice The name of parameter in SPOG that defines the time to wait for mint request to be processed
    bytes32 public constant MINT_REQUEST_QUEUE_TIME = "mintRequest_queue_time";

    /// @notice The name of parameter in SPOG that defines the time while mint request can still be processed
    bytes32 public constant MINT_REQUEST_TTL = "mintRequest_ttl";

    /// @notice The name of parameter in SPOG that defines the time to freeze minter
    bytes32 public constant MINTER_FREEZE_TIME = "minter_freeze_time";

    /// @notice The name of parameter in SPOG that defines the borrow rate
    bytes32 public constant BORROW_RATE_MODEL = "borrow_rate_model";

    /// @notice The name of parameter in SPOG that defines the mint ratio
    bytes32 public constant MINT_RATIO = "mint_ratio"; // bps

    /******************************************************************************************************************\
    |                                                Protocol variables                                                |
    \******************************************************************************************************************/

    /// @notice The EIP-712 typehash for updateCollateral method
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        keccak256("UpdateCollateral(address minter,uint256 amount,uint256 timestamp,string metadata)");

    /// @notice The scale for M index
    uint256 public constant INDEX_BASE_SCALE = 1e18;

    /// @notice TODO The scale for collateral, most likely will be passed in cents
    uint256 public constant COLLATERAL_BASE_SCALE = 1e2;

    /// @notice Descaler for variables in basis points
    uint256 public constant ONE = 10_000; // 100% in basis points.

    /// @notice The scale for M token to collateral (must be less than 18 decimals)
    uint256 public immutable baseScale;

    /// @notice The address of SPOG
    address public immutable spog;

    /// @notice The address of M token
    address public immutable mToken;

    /// @notice The collateral information of minters
    mapping(address minter => CollateralBasic basic) public collateral;

    /// @notice The mint requests of minters, only 1 request per minter
    mapping(address minter => MintRequest request) public mintRequests;

    /// @notice The mint requests of minters, only 1 request per minter
    mapping(address minter => uint256 timestamp) public frozenUntil;

    /// @notice The total normalized principal (t0 principal value) for all minters
    uint256 public totalNormalizedPrincipal;

    /// @notice The normalized principal (t0 principal value) for each minter
    mapping(address minter => uint256 amount) public normalizedPrincipal;

    // TODO possibly bit-pack those 2 variables
    /// @notice The current M index for the protocol tracked for the entire market
    uint256 public mIndex;

    /// @notice The timestamp of the last time the M index was updated
    uint256 public lastAccrualTime;

    modifier onlyApprovedMinter() {
        if (!_isApprovedMinter(msg.sender)) revert NotApprovedMinter();

        _;
    }

    modifier onlyApprovedValidator() {
        if (!_isApprovedValidator(msg.sender)) revert NotApprovedValidator();

        _;
    }

    /**
     * @notice Constructor.
     * @param spog_ The address of SPOG
     */
    constructor(address spog_, address mToken_) StatelessERC712("Protocol") {
        spog = spog_;
        mToken = mToken_;

        mIndex = 1e18;
        lastAccrualTime = block.timestamp;

        baseScale = (10 ** MToken(mToken_).decimals()) / COLLATERAL_BASE_SCALE;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

    /**
     * @notice Updates collateral for minters
     * @param amount_ The amount of collateral
     * @param timestamp_ The timestamp of the update
     * @param metadata_ The metadata of the update, reserved for future informational use
     * @param validators_ The list of validators
     * @param signatures_ The list of signatures
     */
    function updateCollateral(
        uint256 amount_,
        uint256 timestamp_,
        string memory metadata_,
        address[] calldata validators_,
        bytes[] calldata signatures_
    ) external onlyApprovedMinter {
        if (validators_.length != signatures_.length) revert InvalidSignaturesLength();

        // Timestamp sanity checks
        uint256 updateInterval_ = _getUpdateCollateralInterval();
        if (block.timestamp > timestamp_ + updateInterval_) revert ExpiredTimestamp();

        address minter_ = msg.sender;

        CollateralBasic storage minterCollateral_ = collateral[minter_];
        if (minterCollateral_.lastUpdated > timestamp_) revert StaleTimestamp();

        // Core quorum validation, plus possible extension
        bytes32 updateCollateralDigest_ = _getUpdateCollateralDigest(minter_, amount_, metadata_, timestamp_);
        uint256 requiredQuorum_ = _getUpdateCollateralQuorum();
        _hasEnoughValidSignatures(updateCollateralDigest_, validators_, signatures_, requiredQuorum_);

        // _accruePenalties(); // JIRA ticket https://mzerolabs.atlassian.net/jira/software/c/projects/WEB3/boards/10?selectedIssue=WEB3-396

        // Update collateral
        minterCollateral_.amount = amount_;
        minterCollateral_.lastUpdated = timestamp_;

        // _accruePenalties(); // JIRA ticket

        emit CollateralUpdated(minter_, amount_, timestamp_, metadata_);
    }

    /**
     * @notice Proposes minting of M tokens
     * @param amount_ The amount of M tokens to mint
     * @param to_ The address to mint to
     */
    function proposeMint(uint256 amount_, address to_) external onlyApprovedMinter {
        address minter_ = msg.sender;
        uint256 now_ = block.timestamp;

        // Check is minter is frozen
        if (now_ < frozenUntil[msg.sender]) revert FrozenMinter();

        // Check if there is a pending non-expired mint request
        // uint256 expiresAt_ = mintRequest_.createdAt + _getMintRequestTimeToLive();
        // if (mintRequest_.amount > 0 && now_ < expiresAt_) revert OnlyOneMintRequestAllowed();

        // _accruePenalties(); // JIRA ticket

        // Check that mint is sufficiently collateralized
        uint256 allowedDebt_ = _allowedDebtOf(minter_);
        uint256 currentDebt_ = _debtOf(minter_);
        if (currentDebt_ + amount_ > allowedDebt_) revert UncollateralizedMint();

        MintRequest storage mintRequest_ = mintRequests[minter_];
        mintRequest_.amount = amount_;
        mintRequest_.createdAt = now_;
        mintRequest_.to = to_;

        emit MintRequestedCreated(minter_, amount_, to_);
    }

    /**
     * @notice Executes minting of M tokens
     */
    function mint() external onlyApprovedMinter {
        address minter_ = msg.sender;
        uint256 now_ = block.timestamp;

        // Check is minter is frozen
        if (now_ < frozenUntil[minter_]) revert FrozenMinter();

        // Check that request is executable
        MintRequest storage mintRequest_ = mintRequests[minter_];
        (uint256 amount_, uint256 createdAt_, address to_) = (
            mintRequest_.amount,
            mintRequest_.createdAt,
            mintRequest_.to
        );

        if (amount_ == 0) revert NoMintRequest();

        uint256 activeAt_ = createdAt_ + _getMintRequestQueueTime();
        if (now_ < activeAt_) revert PendingMintRequest();

        uint256 expiresAt_ = createdAt_ + _getMintRequestTimeToLive();
        if (now_ > expiresAt_) revert ExpiredMintRequest();

        updateIndices();

        // _accruePenalties(); // JIRA ticket

        // Check that mint is sufficiently collateralized
        uint256 allowedDebt_ = _allowedDebtOf(minter_);
        uint256 currentDebt_ = _debtOf(minter_);
        if (currentDebt_ + amount_ > allowedDebt_) revert UncollateralizedMint();

        // Delete mint request
        delete mintRequests[minter_];

        // Adjust normalized principal for minter
        uint256 normalizedPrincipal_ = _principalValue(amount_);
        normalizedPrincipal[minter_] += normalizedPrincipal_;
        totalNormalizedPrincipal += normalizedPrincipal_;

        // Mint actual tokens
        IMToken(mToken).mint(to_, amount_);

        emit MintRequestExecuted(minter_, amount_, to_);
    }

    /******************************************************************************************************************\
    |                                                Validator Functions                                               |
    \******************************************************************************************************************/

    /**
     * @notice Cancels minting request for selected minter by validator
     * @param minter_ The address of the minter to cancel active outstanding mint request
     */
    function cancel(address minter_) external onlyApprovedValidator {
        // TODO check if request is present, do we need it?
        delete mintRequests[minter_];

        emit MintRequestCanceled(minter_, msg.sender);
    }

    /**
     * @notice Freezes minter
     * @param minter_ The address of the minter to freeze
     */
    function freeze(address minter_) external onlyApprovedValidator {
        if (!_isApprovedMinter(minter_)) revert NotApprovedMinter();

        uint256 frozenUntil_ = block.timestamp + _getMinterFreezeTime();

        emit MinterFrozen(minter_, frozenUntil[minter_] = frozenUntil_);
    }

    function debtOf(address minter) external view returns (uint256) {
        return _debtOf(minter);
    }

    //
    //
    // burn
    // proposeRedeem, redeem
    // removeMinter
    //
    //
    /******************************************************************************************************************\
    |                                                Primary Functions                                                 |
    \******************************************************************************************************************/
    //
    //
    // stake
    // withdraw
    //
    //
    /******************************************************************************************************************\
    |                                                Brains Functions                                                  |
    \******************************************************************************************************************/
    //
    //
    // updateIndices, updateBorrowIndex, updateStakingIndex
    // accruePenalties
    // mintRewardsToZeroHolders
    //
    //

    /**
     * @notice Updates indices
     */
    function updateIndices() public {
        // update Minting borrow index
        _updateBorrowIndex();

        // update Primary staking rate index
        _updateStakingIndex();

        // mintRewardsToZeroHolders();
    }

    function _updateBorrowIndex() internal {
        uint256 now_ = block.timestamp;
        uint256 timeElapsed_ = now_ - lastAccrualTime;
        if (timeElapsed_ > 0) {
            mIndex = _getIndex(timeElapsed_);
            lastAccrualTime = now_;
        }
    }

    function _updateStakingIndex() internal {}

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * @notice Checks that enough valid unique signatures were provided
     * @param digest_ The message hash for signing
     * @param validators_ The list of validators who signed digest
     * @param signatures_ The list of signatures
     * @param requiredQuorum_ The number of signatures required for validated action
     */
    function _hasEnoughValidSignatures(
        bytes32 digest_,
        address[] calldata validators_,
        bytes[] calldata signatures_,
        uint256 requiredQuorum_
    ) internal view {
        address[] memory uniqueValidators_ = new address[](validators_.length);
        uint256 validatorsNum_ = 0;

        if (requiredQuorum_ > validators_.length) revert NotEnoughValidSignatures();

        // TODO consider reverting if any of inputs are duplicate or invalid
        for (uint i = 0; i < signatures_.length; i++) {
            // check that signature is unique and not accounted for
            bool duplicate_ = _contains(uniqueValidators_, validators_[i], validatorsNum_);
            if (duplicate_) continue;

            // check that validator is approved by SPOG
            bool authorized_ = _isApprovedValidator(validators_[i]);
            if (!authorized_) continue;

            // check that ECDSA or ERC1271 signatures for given digest are valid
            bool valid_ = SignatureChecker.isValidSignature(validators_[i], digest_, signatures_[i]);
            if (!valid_) continue;

            uniqueValidators_[validatorsNum_++] = validators_[i];
        }

        if (validatorsNum_ < requiredQuorum_) revert NotEnoughValidSignatures();
    }

    /**
     * @notice Returns the EIP-712 digest for updateCollateral method
     * @param minter_ The address of the minter
     * @param amount_ The amount of collateral
     * @param metadata_ The metadata of the collateral update, reserved for future informational use
     * @param timestamp_ The timestamp of the collateral update
     */
    function _getUpdateCollateralDigest(
        address minter_,
        uint256 amount_,
        string memory metadata_,
        uint256 timestamp_
    ) internal view returns (bytes32) {
        return _getDigest(keccak256(abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter_, amount_, metadata_, timestamp_)));
    }

    function _getIndex(uint timeElapsed_) internal view returns (uint256) {
        uint256 rate_ = _getBorrowRate();
        return timeElapsed_ > 0 ? InterestMath.calculateIndex(mIndex, rate_, timeElapsed_) : mIndex;
    }

    function _allowedDebtOf(address minter_) internal view returns (uint256) {
        CollateralBasic storage minterCollateral_ = collateral[minter_];

        // if collateral was not updated on time, assume that minter_ CV is zero
        uint256 updateInterval_ = _getUpdateCollateralInterval();
        if (minterCollateral_.lastUpdated + updateInterval_ < block.timestamp) return 0;

        uint256 mintRatio_ = _getMintRatio();
        return (minterCollateral_.amount * baseScale * mintRatio_) / ONE;
    }

    function _debtOf(address minter_) internal view returns (uint256) {
        uint256 principalValue_ = normalizedPrincipal[minter_];
        // return _presentValue(principalValue_) + penalties[minter];
        return _presentValue(principalValue_);
    }

    function _presentValue(uint256 principalValue_) internal view returns (uint256) {
        uint256 timeElapsed_ = block.timestamp - lastAccrualTime;
        return (principalValue_ * _getIndex(timeElapsed_)) / INDEX_BASE_SCALE;
    }

    function _principalValue(uint256 presentValue_) internal view returns (uint256) {
        uint256 timeElapsed_ = block.timestamp - lastAccrualTime;
        return (presentValue_ * INDEX_BASE_SCALE) / _getIndex(timeElapsed_);
    }

    /**
     * @notice Helper function to check if a given list contains an element
     * @param arr_ The list to check
     * @param elem_ The element to check for
     * @param len_ The length of the list
     */
    function _contains(address[] memory arr_, address elem_, uint256 len_) internal pure returns (bool) {
        for (uint256 i = 0; i < len_; i++) {
            if (arr_[i] == elem_) {
                return true;
            }
        }
        return false;
    }

    function _fromBytes32(bytes32 value) internal pure returns (address) {
        return address(uint160(uint256(value)));
    }

    /******************************************************************************************************************\
    |                                                SPOG Accessors                                                    |
    \******************************************************************************************************************/

    function _isApprovedMinter(address minter_) internal view returns (bool) {
        return ISPOG(spog).listContains(MINTERS_LIST_NAME, minter_);
    }

    function _isApprovedValidator(address validator_) internal view returns (bool) {
        return ISPOG(spog).listContains(VALIDATORS_LIST_NAME, validator_);
    }

    function _getUpdateCollateralInterval() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(UPDATE_COLLATERAL_INTERVAL));
    }

    function _getUpdateCollateralQuorum() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(UPDATE_COLLATERAL_QUORUM));
    }

    function _getMintRequestQueueTime() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(MINT_REQUEST_QUEUE_TIME));
    }

    function _getMintRequestTimeToLive() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(MINT_REQUEST_TTL));
    }

    function _getMinterFreezeTime() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(MINTER_FREEZE_TIME));
    }

    function _getBorrowRate() internal view returns (uint256) {
        address rateContract = _fromBytes32(ISPOG(spog).get(BORROW_RATE_MODEL));
        return IInterestRateModel(rateContract).getRate();
    }

    function _getMintRatio() internal view returns (uint256) {
        return uint256(ISPOG(spog).get(MINT_RATIO));
    }
}
