# Handbook source

Handbook **1.8.1**. Architecture **v0.16**, through **DEC-077**, defines accepted requirements.

`sources/` contains the Architecture, Open Questions, candidate component map and Decision Log. Topic explanations and worked examples are in `reference/`; current tool instructions are in `guides/`. Dated results belong in `evidence/`; previous editing context is in `history/`.

## Edit

Keep the current requirements and their rationale distinct. Record accepted gameplay changes in the Architecture and Decision Log, then synchronize open questions, the map and reader summaries. Preserve rule IDs, useful examples and stable routes. Keep proposed work labelled as proposed.

For editorial corrections, update the handbook version without inventing a gameplay decision. Keep version history and test details out of the main guidance.

## Build

From the repository root:

```sh
python handbook/build.py
cp handbook/dist/index.html index.html
```

No packages or server are needed. Check internal links, source hashes, downloads, search and offline navigation. Commit the sources and root output together.
