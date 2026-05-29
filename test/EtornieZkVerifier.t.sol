// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    EtornieZkVerifier,
    IGroth16Verifier1,
    IGroth16Verifier3
} from "../src/EtornieZkVerifier.sol";

// ---- Mock sub-verifiers ----

contract MockVerifier1 is IGroth16Verifier1 {
    bool public accept;
    function setAccept(bool v) external { accept = v; }
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[1] calldata
    ) external view returns (bool) { return accept; }
}

contract MockVerifier3 is IGroth16Verifier3 {
    bool public accept;
    function setAccept(bool v) external { accept = v; }
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[3] calldata
    ) external view returns (bool) { return accept; }
}

// ---- Test ----

contract EtornieZkVerifierTest is Test {
    EtornieZkVerifier zk;
    MockVerifier1 hwVerifier;
    MockVerifier3 foVerifier;
    MockVerifier3 cpVerifier;

    address admin = address(0xA11CE);
    address user = address(0xCAFE);

    // Dummy Groth16 proof tuple — values are irrelevant, mock verifier ignores.
    uint256[2] zeroA = [uint256(0), 0];
    uint256[2][2] zeroB = [[uint256(0), 0], [uint256(0), 0]];
    uint256[2] zeroC = [uint256(0), 0];

    function setUp() public {
        zk = new EtornieZkVerifier(admin);
        hwVerifier = new MockVerifier1();
        foVerifier = new MockVerifier3();
        cpVerifier = new MockVerifier3();

        vm.startPrank(admin);
        zk.setHelloWorldVerifier(hwVerifier);
        zk.setFileOwnershipVerifier(foVerifier);
        zk.setComplianceVerifier(cpVerifier);
        vm.stopPrank();
    }

    // ---- HelloWorld ----

    function test_helloWorld_success() public {
        hwVerifier.setAccept(true);
        uint256[1] memory inputs = [uint256(42)];
        bytes32 digest = sha256(abi.encodePacked(bytes32(inputs[0])));

        vm.prank(user);
        zk.verifyHelloWorld(zeroA, zeroB, zeroC, inputs, digest);

        bytes32 slot = keccak256(abi.encode(user, digest));
        (address u, bytes32 d, uint64 ts, bool exists) = zk.proofRecords(slot);
        assertEq(u, user);
        assertEq(d, digest);
        assertEq(ts, uint64(block.timestamp));
        assertTrue(exists);
    }

    function test_helloWorld_revertsOnMismatchedDigest() public {
        hwVerifier.setAccept(true);
        uint256[1] memory inputs = [uint256(42)];
        bytes32 wrongDigest = bytes32(uint256(0xDEAD));

        vm.expectRevert(EtornieZkVerifier.MismatchedDigest.selector);
        vm.prank(user);
        zk.verifyHelloWorld(zeroA, zeroB, zeroC, inputs, wrongDigest);
    }

    function test_helloWorld_revertsOnReplay() public {
        hwVerifier.setAccept(true);
        uint256[1] memory inputs = [uint256(42)];
        bytes32 digest = sha256(abi.encodePacked(bytes32(inputs[0])));

        vm.prank(user);
        zk.verifyHelloWorld(zeroA, zeroB, zeroC, inputs, digest);

        vm.expectRevert(EtornieZkVerifier.ReplayedProof.selector);
        vm.prank(user);
        zk.verifyHelloWorld(zeroA, zeroB, zeroC, inputs, digest);
    }

    function test_helloWorld_revertsOnInvalidProof() public {
        hwVerifier.setAccept(false);
        uint256[1] memory inputs = [uint256(42)];
        bytes32 digest = sha256(abi.encodePacked(bytes32(inputs[0])));

        vm.expectRevert(EtornieZkVerifier.InvalidProof.selector);
        vm.prank(user);
        zk.verifyHelloWorld(zeroA, zeroB, zeroC, inputs, digest);
    }

    function test_helloWorld_revertsWhenVerifierNotSet() public {
        EtornieZkVerifier blank = new EtornieZkVerifier(admin);

        uint256[1] memory inputs = [uint256(42)];
        bytes32 digest = sha256(abi.encodePacked(bytes32(inputs[0])));

        vm.expectRevert(
            abi.encodeWithSelector(
                EtornieZkVerifier.VerifierNotSet.selector,
                EtornieZkVerifier.ProofKind.HelloWorld
            )
        );
        vm.prank(user);
        blank.verifyHelloWorld(zeroA, zeroB, zeroC, inputs, digest);
    }

    // ---- File ownership ----

    function _splitHash(bytes32 h) internal pure returns (bytes32 hi, bytes32 lo) {
        uint256 u = uint256(h);
        hi = bytes32(uint256(uint128(u >> 128)));
        lo = bytes32(uint256(uint128(u)));
    }

    function test_fileOwnership_success() public {
        foVerifier.setAccept(true);

        bytes32 fileHash = keccak256("some file");
        (bytes32 hi, bytes32 lo) = _splitHash(fileHash);
        uint256[3] memory inputs = [uint256(hi), uint256(lo), uint256(0xC0FFEE)];

        vm.prank(user);
        zk.verifyFileOwnership(zeroA, zeroB, zeroC, inputs, fileHash);

        bytes32 slot = keccak256(abi.encode(user, fileHash));
        (address owner, bytes32 fh, bytes32 commitment, , bool exists) =
            zk.fileOwnershipRecords(slot);
        assertEq(owner, user);
        assertEq(fh, fileHash);
        assertEq(commitment, bytes32(uint256(0xC0FFEE)));
        assertTrue(exists);
    }

    function test_fileOwnership_revertsOnMalformedInput() public {
        foVerifier.setAccept(true);
        bytes32 fileHash = keccak256("some file");
        uint256[3] memory bogus = [uint256(1), uint256(2), uint256(3)];

        vm.expectRevert(EtornieZkVerifier.MalformedFileHashInput.selector);
        vm.prank(user);
        zk.verifyFileOwnership(zeroA, zeroB, zeroC, bogus, fileHash);
    }

    // ---- Compliance ----

    function test_compliance_success() public {
        cpVerifier.setAccept(true);

        bytes32 queryHash = keccak256("what is novelty?");
        (bytes32 hi, bytes32 lo) = _splitHash(queryHash);
        uint256[3] memory inputs = [uint256(hi), uint256(lo), uint256(0xBEEF)];

        vm.prank(user);
        zk.verifyCompliance(zeroA, zeroB, zeroC, inputs, queryHash);

        bytes32 slot = keccak256(abi.encode(user, queryHash));
        (address payer, bytes32 qh, bytes32 commitment, , bool exists) =
            zk.complianceRecords(slot);
        assertEq(payer, user);
        assertEq(qh, queryHash);
        assertEq(commitment, bytes32(uint256(0xBEEF)));
        assertTrue(exists);
    }

    function test_compliance_revertsOnMalformedInput() public {
        cpVerifier.setAccept(true);
        bytes32 queryHash = keccak256("hello");
        uint256[3] memory bogus = [uint256(1), uint256(2), uint256(3)];

        vm.expectRevert(EtornieZkVerifier.MalformedQueryHashInput.selector);
        vm.prank(user);
        zk.verifyCompliance(zeroA, zeroB, zeroC, bogus, queryHash);
    }
}
