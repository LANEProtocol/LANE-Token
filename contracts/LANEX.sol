// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract LANEX is OFT {
    uint8 public constant DECIMALS = 18;

    address public immutable DEPLOYER;

    address public protocolCore;
    bool public protocolCoreLocked;

    event ProtocolCoreSet(address indexed core);
    event ProtocolCoreLocked(address indexed core);

    error ONLY_DEPLOYER();
    error ONLY_PROTOCOL_CORE();
    error DEPLOYER_0();
    error ENDPOINT_0();
    error CORE_LOCKED();
    error CORE_0();
    error CORE_ONLY_ON_BSC();

    modifier onlyDeployer() {
        if (msg.sender != DEPLOYER) revert ONLY_DEPLOYER();
        _;
    }

    modifier onlyProtocolCore() {
        if (msg.sender != protocolCore) revert ONLY_PROTOCOL_CORE();
        _;
    }

    constructor(address _deployer, address _lzEndpoint)
        OFT("lanex Stable", "LANEX", _lzEndpoint, _deployer)
        Ownable(_deployer)
    {
        if (_deployer == address(0)) revert DEPLOYER_0();
        if (_lzEndpoint == address(0)) revert ENDPOINT_0();

        DEPLOYER = _deployer;

        // MAINNET MODE:
        // ProtocolCore can only be configured on BSC mainnet (56).
        if (block.chainid != 56) {
            protocolCoreLocked = true;
            emit ProtocolCoreLocked(address(0));
        }
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    function setProtocolCoreOnce(address core) external onlyDeployer {
        if (block.chainid != 56) revert CORE_ONLY_ON_BSC();
        if (protocolCoreLocked) revert CORE_LOCKED();
        if (core == address(0)) revert CORE_0();

        protocolCore = core;
        emit ProtocolCoreSet(core);
    }

    function lockProtocolCore() external onlyDeployer {
        if (block.chainid != 56) revert CORE_ONLY_ON_BSC();
        protocolCoreLocked = true;
        emit ProtocolCoreLocked(protocolCore);
    }

    function mintForProtocolCore(uint256 amount)
        external
        onlyProtocolCore
        returns (uint256)
    {
        _mint(protocolCore, amount);
        return amount;
    }
}
