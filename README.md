# Pepes (PEPES)

Pepes is a fixed-supply ERC-20. Its constructor mints the entire supply once to
`msg.sender`, the address that creates the contract.

| Deployment parameter | Value |
| --- | --- |
| Contract | `src/Pepes.sol:Pepes` |
| Name | `Pepes` |
| Symbol | `PEPES` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; ABI encoding `0x`) |
| Native currency sent at creation | `0` |
| Initial recipient | Constructor caller |
| Solidity | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | None |

## Build and check

Install Foundry and Solidity 0.8.26 in the toolchain, then run:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies are ordinary files in `lib/`; there are no submodules
or package installation steps. With the pinned compiler available, build and
tests require no network. FFI and filesystem cheatcode permissions are disabled.
Tests use local deployments without RPC endpoints, wallets, environment variables,
or shared state between tests.

The default suite includes unit tests, four fuzz tests with 512 cases each, and
two stateful invariants with 128 runs of 64 calls each. Coverage includes metadata,
the sole constructor mint and its event, CREATE2 deployment by a factory,
exact transfers and a simulated distribution flow, approvals, revocation,
finite and unlimited allowances, zero and self transfers, invalid addresses,
insufficient balances and allowances, atomic reverts, and attempts to mint,
burn, freeze or upgrade. A four-holder accounting model checks supply,
balances and allowances across randomized operation sequences.

## Behavior and assumptions

- This is a standard ERC-20 with no transfer tax, burn, rebasing, permit,
  account restrictions, owner, pause function, upgrade path or further minting.
  There is no initialization step.
- `transfer`, `approve` and `transferFrom` return `true` on success and revert
  with OpenZeppelin ERC-20 custom errors on failure. Minting and transfers emit
  `Transfer`; explicit approvals emit `Approval`.
- Zero-value transfers between nonzero addresses are valid and emit events.
  Self transfers preserve balances. The zero address cannot send or receive
  transfers or be an approval's owner or spender.
- Approvals replace the existing allowance. Finite allowances decrease when
  spent; `type(uint256).max` means unlimited approval and is not reduced.
  `transferFrom` does not emit an `Approval` event when it spends allowance.
- Transfer amounts arrive exactly, including transfers by a factory,
  distributor or pool manager. No exemptions or chain-specific addresses are
  needed. Transfers make no external calls or receiver callbacks.
- The token can be sent to any nonzero address, including contracts that cannot
  return it. There is no rescue function. The contract does not accept ordinary
  ETH payments and provides no ETH withdrawal function.

## Deployment and operation

Deploy `Pepes` directly, or pass its creation bytecode unchanged to the approved
launch factory. No constructor arguments are appended. This read-only command
prints the compiled creation bytecode:

```sh
forge inspect src/Pepes.sol:Pepes bytecode
```

For direct creation, the creating account receives all tokens. If a factory or
another contract creates Pepes, that contract receives all tokens; the outer
transaction sender receives none automatically. The factory must be able to
transfer its balance onward. Tests exercise this explicitly with CREATE2.

The deployment operator must choose the intended chain and creating account or
factory, confirm compatibility with the Cancun EVM target, verify source and
compiler settings, and check the deployed metadata, supply, mint event and
initial recipient before distributing funds. The network's launch process owns
the manifest, distributor, liquidity pool and allocation parameters; this token
requires only the metadata and supply above. The example allocation in the unit
test is illustrative, not a deployment configuration. No chain addresses, pool
economics or requester wallet were supplied in this assignment.

Holders control transfers and allowances. Protect the initial supply's custody,
approve only trusted spenders for necessary amounts, and revoke unused approvals.
When changing an existing nonzero allowance, consider revoking it to zero first
and waiting for confirmation: a spender can spend an existing approval before
its replacement confirms. There are no privileged operators or ongoing upkeep
transactions, and lost funds or compromised approvals cannot be reversed by an
administrator.

This project supplies the token, not a live launch. No deployment or broadcast is
performed. The local factory/distributor/pool transfer simulation does not run
Uniswap or the separate network acceptance harness; that harness needs network
launch artifacts and configuration that are not included here. A production
release still needs the network's independent adversarial review and launch
integration checks. Local tests are not a security audit; Slither and Mythril
were not run.

## Vendored source

`dependencies.json` records immutable source commits and downloaded archive
hashes. `lib/openzeppelin-contracts` contains the unchanged ERC-20 dependency
closure from OpenZeppelin Contracts v5.4.0 and its MIT license.
`lib/forge-std` contains the Solidity test library from forge-std v1.9.7 and its
MIT/Apache licenses. These files must remain with the project for offline builds.
They can be reviewed independently of the small Pepes constructor.
