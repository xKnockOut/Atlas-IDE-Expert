# Regex-Units der vcl-compat (FPC)

Kopie von `packages/vcl-compat/src/system.regularexpressions*.pp` aus Free Pascal im Stand
`FPC_COMMIT` von `Tools/Linux/Build-AtlasServer.sh` (Lizenz: modifizierte LGPL von FPC, siehe COPYING.FPC
im FPC-Quelltext). `system.regularexpressions.pp` und `system.regularexpressionsconsts.pp` sind unverändert,
`system.regularexpressionscore.pp` trägt eigene Korrekturen (siehe unten).

Warum hier (#1751): Die vorkompilierten Units des FPC-Pakets sind ohne `USEWIDESTRING` übersetzt
(`TREString = AnsiString`, pcre2-8). Dort zählt `TMatch.Index` UTF-8-Bytes statt Zeichen; hinter einem
Umlaut liegt jeder Treffer daneben (anonymes Log, Spalten von Befunden). Das Build-Skript übersetzt diese
Quellen mit `-dUSEWIDESTRING` (UnicodeString, pcre2-16) wie Delphi. Zur Laufzeit braucht der Server
`libpcre2-16.so.0` (Paket `libpcre2-16-0`).

Bei einem neuen `FPC_COMMIT` diese drei Dateien aus demselben Stand neu holen und die Korrekturen unten neu anwenden,
soweit FPC sie nicht selbst enthält.

Eigene Korrekturen in `system.regularexpressionscore.pp` gegenüber FPC (bei einem neuen Stand prüfen, ob sie noch
nötig sind; der Neuversuch nach leerem Treffer in `MatchAgain` wie in pcre2demo.c steht inzwischen in FPC selbst):
`Replace` übernimmt den ganzen Text zwischen zwei Treffern (vorher nur
dessen erstes Zeichen, etwa `TRegEx.Replace(S, '\s+', ' ')` bei mehreren Lücken); `EscapeRegExChars` läuft über die Zeichen von `TREString` statt über `PChar` (unter `{$MODE OBJFPC}` ein
`PAnsiChar`: Mit `USEWIDESTRING` bestand das Ergebnis zur Hälfte aus ungesetztem Speicher, jedes `TRegEx.Escape`
lieferte je nach Heap ein anderes Muster oder einen Übersetzungsfehler); `GetPCREErrorMsg` liest die Meldung von
pcre2-16 als UTF-16.
