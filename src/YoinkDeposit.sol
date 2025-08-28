// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title YoinkDeposit
 * @dev An escrow contract that acts as a treasury for a yoink.
 * Users can deposit tokens here and the contract will authorize the YoinkMaster to create streams.
 */
contract YoinkDeposit {
    using SuperTokenV1Library for ISuperToken;
    
    // ============ State Variables ============
    
    address public owner;
    address public yoinkMaster;
    ISuperToken public token;
    bool public initialized;
    
    // ============ Events ============
    
    event TokensDeposited(address indexed depositor, uint256 amount);
    event TokensWithdrawn(address indexed recipient, uint256 amount);
    event YoinkMasterAuthorized(address indexed yoinkMaster, ISuperToken token);
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        require(msg.sender == owner, "YoinkDeposit: caller is not the owner");
        _;
    }
    
    modifier onlyInitialized() {
        require(initialized, "YoinkDeposit: not initialized");
        _;
    }
    
    // ============ Initialization ============
    
    /**
      * @dev Initializes the escrow contract
 * @param _owner Owner of the escrow contract
     * @param _yoinkMaster Address of the YoinkMaster contract
     * @param _token SuperToken to be managed
     */
    function initialize(address _owner, address _yoinkMaster, ISuperToken _token) external {
        require(!initialized, "YoinkDeposit: already initialized");
        require(_owner != address(0), "YoinkDeposit: owner cannot be zero");
        require(_yoinkMaster != address(0), "YoinkDeposit: yoinkMaster cannot be zero");
        require(address(_token) != address(0), "YoinkDeposit: token cannot be zero");
        
        owner = _owner;
        yoinkMaster = _yoinkMaster;
        token = _token;
        initialized = true;
        
        token.setMaxFlowPermissions(yoinkMaster);
        
        emit YoinkMasterAuthorized(yoinkMaster, token);
    }
    
    /**
     * @dev Allows the admin (owner) to withdraw all of a specified token to themselves.
     * @param _token The token address to withdraw (SuperToken or ERC20)
     */
    function withdrawAll(address _token) external onlyOwner onlyInitialized {
        require(_token != address(0), "YoinkDeposit: token cannot be zero");
        require(msg.sender == owner, "YoinkDeposit: only admin can withdraw");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "YoinkDeposit: no tokens to withdraw");
        IERC20(_token).transfer(owner, balance);
        emit TokensWithdrawn(owner, balance);
    }
}
