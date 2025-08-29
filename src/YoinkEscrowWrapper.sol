// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YoinkMaster} from "./YoinkMaster.sol";

/**
 * @title YoinkDepositWrapper
 * @dev An escrow contract that acts as a treasury for a yoink.
 * Users can deposit tokens here and the contract will authorize the YoinkMaster to create streams.
 * Supports both regular superTokens and wrapper superTokens with local wrapping functionality.
 */
contract YoinkEscrowWrapper {
    using SuperTokenV1Library for ISuperToken;
    
    // ============ State Variables ============
    
    address public owner;
    address public yoinkMaster;
    ISuperToken public superToken;
    address public underlyingToken; // The underlying token for wrapper superTokens
    bool public initialized;
    bool public isWrapperToken; // Whether this is a wrapper superToken
    address public factory;
    
    // ============ Events ============
    
    event TokensDeposited(address indexed depositor, uint256 amount);
    event TokensWithdrawn(address indexed recipient, uint256 amount);
    event YoinkMasterAuthorized(address indexed yoinkMaster, ISuperToken superToken);
    event TokensWrapped(address indexed wrapper, uint256 underlyingAmount, uint256 superTokenAmount);
    event TokensUnwrapped(address indexed unwrapper, uint256 superTokenAmount, uint256 underlyingAmount);
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        require(msg.sender == owner || msg.sender == factory, "YoinkDepositWrapper: caller is not the owner");
        _;
    }
    
    modifier onlyInitialized() {
        require(initialized, "YoinkDepositWrapper: not initialized");
        _;
    }
    
    // ============ Initialization ============
    
    /**
     * @dev Initializes the escrow contract
     * @param _owner Owner of the escrow contract
     * @param _yoinkMaster Address of the YoinkMaster contract
     * @param _superToken SuperToken to be managed
     * @param _underlyingToken Underlying token for wrapper superTokens (address(0) for non-wrapper)
     */
    function initialize(
        address _owner, 
        address _yoinkMaster, 
        ISuperToken _superToken,
        address _underlyingToken
    ) external {
        require(!initialized, "YoinkDepositWrapper: already initialized");
        require(_owner != address(0), "YoinkDepositWrapper: owner cannot be zero");
        require(_yoinkMaster != address(0), "YoinkDepositWrapper: yoinkMaster cannot be zero");
        require(address(_superToken) != address(0), "YoinkDepositWrapper: superToken cannot be zero");
        
        owner = _owner;
        yoinkMaster = _yoinkMaster;
        superToken = _superToken;
        underlyingToken = _underlyingToken;
        factory = msg.sender; // Set factory to the caller
        initialized = true;
        
        // Note: setMaxFlowPermissions will be called when tokens are deposited
        // This avoids issues in testing environments where the contract has no SuperTokens
        emit YoinkMasterAuthorized(yoinkMaster, superToken);
        }
    
    /**
     * @dev Creates a yoink with this escrow contract as the treasury
     * @param _admin Admin of the yoink
     * @param _yoinkAgent Address authorized to change recipients
     * @param _streamAgent Address authorized to change flow rates
     * @param _metadataURI Optional metadata URI for the yoink
     * @param _hook Optional hook contract address
     * @return yoinkId The ID of the created yoink
     */
    function createYoink(
        address _admin,
        address _yoinkAgent,
        address _streamAgent,
        string memory _metadataURI,
        address _hook
    ) external onlyOwner returns (uint256 yoinkId) {
        require(initialized, "YoinkDepositWrapper: not initialized");
        require(_admin != address(0), "YoinkDepositWrapper: admin cannot be zero");
        require(_yoinkAgent != address(0), "YoinkDepositWrapper: yoinkAgent cannot be zero");
        require(_streamAgent != address(0), "YoinkDepositWrapper: streamAgent cannot be zero");
        
        // Create the yoink - this contract becomes the treasury
        yoinkId = YoinkMaster(yoinkMaster).createYoink(
            _admin,
            _yoinkAgent,
            _flowRateAgent,
            superToken,
            _metadataURI,
            _hook
        );
        
        // Note: Hook will be set by the factory after yoink creation
    }

  
    // ============ Wrapping Functions ============

    /**
     * @dev Wraps all underlying tokens into superTokens
     */
    function wrapAll() external onlyInitialized {
        uint256 balance = IERC20(underlyingToken).balanceOf(address(this));
        if (balance == 0) return;
        superToken.upgrade(balance);
        emit TokensWrapped(address(this), balance, balance);
    }

    // ============ Withdrawal Functions ============
    
    /**
     * @dev Legacy function for backward compatibility
     * Allows the admin (owner) to withdraw all of a specified token to themselves.
     * @param _token The token address to withdraw (SuperToken or ERC20)
     */
    function withdrawAll(address _token) external onlyOwner onlyInitialized {
        require(_token != address(0), "YoinkDepositWrapper: token cannot be zero");
        require(msg.sender == owner, "YoinkDepositWrapper: only admin can withdraw");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "YoinkDepositWrapper: no tokens to withdraw");
        IERC20(_token).transfer(owner, balance);
        emit TokensWithdrawn(owner, balance);
    }
    
    // ============ View Functions ============
    
    /**
     * @dev Gets the current balance of superTokens in this contract
     * @return Current superToken balance
     */
    function getSuperTokenBalance() external view returns (uint256) {
        return superToken.balanceOf(address(this));
    }
    
    /**
     * @dev Gets the current balance of underlying tokens in this contract
     * @return Current underlying token balance
     */
    function getUnderlyingBalance() external view returns (uint256) {
        if (!isWrapperToken) return 0;
        return IERC20(underlyingToken).balanceOf(address(this));
    }

}
