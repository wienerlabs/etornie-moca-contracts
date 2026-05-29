// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title EtornieIpToken
/// @author Etornie AG / Wiener Labs
/// @notice Soul-bound IP-case NFT — EVM port of the Solana
///         `etornie-ip-token` Token-2022 + `DefaultAccountState=Frozen`
///         program. Once minted into a client wallet the token is
///         non-transferable. The operator can burn when the case reaches a
///         terminal closed state; off-chain enforcement of the precondition
///         mirrors the Solana program's design.
/// @dev Soul-bound is enforced via an `_update` override that reverts any
///      transfer where both `from` and `to` are non-zero (i.e. it is neither
///      a mint nor a burn).
contract EtornieIpToken is ERC721, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct CaseRecord {
        bytes16 caseId;
        address clientWallet;
        address operator;
        bytes32 metadataUriHash;
        uint64 mintedAt;
        uint64 burnedAt;
    }

    /// @notice Per-case record keyed by `case_id` (16-byte UUID).
    mapping(bytes16 => CaseRecord) public records;

    /// @notice `tokenId` → `case_id` reverse lookup for indexers.
    mapping(uint256 => bytes16) public tokenToCase;

    event CaseNftMinted(
        bytes16 indexed caseId,
        uint256 indexed tokenId,
        address indexed clientWallet,
        address operator,
        bytes32 metadataUriHash,
        uint64 timestamp
    );

    event CaseNftBurned(
        bytes16 indexed caseId,
        uint256 indexed tokenId,
        address operator,
        uint64 timestamp
    );

    error AlreadyMinted(bytes16 caseId);
    error AlreadyBurned(bytes16 caseId);
    error NotMinted(bytes16 caseId);
    error SoulBound();

    constructor(address admin, address initialOperator)
        ERC721("Etornie Case NFT", "ETRNFT")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, initialOperator);
    }

    /// @notice Mint a soul-bound case NFT to a client wallet.
    /// @dev `tokenId` is deterministic: `uint256(uint128(caseId))`. The first
    ///      128 bits of `tokenId` are always zero, leaving room for an
    ///      optional version prefix in a future upgrade.
    /// @param caseId           16-byte case UUID.
    /// @param clientWallet     The wallet that will hold the soul-bound NFT.
    /// @param metadataUriHash  sha256 of the off-chain metadata URI.
    function mintCaseNft(
        bytes16 caseId,
        address clientWallet,
        bytes32 metadataUriHash
    ) external onlyRole(OPERATOR_ROLE) returns (uint256 tokenId) {
        CaseRecord storage r = records[caseId];
        if (r.mintedAt != 0) revert AlreadyMinted(caseId);

        tokenId = uint256(uint128(caseId));
        tokenToCase[tokenId] = caseId;

        r.caseId = caseId;
        r.clientWallet = clientWallet;
        r.operator = msg.sender;
        r.metadataUriHash = metadataUriHash;
        r.mintedAt = uint64(block.timestamp);

        _safeMint(clientWallet, tokenId);

        emit CaseNftMinted(
            caseId,
            tokenId,
            clientWallet,
            msg.sender,
            metadataUriHash,
            r.mintedAt
        );
    }

    /// @notice Burn the soul-bound case NFT. Backend must enforce the
    ///         terminal-state precondition off-chain.
    /// @param caseId 16-byte case UUID.
    function burnCaseNft(bytes16 caseId) external onlyRole(OPERATOR_ROLE) {
        CaseRecord storage r = records[caseId];
        if (r.mintedAt == 0) revert NotMinted(caseId);
        if (r.burnedAt != 0) revert AlreadyBurned(caseId);

        uint256 tokenId = uint256(uint128(caseId));
        r.burnedAt = uint64(block.timestamp);

        _burn(tokenId);

        emit CaseNftBurned(caseId, tokenId, msg.sender, r.burnedAt);
    }

    /// @notice Soul-bound enforcement: block any transfer that is not a mint
    ///         (`from == 0`) or burn (`to == 0`).
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert SoulBound();
        return super._update(to, tokenId, auth);
    }

    /// @inheritdoc ERC721
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
