# YOLO test coverage

The suite tests the deployed `YOLO` implementation and its vendored ERC-20
dependency without changing either. Existing issuance, event, authorization,
transfer, and factory tests remain in place.

| File | Coverage |
| --- | --- |
| `YOLO.t.sol` | Exact name, symbol, decimals and constructor issuance; mint and transfer events; ordinary/delegated transfers; invalid inputs; unavailable administrative entry points |
| `YOLOLaunch.t.sol` | Immediate CREATE2 deployer receives the supply; exact onward token transfers through launch roles |
| `YOLOProperties.t.sol` | Allowance lifecycle regressions; authorization isolation; repeated failure rollback; zero/one/full-supply/maximum boundaries; transfer round trips and split-transfer equivalence |
| `YOLOInvariant.t.sol` | Four actors, eleven randomly ordered handler actions, independent balance/allowance accounting, three global invariants, and a deterministic handler lifecycle regression |

The invariant discovery review used the five perspectives in the supplied
Pashov fizz reference and the supplied Trail of Bits property-testing guidance.
These are the applicable properties and their implementation basis:

| Perspective | Property | Source basis |
| --- | --- | --- |
| Conservation | Supply remains `10^27`; the tracked balances sum to exactly that supply | `src/YOLO.sol:12-15`; `ERC20.sol:183-210` |
| State transitions | Approval replaces an allowance; finite spending decreases only the owner's allowance for the caller; failed operations leave accounting unchanged | `ERC20.sol:127-130`, `149-153`, `280-310` |
| Round trips | A transfer and its reverse restore balances; splitting a delegated transfer has the same final balances and allowance as one transfer | `ERC20.sol:104-107`, `149-153`, `183-210` |
| Adversarial sequences | Revoked or insufficient approval cannot authorize spending; approvals do not create balances; full-balance transfers remain possible | `ERC20.sol:166-173`, `188-195`, `301-310` |
| Token semantics | Self-transfers conserve balances; zero transfers emit events; zero recipients/spenders are rejected; metadata stays fixed | `src/YOLO.sol:14-15`; `ERC20.sol:48-81`, `166-173`, `183-210`, `280-290` |

`ERC20.sol` above is
`lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol`. These properties
follow from the requested fixed issuance and the implementation's ERC-20
behavior. No vault, pricing, share-conversion, or interest properties apply.

The handler updates its ghost balances and allowances only after successful
calls. Rejected calls must revert with the exact custom error and arguments;
their ghost state is left unchanged. Every actor's balance and every pair's
allowance are compared to the model after each action. Round trips also assert
the intermediate balances, so an implementation that silently does nothing
cannot pass solely by returning to its starting state.

Inputs use bounds and explicit boundary choices. The approval boundary action
selects zero, maximum uint256, maximum minus one, or the current balance. The
full-balance action reaches empty-account states. The deterministic lifecycle
pins positive delegated spending, infinite approval revocation, finite approval
consumption, rejected spending, and refunding an empty account independently of
random scheduling. Unexpected handler reverts fail the campaign.

The new fuzz properties run 1,024 cases each. Inline configuration runs the
invariants for 256 sequences of 128 handler calls. The existing configuration
also runs the original fuzz properties for 1,024 cases. No test requires a
network, fork, signer, FFI, or additional dependency.

To keep build artifacts within the disposable scratch directory:

```sh
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache forge build --offline
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache FOUNDRY_FUZZ_SEED=0x8af298ea9629d3b14bc1204e76fcf291db71cacd9c1a006feff7b4915817c993 forge test --offline
```

Ordinary `forge build` and `forge test` also use these tests. Nothing delivered
imports a file from `test/scratch/`.

The local launch fixture checks token transfers, not a live AMM. The supplied
protected launch tests require the separate network launch harness and its
resolved deployment parameters. They are not copied into this suite. No
implementation defect was found during this review and the local runs.
