# Referenz-Testprojekt

Delphi-Projekt, auf das sich Abnahmekriterien („im Testprojekt“) und die
Messung der Regelqualität (#152) beziehen. Es gehört nicht zur
Projektgruppe des Servers und wird von dessen Build nicht übersetzt.

## Inhalt

| Datei | Zweck |
|---|---|
| `RefGruppe.groupproj` | Projektgruppe mit den drei Pflichtprojekten |
| `RefRuntime.dpk` | Runtime-Package mit der Komponente |
| `RefDesign.dpk` | Design-Time-Package, registriert die Komponente |
| `RefApp.dpr` | VCL-Anwendung mit Formularen und Frame, ohne Datenbank-Units |
| `RefDaten.dpr` | Optional: RefApp plus FireDAC-Zugriffe, nicht in `RefGruppe` |
| `erwartete-meldungen.txt` | Gewollte Hinweise und Warnungen beim Übersetzen |
| `geplante-regeln.txt` | Marker-IDs ohne Regel, je mit zuständigem Issue |
| `Source/Ref.Komponenten.Anzeige.pas` | Komponente mit `published`-Properties samt `default`, `Notification`, `Paint` |
| `Source/Ref.Komponenten.Registrierung.pas` | `Register` für das Design-Time-Package |
| `Source/Ref.Formulare.Haupt.pas/.dfm` | Hauptformular mit Kundenliste |
| `Source/Ref.Formulare.Detail.pas/.dfm` | Von `TBasisFormular` geerbtes Formular (`inherited` in der DFM); in RefApp nach dem Hauptformular automatisch erzeugt (`DetailFormular`, für `form-access-before-create`); eigener `SchliessenButtonClick` mit `inherited` (für `inherited-form-handler-without-inherited`) |
| `Source/Ref.Formulare.Basis.pas/.dfm` | Basisformular |
| `Source/Ref.Formulare.Suchrahmen.pas/.dfm` | Frame |
| `Source/Ref.Sprache.Merkmale.pas` | Generics, Interfaces, Class Helper, anonyme Methoden, Inline-Variablen, `{$IFDEF WIN32/WIN64}` |
| `Source/Ref.Daten.Suche.pas` | Kundensuche ohne Datenbank; RefDaten meldet die FireDAC-Suche an |
| `Source/Ref.Daten.Kunden.pas` | FireDAC-Zugriffe für die Framework-Profile (nur RefDaten) |
| `Source/Ref.Pruefung.Verstoesse.pas` | Bewusst eingebaute Regelverstöße |
| `Source/Ref.Pruefung.Datenbank.pas` | Bewusst eingebaute Verstöße mit FireDAC (nur RefDaten) |
| `Source/Ref.Daten.Auftraege.pas` mit `.inc`, `.Rumpf.inc` | Deklarationen und Rümpfe aus Include-Dateien (#500) |
| `Source/Ref.Daten.Verwendung.pas` | Nutzt die Typen aus der Include-Datei aus einer anderen Unit (#500) |

## Markierung erwarteter Treffer

Jeder bewusst eingebaute Verstoß trägt am Zeilenende einen Kommentar

```pascal
// ERWARTET: <regel-id>
```

Die Zeile mit dem Kommentar ist die Zeile, auf der der Treffer erwartet
wird. Mehrere Regeln werden mit Komma getrennt. Zeilen mit
`// KEIN-TREFFER: <regel-id>` sind Gegenbeispiele, auf denen die Regel
nicht anschlagen darf. Ein Werkzeug für #152 kann so Treffer und
Fehlalarme zählen, ohne Zeilennummern zu pflegen.

Projektweite Regeln brauchen alle Units des Projekts und laufen deshalb nicht
im Golden-Korpus je Datei. Ihre Treffer tragen `// ERWARTET-PROJEKT: <regel-id>`.
Für `unused-public-member` (#1102) prüft
`TUnusedPublicMemberTests.ReferenceProjectMatchesMarkers` RefApp als Ganzes:
genau die markierten Zeilen müssen gemeldet werden, jede weitere Meldung ist ein
Fehlalarm. `TKundenSuche.Anmelden` ist markiert, weil nur RefDaten es aufruft und
RefDaten nicht zu RefApp gehört.

Regeln, die die RTL im Index brauchen (z. B. `System.Contnrs.TObjectStack`),
schweigen im Golden-Korpus, weil er je Datei ohne Symbolindex prüft. Ihre
Treffer tragen `// ERWARTET-INDEX: <regel-id>`. Für `legacy-stack-queue`
(#1106) prüft `TLegacyStackQueueTests.ReferenceProjectMatchesMarkers` alle
Units unter `Source` mit RTL-Stubs im Index: genau die markierten Zeilen
müssen gemeldet werden, jede weitere Meldung ist ein Fehlalarm.

## Marker-IDs und zuständige Regeln

| Marker-ID | Stand |
|---|---|
| `result-not-set` | Regel im Katalog (#269) |
| `unused-local` | Regel im Katalog (#91) |
| `empty-except` | Regel im Katalog (#56) |
| `for-high-to-low` | Regel im Katalog |
| `self-assignment` | Regel im Katalog |
| `security-sql-injection` | Regel im Katalog (#270), in `Ref.Pruefung.Datenbank` |
| `with-statement` | Regel im Katalog (#94) |
| `unreachable-code` | Regel im Katalog (#94) |
| `possible-leak` | geplant, `geplante-regeln.txt`, Issue #56 |
| `legacy-stack-queue` | Regel im Katalog (#1106), `ERWARTET-INDEX`, in `Ref.Pruefung.Verstoesse` |
| `override-only-inherited` | Regel im Katalog (#1143), in `Ref.Pruefung.Verstoesse` |
| `inherited-without-ancestor` | Regel im Katalog (#1144), in `Ref.Pruefung.Verstoesse` |
| `redundant-jump` | Regel im Katalog (#1141), in `Ref.Pruefung.Verstoesse` |

Jede ID steht im Regelkatalog oder in `geplante-regeln.txt` mit dem
offenen Issue, das sie in den Katalog übernimmt. Eine ID ohne Issue lässt
den Golden-Korpus-Test fehlschlagen.

## Regelqualität (#152)

Der DUnitX-Test `TGoldenCorpusTests.ReferenceProjectMatchesMarkers` prüft alle
Units unter `Source` mit den eingebauten Regeln:

- Fehlt ein erwarteter Treffer, schlägt der Test fehl.
- Meldet eine Regel etwas auf einer `KEIN-TREFFER`-Zeile, schlägt der Test fehl.
- Eine Regel-ID, die weder im Regelkatalog noch in
  `geplante-regeln.txt` steht, lässt den Test fehlschlagen. IDs aus
  `geplante-regeln.txt` werden mit Warnung übersprungen.

Der Test protokolliert außerdem die Laufzeit je Regel.

Bewertungen von Treffern aus echten Projekten stehen in
`bewertungen.csv` mit den Spalten Regel-ID, Datei, Zeile, Bewertung und Datum.
Die Bewertung ist `richtig` oder `falsch`.
`pwsh Tools/Get-RuleQuality.ps1` berechnet daraus die Fehlalarmquote je Regel;
`TGoldenCorpusTests.ReferenceRatingsAreValid` prüft die Datei und protokolliert
dieselbe Quote. Die erste Stichprobe (17.10.2026) stammt aus dem Quelltext von
Atlas selbst: alle Treffer der Standardeinstellungen außer den Kennzahlen
(`metric-*`), von `format-without-settings` und `security-insecure-http` nur
jeder zehnte bzw. vierte.

### Trefferquote (Mutationen)

`mutationen.txt` baut gezielt Fehler in die Units unter `Source` ein, je Zeile
`regel-id | Datei | Suchtext | Ersatz`. Der Suchtext muss in der Datei genau
einmal vorkommen; `\n` steht für einen Zeilenumbruch, `\uXXXX` für ein Zeichen,
`\|` und `\\` für die Zeichen selbst. `TGoldenCorpusTests.ReferenceProjectMutationsAreFound`
prüft jede Mutation einzeln: Die Regel ist dafür ausdrücklich eingeschaltet (auch
experimentelle und freiwillige) und jede Konfidenz zählt. Gefunden ist die
Mutation, wenn die Regel danach mehr Treffer meldet als vorher. Der Test
protokolliert die Trefferquote je Regel und schlägt fehl, wenn eine Mutation
nicht gefunden wird.

## Öffnen

`RefGruppe.groupproj` in RAD Studio öffnen. Die `.dproj`-Dateien sind
bewusst minimal. Sie werden einmal in der IDE gespeichert und so
eingecheckt; danach dürfen Öffnen und Speichern sie nicht mehr ändern.

## Bauen

```powershell
pwsh Tools/Build-Referenzprojekt.ps1            # RefGruppe, Win32 und Win64
pwsh Tools/Build-Referenzprojekt.ps1 -MitDaten  # zusätzlich RefDaten (FireDAC)
pwsh Tools/Build-Referenzprojekt.ps1 -Platforms Win32
```

Das Skript baut wie `Tools/Build-Test.ps1` (#260) über cc.ps1 in einer
eigenen Scratch-IDE. Es scheitert,

- wenn ein Build fehlschlägt,
- wenn ein Hinweis oder eine Warnung kommt, die nicht in
  `erwartete-meldungen.txt` steht, oder eine Zeile daraus je Plattform
  nicht genau einmal kommt,
- wenn die IDE eine `.dproj`- oder `.groupproj`-Datei geändert hat.

Die eingebauten Verstöße erzeugen absichtlich Meldungen (W1035 für
`OhneErgebnis`, H2164 für `Unbenutzt`). Die Regel „0 Hinweise“ gilt für
Atlas, nicht für dieses Projekt.

Delphi 12 (#281): sobald verfügbar, dasselbe Skript mit der IDE von
Delphi 12 ausführen; `-CcStartArguments` reicht dafür Argumente an
`cc.ps1 start` weiter.

## FireDAC

FireDAC gehört nicht zu jeder Edition von RAD Studio. Alles, was FireDAC
braucht, steht deshalb im optionalen Projekt `RefDaten`, das nicht zum
Pflicht-Build gehört: `Ref.Daten.Kunden` und `Ref.Pruefung.Datenbank`.
`RefApp` sucht über `TKundenSuche` (`Ref.Daten.Suche`); ohne `RefDaten`
bleibt die Liste leer. Die Prüfregeln sehen beide Units trotzdem, weil der
Golden-Korpus-Test alle Units unter `Source` prüft.
