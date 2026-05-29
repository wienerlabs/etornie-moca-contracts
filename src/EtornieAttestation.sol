// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title EtornieAttestation
/// @author Etornie AG / Wiener Labs
/// @notice EVM port of the Solana `etornie-attestation` Anchor program. One
///         on-chain record per IP case plus an event-log timeline of
///         lifecycle updates that off-chain services can replay.
/// @dev The `operator` is the backend service that relays signed user intents;
///      `OPERATOR_ROLE` gates writes. The DEFAULT_ADMIN_ROLE can rotate
///      operators if a relay key needs to be revoked.
contract EtornieAttestation is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct Case {
        bytes16 caseId;
        bytes32 metadataHash;
        address creator;
        address clientWallet;
        address operator;
        uint64 createdAt;
        bool exists;
    }

    /// @notice Active attestations keyed by `case_id` (16-byte UUID).
    mapping(bytes16 => Case) public cases;

    event CaseAttestationCreated(
        bytes16 indexed caseId,
        bytes32 metadataHash,
        address indexed creator,
        address indexed clientWallet,
        address operator,
        uint64 timestamp
    );

    event CaseAttestationUpdated(
        bytes16 indexed caseId,
        bytes32 oldMetadataHash,
        bytes32 newMetadataHash,
        uint8 eventType,
        address indexed actor,
        address operator,
        uint64 timestamp
    );

    error AttestationAlreadyExists(bytes16 caseId);
    error AttestationNotFound(bytes16 caseId);

    constructor(address admin, address initialOperator) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, initialOperator);
    }

    /// @notice Create a new case attestation. Reverts if `caseId` has been
    ///         attested before — matches the Solana `init` PDA semantics.
    /// @param caseId         16-byte case UUID.
    /// @param metadataHash   sha256 of the canonical case JSON at creation.
    /// @param creator        The user wallet that authored the case
    ///                       (relayed by operator, recorded for provenance).
    /// @param clientWallet   The client wallet the case is filed for.
    function createCaseAttestation(
        bytes16 caseId,
        bytes32 metadataHash,
        address creator,
        address clientWallet
    ) external onlyRole(OPERATOR_ROLE) {
        Case storage c = cases[caseId];
        if (c.exists) revert AttestationAlreadyExists(caseId);

        c.caseId = caseId;
        c.metadataHash = metadataHash;
        c.creator = creator;
        c.clientWallet = clientWallet;
        c.operator = msg.sender;
        c.createdAt = uint64(block.timestamp);
        c.exists = true;

        emit CaseAttestationCreated(
            caseId,
            metadataHash,
            creator,
            clientWallet,
            msg.sender,
            uint64(block.timestamp)
        );
    }

    /// @notice Overwrite the metadata hash and emit a lifecycle event.
    /// @dev The historical hash is preserved in `oldMetadataHash` so the
    ///      tx log alone is enough to reconstruct the case timeline.
    /// @param caseId         16-byte case UUID.
    /// @param newMetadataHash sha256 of the canonical case JSON at event time.
    /// @param eventType      Numeric event code (status change, doc upload, etc).
    /// @param actor          The user wallet that triggered the event.
    function updateCaseAttestation(
        bytes16 caseId,
        bytes32 newMetadataHash,
        uint8 eventType,
        address actor
    ) external onlyRole(OPERATOR_ROLE) {
        Case storage c = cases[caseId];
        if (!c.exists) revert AttestationNotFound(caseId);

        bytes32 oldHash = c.metadataHash;
        c.metadataHash = newMetadataHash;

        emit CaseAttestationUpdated(
            caseId,
            oldHash,
            newMetadataHash,
            eventType,
            actor,
            msg.sender,
            uint64(block.timestamp)
        );
    }

    /// @notice Convenience view returning whether a case has been attested.
    function exists(bytes16 caseId) external view returns (bool) {
        return cases[caseId].exists;
    }
}
