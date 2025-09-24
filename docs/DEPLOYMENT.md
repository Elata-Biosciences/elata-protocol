# 🚀 Deployment Guide

## 📋 **Deployment Flow Overview**

```mermaid
graph TD
    subgraph "Pre-deployment Phase"
        P1[Environment Setup<br/>🔧 Configure variables]
        P2[Security Review<br/>🛡️ Audit contracts]
        P3[Test Validation<br/>🧪 100% pass rate]
        P4[Gas Estimation<br/>⛽ Cost planning]
    end
    
    subgraph "Deployment Phase"
        D1[Testnet Deploy<br/>🧪 Sepolia validation]
        D2[Community Testing<br/>👥 User validation]
        D3[Final Review<br/>📋 Last checks]
        D4[Mainnet Deploy<br/>🚀 Production launch]
    end
    
    subgraph "Post-deployment Phase"
        PD1[Verification<br/>✅ Contract validation]
        PD2[Configuration<br/>⚙️ Role setup]
        PD3[Monitoring<br/>📊 System health]
        PD4[Community Launch<br/>🎉 Go live]
    end
    
    P1 --> P2 --> P3 --> P4
    P4 --> D1 --> D2 --> D3 --> D4
    D4 --> PD1 --> PD2 --> PD3 --> PD4
    
    style P3 fill:#e8f5e8
    style D4 fill:#fff3e0
    style PD4 fill:#e3f2fd
```

## 🔧 **Environment Configuration**

### Network Setup Matrix

```mermaid
graph TD
    subgraph "Ethereum Mainnet"
        EM1[Chain ID: 1]
        EM2[Gas Price: 15-30 gwei]
        EM3[Deploy Cost: ~$260]
        EM4[Security: Highest]
    end
    
    subgraph "Base Mainnet"
        BM1[Chain ID: 8453]
        BM2[Gas Price: 0.01-0.1 gwei]
        BM3[Deploy Cost: ~$2.60]
        BM4[Security: High]
    end
    
    subgraph "Sepolia Testnet"
        ST1[Chain ID: 11155111]
        ST2[Gas Price: Free]
        ST3[Deploy Cost: $0]
        ST4[Security: Testing only]
    end
    
    subgraph "Base Sepolia"
        BS1[Chain ID: 84532]
        BS2[Gas Price: Free]
        BS3[Deploy Cost: $0]
        BS4[Security: Testing only]
    end
    
    style EM1 fill:#ff9999
    style BM1 fill:#99ccff
    style ST1 fill:#99ff99
    style BS1 fill:#ffcc99
```

### Deployment Prerequisites

```mermaid
graph LR
    subgraph "Required Tools"
        RT1[Foundry<br/>Latest version]
        RT2[Git<br/>Version control]
        RT3[Node.js<br/>v18+ for scripts]
    end
    
    subgraph "Required Accounts"
        RA1[Deployer Wallet<br/>Sufficient ETH]
        RA2[Admin Multisig<br/>Gnosis Safe]
        RA3[Treasury Wallet<br/>Token recipient]
    end
    
    subgraph "Required Keys"
        RK1[RPC Endpoints<br/>Infura/Alchemy]
        RK2[API Keys<br/>Etherscan/Basescan]
        RK3[Private Keys<br/>Secure storage]
    end
    
    RT1 --> RA1
    RT2 --> RA2
    RT3 --> RA3
    
    RA1 --> RK1
    RA2 --> RK2
    RA3 --> RK3
    
    style RA2 fill:#fff3e0
    style RK3 fill:#ffebee
```

## 📦 **Deployment Process**

### Contract Deployment Sequence

```mermaid
sequenceDiagram
    participant Deployer
    participant ELTA
    participant ElataXP
    participant VeELTA
    participant LotPool
    participant RewardsDistributor
    participant ElataGovernor
    participant Verification
    
    Note over Deployer, Verification: Phase 1: Core Contracts
    Deployer->>ELTA: Deploy with initial mint
    ELTA-->>Deployer: Contract address
    
    Deployer->>ElataXP: Deploy with admin
    ElataXP-->>Deployer: Contract address
    
    Deployer->>VeELTA: Deploy with ELTA reference
    VeELTA-->>Deployer: Contract address
    
    Note over Deployer, Verification: Phase 2: Governance
    Deployer->>LotPool: Deploy with ELTA + XP
    LotPool-->>Deployer: Contract address
    
    Deployer->>RewardsDistributor: Deploy with VeELTA
    RewardsDistributor-->>Deployer: Contract address
    
    Deployer->>ElataGovernor: Deploy with ELTA
    ElataGovernor-->>Deployer: Contract address
    
    Note over Deployer, Verification: Phase 3: Configuration
    Deployer->>RewardsDistributor: addRewardToken(ELTA)
    Deployer->>ElataXP: grantRole(XP_MINTER, LotPool)
    
    Note over Deployer, Verification: Phase 4: Verification
    Deployer->>Verification: Run verification script
    Verification-->>Deployer: All contracts verified ✅
```

### Gas Cost Estimation

```mermaid
graph TD
    subgraph "Deployment Costs by Network"
        direction TB
        
        ETH[Ethereum Mainnet<br/>13M gas × 20 gwei = $260]
        BASE[Base Mainnet<br/>13M gas × 0.05 gwei = $1.30]
        SEPOLIA[Sepolia Testnet<br/>13M gas × 0 gwei = FREE]
    end
    
    subgraph "Cost Breakdown"
        direction TB
        
        C1[ELTA: 2.3M gas (18%)]
        C2[VeELTA: 3.3M gas (25%)]
        C3[ElataXP: 3.0M gas (23%)]
        C4[Others: 4.4M gas (34%)]
    end
    
    style ETH fill:#ff9999
    style BASE fill:#99ccff
    style SEPOLIA fill:#99ff99
```

## ✅ **Verification Procedures**

### Post-Deployment Verification

```mermaid
graph TD
    subgraph "Contract Verification"
        CV1[Source Code<br/>Block explorer verification]
        CV2[ABI Matching<br/>Interface consistency]
        CV3[Bytecode Hash<br/>Compilation verification]
    end
    
    subgraph "Functional Verification"
        FV1[Basic Operations<br/>Token transfers work]
        FV2[Access Control<br/>Roles properly set]
        FV3[Integration<br/>Cross-contract calls]
        FV4[Security<br/>Protection mechanisms active]
    end
    
    subgraph "Configuration Verification"
        CFV1[Admin Roles<br/>Multisig control]
        CFV2[Initial State<br/>Correct parameters]
        CFV3[Token Supply<br/>Expected amounts]
        CFV4[Permissions<br/>Proper role grants]
    end
    
    CV1 --> FV1
    CV2 --> FV2
    CV3 --> FV3
    
    FV1 --> CFV1
    FV2 --> CFV2
    FV3 --> CFV3
    FV4 --> CFV4
    
    style CFV1 fill:#e8f5e8
    style CFV4 fill:#fff3e0
```

### Verification Commands

```bash
# Contract verification
cast call $ELTA_ADDRESS "name()" --rpc-url $RPC_URL
cast call $ELTA_ADDRESS "totalSupply()" --rpc-url $RPC_URL
cast call $ELTA_ADDRESS "MAX_SUPPLY()" --rpc-url $RPC_URL

# Access control verification
cast call $ELTA_ADDRESS "hasRole(bytes32,address)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $ADMIN_MSIG --rpc-url $RPC_URL

# Integration verification
cast call $VEELTA_ADDRESS "ELTA()" --rpc-url $RPC_URL
cast call $LOTPOOL_ADDRESS "XP()" --rpc-url $RPC_URL
```

## 🚨 **Emergency Procedures**

### Incident Response Flow

```mermaid
graph TD
    subgraph "Detection"
        D1[Monitoring Alert]
        D2[Community Report]
        D3[Security Scan]
    end
    
    subgraph "Assessment"
        A1[Severity Analysis<br/>Critical/High/Medium/Low]
        A2[Impact Assessment<br/>User funds/Protocol function]
        A3[Response Planning<br/>Immediate/Planned/Monitoring]
    end
    
    subgraph "Response Actions"
        R1[Emergency Pause<br/>If available]
        R2[Governance Proposal<br/>Protocol changes]
        R3[Community Communication<br/>Transparency]
        R4[Fix Development<br/>Code changes]
    end
    
    subgraph "Resolution"
        RES1[Fix Deployment<br/>New contracts if needed]
        RES2[Migration Plan<br/>User fund safety]
        RES3[Post-mortem<br/>Lessons learned]
    end
    
    D1 --> A1
    D2 --> A1
    D3 --> A1
    
    A1 --> R1
    A2 --> R2
    A3 --> R3
    
    R1 --> RES1
    R2 --> RES2
    R3 --> RES3
    
    style A1 fill:#ffebee
    style R1 fill:#fff3e0
    style RES1 fill:#e8f5e8
```

### Emergency Contact Tree

```mermaid
graph TD
    INCIDENT[Security Incident Detected]
    
    subgraph "Immediate Response (0-1 hours)"
        IR1[Technical Lead<br/>Initial assessment]
        IR2[Security Team<br/>Threat analysis]
        IR3[Multisig Signers<br/>Emergency actions]
    end
    
    subgraph "Extended Response (1-24 hours)"
        ER1[Core Team<br/>Solution development]
        ER2[Legal Counsel<br/>Compliance review]
        ER3[Communications<br/>Community updates]
    end
    
    subgraph "Recovery Phase (24+ hours)"
        RP1[External Auditors<br/>Independent review]
        RP2[Community DAO<br/>Governance decisions]
        RP3[Ecosystem Partners<br/>Coordination]
    end
    
    INCIDENT --> IR1
    INCIDENT --> IR2
    INCIDENT --> IR3
    
    IR1 --> ER1
    IR2 --> ER2
    IR3 --> ER3
    
    ER1 --> RP1
    ER2 --> RP2
    ER3 --> RP3
    
    style INCIDENT fill:#ffcdd2
    style IR1 fill:#fff3e0
    style ER1 fill:#e8f5e8
    style RP1 fill:#e3f2fd
```

## 📊 **Monitoring & Analytics**

### Key Performance Indicators

```mermaid
graph TD
    subgraph "Protocol Health"
        PH1[Total Value Locked<br/>📈 Growth metric]
        PH2[Active Users<br/>👥 Engagement]
        PH3[Transaction Volume<br/>💱 Usage]
        PH4[Governance Participation<br/>🗳️ Decentralization]
    end
    
    subgraph "Economic Metrics"
        EM1[Token Price<br/>💰 Market value]
        EM2[Staking Ratio<br/>🔒 Supply locked]
        EM3[XP Distribution<br/>🏅 Participation]
        EM4[Funding Efficiency<br/>💧 Capital allocation]
    end
    
    subgraph "Security Metrics"
        SM1[Failed Transactions<br/>🚨 Error rate]
        SM2[Unusual Patterns<br/>🔍 Anomaly detection]
        SM3[Emergency Usage<br/>⚠️ Crisis indicators]
        SM4[Access Control Events<br/>🔐 Permission changes]
    end
    
    PH1 --> EM1
    PH2 --> EM2
    PH3 --> EM3
    PH4 --> EM4
    
    EM1 --> SM1
    EM2 --> SM2
    EM3 --> SM3
    EM4 --> SM4
    
    style PH1 fill:#e8f5e8
    style EM1 fill:#fff3e0
    style SM1 fill:#ffebee
```

---

*Complete deployment guide with visual workflows for professional protocol deployment.*

