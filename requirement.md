
- Create SMC
SGDNFT.sol
GDMRegistry.sol

- Demo flow V1: 
plaintext file → encrypt → upload ciphertext to IPFS → buyer pay on-chain → backend verify purchase → return key → buyer decrypt local

1. SMC layer
SGDNFT.sol
GDMRegistry.sol

registerSGD(...) to create record + mint NFT
purchaseFullAccess(tokenId) to record that buyer purchased
getCID(tokenId) or backend read record/CID to get link encrypted file

2. Enryption layer 
use AES-256-GCM 