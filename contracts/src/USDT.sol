// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title USDT — mock test stablecoin for Inkstake Arena
/// @notice TESTNET ONLY. This token has no value and is NOT affiliated with Tether or any real
///         stablecoin issuer. It exists so players can stake something other than native tCTC
///         during the hackathon. The name and symbol were chosen by the project owner.
/// @dev UUPS-upgradeable, ERC-7201 namespaced storage, 6 decimals by stablecoin convention.
contract USDT is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    error NotMinter();
    error FaucetCooldown();

    event MinterSet(address indexed account, bool allowed);

    uint256 public constant FAUCET_AMOUNT = 1_000e6;
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    /// @custom:storage-location erc7201:inkstake.storage.USDT
    struct USDTStorage {
        mapping(address account => bool allowed) minters;
        mapping(address account => uint256 at) lastFaucet;
    }

    bytes32 private constant STORAGE_SLOT =
        0x181e7851ce70236646a4bdccacb641dd7f5cd904ed2d297634c5f3875df74200;

    function _s() private pure returns (USDTStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __ERC20_init("USDT", "USDT");
        __Ownable_init(initialOwner);
        // OZ 5.7's UUPSUpgradeable is stateless and has no initializer.
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function isMinter(address account) public view returns (bool) {
        return _s().minters[account];
    }

    function lastFaucet(address account) public view returns (uint256) {
        return _s().lastFaucet[account];
    }

    function setMinter(address account, bool allowed) external onlyOwner {
        _s().minters[account] = allowed;
        emit MinterSet(account, allowed);
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != owner() && !_s().minters[msg.sender]) revert NotMinter();
        _mint(to, amount);
    }

    /// @notice Self-service tokens for testers, rate limited per address.
    function faucet() external {
        USDTStorage storage $ = _s();
        uint256 last = $.lastFaucet[msg.sender];
        if (last != 0 && block.timestamp < last + FAUCET_COOLDOWN) revert FaucetCooldown();
        $.lastFaucet[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
