// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EtornieIpToken} from "../src/EtornieIpToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract EtornieIpTokenTest is Test {
    EtornieIpToken nft;

    address admin = address(0xA11CE);
    address operator = address(0x0FFE);
    address client = address(0xC1EA);
    address other = address(0xDEAD);

    bytes16 constant CASE_ID = bytes16(uint128(0x4159d4f64a3e4e2c8b7a9e1f2d3c4b5a));
    bytes32 constant URI_HASH = bytes32(uint256(0xCAFE));

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

    function setUp() public {
        nft = new EtornieIpToken(admin, operator);
    }

    function _expectedTokenId(bytes16 caseId) internal pure returns (uint256) {
        return uint256(uint128(caseId));
    }

    function test_mint_success() public {
        uint256 expectedTokenId = _expectedTokenId(CASE_ID);

        vm.expectEmit(true, true, true, true);
        emit CaseNftMinted(CASE_ID, expectedTokenId, client, operator, URI_HASH, uint64(block.timestamp));

        vm.prank(operator);
        uint256 tokenId = nft.mintCaseNft(CASE_ID, client, URI_HASH);

        assertEq(tokenId, expectedTokenId);
        assertEq(nft.ownerOf(tokenId), client);
        assertEq(nft.tokenToCase(tokenId), CASE_ID);

        (
            bytes16 cid,
            address cw,
            address op,
            bytes32 mh,
            uint64 mintedAt,
            uint64 burnedAt
        ) = nft.records(CASE_ID);
        assertEq(cid, CASE_ID);
        assertEq(cw, client);
        assertEq(op, operator);
        assertEq(mh, URI_HASH);
        assertEq(mintedAt, uint64(block.timestamp));
        assertEq(burnedAt, 0);
    }

    function test_mint_revertsOnDuplicate() public {
        vm.prank(operator);
        nft.mintCaseNft(CASE_ID, client, URI_HASH);

        vm.expectRevert(abi.encodeWithSelector(EtornieIpToken.AlreadyMinted.selector, CASE_ID));
        vm.prank(operator);
        nft.mintCaseNft(CASE_ID, client, URI_HASH);
    }

    function test_mint_revertsForNonOperator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                other,
                nft.OPERATOR_ROLE()
            )
        );
        vm.prank(other);
        nft.mintCaseNft(CASE_ID, client, URI_HASH);
    }

    function test_burn_success() public {
        vm.prank(operator);
        uint256 tokenId = nft.mintCaseNft(CASE_ID, client, URI_HASH);

        vm.expectEmit(true, true, true, true);
        emit CaseNftBurned(CASE_ID, tokenId, operator, uint64(block.timestamp));

        vm.prank(operator);
        nft.burnCaseNft(CASE_ID);

        (, , , , , uint64 burnedAt) = nft.records(CASE_ID);
        assertEq(burnedAt, uint64(block.timestamp));
    }

    function test_burn_revertsOnAlreadyBurned() public {
        vm.startPrank(operator);
        nft.mintCaseNft(CASE_ID, client, URI_HASH);
        nft.burnCaseNft(CASE_ID);

        vm.expectRevert(abi.encodeWithSelector(EtornieIpToken.AlreadyBurned.selector, CASE_ID));
        nft.burnCaseNft(CASE_ID);
        vm.stopPrank();
    }

    function test_burn_revertsOnNotMinted() public {
        vm.expectRevert(abi.encodeWithSelector(EtornieIpToken.NotMinted.selector, CASE_ID));
        vm.prank(operator);
        nft.burnCaseNft(CASE_ID);
    }

    function test_soulBound_revertsOnTransfer() public {
        vm.prank(operator);
        uint256 tokenId = nft.mintCaseNft(CASE_ID, client, URI_HASH);

        vm.expectRevert(EtornieIpToken.SoulBound.selector);
        vm.prank(client);
        nft.transferFrom(client, other, tokenId);
    }

    function test_soulBound_revertsOnSafeTransfer() public {
        vm.prank(operator);
        uint256 tokenId = nft.mintCaseNft(CASE_ID, client, URI_HASH);

        vm.expectRevert(EtornieIpToken.SoulBound.selector);
        vm.prank(client);
        nft.safeTransferFrom(client, other, tokenId);
    }

    function test_supportsInterface_AccessControl_ERC721() public view {
        // ERC-721 interface ID
        assertTrue(nft.supportsInterface(0x80ac58cd));
        // AccessControl interface ID
        assertTrue(nft.supportsInterface(0x7965db0b));
        // Unknown interface
        assertFalse(nft.supportsInterface(0xffffffff));
    }
}
