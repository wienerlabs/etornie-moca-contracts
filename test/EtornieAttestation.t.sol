// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EtornieAttestation} from "../src/EtornieAttestation.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract EtornieAttestationTest is Test {
    EtornieAttestation att;

    address admin = address(0xA11CE);
    address operator = address(0x0FFE);
    address newOperator = address(0xBEEF);
    address creator = address(0xC2EA);
    address client = address(0xC1EA);
    address stranger = address(0xDEAD);

    bytes16 constant CASE_ID = bytes16(uint128(0x4159d4f64a3e4e2c8b7a9e1f2d3c4b5a));
    bytes32 constant META = bytes32(uint256(0x1111));
    bytes32 constant META2 = bytes32(uint256(0x2222));

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

    function setUp() public {
        att = new EtornieAttestation(admin, operator);
    }

    function test_createCaseAttestation_success() public {
        vm.expectEmit(true, true, true, true);
        emit CaseAttestationCreated(CASE_ID, META, creator, client, operator, uint64(block.timestamp));

        vm.prank(operator);
        att.createCaseAttestation(CASE_ID, META, creator, client);

        (
            bytes16 cid,
            bytes32 mh,
            address cr,
            address cw,
            address op,
            uint64 createdAt,
            bool exists
        ) = att.cases(CASE_ID);
        assertEq(cid, CASE_ID);
        assertEq(mh, META);
        assertEq(cr, creator);
        assertEq(cw, client);
        assertEq(op, operator);
        assertEq(createdAt, uint64(block.timestamp));
        assertTrue(exists);
        assertTrue(att.exists(CASE_ID));
    }

    function test_create_revertsOnDuplicate() public {
        vm.prank(operator);
        att.createCaseAttestation(CASE_ID, META, creator, client);

        vm.expectRevert(abi.encodeWithSelector(EtornieAttestation.AttestationAlreadyExists.selector, CASE_ID));
        vm.prank(operator);
        att.createCaseAttestation(CASE_ID, META, creator, client);
    }

    function test_create_revertsForNonOperator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                att.OPERATOR_ROLE()
            )
        );
        vm.prank(stranger);
        att.createCaseAttestation(CASE_ID, META, creator, client);
    }

    function test_updateCaseAttestation_success() public {
        vm.prank(operator);
        att.createCaseAttestation(CASE_ID, META, creator, client);

        vm.expectEmit(true, true, true, true);
        emit CaseAttestationUpdated(CASE_ID, META, META2, 7, creator, operator, uint64(block.timestamp));

        vm.prank(operator);
        att.updateCaseAttestation(CASE_ID, META2, 7, creator);

        (, bytes32 mh, , , , , ) = att.cases(CASE_ID);
        assertEq(mh, META2);
    }

    function test_update_revertsOnMissing() public {
        vm.expectRevert(abi.encodeWithSelector(EtornieAttestation.AttestationNotFound.selector, CASE_ID));
        vm.prank(operator);
        att.updateCaseAttestation(CASE_ID, META2, 0, creator);
    }

    function test_adminCanGrantOperatorRole() public {
        bytes32 role = att.OPERATOR_ROLE();
        vm.prank(admin);
        att.grantRole(role, newOperator);

        vm.prank(newOperator);
        att.createCaseAttestation(CASE_ID, META, creator, client);

        assertTrue(att.exists(CASE_ID));
    }

    function testFuzz_createWithRandomCaseIds(bytes16 caseId1, bytes16 caseId2, bytes32 hash) public {
        vm.assume(caseId1 != caseId2);
        vm.startPrank(operator);
        att.createCaseAttestation(caseId1, hash, creator, client);
        att.createCaseAttestation(caseId2, hash, creator, client);
        vm.stopPrank();
        assertTrue(att.exists(caseId1));
        assertTrue(att.exists(caseId2));
    }
}
