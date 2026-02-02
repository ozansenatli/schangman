import "dotenv/config";
import express from "express";
import cors from "cors";

import {
  getRefereeAddress,
  commitForPlayer,
  answerGuess,
  revealForPlayer,
  hasBackendGame,
  getBackendGameMeta,
} from "./referee.js";

const app = express();
const PORT = Number(process.env.PORT || 3001);

app.use(cors());
app.use(express.json());

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    refereeAddress: getRefereeAddress(),
    hasGamesInMemory: true,
  });
});

app.post("/commit", async (req, res) => {
  try {
    const { player, length } = req.body;
    const result = await commitForPlayer(player, length);

    res.json({
      ok: true,
      player,
      length: result.length,
      commitHash: result.commitHash,
      txHash: result.txHash,
    });
  } catch (e) {
    res.status(400).json({ ok: false, error: e?.message ?? String(e) });
  }
});

app.post("/guess", async (req, res) => {
  try {
    const { player, letter } = req.body;
    const result = await answerGuess(player, letter);

    res.json({
      ok: true,
      player,
      letter,
      positionsMask: result.positionsMask,
      txHash: result.txHash,
    });
  } catch (e) {
    res.status(400).json({ ok: false, error: e?.message ?? String(e) });
  }
});

app.post("/reveal", async (req, res) => {
  try {
    const { player } = req.body;
    const result = await revealForPlayer(player);

    res.json({
      ok: true,
      player,
      txHash: result.txHash,
    });
  } catch (e) {
    res.status(400).json({ ok: false, error: e?.message ?? String(e) });
  }
});

app.get("/debug/:player", (req, res) => {
  try {
    const player = req.params.player;
    if (!hasBackendGame(player)) {
      return res.status(404).json({ ok: false, error: "No backend game" });
    }
    res.json({ ok: true, meta: getBackendGameMeta(player) });
  } catch (e) {
    res.status(400).json({ ok: false, error: e?.message ?? String(e) });
  }
});

app.listen(PORT, () => {
  console.log(`Referee backend running at http://localhost:${PORT}`);
});