# Vendored dependencies

All files below are ordinary repository files and are sufficient for offline
compilation and tests when Solidity 0.8.26 and Foundry are available. No dependency
fetching, package manager, git submodule, or post-install script is needed.

## OpenZeppelin Contracts v5.1.0

- Source: <https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0>
- Archive: <https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0>
- Archive SHA-256: `8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686`
- Location: `lib/openzeppelin-contracts/`
- License: MIT, preserved in `lib/openzeppelin-contracts/LICENSE`.
- Scope: unmodified `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`,
  and `draft-IERC6093.sol`, the complete dependency closure of this token.

## forge-std v1.9.7

- Source: <https://github.com/foundry-rs/forge-std/tree/v1.9.7>
- Archive: <https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7>
- Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`
- Location: `lib/forge-std/`
- Licenses: MIT and Apache-2.0, preserved as `LICENSE-MIT` and `LICENSE-APACHE`.
- Scope: unmodified upstream `src/` plus both license files; used by tests only.

`DEPENDENCIES.sha256` records SHA-256 hashes of every vendored file, including
licenses. Run `sha256sum --check DEPENDENCIES.sha256` to verify their integrity.
