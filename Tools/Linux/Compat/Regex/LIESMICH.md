# Regex-Units der vcl-compat (FPC)

Unveränderte Kopie von `packages/vcl-compat/src/system.regularexpressions*.pp` aus Free Pascal im Stand
`FPC_COMMIT` von `Tools/Linux/Build-AtlasServer.sh` (Lizenz: modifizierte LGPL von FPC, siehe COPYING.FPC
im FPC-Quelltext).

Warum hier (#1751): Die vorkompilierten Units des FPC-Pakets sind ohne `USEWIDESTRING` übersetzt
(`TREString = AnsiString`, pcre2-8). Dort zählt `TMatch.Index` UTF-8-Bytes statt Zeichen; hinter einem
Umlaut liegt jeder Treffer daneben (anonymes Log, Spalten von Befunden). Das Build-Skript übersetzt diese
Quellen mit `-dUSEWIDESTRING` (UnicodeString, pcre2-16) wie Delphi. Zur Laufzeit braucht der Server
`libpcre2-16.so.0` (Paket `libpcre2-16-0`).

Bei einem neuen `FPC_COMMIT` diese drei Dateien aus demselben Stand neu holen.
