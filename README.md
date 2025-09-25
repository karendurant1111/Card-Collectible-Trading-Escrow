# 🎴 Card Collectible Trading Escrow

> A secure, decentralized escrow system for trading collectible cards on the Stacks blockchain

[![Clarity](https://img.shields.io/badge/Clarity-3.0-blue.svg)](https://clarity-lang.org/)
[![Stacks](https://img.shields.io/badge/Stacks-Blockchain-orange.svg)](https://stacks.co/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 📋 Overview

The Card Collectible Trading Escrow is a sophisticated smart contract that enables secure peer-to-peer trading of collectible cards with built-in escrow functionality. The contract ensures safe exchanges by requiring deposits from both parties and implementing a confirmation system before finalizing trades.

## ✨ Features

- 🔒 **Secure Escrow System**: Deposits are held in escrow until trade completion
- 🎯 **Dual Confirmation**: Both parties must confirm before trade finalization
- ⏰ **Time-based Expiration**: Trades automatically expire after 144 blocks (~24 hours)
- 🛡️ **Dispute Resolution**: Built-in mechanism for resolving trade disputes
- 💰 **Fee Collection**: Configurable contract fees for platform sustainability
- 📊 **Card Registration**: Comprehensive card metadata tracking
- 🔄 **Trade States**: Clear trade lifecycle management
- 💳 **Balance Management**: Integrated STX balance tracking

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- [Node.js](https://nodejs.org/) v16+ for testing
- Stacks wallet for deployment

### Installation

1. Clone the repository:
```bash
git clone https://github.com/your-username/Card-Collectible-Trading-Escrow.git
cd Card-Collectible-Trading-Escrow
```

2. Check contract syntax:
```bash
clarinet check
```

3. Run tests:
```bash
npm install
npm test
```

## 📖 Usage Guide

### 1. Card Registration 🏷️

Before trading, users must register their cards:

```clarity
(contract-call? .Card-Collectible-Trading-Escrow register-card
  u1                    ;; card-id
  "Charizard"           ;; card-name
  "Rare"                ;; rarity
  "Pokemon Base Set"    ;; collection
  "Near Mint"           ;; condition
  u50000000             ;; value in microSTX
)
```

### 2. Fund Your Account 💰

Deposit STX into the contract for trading:

```clarity
(contract-call? .Card-Collectible-Trading-Escrow deposit-funds u10000000) ;; 10 STX
```

### 3. Initiate a Trade 🤝

Start a new trade with another user:

```clarity
(contract-call? .Card-Collectible-Trading-Escrow initiate-trade
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7  ;; counterparty
  u1                                            ;; your card-id
  u2                                            ;; their card-id
  u5000000                                      ;; deposit amount
)
```

### 4. Accept a Trade ✅

As the counterparty, accept an incoming trade:

```clarity
(contract-call? .Card-Collectible-Trading-Escrow accept-trade
  u1        ;; trade-id
  u5000000  ;; your deposit amount
)
```

### 5. Confirm Trade Completion ✔️

Both parties must confirm to complete the trade:

```clarity
(contract-call? .Card-Collectible-Trading-Escrow confirm-trade u1) ;; trade-id
```

### 6. Dispute Resolution ⚖️

If issues arise, create a dispute:

```clarity
(contract-call? .Card-Collectible-Trading-Escrow create-dispute
  u1                           ;; trade-id
  "Card condition misrepresented" ;; reason
)
```

## 📊 Trade States

| State | Description |
|-------|-------------|
| `pending` | Trade initiated, waiting for counterparty acceptance |
| `active` | Both parties deposited, waiting for confirmations |
| `completed` | Trade successfully completed |
| `cancelled` | Trade cancelled by initiator |
| `disputed` | Dispute raised, awaiting resolution |
| `resolved` | Dispute resolved by contract owner |

## 🔧 Contract Functions

### Public Functions

- `register-card` - Register a new collectible card
- `deposit-funds` - Deposit STX into your account
- `withdraw-funds` - Withdraw STX from your account
- `initiate-trade` - Start a new trade
- `accept-trade` - Accept an incoming trade
- `confirm-trade` - Confirm trade completion
- `cancel-trade` - Cancel a pending trade
- `create-dispute` - Raise a trade dispute
- `resolve-dispute` - Resolve a dispute (owner only)
- `set-card-tradeable` - Toggle card trading status
- `update-contract-fee` - Update fee rate (owner only)
- `withdraw-fees` - Withdraw collected fees (owner only)

### Read-Only Functions

- `get-trade` - Get trade details
- `get-card-info` - Get card information
- `get-card-owner` - Get card owner
- `get-user-balance` - Get user's STX balance
- `get-dispute` - Get dispute details
- `get-contract-stats` - Get contract statistics

## 🛠️ Configuration

### Constants

- **Trade Timeout**: 144 blocks (~24 hours)
- **Minimum Escrow Fee**: 1,000 microSTX
- **Default Fee Rate**: 1% (100 basis points)

### Error Codes

| Code | Description |
|------|-------------|
| u1001 | Not authorized |
| u1002 | Already exists |
| u1003 | Not found |
| u1004 | Invalid state |
| u1005 | Insufficient funds |
| u1006 | Expired |
| u1007 | Not expired |
| u1008 | Invalid amount |
| u1009 | Same trader |

## 🧪 Testing

Run the test suite:

```bash
npm test
```

Generate coverage report:

```bash
npm run test:coverage
```

## 🏗️ Development

### Project Structure

```
├── contracts/
│   └── Card-Collectible-Trading-Escrow.clar
├── tests/
│   └── Card-Collectible-Trading-Escrow_test.ts
├── settings/
│   └── Devnet.toml
├── Clarinet.toml
├── package.json
└── README.md
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## 🔐 Security Considerations

- All trades require deposits from both parties
- Time-based expiration prevents indefinite locks
- Dispute resolution system for edge cases
- Owner-only administrative functions
- Input validation for all public functions

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Support

For questions, issues, or contributions:

- Open an issue on GitHub
- Join our Discord community
- Follow us on Twitter [@YourProject](https://twitter.com/yourproject)

## 🙏 Acknowledgments

- Built with [Clarinet](https://github.com/hirosystems/clarinet)
- Powered by [Stacks Blockchain](https://stacks.co/)
- Inspired by the collectible card trading community

---

**Happy Trading!** 🎴✨

