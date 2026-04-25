# Elata Protocol Summary

This document defines the current protocol behavior from deployed contracts and tests.

## One-Sentence Summary

Elata is a permissionless app-launch protocol where app tokens are sold on a constant-product ELTA bonding curve, then routed into a fee pipeline that sends launch fees to treasury and app revenue to contributor splits plus treasury.

## One-Paragraph Summary

An app launch costs `110 ELTA` (`100` seed + `10` launch fee). `AppFactory` deploys an app stack (`AppToken`, `AppBondingCurve`, `AppStakingVault`, `AppVestingWallet`, `AppEcosystemVault`) and mints exactly `10,000,000` app tokens split `50%` curve, `25%` vesting wallet, `25%` ecosystem vault. The curve follows $x\,y=k$, supports buys while active, and graduates at `42,000 ELTA` (or can be force-graduated at deadline), creating a Uniswap V2 pair with LP locked for `730 days`. Trading and LP-keyed transfer taxes flow through `FeeCollector` and `FeeSwapper`: `LAUNCH_FEE` routes `100%` to treasury, while app-revenue fee kinds route to contributor split + treasury (default `80/20`, governance-configurable). ELTA has a fixed `77,000,000` supply cap minted at deployment, veELTA lock boost ranges from `1x` to `2x`, and XP gates early buys by default (`100 XP` for first `6 hours`).

---

## System of Equations

Display math below uses [GitHub–flavored LaTeX](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/writing-mathematical-expressions) (`$…$` inline, `$$…$$` block). In PDF or other TeX pipelines, the same expressions compile as usual.

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

$$
T_{\text{deadline}} = t_{\text{activation}} + T_{\text{maxCurve}}, \qquad
\text{if } t \ge T_{\text{deadline}} \text{ and state} \notin \{\text{GRADUATED}, \text{CANCELLED}\} \text{ then force-graduate}.
$$

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
\text{treasury} =
\begin{cases}
A & \text{if app paused or } \text{kind} = \text{LAUNCH\_FEE}, \\[0.4em]
A \cdot \dfrac{p}{10{,}000} & \text{otherwise},
\end{cases}
\qquad
\text{contributors} = A - \text{treasury} \quad \text{(non-launch, unpaused).}
$$

The contributor leg is sent to the app’s `ContributorSplit`.

### 7. XP Early Access Gate

Default parameters: minimum XP $X_{\min} = 100$ and early window $T_{\text{early}} = 6\,\text{h}$ after launch. Gate:

$$
\text{if } t < t_{\text{launch}} + T_{\text{early}} \text{, require } \text{XP}(u) \ge X_{\min}.
$$

---

## One-Pager

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

### Invariants To Preserve

- $k = x\,y$ for curve math (within integer rounding behavior).
- Curve lifecycle is monotonic: `PENDING -> ACTIVE -> GRADUATED` or `PENDING -> CANCELLED`.
- `AppToken.transferFeeBps <= 200 bps`.
- Fee routing never exceeds incoming amount.
- ELTA total supply remains fixed at `77,000,000`.

---

For deeper contract mapping, see [ARCHITECTURE.md](./ARCHITECTURE.md) and [TOKENOMICS.md](./TOKENOMICS.md).
