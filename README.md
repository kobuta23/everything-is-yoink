# Everything Is Yoink - Superfluid Stream Management

Because every contract deserves a yoink
Everything-is-yoink is a state of the art smart contract system for the modern yoink engineer. Now with hooks! 

- Unabashedly overengineered
- Surprisingly expressive
- Beautifully crafted (by claude)

![Yoink Meme](yoink.jpeg)

## 🚀 Basic Interface

```solidity
// 1. Create the yoink
function createYoink(
   address admin,
   address yoinkAgent,
   address flowRateAgent,
   ISuperToken token,
   string memory metadataURI,
   address hook
) returns (uint256 yoinkId);

// 2. Start the stream 
function startStream(
   uint256 yoinkId,
   int96 flowRate,
   address recipient
);

// 3. Start yoinking 
function yoink(
    uint256 yoinkId,
    address newRecipient
);
```


## 🚀 Quick Start

### Prerequisites
- [Foundry](https://getfoundry.sh/) installed
- Git

### Setup
1. Clone the repository
2. Install dependencies:
   ```bash
   forge install
   ```

### Environment Variables
Copy `env.example` to `.env` and fill in your values:
```bash
cp env.example .env
```

Required environment variables:
- `PRIVATE_KEY`: Your wallet private key for deployment
- `MAINNET_RPC_URL`: Ethereum mainnet RPC URL
- `SEPOLIA_RPC_URL`: Sepolia testnet RPC URL
- `ETHERSCAN_API_KEY`: Etherscan API key for verification

## 📁 Project Structure

```
├── src/                           # Smart contracts
│   ├── YoinkMaster.sol           # Core yoink management contract
│   ├── YoinkFactory.sol          # Factory for creating yoinks with presets
│   ├── YoinkEscrowWrapper.sol    # Escrow contract for wrapper superTokens
│   ├── YoinkEscrowPure.sol       # Escrow contract for pure superTokens
│   ├── NonTransferrableNFT.sol   # NFT base contract
│   ├── hooks/                    # Hook contracts for customization
│   │   ├── IYoinkHook.sol        # Hook interface
│   │   ├── RateLimitHook.sol     # Rate limiting hook
│   │   ├── SmartFlowRateHook.sol # Intelligent flow rate modulation
│   │   ├── FeePullerHook.sol     # Fee collection from position managers
│   │   ├── AdvancedHook.sol      # Complex hook with multiple features
│   │   └── IPositionManager.sol  # Position manager interface
│   └── SuperfluidExample.sol     # Example Superfluid integration
├── test/                         # Test files
│   ├── Yoink.t.sol              # Core yoink tests
│   ├── SuperfluidTest.t.sol     # Superfluid integration tests
│   └── NonTransferrableNFT.t.sol # NFT tests
├── script/                       # Deployment scripts
│   ├── DeployFactory.s.sol      # Factory deployment
│   └── DeployYoink.s.sol        # Legacy deployment
├── lib/                         # Dependencies
├── foundry.toml                # Foundry configuration
└── env.example                 # Environment variables template
```

## 🎯 Core Concepts

### Yoink
A "yoink" is a Superfluid stream that can have its recipient changed dynamically. Think of it as a stream that can be "stolen" from one recipient and given to another.

### Hooks
Hooks are modular contracts that can intercept and modify yoink behavior. They can:
- Rate limit yoinks
- Automatically adjust flow rates
- Pull fees from external sources
- Add custom logic and restrictions

### Escrow Contracts
Escrow contracts act as treasuries for yoinks, allowing users to deposit tokens that will be streamed without taking custody.

## 🏭 Factory Presets

The `YoinkFactory` provides easy-to-use presets for common use cases:

### Rate Limited Yoink
```solidity
factory.createRateLimitedYoink(
    admin,
    yoinkAgent,
    flowRateAgent,
    token,
    metadataURI,
    treasury  // Optional: address(0) for escrow, or custom address
);
```
- Enforces 1 hour between yoinks
- Prevents spam and rapid recipient changes

### Smart Flow Rate Yoink
```solidity
factory.createSmartFlowRateYoink(
    admin,
    yoinkAgent,
    token,
    metadataURI,
    targetDuration,  // e.g., 30 days
    treasury         // Optional: address(0) for escrow, or custom address
);
```
- Automatically adjusts flow rate to run out within specified duration
- Calculates optimal flow rate based on treasury balance
- Ensures predictable stream duration

### Fee Puller Yoink
```solidity
factory.createFeePullerYoink(
    admin,
    yoinkAgent,
    token,
    metadataURI,
    positionManager,    // Fee source contract
    feeToken,           // Token to pull fees in
    minFeeThreshold,    // Minimum amount to pull
    treasury            // Optional: address(0) for escrow, or custom address
);
```
- Automatically pulls fees from position managers
- Deposits fees into escrow contract
- Funds yoinks with trading fees or other revenue

### Custom Yoink
```solidity
factory.createCustomYoink(
    admin,
    yoinkAgent,
    flowRateAgent,
    token,
    metadataURI,
    customHook,     // Your custom hook contract
    treasury        // Optional: address(0) for escrow, or custom address
);
```
- Use your own custom hook for specialized logic
- Full control over yoink behavior

## 🔧 Core Functions

### YoinkMaster
- `createYoink()` - Create a new yoink
- `yoink()` - Change stream recipient
- `startStream()` - Start a new stream
- `updateStream()` - Update flow rate for existing stream
- `stopStream()` - Stop the stream
- `setYoinkHook()` - Set custom hook
- `updateTreasury()` - Change treasury address

### Hook System
- `beforeYoink()` - Hook function called before yoink
- Rate limiting, flow rate modulation, fee pulling
- Custom logic and restrictions

## 🧪 Testing

Run all tests:
```bash
forge test
```

Run tests with verbose output:
```bash
forge test -vv
```

Run specific test:
```bash
forge test --match-test test_CreateYoink
```

Run fuzz tests:
```bash
forge test --fuzz-runs 1000
```

## 🔨 Compilation

Compile contracts:
```bash
forge build
```

## 🚀 Deployment

### Deploy Factory (Recommended)
Deploy the complete system with all presets:
```bash
forge script script/DeployFactory.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

This deploys:
- YoinkMaster
- YoinkFactory
- Escrow templates
- All preset hooks (RateLimit, SmartFlowRate, FeePuller)

### Local Development
Start local node:
```bash
anvil
```

Deploy to local network:
```bash
forge script script/DeployFactory.s.sol --rpc-url http://localhost:8545 --broadcast
```

## 📊 Gas Reports

Generate gas report:
```bash
forge test --gas-report
```

## 🔍 Contract Verification

Verify on Etherscan:
```bash
forge verify-contract <CONTRACT_ADDRESS> src/YoinkFactory.sol:YoinkFactory --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY
```

## 📚 Dependencies

- [forge-std](https://github.com/foundry-rs/forge-std): Foundry standard library
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts): Secure smart contract library
- [Superfluid Protocol](https://github.com/superfluid-finance/protocol-monorepo): Superfluid streaming protocol

## 🛠️ Useful Commands

```bash
# Format code
forge fmt

# Lint code
forge build --sizes

# Get contract size
forge build --sizes

# Run specific test with traces
forge test --match-test test_CreateYoink -vvvv

# Deploy and verify in one command
forge script script/DeployFactory.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

## 🔒 Security Features

- **Access Control**: Only authorized agents can change recipients
- **Hook System**: Modular security and logic
- **Escrow Contracts**: No custody of user funds
- **Rate Limiting**: Prevents spam and abuse
- **Treasury Management**: Flexible treasury options

## 📝 License

This project is licensed under the MIT License.
