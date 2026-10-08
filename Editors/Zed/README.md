# BetterDelphiLSP in Zed

Zed bindet eigene Sprachserver nur über eine Erweiterung ein. `betterdelphilsp/` ist eine solche Erweiterung mit Sprache „Delphi“ (`.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm`), der Grammatik tree-sitter-pascal und dem Server.

1. Rust über rustup installieren (Zed baut die Erweiterung selbst).
2. In Zed: Befehlspalette > „zed: install dev extension“ > Ordner `Editors/Zed/betterdelphilsp` wählen.
3. `BetterDelphiLSP.exe` muss im `PATH` liegen, oder in den Einstellungen:

```json
{
  "lsp": {
    "betterdelphilsp": {
      "binary": { "path": "C:\\Tools\\BetterDelphiLSP.exe", "arguments": ["--log", "C:\\Temp\\bdlsp.log"] }
    }
  }
}
```

Für `.dfm` gibt es keine eigene Grammatik; die Pascal-Grammatik hebt Formulardateien nur teilweise hervor, Diagnosen und Navigation kommen vom Server.
