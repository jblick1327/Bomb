# Tasks for ChatGPT (chat mode: no Odin, no access to this PC)

Paste one block at a time. Save each answer as the named file under docs/ so the reviewer can check it later. Each block is self-contained.

---
## 1. Hosting guide for friends -> save as docs/hosting-guide.md
I'm making a small Windows co-op game (2–4 players). One player hosts: their game starts a dedicated server on UDP port 47380 and everyone else joins by IP:port. Write a short, friendly guide for non-technical friends covering:
(1) forwarding UDP 47380 on a home router (generic steps, plus where to look on common router brands);
(2) the Windows Defender Firewall prompt (what to allow, and how to fix it if they clicked Cancel);
(3) how the host finds their public IP, and why the LAN IP shown in the game is only for the same network;
(4) CGNAT, and how to tell if port forwarding is impossible;
(5) the no-port-forward alternative: Tailscale or ZeroTier, step by step.
Keep it under about 900 words, in plain language.

---
## 2. Box2D 3.1 kinematic character mover -> save as docs/research-kinematic-player.md
I use Box2D v3.1.1 through its C API (from Odin). My player is a dynamic capsule with fixed rotation and sleep disabled. I set its velocity every tick, with coyote time and a jump buffer. Problem: any dynamic body the player touches stays awake forever (island sleeping), so rubble piles never sleep while players walk on them. I'm considering a kinematic character "mover" instead.
Explain, citing the Box2D v3.1 docs or samples and naming exact functions (for example b2World_CastMover, b2World_CollideMover, b2SolvePlanes, b2ClipVector, b2MakeCapsule):
(1) how the v3.1 mover approach works;
(2) how to push dynamic debris (applying impulses to bodies we hit) and how to ride moving platforms;
(3) how ground detection, coyote time and jump buffering fit in;
(4) whether kinematic bodies keep islands awake;
(5) the pitfalls.
Give C-like pseudocode for one step of the update. Say clearly where you are unsure of an API detail.

---
## 3. Demo level ideas -> save as docs/level-ideas.md
2D destruction sandbox. Build area 16 m wide × 4.8 m tall above a stone floor; the player is about 0.5 m wide and 1.2 m tall.
- Materials:
  - Wood (splinters along the grain);
  - Glass (shatters, and cracks travel through it);
  - Rubber (bends);
  - Stone (heavy, blocks blast);
  - plus custom variants (toughness, blast resistance, colour).
- Shapes: rectangles and right-angle wedges, rotatable in 15° steps.
- Joints:
  - mortar (automatic between touching objects marked mortar, and to the floor);
  - glue (between two chosen touching objects).
  Both break when overloaded for a while or blasted.
- Blasts are blocked by material in between: Stone and Rubber block most, then Wood, with Glass blocking least.
Propose 8 small preset levels that each show off one idea: cover, a progressive collapse, a glass cascade, a rubber bounce, a cantilever, etc. For each give a name, the idea, an object list with sizes, positions (metres; x from −7.5 to 8.5, y ≥ 0), materials, rotations and joints, and what players should try. Keep every object inside the build area and non-overlapping.
