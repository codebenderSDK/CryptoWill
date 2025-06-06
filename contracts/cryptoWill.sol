// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "@chainlink/contracts/src/v0.8/functions/FunctionsClient.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/ccip/CCIPReceiver.sol";
import "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title CryptoWill - Decentralized Multi-Chain Crypto Inheritance System
 * @dev Main contract that handles inheritance vaults with full Chainlink integration
 * @author CryptoWill Team
 */
contract CryptoWill is 
    AutomationCompatibleInterface,
    FunctionsClient,
    VRFConsumerBaseV2,
    CCIPReceiver,
    ReentrancyGuard,
    Ownable,
    Pausable
{
    // ============ STATE VARIABLES ============
    
    // Chainlink VRF
    uint64 private s_subscriptionId;
    bytes32 private s_keyHash;
    uint32 private constant CALLBACK_GAS_LIMIT = 100000;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    
    // Chainlink Functions
    bytes32 private s_donId;
    uint64 private s_functionsSubscriptionId;
    
    // CCIP
    IRouterClient private s_router;
    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(address => bool) public allowlistedSenders;
    
    // Core inheritance data structures
    struct InheritanceVault {
        address owner;
        uint256 inactivityThreshold;
        uint256 lastActivity;
        uint256 challengePeriod;
        uint256 challengeStartTime;
        bool isActive;
        bool inheritanceTriggered;
        bool challengeActive;
        address[] beneficiaries;
        uint256[] percentages;
        uint64[] preferredChains;
        address[] emergencyContacts;
        mapping(address => uint256) tokenBalances;
        address[] supportedTokens;
    }
    
    struct CrossChainAsset {
        uint64 chainSelector;
        address tokenAddress;
        uint256 amount;
        bool isPending;
    }
    
    struct InheritanceExecution {
        address vaultOwner;
        uint256 executionTime;
        bool isExecuted;
        mapping(address => bool) beneficiaryPaid;
    }
    
    // ============ MAPPINGS ============
    
    mapping(address => InheritanceVault) public vaults;
    mapping(address => bool) public vaultExists;
    mapping(address => CrossChainAsset[]) public crossChainAssets;
    mapping(address => InheritanceExecution) public executions;
    mapping(bytes32 => address) public vrfRequestToVault;
    mapping(bytes32 => address) public functionsRequestToVault;
    mapping(address => mapping(uint64 => uint256)) public crossChainActivity;
    
    // ============ EVENTS ============
    
    event VaultCreated(address indexed owner, uint256 inactivityThreshold);
    event ActivityUpdated(address indexed owner, uint256 timestamp, uint64 chainSelector);
    event InheritanceTriggered(address indexed owner, uint256 challengeStartTime);
    event ChallengePeriodStarted(address indexed owner, uint256 endTime);
    event InheritanceExecuted(address indexed owner, uint256 totalValue);
    event BeneficiaryPaid(address indexed owner, address indexed beneficiary, uint256 amount);
    event CrossChainMessageSent(address indexed owner, uint64 destinationChain, bytes32 messageId);
    event CrossChainMessageReceived(address indexed owner, uint64 sourceChain, bytes32 messageId);
    event EmergencyOverride(address indexed owner, address indexed emergencyContact);
    
    // ============ ERRORS ============
    
    error VaultNotFound();
    error VaultAlreadyExists();
    error OnlyVaultOwner();
    error OnlyEmergencyContact();
    error InheritanceNotTriggered();
    error ChallengePeriodActive();
    error InvalidBeneficiaryData();
    error InsufficientBalance();
    error TransferFailed();
    error InvalidChainSelector();
    error UnauthorizedSender();
    
    // ============ CONSTRUCTOR ============
    
    constructor(
        address _router,
        address _functionsRouter,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        bytes32 _donId
    ) 
        FunctionsClient(_functionsRouter)
        VRFConsumerBaseV2(_vrfCoordinator)
        CCIPReceiver(_router)
    {
        s_router = IRouterClient(_router);
        s_keyHash = _keyHash;
        s_subscriptionId = _subscriptionId;
        s_donId = _donId;
    }
    
    // ============ VAULT MANAGEMENT ============
    
    /**
     * @dev Creates a new inheritance vault
     * @param _inactivityThreshold Time in seconds after which inheritance can be triggered
     * @param _challengePeriod Time in seconds for challenge period
     * @param _beneficiaries Array of beneficiary addresses
     * @param _percentages Array of inheritance percentages (sum must equal 100)
     * @param _preferredChains Array of preferred chain selectors for each beneficiary
     * @param _emergencyContacts Array of emergency contact addresses
     */
    function createVault(
        uint256 _inactivityThreshold,
        uint256 _challengePeriod,
        address[] memory _beneficiaries,
        uint256[] memory _percentages,
        uint64[] memory _preferredChains,
        address[] memory _emergencyContacts
    ) external {
        if (vaultExists[msg.sender]) revert VaultAlreadyExists();
        if (_beneficiaries.length != _percentages.length || 
            _beneficiaries.length != _preferredChains.length) revert InvalidBeneficiaryData();
        
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _percentages.length; i++) {
            totalPercentage += _percentages[i];
        }
        if (totalPercentage != 100) revert InvalidBeneficiaryData();
        
        InheritanceVault storage vault = vaults[msg.sender];
        vault.owner = msg.sender;
        vault.inactivityThreshold = _inactivityThreshold;
        vault.lastActivity = block.timestamp;
        vault.challengePeriod = _challengePeriod;
        vault.isActive = true;
        vault.inheritanceTriggered = false;
        vault.challengeActive = false;
        vault.beneficiaries = _beneficiaries;
        vault.percentages = _percentages;
        vault.preferredChains = _preferredChains;
        vault.emergencyContacts = _emergencyContacts;
        
        vaultExists[msg.sender] = true;
        
        emit VaultCreated(msg.sender, _inactivityThreshold);
    }
    
    /**
     * @dev Deposits tokens into the vault
     * @param _token Token contract address (address(0) for ETH)
     * @param _amount Amount to deposit
     */
    function depositToVault(address _token, uint256 _amount) external payable nonReentrant {
        if (!vaultExists[msg.sender]) revert VaultNotFound();
        
        InheritanceVault storage vault = vaults[msg.sender];
        
        if (_token == address(0)) {
            // ETH deposit
            vault.tokenBalances[address(0)] += msg.value;
            _addSupportedToken(msg.sender, address(0));
        } else {
            // ERC20 deposit
            IERC20(_token).transferFrom(msg.sender, address(this), _amount);
            vault.tokenBalances[_token] += _amount;
            _addSupportedToken(msg.sender, _token);
        }
        
        // Update activity on deposit
        updateActivity();
    }
    
    /**
     * @dev Updates the last activity timestamp for the vault owner
     */
    function updateActivity() public {
        if (!vaultExists[msg.sender]) revert VaultNotFound();
        
        InheritanceVault storage vault = vaults[msg.sender];
        vault.lastActivity = block.timestamp;
        
        // Send cross-chain activity updates
        _broadcastActivityUpdate(msg.sender);
        
        emit ActivityUpdated(msg.sender, block.timestamp, 0);
    }
    
    // ============ CHAINLINK AUTOMATION ============
    
    /**
     * @dev Chainlink Automation checkUpkeep function
     * @param checkData Encoded data for specific checks
     * @return upkeepNeeded Whether upkeep is needed
     * @return performData Data to pass to performUpkeep
     */
    function checkUpkeep(bytes calldata checkData) 
        external 
        view 
        override 
        returns (bool upkeepNeeded, bytes memory performData) 
    {
        address vaultOwner = abi.decode(checkData, (address));
        
        if (!vaultExists[vaultOwner]) {
            return (false, "");
        }
        
        InheritanceVault storage vault = vaults[vaultOwner];
        
        // Check if inheritance should be triggered
        if (!vault.inheritanceTriggered && 
            vault.isActive && 
            block.timestamp >= vault.lastActivity + vault.inactivityThreshold) {
            upkeepNeeded = true;
            performData = abi.encode(vaultOwner, "trigger");
            return (upkeepNeeded, performData);
        }
        
        // Check if challenge period has ended
        if (vault.challengeActive && 
            block.timestamp >= vault.challengeStartTime + vault.challengePeriod) {
            upkeepNeeded = true;
            performData = abi.encode(vaultOwner, "execute");
            return (upkeepNeeded, performData);
        }
        
        return (false, "");
    }
    
    /**
     * @dev Chainlink Automation performUpkeep function
     * @param performData Data from checkUpkeep
     */
    function performUpkeep(bytes calldata performData) external override {
        (address vaultOwner, string memory action) = abi.decode(performData, (address, string));
        
        if (keccak256(bytes(action)) == keccak256(bytes("trigger"))) {
            _triggerInheritance(vaultOwner);
        } else if (keccak256(bytes(action)) == keccak256(bytes("execute"))) {
            _executeInheritance(vaultOwner);
        }
    }
    
    // ============ CHAINLINK FUNCTIONS ============
    
    /**
     * @dev Requests off-chain verification of user activity
     * @param _vaultOwner Address of vault owner to verify
     */
    function requestActivityVerification(address _vaultOwner) external {
        if (!vaultExists[_vaultOwner]) revert VaultNotFound();
        
        // JavaScript source code for off-chain verification
        string memory source = 
            "const walletAddress = args[0];"
            "const apiResponse = await Functions.makeHttpRequest({"
            "  url: `https://api.etherscan.io/api?module=account&action=txlist&address=${walletAddress}&page=1&offset=1&sort=desc`"
            "});"
            "if (apiResponse.error) {"
            "  throw Error('Request failed');"
            "}"
            "const lastTx = apiResponse.data.result[0];"
            "return Functions.encodeUint256(parseInt(lastTx.timeStamp));";
        
        string[] memory args = new string[](1);
        args[0] = _addressToString(_vaultOwner);
        
        bytes32 requestId = _sendRequest(source, args);
        functionsRequestToVault[requestId] = _vaultOwner;
    }
    
    /**
     * @dev Handles the response from Chainlink Functions
     * @param requestId The request ID
     * @param response The response data
     * @param err Any error that occurred
     */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) 
        internal 
        override 
    {
        address vaultOwner = functionsRequestToVault[requestId];
        if (vaultOwner == address(0)) return;
        
        if (err.length > 0) {
            // Handle error
            return;
        }
        
        uint256 lastActivityTimestamp = abi.decode(response, (uint256));
        
        // Update activity if recent activity found
        if (lastActivityTimestamp > vaults[vaultOwner].lastActivity) {
            vaults[vaultOwner].lastActivity = lastActivityTimestamp;
            emit ActivityUpdated(vaultOwner, lastActivityTimestamp, 0);
        }
    }
    
    // ============ CHAINLINK VRF ============
    
    /**
     * @dev Requests randomness for inheritance delay
     * @param _vaultOwner Vault owner address
     */
    function requestInheritanceDelay(address _vaultOwner) external {
        bytes32 requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );
        
        vrfRequestToVault[requestId] = _vaultOwner;
    }
    
    /**
     * @dev Handles VRF response
     * @param requestId The request ID
     * @param randomWords Array of random numbers
     */
    function fulfillRandomWords(bytes32 requestId, uint256[] memory randomWords) 
        internal 
        override 
    {
        address vaultOwner = vrfRequestToVault[requestId];
        if (vaultOwner == address(0)) return;
        
        // Add random delay (0-24 hours) to challenge period
        uint256 randomDelay = (randomWords[0] % 86400); // 0-24 hours in seconds
        vaults[vaultOwner].challengeStartTime += randomDelay;
    }
    
    // ============ CCIP CROSS-CHAIN ============
    
    /**
     * @dev Sends cross-chain message to update activity
     * @param _destinationChainSelector Target chain selector
     * @param _vaultOwner Vault owner address
     * @param _timestamp Activity timestamp
     */
    function sendCrossChainActivity(
        uint64 _destinationChainSelector,
        address _vaultOwner,
        uint256 _timestamp
    ) external {
        if (!allowlistedDestinationChains[_destinationChainSelector]) revert InvalidChainSelector();
        
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: abi.encode(_vaultOwner, _timestamp),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000})),
            feeToken: address(0) // Pay in native token
        });
        
        uint256 fees = s_router.getFee(_destinationChainSelector, evm2AnyMessage);
        
        bytes32 messageId = s_router.ccipSend{value: fees}(
            _destinationChainSelector,
            evm2AnyMessage
        );
        
        emit CrossChainMessageSent(_vaultOwner, _destinationChainSelector, messageId);
    }
    
    /**
     * @dev Handles incoming CCIP messages
     * @param any2EvmMessage The CCIP message
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) 
        internal 
        override 
    {
        if (!allowlistedSenders[abi.decode(any2EvmMessage.sender, (address))]) {
            revert UnauthorizedSender();
        }
        
        (address vaultOwner, uint256 timestamp) = abi.decode(any2EvmMessage.data, (address, uint256));
        
        if (vaultExists[vaultOwner] && timestamp > vaults[vaultOwner].lastActivity) {
            vaults[vaultOwner].lastActivity = timestamp;
            crossChainActivity[vaultOwner][any2EvmMessage.sourceChainSelector] = timestamp;
            
            emit CrossChainMessageReceived(vaultOwner, any2EvmMessage.sourceChainSelector, any2EvmMessage.messageId);
            emit ActivityUpdated(vaultOwner, timestamp, any2EvmMessage.sourceChainSelector);
        }
    }
    
    // ============ INHERITANCE EXECUTION ============
    
    /**
     * @dev Triggers the inheritance process
     * @param _vaultOwner Vault owner address
     */
    function _triggerInheritance(address _vaultOwner) internal {
        if (!vaultExists[_vaultOwner]) revert VaultNotFound();
        
        InheritanceVault storage vault = vaults[_vaultOwner];
        
        if (block.timestamp < vault.lastActivity + vault.inactivityThreshold) {
            return; // Not ready for inheritance
        }
        
        vault.inheritanceTriggered = true;
        vault.challengeActive = true;
        vault.challengeStartTime = block.timestamp;
        
        // Request random delay for additional security
        requestInheritanceDelay(_vaultOwner);
        
        emit InheritanceTriggered(_vaultOwner, vault.challengeStartTime);
        emit ChallengePeriodStarted(_vaultOwner, vault.challengeStartTime + vault.challengePeriod);
    }
    
    /**
     * @dev Executes the inheritance distribution
     * @param _vaultOwner Vault owner address
     */
    function _executeInheritance(address _vaultOwner) internal {
        if (!vaultExists[_vaultOwner]) revert VaultNotFound();
        
        InheritanceVault storage vault = vaults[_vaultOwner];
        
        if (!vault.inheritanceTriggered || !vault.challengeActive) revert InheritanceNotTriggered();
        if (block.timestamp < vault.challengeStartTime + vault.challengePeriod) revert ChallengePeriodActive();
        
        vault.challengeActive = false;
        vault.isActive = false;
        
        InheritanceExecution storage execution = executions[_vaultOwner];
        execution.vaultOwner = _vaultOwner;
        execution.executionTime = block.timestamp;
        execution.isExecuted = true;
        
        uint256 totalValue = 0;
        
        // Distribute assets to beneficiaries
        for (uint256 i = 0; i < vault.beneficiaries.length; i++) {
            address beneficiary = vault.beneficiaries[i];
            uint256 percentage = vault.percentages[i];
            uint64 preferredChain = vault.preferredChains[i];
            
            for (uint256 j = 0; j < vault.supportedTokens.length; j++) {
                address token = vault.supportedTokens[j];
                uint256 tokenBalance = vault.tokenBalances[token];
                uint256 beneficiaryAmount = (tokenBalance * percentage) / 100;
                
                if (beneficiaryAmount > 0) {
                    if (preferredChain != 0 && preferredChain != block.chainid) {
                        // Cross-chain transfer via CCIP
                        _sendCrossChainAsset(beneficiary, token, beneficiaryAmount, preferredChain);
                    } else {
                        // Local transfer
                        _transferAsset(beneficiary, token, beneficiaryAmount);
                    }
                    
                    totalValue += beneficiaryAmount;
                }
            }
            
            execution.beneficiaryPaid[beneficiary] = true;
            emit BeneficiaryPaid(_vaultOwner, beneficiary, totalValue);
        }
        
        emit InheritanceExecuted(_vaultOwner, totalValue);
    }
    
    /**
     * @dev Transfers assets to beneficiary
     * @param _beneficiary Beneficiary address
     * @param _token Token address (address(0) for ETH)
     * @param _amount Amount to transfer
     */
    function _transferAsset(address _beneficiary, address _token, uint256 _amount) internal {
        if (_token == address(0)) {
            // Transfer ETH
            (bool success,) = _beneficiary.call{value: _amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Transfer ERC20
            bool success = IERC20(_token).transfer(_beneficiary, _amount);
            if (!success) revert TransferFailed();
        }
    }
    
    /**
     * @dev Sends assets cross-chain via CCIP
     * @param _beneficiary Beneficiary address
     * @param _token Token address
     * @param _amount Amount to send
     * @param _destinationChain Target chain selector
     */
    function _sendCrossChainAsset(
        address _beneficiary,
        address _token,
        uint256 _amount,
        uint64 _destinationChain
    ) internal {
        if (!allowlistedDestinationChains[_destinationChain]) revert InvalidChainSelector();
        
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_beneficiary),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000})),
            feeToken: address(0)
        });
        
        uint256 fees = s_router.getFee(_destinationChain, evm2AnyMessage);
        
        // Approve token for CCIP
        IERC20(_token).approve(address(s_router), _amount);
        
        bytes32 messageId = s_router.ccipSend{value: fees}(
            _destinationChain,
            evm2AnyMessage
        );
        
        emit CrossChainMessageSent(_beneficiary, _destinationChain, messageId);
    }
    
    // ============ EMERGENCY FUNCTIONS ============
    
    /**
     * @dev Emergency override by vault owner
     */
    function emergencyOverride() external {
        if (!vaultExists[msg.sender]) revert VaultNotFound();
        
        InheritanceVault storage vault = vaults[msg.sender];
        vault.inheritanceTriggered = false;
        vault.challengeActive = false;
        vault.lastActivity = block.timestamp;
        
        emit EmergencyOverride(msg.sender, msg.sender);
    }
    
    /**
     * @dev Emergency override by emergency contact
     * @param _vaultOwner Vault owner address
     */
    function emergencyContactOverride(address _vaultOwner) external {
        if (!vaultExists[_vaultOwner]) revert VaultNotFound();
        
        InheritanceVault storage vault = vaults[_vaultOwner];
        
        bool isEmergencyContact = false;
        for (uint256 i = 0; i < vault.emergencyContacts.length; i++) {
            if (vault.emergencyContacts[i] == msg.sender) {
                isEmergencyContact = true;
                break;
            }
        }
        
        if (!isEmergencyContact) revert OnlyEmergencyContact();
        
        vault.inheritanceTriggered = false;
        vault.challengeActive = false;
        vault.lastActivity = block.timestamp;
        
        emit EmergencyOverride(_vaultOwner, msg.sender);
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Allows specific destination chains for CCIP
     * @param _destinationChainSelector Chain selector to allow
     * @param _allowed Whether to allow this chain
     */
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool _allowed) 
        external 
        onlyOwner 
    {
        allowlistedDestinationChains[_destinationChainSelector] = _allowed;
    }
    
    /**
     * @dev Allows specific senders for CCIP
     * @param _sender Sender address to allow
     * @param _allowed Whether to allow this sender
     */
    function allowlistSender(address _sender, bool _allowed) external onlyOwner {
        allowlistedSenders[_sender] = _allowed;
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Gets vault information
     * @param _owner Vault owner address
     * @return Vault details
     */
    function getVault(address _owner) external view returns (
        address owner,
        uint256 inactivityThreshold,
        uint256 lastActivity,
        uint256 challengePeriod,
        bool isActive,
        bool inheritanceTriggered,
        bool challengeActive,
        address[] memory beneficiaries,
        uint256[] memory percentages
    ) {
        InheritanceVault storage vault = vaults[_owner];
        return (
            vault.owner,
            vault.inactivityThreshold,
            vault.lastActivity,
            vault.challengePeriod,
            vault.isActive,
            vault.inheritanceTriggered,
            vault.challengeActive,
            vault.beneficiaries,
            vault.percentages
        );
    }
    
    /**
     * @dev Gets token balance in vault
     * @param _owner Vault owner
     * @param _token Token address
     * @return Token balance
     */
    function getVaultTokenBalance(address _owner, address _token) external view returns (uint256) {
        return vaults[_owner].tokenBalances[_token];
    }
    
    // ============ INTERNAL HELPER FUNCTIONS ============
    
    function _addSupportedToken(address _owner, address _token) internal {
        InheritanceVault storage vault = vaults[_owner];
        for (uint256 i = 0; i < vault.supportedTokens.length; i++) {
            if (vault.supportedTokens[i] == _token) {
                return; // Token already supported
            }
        }
        vault.supportedTokens.push(_token);
    }
    
    function _broadcastActivityUpdate(address _vaultOwner) internal {
        // Broadcast to all allowed destination chains
        // This is a simplified version - in production, you'd iterate through allowed chains
        // and send updates where necessary
    }
    
    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
    
    // ============ RECEIVE FUNCTION ============
    
    receive() external payable {
        // Allow contract to receive ETH for CCIP fees and vault deposits
    }
}
