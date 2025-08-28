// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";


import {NonTransferrableNFT} from "./NonTransferrableNFT.sol";

/**
 * @title YoinkMaster
 * @dev A contract for managing Superfluid streams with dynamic beneficiary changes.
 * The contract uses createFlowFrom to stream from treasury accounts without taking custody.
 * 
 * Permission Hierarchy:
 * 0. Only Treasury can create a yoink as only treasury can set themselves as treasury
 * 1. Treasury & Token of a yoinkID are immutable. Shouldn't be able to change
 * 2. YoinkAgent, FlowRateAgent, and Hook are mutable by the Admin
 * 3. The Admin is mutable by the admin.
 * 
 * Also includes factory functionality to create escrow contracts.
 */
contract YoinkMaster is NonTransferrableNFT, ReentrancyGuard {
    using SuperTokenV1Library for ISuperToken;

    // ============ Structs ============
    
    struct YoinkData {
        address admin;                   // Current admin of this yoink (mutable by admin)
        address yoinkAgent;              // Authorized bot for changing recipients (mutable by admin)
        address flowRateAgent;           // Authorized bot for changing flow rates (mutable by admin)
        address treasury;                // Treasury address that funds the stream (IMMUTABLE)
        ISuperToken token;               // SuperToken being streamed (IMMUTABLE)
        address currentRecipient;        // Current stream recipient
        int96 currentFlowRate;           // Current flow rate
        bool isActive;                   // Whether the stream is active
        address hook;                    // Hook contract for beforeYoink calls (mutable by admin)
    }

    // ============ Events ============
    
    event YoinkCreated(uint256 indexed yoinkId, address indexed treasury, address indexed admin, address token);
    event RecipientChanged(uint256 indexed yoinkId, address indexed oldRecipient, address indexed newRecipient);
    event FlowRateUpdated(uint256 indexed yoinkId, int96 oldFlowRate, int96 newFlowRate);
    event YoinkAgentSet(uint256 indexed yoinkId, address indexed oldAgent, address indexed newAgent);
    event FlowRateAgentSet(uint256 indexed yoinkId, address indexed oldAgent, address indexed newAgent);
    event AdminshipTransferred(uint256 indexed yoinkId, address indexed oldAdmin, address indexed newAdmin);
    event StreamStarted(uint256 indexed yoinkId, address indexed recipient, int96 flowRate);
    event StreamStopped(uint256 indexed yoinkId);

    event YoinkHookSet(uint256 indexed yoinkId, address indexed hook);
    event YoinkHookRemoved(uint256 indexed yoinkId);

    // ============ State Variables ============
    
    mapping(uint256 => YoinkData) public yoinks;
    
    // Total number of yoinks created (for sequential IDs)
    uint256 public totalSupply;
    
    // Mapping to track NFT balances (address => number of active NFTs)
    mapping(address => uint256) private _balances;
    
    // ============ Modifiers ============
    
    modifier onlyYoinkAdmin(uint256 yoinkId) {
        require(yoinks[yoinkId].admin == msg.sender, "Yoink: caller is not the yoink admin");
        _;
    }
    
    modifier onlyYoinkAgent(uint256 yoinkId) {
        require(
            yoinks[yoinkId].yoinkAgent == msg.sender || yoinks[yoinkId].admin == msg.sender,
            "Yoink: caller is not authorized to change recipients"
        );
        _;
    }
    
    modifier onlyFlowRateAgent(uint256 yoinkId) {
        require(
            yoinks[yoinkId].flowRateAgent == msg.sender || yoinks[yoinkId].admin == msg.sender,
            "Yoink: caller is not authorized to change flow rates"
        );
        _;
    }
    
    modifier yoinkExists(uint256 yoinkId) {
        require(yoinks[yoinkId].treasury != address(0), "Yoink: yoink does not exist");
        _;
    }

    // ============ Constructor ============
    
    constructor() NonTransferrableNFT("Yoink", "YOINK") {
    }

    // ============ Core Functions ============
    
    /**
     * @dev Creates a new yoink. Only the treasury can create yoinks for security.
     * Treasury and Token are immutable once set.
     * @param admin Initial admin of the yoink (can be treasury or someone else)
     * @param yoinkAgent Address authorized to change recipients
     * @param flowRateAgent Address authorized to change flow rates
     * @param token SuperToken to be streamed (immutable once set)
     * @param metadataURI Optional metadata URI for the yoink NFT (empty string if not provided)
     */
    function createYoink(
        address admin,
        address yoinkAgent,
        address flowRateAgent,
        ISuperToken token,
        string memory metadataURI
    ) external returns (uint256) {
        totalSupply++;
        uint256 yoinkId = totalSupply;
        require(admin != address(0), "Yoink: admin cannot be zero address");
        require(address(token) != address(0), "Yoink: token cannot be zero address");
        yoinks[yoinkId] = YoinkData({
            treasury: msg.sender,         // Only treasury can create
            admin: admin,
            yoinkAgent: yoinkAgent,
            flowRateAgent: flowRateAgent,
            token: token,
            isActive: false,
            hook: address(0),
            currentRecipient: address(0),
            currentFlowRate: 0
        });
        // Set metadata URI - use provided URI or default if empty
        string memory finalURI = bytes(metadataURI).length > 0 
            ? metadataURI 
            : "ipfs://bafkreiejevgwmhd7ecmq5rjf2khkbssxdquiwvag57vfvobp6yyphrs66i";
        _setTokenURI(yoinkId, finalURI);
        
        // Note: NFT will be minted when stream starts, not when yoink is created
        
        emit YoinkCreated(yoinkId, msg.sender, admin, address(token));
        return yoinkId;
    }

    /**
     * @dev Sets or updates the flow rate for a yoink using createFlowFrom
     * @param yoinkId Unique identifier for the yoink
     * @param newFlowRate New flow rate to set (must be positive)
     * @param recipient Recipient address (if starting a new stream)
     */
    function setFlowRate(
        uint256 yoinkId,
        int96 newFlowRate,
        address recipient
    ) external onlyFlowRateAgent(yoinkId) yoinkExists(yoinkId) {
        require(newFlowRate > 0, "Yoink: flow rate must be positive");
        require(recipient != address(0), "Yoink: recipient cannot be zero address");
        YoinkData storage yoink = yoinks[yoinkId];
        
        if (yoink.isActive) {
            // Update existing stream
            int96 oldFlowRate = yoink.currentFlowRate;
            
            // Update the flow rate
            yoink.token.updateFlowFrom(yoink.treasury, yoink.currentRecipient, newFlowRate);
            yoink.currentFlowRate = newFlowRate;
            emit FlowRateUpdated(yoinkId, oldFlowRate, newFlowRate);
        } else {
            // Create stream from treasury to recipient
            yoink.token.createFlowFrom(yoink.treasury, recipient, newFlowRate);
            
            // Update state after successful Superfluid call
            yoink.currentRecipient = recipient;
            yoink.currentFlowRate = newFlowRate;
            yoink.isActive = true;
            
            // Update balance and emit mint event for the yoink NFT
            _balances[recipient]++;
            _emitMint(recipient, yoinkId);
            
            emit StreamStarted(yoinkId, recipient, newFlowRate);
        }
    }

    /**
     * @dev Yoinks the stream to a new recipient using createFlowFrom
     * @param yoinkId Unique identifier for the yoink
     * @param newRecipient New recipient address
     * Note: contracts calling this function should try-catch to avoid reverting the entire transaction.
     */
    function yoink(
        uint256 yoinkId,
        address newRecipient
    ) external onlyYoinkAgent(yoinkId) yoinkExists(yoinkId) nonReentrant {
        require(newRecipient != address(0), "Yoink: new recipient cannot be zero address");
        
        YoinkData storage yoink = yoinks[yoinkId];
        require(yoink.isActive, "Yoink: stream is not active");
        
        address oldRecipient = yoink.currentRecipient;
        
        // Call hook before yoink if set
        if (yoink.hook != address(0)) {
            //TODO: update hook to return (potentially) a new recipient
            yoink.hook.call(
                abi.encodeWithSignature(
                    "beforeYoink(uint256,address,address,address)",
                    yoinkId,
                    oldRecipient,
                    newRecipient,
                    msg.sender
                )
            );
        }
        
        // Delete the old stream and create new one
        yoink.token.deleteFlowFrom(yoink.treasury, oldRecipient);
        yoink.token.createFlowFrom(yoink.treasury, newRecipient, yoink.currentFlowRate);
        
        // Update state after successful Superfluid calls
        yoink.currentRecipient = newRecipient;
        
        // Update balances and emit transfer event for NFT ownership change
        _balances[oldRecipient]--;
        _balances[newRecipient]++;
        _emitTransfer(oldRecipient, newRecipient, yoinkId);
        
        emit RecipientChanged(yoinkId, oldRecipient, newRecipient);
    }

    /**
     * @dev Stops the stream for a yoink
     * @param yoinkId Unique identifier for the yoink
     */
    function stopStream(uint256 yoinkId) external onlyYoinkAdmin(yoinkId) yoinkExists(yoinkId) nonReentrant {
        YoinkData storage yoink = yoinks[yoinkId];
        require(yoink.isActive, "Yoink: stream is not active");
        
        // Delete the stream
        yoink.token.deleteFlowFrom(yoink.treasury, yoink.currentRecipient);
        
        // Update state after successful Superfluid call
        yoink.isActive = false;
        yoink.currentFlowRate = 0;
        
        // Update balance and emit burn event for the yoink NFT
        _balances[yoink.currentRecipient]--;
        _emitBurn(yoink.currentRecipient, yoinkId);
        
        emit StreamStopped(yoinkId);
    }

    // ============ Management Functions ============
    
    /**
     * @dev Sets a hook for the yoink function. Hook can do anything including reverting.
     * @param yoinkId Unique identifier for the yoink
     * @param hook Address of the hook contract (address(0) to remove)
     */
    function setYoinkHook(uint256 yoinkId, address hook) 
        external 
        onlyYoinkAdmin(yoinkId) 
        yoinkExists(yoinkId) 
    {
        YoinkData storage yoink = yoinks[yoinkId];
        yoink.hook = hook;
        if (hook != address(0)) {
            emit YoinkHookSet(yoinkId, hook);
        } else {
            emit YoinkHookRemoved(yoinkId);
        }
    }
    

    
    /**
     * @dev Sets a new yoink agent for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @param agent Address to set as yoink agent (can be zero to remove)
     */
    function setYoinkAgent(uint256 yoinkId, address agent)
        external
        onlyYoinkAdmin(yoinkId)
        yoinkExists(yoinkId)
    {
        address oldAgent = yoinks[yoinkId].yoinkAgent;
        yoinks[yoinkId].yoinkAgent = agent;
        
        emit YoinkAgentSet(yoinkId, oldAgent, agent);
    }

    /**
     * @dev Sets a new flow rate agent for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @param agent Address to set as flow rate agent (can be zero to remove)
     */
    function setFlowRateAgent(uint256 yoinkId, address agent) 
        external 
        onlyYoinkAdmin(yoinkId) 
        yoinkExists(yoinkId) 
    {
        address oldAgent = yoinks[yoinkId].flowRateAgent;
        yoinks[yoinkId].flowRateAgent = agent;
        
        emit FlowRateAgentSet(yoinkId, oldAgent, agent);
    }

    /**
     * @dev Transfers adminship of a yoink. Can be called by current admin.
     * @param yoinkId Unique identifier for the yoink
     * @param newAdmin New admin address
     */
    function transferAdminship(uint256 yoinkId, address newAdmin) 
        external 
        onlyYoinkAdmin(yoinkId)
        yoinkExists(yoinkId) 
    {
        require(newAdmin != address(0), "Yoink: new admin cannot be zero address");
        
        address oldAdmin = yoinks[yoinkId].admin;
        yoinks[yoinkId].admin = newAdmin;
        
        emit AdminshipTransferred(yoinkId, oldAdmin, newAdmin);
    }

    // ============ View Functions ============
    
    /**
     * @dev Gets the yoink information
     * @param yoinkId Unique identifier for the yoink
     * @return YoinkData struct containing all yoink information
     */
    function getYoink(uint256 yoinkId) external view returns (YoinkData memory) {
        return yoinks[yoinkId];
    }

    /**
     * @dev Gets the admin of a yoink
     * @param yoinkId Unique identifier for the yoink
     * @return Admin address
     */
    function getAdmin(uint256 yoinkId) external view returns (address) {
        return yoinks[yoinkId].admin;
    }

    /**
     * @dev Gets the owner of a yoink
     * @param yoinkId Unique identifier for the yoink
     * @return Owner address
     */
    function ownerOf(uint256 yoinkId) public view override returns (address) {
        YoinkData storage yoink = yoinks[yoinkId];
        if (!yoink.isActive || yoink.currentRecipient == address(0)) {
            revert("ERC721: invalid token ID");
        }
        return yoink.currentRecipient;
    }
    
    /**
     * @dev Gets the balance of NFTs for an address
     * @param owner Address to check balance for
     * @return Number of active NFTs owned by the address
     */
    function balanceOf(address owner) public view override returns (uint256) {
        require(owner != address(0), "ERC721: address zero is not a valid owner");
        return _balances[owner];
    }

    /**
     * @dev Checks if an address is authorized as a yoink agent
     * @param yoinkId Unique identifier for the yoink
     * @param agent Address to check
     * @return bool True if authorized
     */
    function isYoinkAgent(uint256 yoinkId, address agent) external view returns (bool) {
        return yoinks[yoinkId].yoinkAgent == agent || yoinks[yoinkId].admin == agent;
    }

    /**
     * @dev Checks if an address is authorized as a flow rate agent
     * @param yoinkId Unique identifier for the yoink
     * @param agent Address to check
     * @return bool True if authorized
     */
    function isFlowRateAgent(uint256 yoinkId, address agent) external view returns (bool) {
        return yoinks[yoinkId].flowRateAgent == agent || yoinks[yoinkId].admin == agent;
    }

    /**
     * @dev Gets the current flow rate for a specific yoink
     * @param yoinkId Unique identifier for the yoink
     * @return Current flow rate
     */
    function getCurrentFlowRate(uint256 yoinkId) external view returns (int96) {
        YoinkData storage yoink = yoinks[yoinkId];
        if (!yoink.isActive) return 0;
        
        return yoink.token.getFlowRate(yoink.treasury, yoink.currentRecipient);
    }

    /**
     * @dev Gets the current recipient for a specific yoink
     * @param yoinkId Unique identifier for the yoink
     * @return Current recipient address
     */
    function getCurrentRecipient(uint256 yoinkId) external view returns (address) {
        return yoinks[yoinkId].currentRecipient;
    }

    /**
     * @dev Checks if a yoink is active
     * @param yoinkId Unique identifier for the yoink
     * @return True if the yoink is active
     */
    function isYoinkActive(uint256 yoinkId) external view returns (bool) {
        return yoinks[yoinkId].isActive;
    }

    /**
     * @dev Gets the treasury address for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @return Treasury address
     */
    function getTreasury(uint256 yoinkId) external view returns (address) {
        return yoinks[yoinkId].treasury;
    }
    
    /**
     * @dev Gets the treasury balance for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @return Treasury balance
     */
    function getTreasuryBalance(uint256 yoinkId) external view returns (uint256) {
        YoinkData storage yoink = yoinks[yoinkId];
        return yoink.token.balanceOf(yoink.treasury);
    }

}
