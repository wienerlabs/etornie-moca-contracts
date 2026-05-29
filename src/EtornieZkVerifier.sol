// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice snarkjs-style Groth16 verifier with 1 public input.
interface IGroth16Verifier1 {
    function verifyProof(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[1] calldata pubSignals
    ) external view returns (bool);
}

/// @notice snarkjs-style Groth16 verifier with 3 public inputs.
interface IGroth16Verifier3 {
    function verifyProof(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[3] calldata pubSignals
    ) external view returns (bool);
}

/// @title EtornieZkVerifier
/// @author Etornie AG / Wiener Labs
/// @notice EVM port of the Solana `etornie-zk-verifier` Anchor program. Wraps
///         three Groth16 verifier sub-contracts (one per circuit) and records
///         each accepted proof, with per-user replay protection.
/// @dev Sub-verifier addresses are settable by `ADMIN_ROLE` so the on-chain
///      verifying keys can be rotated when a circuit is re-compiled. The
///      verifier sub-contracts themselves are stateless — the auto-generated
///      snarkjs Solidity verifier per circuit.
contract EtornieZkVerifier is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    enum ProofKind {
        HelloWorld,
        FileOwnership,
        Compliance
    }

    /// @notice Verifier sub-contracts per circuit.
    IGroth16Verifier1 public helloWorldVerifier;
    IGroth16Verifier3 public fileOwnershipVerifier;
    IGroth16Verifier3 public complianceVerifier;

    struct ProofRecord {
        address user;
        bytes32 journalDigest;
        uint64 verifiedAt;
        bool exists;
    }

    struct FileOwnershipRecord {
        address owner;
        bytes32 fileHash;
        bytes32 commitment;
        uint64 verifiedAt;
        bool exists;
    }

    struct ComplianceRecord {
        address payer;
        bytes32 queryHash;
        bytes32 commitment;
        uint64 verifiedAt;
        bool exists;
    }

    /// @notice keyed by `keccak256(user, journalDigest)`.
    mapping(bytes32 => ProofRecord) public proofRecords;
    /// @notice keyed by `keccak256(owner, fileHash)`.
    mapping(bytes32 => FileOwnershipRecord) public fileOwnershipRecords;
    /// @notice keyed by `keccak256(payer, queryHash)`.
    mapping(bytes32 => ComplianceRecord) public complianceRecords;

    event VerifierUpdated(ProofKind indexed kind, address indexed verifier);
    event HelloWorldVerified(
        address indexed user,
        bytes32 indexed journalDigest,
        uint64 timestamp
    );
    event FileOwnershipVerified(
        address indexed owner,
        bytes32 indexed fileHash,
        bytes32 commitment,
        uint64 timestamp
    );
    event ComplianceVerified(
        address indexed payer,
        bytes32 indexed queryHash,
        bytes32 commitment,
        uint64 timestamp
    );

    error VerifierNotSet(ProofKind kind);
    error InvalidProof();
    error ReplayedProof();
    error MismatchedDigest();
    error MalformedFileHashInput();
    error MalformedQueryHashInput();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------

    function setHelloWorldVerifier(IGroth16Verifier1 v) external onlyRole(ADMIN_ROLE) {
        helloWorldVerifier = v;
        emit VerifierUpdated(ProofKind.HelloWorld, address(v));
    }

    function setFileOwnershipVerifier(IGroth16Verifier3 v) external onlyRole(ADMIN_ROLE) {
        fileOwnershipVerifier = v;
        emit VerifierUpdated(ProofKind.FileOwnership, address(v));
    }

    function setComplianceVerifier(IGroth16Verifier3 v) external onlyRole(ADMIN_ROLE) {
        complianceVerifier = v;
        emit VerifierUpdated(ProofKind.Compliance, address(v));
    }

    // -------------------------------------------------------------------
    // HelloWorld — generic 1-input proof. Matches `verify_proof` on Solana.
    // -------------------------------------------------------------------

    /// @notice Verify a HelloWorld Groth16 proof and record it.
    /// @dev `journalDigest` MUST equal `sha256(publicInputs[0])` so the
    ///      record slot is bound to the inputs that produced it.
    function verifyHelloWorld(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[1] calldata publicInputs,
        bytes32 journalDigest
    ) external {
        if (sha256(abi.encodePacked(bytes32(publicInputs[0]))) != journalDigest) {
            revert MismatchedDigest();
        }

        bytes32 slot = keccak256(abi.encode(msg.sender, journalDigest));
        if (proofRecords[slot].exists) revert ReplayedProof();

        IGroth16Verifier1 v = helloWorldVerifier;
        if (address(v) == address(0)) revert VerifierNotSet(ProofKind.HelloWorld);
        if (!v.verifyProof(pA, pB, pC, publicInputs)) revert InvalidProof();

        proofRecords[slot] = ProofRecord({
            user: msg.sender,
            journalDigest: journalDigest,
            verifiedAt: uint64(block.timestamp),
            exists: true
        });

        emit HelloWorldVerified(msg.sender, journalDigest, uint64(block.timestamp));
    }

    // -------------------------------------------------------------------
    // FileOwnership — proves the caller knows `s` with
    //                 Poseidon(s, fh_hi, fh_lo) == commitment.
    // -------------------------------------------------------------------

    function verifyFileOwnership(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[3] calldata publicInputs,
        bytes32 fileHash
    ) external {
        (bytes32 expHi, bytes32 expLo) = _splitHash(fileHash);
        if (bytes32(publicInputs[0]) != expHi || bytes32(publicInputs[1]) != expLo) {
            revert MalformedFileHashInput();
        }

        bytes32 slot = keccak256(abi.encode(msg.sender, fileHash));
        if (fileOwnershipRecords[slot].exists) revert ReplayedProof();

        IGroth16Verifier3 v = fileOwnershipVerifier;
        if (address(v) == address(0)) revert VerifierNotSet(ProofKind.FileOwnership);
        if (!v.verifyProof(pA, pB, pC, publicInputs)) revert InvalidProof();

        bytes32 commitment = bytes32(publicInputs[2]);
        fileOwnershipRecords[slot] = FileOwnershipRecord({
            owner: msg.sender,
            fileHash: fileHash,
            commitment: commitment,
            verifiedAt: uint64(block.timestamp),
            exists: true
        });

        emit FileOwnershipVerified(msg.sender, fileHash, commitment, uint64(block.timestamp));
    }

    // -------------------------------------------------------------------
    // Compliance — x402 AI pay-per-query compliance proof.
    // -------------------------------------------------------------------

    function verifyCompliance(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[3] calldata publicInputs,
        bytes32 queryHash
    ) external {
        (bytes32 expHi, bytes32 expLo) = _splitHash(queryHash);
        if (bytes32(publicInputs[0]) != expHi || bytes32(publicInputs[1]) != expLo) {
            revert MalformedQueryHashInput();
        }

        bytes32 slot = keccak256(abi.encode(msg.sender, queryHash));
        if (complianceRecords[slot].exists) revert ReplayedProof();

        IGroth16Verifier3 v = complianceVerifier;
        if (address(v) == address(0)) revert VerifierNotSet(ProofKind.Compliance);
        if (!v.verifyProof(pA, pB, pC, publicInputs)) revert InvalidProof();

        bytes32 commitment = bytes32(publicInputs[2]);
        complianceRecords[slot] = ComplianceRecord({
            payer: msg.sender,
            queryHash: queryHash,
            commitment: commitment,
            verifiedAt: uint64(block.timestamp),
            exists: true
        });

        emit ComplianceVerified(msg.sender, queryHash, commitment, uint64(block.timestamp));
    }

    // -------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------

    /// @notice Mirror the Solana `expected_fh_hi/lo` canonical encoding:
    ///         top 16 bytes of `h` go into the low half of `hi`, bottom 16
    ///         bytes go into the low half of `lo`. Top 16 bytes of both
    ///         halves are zero (BN254 254-bit field safety).
    function _splitHash(bytes32 h) internal pure returns (bytes32 hi, bytes32 lo) {
        uint256 u = uint256(h);
        hi = bytes32(uint256(uint128(u >> 128)));
        lo = bytes32(uint256(uint128(u)));
    }
}
