// SPDX-License-Identifier: BSD-3-Clause

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ApeClaim is Ownable {

    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;
    using SafeERC20 for IERC20;

    // List of all 106 LPs
    EnumerableSet.AddressSet private _whiteList;
    // indicate the whitelist has been audited and allow LPs proceed to claim.
    bool public whiteListConfirmed = false;
    // Number of LPs
    uint public LPS_COUNT = 106;

    // YX's address to receive the rewards.
    address public YX = address(0x564286362092D8e7936f0549571a803B203aAceD);
    // preserved YX rewards
    uint public YX_REWARDS = 3; // means amount will be divided by 109
    // indicate whether YX can start to claim the rewards.
    bool public YX_REWARDS_RELEASED = false;
    // How much rewards YX has already claimed.
    uint public YX_REWARDS_CLAIMED;

    // Total amount has been claimed from this contract.
    uint public totalClaimed;
    // record of amount that each LP has already claimed
    mapping (address => uint) public lpClaimed;

    IERC20 public WETH = IERC20(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    //    address public BSC_ETH = "0x2170ed0880ac9a755fd29b2688956bd959f933f8";

    event AddedLP(address indexed lp_);
    event RemovedLP(address indexed lp_);
    event ConfirmedWhitelist();
    event Claimed(address indexed lp_, uint amount_);
    event ReleasedYXRewards(uint yxRewards_);
    event ClaimedYXRewards(address indexed yxAddress_, uint amount_);

    modifier whenWhiteListNotConfirmed() {
        require(! whiteListConfirmed, "ApeClaim: whitelist has already been finalized");
        _;
    }

    modifier whenWhiteListConfirmed() {
        require(whiteListConfirmed, "ApeClaim: whitelist has NOT yet been finalized");
        _;
    }

    modifier onlyYX() {
        require(_msgSender() == YX, "ApeClaim: only YX can call this function");
        _;
    }

    modifier onlyLP() {
        require(containsLP(_msgSender()), "ApeClaim: only LP can call this function");
        _;
    }

    modifier whenYXRewardsReleased() {
        require(YX_REWARDS_RELEASED, "ApeClaim: YX's rewards has not been released yet");
        _;
    }

    modifier whenYXRewardsNotReleased() {
        require(! YX_REWARDS_RELEASED, "ApeClaim: YX's rewards has been already released");
        _;
    }

    constructor() {}

    function addLP(address[] calldata lps_ ) external onlyOwner whenWhiteListNotConfirmed {
        for (uint i = 0; i < lps_.length; i++) {
            require(lps_[i] != address(0x0), "ApeClaim:: Can not add 0x0 LP");
            _whiteList.add(lps_[i]);

            emit AddedLP(lps_[i]);
        }
    }

    function removeLP(address[] calldata lps_) external onlyOwner whenWhiteListNotConfirmed {
        require(! whiteListConfirmed, "ApeClaim: whitelist has already been finalized");
        for (uint i = 0; i < lps_.length; i++) {
            require(_whiteList.remove(lps_[i]), "ApeClaim:: LP not exist");
            emit RemovedLP(lps_[i]);
        }
    }

    function confirmWhiteList() external onlyOwner {
        require(_whiteList.length() == LPS_COUNT, "LPs count should exactly be 106");
        whiteListConfirmed = true;
        emit ConfirmedWhitelist();
    }

    function claim() external whenWhiteListConfirmed onlyLP {
        uint amount = getClaimable(_msgSender());
        totalClaimed += amount;
        lpClaimed[_msgSender()] += amount;
        WETH.safeTransfer(_msgSender(), amount);
        emit Claimed(_msgSender(), amount);
    }

    function getClaimable(address who_) view public returns(uint) {
        require(who_ != address(0x0));
        require(containsLP(who_), "ApeClaim: only support to get claimable amount of LP");
        uint totalAmount = (WETH.balanceOf(address(this)) + totalClaimed);
        uint lpQuotaAmount = totalAmount / (LPS_COUNT + YX_REWARDS);
        require(lpQuotaAmount >= lpClaimed[who_]);
        uint lpClaimableAmount = lpQuotaAmount - lpClaimed[who_];
        return lpClaimableAmount;
    }

    function releaseYXRewards(uint finalizedYXRewards_) external onlyOwner whenWhiteListConfirmed whenYXRewardsNotReleased {
        require(finalizedYXRewards_ >= 2 && finalizedYXRewards_ <= 3, "YX rewards should be either 2 or 3");
        // the final rewards must be less than or equals to preserved YX rewards, so that other LP can claim properly.
        require(finalizedYXRewards_ <= YX_REWARDS);
        YX_REWARDS_RELEASED = true;
        emit ReleasedYXRewards(finalizedYXRewards_);
    }

    function claimYXRewards() external onlyYX whenYXRewardsReleased {
        uint amount = getClaimableYXRewards();
        totalClaimed += amount;
        YX_REWARDS_CLAIMED += amount;
        WETH.safeTransfer(_msgSender(), amount);
        emit ClaimedYXRewards(YX, amount);
    }

    function getClaimableYXRewards() public view returns(uint) {
        uint totalAmount = (WETH.balanceOf(address(this)) + totalClaimed);
        uint yxQuotaAmount = (totalAmount - LPS_COUNT) * YX_REWARDS / (LPS_COUNT + YX_REWARDS);
        require(yxQuotaAmount >= YX_REWARDS_CLAIMED);
        uint yxClaimableAmount = yxQuotaAmount - YX_REWARDS_CLAIMED;
        return yxClaimableAmount;
    }

    function containsLP(address lp_) public view returns (bool) {
        return _whiteList.contains(lp_);
    }

    function lpsCount() public view returns (uint) {
        return _whiteList.length();
    }

    function lpAtIndex(uint index) public view returns (address) {
        require(index < _whiteList.length(), "ApeClaim:: index out of bounds");
        return _whiteList.at(index);
    }
}
