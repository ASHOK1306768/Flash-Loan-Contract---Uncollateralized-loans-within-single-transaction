// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FlashLoanContract - AUTO DEPLOY VERSION
 * @dev A flash loan contract that provides uncollateralized loans within a single transaction
 * @notice This version automatically sets msg.sender as the initial owner
 * @author Flash Loan Team
 */

interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        bytes calldata params
    ) external returns (bool);
}

contract FlashLoanContract is ReentrancyGuard, Ownable {
    // Events
    event FlashLoan(
        address indexed borrower,
        address indexed asset,
        uint256 amount,
        uint256 fee,
        uint256 timestamp
    );
    
    event LiquidityDeposited(
        address indexed provider,
        address indexed asset,
        uint256 amount,
        uint256 timestamp
    );
    
    event LiquidityWithdrawn(
        address indexed provider,
        address indexed asset,
        uint256 amount,
        uint256 timestamp
    );

    // State variables
    mapping(address => uint256) public poolBalances; // asset => balance
    mapping(address => mapping(address => uint256)) public userDeposits; // user => asset => amount
    mapping(address => bool) public supportedAssets;
    
    uint256 public flashLoanFeePercentage = 9; // 0.09% fee (9 basis points)
    uint256 public constant PERCENTAGE_FACTOR = 10000; // For percentage calculations
    
    address[] public assetsList;

    // Modifiers
    modifier onlySupportedAsset(address asset) {
        require(supportedAssets[asset], "Asset not supported");
        _;
    }

    /**
     * @dev Constructor automatically sets deployer as owner
     * @notice No parameters needed - deployer becomes the owner automatically
     */
    constructor() Ownable(msg.sender) {
        // Contract is ready to use immediately after deployment
        // The deployer automatically becomes the owner
    }

    /**
     * @dev Core Function 1: Execute Flash Loan
     * @param asset The address of the asset to borrow
     * @param amount The amount to borrow
     * @param receiverAddress The address of the contract that will receive the loan
     * @param params Additional parameters to pass to the receiver
     */
    function executeFlashLoan(
        address asset,
        uint256 amount,
        address receiverAddress,
        bytes calldata params
    ) external nonReentrant onlySupportedAsset(asset) {
        require(amount > 0, "Amount must be greater than 0");
        require(receiverAddress != address(0), "Invalid receiver address");
        require(poolBalances[asset] >= amount, "Insufficient liquidity");

        uint256 fee = (amount * flashLoanFeePercentage) / PERCENTAGE_FACTOR;
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));

        // Transfer the loan amount to the receiver
        require(
            IERC20(asset).transfer(receiverAddress, amount),
            "Transfer failed"
        );

        // Call the receiver's executeOperation function
        require(
            IFlashLoanReceiver(receiverAddress).executeOperation(
                asset,
                amount,
                fee,
                params
            ),
            "Flash loan execution failed"
        );

        // Check that the loan + fee has been repaid
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        require(
            balanceAfter >= balanceBefore + fee,
            "Flash loan not repaid with fee"
        );

        // Update pool balance with the fee earned
        poolBalances[asset] = balanceAfter;

        emit FlashLoan(
            msg.sender,
            asset,
            amount,
            fee,
            block.timestamp
        );
    }

    /**
     * @dev Core Function 2: Provide Liquidity
     * @param asset The address of the asset to deposit
     * @param amount The amount to deposit
     */
    function provideLiquidity(address asset, uint256 amount) 
        external 
        nonReentrant 
        onlySupportedAsset(asset) 
    {
        require(amount > 0, "Amount must be greater than 0");
        
        // Transfer tokens from user to contract
        require(
            IERC20(asset).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Update balances
        poolBalances[asset] += amount;
        userDeposits[msg.sender][asset] += amount;

        emit LiquidityDeposited(
            msg.sender,
            asset,
            amount,
            block.timestamp
        );
    }

    /**
     * @dev Core Function 3: Withdraw Liquidity
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw
     */
    function withdrawLiquidity(address asset, uint256 amount) 
        external 
        nonReentrant 
        onlySupportedAsset(asset) 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(
            userDeposits[msg.sender][asset] >= amount,
            "Insufficient deposited amount"
        );
        require(
            poolBalances[asset] >= amount,
            "Insufficient pool liquidity"
        );

        // Update balances
        poolBalances[asset] -= amount;
        userDeposits[msg.sender][asset] -= amount;

        // Transfer tokens back to user
        require(
            IERC20(asset).transfer(msg.sender, amount),
            "Transfer failed"
        );

        emit LiquidityWithdrawn(
            msg.sender,
            asset,
            amount,
            block.timestamp
        );
    }

    // Admin functions
    function addSupportedAsset(address asset) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(!supportedAssets[asset], "Asset already supported");
        
        supportedAssets[asset] = true;
        assetsList.push(asset);
    }

    function removeSupportedAsset(address asset) external onlyOwner {
        require(supportedAssets[asset], "Asset not supported");
        
        supportedAssets[asset] = false;
        
        // Remove from assets list
        for (uint i = 0; i < assetsList.length; i++) {
            if (assetsList[i] == asset) {
                assetsList[i] = assetsList[assetsList.length - 1];
                assetsList.pop();
                break;
            }
        }
    }

    function setFlashLoanFee(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 100, "Fee too high"); // Max 1%
        flashLoanFeePercentage = newFeePercentage;
    }

    // View functions
    function getPoolBalance(address asset) external view returns (uint256) {
        return poolBalances[asset];
    }

    function getUserDeposit(address user, address asset) 
        external 
        view 
        returns (uint256) 
    {
        return userDeposits[user][asset];
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return assetsList;
    }

    function calculateFlashLoanFee(uint256 amount) 
        external 
        view 
        returns (uint256) 
    {
        return (amount * flashLoanFeePercentage) / PERCENTAGE_FACTOR;
    }

    function getContractInfo() external view returns (
        address contractOwner,
        uint256 feePercentage,
        uint256 totalSupportedAssets,
        address[] memory assets
    ) {
        return (
            owner(),
            flashLoanFeePercentage,
            assetsList.length,
            assetsList
        );
    }

    // Emergency function to withdraw stuck tokens (only owner)
    function emergencyWithdraw(address asset, uint256 amount) 
        external 
        onlyOwner 
    {
        require(
            IERC20(asset).transfer(owner(), amount),
            "Emergency withdraw failed"
        );
    }

    /**
     * @dev Initialize contract with common assets (called after deployment)
     * @param commonAssets Array of token addresses to add as supported assets
     */
    function initializeWithAssets(address[] calldata commonAssets) external onlyOwner {
        for (uint i = 0; i < commonAssets.length; i++) {
            if (!supportedAssets[commonAssets[i]] && commonAssets[i] != address(0)) {
                supportedAssets[commonAssets[i]] = true;
                assetsList.push(commonAssets[i]);
            }
        }
    }

    /**
     * @dev Batch add multiple supported assets
     * @param assets Array of asset addresses to support
     */
    function batchAddSupportedAssets(address[] calldata assets) external onlyOwner {
        for (uint i = 0; i < assets.length; i++) {
            if (!supportedAssets[assets[i]] && assets[i] != address(0)) {
                supportedAssets[assets[i]] = true;
                assetsList.push(assets[i]);
            }
        }
    }
}

/**
 * @title AutoDeployHelper
 * @dev Helper contract for easy deployment and setup
 */
contract AutoDeployHelper {
    event FlashLoanContractDeployed(address indexed contractAddress, address indexed owner);
    
    function deployFlashLoanContract() external returns (address) {
        FlashLoanContract newContract = new FlashLoanContract();
        
        // Transfer ownership to the caller
        newContract.transferOwnership(msg.sender);
        
        emit FlashLoanContractDeployed(address(newContract), msg.sender);
        
        return address(newContract);
    }
    
    function deployAndInitialize(address[] calldata initialAssets) external returns (address) {
        FlashLoanContract newContract = new FlashLoanContract();
        
        // Initialize with assets if provided
        if (initialAssets.length > 0) {
            newContract.initializeWithAssets(initialAssets);
        }
        
        // Transfer ownership to the caller
        newContract.transferOwnership(msg.sender);
        
        emit FlashLoanContractDeployed(address(newContract), msg.sender);
        
        return address(newContract);
    }
}
