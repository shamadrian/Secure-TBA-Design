## Research Statement

This repository contains research submitted to the Cryptology and Information Security Conference 2024 (CISC 2024) and accepted for presentation. The conference materials are provided in the conference directory, including the presentation PowerPoint and the research paper. The official conference website is https://cisc2024.ccisa.org.tw/#Session, and the conference number is A3-04.

## Secure TBA Design
This repository explores a security-focused Token Bound Account (TBA) design built on ERC-6551, with guardianship-based recovery, approval tracking, and marketplace-safe listing flow. It includes a minimal ERC-721 NFT, a TBA implementation, a marketplace example, and a Foundry test suite that models common attack paths and mitigations.

## Scope

- ERC-6551 compatible account contract (`TBA`) with guarded execution and approval tracking.
- Guardian-based recovery module to break ownership cycles.
- ERC-721 NFT contract for TBA binding.
- Marketplace example demonstrating safe listing and settlement patterns.
- Foundry tests for ownership cycles, approvals, and marketplace attack simulations.

## Contracts (src)

### Guardian

`Guardian` provides a simple recovery mechanism using a guardian set and vote threshold.

- Initialize up to 3 guardians, with a default threshold of 2.
- Guardians can propose and vote on recovery.
- Recovery executes `breakCycle` (implemented in `TBA`) and clears guardians.
- Includes a recovery window (`recoveryPeriod`).

### TBA

`TBA` is an ERC-6551 account implementation with the following security constraints:

- Owner is the bound token owner (ERC-721 owner).
- `execute` only allows call operations and blocks `approve` and `setApprovalForAll`.
- Tracks token/NFT approvals and operators for later reset.
- `lock` and `unlock` for marketplace-safe transfers.
- `reset` clears approvals and operators to prevent backrun extraction.
- Guardian-based recovery to break ownership cycles.

Public getters:

- `token()` — bound token (chainId, tokenContract, tokenId)
- `owner()` — ERC-721 owner of the bound token
- `getApprovals()` — tracked ERC-20 approvals, ERC-721 approvals, and operators
- `getState()` — lock state
- `getReset()` — whether approvals are clean
- `getReceiver()` — receiver address for timed unlock

### NFT

Minimal ERC-721 for testing TBAs. Minting and burning are restricted to the owner.

### NFTMarketPlace

Simple marketplace for listing and accepting offers. Supports a secure TBA flow:

- `advanceList` requires a locked, reset TBA with the marketplace as receiver.
- `advanceAcceptOffer` unlocks the TBA before transferring the NFT.

### TokenCallbackHandler

ERC-721 and ERC-1155 receiver implementation for safely receiving tokens.

## Tests (test)

`TBA.t.sol` validates security flows and attack scenarios:

- `test_createOwnershipCycle` — creates a cycle of TBAs owning each other.
- `test_breakOwnershipCycle` — uses guardians to recover and break the cycle.
- `test_approveThroughExecute` — ensures disallowed approval calls revert.
- `test_approvalForAll` — tracks approvals and operators correctly.
- `test_frontrunAttack` — models asset withdrawal before settlement.
- `test_backrunAttack` — models token drain via prior approvals.
- `test_lockAndReset` — enforces lock and reset before safe listing.

## Architecture Notes

- **Approval Safety**: `execute` blocks direct approvals to reduce token-drain risk.
- **Reset Mechanism**: `reset` clears approvals and operators prior to listing.
- **Locking**: `lock` prevents execution while a listing is active; `unlock` can be time-based or receiver-based.
- **Recovery**: Guardians can recover ownership if a cycle forms.

## Prerequisites

- Foundry (Forge, Cast, Anvil, Chisel)
- An Ethereum RPC endpoint for mainnet fork testing

## Setup

1. Install Foundry: https://book.getfoundry.sh/
2. Set an RPC endpoint for tests:

```bash
export RPC_URL="https://your-rpc-endpoint"
```

## Security Considerations

- `execute` only supports `call` operations; delegatecall is not allowed.
- Approval blocking is enforced at the calldata selector level.
- Listing requires a locked TBA with cleared approvals to prevent extraction.
- Guardians should be well-distributed and secured by separate keys.

## Repository Layout

- src/ — core contracts
- test/ — Foundry tests
- script/ — example deployment scripts
- lib/ — dependencies (openzeppelin, forge-std, reference)

