# 🪓 Dynamic Hangman on Ethereum

A **smart-contract-based Hangman game** implemented in Solidity, inspired by a *dynamic* Hangman variant where **no fixed word is chosen upfront**.  
Instead, the game maintains a **set of all words still consistent with the player’s guesses**, guaranteeing fairness and determinism on-chain.

---

## 📌 Project Idea

Traditional Hangman secretly selects a word at the start of the game.  
This is **incompatible with blockchains**, because:

- Smart contracts are **fully transparent**
- There is **no true randomness**
- Secrets cannot be kept on-chain

### ✅ Our Solution: Dynamic Hangman

We implement a **constraint-based Hangman**:

- No word is fixed initially
- The contract only tracks:
  - word length
  - revealed letters (mask)
  - rejected letters
  - number of wrong guesses
- After each guess, the set of **possible valid words shrinks**
- Any remaining word consistent with all guesses is valid

> The game is fair because **the contract never lies** — it only enforces logical constraints.

This design is inspired by the provided Python demo, which separates:
- **off-chain word filtering**
- **on-chain game logic**

---

## 🧠 Core Concept (from the Python Demo)

The Python demo works as follows:

1. Start with a random word length
2. Maintain:
   - `_ _ _ _` word mask
   - set of correct letters
   - set of wrong letters
3. On each guess:
   - filter all words matching the constraints
   - pick *any* valid word
   - update the mask or wrong guesses

### Solidity adaptation

On-chain we **do not pick a random word**.  
Instead, we:

- Store a **fixed dictionary**
- Maintain **constraints only**
- Ensure that:
  - all future states remain logically consistent
  - the player cannot force contradictions

---

## 🔗 Smart Contract Scope

### What the Smart Contract Does

- Manages **game state per player**
- Validates guesses (`a`–`z`, no duplicates)
- Tracks:
  - word length
  - revealed positions
  - correct letter set
  - wrong letter set
  - wrong guess counter
- Determines:
  - win condition
  - loss condition
- Emits events for frontend updates

### What the Smart Contract Does NOT Do

- No hidden secrets
- No randomness
- No large-scale computation
- No file access
- No regex or dynamic memory allocation

---

## ⚠️ Blockchain & Solidity Constraints

### Transparency
- All game state is public
- No secret word can exist

### Determinism
- Same inputs → same state transition
- No `block.timestamp` logic for gameplay
- No randomness

### Gas Costs
- Dictionary size must be **small**
- Filtering logic must be **gas-efficient**
- Prefer:
  - bitmasks
  - fixed-size arrays
  - `bytes` over `string`

### Immutability
- Contract logic cannot be changed after deployment
- Bugs are permanent

---

## 🧩 Architecture Overview

### On-Chain (Solidity)
- Game state
- Guess validation
- Constraint enforcement
- Win/loss logic

### Off-Chain
- Frontend (UI)
- Optional helper logic (display, UX)
- No trust-sensitive logic

---

## 🗂️ Repository Structure

dynamic-hangman/  
│  
├── contracts/  
│ └── Hangman.sol # Solidity smart contract  
│  
├── frontend/  
│ ├── src/  
│ │ ├── App.tsx # Main UI (Lovable / React)  
│ │ ├── components/  
│ │ └── hooks/  
│ └── public/  
│  
├── scripts/  
│ └── deploy.ts # Deployment script (optional)  
│  
├── demo/  
│ └── hangman_demo.py # Original Python reference implementation  
│  
├── wordlists/  
│ └── words.txt # Small dictionary (used to generate Solidity list)  
│  
└── README  

---

## 🛠️ Smart Contract Design (Planned)

### State Variables (per game)

- `uint8 wordLength`
- `uint8 wrongGuesses`
- `bytes mask` (`_a__`)
- `uint32 guessedMask` (bitmask for a–z)
- `Status gameStatus`

### Core Functions

- `startGame(uint8 length)`
- `guessLetter(bytes1 letter)`
- `getMask() view`
- `getWrongGuesses() view`
- `getGameStatus() view`

### Events

- `GameStarted`
- `LetterGuessed`
- `GameWon`
- `GameLost`

---

## 🧪 Development Roadmap

### Phase 1 – Analysis
- [x] Implement dynamic Hangman in Python
- [x] Identify on-chain compatible logic
- [x] Define constraints and state model

### Phase 2 – Smart Contract
- [ ] Implement Solidity contract
- [ ] Encode dictionary efficiently
- [ ] Add events and validations
- [ ] Test in Remix VM

### Phase 3 – Frontend (Lovable)
- [ ] Minimal UI:
  - start game
  - display mask
  - guess letters
- [ ] Connect to contract via wallet
- [ ] Show events and game state

### Phase 4 – Testing & Refinement
- [ ] Edge cases
- [ ] Gas optimization
- [ ] UI polish

---

## 🎨 Frontend Plan (Lovable)

The frontend will be intentionally simple:

- Letter buttons (`A–Z`)
- Word mask display (`_ A _ _`)
- Hangman stage visualization
- Wrong guess counter
- Win / loss messages

The frontend:
- **never decides game logic**
- only **reads contract state**
- only **submits guesses**

---

## 🎯 Learning Goals

This project demonstrates:

- How to design games for **fully transparent systems**
- How to translate **off-chain logic into on-chain constraints**
- Solidity state-machine thinking
- Separation of concerns between blockchain and UI