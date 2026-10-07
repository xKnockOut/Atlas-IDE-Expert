# Architektur von BetterDelphiLSP

Grundlage ist das Konzept „Rollenbasierte Kopplung und Kohäsion“ (Entwurf, Stand 30.09.2026). Dieses Dokument hält fest, wie das Konzept in diesem Projekt angewendet wird. Bei Widersprüchen gilt das Konzept.

## Ausgabeartefakte

| Projekt | Art (Konzept 6.2) | Darf verwenden | Darf nicht verwenden |
|---|---|---|---|
| `BDLsp.Common` | Platform-Package | plattformunabhängige RTL (`System.*`) | Windows (`Winapi.*`, `System.Win.*`), VCL, FMX, `BDLsp.Windows` |
| `BDLsp.Windows` | Platform-Package | RTL, `Winapi.*`, `System.Win.*`, `BDLsp.Common` | VCL, FMX |
| `BetterDelphiLSP` | Anwendung (Host) | beide Packages, RTL, Windows | VCL (Konsolenanwendung) |
| `BDLsp.Tests` | Testprojekt (DUnitX) | alles, was getestet wird | – |

Abhängigkeitsrichtung:

```text
BetterDelphiLSP ──► BDLsp.Windows ──► BDLsp.Common ──► RTL
       │                                   ▲
       └───────────────────────────────────┘
```

Die Regeln für die Packages prüft `Tools/Check-PackageDependencies.ps1` (uses- und requires-Klauseln). Das Skript läuft lokal und in der GitHub Action „Package-Abhängigkeiten“.

## Verzeichnisstruktur

```text
BetterDelphiLSP.groupproj          Projektgruppe (Build-Reihenfolge: Common, Windows, Anwendung, Tests)
Packages/
  BDLsp.Common/
    BDLsp.Common.dpk/.dproj
    Source/<Feature>/              ein Ordner je Platform-Feature, darin optional Rollenordner
  BDLsp.Windows/
    BDLsp.Windows.dpk/.dproj
    Source/<Feature>/
Application/
  BetterDelphiLSP.dpr/.dproj
  Source/
    Foundation/  Core/  Adapters/  Platform/  Features/  Shell/   (Host-Rollen, Konzept 7.2/7.3)
Tests/
  BDLsp.Tests.dpr/.dproj
  Common/  Windows/  Application/  (Tests je Ausgabeartefakt)
Tools/                             Hilfsskripte
Output/<Plattform>/<Konfiguration>/ Build-Ausgabe (nicht versioniert): Dcu, Dcp, Bpl, Bin
```

Die Anwendung und das Testprojekt binden die Packages statisch ein: Sie finden die DCUs der Packages in `Output/<Plattform>/<Konfiguration>/Dcu/<Package>`. Deshalb müssen die Packages vor der Anwendung gebaut werden; die Projektgruppe regelt das.

## Benennung (Konzept 6.3)

```text
Ausgabeartefakt.Feature.Rolle.Sache
```

- Präfixe der Ausgabeartefakte (Whitelist): `BDLsp.Common`, `BDLsp.Windows`
- Units der Anwendung tragen kein Präfix, z. B. `Shell.Application`
- Units im Wurzelverzeichnis eines Features tragen keinen Rollenbezeichner, z. B. `BDLsp.Common.Product.Version`
- Rollenbezeichner sind reserviert: `Contract`, `Providers`, `Adapters`, `Internals`, `Hosting`, `Composition` (Features) sowie `Foundation`, `Core`, `Shell`, `Adapters`, `Platform` (Host)

## Importregeln

Platform-Features in den Packages (Konzept 8.3) importieren weder Host noch Hosted-Features:

| Importierende Rolle | Darf importieren |
|---|---|
| Contract | eigenes Contract, fremdes Contract |
| Internals | eigenes Contract und Internals, fremdes Contract und Root |
| Providers, Adapters, Root | eigenes Contract, Internals und Root, fremdes Contract und Root |
| Composition | eigenes Contract, Providers, Adapters, Root und Composition, fremdes Contract und Root |

Für die Anwendung gelten die Host-Matrix (8.1) und die Hosted-Feature-Matrix (8.2). Hosted-Features importieren sich nie gegenseitig; feature-übergreifende Abläufe orchestriert der Host (Konzept 11).

## DI-Strategie

Komposition von Hand (keine Container-Bibliothek). Composition-Units tragen deshalb kein Strategie-Suffix. Wird später eine zweite Strategie (z. B. Spring4D) eingeführt, erhalten die Units ein Suffix nach Konzept 7.6.

## Umgesetzte Features

| Feature | Units | Inhalt |
|---|---|---|
| `BDLsp.Common.JsonRpc` (Platform) | `Contract`, `Messages`, `StreamTransport`, `Dispatcher`, `Connection` | JSON-RPC 2.0 mit LSP-Rahmung (`Content-Length`) über beliebige Streams, Verteilung auf Handler, Nachrichtenschleife |
| `BDLsp.Common.Lsp` (Platform) | `Contract`, `Lifecycle` | LSP-Fehlercodes und Konstanten, Lebenszyklus `initialize` → `initialized` → `shutdown` → `exit` |
| `BDLsp.Windows.Console` (Platform) | `StdStreams` | stdin/stdout als Streams, `Write`/`Writeln` auf stderr umgeleitet |
| `Shell` (Host) | `Shell.Application`, `Shell.Composition` | Einstiegspunkt, Komposition von Hand, Capabilities |

Ablauf einer Anfrage:

```text
stdin ─► TJsonRpcStreamTransport ─► TJsonRpcConnection ─► TJsonRpcDispatcher ─► Handler
                                                              │ Guard: TLspLifecycle
stdout ◄─ TJsonRpcStreamTransport ◄──────── Antwort ◄─────────┘
```

Neue LSP-Methoden registrieren ihre Handler in `Shell.Composition` am Dispatcher und tragen ihre Capability in `BuildCapabilities` ein.

## Geplante Zuordnung der Bausteine

Vorschlag, wird mit den jeweiligen Issues verfeinert:

| Baustein | Ort | Begründung |
|---|---|---|
| Logging-Abstraktion (#3) | `BDLsp.Common` (Contract) | von allen genutzt |
| Logging über `OutputDebugString`, Logdatei (#3) | `BDLsp.Windows` | Windows-API |
| Dokumentverwaltung, Lexer, Parser, Präprozessor, Symbolindex, Namensauflösung, Prüfregeln, DFM-Parser | `BDLsp.Common` | reine Textverarbeitung |
| Delphi-Installationen und Bibliothekspfade aus der Registry (#14, #47) | `BDLsp.Windows` | Registry |
| Compiler- und MSBuild-Aufruf (#40) | `BDLsp.Windows` | Prozesse, `rsvars.bat` |
| Debug-Adapter, Windows-Debug-API (#75) | `BDLsp.Windows` | Windows-API |
| LSP-Methoden (Navigation, Hover, Code-Aktionen …) | `BetterDelphiLSP`, Hosted-Features | Fachcode des Servers |
| Einstiegspunkt, Komposition | `BetterDelphiLSP`, Shell | Host |
