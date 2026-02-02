// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Hangman {

    uint8 public constant MIN_LEN = 4;
    uint8 public constant MAX_LEN = 10;
    uint8 public constant MAX_WRONG_GUESSES = 6;

    // The referee must reveal after the game ends (or can reveal immediately after end)
    // within this many seconds, otherwise player can slash the bond.
    uint64 public constant REVEAL_DEADLINE_SECONDS = 30 minutes;

    // Referee posts a bond to discourage griefing/lying.
    uint256 public immutable REFEREE_BOND_WEI;

    address public immutable referee;


    enum Status {
        None,          // no game for player
        WaitingCommit, // started, waiting for referee commitment
        Active,        // referee committed, guesses can be answered
        Won,           // player revealed all letters (per referee responses)
        Lost,          // wrong guesses reached limit
        Forfeit        // referee failed: bond slashed to player
    }

    struct Game {
        Status status;

        uint8 length;
        uint8 wrongGuesses;

        bytes mask; // '_' and revealed letters (length <= 10)

        uint32 guessedMask;  // bitset for letters guessed (a-z)
        uint32 correctMask;  // letters confirmed correct
        uint32 wrongMask;    // letters confirmed wrong

        // For each letter a-z, store the exact positions where it occurs, as a bitmask.
        // Because length <= 10, uint16 is plenty (bits 0..9 used).
        uint16[26] posMaskByLetter;

        // Commitment and bond handling
        bytes32 wordCommit;     // keccak256(player, salt, word)
        uint256 bond;           // referee bond locked for this game
        uint64 revealDeadline;  // timestamp by which referee must reveal after game ends
        bool revealed;          // whether reveal was successfully processed
    }

    mapping(address => Game) private games;

    // ------------------------------------------------------------
    // Events
    // ------------------------------------------------------------

    event GameStarted(address indexed player, uint8 length, bytes mask);
    event WordCommitted(address indexed player, bytes32 commitHash, uint256 bond);
    event RefereeAnswered(address indexed player, bytes1 letter, uint16 positionsMask, bool correct);
    event GameEnded(address indexed player, Status finalStatus);
    event WordRevealed(address indexed player, string word, bytes32 salt);
    event RefereeSlashed(address indexed player, uint256 amount);

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------

    constructor(address _referee, uint256 _bondWei) {
        require(_referee != address(0), "referee = 0");
        require(_bondWei > 0, "bond must be > 0");
        referee = _referee;
        REFEREE_BOND_WEI = _bondWei;
    }

    // ------------------------------------------------------------
    // Public API (player)
    // ------------------------------------------------------------

    function startGame() external {
        Game storage g = games[msg.sender];
        require(g.status != Status.Active && g.status != Status.WaitingCommit, "game already running");

        // reset
        uint8 length = _randomLength();

        g.status = Status.WaitingCommit;
        g.length = length;
        g.wrongGuesses = 0;
        g.guessedMask = 0;
        g.correctMask = 0;
        g.wrongMask = 0;

        for (uint256 i = 0; i < 26; i++) {
            g.posMaskByLetter[i] = 0;
        }

        g.wordCommit = bytes32(0);
        g.bond = 0;
        g.revealDeadline = 0;
        g.revealed = false;

        g.mask = new bytes(length);
        for (uint256 i2 = 0; i2 < length; i2++) {
            g.mask[i2] = bytes1("_");
        }

        emit GameStarted(msg.sender, length, g.mask);
    }

    function getMyGame()
        external
        view
        returns (
            Status status,
            uint8 length,
            uint8 wrongGuesses,
            bytes memory mask,
            uint32 guessedMask,
            uint32 correctMask,
            uint32 wrongMask,
            bytes32 wordCommit,
            uint256 bond,
            uint64 revealDeadline,
            bool revealed
        )
    {
        Game storage g = games[msg.sender];
        return (
            g.status,
            g.length,
            g.wrongGuesses,
            g.mask,
            g.guessedMask,
            g.correctMask,
            g.wrongMask,
            g.wordCommit,
            g.bond,
            g.revealDeadline,
            g.revealed
        );
    }

    // If referee fails to reveal on time, player can slash the bond.
    function claimRefereeForfeit() external {
        Game storage g = games[msg.sender];

        require(g.status == Status.Won || g.status == Status.Lost, "game not ended");
        require(!g.revealed, "already revealed");
        require(g.revealDeadline != 0, "no deadline set");
        require(block.timestamp > g.revealDeadline, "deadline not passed");
        require(g.bond > 0, "no bond");

        uint256 amount = g.bond;
        g.bond = 0;
        g.status = Status.Forfeit;

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "payout failed");

        emit RefereeSlashed(msg.sender, amount);
        emit GameEnded(msg.sender, Status.Forfeit);
    }

    // ------------------------------------------------------------
    // Referee API
    // ------------------------------------------------------------

    // Referee commits to a word off-chain:
    // commit = keccak256(abi.encodePacked(player, salt, word))
    // Referee must attach exactly REFEREE_BOND_WEI.
    function commitWord(address player, bytes32 commitHash) external payable {
        require(msg.sender == referee, "only referee");
        require(msg.value == REFEREE_BOND_WEI, "wrong bond amount");

        Game storage g = games[player];
        require(g.status == Status.WaitingCommit, "not waiting commit");
        require(g.wordCommit == bytes32(0), "already committed");

        g.wordCommit = commitHash;
        g.bond = msg.value;
        g.status = Status.Active;

        emit WordCommitted(player, commitHash, msg.value);
    }

    // Referee answers a guess with the exact positions of the guessed letter:
    // positionsMask bit i = 1 means letter occurs at index i (0-based).
    // positionsMask == 0 => letter is wrong (does not occur).
    function refereeAnswer(address player, bytes1 letter, uint16 positionsMask) external {
        require(msg.sender == referee, "only referee");

        Game storage g = games[player];
        require(g.status == Status.Active, "game not active");

        bytes1 norm = _normalizeLetter(letter);
        uint8 idx = uint8(norm) - 97; // safe because normalize enforces a-z

        uint32 bit = uint32(1) << idx;
        require((g.guessedMask & bit) == 0, "letter already guessed");

        // positionsMask must not have bits beyond length
        require(_positionsMaskFitsLength(positionsMask, g.length), "positions out of range");

        // Mark guessed
        g.guessedMask |= bit;

        bool correct = (positionsMask != 0);

        if (!correct) {
            // wrong: exclude all words containing that letter
            g.wrongMask |= bit;
            g.wrongGuesses += 1;

            if (g.wrongGuesses >= MAX_WRONG_GUESSES) {
                g.status = Status.Lost;
                g.revealDeadline = uint64(block.timestamp + REVEAL_DEADLINE_SECONDS);
                emit GameEnded(player, Status.Lost);
            }
        } else {
            // correct: record exact positions (no extra occurrences allowed)
            // Must be consistent if the referee ever answers the same letter (shouldn't happen due to guessedMask)
            g.correctMask |= bit;
            g.posMaskByLetter[idx] = positionsMask;

            // Consistency checks with existing mask:
            // - must not contradict already revealed letters
            // - must reveal this letter exactly at positionsMask
            for (uint256 i = 0; i < g.length; i++) {
                bool bitSet = ((positionsMask >> i) & 1) == 1;
                bytes1 current = g.mask[i];

                if (current != bytes1("_")) {
                    // already revealed: must match
                    if (bitSet) {
                        require(current == norm, "contradicts revealed letter");
                    } else {
                        require(current != norm, "missing required occurrence");
                    }
                } else {
                    // currently hidden: if bitSet, we reveal now; otherwise keep hidden
                    // also ensure we do not reveal over someone else's letter (impossible since current == '_')
                }
            }

            // Update mask: reveal norm at all positions in positionsMask
            for (uint256 j = 0; j < g.length; j++) {
                if (((positionsMask >> j) & 1) == 1) {
                    g.mask[j] = norm;
                }
            }

            if (!_hasUnrevealed(g.mask)) {
                g.status = Status.Won;
                g.revealDeadline = uint64(block.timestamp + REVEAL_DEADLINE_SECONDS);
                emit GameEnded(player, Status.Won);
            }
        }

        emit RefereeAnswered(player, norm, positionsMask, correct);
    }

    // Referee reveals word+salt. Contract verifies:
    // 1) commitment matches
    // 2) word length matches
    // 3) all recorded constraints (wrong letters + exact positions for correct letters) match this word
    // On success: refund bond to referee.
    // On failure: slash bond to player.
    function revealWord(address player, string calldata word, bytes32 salt) external {
        require(msg.sender == referee, "only referee");

        Game storage g = games[player];

        require(g.status == Status.Won || g.status == Status.Lost, "game not ended");
        require(!g.revealed, "already revealed");
        require(g.wordCommit != bytes32(0), "no commit");
        require(g.bond > 0, "no bond");

        bytes memory w = bytes(word);
        require(w.length == g.length, "length mismatch");

        // verify commitment
        bytes32 recomputed = keccak256(abi.encodePacked(player, salt, word));
        if (recomputed != g.wordCommit) {
            _slashBondToPlayer(player, g);
            revert("commit mismatch");
        }

        // Compute expected positions for each letter based on revealed word
        uint16[26] memory expectedPos;
        for (uint256 i = 0; i < w.length; i++) {
            bytes1 ch = w[i];
            bytes1 norm = _normalizeLetter(ch); // enforces a-z
            uint8 li = uint8(norm) - 97;
            expectedPos[li] |= uint16(1) << uint16(i);
        }

        // Check wrong letters: must have zero occurrences
        for (uint8 li2 = 0; li2 < 26; li2++) {
            uint32 lbit = uint32(1) << li2;

            if ((g.wrongMask & lbit) != 0) {
                require(expectedPos[li2] == 0, "wrong letter occurs");
            }
        }

        // Check correct letters: positions must match exactly
        for (uint8 li3 = 0; li3 < 26; li3++) {
            uint32 lbit2 = uint32(1) << li3;

            if ((g.correctMask & lbit2) != 0) {
                require(expectedPos[li3] == g.posMaskByLetter[li3], "positions mismatch");
            }
        }

        // Optional: ensure current on-chain mask matches the word at revealed positions
        for (uint256 j = 0; j < g.length; j++) {
            if (g.mask[j] != bytes1("_")) {
                require(g.mask[j] == w[j], "mask mismatch");
            }
        }

        // success: refund bond to referee
        g.revealed = true;

        uint256 amount = g.bond;
        g.bond = 0;

        (bool ok, ) = referee.call{value: amount}("");
        require(ok, "refund failed");

        emit WordRevealed(player, word, salt);
    }

    // ------------------------------------------------------------
    // Internal: bond slashing
    // ------------------------------------------------------------

    function _slashBondToPlayer(address player, Game storage g) internal {
        uint256 amount = g.bond;
        g.bond = 0;
        g.status = Status.Forfeit;
        g.revealed = true;

        (bool ok, ) = player.call{value: amount}("");
        require(ok, "slash payout failed");

        emit RefereeSlashed(player, amount);
        emit GameEnded(player, Status.Forfeit);
    }

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------

    function _randomLength() internal view returns (uint8) {
        uint256 span = uint256(MAX_LEN - MIN_LEN + 1);
        uint256 r = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    msg.sender,
                    address(this)
                )
            )
        );
        return uint8(MIN_LEN + (r % span));
    }

    function _hasUnrevealed(bytes memory m) internal pure returns (bool) {
        for (uint256 i = 0; i < m.length; i++) {
            if (m[i] == bytes1("_")) return true;
        }
        return false;
    }

    function _normalizeLetter(bytes1 ch) internal pure returns (bytes1) {
        uint8 c = uint8(ch);

        // A-Z -> a-z
        if (c >= 65 && c <= 90) {
            c += 32;
        }

        require(c >= 97 && c <= 122, "letter must be a-z");
        return bytes1(c);
    }

    function _positionsMaskFitsLength(uint16 mask, uint8 length) internal pure returns (bool) {
        // valid bits are 0..(length-1); so mask must be < 2^length
        // because length <= 10, shifting is safe.
        uint16 limit = uint16(1) << uint16(length);
        return mask < limit;
    }

    receive() external payable {}
}
