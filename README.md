# CryptoWill - Smart Contract Inheritance Wallet

## Overview

CryptoWill is a comprehensive smart contract wallet application designed to prevent loss of cryptocurrency funds due to death or disability. It uses Avalanche as the primary blockchain with Chainlink services for automation and cross-chain asset detection.

## Features

- **Multi-chain Asset Management**: Support for ERC20, ERC721, ERC1155, and ERC404 tokens
- **Automated Proof of Life**: Chainlink Automation monitors wallet activity
- **Beneficiary Management**: Add, remove, and allocate inheritance percentages
- **Charity Fallback**: Donate unclaimed assets to predefined charities
- **Browser Extension Interface**: User-friendly React-based UI
- **Cross-chain Detection**: Chainlink CCIP integration for multi-chain assets

## Smart Contract Deployment

### Prerequisites

1. **Development Environment**:
   - Node.js (v16+)
   - Hardhat or Truffle
   - MetaMask wallet with AVAX for gas fees

2. **Required Dependencies**:
   ```bash
   npm install @openzeppelin/contracts @chainlink/contracts ethers hardhat
   ```

### Deployment Steps

1. **Compile the Contract**:
   ```bash
   npx hardhat compile
   ```

2. **Deploy to Avalanche C-Chain**:
   ```javascript
   // hardhat.config.js
   module.exports = {
     networks: {
       avalanche: {
         url: 'https://api.avax.network/ext/bc/C/rpc',
         chainId: 43114,
         accounts: [process.env.PRIVATE_KEY]
       }
     }
   };
   ```

3. **Deployment Script**:
   ```javascript
   // scripts/deploy.js
   async function main() {
     const CryptoWill = await ethers.getContractFactory("CryptoWill");
     const cryptoWill = await CryptoWill.deploy();
     await cryptoWill.deployed();
     console.log("CryptoWill deployed to:", cryptoWill.address);
   }
   
   main().catch((error) => {
     console.error(error);
     process.exitCode = 1;
   });
   ```

4. **Execute Deployment**:
   ```bash
   npx hardhat run scripts/deploy.js --network avalanche
   ```

### Chainlink Integration Setup

1. **Register Chainlink Automation**:
   - Visit [Chainlink Automation](https://automation.chain.link/)
   - Connect your wallet and register your contract
   - Set up upkeep for proof-of-life monitoring

2. **CCIP Configuration**:
   - Configure supported chains in the contract
   - Set up cross-chain message passing for asset detection

## Browser Extension Installation

### Development Installation

1. **Prepare Extension Files**:
   ```
   cryptowill-extension/
   ├── manifest.json
   ├── index.html
   ├── icons/
   │   ├── icon16.png
   │   ├── icon48.png
   │   └── icon128.png
   └── README.md
   ```

2. **Update Contract Address**:
   - Open `index.html`
   - Replace `CONTRACT_ADDRESS` with your deployed contract address

3. **Load Extension in Browser**:
   - Open Chrome/Firefox
   - Navigate to Extensions (chrome://extensions/)
   - Enable "Developer mode"
   - Click "Load unpacked" and select the extension folder

### Production Distribution

1. **Package Extension**:
   ```bash
   zip -r cryptowill-extension.zip cryptowill-extension/
   ```

2. **Submit to Stores**:
   - Chrome Web Store: [Chrome Developer Dashboard](https://chrome.google.com/webstore/developer/dashboard)
   - Firefox Add-ons: [Firefox Developer Hub](https://addons.mozilla.org/developers/)

## Configuration

### Contract Configuration

1. **Set Proof of Life Interval**:
   ```javascript
   await contract.setProofOfLifeInterval(90 * 24 * 60 * 60); // 90 days
   ```

2. **Add Beneficiaries**:
   ```javascript
   await contract.addBeneficiary(
     "0x742d35Cc6635C0532925a3b8D71FaC8BEE21aBe8", // beneficiary address
     50, // ERC20 percentage
     100, // ERC721 percentage
     25, // ERC1155 percentage
     0   // ERC404 percentage
   );
   ```

### Extension Configuration

1. **Network Settings**:
   - The extension automatically connects to Avalanche C-Chain
   - Supports network switching via MetaMask

2. **Asset Detection**:
   - Configured for popular tokens on supported chains
   - CCIP integration for cross-chain asset discovery

## Usage Guide

### For Wallet Owners

1. **Initial Setup**:
   - Install browser extension
   - Connect MetaMask wallet
   - Deploy or connect to existing CryptoWill contract

2. **Configure Beneficiaries**:
   - Open "Manage Beneficiaries" modal
   - Add beneficiary addresses
   - Set allocation percentages for each token type
   - Beneficiaries must approve their inclusion

3. **Maintain Proof of Life**:
   - Send regular life signs via the extension
   - Configure appropriate check intervals
   - Monitor next check dates

4. **Asset Management**:
   - Deposit assets to the contract
   - View multi-chain balances
   - Withdraw assets as needed

### For Beneficiaries

1. **Approval Process**:
   - Receive notification of beneficiary status
   - Connect wallet and approve inclusion
   - Verify allocation percentages

2. **Claiming Process**:
   - Monitor owner's activity status
   - Wait for inactivity period to be triggered
   - Submit claims after claim period begins
   - Provide proof of beneficiary status

## Security Considerations

### Smart Contract Security

1. **Access Control**:
   - Only contract owner can add/remove beneficiaries
   - Only approved beneficiaries can claim assets
   - Time-locked claiming mechanism

2. **Reentrancy Protection**:
   - All external calls protected with ReentrancyGuard
   - State changes before external interactions

3. **Input Validation**:
   - Address validation for all parameters
   - Percentage bounds checking
   - Balance verification before transfers

### Extension Security

1. **No Private Key Storage**:
   - Extension never stores private keys
   - All transactions via MetaMask integration
   - User maintains full control of keys

2. **Secure Communication**:
   - HTTPS-only connections
   - Verified contract interactions
   - Input sanitization

## Sample Charity Addresses

The contract includes predefined charity addresses for fallback donations:

```solidity
address[] public charityAddresses = [
    0x750EF1D7a0b4Ab1c97B7A623D7917CcEb5ea779C, // GiveDirectly
    0x10ED43C718714eb63d5aA57B78B54704E256024E, // Red Cross
    0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984  // UNICEF
];
```

## Troubleshooting

### Common Issues

1. **MetaMask Connection**:
   - Ensure MetaMask is installed and unlocked
   - Switch to Avalanche C-Chain network
   - Refresh extension popup

2. **Transaction Failures**:
   - Check AVAX balance for gas fees
   - Verify contract address is correct
   - Ensure sufficient token allowances

3. **Beneficiary Issues**:
   - Beneficiaries must approve inclusion
   - Check allocation percentages don't exceed 100%
   - Verify addresses are valid

### Support Resources

- **Avalanche Documentation**: https://docs.avax.network/
- **Chainlink Documentation**: https://docs.chain.link/
- **OpenZeppelin Contracts**: https://docs.openzeppelin.com/contracts/

## Gas Optimization Tips

1. **Batch Operations**:
   - Add multiple beneficiaries in single transaction
   - Use multicall for complex operations

2. **Storage Optimization**:
   - Pack struct variables efficiently
   - Use events for historical data

3. **Function Optimization**:
   - Minimize external calls
   - Cache frequently accessed values

## Legal Considerations

1. **Jurisdictional Compliance**:
   - Verify inheritance laws in your jurisdiction
   - Consider legal implications of smart contract wills
   - Consult with legal professionals

2. **Backup Documentation**:
   - Maintain off-chain documentation
   - Provide clear instructions to beneficiaries
   - Consider traditional legal backup measures

## Future Enhancements

1. **Multi-signature Support**:
   - Require multiple signatures for sensitive operations
   - Implement guardian system for additional security

2. **Advanced Asset Types**:
   - Support for more token standards
   - Integration with DeFi protocols
   - Yield-generating asset management

3. **Enhanced UI/UX**:
   - Mobile application
   - Advanced analytics dashboard
   - Notification system

## Contributing

To contribute to CryptoWill development:

1. Fork the repository
2. Create feature branches
3. Submit pull requests with tests
4. Follow coding standards and documentation requirements

## License

MIT License - see LICENSE file for details.

## Disclaimer

CryptoWill is experimental software. Users should:
- Test thoroughly on testnets
- Understand smart contract risks
- Consider legal implications
- Maintain backup access methods
- Never invest more than you can afford to lose
