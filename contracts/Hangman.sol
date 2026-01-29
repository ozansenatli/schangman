// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Hangman {
    // ---------- State Variables ----------
    enum Status { None, Active, Won, Lost }

    struct Game {
        Status status;
        uint8 length;
        uint8 wrongGuesses;
        bytes mask;
        uint32 guessedMask;
        uint32 correctMask;
        uint32 wrongMask;
    }

    // One game per player address
    mapping(address => Game) private games;

    uint8 public constant MIN_LEN = 4;
    uint8 public constant MAX_LEN = 10;
    uint8 public constant MAX_WRONG_GUESSES = 6;


    // ---------- Dictionary (Demo) ----------
    // TODO: Change dictionary
    string[] private DICT = [
        // ---- 4 letters ----
        "game",
        "node",
        "hash",
        "byte",
        "mask",
        "code",

        // ---- 5 letters ----
        "block",
        "chain",
        "token",
        "miner",
        "guess",
        "solve",

        // ---- 6 letters ----
        "wallet",
        "ledger",
        "crypto",
        "nonce",
        "sender",
        "verify",

        // ---- 7 letters ----
        "account",
        "balance",
        "storage",
        "compile",
        "execute",
        "network",

        // ---- 8 letters ----
        "contract",
        "function",
        "variable",
        "modifier",
        "overflow",
        "gaslimit",

        // ---- 9 letters ----
        "immutable",
        "consensus",
        "blocktime",
        "signature",
        "deployment",
        "interface",

        // ---- 10 letters ----
        "transaction",
        "constraints",
        "programmer",
        "validation",
        "calldatax",
        "eventloggg"
    ];


    // ---------- Events ----------
    event GameStarted(
        address indexed player,
        uint8 length, 
        bytes mask);

    event LetterGuessed(
        address indexed player,
        bytes1 letter,
        bool correct,
        bytes mask,
        uint8 wrongGuesses,
        Status status);

    
    // ---------- Public API ----------
    function startGame() external {
        Game storage g = games[msg.sender];

        require(g.status != Status.Active, "game already active");

        uint8 length = _randomLength();
        
        g.status = Status.Active;
        g.length = length;
        g.wrongGuesses = 0;
        g.guessedMask = 0;
        g.correctMask = 0;
        g.wrongMask = 0;

        g.mask = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            g.mask[i] = bytes1("_");
        }

        emit GameStarted
        (msg.sender, 
        length, 
        g.mask);
    }

    function guessLetter(bytes1 letter) external {
        Game storage g = games[msg.sender];
        require(g.status == Status.Active, "no active game");

        uint8 idx = _letterIndex(letter);
        uint32 bit = uint32(1) << idx;

        require((g.guessedMask & bit) == 0, "letter already guessed");
        g.guessedMask |= bit;

        (bytes memory w, bool found) = _findCandidate(g);
        require(found, "no valid words");

        bool isCorrect = _contains(w, letter);

        if (isCorrect) {
            g.correctMask |= bit;
            for (uint256 i = 0; i < g.length; i++) {
                bytes1 c = w[i];
                if (_isCorrectLetter(g, c)) {
                    g.mask[i] = c;
                } else {
                    g.mask[i] = bytes1("_");
                }
            }

            if (!_hasUnrevealed(g.mask)) {
                g.status = Status.Won;
            }
        } else {
            g.wrongMask |= bit;
            g.wrongGuesses += 1;

            if (g.wrongGuesses >= MAX_WRONG_GUESSES) {
                g.status = Status.Lost;
            }
        }

        emit LetterGuessed(
            msg.sender,
            letter,
            isCorrect,
            g.mask,
            g.wrongGuesses,
            g.status
        );

    }

    function getMyGame() external view returns(
        Status status,
        uint8 length,
        uint8 wrongGuesses,
        bytes memory mask,
        uint32 guessedMask,
        uint32 correctMask,
        uint32 wrongMask
    ) {
        Game storage g = games[msg.sender];
        return (
            g.status,
            g.length,
            g.wrongGuesses,
            g.mask,
            g.guessedMask,
            g.correctMask,
            g.wrongMask
        );
    }


    // ---------- Constraint Solver ----------
    function _findCandidate(Game storage g) internal view returns (
        bytes memory word,
        bool found
    ) {
        for (uint256 i = 0; i < DICT.length; i++) {
            bytes memory w = bytes(DICT[i]);
            if (w.length != g.length) continue;

            if (_matchesConstraints(g, w)){
                return (w, true);
            }
        }
        return ("", false);
    }

    function _matchesConstraints(Game storage g, bytes memory w) internal view returns (bool) {
        for (uint256 i = 0; i < g.length; i++) {
            bytes1 wc = w[i];
            bytes1 mc = g.mask[i];

            if (mc != bytes1("_")){
                if (wc != mc) return false;
            } else {
                if (_isCorrectLetter(g, wc)) return false;
            }

            if (_isWrongLetter(g, wc)) return false;
        }
        return true;
    }


    // ---------- Helpers ----------
    function _randomLength() internal view returns (uint8) {
        uint256 span = uint256(MAX_LEN - MIN_LEN + 1);
        uint256 r = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp, msg.sender)));
        return uint8(MIN_LEN + (r % span));
    }

    function _letterIndex(bytes1 letter) internal pure returns (uint8) {
        uint8 c = uint8(letter);
        require(c >= 97 && c <= 122, "input must be a letter a-z");
        return c - 97;
    }

    function _isCorrectLetter(Game storage g, bytes1 c) internal view returns (bool) {
        uint8 idx = uint8(c) - 97;
        if (idx > 25) return false;
        return (g.correctMask & (uint32(1) << idx)) != 0;
    }

    function _isWrongLetter(Game storage g, bytes1 c) internal view returns (bool) {
        uint8 idx = uint8(c) - 97;
        if (idx > 25) return false;
        return (g.wrongMask & (uint32(1) << idx)) != 0;
    }

    function _contains(bytes memory w, bytes1 letter) internal pure returns (bool) {
        for (uint256 i = 0; i < w.length; i++) {
            if (w[i] == letter) return true;
        }
        return false;
    }

    function _hasUnrevealed(bytes memory m) internal pure returns (bool) {
        for (uint256 i = 0; i < m.length; i++) {
            if (m[i] == bytes1("_")) return true;
        }
        return false;
    }
}
