# Elata Protocol Architecture

## 🏗️ **System Architecture Overview**

```mermaid
graph TB
    subgraph "Application Layer"
        APP1[EEG Games]
        APP2[Meditation Apps]
        APP3[Research Tools]
        APP4[Analytics Dashboard]
    end
    
    subgraph "Protocol Layer"
        subgraph "Core Contracts"
            ELTA[ELTA Token<br/>Governance & Utility]
            VE[VeELTA<br/>Multi-position Staking]
            XP[ElataXP<br/>Reputation System]
            LP[LotPool<br/>Funding Governance]
        end
        
        subgraph "Advanced Contracts"
            RD[RewardsDistributor<br/>Yield Distribution]
            GOV[ElataGovernor<br/>Onchain Voting]
            TL[ElataTimelock<br/>Execution Delays]
            STATS[ProtocolStats<br/>Data Aggregation]
        end
    end
    
    subgraph "Infrastructure Layer"
        ZORP[ZORP Protocol<br/>Data Submission]
        IPFS[IPFS Storage<br/>Decentralized Data]
        KEEPERS[Keeper Network<br/>Automation]
    end
    
    subgraph "Hardware Layer"
        EEG[EEG Devices<br/>Data Collection]
        PI[Raspberry Pi<br/>Processing]
        ADS[ADS1299<br/>Signal Acquisition]
    end
    
    APP1 --> ELTA
    APP2 --> XP
    APP3 --> LP
    APP4 --> STATS
    
    ELTA --> VE
    VE --> RD
    XP --> LP
    GOV --> TL
    
    LP --> ZORP
    RD --> KEEPERS
    STATS --> IPFS
    
    ZORP --> EEG
    EEG --> PI
    PI --> ADS
    
    style ELTA fill:#ff9999
    style VE fill:#99ccff
    style XP fill:#99ff99
    style LP fill:#ffcc99
```

## 📊 **Contract Interaction Matrix**

```mermaid
graph TD
    subgraph "Token Economics"
        direction TB
        ELTA[ELTA Token<br/>77M Supply Cap]
        MINT[Minting Logic<br/>Role-gated]
        BURN[Burning Logic<br/>Deflationary]
        
        ELTA --> MINT
        ELTA --> BURN
    end
    
    subgraph "Staking Economics"
        direction TB
        LOCK[Lock Creation<br/>NFT Positions]
        POWER[Voting Power<br/>Linear Decay]
        DELEGATE[Delegation<br/>Flexible Control]
        
        LOCK --> POWER
        POWER --> DELEGATE
    end
    
    subgraph "Reputation Economics"
        direction TB
        EARN[XP Earning<br/>Activity-based]
        DECAY[XP Decay<br/>14-day Window]
        VOTE[Voting Rights<br/>Funding Rounds]
        
        EARN --> DECAY
        DECAY --> VOTE
    end
    
    subgraph "Funding Economics"
        direction TB
        ROUNDS[Weekly Rounds<br/>Community Voting]
        ALLOCATION[Fund Allocation<br/>Merit-based]
        PAYOUT[Research Payouts<br/>Transparent]
        
        ROUNDS --> ALLOCATION
        ALLOCATION --> PAYOUT
    end
    
    ELTA -.-> LOCK
    POWER -.-> DELEGATE
    VOTE -.-> ROUNDS
    PAYOUT -.-> ELTA
    
    style ELTA fill:#ff9999
    style LOCK fill:#99ccff
    style EARN fill:#99ff99
    style ROUNDS fill:#ffcc99
```

## 🔄 **State Transitions**

### VeELTA Position Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: createLock()
    Created --> Active: Position NFT minted
    Active --> Increased: increaseAmount()
    Active --> Extended: increaseUnlockTime()
    Active --> Merged: mergePositions()
    Active --> Split: splitPosition()
    Split --> Active: New positions created
    Merged --> Active: Combined position
    Increased --> Active: More ELTA locked
    Extended --> Active: Longer duration
    Active --> Expired: Time passes
    Active --> EmergencyUnlocked: emergencyUnlock()
    Expired --> Withdrawn: withdraw()
    EmergencyUnlocked --> Withdrawn: withdraw()
    Withdrawn --> [*]: NFT burned
    
    note right of Created
        Initial voting power:
        amount × duration ÷ MAX_LOCK
    end note
    
    note right of Active
        Voting power decays linearly:
        amount × time_remaining ÷ MAX_LOCK
    end note
    
    note right of EmergencyUnlocked
        50% penalty applied
        Immediate withdrawal allowed
    end note
```

### XP Decay State Machine

```mermaid
stateDiagram-v2
    [*] --> Fresh: XP Awarded
    Fresh --> Aging: Time passes
    Aging --> PartialDecay: 0-14 days old
    PartialDecay --> FullDecay: 14+ days old
    PartialDecay --> Refreshed: New XP awarded
    Refreshed --> Aging: Time passes
    FullDecay --> Removed: updateUserDecay()
    Removed --> [*]: Entry deleted
    
    note right of Fresh
        Effective XP = 100%
        Full voting power
    end note
    
    note right of PartialDecay
        Effective XP = linear decay
        (14 - age) ÷ 14 × amount
    end note
    
    note right of FullDecay
        Effective XP = 0%
        No voting power
    end note
```

### Funding Round State Flow

```mermaid
stateDiagram-v2
    [*] --> Setup: Admin creates round
    Setup --> Active: startRound()
    Active --> Voting: Users cast votes
    Voting --> Voting: More votes
    Voting --> Closed: Duration expires
    Closed --> Finalized: finalize()
    Finalized --> [*]: Funds distributed
    
    note right of Setup
        - Define options
        - Set recipients
        - Take XP snapshot
    end note
    
    note right of Voting
        - XP allocation
        - Cannot exceed snapshot
        - Immutable votes
    end note
    
    note right of Finalized
        - Winner determined
        - ELTA transferred
        - Events emitted
    end note
```

## 📐 **Mathematical Models**

### Voting Power Decay Function

```mermaid
graph LR
    subgraph "Linear Decay Model"
        INPUT[Lock: 1000 ELTA<br/>Duration: 104 weeks]
        FORMULA[f(t) = 1000 × (104-t)/208]
        OUTPUT[Voting Power over Time]
    end
    
    INPUT --> FORMULA --> OUTPUT
```

**Mathematical Expression:**
$$
VP(t) = A \times \frac{\max(0, D - t)}{MAX\_LOCK}
$$

Where:
- $VP(t)$ = Voting power at time $t$
- $A$ = Locked amount
- $D$ = Lock duration
- $t$ = Time elapsed since lock creation
- $MAX\_LOCK$ = 208 weeks

### XP Decay Function

```mermaid
graph LR
    subgraph "Exponential-like Decay"
        XP_INPUT[XP Entry: 1000 XP<br/>Timestamp: t₀]
        XP_FORMULA[g(t) = 1000 × max(0, (14d - age)/14d)]
        XP_OUTPUT[Effective XP over Time]
    end
    
    XP_INPUT --> XP_FORMULA --> XP_OUTPUT
```

**Mathematical Expression:**
$$
XP_{effective}(t) = \sum_{i=1}^{n} XP_i \times \frac{\max(0, DECAY\_WINDOW - (t - t_i))}{DECAY\_WINDOW}
$$

Where:
- $XP_{effective}(t)$ = Total effective XP at time $t$
- $XP_i$ = Amount of XP entry $i$
- $t_i$ = Timestamp of XP entry $i$
- $DECAY\_WINDOW$ = 14 days

### Reward Distribution Formula

$$
R_u = \frac{VP_u}{\sum_{i=1}^{n} VP_i} \times R_{total}
$$

Where:
- $R_u$ = Reward for user $u$
- $VP_u$ = User's voting power at epoch snapshot
- $R_{total}$ = Total epoch rewards

## 🔗 **Integration Patterns**

### Frontend Data Flow

```mermaid
sequenceDiagram
    participant Frontend
    participant ProtocolStats
    participant ELTA
    participant VeELTA
    participant ElataXP
    participant LotPool
    
    Note over Frontend, LotPool: Dashboard Load
    Frontend->>ProtocolStats: getUserSummary(address)
    ProtocolStats->>ELTA: balanceOf(user)
    ProtocolStats->>VeELTA: getUserVotingPower(user)
    ProtocolStats->>ElataXP: effectiveBalance(user)
    ProtocolStats->>LotPool: getUserVotingStatus(user, round)
    ProtocolStats-->>Frontend: Complete user data
    
    Note over Frontend, LotPool: Real-time Updates
    ELTA->>Frontend: Transfer event
    VeELTA->>Frontend: LockCreated event
    ElataXP->>Frontend: XPAwarded event
    LotPool->>Frontend: Voted event
    
    Frontend->>Frontend: Update UI state
```

### Cross-Contract Communication

```mermaid
graph TD
    subgraph "Contract Dependencies"
        direction TB
        
        ELTA --> VE_DEP[VeELTA depends on ELTA<br/>for token transfers]
        XP --> LP_DEP[LotPool depends on ElataXP<br/>for voting snapshots]
        VE --> RD_DEP[RewardsDistributor depends on VeELTA<br/>for voting power calculations]
        ELTA --> GOV_DEP[ElataGovernor depends on ELTA<br/>for voting tokens]
    end
    
    subgraph "Data Flow"
        direction LR
        
        USER_ACTION[User Action] --> CONTRACT_CALL[Contract Function]
        CONTRACT_CALL --> STATE_CHANGE[State Update]
        STATE_CHANGE --> EVENT_EMIT[Event Emission]
        EVENT_EMIT --> FRONTEND_UPDATE[Frontend Update]
    end
    
    style VE_DEP fill:#e3f2fd
    style LP_DEP fill:#f3e5f5
    style RD_DEP fill:#e8f5e8
    style GOV_DEP fill:#fff3e0
```

## 🛡️ **Security Model Deep Dive**

### Access Control Matrix

```mermaid
graph TD
    subgraph "Role Hierarchy"
        ADMIN[DEFAULT_ADMIN_ROLE<br/>🔑 Master Control]
        MINTER[MINTER_ROLE<br/>🏭 Token Creation]
        MANAGER[MANAGER_ROLE<br/>⚙️ Operations]
        DISTRIBUTOR[DISTRIBUTOR_ROLE<br/>💰 Rewards]
        KEEPER[KEEPER_ROLE<br/>🤖 Automation]
        PAUSER[PAUSER_ROLE<br/>⏸️ Emergency Stop]
        EMERGENCY[EMERGENCY_ROLE<br/>🚨 Critical Actions]
    end
    
    ADMIN --> MINTER
    ADMIN --> MANAGER
    ADMIN --> DISTRIBUTOR
    ADMIN --> KEEPER
    ADMIN --> PAUSER
    ADMIN --> EMERGENCY
    
    style ADMIN fill:#ff9999
    style EMERGENCY fill:#ffcdd2
```

### Security Layers

```mermaid
graph LR
    subgraph "Layer 1: Input Validation"
        L1_1[Zero Address Checks]
        L1_2[Amount Validation]
        L1_3[Array Length Matching]
        L1_4[Boundary Conditions]
    end
    
    subgraph "Layer 2: Access Control"
        L2_1[Role-based Permissions]
        L2_2[Multi-signature Requirements]
        L2_3[Function Modifiers]
        L2_4[Emergency Controls]
    end
    
    subgraph "Layer 3: Economic Security"
        L3_1[Time-locked Positions]
        L3_2[Non-transferable Assets]
        L3_3[Supply Caps]
        L3_4[Linear Decay]
    end
    
    subgraph "Layer 4: Operational Security"
        L4_1[Reentrancy Guards]
        L4_2[State Validation]
        L4_3[External Call Safety]
        L4_4[Event Logging]
    end
    
    L1_1 --> L2_1
    L1_2 --> L2_2
    L1_3 --> L2_3
    L1_4 --> L2_4
    
    L2_1 --> L3_1
    L2_2 --> L3_2
    L2_3 --> L3_3
    L2_4 --> L3_4
    
    L3_1 --> L4_1
    L3_2 --> L4_2
    L3_3 --> L4_3
    L3_4 --> L4_4
```

### Attack Vector Mitigation

```mermaid
graph TD
    subgraph "Flash Loan Attacks"
        FA1[Attacker borrows large ELTA amount]
        FA2[Tries to create governance positions]
        FA3[❌ BLOCKED: Time-locked staking required]
    end
    
    subgraph "Voting Manipulation"
        VM1[Attacker tries to buy XP/votes]
        VM2[Attempts to transfer reputation]
        VM3[❌ BLOCKED: Non-transferable XP]
    end
    
    subgraph "Supply Manipulation"
        SM1[Attacker tries to mint unlimited tokens]
        SM2[Attempts to exceed supply cap]
        SM3[❌ BLOCKED: Hard cap enforcement]
    end
    
    subgraph "Governance Takeover"
        GT1[Attacker accumulates voting power]
        GT2[Tries to pass malicious proposals]
        GT3[❌ BLOCKED: Quorum + timelock delays]
    end
    
    style FA3 fill:#c8e6c9
    style VM3 fill:#c8e6c9
    style SM3 fill:#c8e6c9
    style GT3 fill:#c8e6c9
```

## 💰 **Economic Mechanism Design**

### Token Value Accrual Model

```mermaid
graph TD
    subgraph "Revenue Sources"
        RS1[App Store Fees<br/>15% take rate]
        RS2[Tournament Rake<br/>5-10% of prizes]
        RS3[Infrastructure Fees<br/>Protocol usage]
        RS4[Premium Features<br/>ELTA-gated access]
    end
    
    subgraph "Value Distribution"
        VD1[Treasury: 50%<br/>Operations & Growth]
        VD2[Staker Yields: 25%<br/>Real Returns]
        VD3[Buyback & Burn: 25%<br/>Supply Reduction]
    end
    
    subgraph "Demand Drivers"
        DD1[Governance Participation]
        DD2[Yield Expectations]
        DD3[App Ecosystem Access]
        DD4[Speculative Premium]
    end
    
    RS1 --> VD1
    RS2 --> VD2
    RS3 --> VD3
    RS4 --> VD1
    
    VD2 --> DD1
    VD2 --> DD2
    VD3 --> DD3
    VD1 --> DD4
    
    style VD2 fill:#e8f5e8
    style VD3 fill:#ffebee
```

### Staking Incentive Alignment

```mermaid
graph LR
    subgraph "Short-term Stakers"
        ST1[1-4 week locks]
        ST2[Low voting power]
        ST3[Minimal rewards]
        ST4[High flexibility]
    end
    
    subgraph "Medium-term Stakers"
        MT1[6 month - 1 year locks]
        MT2[Moderate voting power]
        MT3[Proportional rewards]
        MT4[Balanced commitment]
    end
    
    subgraph "Long-term Stakers"
        LT1[2-4 year locks]
        LT2[Maximum voting power]
        LT3[Highest rewards]
        LT4[Strong alignment]
    end
    
    ST1 --> ST2 --> ST3 --> ST4
    MT1 --> MT2 --> MT3 --> MT4
    LT1 --> LT2 --> LT3 --> LT4
    
    style LT1 fill:#4caf50
    style LT2 fill:#4caf50
    style LT3 fill:#4caf50
    style LT4 fill:#4caf50
```

## 🎮 **User Journey Flows**

### New User Onboarding

```mermaid
journey
    title New User Journey
    section Discovery
      Learn about Elata: 5: User
      Read documentation: 4: User
      Join community: 5: User
    section First Interaction
      Get ELTA tokens: 3: User
      Try EEG app: 5: User
      Earn first XP: 5: User
    section Engagement
      Participate in funding: 4: User
      Create staking position: 3: User
      Delegate voting power: 3: User
    section Advanced Usage
      Manage multiple positions: 4: User
      Claim staking rewards: 5: User
      Participate in governance: 4: User
```

### Researcher Journey

```mermaid
journey
    title Researcher Journey
    section Proposal Creation
      Identify research need: 5: Researcher
      Create funding proposal: 4: Researcher
      Submit to community: 4: Researcher
    section Community Voting
      Present to community: 4: Researcher
      Community votes with XP: 5: Community
      Results announced: 5: Researcher
    section Funding & Execution
      Receive ELTA funding: 5: Researcher
      Execute research: 5: Researcher
      Publish results: 4: Researcher
    section Impact
      Data benefits community: 5: Community
      Researcher reputation grows: 5: Researcher
      More funding opportunities: 5: Researcher
```

### Developer Integration Journey

```mermaid
journey
    title Developer Integration
    section Setup
      Read documentation: 4: Developer
      Clone repository: 5: Developer
      Run local tests: 5: Developer
    section Integration
      Connect to contracts: 4: Developer
      Implement XP rewards: 4: Developer
      Add staking features: 3: Developer
    section Advanced Features
      Integrate governance: 3: Developer
      Add reward claiming: 4: Developer
      Optimize gas usage: 4: Developer
    section Production
      Deploy to testnet: 4: Developer
      Community testing: 5: Community
      Mainnet launch: 5: Developer
```

## 🔄 **Data Flow Diagrams**

### Complete Protocol Data Flow

```mermaid
flowchart TD
    subgraph "User Actions"
        UA1[Play EEG Games]
        UA2[Submit Data]
        UA3[Stake ELTA]
        UA4[Vote in Rounds]
    end
    
    subgraph "Smart Contract Layer"
        SC1[ElataXP.award()]
        SC2[VeELTA.createLock()]
        SC3[LotPool.vote()]
        SC4[RewardsDistributor.claim()]
    end
    
    subgraph "State Changes"
        ST1[XP Balance Updated]
        ST2[NFT Position Minted]
        ST3[Vote Recorded]
        ST4[Rewards Claimed]
    end
    
    subgraph "Events Emitted"
        EV1[XPAwarded]
        EV2[LockCreated]
        EV3[Voted]
        EV4[RewardClaimed]
    end
    
    subgraph "Frontend Updates"
        FE1[Update XP Display]
        FE2[Show New Position]
        FE3[Update Vote Status]
        FE4[Show Claimed Rewards]
    end
    
    UA1 --> SC1 --> ST1 --> EV1 --> FE1
    UA3 --> SC2 --> ST2 --> EV2 --> FE2
    UA4 --> SC3 --> ST3 --> EV3 --> FE3
    UA4 --> SC4 --> ST4 --> EV4 --> FE4
    
    style SC1 fill:#e8f5e8
    style SC2 fill:#e3f2fd
    style SC3 fill:#f3e5f5
    style SC4 fill:#fff3e0
```

## 🎯 **Performance Analysis**

### Gas Cost Breakdown

```mermaid
graph TD
    subgraph "Contract Deployment"
        CD1[ELTA: 2.3M gas<br/>$46 @ 20 gwei]
        CD2[VeELTA: 3.3M gas<br/>$66 @ 20 gwei]
        CD3[ElataXP: 3.0M gas<br/>$60 @ 20 gwei]
        CD4[LotPool: 1.4M gas<br/>$28 @ 20 gwei]
        CD5[Others: 2.0M gas<br/>$40 @ 20 gwei]
        TOTAL[Total: 13M gas<br/>$260 @ 20 gwei]
    end
    
    CD1 --> TOTAL
    CD2 --> TOTAL
    CD3 --> TOTAL
    CD4 --> TOTAL
    CD5 --> TOTAL
    
    style TOTAL fill:#e8f5e8
```

### Operation Cost Comparison

```mermaid
graph LR
    subgraph "Basic Operations"
        BO1[ELTA Transfer<br/>56K gas]
        BO2[ERC20 Standard<br/>~21K gas]
        BO3[2.7x overhead<br/>Due to voting features]
    end
    
    subgraph "Staking Operations"
        SO1[Create Lock<br/>257K gas]
        SO2[Increase Amount<br/>52K gas]
        SO3[Withdraw<br/>78K gas]
    end
    
    subgraph "Governance Operations"
        GO1[XP Award<br/>230K gas]
        GO2[Vote in Round<br/>86K gas]
        GO3[Claim Rewards<br/>80K gas]
    end
    
    style BO1 fill:#fff3e0
    style SO1 fill:#e3f2fd
    style GO1 fill:#f3e5f5
```

## 🔮 **Future Architecture**

### Planned Integrations

```mermaid
graph TB
    subgraph "Current Protocol"
        CURRENT[Elata Protocol v2.0<br/>Complete Implementation]
    end
    
    subgraph "Phase 3: Ecosystem Integration"
        ZORP_INT[ZORP Integration<br/>Data submission rewards]
        EEG_INT[EEG Hardware<br/>Direct device integration]
        APP_STORE[App Ecosystem<br/>Revenue sharing]
        DATA_MARKET[Data Marketplace<br/>Monetization]
    end
    
    subgraph "Phase 4: Advanced Features"
        CROSS_CHAIN[Cross-chain Bridge<br/>Multi-network support]
        ZK_PRIVACY[ZK Privacy<br/>Anonymous participation]
        AI_MODELS[AI Marketplace<br/>Model monetization]
        MOBILE_SDK[Mobile SDK<br/>Native app integration]
    end
    
    CURRENT --> ZORP_INT
    CURRENT --> EEG_INT
    CURRENT --> APP_STORE
    CURRENT --> DATA_MARKET
    
    ZORP_INT --> CROSS_CHAIN
    EEG_INT --> ZK_PRIVACY
    APP_STORE --> AI_MODELS
    DATA_MARKET --> MOBILE_SDK
    
    style CURRENT fill:#4caf50
    style ZORP_INT fill:#2196f3
    style CROSS_CHAIN fill:#9c27b0
```

---

## 📚 **Documentation Map**

```mermaid
graph TD
    subgraph "User Documentation"
        UD1[README.md<br/>📖 Overview & Quick Start]
        UD2[CONTRIBUTING.md<br/>👥 Developer Guide]
        UD3[FAQ.md<br/>❓ Common Questions]
    end
    
    subgraph "Technical Documentation"
        TD1[ARCHITECTURE.md<br/>🏗️ System Design]
        TD2[DEPLOYMENT.md<br/>🚀 Deployment Guide]
        TD3[FRONTEND_INTEGRATION.md<br/>🖥️ API Reference]
    end
    
    subgraph "Reference Documentation"
        RD1[Contract ABIs<br/>📋 Interface Specs]
        RD2[Gas Reports<br/>⛽ Cost Analysis]
        RD3[Test Coverage<br/>🧪 Quality Metrics]
    end
    
    UD1 --> TD1
    UD2 --> TD2
    UD3 --> TD3
    
    TD1 --> RD1
    TD2 --> RD2
    TD3 --> RD3
    
    style UD1 fill:#e8f5e8
    style TD1 fill:#e3f2fd
    style RD1 fill:#fff3e0
```

---

*This architecture represents a complete, production-ready DeFi protocol designed specifically for neuroscience research coordination and community governance.*

