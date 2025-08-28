// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YoinkMaster} from "./YoinkMaster.sol";

/**
 * @title YoinkDeposit
 * @dev An escrow contract that acts as a treasury for a yoink.
 * Users can deposit tokens here and the contract will authorize the YoinkMaster to create streams.
 */
contract YoinkEscrowPure {
    using SuperTokenV1Library for ISuperToken;
    
    // ============ State Variables ============
    
    address public owner;
    address public yoinkMaster;
    ISuperToken public token;
    bool public initialized;
    
    // ============ Events ============
    
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
        
        // THIS IS HOW WE AUTHORIZE THE YOINKMASTER TO CREATE STREAMS FROM THIS CONTRACT
        token.setMaxFlowPermissions(yoinkMaster);
        
        emit YoinkMasterAuthorized(yoinkMaster, token);
    }
    
    /**
     * @dev Creates a yoink with this escrow contract as the treasury
     * @param _admin Admin of the yoink
     * @param _yoinkAgent Address authorized to change recipients
     * @param _flowRateAgent Address authorized to change flow rates
     * @param _metadataURI Optional metadata URI for the yoink
     * @param _hook Optional hook contract address
     * @return yoinkId The ID of the created yoink
     */
    function createYoink(
        address _admin,
        address _yoinkAgent,
        address _flowRateAgent,
        string memory _metadataURI,
        address _hook
    ) external onlyOwner returns (uint256 yoinkId) {
        require(initialized, "YoinkDeposit: not initialized");
        require(_admin != address(0), "YoinkDeposit: admin cannot be zero");
        require(_yoinkAgent != address(0), "YoinkDeposit: yoinkAgent cannot be zero");
        require(_flowRateAgent != address(0), "YoinkDeposit: flowRateAgent cannot be zero");
        
        // Create the yoink - this contract becomes the treasury
        yoinkId = YoinkMaster(yoinkMaster).createYoink(
            _admin,
            _yoinkAgent,
            _flowRateAgent,
            token,
            _metadataURI
        );
        
        // Set the hook if provided
        if (_hook != address(0)) {
            YoinkMaster(yoinkMaster).setYoinkHook(yoinkId, _hook);
        }
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
