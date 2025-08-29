# Yoink NFT Metadata

This directory contains the NFT metadata for Yoink NFTs.

## Metadata Structure

The `yoink-metadata.json` file follows the OpenSea metadata standard and includes:

- **name**: The name of the NFT
- **description**: A description of what the NFT represents
- **image**: The IPFS URI of the NFT image
- **external_url**: Link to the project repository
- **attributes**: NFT traits/attributes
- **properties**: Additional metadata properties

## Setup Instructions

1. **Upload your image to IPFS** (e.g., using Pinata):
   - Upload your NFT image file
   - Copy the IPFS CID

2. **Update the metadata file**:
   - Replace `YOUR_IMAGE_CID_HERE` in `yoink-metadata.json` with your actual image CID
   - Update the `external_url` to point to your actual repository

3. **Upload the metadata to IPFS**:
   - Upload the updated `yoink-metadata.json` file to IPFS
   - Copy the metadata CID

4. **Update the contract**:
   - Replace `YOUR_METADATA_CID_HERE` in `src/YoinkMaster.sol` with your metadata CID

## Example

If your image CID is `QmXxxx...` and your metadata CID is `QmYyyy...`:

```json
{
  "image": "ipfs://QmXxxx...",
  "properties": {
    "files": [
      {
        "uri": "ipfs://QmXxxx...",
        "type": "image/png"
      }
    ]
  }
}
```

And in the contract:
```solidity
: "ipfs://QmYyyy...";
```

## Metadata Standards

This metadata follows:
- [OpenSea Metadata Standards](https://docs.opensea.io/docs/metadata-standards)
- [ERC-721 Metadata Extension](https://eips.ethereum.org/EIPS/eip-721)
