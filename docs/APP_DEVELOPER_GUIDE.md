# App Developer Guide

This guide teaches the Elata protocol to a web developer who is building an app
with `../elata-bio-sdk` and publishing it through `../elata-appstore`.

Start with the first section. Each section adds one layer of detail. You do not
need to understand every contract before you can reason about the product model.

## 1. The One Idea

In a normal app store, a developer usually charges a fixed price or
subscription. Users pay the app store, the app store takes a fee, and the
developer receives the rest.

Elata adds a protocol layer around the app. Instead of only charging a fixed
subscription, an app can optionally launch its own token. Users can buy and sell
that token, and the token price changes as demand changes.

Launching a token is optional. You can register and publish an app without ever
launching a token. In that mode, Elata still gives the app a protocol identity,
owner Safe, metadata, and contributor setup, but you do not turn on the token
market. You can still monetize the app by selling premium content, access, or
in-app items.

A token launch creates a different growth loop:

- Early users can buy the app token.
- If the app becomes more useful or popular, demand for the token can increase.
- Users can become economically aligned with the app instead of only paying for
  access.
- Token holders can stake, participate, earn rewards, or unlock app-specific
  features depending on the app design.
- The token can give the community a shared identity and a reason to coordinate
  around the app's growth.
- Protocol fees can route automatically to contributors and treasury.

The key shift is this:

| Traditional app store | Elata protocol |
|---|---|
| Users pay a fixed app fee | Users can buy an app token with a changing price |
| Users are only customers | Users can become holders, stakers, and early supporters |
| Revenue is paid out by the platform | Revenue is routed by contracts |
| Price is set by the developer | Launch price moves through a bonding curve |
| Community is built outside the payment system | Token ownership can help form the community |
| Growth is mostly marketing-driven | Growth can be helped by early-user incentives |

Your app is still a normal browser app. The protocol is the ownership, launch,
fee, and revenue system around it. The token layer is available when it fits the
app, but it is not required.

## 2. The App And The Protocol Are Separate

Your app is the thing users use:

- HTML, CSS, JavaScript, and assets.
- `../elata-bio-sdk` camera, EEG, BLE, or WASM logic.
- UI, game state, user flows, and product features.
- Any backend APIs you host separately over HTTPS.

The protocol is the shared economic system around the app:

- It records that the app exists.
- It records who controls the app.
- It can launch an app token, if the developer chooses to.
- If a token exists, it can run the token's initial market.
- It can support premium content or item sales.
- It can route fees to contributors and treasury.
- If a token exists, it can support staking, vesting, ecosystem funds, and
  in-app items.

The appstore connects the two. It shows the app listing, hosts or embeds the
browser app, and gives users interfaces for protocol actions such as buying,
staking, claiming, or viewing token status.

## 3. The Main Objects

Learn these first. Most of the protocol is just these objects interacting.

| Object | What it means |
|---|---|
| App record | The canonical on-chain record that says this app exists |
| Owner Safe | The team-controlled admin wallet for the app |
| ELTA | The protocol token used for launch costs and app-token markets |
| App token | Optional token belonging to one app |
| Bonding curve | Optional initial market where users buy the app token |
| Contributor split | The payout contract for app contributors |
| Fee pipeline | The system that collects and routes app/protocol fees |
| Premium content | Paid app content or items that can be sold without launching a token |
| Staking vault | Token-launch contract where app-token holders can stake |
| Vesting wallet | Token-launch contract that unlocks team tokens over time |
| Ecosystem vault | Token-launch bucket for growth, incentives, or operations |

If you remember only one sentence: registering an Elata app creates an app
record, an owner Safe, and a contributor split; launching a token later is
optional.

## 4. The Launch Flow

Elata uses a two-phase launch so an app can exist with or without a token.

### Phase A: Register The App

Registration creates the app's protocol identity.

You provide:

- The owner Safe.
- The app metadata URI.
- Initial contributor information.

The protocol:

- Charges `10 ELTA`.
- Deploys `ContributorSplit`.
- Registers the app in `AppRegistry`.

After Phase A, the app exists in the protocol. You can stop here permanently if
you do not want a token. This is useful when you want the store listing, app
release path, owner Safe, contributor setup, and premium-content sales without
launching a market.

### Phase B: Launch The Token

Token launch is optional. If you choose it, it attaches the app-token economy to
the existing app.

You provide:

- The app ID.
- Token name.
- Token symbol.
- Operators for app modules, if needed.

The protocol:

- Charges `100 ELTA` as the curve seed.
- Deploys the app token.
- Deploys the bonding curve.
- Deploys staking, vesting, and ecosystem vaults.
- Mints and allocates the app token supply.
- Initializes the curve with ELTA and app-token reserves.

Registration-only cost is `10 ELTA`. Full token launch cost is `110 ELTA`:
`10 ELTA` registration plus `100 ELTA` curve seed.

## 5. What Happens To The App Token

Only token-launched apps get an app token. If you never launch a token, this
section does not apply to your app.

Each launched app token has a default supply of `10,000,000`.

| Allocation | Share | Amount | Purpose |
|---|---:|---:|---|
| Bonding curve | `50%` | `5,000,000` | Sold to users through the launch market |
| Team vesting wallet | `25%` | `2,500,000` | Team allocation that unlocks over time |
| Ecosystem vault | `25%` | `2,500,000` | Growth, rewards, operations, or app ecosystem use |

This matters because users are not just buying a subscription. They are buying
part of the app's token economy. The app can then decide how that token fits
into the product: access, rewards, staking, governance, items, tournaments, or
other app-specific behavior.

Tokens can also become community infrastructure. A token gives users a visible
way to belong to the app ecosystem, coordinate around shared goals, and be
recognized as early supporters. That community layer can matter as much as the
payment layer: holders may help test, promote, moderate, create content, organize
events, or bring in other users because they have a stake in the app doing well.

## 6. How The Bonding Curve Works

The bonding curve only exists for apps that launch a token. It is the first
place users buy the app token.

It starts with two reserves:

| Reserve | Initial amount |
|---|---:|
| ELTA | `100 ELTA` |
| App token | `5,000,000` app tokens |

When a user buys:

1. The user sends ELTA to the curve.
2. The curve keeps more ELTA in reserve.
3. The curve releases app tokens to the user.
4. Because fewer app tokens remain in the curve, the next price is higher.

So if demand is high, the token price rises during the launch. This is the
mechanism that rewards earlier participation: early buyers get access to the
curve before later demand has pushed the price up.

The curve has a target:

| Parameter | Value |
|---|---:|
| Graduation target | `42,000 ELTA` in curve reserves |

When the target is reached, the app token graduates.

## 7. What Graduation Means

Graduation moves the app token from the launch curve into a public liquidity
phase.

At graduation:

- A Uniswap V2-style trading pair is created or used.
- Remaining curve assets are added as liquidity.
- LP tokens are locked for `730 days` by default.
- The app is marked as graduated.

In web terms: the token moves from a controlled launch checkout into a broader
market where users can trade through DEX infrastructure.

## 8. How Fees And Revenue Move

Protocol fees are not distributed by frontend code. Contracts account for them
and route them.

The current path is:

```text
App activity -> FeeCollector -> FeeSwapper -> ContributorSplit + Treasury
```

Default routing:

| Fee source | Contributors | Treasury |
|---|---:|---:|
| Launch fee | `0%` | `100%` |
| App revenue fees | `80%` | `20%` |
| Paused app | `0%` | `100%` |

`ContributorSplit` is pull-based: contributors claim what they are owed from the
split contract. Your frontend can show claimable balances, but it should not
pretend revenue distribution is just a normal database update.

## 9. Why Early Users Are Incentivized

Elata is designed to help an app form an early community.

Early users may have several reasons to join:

- They can buy before later demand changes the curve price.
- They can hold the app token if they believe the app will grow.
- They can stake if the app uses staking.
- They can receive rewards or access if the app designs token-based benefits.
- They can identify as part of the app's early community.
- They can invite other users because growth may increase the usefulness of the
  app ecosystem.

The protocol does not magically create demand. The app still needs to be useful.
What the protocol does is make early participation more meaningful than a simple
subscription payment.

## 10. What The Developer Must Decide

Before registration:

- What app metadata should be published?
- Which Safe controls the app?
- Who are the initial contributors?
- Is the browser app platform-hosted or self-hosted?

Before optional token launch:

- Is the app ready for a public token economy?
- What are the token name and symbol?
- Who should operate app modules?
- Does the launch wallet have `100 ELTA` plus gas?
- Does the team understand the token allocation and vesting model?

Before adding token utility:

- Does the token unlock access, rewards, staking, governance, items, or status?
- What can non-token users still do?
- What protocol actions require wallet signatures?
- How will the app explain token risk and transaction costs to users?

Before selling premium content:

- What is paid, and what remains free?
- Is the purchase for one item, recurring access, or a gated experience?
- Does the content need NFT metadata or a simpler appstore release record?
- Where do proceeds route, and are contributor split addresses correct?

## 11. What Your Frontend Should Do

Treat protocol state like external production state that can lag, fail, or be
rejected by the user.

Good frontend behavior:

- Separate "play the app" from "connect wallet".
- Show pending states for wallet transactions.
- Wait for transaction confirmation before showing success.
- Read app/token/curve status before enabling buy, stake, or claim actions.
- Handle users who do not hold the app token.
- Explain when an action costs gas or spends ELTA.
- Keep SDK permission flows clear: camera, EEG, and BLE are browser permissions,
  not protocol permissions.

For appstore deployment, remember that the appstore hosts or embeds browser
content. It does not execute your backend. Upload a static bundle with
`index.html` or provide an embeddable HTTPS URL.

## 12. Deeper Contract Map

Once the mental model is clear, these are the contracts behind it:

| Contract | Role |
|---|---|
| `AppRegistry` | Stores app ownership, metadata, token, curve, and split references |
| `AppFactory` | Runs app registration and token launch |
| `AppToken` | ERC-20 token for one app |
| `AppBondingCurve` | Initial app-token market |
| `AppStakingVault` | Staking surface for app-token holders |
| `AppVestingWallet` | Team vesting allocation |
| `AppEcosystemVault` | Ecosystem allocation |
| `ContributorSplit` | Contributor revenue claims |
| `FeeCollector` | Accounts for collected fees |
| `FeeSwapper` | Routes fees to split and treasury |
| `ElataPoints` | XP/reputation system |

## 13. Plain-English Terms

| Term | Meaning |
|---|---|
| Wallet | A user account that signs blockchain transactions |
| Transaction | A signed request to change protocol state |
| Gas | Network fee paid to run a transaction |
| Safe | Shared team wallet with multiple signers |
| Contract | On-chain program with persistent public state |
| ERC-20 | Standard fungible token type |
| ERC-721 | Standard NFT type |
| Metadata URI | Link to JSON describing an app, token, or NFT |
| Treasury | Protocol-controlled revenue destination |
| Vesting | Tokens unlock over time instead of all at once |
| Liquidity | Assets available for token trading |
| LP token | Receipt representing DEX liquidity |

## Related Docs

- [APP_LAUNCH_GUIDE.md](./APP_LAUNCH_GUIDE.md): contract-level launch flow.
- [PROTOCOL_SUMMARY.md](./PROTOCOL_SUMMARY.md): constants and equations.
- [TOKENOMICS.md](./TOKENOMICS.md): deeper economic design.
- [NFT_METADATA.md](./NFT_METADATA.md): metadata for in-app content.
- `../elata-appstore/docs/APP_UPLOAD_RUNTIME_CRITERIA.md`: upload and runtime
  rules.
- `../elata-bio-sdk/docs/guides/getting-started.md`: SDK onboarding.
