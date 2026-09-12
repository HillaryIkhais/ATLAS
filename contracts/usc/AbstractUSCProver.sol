// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IUSCProver.sol";
import "../common/AuthorityTypes.sol";
import "./BlockProverTypes.sol";

/// @title AbstractUSCProver
/// @notice Shared Attestcoin/USC proof handling for ATLAS.
/// @dev Encapsulates everything except the cryptographic verification step:
///      unpacking the opaque proof, decoding the ABI-encoded transaction +
///      receipt (the `abiEncode` output of the gluwa usc-sdk), locating the
///      proven `AuthorityUpdated` log and mapping it onto
///      `IUSCProver.ProvenAction`. `RealUSCProver` fills in the crypto via the
///      CC3 BlockProver precompile; `MockUSCProver` skips crypto but keeps the
///      full decode path so Foundry exercises the real proof shape end-to-end.
/// @dev Proof layout (all ABI-encoded):
///      proof          = abi.encode(uint64 blockHeight, InclusionProof, ContinuityProof)
///      inclusion.data = abi.encode(bytes txBytes, MerkleProofEntry[] siblings)
///      txBytes        = abi.encode(uint8 txType, bytes[] chunks)  -- SDK abiEncode output
///      chunks[0]      = (nonce, gasLimit, from, toIsNull, to, value, data)
///      chunks[2 or 3] = receipt (status, gasUsed, logs, logsBloom)
abstract contract AbstractUSCProver {
    /// @dev keccak256("AuthorityUpdated(uint256,address,bytes32,uint256,uint256,uint64,uint8)")
    bytes32 internal constant AUTHORITY_UPDATED_SIG =
        0x9e9f7c6a11b02e008df86f47a12e8a70b18409ff08a36ab047e9940225f7cce3;

    error InvalidTransactionEncoding();
    error FailedSourceTransaction();
    error UntrustedController();
    error NoAuthorityUpdatedLog();

    uint64 public immutable sourceChainKey;
    address public immutable authorizedController;

    constructor(uint64 _sourceChainKey, address _authorizedController) {
        sourceChainKey = _sourceChainKey;
        authorizedController = _authorizedController;
    }

    /// @notice Shared pipeline: unpack proof -> native verify -> decode event.
    function _prove(bytes calldata proof) internal returns (bool verified, IUSCProver.ProvenAction memory action) {
        (uint64 blockHeight, BlockProverTypes.InclusionProof memory inclusionProof, BlockProverTypes.ContinuityProof
            memory continuityProof) =
            abi.decode(proof, (uint64, BlockProverTypes.InclusionProof, BlockProverTypes.ContinuityProof));

        (bytes memory txBytes, BlockProverTypes.MerkleProofEntry[] memory siblings) =
            abi.decode(inclusionProof.data, (bytes, BlockProverTypes.MerkleProofEntry[]));

        if (!_verifyNativeCall(blockHeight, txBytes, inclusionProof.root, siblings, continuityProof)) {
            return (false, action);
        }

        return (true, _decodeAuthorityUpdated(txBytes));
    }

    /// @notice Cryptographic verification. Implementations decide how to verify;
    ///         `false` means "this proof does not bind txBytes to the source
    ///         block at blockHeight" and the caller must reject the update.
    function _verifyNativeCall(
        uint64 blockHeight,
        bytes memory txBytes,
        bytes32 root,
        BlockProverTypes.MerkleProofEntry[] memory siblings,
        BlockProverTypes.ContinuityProof memory continuityProof
    ) internal virtual returns (bool);

    /// @notice Recover the AuthorityUpdated fact from the proven tx + receipt.
    function _decodeAuthorityUpdated(bytes memory txBytes)
        internal
        view
        returns (IUSCProver.ProvenAction memory action)
    {
        (uint8 txType, bytes[] memory chunks) = abi.decode(txBytes, (uint8, bytes[]));
        if (chunks.length < 3) revert InvalidTransactionEncoding();

        // chunks[0]: common fields (nonce, gasLimit, from, toIsNull, to, value, data).
        (, , , bool toIsNull, address to, , ) =
            abi.decode(chunks[0], (uint64, uint64, address, bool, address, uint256, bytes));
        if (toIsNull) revert InvalidTransactionEncoding();

        // Receipt chunk: type 0-2 -> index 2, type 3-4 -> index 3.
        uint256 receiptIdx = txType <= 2 ? 2 : 3;
        if (chunks.length <= receiptIdx) revert InvalidTransactionEncoding();

        (uint8 receiptStatus, , BlockProverTypes.ReceiptLog[] memory logs, ) =
            abi.decode(chunks[receiptIdx], (uint8, uint64, BlockProverTypes.ReceiptLog[], bytes));

        if (receiptStatus != 1) revert FailedSourceTransaction();

        for (uint256 i = 0; i < logs.length; i++) {
            BlockProverTypes.ReceiptLog memory log = logs[i];
            if (log.topics.length == 4 && log.topics[0] == AUTHORITY_UPDATED_SIG) {
                if (log.addr != authorizedController) revert UntrustedController();

                action.sourceContract = log.addr;
                action.authorityId = uint256(log.topics[1]);
                action.agent = address(uint160(uint256(log.topics[2])));
                action.action = log.topics[3];

                (uint256 maxAmount, uint256 expiresAt, uint64 version, uint8 status) =
                    abi.decode(log.data, (uint256, uint256, uint64, uint8));
                action.maxAmount = maxAmount;
                action.expiresAt = expiresAt;
                action.version = version;
                action.status = AuthorityTypes.Status(status);
                return action;
            }
        }

        revert NoAuthorityUpdatedLog();
    }
}