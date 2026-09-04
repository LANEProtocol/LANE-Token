// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ILANETokenView {
    function farmingVault() external view returns (address);
    function isFeeExemptSender(address a) external view returns (bool);
}

library SafeERC20Minimal {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.transfer.selector, to, value));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "SAFE_TRANSFER_FAILED");
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "SAFE_TRANSFER_FROM_FAILED");
    }
}

contract FarmingVault_LANE_Eras {
    using SafeERC20Minimal for IERC20;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant YEAR      = 365 days;
    uint256 private constant BPS       = 10_000;

    uint256 public constant REWARD_TOTAL_CAP = 13_500_000 * 1e18;

    IERC20 public immutable LANE;
    ILANETokenView private immutable LANEVIEW;

    struct Era {
        uint256 rewardCap;
        uint256 rewardRemaining;
        uint256 aprBps;
    }

    Era[] public eras;
    uint256 public currentEra;
    uint256 public totalRewardsPaid;

    uint256 public totalStaked;
    uint256 public rewardPerTokenStored;
    uint64  public lastUpdateTime;

    struct UserInfo {
        uint256 balance;
        uint256 rewards;
        uint256 userRewardPerTokenPaid;
    }

    mapping(address => UserInfo) public users;

    bool public rewardsReady;

    bool private _entered;
    modifier nonReentrant() {
        require(!_entered, "REENTRANCY");
        _entered = true;
        _;
        _entered = false;
    }

    event RewardsReady(uint256 vaultBalance);
    event Staked(address indexed user, uint256 sentAmount, uint256 receivedAmount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event EraAdvanced(uint256 indexed fromEra, uint256 indexed toEra);
    event EraConsumed(uint256 indexed era, uint256 consumed, uint256 remaining);

    constructor(address _laneToken) {
        require(_laneToken != address(0), "BAD_TOKEN");

        LANE = IERC20(_laneToken);
        LANEVIEW = ILANETokenView(_laneToken);

        uint256[5] memory caps;
        uint256[5] memory aprs;

        caps[0] = 4_725_000 * 1e18;
        caps[1] = 3_375_000 * 1e18;
        caps[2] = 2_430_000 * 1e18;
        caps[3] = 1_620_000 * 1e18;
        caps[4] = 1_350_000 * 1e18;

        aprs[0] = 6000;
        aprs[1] = 4500;
        aprs[2] = 3000;
        aprs[3] = 1800;
        aprs[4] = 1000;

        uint256 sumCaps = 0;
        uint256 prevApr = type(uint256).max;

        for (uint256 i = 0; i < caps.length; i++) {
            require(caps[i] > 0, "ZERO_CAP");
            require(aprs[i] > 0, "ZERO_APR");
            require(aprs[i] <= prevApr, "APR_NOT_DECREASING");
            prevApr = aprs[i];

            eras.push(Era({ rewardCap: caps[i], rewardRemaining: caps[i], aprBps: aprs[i] }));
            sumCaps += caps[i];
        }

        require(sumCaps == REWARD_TOTAL_CAP, "CAP_SUM_MISMATCH");

        lastUpdateTime = uint64(block.timestamp);
        currentEra = 0;
    }

    function availableRewards() public view returns (uint256) {
        uint256 bal = LANE.balanceOf(address(this));
        if (bal <= totalStaked) return 0;
        return bal - totalStaked;
    }

    function configOK() external view returns (bool okVaultSet, bool okFeeExemptSender) {
        okVaultSet = (LANEVIEW.farmingVault() == address(this));
        okFeeExemptSender = LANEVIEW.isFeeExemptSender(address(this));
    }

    function _requireConfig() internal view {
        require(LANEVIEW.farmingVault() == address(this), "VAULT_NOT_SET_IN_TOKEN");
        require(LANEVIEW.isFeeExemptSender(address(this)), "VAULT_NOT_FEE_EXEMPT");
    }

    modifier updateReward(address account) {
        _updateGlobal();
        if (account != address(0)) {
            UserInfo storage u = users[account];
            u.rewards = _earned(account);
            u.userRewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    function stake(uint256 amount)
        external
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "ZERO_AMOUNT");

        _requireConfig();

        if (!rewardsReady) {
            require(LANE.balanceOf(address(this)) >= REWARD_TOTAL_CAP, "REWARDS_NOT_SEEDED");
            rewardsReady = true;
            emit RewardsReady(LANE.balanceOf(address(this)));
        }

        uint256 balBefore = LANE.balanceOf(address(this));
        LANE.safeTransferFrom(msg.sender, address(this), amount);
        uint256 balAfter = LANE.balanceOf(address(this));

        require(balAfter >= balBefore, "BAD_BALANCE");
        uint256 received = balAfter - balBefore;
        require(received > 0, "RECEIVED_ZERO");

        users[msg.sender].balance += received;
        totalStaked += received;

        emit Staked(msg.sender, amount, received);
    }

    function withdraw(uint256 amount)
        external
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "ZERO_AMOUNT");
        UserInfo storage u = users[msg.sender];
        require(u.balance >= amount, "INSUFFICIENT_STAKE");

        u.balance -= amount;
        totalStaked -= amount;

        LANE.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claim()
        external
        nonReentrant
        updateReward(msg.sender)
    {
        UserInfo storage u = users[msg.sender];
        uint256 reward = u.rewards;
        require(reward > 0, "NO_REWARD");
        require(availableRewards() >= reward, "INSOLVENT_REWARD_POOL");

        u.rewards = 0;
        totalRewardsPaid += reward;

        LANE.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    function touch() external updateReward(address(0)) {}

    function eraCount() external view returns (uint256) { return eras.length; }

    function eraInfo(uint256 idx)
        external
        view
        returns (uint256 cap, uint256 remaining, uint256 apr)
    {
        Era storage e = eras[idx];
        return (e.rewardCap, e.rewardRemaining, e.aprBps);
    }

    function earned(address account) external view returns (uint256) {
        return _earnedView(account);
    }

    function _earned(address account) internal view returns (uint256) {
        UserInfo storage u = users[account];
        return (u.balance * (rewardPerTokenStored - u.userRewardPerTokenPaid)) / PRECISION + u.rewards;
    }

    function _earnedView(address account) internal view returns (uint256) {
        uint256 rpt = rewardPerTokenStored;
        uint64  lut = lastUpdateTime;

        if (block.timestamp > lut && totalStaked > 0 && currentEra < eras.length) {
            uint256 dtRemaining = block.timestamp - uint256(lut);
            uint256 eraIdx = currentEra;

            while (dtRemaining > 0 && eraIdx < eras.length) {
                Era storage e = eras[eraIdx];
                if (e.rewardRemaining == 0) { eraIdx++; continue; }

                uint256 rewardWanted = (totalStaked * e.aprBps * dtRemaining) / (BPS * YEAR);
                if (rewardWanted == 0) break;

                uint256 rewardUsed = rewardWanted;
                if (rewardUsed > e.rewardRemaining) rewardUsed = e.rewardRemaining;

                uint256 avail = availableRewards();
                if (rewardUsed > avail) rewardUsed = avail;

                if (rewardUsed == 0) break;

                rpt += (rewardUsed * PRECISION) / totalStaked;

                uint256 denom = totalStaked * e.aprBps;
                uint256 dtUsed = (rewardUsed * (BPS * YEAR)) / denom;
                if (dtUsed == 0) dtUsed = 1;

                if (rewardUsed == e.rewardRemaining) eraIdx++;

                if (dtUsed >= dtRemaining) dtRemaining = 0;
                else dtRemaining -= dtUsed;
            }
        }

        UserInfo storage u = users[account];
        return (u.balance * (rpt - u.userRewardPerTokenPaid)) / PRECISION + u.rewards;
    }

    function _updateGlobal() internal {
        uint64 nowTs = uint64(block.timestamp);
        if (nowTs <= lastUpdateTime) return;

        if (totalStaked == 0 || currentEra >= eras.length) {
            lastUpdateTime = nowTs;
            return;
        }

        uint256 dtRemaining = uint256(nowTs - lastUpdateTime);
        uint256 eraIdx = currentEra;

        while (dtRemaining > 0 && eraIdx < eras.length) {
            Era storage e = eras[eraIdx];
            if (e.rewardRemaining == 0) { eraIdx++; continue; }

            uint256 rewardWanted = (totalStaked * e.aprBps * dtRemaining) / (BPS * YEAR);
            if (rewardWanted == 0) break;

            uint256 rewardUsed = rewardWanted;
            if (rewardUsed > e.rewardRemaining) rewardUsed = e.rewardRemaining;

            uint256 avail = availableRewards();
            if (rewardUsed > avail) rewardUsed = avail;

            if (rewardUsed == 0) break;

            e.rewardRemaining -= rewardUsed;

            rewardPerTokenStored += (rewardUsed * PRECISION) / totalStaked;
            emit EraConsumed(eraIdx, rewardUsed, e.rewardRemaining);

            uint256 denom = totalStaked * e.aprBps;
            uint256 dtUsed = (rewardUsed * (BPS * YEAR)) / denom;
            if (dtUsed == 0) dtUsed = 1;

            if (dtUsed >= dtRemaining) dtRemaining = 0;
            else dtRemaining -= dtUsed;

            if (e.rewardRemaining == 0) {
                uint256 fromEra = eraIdx;
                eraIdx++;
                emit EraAdvanced(fromEra, eraIdx);
            } else {
                dtRemaining = 0;
            }
        }

        currentEra = eraIdx;
        lastUpdateTime = nowTs;
    }
}
