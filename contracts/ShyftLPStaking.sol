//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract ShyftLPStaking is Ownable {
  using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;       // How many LP tokens the user has provided.
        uint256 rewardDebt;   // Reward debt.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;
        uint256 perBlockShyftAllocated;
        uint256 lastRewardBlock;
        uint256 accShyftPerShare;
    }

    IERC20 public shyftTokenContract;

    PoolInfo[] public poolInfo;
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event ContractFunded(address indexed from, uint256 amount);

    constructor(
        IERC20 _shyftContractAddress,
        uint256 _shyftPerBlock,
        uint256 _startBlock
    ) public {
        shyftTokenContract = _shyftContractAddress;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(uint256 _shyftPerBlock, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            perBlockShyftAllocated: _shyftPerBlock,
            lastRewardBlock: lastRewardBlock,
            accShyftPerShare: 0
            }));
    }

    function set(uint256 _poolId, uint256 _shyftPerBlock, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        poolInfo[_poolId].perBlockShyftAllocated = _shyftPerBlock;
    }

    function fund(uint256 _amount) public {
        address _from = address(msg.sender);
        require(_from != address(0), 'fund: must pass valid _from address');
        require(_amount > 0, 'fund: expecting a positive non zero _amount value');
        require(shyftTokenContract.balanceOf(_from) >= _amount, 'fund: expected an address that contains enough Shyft for Transfer');
        shyftTokenContract.transferFrom(_from, address(this), _amount);
        emit ContractFunded(_from, _amount);
    }

    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function pendingShyftReward(uint256 _poolId) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_poolId];
        UserInfo storage user = userInfo[_poolId][msg.sender];
        uint256 accShyftPerShare = pool.accShyftPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 shyftReward = multiplier.mul(pool.perBlockShyftAllocated);
            accShyftPerShare = accShyftPerShare.add(shyftReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accShyftPerShare).div(1e12).sub(user.rewardDebt);
    }

    function harvest(uint256 _poolId) external returns (uint256) {
        PoolInfo storage pool = poolInfo[_poolId];
        UserInfo storage user = userInfo[_poolId][msg.sender];
        updatePool(0);
        console.log('currentBlock', block.number, pool.accShyftPerShare);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accShyftPerShare).div(1e12).sub(user.rewardDebt);
            safeShyftTransfer(msg.sender, pending);
            return pending;
        }
        return 0;
    }

    function getLockedShyftView() external view returns (uint256) {
        return shyftTokenContract.balanceOf(address(this));
    }

    function getLpSupply(uint256 _poolId) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_poolId];
        return pool.lpToken.balanceOf(address(this));
    }

    //////////////////
    //
    // PUBLIC functions
    //
    //////////////////


    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update pool supply and reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _poolId) public {
        PoolInfo storage pool = poolInfo[_poolId];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 shyftReward = multiplier.mul(pool.perBlockShyftAllocated);
        pool.accShyftPerShare = pool.accShyftPerShare.add(shyftReward.mul(1e12).div(lpSupply));

        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Contract for RIO allocation.
    function deposit(uint256 _poolId, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_poolId];
        UserInfo storage user = userInfo[_poolId][msg.sender];
        updatePool(_poolId);
        // if user already has LP tokens in the pool execute harvest for the user
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accShyftPerShare).div(1e12).sub(user.rewardDebt);
            safeShyftTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accShyftPerShare).div(1e12);

        emit Deposit(msg.sender, _poolId, _amount);
    }

    // Withdraw LP tokens from Contract.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accShyftPerShare).div(1e12).sub(user.rewardDebt);

        safeShyftTransfer(address(msg.sender), pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accShyftPerShare).div(1e12);

        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
    }

    //////////////////
    //
    // INTERNAL functions
    //
    //////////////////

    // Safe RIO transfer function, just in case if rounding error causes pool to not have enough RIOs.
    function safeShyftTransfer(address _to, uint256 _amount) internal {
        address _from = address(this);
        uint256 shyftBal = shyftTokenContract.balanceOf(_from);
        if (_amount > shyftBal) {
            shyftTokenContract.transfer(_to, shyftBal);
        } else {
            shyftTokenContract.transfer(_to, _amount);
        }
    }
}
