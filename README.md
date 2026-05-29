# etornie-moca-contracts

Solidity port of the Etornie Solana programs, deployed on **Moca Chain** (EVMOS-based L1) for the Animoca grant track.

Three contracts mirror the original `etornie-solana` Anchor programs:

| Solana program (Anchor)        | EVM contract (Solidity)        | Purpose |
|--------------------------------|--------------------------------|---------|
| `etornie-attestation`          | `EtornieAttestation.sol`       | Per-case on-chain attestation + lifecycle event log |
| `etornie-ip-token`             | `EtornieIpToken.sol`           | Soul-bound ERC-721 case NFT (mint/burn only) |
| `etornie-zk-verifier`          | `EtornieZkVerifier.sol`        | Groth16 verifier with three circuits: HelloWorld, FileOwnership, Compliance (x402) |

> Built by [Wiener Labs](https://wienerlabs.com) for [Etornie AG](https://etornie.com) (Ruessenstrasse 5, 6340 Baar, Switzerland).

## Stack

- **Foundry** (forge, cast, anvil) — Solidity 0.8.24, evm-version `shanghai`
- **OpenZeppelin Contracts v5.0.2** — `ERC721`, `AccessControl`
- **No external runtime deps** — all OZ utilities + forge-std vendored under `lib/`

## Network

[Moca Chain](https://docs.moca.network) is an EVMOS-based L1 with London opcodes and partial Shanghai support. Native token `$MOCA`, ~1 s block time, 60 M gas limit.

| Network  | Chain ID  | RPC                                      | Explorer                                     |
|----------|-----------|------------------------------------------|----------------------------------------------|
| Testnet  | `222888`  | `https://rpc.testnet.mocachain.dev`      | https://testnet-scan.mocachain.org           |
| Mainnet  | `2288`    | `https://rpc.mocachain.org` (API key)    | https://scan.mocachain.org                   |

Testnet faucet: <https://faucet.mocachain.org>.

## Quick start

```bash
git clone https://github.com/wienerlabs/etornie-moca-contracts.git
cd etornie-moca-contracts
forge install   # pulls forge-std + openzeppelin-contracts

forge build
forge test -vvv
```

## Deploy to Moca Testnet

1. **Get test MOCA** from the [faucet](https://faucet.mocachain.org) for the deployer address.
2. **Configure env** — copy `.env.example` to `.env`, fill `PRIVATE_KEY` + `MOCA_TESTNET_RPC`.
3. **Dry-run** (no broadcast):

   ```bash
   source .env
   forge script script/Deploy.s.sol --rpc-url moca_testnet
   ```

4. **Broadcast**:

   ```bash
   forge script script/Deploy.s.sol --rpc-url moca_testnet --broadcast --private-key $PRIVATE_KEY
   ```

5. **Verify on explorer**: `https://testnet-scan.mocachain.org/address/<DEPLOYED_ADDRESS>`

## Contract notes

### `EtornieAttestation`

- One record per `case_id` (16-byte UUID). Subsequent `create` reverts.
- `update` emits `CaseAttestationUpdated` with `oldMetadataHash` + `newMetadataHash` so the tx log alone is a full timeline.
- Writes gated by `OPERATOR_ROLE`. Admin can rotate operators via `grantRole` / `revokeRole`.

### `EtornieIpToken`

- ERC-721 with `_update` override that reverts on transfer (allows only mint and burn) — matches the Solana `DefaultAccountState=Frozen` design.
- `tokenId` is deterministic: `uint256(uint128(caseId))`. Top 128 bits reserved.
- Mint + burn gated by `OPERATOR_ROLE`. Burn precondition (case in terminal state) is enforced off-chain by the backend.

### `EtornieZkVerifier`

- Wraps three Groth16 verifier sub-contracts (one per circuit). Sub-verifier addresses are admin-settable so each circuit's verifying key can be rotated.
- Records are keyed by `keccak256(user, digest)` so the same proof cannot be replayed against the same user.
- `verifyFileOwnership` / `verifyCompliance` mirror the Solana canonical encoding of `(hi, lo)` halves to close the grief vector where unused high bits could map distinct hashes to the same slot.
- Auto-generated snarkjs Groth16 verifier contracts (one per circuit) are deployed separately and registered via `setHelloWorldVerifier` / `setFileOwnershipVerifier` / `setComplianceVerifier`. Circom source lives in the [`etornie-solana`](https://github.com/wienerlabs/etornie-solana) repo under `circuits/`.

## Tests

```
forge test -vvv
```

Current suite:

| Suite                      | Tests | Coverage focus |
|----------------------------|-------|----------------|
| `EtornieAttestation.t.sol` | 7     | create, update, role gating, duplicate revert, fuzz on case IDs |
| `EtornieIpToken.t.sol`     | 9     | mint, burn, soul-bound revert (transfer + safeTransfer), interface ids |
| `EtornieZkVerifier.t.sol`  | 9     | verify success (×3 circuits), mismatched digest, replay, invalid proof, malformed input |

All 25 tests pass locally (`forge test`).

## Project layout

```
.
├── src/
│   ├── EtornieAttestation.sol
│   ├── EtornieIpToken.sol
│   └── EtornieZkVerifier.sol
├── test/
│   ├── EtornieAttestation.t.sol
│   ├── EtornieIpToken.t.sol
│   └── EtornieZkVerifier.t.sol
├── script/
│   └── Deploy.s.sol
├── lib/
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── foundry.toml
├── remappings.txt
├── .env.example
├── LICENSE
└── README.md
```

## Deployed addresses

### Moca Testnet (chain ID `222888`)

| Contract             | Address                                                                                                                       | Tx |
|----------------------|--------------------------------------------------------------------------------------------------------------------------------|----|
| `EtornieAttestation` | [`0x79987a54DB54680bd4c3Ac3AbF1E34D723180e56`](https://testnet-scan.mocachain.org/address/0x79987a54DB54680bd4c3Ac3AbF1E34D723180e56) | [`0xd7f218f6…02c3db`](https://testnet-scan.mocachain.org/tx/0xd7f218f6584fd696089c0a4ac537dc18b707cd8a13a850a668151d1f7f02c3db) |
| `EtornieIpToken`     | [`0x81222d1f6FcA1b47F87F2ffDbBE77259Ce85ee2F`](https://testnet-scan.mocachain.org/address/0x81222d1f6FcA1b47F87F2ffDbBE77259Ce85ee2F) | [`0x9cc2a7fc…62dbb`](https://testnet-scan.mocachain.org/tx/0x9cc2a7fcfdce1ab4ff8f96a3dac09e9806b59e5d9d0e8434ec98a554c1462dbb) |
| `EtornieZkVerifier`  | [`0xeeb6d9973437C54d000BF2388147ae179723DCfC`](https://testnet-scan.mocachain.org/address/0xeeb6d9973437C54d000BF2388147ae179723DCfC) | [`0xf4bdaa41…bb9c70c`](https://testnet-scan.mocachain.org/tx/0xf4bdaa417188bb012b9013663d0e2e93e77b6a01411442f89e2d0ad52bb9c70c) |

Admin + operator on every contract: `0x6345eE23c81132A3b3245E2fcB55374205A2C8c4` (initial deployer; rotate via `grantRole` / `revokeRole` before mainnet).

Deploy gas: ~0.0031 MOCA total (~3.1 M gas at ~1 Gwei) across the three contracts.

### Moca Mainnet (chain ID `2288`)

Not deployed yet.

## Related

- [`etornie-solana`](https://github.com/wienerlabs/etornie-solana) — original Anchor programs + Circom circuits
- [`etornie.xyz`](https://github.com/wienerlabs/etornie.xyz) — marketing site
- [Etornie product](https://etornie.com) — production app at `app.etornie.com`

## License

MIT — see [LICENSE](LICENSE).
