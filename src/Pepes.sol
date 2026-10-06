// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Pepes
/// @notice Fixed-supply ERC-20: one billion PEPES, with 18 decimals.
/// @dev The constructor caller receives the entire supply. There are no administrative powers,
/// transfer fees, public mint/burn functions, or upgrade mechanisms.
contract Pepes is ERC20 {
    /// @notice The entire supply, expressed in the smallest token units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Pepes", "PEPES") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
