# Benchmark

*Deutsche Fassung: [Benchmark.md](../Benchmark.md)*

`Tools/Benchmark/bench.mjs` measures the performance targets (#85) on the real server over stdio. Needs Node 18 or newer.

| Operation | Target (p95) |
|---|---|
| Go to definition, highlight occurrences | < 50 ms |
| Hover, completion, parameter hint | < 100 ms |
| Syntax error after a keystroke | < 200 ms |
| Start with an existing index cache | < 2 s |

## Running

```
node Tools/Benchmark/bench.mjs --server Output\Win64\Release\Bin\AtlasServer.exe --baseline benchmark\letzte.json
```

| Option | Meaning |
|---|---|
| `--server` | Server EXE, default `Output\Win64\Release\Bin\AtlasServer.exe` |
| `--corpus` | Folder with source code, can be given several times; default `Tests/Referenzprojekt`. For the large corpus add the VCL sources, e.g. `--corpus "C:\Program Files (x86)\Embarcadero\Studio\37.0\source\vcl"`. The first folder is the workspace root. |
| `--samples` | Number of measuring positions (default 30) |
| `--completion-samples` | Number of completion requests (default 100, #31) |
| `--out` | Result folder (default `benchmark/`, not under version control) |
| `--baseline` | Earlier measurement to compare with |
| `--version` | Label in the report, e.g. `0.1.0` |
| `--no-fail` | Always exit code 0 |

## Procedure

1. Start without cache (reported, no target), then three starts with cache. The server is ready as soon as `workspace/symbol` finds a symbol from the corpus.
2. At fixed identifier positions from the implementation sections: definition, occurrences, hover, parameter hint.
3. Completion (#31) with a warm index at its own positions (default 100): two characters of the identifier typed, so that fuzzy matching (#229) and symbols from units not yet used (#180) take part as in the editor; like RAD Studio the client sends `documentationFormat: ["plaintext"]`.
4. For up to 10 files: insert a syntax error via `didChange` and measure the time until `publishDiagnostics`.

## Result

The result folder holds `benchmark-<time>.json`, `letzte.json` and `bericht.md`. Exit code 1 if a p95 exceeds its target or is more than 20 % and more than 5 ms slower than `--baseline`; exit code 2 on an error in the run.

The pure functions (statistics, comparison, choice of positions) are tested with `node --test Tools/Benchmark/lib.test.mjs`.
