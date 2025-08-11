# Cross-Chain Arbitrage Hook

[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Uniswap V4](https://img.shields.io/badge/Uniswap-V4%20Hook-FF007A.svg)](https://github.com/Uniswap/v4-core)
[![Across Protocol](https://img.shields.io/badge/Across-V4%20Integration-6C5CE7.svg)](https://across.to/)
[![UHI Extension](https://img.shields.io/badge/UHI-Extension-00D4FF.svg)](https://github.com/uniswap-hook-incubator)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

A Uniswap v4 Hook that extends the UHI arbitrage framework with cross-chain MEV capture capabilities using Across Protocol V4. This hook intelligently detects arbitrage opportunities across multiple chains and executes profitable trades by bridging assets via Across Protocol's intent-based infrastructure.

**Sponsor:** Across Protocol (VIP)  
**Prize Eligibility:** ✅ Builds on existing UHI codebase + adds cross-chain features  
**UHI Extension:** Expands traditional arbitrage hooks with multi-chain MEV extraction

## Problem Statement

Current MEV and arbitrage opportunities are limited to single chains, missing significant value extraction possibilities:

1. **Fragmented Liquidity**: Price discrepancies exist across chains but are impossible to capture atomically
2. **Manual Cross-Chain Trading**: Users must manually bridge assets and execute trades separately
3. **MEV Leakage**: Arbitrage bots are limited to single-chain opportunities, leaving cross-chain alpha uncaptured
4. **High Latency**: Traditional bridges are too slow for profitable arbitrage execution
5. **Complex Infrastructure**: Building cross-chain arbitrage systems requires extensive bridge integrations

## Solution Architecture

### Core Innovation: Intent-Based Cross-Chain Arbitrage

This hook leverages Across V4's intent system to create the first automated cross-chain arbitrage execution layer directly embedded in Uniswap v4 swaps.

### Key Components

#### 1. Multi-Chain Price Oracle Integration
- **Real-time Price Feeds**: Chainlink price oracles across all supported chains
- **Liquidity Analysis**: Deep liquidity assessment for arbitrage feasibility
- **Gas Cost Modeling**: Accurate cross-chain execution cost prediction
- **Profitability Threshold**: Dynamic minimum profit requirements based on market conditions

#### 2. Across V4 Integration Layer
- **Intent Creation**: Converts arbitrage opportunities into Across intents
- **ZK-Proof Settlement**: Leverages Across V4's zero-knowledge proof system
- **Fast Execution**: Sub-minute cross-chain arbitrage completion
- **Universal Chain Support**: Works across all Across V4 supported chains

#### 3. UHI-Extended Arbitrage Logic
- **beforeSwap Hook**: Intercepts swaps to analyze cross-chain opportunities
- **MEV Protection**: Front-running protection via private mempool integration
- **Dynamic Routing**: Intelligent selection of optimal execution chains
- **Profit Sharing**: Configurable fee sharing with LPs and protocol

### Technical Flow

```mermaid
graph TD
    A[User Initiates Swap] --> B[beforeSwap Hook Triggered]
    B --> C[Multi-Chain Price Analysis]
    C --> D{Profitable Arbitrage Detected?}
    
    D -->|No| E[Execute Standard Swap]
    D -->|Yes| F[Calculate Optimal Route]
    
    F --> G[Create Across Intent]
    G --> H[Bridge Asset to Target Chain]
    H --> I[Execute Arbitrage Trade]
    I --> J[Bridge Profits Back]
    J --> K[Distribute Profits]
    
    E --> L[Complete Transaction]
    K --> L
    
    style A fill:#e1f5fe
    style K fill:#c8e6c9
    style L fill:#c8e6c9
```

## Architecture Deep Dive

### Hook Structure
```solidity
contract CrossChainArbitrageHook is BaseHook {
    using PriceOracle for address[];
    using AcrossIntegration for ArbitrageRoute;
    using ProfitCalculator for ArbitrageOpportunity;

    struct ArbitrageOpportunity {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 expectedProfitBPS;
        uint256 originChainId;
        uint256 targetChainId;
        bytes32 routeHash;
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        ArbitrageOpportunity memory opportunity = _analyzeArbitrageOpportunity(
            key, 
            params
        );
        
        if (_isProfitable(opportunity)) {
            return _executeCrossChainArbitrage(sender, opportunity);
        }
        
        return BaseHook.beforeSwap.selector;
    }
}
```

### Cross-Chain Price Discovery
```solidity
library CrossChainPriceOracle {
    struct ChainPriceData {
        uint256 chainId;
        uint256 price;
        uint256 liquidity;
        uint256 gasEstimate;
        uint256 timestamp;
    }
    
    function getBestArbitrageRoute(
        address tokenA,
        address tokenB,
        uint256 amount
    ) external view returns (ArbitrageRoute memory) {
        ChainPriceData[] memory prices = _fetchMultiChainPrices(tokenA, tokenB);
        return _calculateOptimalRoute(prices, amount);
    }
}
```

### Across Protocol Integration
```solidity
library AcrossIntegration {
    function executeArbitrage(
        ArbitrageOpportunity memory opportunity
    ) external returns (bytes32 intentId) {
        // Create cross-chain intent
        intentId = IAcrossProtocol(ACROSS_SPOKE_POOL).depositV3(
            opportunity.tokenIn,
            opportunity.amountIn,
            opportunity.targetChainId,
            address(this),
            _buildArbitrageCalldata(opportunity)
        );
        
        emit ArbitrageIntentCreated(intentId, opportunity);
    }
}
```

## Supported Chains & Tokens

### Initial Chain Support
- **Ethereum** - High liquidity, expensive gas
- **Arbitrum** - Moderate gas, active DeFi ecosystem  
- **Base** - Low gas, growing liquidity
- **Polygon** - Very low gas, established protocols
- **Optimism** - Moderate gas, strong ecosystem

### Target Assets
- **ETH/WETH** - Highest volume, most opportunities
- **USDC** - Stable arbitrage with minimal price risk
- **USDT** - High volume stablecoin arbitrage
- **WBTC** - Cross-chain Bitcoin arbitrage
- **Major DeFi Tokens** - UNI, AAVE, CRV, etc.

## Key Features

### 1. Automated Opportunity Detection
- **Real-time Monitoring**: Continuous price surveillance across chains
- **Minimum Profit Thresholds**: Configurable profitability requirements  
- **Risk Assessment**: Automated evaluation of execution risk vs reward
- **Market Impact Analysis**: Slippage and liquidity depth calculations

### 2. Intent-Based Execution
- **Across V4 Integration**: Leverages fastest cross-chain bridge
- **ZK-Proof Security**: Enhanced security through zero-knowledge proofs
- **Optimistic Fulfillment**: Sub-minute execution times
- **Universal Settlement**: Single system for all supported chains

### 3. MEV Protection & Capture
- **Private Mempools**: Protection from front-running
- **Profit Optimization**: Maximum value extraction from price discrepancies
- **Fair Distribution**: Configurable profit sharing with stakeholders
- **Anti-Sandwich Protection**: MEV protection for underlying swaps

### 4. UHI Framework Extension
- **Modular Design**: Builds on proven UHI architecture patterns
- **Gas Optimization**: Inherits UHI gas efficiency techniques
- **Composability**: Works with other UHI modules and hooks
- **Battle-Tested Security**: Extends verified UHI security models

## Business Model & Value Proposition

### Revenue Streams
1. **Arbitrage Profit Sharing**: 30-50% of captured MEV
2. **Bridge Fee Rebates**: Revenue sharing with Across Protocol
3. **Premium Features**: Advanced routing for institutional users
4. **API Licensing**: Cross-chain arbitrage data and signals

### Competitive Advantages
- **First Mover**: First cross-chain arbitrage hook on Uniswap v4
- **Speed**: Fastest execution via Across V4 intent system
- **Integration**: Native Uniswap integration vs external solutions
- **Scalability**: Automatic expansion to new chains via Across

### Market Opportunity
- **Cross-Chain MEV**: $50M+ annual opportunity (conservative estimate)
- **Institutional Demand**: Hedge funds seeking systematic alpha
- **Protocol Integration**: Other DEXs licensing the technology
- **Chain Expansion**: Revenue scales with new chain additions

## Technical Implementation

### Core Hook Functions

```solidity
function beforeSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    bytes calldata hookData
) external override returns (bytes4) {
    // 1. Analyze cross-chain arbitrage opportunity
    ArbitrageOpportunity memory opportunity = _scanCrossChainPrices(key, params);
    
    // 2. Check profitability threshold
    if (opportunity.expectedProfitBPS < minProfitBPS) {
        return BaseHook.beforeSwap.selector;
    }
    
    // 3. Execute cross-chain arbitrage
    _initiateCrossChainTrade(sender, opportunity);
    
    // 4. Return modified swap parameters or skip local swap
    return _shouldSkipLocalSwap(opportunity) ? 
        this.beforeSwap.selector : 
        BaseHook.beforeSwap.selector;
}
```

### Cross-Chain Price Analysis
```solidity
function _scanCrossChainPrices(
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params
) internal view returns (ArbitrageOpportunity memory) {
    address tokenIn = Currency.unwrap(key.currency0);
    address tokenOut = Currency.unwrap(key.currency1);
    uint256 amountIn = params.amountSpecified;
    
    // Get current local price
    uint256 localPrice = _getCurrentPrice(key);
    
    // Scan all supported chains for better prices
    uint256 bestPrice = localPrice;
    uint256 bestChainId = block.chainid;
    
    for (uint256 i = 0; i < supportedChains.length; i++) {
        uint256 chainId = supportedChains[i];
        if (chainId == block.chainid) continue;
        
        uint256 remotePrice = priceOracle.getPrice(tokenIn, tokenOut, chainId);
        uint256 totalCost = _calculateExecutionCost(chainId, amountIn);
        
        if (_isProfitable(localPrice, remotePrice, totalCost)) {
            bestPrice = remotePrice;
            bestChainId = chainId;
        }
    }
    
    return ArbitrageOpportunity({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amountIn,
        originChainId: block.chainid,
        targetChainId: bestChainId,
        expectedProfitBPS: _calculateProfitBPS(localPrice, bestPrice),
        routeHash: keccak256(abi.encode(tokenIn, tokenOut, bestChainId))
    });
}
```

### Across Protocol Integration
```solidity
function _initiateCrossChainTrade(
    address user,
    ArbitrageOpportunity memory opportunity
) internal {
    // Build calldata for destination chain execution
    bytes memory arbitrageCalldata = abi.encodeWithSelector(
        this.executeArbitrageOnDestination.selector,
        opportunity,
        user
    );
    
    // Create Across intent
    bytes32 intentId = IAcrossSpokePool(ACROSS_SPOKE_POOL).depositV3(
        opportunity.tokenIn,
        opportunity.amountIn,
        opportunity.targetChainId,
        address(this), // recipient
        arbitrageCalldata
    );
    
    // Store intent for tracking
    pendingArbitrages[intentId] = PendingArbitrage({
        user: user,
        opportunity: opportunity,
        timestamp: block.timestamp,
        status: ArbitrageStatus.PENDING
    });
    
    emit CrossChainArbitrageInitiated(intentId, user, opportunity);
}
```

### Destination Chain Execution
```solidity
function executeArbitrageOnDestination(
    ArbitrageOpportunity memory opportunity,
    address originalUser
) external {
    require(msg.sender == ACROSS_SPOKE_POOL, "Only Across can call");
    
    // Execute the arbitrage trade on destination chain
    uint256 amountOut = _executeSwapOnDestination(
        opportunity.tokenIn,
        opportunity.tokenOut,
        opportunity.amountIn
    );
    
    // Calculate profit
    uint256 profit = amountOut > opportunity.amountIn ? 
        amountOut - opportunity.amountIn : 0;
    
    if (profit > 0) {
        // Distribute profits
        uint256 userShare = profit * USER_PROFIT_SHARE_BPS / 10000;
        uint256 protocolFee = profit - userShare;
        
        // Bridge profits back to original chain
        _bridgeProfitsBack(
            opportunity.originChainId,
            originalUser,
            userShare,
            protocolFee
        );
    }
    
    emit ArbitrageExecuted(
        keccak256(abi.encode(opportunity)),
        profit,
        amountOut
    );
}
```

## Risk Management

### Technical Risks
- **Bridge Failure**: Handled via Across's proven security model and insurance
- **Price Slippage**: Real-time price monitoring with slippage protection
- **Gas Price Volatility**: Dynamic gas price updates with safety margins
- **Chain Congestion**: Automatic chain selection based on network conditions

### Economic Risks
- **Arbitrage Competition**: Mitigated by speed advantage and private execution
- **Impermanent Loss**: Not applicable as positions are not held long-term
- **Market Volatility**: Protected by minimum profit thresholds and quick execution
- **MEV Extraction**: Risk of being front-run, mitigated by private mempools

### Operational Risks
- **Oracle Failures**: Multiple price feed sources with fallback mechanisms
- **Smart Contract Bugs**: Comprehensive testing and audit program
- **Liquidity Fragmentation**: Continuous monitoring of cross-chain liquidity
- **Regulatory Changes**: Flexible architecture to adapt to new requirements

## Performance Metrics

### Technical KPIs
- **Execution Speed**: Target <90 seconds for cross-chain arbitrage
- **Success Rate**: >98% successful arbitrage executions
- **Price Accuracy**: ±0.1% deviation from expected prices
- **Gas Efficiency**: <5% gas overhead vs standard swaps

### Business KPIs
- **Profit Capture**: Target 15-40% annual return on deployed capital
- **Volume Growth**: Monthly arbitrage volume growth rate
- **Market Share**: Percentage of cross-chain MEV captured
- **Integration Partners**: Number of protocols adopting the hook

### User Experience KPIs
- **Transaction Success Rate**: >99.5% successful user transactions
- **Average Profit per Transaction**: Dollar value of user benefit
- **User Retention**: Repeat usage by arbitrage participants
- **Gas Savings**: Comparison vs manual cross-chain trading

## Development Roadmap

### Phase 1: Core Implementation (4-6 weeks)
- [ ] UHI framework extension and hook architecture
- [ ] Across Protocol V4 integration
- [ ] Multi-chain price oracle implementation
- [ ] Basic arbitrage detection algorithm
- [ ] Local testing and simulation framework

### Phase 2: Advanced Features (4-6 weeks)
- [ ] MEV protection mechanisms
- [ ] Advanced profit optimization algorithms
- [ ] Gas cost prediction and optimization
- [ ] Private mempool integration
- [ ] Comprehensive testing across all supported chains

### Phase 3: Production Optimization (3-4 weeks)
- [ ] Security audit and bug fixes
- [ ] Gas optimization and performance tuning
- [ ] Monitoring and alerting systems
- [ ] Documentation and integration guides
- [ ] Mainnet deployment preparation

### Phase 4: Ecosystem Integration (4-6 weeks)
- [ ] Additional chain support
- [ ] Institutional API development
- [ ] Partnership integrations
- [ ] Analytics dashboard
- [ ] Governance token considerations

## Competitive Analysis

### vs. Traditional Arbitrage Bots
- **Speed**: 10x faster execution via Across intents vs manual bridging
- **Integration**: Native Uniswap integration vs external systems
- **Capital Efficiency**: No need to maintain balances on multiple chains
- **User Access**: Retail users can benefit from institutional-grade arbitrage

### vs. Other Cross-Chain DEXs
- **Embedded Execution**: Built into Uniswap swaps vs separate applications
- **MEV Capture**: Systematic profit extraction vs opportunistic trading
- **Intent-Based**: Advanced execution model vs traditional bridge-and-swap
- **UHI Foundation**: Built on proven hook architecture vs custom solutions

### vs. Bridge Aggregators
- **Purpose-Built**: Designed specifically for arbitrage vs general bridging
- **Profit Optimization**: Advanced algorithms vs basic route selection
- **Automatic Execution**: No user intervention required
- **Value Capture**: Profit sharing vs simple bridge fee structures

## Project Structure

```
cross-chain-arbitrage-hook/
├── contracts/                               # Smart contract layer
│   ├── src/
│   │   ├── hooks/
│   │   │   ├── CrossChainArbitrageHook.sol      # Main hook contract
│   │   │   └── interfaces/
│   │   │       ├── IArbitrageHook.sol           # Hook interface
│   │   │       └── IAcrossIntegration.sol       # Across integration
│   │   │
│   │   ├── libraries/
│   │   │   ├── PriceOracle.sol                  # Multi-chain price feeds
│   │   │   ├── AcrossIntegration.sol            # Across V4 integration
│   │   │   ├── ProfitCalculator.sol             # Arbitrage math
│   │   │   ├── GasEstimator.sol                 # Cross-chain gas costs
│   │   │   └── MEVProtection.sol                # Anti-MEV mechanisms
│   │   │
│   │   ├── managers/
│   │   │   ├── ArbitrageManager.sol             # Core arbitrage logic
│   │   │   ├── ChainManager.sol                 # Multi-chain coordination
│   │   │   └── ProfitDistributor.sol            # Profit sharing logic
│   │   │
│   │   └── utils/
│   │       ├── ChainConstants.sol               # Chain-specific constants
│   │       ├── Errors.sol                       # Custom errors
│   │       └── Events.sol                       # Event definitions
│   │
│   ├── test/
│   │   ├── unit/
│   │   │   ├── CrossChainArbitrageHook.t.sol    # Hook unit tests
│   │   │   ├── PriceOracle.t.sol                # Oracle tests
│   │   │   └── ProfitCalculator.t.sol           # Math library tests
│   │   │
│   │   ├── integration/
│   │   │   ├── E2E.t.sol                        # End-to-end tests
│   │   │   ├── AcrossIntegration.t.sol          # Across integration tests
│   │   │   └── MultiChainArbitrage.t.sol        # Cross-chain scenarios
│   │   │
│   │   └── fork/
│   │       ├── MainnetFork.t.sol                # Ethereum fork tests
│   │       ├── ArbitrumFork.t.sol               # Arbitrum fork tests
│   │       └── BaseFork.t.sol                   # Base fork tests
│   │
│   ├── script/
│   │   ├── Deploy.s.sol                         # Deployment script
│   │   ├── ConfigureChains.s.sol                # Multi-chain setup
│   │   └── SetupOracles.s.sol                   # Oracle configuration
│   │
│   ├── foundry.toml                             # Foundry configuration
│   ├── remappings.txt                           # Import remappings
│   └── .env.example                             # Contract environment template
│
├── frontend/                                # React frontend application
│   ├── src/
│   │   ├── components/
│   │   │   ├── ui/
│   │   │   │   ├── Button.tsx                   # Reusable button component
│   │   │   │   ├── Card.tsx                     # Card container
│   │   │   │   ├── Input.tsx                    # Form input
│   │   │   │   ├── Modal.tsx                    # Modal dialogs
│   │   │   │   ├── Badge.tsx                    # Status badges
│   │   │   │   ├── Progress.tsx                 # Progress indicators
│   │   │   │   └── Toast.tsx                    # Notification toasts
│   │   │   │
│   │   │   ├── arbitrage/
│   │   │   │   ├── ArbitrageInterface.tsx       # Main arbitrage UI
│   │   │   │   ├── OpportunityCard.tsx          # Arbitrage opportunity display
│   │   │   │   ├── ProfitCalculator.tsx         # Real-time profit calculation
│   │   │   │   ├── ChainSelector.tsx            # Multi-chain selection
│   │   │   │   ├── TokenSelector.tsx            # Token pair selection
│   │   │   │   └── ExecutionStatus.tsx          # Transaction status tracking
│   │   │   │
│   │   │   ├── analytics/
│   │   │   │   ├── Dashboard.tsx                # Analytics dashboard
│   │   │   │   ├── PriceChart.tsx               # Multi-chain price charts
│   │   │   │   ├── ProfitHistory.tsx            # Historical profit tracking
│   │   │   │   ├── VolumeMetrics.tsx            # Volume analytics
│   │   │   │   └── PerformanceStats.tsx         # Performance metrics
│   │   │   │
│   │   │   ├── wallet/
│   │   │   │   ├── WalletConnect.tsx            # Wallet connection
│   │   │   │   ├── ChainSwitch.tsx              # Network switching
│   │   │   │   ├── BalanceDisplay.tsx           # Multi-chain balances
│   │   │   │   └── TransactionHistory.tsx       # Transaction history
│   │   │   │
│   │   │   └── layout/
│   │   │       ├── Header.tsx                   # App header
│   │   │       ├── Navigation.tsx               # Navigation menu
│   │   │       ├── Footer.tsx                   # App footer
│   │   │       └── Layout.tsx                   # Main layout wrapper
│   │   │
│   │   ├── hooks/
│   │   │   ├── useAcrossSDK.ts                  # Across V4 SDK integration
│   │   │   ├── useArbitrage.ts                  # Arbitrage logic hook
│   │   │   ├── usePriceFeeds.ts                 # Multi-chain price data
│   │   │   ├── useWallet.ts                     # Wallet connection hook
│   │   │   ├── useChainData.ts                  # Chain-specific data
│   │   │   ├── useGasEstimation.ts              # Gas price estimates
│   │   │   └── useTransactionStatus.ts          # Transaction monitoring
│   │   │
│   │   ├── services/
│   │   │   ├── across/
│   │   │   │   ├── AcrossService.ts             # Across V4 SDK wrapper
│   │   │   │   ├── IntentManager.ts             # Intent creation/tracking
│   │   │   │   └── BridgeUtils.ts               # Bridge helper functions
│   │   │   │
│   │   │   ├── arbitrage/
│   │   │   │   ├── OpportunityScanner.ts        # Real-time opportunity detection
│   │   │   │   ├── ProfitCalculator.ts          # Profit calculation service
│   │   │   │   ├── ExecutionService.ts          # Arbitrage execution
│   │   │   │   └── RiskManager.ts               # Risk assessment
│   │   │   │
│   │   │   ├── blockchain/
│   │   │   │   ├── ContractService.ts           # Smart contract interactions
│   │   │   │   ├── MultiChainProvider.ts        # Multi-chain RPC management
│   │   │   │   ├── EventListener.ts             # Contract event monitoring
│   │   │   │   └── TransactionService.ts        # Transaction management
│   │   │   │
│   │   │   ├── oracles/
│   │   │   │   ├── ChainlinkService.ts          # Chainlink price feeds
│   │   │   │   ├── UniswapV3Oracle.ts           # Uniswap V3 TWAP
│   │   │   │   ├── PriceAggregator.ts           # Multi-source price aggregation
│   │   │   │   └── PriceHistory.ts              # Historical price data
│   │   │   │
│   │   │   └── api/
│   │   │       ├── ApiClient.ts                 # Backend API client
│   │   │       ├── WebSocketClient.ts           # Real-time data streaming
│   │   │       └── CacheService.ts              # Data caching layer
│   │   │
│   │   ├── utils/
│   │   │   ├── constants.ts                     # App constants
│   │   │   ├── formatters.ts                    # Data formatting utilities
│   │   │   ├── validators.ts                    # Input validation
│   │   │   ├── calculations.ts                  # Mathematical calculations
│   │   │   ├── chainConfig.ts                   # Chain configurations
│   │   │   └── tokenConfig.ts                   # Token configurations
│   │   │
│   │   ├── stores/
│   │   │   ├── arbitrageStore.ts                # Zustand arbitrage state
│   │   │   ├── walletStore.ts                   # Wallet connection state
│   │   │   ├── priceStore.ts                    # Price data state
│   │   │   ├── transactionStore.ts              # Transaction state
│   │   │   └── settingsStore.ts                 # User settings state
│   │   │
│   │   ├── types/
│   │   │   ├── arbitrage.ts                     # Arbitrage type definitions
│   │   │   ├── chains.ts                        # Chain type definitions
│   │   │   ├── tokens.ts                        # Token type definitions
│   │   │   ├── transactions.ts                  # Transaction types
│   │   │   └── api.ts                           # API response types
│   │   │
│   │   ├── styles/
│   │   │   ├── globals.css                      # Global styles
│   │   │   ├── components.css                   # Component-specific styles
│   │   │   └── tailwind.css                     # Tailwind imports
│   │   │
│   │   ├── App.tsx                              # Main App component
│   │   ├── main.tsx                             # Entry point
│   │   └── vite-env.d.ts                        # Vite type definitions
│   │
│   ├── public/
│   │   ├── icons/
│   │   │   ├── chains/                          # Chain logos
│   │   │   ├── tokens/                          # Token logos
│   │   │   └── app/                             # App icons
│   │   │
│   │   ├── favicon.ico                          # App favicon
│   │   └── manifest.json                        # PWA manifest
│   │
│   ├── package.json                             # Frontend dependencies
│   ├── tsconfig.json                            # TypeScript configuration
│   ├── vite.config.ts                           # Vite configuration
│   ├── tailwind.config.js                       # Tailwind CSS configuration
│   ├── postcss.config.js                        # PostCSS configuration
│   └── .env.example                             # Frontend environment template
│
├── backend/                                 # Backend API server (optional)
│   ├── src/
│   │   ├── routes/
│   │   │   ├── arbitrage.ts                     # Arbitrage API routes
│   │   │   ├── prices.ts                        # Price data API
│   │   │   ├── analytics.ts                     # Analytics API
│   │   │   └── webhooks.ts                      # Webhook handlers
│   │   │
│   │   ├── services/
│   │   │   ├── PriceAggregationService.ts       # Price data aggregation
│   │   │   ├── ArbitrageMonitorService.ts       # Opportunity monitoring
│   │   │   ├── NotificationService.ts           # Push notifications
│   │   │   └── AnalyticsService.ts              # Data analytics
│   │   │
│   │   ├── middleware/
│   │   │   ├── auth.ts                          # Authentication middleware
│   │   │   ├── rateLimit.ts                     # Rate limiting
│   │   │   └── validation.ts                    # Request validation
│   │   │
│   │   ├── models/
│   │   │   ├── ArbitrageOpportunity.ts          # Opportunity data model
│   │   │   ├── Transaction.ts                   # Transaction data model
│   │   │   └── User.ts                          # User data model
│   │   │
│   │   ├── utils/
│   │   │   ├── database.ts                      # Database utilities
│   │   │   ├── logger.ts                        # Logging utilities
│   │   │   └── websocket.ts                     # WebSocket server
│   │   │
│   │   └── app.ts                               # Express app setup
│   │
│   ├── package.json                             # Backend dependencies
│   ├── tsconfig.json                            # TypeScript configuration
│   └── .env.example                             # Backend environment template
│
├── docs/                                    # Documentation
│   ├── INTEGRATION.md                           # Integration guide
│   ├── API.md                                   # API documentation
│   ├── FRONTEND.md                              # Frontend setup guide
│   ├── DEPLOYMENT.md                            # Deployment instructions
│   └── SECURITY.md                              # Security considerations
│
├── .github/                                 # GitHub workflows
│   └── workflows/
│       ├── contracts.yml                        # Contract CI/CD
│       ├── frontend.yml                         # Frontend CI/CD
│       ├── backend.yml                          # Backend CI/CD
│       └── security.yml                         # Security scanning
│
├── docker/                                  # Docker configurations
│   ├── Dockerfile.frontend                      # Frontend container
│   ├── Dockerfile.backend                       # Backend container
│   └── docker-compose.yml                       # Multi-service setup
│
├── README.md                                    # Main documentation
├── LICENSE                                      # MIT license
├── .gitignore                                   # Git ignore rules
└── package.json                                 # Root package.json (workspaces)
```

## Getting Started

### Prerequisites
- **Foundry** (latest version) - `curl -L https://foundry.paradigm.xyz | bash`
- **Node.js** 18+ for frontend and backend development
- **Git** for dependency management
- **Multi-chain RPC endpoints** (Alchemy, Infura, QuickNode, etc.)
- **UHI Framework** - Base arbitrage hook dependencies
- **Across Protocol SDK** - For cross-chain integration
- **Modern Browser** - Chrome, Firefox, or Safari with Web3 wallet support

### System Requirements
- **RAM**: Minimum 8GB (16GB recommended)
- **Storage**: 10GB free space for dependencies and build artifacts
- **Network**: Stable internet connection for multi-chain operations
- **OS**: macOS, Linux, or Windows with WSL2

### Installation
```bash
# Clone the repository
git clone https://github.com/your-org/cross-chain-arbitrage-hook
cd cross-chain-arbitrage-hook

# Install root dependencies (if using workspaces)
npm install

# Install and build contracts
cd contracts
forge install
forge build

# Install frontend dependencies
cd ../frontend
npm install

# Install backend dependencies (optional)
cd ../backend
npm install

# Return to root
cd ..
```

### Quick Start (Development)
```bash
# Terminal 1: Start local blockchain (Anvil)
anvil --fork-url $MAINNET_RPC_URL

# Terminal 2: Deploy contracts to local network
cd contracts
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Terminal 3: Start backend (optional)
cd backend
npm run dev

# Terminal 4: Start frontend
cd frontend
npm run dev
```

### Configuration
```bash
# Copy environment template
cp .env.example .env

### Frontend Technology Stack

**Core Framework:**
- **React 18** - Modern React with hooks and concurrent features
- **TypeScript** - Type safety for complex arbitrage logic
- **Vite** - Fast development server and build tool
- **React Router** - Client-side routing

**Styling & UI:**
- **Tailwind CSS** - Utility-first CSS framework
- **Headless UI** - Unstyled, accessible UI components
- **React Hot Toast** - Beautiful notifications
- **Framer Motion** - Smooth animations and transitions

**Web3 Integration:**
- **wagmi** - React hooks for Ethereum interactions
- **viem** - TypeScript Ethereum library
- **RainbowKit** - Wallet connection UI
- **Across V4 SDK** - Cross-chain bridge integration

**State Management:**
- **Zustand** - Lightweight state management
- **TanStack Query** - Server state management and caching
- **React Hook Form** - Form state management

**Data & Analytics:**
- **Recharts** - React charting library
- **D3.js** - Advanced data visualizations
- **date-fns** - Date manipulation utilities

**Development Tools:**
- **ESLint** - Code linting
- **Prettier** - Code formatting
- **Husky** - Git hooks
- **Vitest** - Unit testing framework

### Backend Technology Stack (Optional)

**Core Framework:**
- **Node.js** - JavaScript runtime
- **Express.js** - Web application framework
- **TypeScript** - Type safety for backend services

**Database & Caching:**
- **PostgreSQL** - Primary database for analytics
- **Redis** - Caching and session storage
- **Prisma** - Database ORM and migrations

**Real-time Features:**
- **Socket.io** - WebSocket connections
- **Bull Queue** - Job queue processing
- **Node-cron** - Scheduled tasks

**Monitoring & Security:**
- **Winston** - Logging framework
- **Helmet** - Security middleware
- **Rate-limiter-flexible** - Rate limiting
- **JWT** - Authentication tokens

```

### Configuration

#### Environment Setup
```bash
# Copy environment templates
cp contracts/.env.example contracts/.env
cp frontend/.env.example frontend/.env
cp backend/.env.example backend/.env

# Configure contract environment (contracts/.env)
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY
ARBITRUM_RPC_URL=https://arbitrum-mainnet.infura.io/v3/YOUR_KEY
BASE_RPC_URL=https://mainnet.base.org
POLYGON_RPC_URL=https://polygon-mainnet.infura.io/v3/YOUR_KEY
OPTIMISM_RPC_URL=https://optimism-mainnet.infura.io/v3/YOUR_KEY

# API Keys
CHAINLINK_API_KEY=your_chainlink_key
ACROSS_API_KEY=your_across_key
ETHERSCAN_API_KEY=your_etherscan_key
ARBISCAN_API_KEY=your_arbiscan_key
BASESCAN_API_KEY=your_basescan_key

# Hook Configuration
MIN_PROFIT_BPS=50              # Minimum 0.5% profit threshold
MAX_SLIPPAGE_BPS=100          # Maximum 1% slippage
GAS_PRICE_BUFFER_BPS=200      # 2% buffer for gas price estimates
USER_PROFIT_SHARE_BPS=7000    # 70% profit share to users
DEPLOYER_PRIVATE_KEY=your_deployer_private_key
```

#### Frontend Environment (frontend/.env)
```bash
# API Endpoints
VITE_API_BASE_URL=http://localhost:3001/api
VITE_WS_URL=ws://localhost:3001

# Contract Addresses (populated after deployment)
VITE_ARBITRAGE_HOOK_ADDRESS=0x...
VITE_POOL_MANAGER_ADDRESS=0x...

# Chain Configuration
VITE_DEFAULT_CHAIN_ID=1
VITE_SUPPORTED_CHAINS=1,42161,8453,137,10

# Feature Flags
VITE_ENABLE_ANALYTICS=true
VITE_ENABLE_NOTIFICATIONS=true
VITE_DEBUG_MODE=false

# Third-party Services
VITE_WALLETCONNECT_PROJECT_ID=your_walletconnect_project_id
VITE_ALCHEMY_API_KEY=your_alchemy_api_key
```

#### Backend Environment (backend/.env) - Optional
```bash
# Server Configuration
PORT=3001
NODE_ENV=development
CORS_ORIGIN=http://localhost:5173

# Database
DATABASE_URL=postgresql://username:password@localhost:5432/arbitrage_db
REDIS_URL=redis://localhost:6379

# Authentication
JWT_SECRET=your_jwt_secret
JWT_EXPIRES_IN=7d

# External APIs
CHAINLINK_WS_URL=wss://ws.chain.link
ACROSS_API_URL=https://api.across.to
```

## Integration Guide

### Integration Guide

#### For Developers
```solidity
// Deploy the hook
CrossChainArbitrageHook hook = new CrossChainArbitrageHook(
    poolManager,
    acrossProtocolAddress,
    chainlinkOracleRegistry
);

// Create a pool with the arbitrage hook
PoolKey memory key = PoolKey({
    currency0: Currency.wrap(tokenA),
    currency1: Currency.wrap(tokenB),
    fee: 3000,
    tickSpacing: 60,
    hooks: IHooks(address(hook))
});
```

#### Frontend Integration
```typescript
// Install the SDK
npm install @across-protocol/sdk-v2

// Initialize in your app
import { AcrossSDK } from '@across-protocol/sdk-v2'

const acrossSDK = new AcrossSDK({
  rpcUrls: {
    1: process.env.VITE_MAINNET_RPC_URL,
    42161: process.env.VITE_ARBITRUM_RPC_URL,
    8453: process.env.VITE_BASE_RPC_URL,
  },
  spokePoolAddresses: {
    1: '0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5',
    42161: '0x6f26Bf09B1C792e3228e5467807a900A503c0281',
    8453: '0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64',
  }
})

// Execute cross-chain arbitrage
const executeArbitrage = async (opportunity: ArbitrageOpportunity) => {
  const quote = await acrossSDK.getQuote({
    tokenAddress: opportunity.tokenIn,
    amount: opportunity.amountIn,
    originChainId: opportunity.originChainId,
    destinationChainId: opportunity.targetChainId
  })
  
  const intent = await acrossSDK.executeIntent(quote)
  return intent.hash
}
```

#### For LPs
Liquidity providers benefit from:
- **Increased Fee Generation**: Higher trading volume through arbitrage activity
- **Better Price Discovery**: Reduced spreads and more efficient price discovery
- **MEV Protection**: Hook captures MEV that would otherwise be extracted by bots
- **Automatic Rebalancing**: Cross-chain arbitrage helps maintain optimal liquidity distribution

#### For Traders
Users automatically benefit when:
- **Making Swaps**: Automatic routing to cheapest execution chain
- **No Extra Costs**: Gas-optimized execution with shared profit model
- **Better Prices**: Access to cross-chain liquidity for better rates
- **Simplified UX**: Single transaction for complex cross-chain operations

#### For Protocols
Other protocols can integrate by:
- **Hook Composability**: Combine with other Uniswap v4 hooks
- **API Access**: Use our arbitrage detection API for their own applications
- **White-label Solutions**: Custom arbitrage interfaces for their users
- **Revenue Sharing**: Partnership opportunities for mutual benefit

### Deployment Instructions

#### Local Development Deployment
```bash
# Start local development environment
npm run dev

# Deploy to local Anvil network
cd contracts
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Configure frontend with deployed addresses
cd ../frontend
# Update .env with deployed contract addresses
npm run dev
```

#### Testnet Deployment
```bash
# Deploy to Arbitrum Sepolia
forge script script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY

# Deploy to Base Sepolia
forge script script/Deploy.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY
```

#### Mainnet Deployment
```bash
# Security checklist before mainnet deployment
npm run security-check
npm run audit-report

# Deploy to mainnet with multi-sig
forge script script/Deploy.s.sol \
  --rpc-url $MAINNET_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --slow # Use slower deployment for better reliability
```

### Frontend Deployment

#### Vercel Deployment
```bash
# Install Vercel CLI
npm install -g vercel

# Deploy frontend
cd frontend
vercel --prod

# Set environment variables in Vercel dashboard:
# VITE_ARBITRAGE_HOOK_ADDRESS
# VITE_POOL_MANAGER_ADDRESS
# VITE_WALLETCONNECT_PROJECT_ID
```

#### Self-hosted Deployment
```bash
# Build for production
cd frontend
npm run build

# Deploy with Docker
docker build -f ../docker/Dockerfile.frontend -t arbitrage-frontend .
docker run -p 3000:3000 arbitrage-frontend

# Or deploy to your preferred hosting service
```

### Monitoring & Analytics

#### Performance Monitoring
```bash
# Set up monitoring stack
cd monitoring
docker-compose up -d  # Starts Prometheus, Grafana, and custom metrics collectors

# View dashboards at:
# http://localhost:3000 (Grafana)
# http://localhost:9090 (Prometheus)
```

#### Key Metrics to Monitor
- **Arbitrage Success Rate**: Percentage of successful cross-chain arbitrages
- **Average Execution Time**: Time from opportunity detection to completion
- **Profit Margins**: Average and total profits captured
- **Gas Efficiency**: Gas costs compared to alternative routing methods
- **Chain Health**: Monitoring of all supported chains for outages or issues

## Security Considerations

### Smart Contract Security
- **Audit Requirements**: Full security audit before mainnet deployment
- **Access Controls**: Proper role-based permissions for admin functions
- **Reentrancy Protection**: Guards against reentrancy attacks
- **Integer Overflow**: SafeMath usage for all arithmetic operations

### Cross-Chain Security
- **Bridge Risk**: Mitigated by using established Across Protocol
- **Oracle Manipulation**: Multiple price feed sources with outlier detection
- **Front-Running**: Private mempool integration and MEV protection
- **Chain Reorg Risk**: Confirmation requirements and deep reorg protection

### Economic Security
- **Slippage Protection**: Maximum slippage limits on all trades
- **Profit Thresholds**: Minimum profit requirements to prevent unprofitable trades
- **Circuit Breakers**: Emergency stops for unusual market conditions
- **Insurance Fund**: Protocol reserve fund for edge case losses

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for:
- Code style and standards
- Testing requirements
- Pull request process
- Issue reporting

### Development Setup
```bash
# Fork the repository
git fork https://github.com/your-org/cross-chain-arbitrage-hook

# Create feature branch
git checkout -b feature/your-feature-name

# Make changes and test
forge test

# Submit pull request
```

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## Contact & Support

- **Team**: Cross-Chain Arbitrage Team
- **Discord**: Join our [Discord server](https://discord.gg/your-server)
- **Twitter**: [@CrossChainArb](https://twitter.com/your-handle)
- **Email**: team@crosschainarbitrage.com
- **Documentation**: [Full Documentation](https://docs.crosschainarbitrage.com)

## Acknowledgments

- **Uniswap Foundation** for the Hook Incubator program
- **Across Protocol** for V4 integration support and VIP sponsorship
- **UHI Community** for the foundational arbitrage framework
- **Hook Incubator** mentors and participants for guidance and feedback

---

*This project is submitted for the UHI5 Hookathon targeting Across Protocol's VIP sponsor prize. Built as an extension of the UHI arbitrage framework with cross-chain MEV capture capabilities.*