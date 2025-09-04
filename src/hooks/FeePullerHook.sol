// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYoinkHook} from "./IYoinkHook.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {YoinkMaster} from "../YoinkMaster.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "./IPositionManager.sol";

/**
 * @title FeePullerHook
 * @dev Hook that pulls fees from a position manager and deposits them into the escrow contract
 * This hook acts as both a yoink hook and a flow rate agent
 */
contract FeePullerHook is IYoinkHook {
    
    // ============ Events ============
    
    event FeesPulled(uint256 indexed yoinkId, uint256 amount, address token);
    event FeesDeposited(uint256 indexed yoinkId, uint256 amount, address escrowContract);
    event PositionManagerSet(uint256 indexed yoinkId, address indexed positionManager);
    event FeeTokenSet(uint256 indexed yoinkId, address indexed feeToken);
    
    // ============ State Variables ============
    
    YoinkMaster public immutable yoinkMaster;
    
    // Mapping from yoinkId to position manager contract
    mapping(uint256 => address) public positionManagers;
    
    // Mapping from yoinkId to fee token address
    mapping(uint256 => address) public feeTokens;
    
    // Mapping from yoinkId to minimum fee threshold
    mapping(uint256 => uint256) public minFeeThresholds;
    
    // ============ Constructor ============
    
    constructor(address _yoinkMaster) {
        yoinkMaster = YoinkMaster(_yoinkMaster);
    }
    
    // ============ Hook Functions ============
    
    /**
     * @dev Hook function called before yoink
     * Pulls fees and deposits them into the escrow contract
     */
    function beforeYoink(
        uint256 yoinkId,
        address oldRecipient,
        address newRecipient,
        address caller
    ) external returns (address) {
        // Pull fees from position manager
        _pullAndDepositFees(yoinkId);

        // Return address(0) to use the original recipient
        return address(0);
    }
    
    // ============ Configuration Functions ============
    
    /**
     * @dev Sets the position manager for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @param positionManager Address of the position manager contract
     */
    function setPositionManager(uint256 yoinkId, address positionManager) external {
        if(msg.sender != yoinkMaster.getAdmin(yoinkId)) {
            revert("FeePullerHook: only yoink admin can set position manager");
        }
        require(positionManager != address(0), "FeePullerHook: position manager cannot be zero");
        positionManagers[yoinkId] = positionManager;
        emit PositionManagerSet(yoinkId, positionManager);
    }
    
    /**
     * @dev Sets the fee token for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @param feeToken Address of the fee token
     */
    function setFeeToken(uint256 yoinkId, address feeToken) external {
        if(msg.sender != yoinkMaster.getAdmin(yoinkId)) {
            revert("FeePullerHook: only yoink admin can set fee token");
        }
        require(feeToken != address(0), "FeePullerHook: fee token cannot be zero");
        feeTokens[yoinkId] = feeToken;
        emit FeeTokenSet(yoinkId, feeToken);
    }
    
    /**
     * @dev Sets the minimum fee threshold for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @param minThreshold Minimum amount of fees to pull
     */
    function setMinFeeThreshold(uint256 yoinkId, uint256 minThreshold) external {
        if(msg.sender != yoinkMaster.getAdmin(yoinkId)) {
            revert("FeePullerHook: only yoink admin can set fee threshold");
        }
        minFeeThresholds[yoinkId] = minThreshold;
    }
    
    /**
     * @dev Manually pulls fees for a yoink
     * @param yoinkId Unique identifier for the yoink
     */
    function pullFees(uint256 yoinkId) external {
        _pullAndDepositFees(yoinkId);
    }
    
    // ============ Internal Functions ============
    
    function _pullAndDepositFees(uint256 yoinkId) internal {
        address positionManager = positionManagers[yoinkId];
        address feeToken = feeTokens[yoinkId];
        
        if (positionManager == address(0) || feeToken == address(0)) {
            return; // Not configured
        }
        
        // Get current fee balance from position manager
        uint256 feeBalance = _getFeeBalance(positionManager, feeToken);
        uint256 minThreshold = minFeeThresholds[yoinkId];
        
        if (feeBalance < minThreshold) {
            return; // Not enough fees to pull
        }
        
        // Pull fees from position manager
        uint256 pulledAmount = _pullFeesFromPositionManager(positionManager, feeToken, feeBalance);
        
        if (pulledAmount > 0) {
            emit FeesPulled(yoinkId, pulledAmount, feeToken);
            
            // Deposit fees into escrow contract
            address escrowContract = _getEscrowContract(yoinkId);
            if (escrowContract != address(0)) {
                _depositFeesToEscrow(yoinkId, feeToken, pulledAmount, escrowContract);
            }
        }
    }
    
    function _getFeeBalance(address positionManager, address feeToken) internal view returns (uint256) {
        // Call the position manager's fee balance function
        try IPositionManager(positionManager).getFeeBalance(feeToken) returns (uint256 balance) {
            return balance;
        } catch {
            // Fallback to ERC20 balance if the interface is not supported
            return IERC20(feeToken).balanceOf(positionManager);
        }
    }
    
    function _pullFeesFromPositionManager(address positionManager, address feeToken, uint256 amount) internal returns (uint256) {
        // Call the position manager's fee withdrawal function
        try IPositionManager(positionManager).withdrawFees(feeToken, amount) returns (uint256 withdrawn) {
            return withdrawn;
        } catch {
            // Fallback to direct transfer if the interface is not supported
            // Note: This requires the hook to have approval from the position manager
            IERC20(feeToken).transferFrom(positionManager, address(this), amount);
            return amount;
        }
    }
    
    function _getEscrowContract(uint256 yoinkId) internal view returns (address) {
        // Get the treasury address from YoinkMaster
        address treasury = yoinkMaster.getTreasury(yoinkId);
        
        // Check if this is an escrow contract by calling a function on it
        // For now, we'll assume any treasury that's not the original caller is an escrow
        // In practice, you might want to add a function to check if an address is an escrow contract
        
        return treasury;
    }
    
    function _depositFeesToEscrow(uint256 yoinkId, address feeToken, uint256 amount, address escrowContract) internal {
        // Transfer fees to escrow contract
        IERC20(feeToken).transfer(escrowContract, amount);
        
        // If the escrow contract supports it, wrap the tokens into superTokens
        _wrapTokensInEscrow(escrowContract, feeToken, amount);
        
        emit FeesDeposited(yoinkId, amount, escrowContract);
    }
    
    function _wrapTokensInEscrow(address escrowContract, address feeToken, uint256 amount) internal {
        // This would call the escrow contract's wrap function
        // Example: YoinkEscrowWrapper(escrowContract).wrapTokens(feeToken, amount);
        
        // For now, this is a placeholder - the actual implementation would depend on the escrow contract interface
    }
    
    // ============ View Functions ============
    
    /**
     * @dev Gets the current fee balance for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @return Current fee balance
     */
    function getFeeBalance(uint256 yoinkId) external view returns (uint256) {
        address positionManager = positionManagers[yoinkId];
        address feeToken = feeTokens[yoinkId];
        
        if (positionManager == address(0) || feeToken == address(0)) {
            return 0;
        }
        
        return _getFeeBalance(positionManager, feeToken);
    }
    
    /**
     * @dev Gets the configuration for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @return positionManager Address of the position manager
     * @return feeToken Address of the fee token
     * @return minThreshold Minimum fee threshold
     */
    function getConfiguration(uint256 yoinkId) external view returns (
        address positionManager,
        address feeToken,
        uint256 minThreshold
    ) {
        return (
            positionManagers[yoinkId],
            feeTokens[yoinkId],
            minFeeThresholds[yoinkId]
        );
    }
}
