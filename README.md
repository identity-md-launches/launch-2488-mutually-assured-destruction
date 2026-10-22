# Mutually Assured Destruction (MAD)

A fixed-supply ERC-20 for Ethereum. The only production contract is
[`MADToken`](src/MADToken.sol), built on the vendored OpenZeppelin Contracts
v5.4.0 ERC-20 implementation.

## Token behavior and assumptions

| Property | Value |
| --- | --- |
| Solidity contract identifier | `MADToken` |
| Token name | `Mutually Assured Destruction` |
| Symbol | `MAD` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Initial recipient | The constructor's `msg.sender` |
| Constructor arguments | None (`[]`) |
| Owner / administrator | None |

The constructor performs exactly one mint of the entire supply to the immediate
deployer. The token has no callable mint, burn, pause, blacklist, seizure,
ownership, initialization, or upgrade functions. Supply remains constant.

The brief specifies a name, symbol, supply, decimals, and initial recipient.
The name is treated as branding: no destruction game, transfer tax, automatic
burn, vesting, or other transfer rule is inferred from it. Transfers deliver
exactly the requested amount, including transfers involving contracts.

Standard ERC-20 behavior applies:

- Successful `transfer`, `approve`, and `transferFrom` calls return `true`.
  Invalid calls revert with OpenZeppelin's ERC-6093 custom errors.
- Transfers to the zero address and approvals to the zero spender revert.
  Zero-value transfers between valid addresses succeed and emit `Transfer`.
- Self-transfers preserve the balance. A delegated self-transfer still consumes
  finite allowance. Even the holder needs allowance when using `transferFrom`.
- `approve` replaces the caller's allowance for that spender; approving zero
  revokes it. Finite allowances decrease when spent. The maximum `uint256`
  represents unlimited allowance and does not decrease.
- Explicit approvals emit `Approval`. As in OpenZeppelin v5, spending an
  allowance with `transferFrom` does not emit an additional `Approval`; consumers
  can query `allowance` for the current value.
- Transfers make no recipient callback. There is no payable entrypoint or
  asset-recovery function.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xb9e6f3d6091f8bfda31746690a4dce32b4e3a353c3fe124cc2d1b8d5bd32c3a4 forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, the Cancun EVM target, optimizer runs of
`200`, and `bytecode_hash = "none"`. It enables neither FFI nor filesystem
permissions. All required Solidity dependencies are ordinary files under `lib/`;
there are no submodules or dependency installation steps. With the pinned
compiler installed, builds and tests work without a network. Tests require no
RPC, keys, environment lookups, or fork state. The seed above only configures
Foundry's test runner; the Solidity tests do not access environment variables.

Dependency provenance and archive checksums are recorded in
[`lib/openzeppelin-contracts/VENDORED.md`](lib/openzeppelin-contracts/VENDORED.md)
and [`lib/forge-std/VENDORED.md`](lib/forge-std/VENDORED.md). The former contains
only the ERC-20 source dependency closure and its MIT license; the latter vendors
forge-std v1.9.7 source and its MIT/Apache licenses. Upstream files are unmodified.

## Deployment parameters

Deploy the creation bytecode for `src/MADToken.sol:MADToken` directly, with no
constructor arguments, initializer, library linking, or attached ETH. The build
artifact is `out/MADToken.sol/MADToken.json`. The constructor does not call any
external contract or require any previously deployed code.

For the requested Ethereum launch (chain ID `1`), the launch factory is the
immediate deployer and receives all `10^27` units. A direct EOA deployment instead
gives the supply to that EOA; a wrapper deployment gives it to the wrapper. This
distinction is tested with CREATE2. Do not deploy through a generic wrapper that
cannot forward its tokens.

The launch factory handles the supplied 10% swarm allocation, 80% liquidity
allocation, and 10% remainder allocation after construction. Those allocations
are not made by the token. The token needs no factory, distributor, pool manager,
recipient, or paired-token address in its configuration, because every transfer
uses the same exact-amount behavior. No application contracts or launch manifest
are included; the launch system supplies the manifest and performs deployment.

## After launch and operational responsibilities

There are no token settings to initialize and no administrator or ongoing keeper
role. The launch operator is responsible for deploying the reviewed bytecode,
verifying the metadata and total supply, performing the external distribution
and pool setup, and publishing the verified source and deployed address.

Holders manage their own balances and approvals. Approve only trusted spenders
for the required amount. To change an existing nonzero allowance safely, first
revoke it and confirm that transaction before setting the replacement; the
standard ERC-20 allowance replacement race is not changed by this token.

No operator can undo a transfer, recover lost keys, reclaim tokens sent to the
token contract, or upgrade the token. Recipients must be able to manage any
tokens sent to them. The token does not validate recipients' capabilities.

## Validation and security review

The local suite has 29 tests: 22 example-based tests, six fuzz tests with 1,024
cases each, and one stateful invariant with 256 sequences of 64 calls. Coverage
includes metadata and one-time mint events, factory deployment, exact delivery,
zero and full-balance transfers, approvals and revocation, self-transfers,
infinite allowance, insufficient balances and allowances, transaction rollback,
invalid addresses, absence of privileged entrypoints, and conservation of the
entire supply across interleaved transfers and approvals.

The launch-flow test checks the token transfer legs for distribution, claims,
and trading using local actors. It does not simulate a Uniswap pool or substitute
for the launch system's separate integration checks.

Review against the supplied security reference found no external-call,
reentrancy, oracle, randomness, signature, proxy, or administrative-control
surface in this implementation. Holder authorization uses the standard ERC-20
allowance mechanism. Minting is reachable only in construction; token transfer
and approval arithmetic comes from the unmodified OpenZeppelin implementation.

`forge build`, `forge test` with the supplied seed, and `forge fmt --check` are
the local validation commands. Slither and Mythril were not run. These checks
and the implementation review are not an independent security audit; independent
adversarial review remains a release responsibility.
