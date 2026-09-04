// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// Lane Protocol is the operational lane of the ecosystem: the LANE token is a utility token designed to connect to services and facilitate exchange within the protocol, it does not constitute a security or an investment asset, but rather a functional medium that enables interaction and the use of services among its users.
contract LANE is OFT {
    uint8 public constant DECIMALS = 18;

    uint256 public constant TOTAL_SUPPLY = 21_000_000 * 1e18;
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant FEE_BPS = 100;

    address public immutable DEPLOYER;
    address public immutable DEV_WALLET;

    mapping(address => bool) public isFeeExemptSender;

    address public farmingVault;
    bool public farmingVaultLocked;

    address public collateralCore;
    bool public collateralCoreLocked;

    event FarmingVaultSet(address indexed vault);
    event CollateralCoreSet(address indexed core);

    error ONLY_DEPLOYER();
    error DEPLOYER_0();
    error DEV_0();
    error ENDPOINT_0();
    error VAULT_LOCKED();
    error VAULT_0();
    error CORE_LOCKED();
    error CORE_0();

    modifier onlyDeployer() {
        if (msg.sender != DEPLOYER) revert ONLY_DEPLOYER();
        _;
    }

    constructor(address _deployer, address _devWallet, address _lzEndpoint)
        OFT("Lane Protocol", "LANE", _lzEndpoint, _deployer)
        Ownable(_deployer)
    {
        if (_deployer == address(0)) revert DEPLOYER_0();
        if (_devWallet == address(0)) revert DEV_0();
        if (_lzEndpoint == address(0)) revert ENDPOINT_0();
        DEPLOYER = _deployer;
        DEV_WALLET = _devWallet;

        isFeeExemptSender[_deployer] = true;
        isFeeExemptSender[_devWallet] = true;

        if (block.chainid == 56) {
            _mint(_deployer, TOTAL_SUPPLY);
        }
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
    function setFarmingVaultOnce(address vault) external onlyDeployer {
        if (farmingVaultLocked) revert VAULT_LOCKED();
        if (vault == address(0)) revert VAULT_0();

        farmingVault = vault;
        farmingVaultLocked = true;

        isFeeExemptSender[vault] = true;

        emit FarmingVaultSet(vault);
    }

    function setCollateralCoreOnce(address core) external onlyDeployer {
        if (collateralCoreLocked) revert CORE_LOCKED();
        if (core == address(0)) revert CORE_0();

        collateralCore = core;
        collateralCoreLocked = true;

        emit CollateralCoreSet(core);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        if (amount == 0) {
            super._update(from, to, 0);
            return;
        }

        if (from == address(this) || to == address(this)) {
            super._update(from, to, amount);
            return;
        }

        if (FEE_BPS == 0) {
            super._update(from, to, amount);
            return;
        }

        if (from == farmingVault || to == farmingVault || isFeeExemptSender[from]) {
            super._update(from, to, amount);
            return;
        }

        uint256 fee = (amount * FEE_BPS) / FEE_DENOMINATOR;
        if (fee == 0) {
            super._update(from, to, amount);
            return;
        }

        uint256 net = amount - fee;

        super._update(from, DEV_WALLET, fee);
        super._update(from, to, net);
    }
}
