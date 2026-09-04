// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ILANE {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ILANEX {
    function mintForProtocolCore(uint256 amount) external returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IOracleAdapter {
    function price() external view returns (uint256);
}

contract LANEXMonetaryCore {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_status != _ENTERED, "REENTRANCY");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    error BSC_ONLY();
    function _isBscLike() internal view returns (bool) {
        return block.chainid == 56;
    }

    address public immutable DEPLOYER;
    bool public configLocked;

    error ONLY_DEPLOYER();
    error LOCKED();
    error BAD_ADDR();
    error NO_CONFIG();

    modifier onlyDeployer() {
        if (msg.sender != DEPLOYER) revert ONLY_DEPLOYER();
        _;
    }

    modifier notLocked() {
        if (configLocked) revert LOCKED();
        _;
    }

    ILANE public LANE;
    ILANEX public LANEX;

    address public oracleAdapter;

    event ConfigSet(address lane, address lanex, address oracleAdapter);
    event ConfigLocked();

    uint256 public constant MAX_STALE_TIME = 2 hours;
    uint256 public constant MAX_DEVIATION_BPS = 300;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public constant COLLATERAL_CAP_LANE = 5_000_000 * 1e18;

    uint256 public totalCollateral;

    struct Position {
        uint256 collateral;
        uint256 minted;
    }

    mapping(address => Position) public positions;

    event Deposited(address indexed user, uint256 mmuAmount, uint256 minted);
    event Refreshed(address indexed user, uint256 mintedDelta);

    constructor(address _deployer) {
        if (!_isBscLike()) revert BSC_ONLY();
        if (_deployer == address(0)) revert BAD_ADDR();
        DEPLOYER = _deployer;
    }

    function setConfig(
        address _lane,
        address _lanex,
        address _oracleAdapter
    ) external onlyDeployer notLocked {
        if (_lane == address(0) || _lanex == address(0) || _oracleAdapter == address(0)) revert BAD_ADDR();

        LANE = ILANE(_lane);
        LANEX = ILANEX(_lanex);
        oracleAdapter = _oracleAdapter;

        emit ConfigSet(_lane, _lanex, _oracleAdapter);
    }

    function lockConfig() external onlyDeployer notLocked {
        configLocked = true;
        emit ConfigLocked();
    }

    function _requireConfigured() internal view {
        if (address(LANE) == address(0) || address(LANEX) == address(0) || oracleAdapter == address(0)) revert NO_CONFIG();
    }

    function _price() internal view returns (uint256) {
        return IOracleAdapter(oracleAdapter).price();
    }

    function _maxMint(Position storage p, uint256 price_) internal view returns (uint256) {
        return (p.collateral * price_) / 1e18;
    }

    function _mintToCoreAndPay(address to, uint256 delta) internal {
        uint256 beforeBal = LANEX.balanceOf(address(this));

        uint256 minted = LANEX.mintForProtocolCore(delta);
        require(minted == delta && minted > 0, "MINT_FAIL");

        uint256 afterBal = LANEX.balanceOf(address(this));
        require(afterBal >= beforeBal + delta, "CORE_NOT_FUNDED");

        require(LANEX.transfer(to, delta), "LANEX_TRANSFER_FAIL");
    }

    function deposit(uint256 amountLANE) external nonReentrant {
        _requireConfigured();
        require(amountLANE > 0, "ZERO_AMOUNT");

        uint256 beforeBal = LANE.balanceOf(address(this));
        require(LANE.transferFrom(msg.sender, address(this), amountLANE), "LANE_TRANSFER_FAIL");
        uint256 afterBal = LANE.balanceOf(address(this));

        uint256 received = afterBal - beforeBal;
        require(received > 0, "NO_COLLATERAL_RECEIVED");
        require(totalCollateral + received <= COLLATERAL_CAP_LANE, "COLLATERAL_CAP_EXCEEDED");

        Position storage p = positions[msg.sender];
        p.collateral += received;
        totalCollateral += received;

        uint256 price_ = _price();
        uint256 allowed = _maxMint(p, price_);

        if (allowed <= p.minted) {
            emit Deposited(msg.sender, received, 0);
            return;
        }

        uint256 delta = allowed - p.minted;
        _mintToCoreAndPay(msg.sender, delta);
        p.minted += delta;

        emit Deposited(msg.sender, received, delta);
    }

    function refresh() external nonReentrant {
        _requireConfigured();

        Position storage p = positions[msg.sender];
        require(p.collateral > 0, "NO_COLLATERAL");

        uint256 price_ = _price();
        uint256 allowed = _maxMint(p, price_);

        if (allowed <= p.minted) {
            emit Refreshed(msg.sender, 0);
            return;
        }

        uint256 delta = allowed - p.minted;
        _mintToCoreAndPay(msg.sender, delta);
        p.minted += delta;

        emit Refreshed(msg.sender, delta);
    }
}
