# NFT Metadata Standard

This document outlines the NFT metadata standards used by Elata Protocol's `InAppContent721` and related contracts, including recommended hosting strategies.

## Overview

Elata Protocol uses ERC-721 NFTs for in-app content delivery. Each app can deploy its own NFT collection via the `AppModuleFactory`.

## Metadata Standard

### Token URI Structure

Token URIs follow the [ERC-721 Metadata Standard](https://eips.ethereum.org/EIPS/eip-721):

```json
{
  "name": "Content Title",
  "description": "Description of the content",
  "image": "ipfs://QmXxx.../image.png",
  "external_url": "https://app.elata.bio/content/123",
  "attributes": [
    {
      "trait_type": "Category",
      "value": "Article"
    },
    {
      "trait_type": "Creator",
      "value": "0x1234..."
    },
    {
      "trait_type": "App",
      "value": "Elata App Name"
    },
    {
      "display_type": "date",
      "trait_type": "Created",
      "value": 1700000000
    }
  ],
  "animation_url": "ipfs://QmYyy.../video.mp4",
  "content": {
    "type": "article",
    "uri": "ipfs://QmZzz.../content.json"
  }
}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Human-readable title |
| `description` | string | Brief description (max 500 chars recommended) |
| `image` | string | URI to preview image (required for marketplace display) |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `external_url` | string | Link to Elata frontend for content viewing |
| `attributes` | array | OpenSea-compatible trait array |
| `animation_url` | string | Video/audio content URL |
| `content` | object | Extended content reference for app-specific data |

### Contract URI (Collection Metadata)

The `InAppContent721` contract supports `contractURI()` for collection-level metadata:

```json
{
  "name": "App Name Content Collection",
  "description": "NFT collection for App Name in-app content",
  "image": "ipfs://QmColl.../logo.png",
  "external_link": "https://app.elata.bio/app/123",
  "seller_fee_basis_points": 500,
  "fee_recipient": "0xCreatorAddress..."
}
```

## Hosting Strategy

### Recommended: IPFS + Pinata

For decentralized, permanent storage:

1. **Upload content to IPFS** using Pinata, NFT.Storage, or similar service
2. **Pin metadata JSON** to IPFS
3. **Set token URI** to `ipfs://` gateway

```solidity
// Example: Setting metadata
content721.setTokenURI(tokenId, "ipfs://QmXxx.../metadata.json");
```

### Alternative: Arweave

For truly permanent storage with one-time payment:

1. **Upload to Arweave** using Bundlr or ArDrive
2. **Use `ar://` URI scheme**

```
ar://ABC123XYZ...
```

### Fallback: Centralized (Development Only)

For development/testing:

```
https://api.elata.bio/metadata/{tokenId}
```

**Note:** Centralized hosting should be migrated to IPFS/Arweave before mainnet launch.

## Implementation Details

### InAppContent721 Contract

The contract implements **ERC-4906** for metadata update signaling, which helps marketplaces and indexers know when to refresh token metadata.

```solidity
// Token URI management
function setTokenURI(uint256 tokenId, string memory uri) external onlyOwner;
function batchSetTokenURI(uint256[] calldata tokenIds, string[] calldata uris) external onlyOwner;
function tokenURI(uint256 tokenId) external view returns (string memory);

// Collection metadata
function setContractURI(string memory uri) external onlyOwner;
function contractURI() external view returns (string memory);

// ERC-4906 events (emitted automatically on URI updates)
event MetadataUpdate(uint256 _tokenId);
event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

// Manual metadata refresh signal (for off-chain updates)
function emitBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) external onlyOwner;
```

### ERC-4906 Integration

When you update token metadata (via `setTokenURI` or `batchSetTokenURI`), the contract automatically emits ERC-4906 events. Marketplaces like OpenSea, Blur, and LooksRare listen for these events to refresh cached metadata.

For off-chain metadata updates (e.g., you updated the JSON on IPFS but the URI stayed the same), use `emitBatchMetadataUpdate()` to signal indexers to refresh.

### ContentStore Integration

When content is listed via `ContentStore`, the associated NFT metadata should:

1. Reference the content listing ID
2. Include price and availability info in attributes
3. Link to the original content on IPFS

### Soulbound Tokens

`InAppContent721` supports soulbound (non-transferable) tokens:

```solidity
function setSoulbound(uint256 tokenId, bool isSoulbound) external onlyMinter;
```

Soulbound tokens:
- Cannot be transferred after minting
- Represent non-tradeable achievements, access passes, or credentials
- Still have standard metadata

## Best Practices

### Image Guidelines

| Asset | Recommended Size | Format |
|-------|------------------|--------|
| Token Image | 1000x1000px | PNG, JPEG, GIF |
| Animation | 1920x1080px max | MP4, WEBM |
| Collection Logo | 500x500px | PNG |

### Content Organization

```
content/
├── {contentId}/
│   ├── metadata.json     # Token metadata
│   ├── image.png         # Preview image
│   ├── content.json      # Full content (if applicable)
│   └── media/            # Additional assets
│       ├── video.mp4
│       └── audio.mp3
```

### Pinning Strategy

1. **Immediate pin** on content creation
2. **Redundant pinning** via multiple services (Pinata + NFT.Storage)
3. **Regular pin verification** via automated checks

## Frontend Integration

### Fetching Metadata

```typescript
async function getTokenMetadata(tokenId: number): Promise<Metadata> {
  const uri = await contract.tokenURI(tokenId);
  
  // Handle IPFS URIs
  const url = uri.startsWith('ipfs://')
    ? `https://ipfs.io/ipfs/${uri.slice(7)}`
    : uri;
    
  const response = await fetch(url);
  return response.json();
}
```

### Displaying Content

1. Fetch metadata via `tokenURI()`
2. Resolve IPFS gateway URL
3. Display image/content with appropriate loading states
4. Cache aggressively (IPFS content is immutable)

## Migration Path

### From Centralized to IPFS

1. Upload existing metadata to IPFS
2. Record mapping of `tokenId → ipfsHash`
3. Call `setTokenURI()` for each token (batch via multicall)
4. Update frontend to use new URIs

### Contract Upgrade Path

If metadata format changes are needed:
1. Deploy new `InAppContent721` via `AppModuleFactory`
2. Migrate holders via airdrop to new collection
3. Decommission old contract (mark read-only)

## Related Contracts

- `InAppContent721.sol` - NFT minting and URI management
- `ContentStore.sol` - Content listing and purchase logic
- `AppModuleFactory.sol` - Module deployment

## References

- [EIP-721: Non-Fungible Token Standard](https://eips.ethereum.org/EIPS/eip-721)
- [EIP-721 Metadata Extension](https://eips.ethereum.org/EIPS/eip-721#specification)
- [EIP-4906: Metadata Update Extension](https://eips.ethereum.org/EIPS/eip-4906)
- [OpenSea Metadata Standards](https://docs.opensea.io/docs/metadata-standards)
- [IPFS Documentation](https://docs.ipfs.tech/)
- [Arweave Documentation](https://docs.arweave.org/)
