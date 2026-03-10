# Elata XP System

## Overview
ElataPoints is a non-transferable ERC20Votes token used for governance weight and rewards. XP can be issued via:
- Direct award by operator (`award`)
- Off-chain signature (`updateBySig`)
- Merkle-based per-epoch claims (`claimXP`)

This document describes the Merkle distribution flow, delta semantics, operator roles, JSON format, security, and runbooks.

## Delta per distribution
- Each distribution (epoch) encodes incremental XP to mint for that epoch.
- Decreases/decay are handled via operator `revoke(address, amount)`; do not use negative Merkle values.

## On-chain data
- `currentDistributionId`: incremental id
- `merkleRoots[id]`: Merkle root for epoch
- `distributionDataHash[id]`: keccak256 of canonical JSON (full file)
- `hasClaimed(id,user)`: true after user claims

## Claim logic
1. Verify `merkleRoots[id] != 0` and `amount > 0` and not already claimed
2. Leaf = `keccak256(abi.encodePacked(user, amount))`
3. `MerkleProof.verify(proof, root, leaf)` with pair sorting semantics
4. Mark claimed, mint `amount`, self-delegate if none, emit `XPClaimed` and `XPAwarded`

## Canonical JSON schema
```json
{
  "distributionId": 7,
  "merkleRoot": "0x…",
  "dataHash": "0x…",
  "claims": {
    "0xabc...": { "amount": "100000000000000000000", "proof": ["0x..","0x.."] }
  }
}
```
- Addresses are lowercased keys
- `amount` is a decimal string in wei
- `proof` is leaf→root order, hex `0x`-prefixed
- `dataHash = keccak256(utf8Bytes(full minified JSON))`

## Tooling
- `scripts/xp/xp-generate-merkle.ts`: Build tree `{ sortPairs: true }`, aggregate duplicates, drop zeros, output canonical JSON and `dataHash`
- `scripts/xp/xp-publish-root.ts`: Validate JSON `dataHash`, call `setMerkleRoot(root,dataHash)` using Viem

## Frontend
- Loads `/xp-distribution.json`
- Validates on-chain vs file (id, root, dataHash)
- If eligible, calls `claimXP(id, amount, proof)` via wagmi/viem
- Refreshes `balanceOf` and updates tier

## Operator roles and rotation
- `XP_OPERATOR_ROLE` can `award`, `revoke`, `setMerkleRoot`
- Rotation:
  1. Admin `grantRole(XP_OPERATOR_ROLE, new)`
  2. Use new key to publish next root
  3. Admin `revokeRole(XP_OPERATOR_ROLE, old)`

## Security notes
- Claims are O(log n) hashing; state writes are minimal
- Events monitored: `MerkleRootUpdated`, `XPClaimed`, `XPAwarded`
- If compromised root is published, revoke XP from affected addresses and rotate operator
- Consider adding `pauseClaims` in a future update

## Test plan
- Foundry: success/failure cases, role gating, rotation
- Node: generator determinism, proof round-trip, duplicate aggregation
- Manual E2E: testnet publish, UI claim, block mismatched JSON

## Updating Merkle trees
1. Prepare allocations (JSON/CSV) with `{ address, amountWei }`
2. Generate canonical file:
```bash
pnpm ts-node scripts/xp/xp-generate-merkle.ts \
  --in scripts/xp/data/allocs.json \
  --out ./output/xp-distribution.json \
  --id <N>
```
3. Publish root:
```bash
pnpm ts-node scripts/xp/xp-publish-root.ts \
  --rpc $RPC --key $OPERATOR_PK --contract $XP_ADDR \
  --json ./output/xp-distribution.json
```
4. Users claim via the frontend; UI validates proofs and enables claim

## How normal users update values
- Users do not publish roots; operators do
- Users influence their XP inputs by participating in protocol activities (apps launched, staking, governance)
- Off-chain pipeline aggregates activity into allocations; if disputes, operators can include corrections in next epoch or revoke


