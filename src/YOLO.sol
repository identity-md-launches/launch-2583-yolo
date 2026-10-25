// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title YOLO
/// @notice Fixed-supply ERC-20: one billion YOLO, with 18 decimals.
/// @dev The immediate deployer receives the entire supply, including when deployed by a factory.
///      No mint, burn, administrative, or upgrade functions are exposed after construction.
contract YOLO is ERC20 {
    /// @notice Total issuance in the token's smallest units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("YOLO", "YOLO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
