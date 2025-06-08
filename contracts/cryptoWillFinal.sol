// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

interface IERC404 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract CryptoWill is ReentrancyGuard, Ownable, AutomationCompatibleInterface {
    
    // Events
    event BeneficiaryAdded(address indexed beneficiary, uint256 timestamp);
    event BeneficiaryRemoved(address indexed beneficiary, uint256 timestamp);
    event AssetClaimed(address indexed beneficiary, address indexed token, uint256 amount, uint8 tokenType);
    event LifeSignSent(uint256 timestamp);
    event InactivityTriggered(uint256 timestamp);
    event CharityDonation(address indexed charity, address indexed token, uint256 amount);
    event ProofOfLifeIntervalUpdated(uint256 newInterval);
    
    // Structs
    struct Beneficiary {
        address wallet;
        uint256 erc20Percentage;
        uint256 erc721Percentage; 
        uint256 erc1155Percentage;
        uint256 erc404Percentage;
        bool approved;
        bool exists;
    }
    
    struct AssetAllocation {
        address tokenAddress;
        uint8 tokenType; // 0=ERC20, 1=ERC721, 2=ERC1155, 3=ERC404
        uint256 amount;
        uint256 tokenId; // For NFTs
    }
    
    // State variables
    mapping(address => Beneficiary) public beneficiaries;
    address[] public beneficiaryList;
    mapping(address => mapping(address => uint256)) public erc20Balances;
    mapping(address => mapping(address => uint256[])) public erc721Tokens;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public erc1155Balances;
    
    uint256 public lastActivityTimestamp;
    uint256 public proofOfLifeInterval = 90 days;
    uint256 public inactivityThreshold = 365 days;
    uint256 public claimPeriod = 30 days;
    uint256 public inactivityTriggeredAt;
    bool public inactivityTriggered;
    
    // Predefined charity addresses
    address[] public charityAddresses = [
        0x750EF1D7a0b4Ab1c97B7A623D7917CcEb5ea779C, // Example charity 1
        0x10ED43C718714eb63d5aA57B78B54704E256024E, // Example charity 2
        0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984  // Example charity 3
    ];
    
    modifier onlyBeneficiary() {
        require(beneficiaries[msg.sender].exists && beneficiaries[msg.sender].approved, "Not an approved beneficiary");
        _;
    }
    
    modifier onlyAfterInactivity() {
        require(inactivityTriggered, "Inactivity not triggered");
        require(block.timestamp >= inactivityTriggeredAt + claimPeriod, "Claim period not reached");
        _;
    }
    
    constructor() {
        lastActivityTimestamp = block.timestamp;
    }
    
    // Chainlink Automation functions
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = (block.timestamp - lastActivityTimestamp) >= proofOfLifeInterval && !inactivityTriggered;
        return (upkeepNeeded, "");
    }
    
    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp - lastActivityTimestamp) >= proofOfLifeInterval && !inactivityTriggered) {
            inactivityTriggered = true;
            inactivityTriggeredAt = block.timestamp;
            emit InactivityTriggered(block.timestamp);
        }
    }
    
    // Owner functions
    function sendLifeSign() external onlyOwner {
        lastActivityTimestamp = block.timestamp;
        if (inactivityTriggered) {
            inactivityTriggered = false;
            inactivityTriggeredAt = 0;
        }
        emit LifeSignSent(block.timestamp);
    }
    
    function setProofOfLifeInterval(uint256 _interval) external onlyOwner {
        require(_interval >= 30 days && _interval <= 365 days, "Invalid interval");
        proofOfLifeInterval = _interval;
        emit ProofOfLifeIntervalUpdated(_interval);
    }
    
    function addBeneficiary(
        address _beneficiary,
        uint256 _erc20Percentage,
        uint256 _erc721Percentage,
        uint256 _erc1155Percentage,
        uint256 _erc404Percentage
    ) external onlyOwner {
        require(_beneficiary != address(0), "Invalid beneficiary address");
        require(!beneficiaries[_beneficiary].exists, "Beneficiary already exists");
        require(
            _erc20Percentage <= 100 && _erc721Percentage <= 100 && 
            _erc1155Percentage <= 100 && _erc404Percentage <= 100,
            "Percentage cannot exceed 100"
        );
        
        beneficiaries[_beneficiary] = Beneficiary({
            wallet: _beneficiary,
            erc20Percentage: _erc20Percentage,
            erc721Percentage: _erc721Percentage,
            erc1155Percentage: _erc1155Percentage,
            erc404Percentage: _erc404Percentage,
            approved: false,
            exists: true
        });
        
        beneficiaryList.push(_beneficiary);
        emit BeneficiaryAdded(_beneficiary, block.timestamp);
    }
    
    function removeBeneficiary(address _beneficiary) external onlyOwner {
        require(beneficiaries[_beneficiary].exists, "Beneficiary does not exist");
        
        // Remove from array
        for (uint i = 0; i < beneficiaryList.length; i++) {
            if (beneficiaryList[i] == _beneficiary) {
                beneficiaryList[i] = beneficiaryList[beneficiaryList.length - 1];
                beneficiaryList.pop();
                break;
            }
        }
        
        delete beneficiaries[_beneficiary];
        emit BeneficiaryRemoved(_beneficiary, block.timestamp);
    }
    
    // Beneficiary approval
    function approveBeneficiary() external {
        require(beneficiaries[msg.sender].exists, "Not a registered beneficiary");
        beneficiaries[msg.sender].approved = true;
    }
    
    // Asset management functions
    function depositERC20(address _token, uint256 _amount) external onlyOwner nonReentrant {
        require(_token != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than 0");
        
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        erc20Balances[address(this)][_token] += _amount;
        lastActivityTimestamp = block.timestamp;
    }
    
    function withdrawERC20(address _token, uint256 _amount) external onlyOwner nonReentrant {
        require(erc20Balances[address(this)][_token] >= _amount, "Insufficient balance");
        
        erc20Balances[address(this)][_token] -= _amount;
        IERC20(_token).transfer(msg.sender, _amount);
        lastActivityTimestamp = block.timestamp;
    }
    
    function depositERC721(address _token, uint256 _tokenId) external onlyOwner {
        IERC721(_token).transferFrom(msg.sender, address(this), _tokenId);
        erc721Tokens[address(this)][_token].push(_tokenId);
        lastActivityTimestamp = block.timestamp;
    }
    
    function depositERC1155(address _token, uint256 _tokenId, uint256 _amount) external onlyOwner {
        IERC1155(_token).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, "");
        erc1155Balances[address(this)][_token][_tokenId] += _amount;
        lastActivityTimestamp = block.timestamp;
    }
    
    // Claiming functions
    function claimERC20(address _token) external onlyBeneficiary onlyAfterInactivity nonReentrant {
        uint256 totalBalance = erc20Balances[address(this)][_token];
        require(totalBalance > 0, "No balance to claim");
        
        uint256 claimAmount = (totalBalance * beneficiaries[msg.sender].erc20Percentage) / 100;
        require(claimAmount > 0, "No allocation for this beneficiary");
        
        erc20Balances[address(this)][_token] -= claimAmount;
        IERC20(_token).transfer(msg.sender, claimAmount);
        
        emit AssetClaimed(msg.sender, _token, claimAmount, 0);
    }
    
    function claimERC721(address _token, uint256 _tokenId) external onlyBeneficiary onlyAfterInactivity {
        require(beneficiaries[msg.sender].erc721Percentage > 0, "No NFT allocation");
        
        // Simple allocation: first come, first served based on percentage
        IERC721(_token).transferFrom(address(this), msg.sender, _tokenId);
        
        // Remove from tracking
        uint256[] storage tokens = erc721Tokens[address(this)][_token];
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == _tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
        
        emit AssetClaimed(msg.sender, _token, 1, 1);
    }
    
    function claimERC1155(address _token, uint256 _tokenId, uint256 _amount) external onlyBeneficiary onlyAfterInactivity {
        uint256 totalBalance = erc1155Balances[address(this)][_token][_tokenId];
        require(totalBalance > 0, "No balance to claim");
        
        uint256 claimAmount = (totalBalance * beneficiaries[msg.sender].erc1155Percentage) / 100;
        require(claimAmount > 0 && claimAmount >= _amount, "Invalid claim amount");
        
        erc1155Balances[address(this)][_token][_tokenId] -= claimAmount;
        IERC1155(_token).safeTransferFrom(address(this), msg.sender, _tokenId, claimAmount, "");
        
        emit AssetClaimed(msg.sender, _token, claimAmount, 2);
    }
    
    // Charity fallback functions
    function donateUnclaimedAssets() external {
        require(inactivityTriggered, "Inactivity not triggered");
        require(block.timestamp >= inactivityTriggeredAt + claimPeriod + 30 days, "Donation period not reached");
        
        // This function would iterate through all assets and donate to charities
        // Implementation would depend on specific requirements
    }
    
    // View functions
    function getBeneficiaryCount() external view returns (uint256) {
        return beneficiaryList.length;
    }
    
    function getBeneficiary(address _beneficiary) external view returns (Beneficiary memory) {
        return beneficiaries[_beneficiary];
    }
    
    function getERC20Balance(address _token) external view returns (uint256) {
        return erc20Balances[address(this)][_token];
    }
    
    function getERC721Tokens(address _token) external view returns (uint256[] memory) {
        return erc721Tokens[address(this)][_token];
    }
    
    function getERC1155Balance(address _token, uint256 _tokenId) external view returns (uint256) {
        return erc1155Balances[address(this)][_token][_tokenId];
    }
    
    function getInactivityStatus() external view returns (bool triggered, uint256 triggeredAt, uint256 nextCheck) {
        return (inactivityTriggered, inactivityTriggeredAt, lastActivityTimestamp + proofOfLifeInterval);
    }
    
    // Required for ERC1155 tokens
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
    
    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
