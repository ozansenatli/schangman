# Schangman – Smart Contract Hangman with Referee Backend

Schangman is a blockchain-based variant of the Hangman game implemented as an Ethereum smart contract, combined with an off-chain **referee backend**.  
The smart contract enforces game rules and stores all public game state on-chain, while the referee backend privately selects words, answers guesses, and later proves correctness via a cryptographic commitment.

This design avoids storing secret words on-chain while keeping the game **verifiable, trust-minimized, and censorship-resistant**.

---


### Components

- **Smart Contract (Solidity)**
  - Holds all game state
  - Enforces rules (guesses, win/loss, bond slashing)
  - Verifies referee honesty using commitments
- **Referee Backend (Node.js + ethers.js)**
  - Privately selects a word
  - Commits to the word hash on-chain
  - Answers guesses with exact letter positions
  - Reveals word + salt at the end
- **Frontend**
  - Calls `startGame` and displays game state
  - Sends guesses
  - Triggers backend endpoints
  - (Implemented separately by another team member)

---

## Game Flow

1. **Player starts game**
   - Calls `startGame()` on the smart contract
   - Contract chooses a random word length (4–10)

2. **Referee commits**
   - Backend selects a secret word of that length
   - Computes commitment:  
     `keccak256(player, salt, word)`
   - Calls `commitWord()` with a bond (stake)

3. **Gameplay**
   - Player guesses letters
   - Backend answers each guess with:
     - exact positions (bitmask), or
     - confirmation that the letter is absent
   - Contract updates mask and counts wrong guesses

4. **Game ends**
   - Player wins (all letters revealed) or loses (too many wrong guesses)

5. **Reveal & verification**
   - Backend reveals word + salt
   - Contract verifies:
     - commitment correctness
     - consistency with all previous answers
   - Bond refunded if honest, slashed if cheating or timeout

---