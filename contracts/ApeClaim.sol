// SPDX-License-Identifier: BSD-3-Clause

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ApeClaim is Ownable, ReentrancyGuard {
    enum RequestStatus {PENDING, CANCELED, APPROVED, REJECTED}
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;

    struct Request {
        address requester; // sender of the request.
        address newLPAddress; // new address the LP (requester).
        uint nonce; // serial number allocated for each request.
        uint timestamp; // time of the request creation.
        RequestStatus status; // status of the request.
    }
    // mapping between a replacing LP request hash and the corresponding request nonce.
    mapping(bytes32=>uint) public replaceLPRequestNonce;
    // all replacing LP requests
    Request[] public replaceLPRequests;

    // List of all 106 LPs
    EnumerableSet.AddressSet private _whiteList;
    // indicate the whitelist has been audited and allow LPs proceed to claim.
    bool public whiteListConfirmed = false;
    // Each LP's principal
    uint public LP_PRINCIPAL = 1 ether;
    // Number of LPs
    uint public LPS_COUNT = 106;
    // The total principal of all LPs
    uint public TOTAL_PRINCIPAL = LPS_COUNT * LP_PRINCIPAL;

    // YX's address to receive the rewards.
    address public YX = address(0x2482afB8d5136e9728fb0a7445CcaF95532DC614);
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

    event AddedLP(address indexed lp_);
    event RemovedLP(address indexed lp_);
    event ConfirmedWhitelist();
    event Claimed(address indexed lp_, uint amount_);
    event ReleasedYXRewards(uint yxRewards_);
    event ClaimedYXRewards(address indexed yxAddress_, uint amount_);
    event Received(address indexed from_, uint amount_);
    event PullFund(address indexed to_, uint amount_);
    event PullFundERC20(address token_, address indexed to_, uint amount_);
    event ReplacedLP(address indexed originLP_, address indexed newLP_);
    event ReplaceLPRequestAdd(
        uint indexed nonce,
        address indexed requester,
        address indexed newLPAddress,
        uint timestamp,
        bytes32 requestHash
    );
    event ReplaceLPRequestCancel(uint indexed nonce, address indexed requester, bytes32 requestHash);

    event ReplaceLPConfirmed(
        uint indexed nonce,
        address indexed requester,
        address indexed newLPAddress,
        uint timestamp,
        bytes32 requestHash
    );

    event ReplaceLPRejected(
        uint indexed nonce,
        address indexed requester,
        address indexed newLPAddress,
        uint timestamp,
        bytes32 requestHash
    );

    modifier whenWhiteListNotConfirmed() {
        require(! whiteListConfirmed, "ApeClaim: whitelist has already been locked and finalized");
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
        for (uint i = 0; i < lps_.length; i++) {
            require(_whiteList.remove(lps_[i]), "ApeClaim:: LP not exist");
            emit RemovedLP(lps_[i]);
        }
    }

    function replaceLP(address originLP_, address newLP_) external onlyOwner whenWhiteListNotConfirmed {
        require(_replaceLP(originLP_, newLP_), "ApeClaim: failed to replace LP");
    }

    function addReplaceLPAddressRequest(address newLPAddress_) external onlyLP returns (bool) {
        require(newLPAddress_ != address(0x0), "invalid new LP address");

        uint nonce = replaceLPRequests.length;
        uint timestamp = block.timestamp;

        Request memory request = Request({
        requester: msg.sender,
        newLPAddress: newLPAddress_,
        nonce: nonce,
        timestamp: timestamp,
        status: RequestStatus.PENDING
        });

        bytes32 requestHash = calcRequestHash(request);
        replaceLPRequestNonce[requestHash] = nonce;
        replaceLPRequests.push(request);

        emit ReplaceLPRequestAdd(nonce, msg.sender, newLPAddress_, timestamp, requestHash);
        return true;
    }

    function cancelReplaceLpRequest(bytes32 requestHash) external onlyLP returns (bool) {
        uint nonce;
        Request memory request;

        (nonce, request) = getPendingReplaceLPRequest(requestHash);

        require(msg.sender == request.requester, "cancel sender is different than pending request initiator");
        replaceLPRequests[nonce].status = RequestStatus.CANCELED;

        emit ReplaceLPRequestCancel(nonce, msg.sender, requestHash);
        return true;
    }

    function confirmReplaceLPRequest(bytes32 requestHash) external onlyOwner returns (bool) {
        uint nonce;
        Request memory request;

        (nonce, request) = getPendingReplaceLPRequest(requestHash);

        replaceLPRequests[nonce].status = RequestStatus.APPROVED;

        require(_replaceLP(request.requester, request.newLPAddress));

        emit ReplaceLPConfirmed(
            request.nonce,
            request.requester,
            request.newLPAddress,
            request.timestamp,
            requestHash
        );
        return true;
    }

    function _replaceLP(address currentLPAddress_, address newLPAddress_) internal returns (bool) {
        require(currentLPAddress_ != address(0));
        require(newLPAddress_ != address(0));
        require(containsLP(currentLPAddress_), "ApeClaim: the original LP does not exist");
        require(!containsLP(newLPAddress_), "ApeClaim: the new LP already exists.");

        // replace whitelist with new LP
        require(_whiteList.remove(currentLPAddress_), "ApeClaim:: LP not exist");
        require(_whiteList.add(newLPAddress_), "ApeClaim:: LP replace failed");

        // replace claimed amount with new LP
        lpClaimed[newLPAddress_] = lpClaimed[currentLPAddress_];
        delete lpClaimed[currentLPAddress_];

        emit ReplacedLP(currentLPAddress_, newLPAddress_);
        return true;
    }

    function rejectReplaceLPRequest(bytes32 requestHash) external onlyOwner returns (bool) {
        uint nonce;
        Request memory request;

        (nonce, request) = getPendingReplaceLPRequest(requestHash);

        replaceLPRequests[nonce].status = RequestStatus.REJECTED;

        emit ReplaceLPRejected(
            request.nonce,
            request.requester,
            request.newLPAddress,
            request.timestamp,
            requestHash
        );
        return true;
    }

    function calcRequestHash(Request memory request) internal pure returns (bytes32) {
        return keccak256(abi.encode(
                request.requester,
                request.newLPAddress,
                request.nonce,
                request.timestamp
            ));
    }

    function getReplaceLPRequest(uint nonce) external view returns (
        uint requestNonce,
        address requester,
        address newLPAddress,
        uint timestamp,
        string memory status,
        bytes32 requestHash
    )
    {
        Request memory request = replaceLPRequests[nonce];
        string memory statusString = getStatusString(request.status);

        requestNonce = request.nonce;
        requester = request.requester;
        newLPAddress = request.newLPAddress;
        timestamp = request.timestamp;
        status = statusString;
        requestHash = calcRequestHash(request);
    }

    function getReplaceLPRequestsLength() external view returns (uint length) {
        return replaceLPRequests.length;
    }
    
    function getPendingReplaceLPRequest(bytes32 requestHash) internal view returns (uint nonce, Request memory request) {
        require(requestHash != 0, "request hash is 0");
        nonce = replaceLPRequestNonce[requestHash];
        request = replaceLPRequests[nonce];
        validatePendingRequest(request, requestHash);
    }
    
    function validatePendingRequest(Request memory request, bytes32 requestHash) internal pure {
        require(request.status == RequestStatus.PENDING, "request is not pending");
        require(requestHash == calcRequestHash(request), "given request hash does not match a pending request");
    }

    function getStatusString(RequestStatus status) internal pure returns (string memory) {
        if (status == RequestStatus.PENDING) {
            return "pending";
        } else if (status == RequestStatus.CANCELED) {
            return "canceled";
        } else if (status == RequestStatus.APPROVED) {
            return "approved";
        } else if (status == RequestStatus.REJECTED) {
            return "rejected";
        } else {
            // this fallback can never be reached.
            return "unknown";
        }
    }

    function confirmWhiteList() external onlyOwner {
        require(_whiteList.length() == LPS_COUNT, "LPs count should exactly be 106");
        whiteListConfirmed = true;
        emit ConfirmedWhitelist();
    }

    function _transferFund(address to_, uint amount_) internal virtual {
        payable(to_).transfer(amount_);
    }

    function _getBalance(address who_) internal view virtual returns(uint) {
        return who_.balance;
    }

    function _claim(address lp_) internal {
        uint amount = getClaimable(lp_);
        totalClaimed += amount;
        lpClaimed[lp_] += amount;
        _transferFund(lp_, amount);
        emit Claimed(lp_, amount);
    }

    function claim() external whenWhiteListConfirmed onlyLP nonReentrant {
        _claim(_msgSender());
    }

    function getClaimable(address who_) view public returns(uint) {
        require(who_ != address(0x0));
        require(containsLP(who_), "ApeClaim: only support to get claimable amount of LP");

        uint totalAmount = (_getBalance(address(this)) + totalClaimed);
        uint lpQuotaAmount = 0;
        // No reward before gain principal back
        if (totalAmount <= TOTAL_PRINCIPAL) {
            lpQuotaAmount = totalAmount / LPS_COUNT;
        } else {
            uint lpProfitAmount = (totalAmount - TOTAL_PRINCIPAL) / (LPS_COUNT + YX_REWARDS);
            lpQuotaAmount = lpProfitAmount + LP_PRINCIPAL;
        }
        require(lpQuotaAmount >= lpClaimed[who_]);
        uint lpClaimableAmount = lpQuotaAmount - lpClaimed[who_];
        return lpClaimableAmount;
    }

    function releaseToAll() external whenWhiteListConfirmed nonReentrant {
        uint length = _whiteList.length();
        for (uint i = 0; i < length; i++) {
            _claim(_whiteList.at(i));
        }
    }

    function releaseYXRewards(uint finalizedYXRewards_) external onlyOwner whenWhiteListConfirmed whenYXRewardsNotReleased {
        require(finalizedYXRewards_ >= 2 && finalizedYXRewards_ <= 3, "YX rewards should be either 2 or 3");
        // the final rewards must be less than or equals to preserved YX rewards, so that other LP can claim properly.
        require(finalizedYXRewards_ <= YX_REWARDS);
        YX_REWARDS_RELEASED = true;
        emit ReleasedYXRewards(finalizedYXRewards_);
    }

    function claimYXRewards() external onlyYX whenYXRewardsReleased nonReentrant {
        uint amount = getClaimableYXRewards();
        totalClaimed += amount;
        YX_REWARDS_CLAIMED += amount;
        _transferFund(_msgSender(), amount);
        emit ClaimedYXRewards(YX, amount);
    }

    function getClaimableYXRewards() public view returns(uint) {
        uint totalAmount = (_getBalance(address(this)) + totalClaimed);
        // YX would get rewards only after profit gained. ;-)
        if (totalAmount <= TOTAL_PRINCIPAL) {
            return 0;
        }
        uint yxQuotaAmount = (totalAmount - TOTAL_PRINCIPAL) * YX_REWARDS / (LPS_COUNT + YX_REWARDS);
        require(yxQuotaAmount >= YX_REWARDS_CLAIMED);
        uint yxClaimableAmount = yxQuotaAmount - YX_REWARDS_CLAIMED;
        return yxClaimableAmount;
    }

    function pullFunds(address tokenAddress_) onlyOwner external {
        if (tokenAddress_ == address(0)) {
            payable(_msgSender()).transfer(address(this).balance);
            emit PullFund(_msgSender(), address(this).balance);
        } else {
            IERC20 token = IERC20(tokenAddress_);
            token.transfer(_msgSender(), token.balanceOf(address(this)));
            emit PullFundERC20(tokenAddress_, _msgSender(), token.balanceOf(address(this)));
        }
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

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
