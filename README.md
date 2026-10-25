# YOLO

YOLO is a fixed-supply ERC-20 token. Its constructor mints exactly
1,000,000,000 YOLO, with 18 decimals, to the immediate deployer.

| Deployment parameter | Value |
| --- | --- |
| Solidity contract | `src/YOLO.sol:YOLO` |
| Name / symbol | `YOLO` / `YOLO` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None; encoded arguments are empty (`0x`) |
| Deployment ETH value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Intended launch chain | Ethereum, chain ID `1` |
| Solidity / EVM target | `0.8.26` / Cancun |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |
| External library linking | None |

The only project contract to deploy is `YOLO`. Its creation bytecode and ABI
are built into `out/YOLO.sol/YOLO.json`. Deploy that creation bytecode directly
with no constructor arguments, either through CREATE or CREATE2. In the IMD
launch the factory is the immediate deployer and receives the entire supply;
the wallet that requests the launch receives no tokens during construction.
The constructor makes no external calls and needs no existing on-chain contracts.

## Behavior and assumptions

`INITIAL_SUPPLY` is the named issuance constant, `1_000_000_000 * 10 ** 18`.
One mint `Transfer` event is emitted during construction. OpenZeppelin's
unmodified ERC-20 implementation provides transfers, balances, approvals,
allowances, and the metadata functions. Successful transfers and approvals
return `true`; invalid operations revert with ERC-6093 custom errors.

- Transfers arrive in full. There are no token fees, taxes, rebases, or transfer restrictions.
- Zero-value transfers between nonzero addresses are supported and emit `Transfer`.
- Transfers to the zero address and approvals to a zero spender revert.
- Self-transfers preserve balances; delegated self-transfers still consume finite allowance.
- `approve` replaces the previous allowance. Finite allowances decrease on `transferFrom`;
  an allowance of `type(uint256).max` remains unchanged. OpenZeppelin v5 does not emit
  `Approval` when `transferFrom` consumes allowance; integrations should read `allowance`.
- Supply cannot grow or shrink after deployment. There are no external mint or burn functions,
  owner, pause, blacklist, seizure, initializer, upgrade mechanism, or proxy.
- Token operations make no external calls or receiver callbacks. Contract recipients must
  implement their own means of moving received tokens.

## Build and check

Foundry and Solidity 0.8.26 are required. Both Solidity dependencies are vendored
as ordinary source files under `lib/`; there are no submodules or installation steps.
With the pinned compiler available, build and tests need no network, RPC,
environment secrets, FFI, or filesystem cheatcode permissions.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x8af298ea9629d3b14bc1204e76fcf291db71cacd9c1a006feff7b4915817c993 forge test
forge fmt --check
sha256sum --check DEPENDENCIES.sha256
```

Tests cover constructor issuance and events, metadata, ordinary and delegated
transfers, approval replacement/revocation, infinite allowances, exact balances,
self/zero transfers, maximum integers, failure atomicity, unauthorized actions,
and ETH rejection. Fuzz tests run 1,024 cases each. Two stateful invariants run
256 sequences of up to 64 calls each, comparing balances and allowances to an
independent model while checking supply conservation.

The local launch fixture checks CREATE2 recipient semantics, the exact
10%/60%/30% transfer split described for this launch, onward claims, and token
movement into and out of pool custody. It does not instantiate an AMM or test
pricing, liquidity settlement, or actual swaps. The supplied protected launch
checks rely on the separate network launch harness, dependencies, and resolved
deployment parameters; those integration checks are performed by the verifier.

## After launch

There are no token settings or administrative duties to configure. The network
deployer is responsible for the separate launch manifest, factory execution,
distributor funding, pool initialization and seeding, and forwarding the remainder
under the supplied launch economics. None of those allocations are performed by
the token constructor. No application contracts or launch manifest are included.

The launch operator should confirm the deployed name, symbol, decimals, total
supply, bytecode, mint event, and resulting allocation balances, then verify the
source using the pinned build settings. Deployment and transactions are outside
this deliverable; no keys or signer configuration are required to build it.

Holders are responsible for recipient addresses and spender approvals. Prefer
exact approvals; when changing an active allowance, revoke it and wait for
confirmation before approving a replacement. Already authorized spending can
still occur before a revocation is mined. The deployer has no recovery power.
Tokens sent to this token contract or another contract without a withdrawal
function may be permanently stuck. Ordinary ETH transfers to YOLO revert;
forcibly credited ETH and unrelated tokens cannot be rescued.

## Security review scope

The implementation is deliberately limited to OpenZeppelin ERC-20 plus a
constructor mint. Review against the supplied security reference focuses on
integer units, issuance reachability, allowance authorization, input validation,
failure rollback, and the absence of external calls and administrative powers.
Oracles, randomness, signatures, vault accounting, and upgrade storage do not apply.

Local validation uses Foundry build, unit tests, fuzz tests, stateful invariants,
and formatting checks. Slither and Mythril are not run as part of this deliverable.
These checks are not an independent security audit; the network's independent
review and real launch integration checks remain separate release steps.

Dependency versions, provenance, and licenses are recorded in [DEPENDENCIES.md](DEPENDENCIES.md).
