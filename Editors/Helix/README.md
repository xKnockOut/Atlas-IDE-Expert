# BetterDelphiLSP in Helix

1. Den Inhalt von `languages.toml` in die eigene `languages.toml` übernehmen (Linux/macOS `~/.config/helix/`, Windows `%AppData%\helix\`).
2. Für Syntaxhervorhebung die Grammatik holen: `hx --grammar fetch` und `hx --grammar build`. Ohne Grammatik arbeiten Diagnosen, Navigation und Vervollständigung trotzdem.
3. `hx --health delphi` muss den Server als gefunden melden. Liegt `BetterDelphiLSP.exe` nicht im `PATH`, bei `command` den vollen Pfad eintragen.

`.dfm` ist enthalten, damit Diagnosen und Navigation in Formulardateien funktionieren.
