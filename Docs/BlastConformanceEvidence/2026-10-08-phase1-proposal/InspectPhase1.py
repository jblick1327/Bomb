"""Read-only Phase 1 provenance and independent arithmetic checks; no Unity tests."""
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[3]
ARCHIVE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Users\jblic\Downloads\BOM-Handbook-1.5.0-Source.zip")
BASE = "3f652e9178a78777bd41514441229827f7e611ad"
EXPECTED = "ef1d9430e490e7b4757e38f57daf12b1dfe19ff3cd2272610aea3147f9e93a0c"

def sha(data):
    return hashlib.sha256(data).hexdigest()

def git(*args, cwd=ROOT):
    return subprocess.check_output(["git", *args], cwd=cwd, text=True).strip()

with zipfile.ZipFile(ARCHIVE) as archive:
    prefix = "BOM-Handbook-1.5.0/"
    checkpoint = json.loads(archive.read(prefix + "CHECKPOINT.json"))
    files = []
    for name, expected in checkpoint["files"].items():
        raw = archive.read(prefix + name)
        actual = sha(raw)
        files.append({"path": name, "bytes": len(raw), "sha256": actual,
                      "matchesCheckpoint": actual == expected})
    page = archive.read(prefix + "index.html").decode("utf-8")
    embedded = json.loads(re.search(r'<script[^>]*type="application/json"[^>]*>([\s\S]*?)</script>', page)[1])
    names = ["BOM Architecture.md", "BOM Decision Log.md", "BOM Open Questions.md",
             "BOM Model Interview Handoff.md", "BOM-Team-Model-Handoff.md", "BOM-Candidate-Component-Map.md"]
    sources = {}
    comparisons = []
    for name in names:
        raw = archive.read(prefix + "handbook/sources/" + name)
        text = raw.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
        sources[name] = text
        entry = embedded["sources"][name]
        comparisons.append({"path": "handbook/sources/" + name, "version": entry["version"], "lines": len(text.splitlines()),
                            "sha256": sha(raw), "matchesEmbeddedMarkdown": text == entry["markdown"],
                            "matchesEmbeddedSha256": sha(text.encode()) == entry["sha256"]})
    book = json.loads(archive.read(prefix + "handbook/handbook.json"))
    signature = sha((json.dumps(book, sort_keys=True, ensure_ascii=False) + "".join(sources.values())).encode())
    assert all(f["matchesCheckpoint"] for f in files)
    assert all(f["matchesEmbeddedMarkdown"] and f["matchesEmbeddedSha256"] for f in comparisons)
    assert embedded["version"] == "1.5.0" and embedded["baseline"] == "Architecture v0.13 \u00b7 DEC-066"
    assert signature == embedded["sourceHash"] == checkpoint["sourceHash"] == EXPECTED

manifests = []
for directory in ["Docs/ConformanceEvidence", "Docs/ConformanceEvidence/Correction-2026-10-08",
                  "Docs/BlastConformanceEvidence/2026-10-08-phase1-baseline"]:
    mismatches = []
    count = 0
    for line in (ROOT / directory / "SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
        digest, name = line.split(None, 1)
        count += 1
        if sha((ROOT / directory / name.strip().lstrip("*")).read_bytes()) != digest:
            mismatches.append(name)
    manifests.append({"path": directory + "/SHA256SUMS.txt", "entries": count, "mismatches": mismatches})
    assert not mismatches, (directory, mismatches)

historical = []
for name in ["editmode-after-result.json", "playmode-after-result.json"]:
    rel = "Docs/ConformanceEvidence/Correction-2026-10-08/" + name
    envelope = json.loads((ROOT / rel).read_text(encoding="utf-8-sig"))
    result = json.loads(envelope["data"]["result"])
    assert envelope["success"] and result["status"] == "completed"
    assert len(result["results"]) == result["summary"]["total"]
    historical.append({"path": rel, "status": result["status"], "duration": result["duration"],
                       "summary": result["summary"], "actualPassedResults": sum(t["Status"] == "Passed" for t in result["results"]),
                       "rerunInPhase1": False})

inventory = []
paths = sorted({*git("ls-files", "Assets/Game/Destruction").splitlines(),
                *git("ls-files", "Assets/Tests", "Packages", "ProjectSettings").splitlines()})
for name in paths:
    raw = (ROOT / name).read_bytes()
    committed = subprocess.check_output(["git", "show", BASE + ":" + name], cwd=ROOT)
    assert raw == committed, name
    inventory.append({"path": name, "sha256": sha(raw), "identicalToExperimentBase": True})

arithmetic = {"kind": "Independent closed-form fixture expectations; not implementation output",
              "inputs": {"air": 1, "coverThickness": 1, "coverResistance": 4, "coreThickness": 2, "coreResistance": 1},
              "costToCore": 1 + 1 + 4 * 1,
              "costThroughCore": 1 + 1 + 2 + 4 * 1 + 1 * 2,
              "radius5CoverPenetration": (5 - 1) / (1 + 4),
              "radius5CoverRemaining": 1 - (5 - 1) / 5,
              "radius8CorePenetration": (8 - 6) / (1 + 1),
              "wideLayerOffAxis": [],
              "coveredCharacterMinimumCost": 4.1 + 4 + 2,
              "radius8OpeningHalfAngleDegrees": math.degrees(math.acos(6 / 8)),
              "radius8CoverBackOpeningHalfHeight": 2 * math.tan(math.acos(6 / 8)),
              "emptySpaceMaxSectorDegreesForQuarterMillimeterSagittaAtRadius10": math.degrees(2 * math.acos(1 - 0.00025 / 10)),
              "narrowCoverSilhouetteDegrees": math.degrees(math.atan2(0.01, 3) - math.atan2(-0.01, 3)),
              "narrowCover": {"resistance": 16, "thickness": 0.02, "radius": 5,
                              "centralReach": 5 - 16 * 0.02,
                              "rotated37DegreeCentralReach": 5 - 16 * 0.02 / math.cos(math.radians(37))},
              "thinWideLayer": {"front": 1, "thickness": 0.02, "resistance": 4, "radius": 1.05,
                                "penetration": (1.05 - 1) / 5, "costToBack": 1.02 + 4 * 0.02},
              "cavity": {"materialIntervals": [[1, 2], [3, 4]], "resistance": 1, "radius": 5,
                         "costToBackWall": 3 + 1, "backWallPenetration": (5 - 4) / 2, "endpoint": 3.5},
              "coveredCorner": {"radius": 7, "characterBounds": [[3.4, 1.4], [3.6, 1.6]],
                                "minimumDirectCost": math.hypot(3.4, 1.4) * (1 + 4 / 3.4),
                                "airDetourLength": math.hypot(0.9, 1.1) + 1.2 + math.hypot(1.4, 2.6)}}
for degrees in [0, 10, 20, 30]:
    cosine = math.cos(math.radians(degrees))
    arithmetic["wideLayerOffAxis"].append({"degrees": degrees, "costToCore": 6 / cosine,
                                           "radius5CoverEndpointX": 0.8 + cosine,
                                           "radius8CoreEndpointX": 4 * cosine - 1})
assert arithmetic["costToCore"] == 6 and arithmetic["costThroughCore"] == 10
assert arithmetic["radius5CoverPenetration"] == 0.8 and arithmetic["radius8CorePenetration"] == 1
assert arithmetic["coveredCorner"]["minimumDirectCost"] > 7
assert arithmetic["coveredCorner"]["airDetourLength"] < 7

output = {"phase": "Phase 1; read-only inspection and proposed bounds; no implementation or Unity test run",
          "archive": {"path": str(ARCHIVE), "bytes": ARCHIVE.stat().st_size, "sha256": sha(ARCHIVE.read_bytes())},
          "checkpoint": checkpoint, "embeddedIdentity": {k: embedded[k] for k in ["version", "baseline", "sourceHash"]},
          "independentlyRecomputedSourceHash": signature, "checkpointFileChecks": files,
          "sourceChecks": comparisons, "preservedEvidence": manifests, "historicalTests": historical,
          "sourceAndSettingsInventory": inventory, "independentExpectations": arithmetic,
          "reportCheckout": {"path": str(ROOT), "branch": git("branch", "--show-current"), "inspectionHead": git("rev-parse", "HEAD"),
                             "experimentBase": BASE, "preReportSourceAndSettingsDiff": git("diff", BASE, "--name-only", "--", "Assets", "Packages", "ProjectSettings")}}
print(json.dumps(output, indent=2, ensure_ascii=True))
