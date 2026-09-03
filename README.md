# SOTA (beta) — State of the Art

The NFT collection Sota Minds is built to seed: one token per researcher who
pushed AI's state of the art. **Beta — names, symbols, and mechanisms will
change.**

A token is a **researcher + a set of modifiers**. The modifiers are the
interesting part — rarity, era, awards, and whatever mechanisms governance
adds — and they drive the artwork. The image is **not stored on-chain**: it
comes from an external render service that is handed the token's modifiers.

## The image-service architecture

```
  SOTA contract  ──(researcher, modifiers[])──►  metadata service  ──►  render service
  (source of truth)                              (this repo, /meta)      (a designer builds)
```

1. The **contract** stores each token's `researcher`, `thesis`, and
   `modifiers[]`, and exposes them via `seatInfo(id)` / `modifiersOf(id)`.
   Two service URLs live on-chain and are swappable by the owner:
   `metadataBase` and `imageService`.
2. `tokenURI(id) = metadataBase + id` points at a **metadata service** that
   reads the token from chain and returns ERC-721 JSON.
3. That JSON's `image` is the **render service** called with the token's
   modifiers, e.g.
   `https://render.sota.freysa.dev/img?researcher=Demis%20Hassabis&mods=founder,nobel-2024,deepmind`.
   The render service is a pure function of (researcher, modifiers) → image, so
   a designer can build and iterate on it independently, and the same modifiers
   always produce the same art.

Because the modifiers are on-chain, any renderer — ours or a third party's — has
everything it needs. Swap either service with `setServices()` without touching
tokens.

## Contract

- ERC-721 + ERC-2981 (5% royalty → treasury) + Ownable + ReentrancyGuard
- `MAX_SEATS = 128`, seat id = token id
- Per-seat `(price, researcher, thesis, modifiers[], minted)`; frozen once minted
- Minting is gated by `IMintGate` (a seat mints only once holders ratify it —
  reuses the CanonGate ratification contract); proceeds forward to the treasury
- 10 passing tests (`forge test`)

## Mechanisms — open design

The modifier system is the canvas. Ideas on the table (cooking with bird-is-spy):
- **Static traits**: rarity tier, era/school, marquee awards.
- **Living modifiers**: holders vote (through the gate) to append a modifier to
  an already-minted seat — a real new award mints a visible change in the art.
- **Endorsements**: modifiers that reflect on-chain holder activity.

PRs and proposals welcome.

## Build

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 --no-git
forge test
```

Not yet deployed — pending the mechanism round and a metadata/render endpoint.
