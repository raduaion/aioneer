// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./IERC20.sol";

contract AionSol {
    uint256 version = 0;

    address payable public owner;
    address payable public cUSDToken;

    enum Status {
        CREATED,
        COLLATERAL_PAID,
        STAKED,
        WITHDRAWN,
        COMPLETED,
        DEFAULTED,
        CANCELED
    }

    struct ProfitShareDetails {
        uint256 projectId;
        uint256 principal;
        uint256 collateral;
        uint256 interestRate;
        uint256 maturity;
        uint256 staked;
    }

    ProfitShareDetails public details;
    Status status;

    address[] stakers;
    mapping(address=>uint256) stakedAmount;

    struct ProfitSharePayment {
        uint256 principal;
        uint256 collateral;
        uint256 interest;
        uint256 timestamp;
    }
    ProfitSharePayment public paymentDetails;

    error InvalidNumber(uint256 required, uint256 passed);
    error MaximumValue(uint256 required, uint256 passed);
    error MinimumValue(uint256 required, uint256 passed);
    error InvalidStatus(Status required, Status current);
    error InvalidAddress(address required, address current);

    modifier onlyOwner {
        if(msg.sender != owner) {
            revert InvalidAddress(owner, msg.sender);
        }
        _;
    }

    modifier onlyStatus(Status _status) {
        if(status != _status) {
            revert InvalidStatus(_status, status);
        }
        _;
    }

    constructor(ProfitShareDetails memory _pDetails, address _cUSDToken) {
        require(_pDetails.projectId != 0, "Project ID cannot be 0");
        require(_pDetails.principal > 0, "Principal must be bigger than 0");
        require(_pDetails.collateral <= _pDetails.principal / 2, "Collateral cannot be bigger than 50% of principal");
        require(_pDetails.maturity > 0, "Maturity must be bigger than 0");
        require(_pDetails.interestRate > 0, "Interest rate must be bigger than 0");
        require(_pDetails.staked == 0, "Staked amount must be 0");
        owner = payable(msg.sender);
        details = _pDetails;
        if(_pDetails.collateral == 0) {
            status = Status.COLLATERAL_PAID;
        } else {
            status = Status.CREATED;
        }
        paymentDetails.timestamp = 0;
        cUSDToken = payable(_cUSDToken);
    }

    function get() public view returns (ProfitShareDetails memory, Status) {
        return (details, status);
    }

    function getToken() public view returns (address) {
        return cUSDToken;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getBalanceCUSD() public view returns (uint256) {
        return IERC20(cUSDToken).balanceOf(address(this));
    }

    function getOwner() public view returns (address) {
        return owner;
    }

    function payCollateral() external onlyOwner onlyStatus(Status.CREATED) {
        IERC20(cUSDToken).transferFrom(msg.sender, address(this), details.collateral);
        status = Status.COLLATERAL_PAID;
    }

    function stake(uint256 _amount) external onlyStatus(Status.COLLATERAL_PAID) {
        if(details.staked + _amount > details.principal) {
            revert MaximumValue(details.principal - details.staked, _amount);
        }

        // minimum 5% of the stake
        if(details.staked + _amount < details.principal/20) {
            revert MinimumValue(details.principal/20, details.staked+_amount);
        }

        IERC20(cUSDToken).transferFrom(msg.sender, address(this), _amount);

        details.staked += _amount;
        stakedAmount[msg.sender] += _amount;
        stakers.push(msg.sender);

        if(details.staked == details.principal) {
            paymentDetails.timestamp = block.timestamp;
            status = Status.STAKED;
        }
    }

    function withdraw() external onlyOwner onlyStatus(Status.STAKED){
        IERC20(cUSDToken).transfer(payable(owner), details.principal);
        status = Status.WITHDRAWN;
    }

    function getPaymentDetails() public view returns (ProfitSharePayment memory) {
        return paymentDetails;
    }

    function payInstallment(uint256 _principalAmount) external onlyOwner onlyStatus(Status.WITHDRAWN) {
        if(details.principal - paymentDetails.principal < _principalAmount) {
            revert InvalidNumber(details.principal - paymentDetails.principal, _principalAmount);
        }

        uint256 _interest = _principalAmount * details.interestRate / 100;
        uint256 _total = _principalAmount + _interest;
        // transfer the amount from the owner
        IERC20(cUSDToken).transferFrom(msg.sender, address(this), _total);

        // pay stakers
        for (uint i = 0; i < stakers.length; i++) {
            uint256 _percentage = stakedAmount[stakers[i]] * 100 / details.principal;
            uint256 _principalForStaker = _percentage * _principalAmount / 100;
            uint256 _interestForStaker = _percentage * _interest / 100;

            IERC20(cUSDToken).transfer(payable(stakers[i]), _principalForStaker + _interestForStaker);
        }

        // update amounts paid
        paymentDetails.principal += _principalAmount;
        paymentDetails.interest += _interest;

        // release collateral
        uint256 _collateral = details.collateral * _principalAmount / details.principal;
        IERC20(cUSDToken).transfer(payable(owner), _collateral);
        paymentDetails.collateral += _collateral;

        if(paymentDetails.principal == details.principal) {
            status = Status.COMPLETED;
        }
    }

    function getVersion() public view returns (uint256) {
        return version;
    }
}
