# Elata Protocol Summary

This document defines the current protocol behavior from deployed contracts and tests.

## One-Sentence Summary

Elata is a permissionless app-launch protocol where app tokens are sold on a constant-product ELTA bonding curve, then routed into a fee pipeline that sends launch fees to treasury and app revenue to contributor splits plus treasury.

## One-Paragraph Summary

An app launch costs `110 ELTA` (`100` seed + `10` launch fee). `AppFactory` deploys an app stack (`AppToken`, `AppBondingCurve`, `AppStakingVault`, `AppVestingWallet`, `AppEcosystemVault`) and mints exactly `10,000,000` app tokens split `50%` curve, `25%` vesting wallet, `25%` ecosystem vault. The curve follows $x\,y=k$, supports buys while active, and graduates at `42,000 ELTA` (or can be force-graduated at deadline), creating a Uniswap V2 pair with LP locked for `730 days`. Trading and LP-keyed transfer taxes flow through `FeeCollector` and `FeeSwapper`: `LAUNCH_FEE` routes `100%` to treasury, while app-revenue fee kinds route to contributor split + treasury (default `80/20`, governance-configurable). ELTA has a fixed `77,000,000` supply cap minted at deployment, veELTA lock boost ranges from `1x` to `2x`, and XP gates early buys by default (`100 XP` for first `6 hours`).

---

## System of Equations

### 1. Bonding Curve

Constant product invariant (reserves $x$ for ELTA, $y$ for the app token):

$$k = x\,y = r_{\text{ELTA}}\,r_{\text{APP}}.$$

Default initialization:

$$
r_{\text{ELTA},0} = 100\,\text{ELTA},\qquad
r_{\text{APP},0} = 5{,}000{,}000\,\text{APP},\qquad
k_0 = r_{\text{ELTA},0}\,r_{\text{APP},0}.
$$

One buy: user sends $e$ ELTA in (before fees; see §2 for fee-on-top). New reserves and token output:

$$
\begin{aligned}
r'_{\text{ELTA}} &= r_{\text{ELTA}} + e, \\
r'_{\text{APP}} &= \frac{k}{r'_{\text{ELTA}}}, \\
\Delta_{\text{APP}} &= r_{\text{APP}} - r'_{\text{APP}}.
\end{aligned}
$$

Spot price in ELTA per APP (continuous approximation):

$$\text{price} \approx \frac{r_{\text{ELTA}}}{r_{\text{APP}}}.$$

### 2. Bonding-Curve Trading Fee

Base trade fee with basis points $b$ from `AppFeeRouter.feeBps()` (default $b=100$):

$$
f = \frac{e\,b}{10{,}000},
\qquad
C = e + f,
$$

where $e=\texttt{actualEltaIn}$, $f=\texttt{tradingFee}$, and $C=\texttt{buyerPays}$.

Optional sniper add-on (default off): if enabled and the block time is still inside the sniper window, the effective bps is $b' = b + b_{\text{sniper}}$.

### 3. Token Supply and Launch Allocation

Per-app total supply $S$ and default allocation (by share of $S$):

$$S = 10{,}000{,}000\,\text{APP}, \quad w_{\text{curve}} = \tfrac{1}{2}, \quad w_{\text{vest}} = w_{\text{eco}} = \tfrac{1}{4}.$$

Conservation of the split:

$$w_{\text{curve}} + w_{\text{vest}} + w_{\text{eco}} = 1, \qquad
w_{\text{curve}}S + w_{\text{vest}}S + w_{\text{eco}}S = S.$$

### 4. Graduation Rules

Target graduation (nominal reserve threshold):

$$r_{\text{ELTA}} \ge 42{,}000\,\text{ELTA} \quad\Rightarrow\quad \text{graduate}.$$

Forced graduation when the curve is past the maximum duration and not already finished:

$$T_{\text{deadline}} = t_{\text{activation}} + T_{\text{maxCurve}}.$$

$$t \ge T_{\text{deadline}} \;\land\; \text{state} \notin \{\text{GRADUATED},\,\text{CANCELLED}\} \;\Rightarrow\; \text{force-graduate}.$$

LP lock (default) after graduation at $t_{\text{grad}}$:

$$t_{\text{LP unlock}} = t_{\text{grad}} + 730\,\text{days}.$$

### 5. veELTA Voting Power

Lock window:

$$T_{\min} = 7\,\text{days}, \qquad T_{\max} = 730\,\text{days}.$$

Boost and voting power for locked amount $L$ and lock duration $\tau$ (with $\tau \le T_{\max}$):

$$
\beta = 1 + \frac{\tau}{T_{\max}},
\qquad
V = L\,\beta,
\qquad
\beta \in [1,\,2].
$$

### 6. Fee Routing Policy (Current V2 Pipeline)

`FeeCollector` tracks pending balances by `(appId, feeKind, asset)` and sweeps to `FeeSwapper`. Let $A$ be the amount swept for a given route, and $p$ the treasury take in bps (`treasuryTakeBps`, default $2000$). Policy:

$$
T(A) =
\begin{cases}
A & \text{paused or } \mathrm{kind} = \texttt{LAUNCH\\_FEE}, \\
A \cdot \dfrac{p}{10{,}000} & \text{otherwise (active app revenue),}
\end{cases}
$$

$$C(A) = A - T(A) \quad \text{(contributor leg, non-launch unpaused only).}$$

The contributor leg is sent to the app’s `ContributorSplit`.

### 7. XP Early Access Gate

Default parameters: minimum XP $X_{\min} = 100$ and early window $T_{\text{early}} = 6\,\text{h}$ after launch. Gate:

$$
\text{if } t < t_{\text{launch}} + T_{\text{early}} \text{, require } \text{XP}(u) \ge X_{\min}.
$$

### 8. LP Transfer Tax

App tokens charge a transfer tax only when one side of the transfer is an allowlisted liquidity pool address (wallet-to-wallet transfers are exempt). For transfer amount $a$ and tax rate $b_{\text{transfer}}$ (default $100$ bps, max $200$ bps):

$$
\text{fee} = \frac{a \cdot b_{\text{transfer}}}{10{,}000}, \qquad b_{\text{transfer}} \in [0,\,200].
$$

The fee is forwarded to `FeeCollector` and enters the standard V2 routing pipeline (§6).

---

## One-Pager

### Tokens

| Token | Role |
|---|---|
| **ELTA** | Protocol base token; fixed supply of `77,000,000`; used to seed and buy from bonding curves, pay launch fees, and lock for governance. |
| **veELTA** | Non-transferable vote-escrowed ELTA; granted by locking ELTA for `7`–`730 days`; boosts voting power `1×`–`2×`. |
| **AppToken** | Per-app ERC-20 minted at launch (`10,000,000` total); sold via the bonding curve, vested to contributors, and held in the ecosystem vault. |

### Core Flow

1. Developer registers app and launches token via `AppFactory`.
2. Pays `10 ELTA` launch fee + `100 ELTA` curve seed.
3. App token (`10,000,000`) is minted as `50/25/25` curve/vesting/ecosystem.
4. Buyers purchase from active bonding curve ($x\,y=k$).
5. Trading fees and LP-keyed transfer taxes accumulate and are swept to `FeeCollector`.
6. `FeeSwapper` routes by fee kind:
   - `LAUNCH_FEE`: `100%` treasury
   - App revenue kinds: default `80%` contributor split / `20%` treasury
7. At `42,000 ELTA` (or deadline), curve graduates to Uniswap LP and locks LP.

### Key Constants (Defaults)

| Parameter | Value |
|---|---|
| ELTA max supply | `77,000,000` |
| App launch total | `110 ELTA` |
| App creation fee | `10 ELTA` |
| Curve seed | `100 ELTA` |
| App token supply | `10,000,000` |
| Curve graduation target | `42,000 ELTA` |
| LP lock duration | `730 days` |
| XP early gate | `100 XP`, first `6h` |
| Base trade fee | `1%` (`100 bps`) |

### Protocol Invariants

- **Curve math:** $k = x\,y$ is preserved on every trade (within integer rounding).
- **State monotonicity:** `PENDING → ACTIVE → GRADUATED` or `PENDING → CANCELLED`; no backward transitions.
- **Transfer tax cap:** $b_{\text{transfer}} \le 200\,\text{bps}$, enforced on-chain.
- **Fee conservation:** $T(A) + C(A) = A$ for any swept amount; routing never creates tokens.
- **ELTA supply:** fixed at $77{,}000{,}000$; no minting after deployment.

---

## Comparison: Elata vs. Virtuals Protocol

Virtuals Protocol is the closest structural analogue to Elata. The two share a constant-product bonding curve, the same 42,000-token graduation threshold, and a veToken governance model — but diverge meaningfully in economics and scope.

| | **Elata** | **Virtuals** |
|---|---|---|
| **Base token** | ELTA (77M fixed, no burn) | VIRTUAL (~1B, deflationary via buyback-burn) |
| **Launch cost** | 110 ELTA (100 seed + 10 fee) | 100 VIRTUAL |
| **Curve type** | Constant-product (xy=k) | Constant-product (xy=k) |
| **Graduation threshold** | 42,000 ELTA | 42,000 VIRTUAL |
| **App/agent token supply** | 10,000,000 | 1,000,000,000 |
| **Token allocation** | 50% curve / 25% vesting / 25% eco vault | All minted at graduation into LP |
| **LP lock** | 730 days (2 yr) | 10 years |
| **veToken governance** | veELTA, 7–730 day lock, 1×–2× boost | veVIRTUAL |
| **Revenue routing** | 80% contributors / 20% treasury | Protocol revenue → buyback & burn |
| **Early-access gate** | XP gate (100 XP, first 6 h) | None |
| **Transfer tax** | LP-keyed, max 200 bps | Not present |
| **Focus** | Permissionless app tokens | AI agent tokenization |

**Key differences:**

- **Revenue model:** Elata routes app revenue to creators (80/20 contributor/treasury split); Virtuals uses protocol revenue to deflate VIRTUAL supply via buyback-and-burn.
- **Pre-graduation allocation:** Elata allocates tokens at launch (vesting wallet + ecosystem vault); Virtuals mints the full agent supply only at graduation.
- **LP lock:** Virtuals locks LP for 10 years; Elata uses 2 years.
- **Supply policy:** ELTA is fixed with no burn mechanism; VIRTUAL is actively deflationary.
- **Access control:** Elata adds an XP-gated early-buy window; Virtuals has no equivalent gate.

---

For deeper contract mapping, see [ARCHITECTURE.md](./ARCHITECTURE.md) and [TOKENOMICS.md](./TOKENOMICS.md).
