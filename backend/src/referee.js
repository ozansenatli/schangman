// backend/src/referee.js
import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { DICT } from "./dictionary.js";

// -------------------------
// Resolve __dirname in ES modules
// -------------------------
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// -------------------------
// Load env
// (index.js already imports "dotenv/config", so process.env is populated)
// -------------------------
const RPC_URL = process.env.RPC_URL;
const REFEREE_PRIVATE_KEY = process.env.REFEREE_PRIVATE_KEY;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
const BOND_WEI = process.env.BOND_WEI;

if (!RPC_URL || !REFEREE_PRIVATE_KEY || !CONTRACT_ADDRESS || !BOND_WEI) {
  throw new Error(
    "Missing env vars in referee.js. Need RPC_URL, REFEREE_PRIVATE_KEY, CONTRACT_ADDRESS, BOND_WEI."
  );
}

let BOND_WEI_BIGINT;
try {
  BOND_WEI_BIGINT = BigInt(BOND_WEI);
} catch {
  throw new Error("BOND_WEI must be an integer string (wei), e.g. 1000000000000000");
}

// -------------------------
// ABI + Ethers setup
// -------------------------
const abiPath = path.join(__dirname, "..", "abi", "Hangman.json");
const artifact = JSON.parse(fs.readFileSync(abiPath, "utf8"));

// Support either:
// 1) ABI array directly: [ { "type": "function", ... }, ... ]
// 2) Artifact json: { "abi": [ ... ], "bytecode": "...", ... }
const ABI = Array.isArray(artifact) ? artifact : artifact.abi;
if (!ABI) {
  throw new Error("backend/abi/Hangman.json must be an ABI array or contain an `abi` field");
}

const provider = new ethers.JsonRpcProvider(RPC_URL);
const refereeWallet = new ethers.Wallet(REFEREE_PRIVATE_KEY, provider);
const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, refereeWallet);

// -------------------------
// In-memory store
// playerLower -> { word, saltHex, length, commitHash }
// -------------------------
const games = new Map();

// -------------------------
// Utility / helpers
// -------------------------
export function getRefereeAddress() {
  return refereeWallet.address;
}

export function normalizeLetter(letter) {
  if (typeof letter !== "string" || letter.length !== 1) {
    throw new Error("Letter must be exactly one character");
  }
  const l = letter.toLowerCase();
  if (l < "a" || l > "z") throw new Error("Letter must be a-z");
  return l;
}

export function pickWordOfLength(length) {
  const list = DICT[length];
  if (!list || list.length === 0) {
    throw new Error(`No dictionary words for length ${length}`);
  }
  const i = Math.floor(Math.random() * list.length);
  return list[i];
}

export function computeCommitHash(player, saltHex, word) {
  // Must match Solidity: keccak256(abi.encodePacked(player, salt, word))
  return ethers.keccak256(
    ethers.solidityPacked(["address", "bytes32", "string"], [player, saltHex, word])
  );
}

export function letterToBytes1(letterLowercase) {
  // "a" -> 0x61
  const code = letterLowercase.charCodeAt(0); // 97..122
  return "0x" + code.toString(16).padStart(2, "0");
}

export function computePositionsMask(word, letterLowercase) {
  let mask = 0;
  for (let i = 0; i < word.length; i++) {
    if (word[i] === letterLowercase) {
      mask |= 1 << i;
    }
  }
  return mask; // fits uint16 for length <= 10
}

// -------------------------
// Game lifecycle (backend-side)
// -------------------------

/**
 * Creates a secret word+salt for a player and commits on-chain.
 * Returns { commitHash, txHash, length }.
 */
export async function commitForPlayer(player, length) {
  if (!ethers.isAddress(player)) throw new Error("Invalid player address");

  const len = Number(length);
  if (!Number.isInteger(len) || len < 4 || len > 10) {
    throw new Error("Invalid length (must be integer 4..10)");
  }

  const word = pickWordOfLength(len);
  const saltHex = ethers.hexlify(ethers.randomBytes(32));
  const commitHash = computeCommitHash(player, saltHex, word);

  // Store off-chain secret
  games.set(player.toLowerCase(), { word, saltHex, length: len, commitHash });

  // Send on-chain commit (must attach bond)
  const tx = await contract.commitWord(player, commitHash, {
    value: BOND_WEI_BIGINT,
  });
  const receipt = await tx.wait();

  return {
    commitHash,
    txHash: receipt.hash,
    length: len,
  };
}

/**
 * Answers one guess for a player on-chain (refereeAnswer).
 * Returns { positionsMask, txHash }.
 */
export async function answerGuess(player, letter) {
  if (!ethers.isAddress(player)) throw new Error("Invalid player address");

  const key = player.toLowerCase();
  const g = games.get(key);
  if (!g) throw new Error("No backend game for player. Call /commit first.");

  const l = normalizeLetter(letter);
  const positionsMask = computePositionsMask(g.word, l);
  const letterBytes1 = letterToBytes1(l);

  const tx = await contract.refereeAnswer(player, letterBytes1, positionsMask);
  const receipt = await tx.wait();

  return {
    positionsMask,
    txHash: receipt.hash,
  };
}

/**
 * Reveals the secret word+salt on-chain after the game ended (Won/Lost).
 * Returns { txHash }.
 */
export async function revealForPlayer(player) {
  if (!ethers.isAddress(player)) throw new Error("Invalid player address");

  const key = player.toLowerCase();
  const g = games.get(key);
  if (!g) throw new Error("No backend game for player. Call /commit first.");

  const tx = await contract.revealWord(player, g.word, g.saltHex);
  const receipt = await tx.wait();

  return { txHash: receipt.hash };
}

// -------------------------
// Debug helpers (no secrets)
// -------------------------
export function hasBackendGame(player) {
  if (!player) return false;
  return games.has(String(player).toLowerCase());
}

export function getBackendGameMeta(player) {
  const g = games.get(String(player).toLowerCase());
  if (!g) return null;
  return { length: g.length, commitHash: g.commitHash };
}