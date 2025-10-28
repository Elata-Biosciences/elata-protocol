# XP Operators Runbook

## Roles
- XP operators can: `award`, `revoke`, `setMerkleRoot`.
- Admins (DEFAULT_ADMIN_ROLE) can grant/revoke `XP_OPERATOR_ROLE`.

## Grant operator
```bash
pnpm ts-node scripts/xp/xp-grant-operators.ts \
  --rpc $RPC \
  --key $ADMIN_PK \
  --contract $XP_ADDR \
  --ops 0xOperator1,0xOperator2
```

## Revoke operator
Use the same script with `--revoke` or call directly via a wallet:
```solidity
xp.revokeRole(XP_OPERATOR_ROLE, 0xOperator1);
```

## Publish distribution
1) Generate canonical JSON in appstore/public
```bash
pnpm ts-node ../elata-protocol/scripts/xp/xp-generate-merkle.ts \
  --in scripts/xp/data/allocs.json \
  --out public/xp-distribution.json \
  --id <N>
```
2) Publish root on-chain
```bash
pnpm ts-node ../elata-protocol/scripts/xp/xp-publish-root.ts \
  --rpc $RPC --key $OPERATOR_PK --contract $XP_ADDR \
  --json public/xp-distribution.json
```

## Rotation
1) Grant role to new operator
2) Switch backend to new key and publish next root
3) Revoke old operator

## Emergency
- If a bad root is set, revoke the responsible operator. Use `revoke(user, amount)` to remove illegitimate XP.






