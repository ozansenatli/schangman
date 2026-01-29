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
        "abbreviate"
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

        emit GameStarted(msg.sender, length, g.mask);
    }

    function guessLetter(string calldata _letter) external {
        Game storage g = games[msg.sender];
        require(g.status == Status.Active, "no active game");

        bytes memory b = bytes(_letter);
        require(b.length == 1, "enter exactly one character");

        bytes1 letter = b[0];
        uint8 c = uint8(letter);

        if (c >= 65 && c <= 90) {
            c += 32;
            letter = bytes1(c);
        }
        require(c >= 97 && c <= 122, "input must be a single letter a-z");

        uint8 idx = c - 97;
        uint32 bit = uint32(1) << idx;

        require((g.guessedMask & bit) == 0, "letter already guessed");

        bytes memory w = _pickRandomCandidate(g);

        g.guessedMask |= bit;

        bool isCorrect = _contains(w, letter);

        if (isCorrect) {
            g.correctMask |= bit;
            for (uint256 i = 0; i < g.length; i++) {
                bytes1 wc = w[i];
                if (_isCorrectLetter(g, wc)) {
                    g.mask[i] = wc;
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

    function getMyGame() external view returns (
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


    // ---------- Constraints ----------
    
    function _matchesConstraints(Game storage g, bytes memory w) internal view returns (bool) {
        if (w.length != g.length) return false;

        for (uint256 i = 0; i < g.length; i++) {
            bytes1 wc = w[i];
            bytes1 mc = g.mask[i];

            if (_isWrongLetter(g, wc)) return false;

            if (mc != bytes1("_")) {
                if (wc != mc) return false;
            } else {
                if (_isCorrectLetter(g, wc)) return false;
            }
        }
        return true;
    }

    function _pickRandomCandidate(Game storage g) internal view returns (bytes memory) {
        uint256 count = _countCandidates(g);
        require(count > 0, "no valid words");

        uint256 r = _rand(count);

        uint256 seen = 0;
        for (uint256 i = 0; i < DICT.length; i++) {
            bytes memory w = bytes(DICT[i]);
            if (!_matchesConstraints(g, w)) continue;

            if (seen == r) {
                return w;
            }
            seen++;
        }
        revert("candidate selection failed");
    }

    function _countCandidates(Game storage g) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < DICT.length; i++) {
            bytes memory w = bytes(DICT[i]);
            if (_matchesConstraints(g, w)) {
                count++;
            }
        }
        return count;
    }


    // ---------- Helpers ----------
    function _randomLength() internal view returns (uint8) {
        uint256 span = uint256(MAX_LEN - MIN_LEN + 1);
        uint256 r = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp, msg.sender)));
        return uint8(MIN_LEN + (r % span));
    }

    function _rand(uint256 modulo) internal view returns (uint256) {
        // pseudo-random: OK for class project, not secure for production
        return uint256(
            keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp, msg.sender))) % modulo;
    }

    function _isCorrectLetter(Game storage g, bytes1 c) internal view returns (bool) {
        uint8 uc = uint8(c);
        if (uc < 97 || uc > 122) return false;
        uint8 idx = uc - 97;
        return (g.correctMask & (uint32(1) << idx)) != 0;
    }

    function _isWrongLetter(Game storage g, bytes1 c) internal view returns (bool) {
        uint8 uc = uint8(c);
        if (uc < 97 || uc > 122) return false;
        uint8 idx = uc - 97;
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