# 0009: Installer als eigene VCL-Anwendung je Benutzer

- Status: Angenommen
- Datum: 2026-10-14
- Bezug: #495 Installation und Updates, #83 Release-Prozess, #281 Delphi 12 und 64-Bit-IDE, ADR 0006 IDE-Plugin, ADR 0008 Plattformen

## Kontext

Das Plugin muss je Delphi-Version und IDE-Variante (32-Bit-IDE, 64-Bit-IDE ab Delphi 12.3) die passende BPL unter „Known Packages“ eintragen; der Server liegt daneben. Von Hand heißt das: Package bauen oder herunterladen, in jeder IDE über *Packages installieren* hinzufügen, beim Update dieselben Schritte. Die Deinstallation soll keinen Eintrag unter „Known Packages“ zurücklassen und Benutzerdaten nur auf Wunsch entfernen. Der Release-Runner hat nur RAD Studio, keine Installer-Werkzeuge.

## Entscheidung

- Ein eigener Installer `AtlasSetup.exe`, in Delphi als VCL-Anwendung (Win32, läuft auf jedem Windows) im Repo, Teil der Projektgruppe.
- Installation **je Benutzer** nach `%LOCALAPPDATA%\Programs\Atlas`, ohne Administratorrechte (Manifest `asInvoker`). Registriert wird nur unter `HKCU`, wo die IDE „Known Packages“ liest.
- Aufbau des Pakets gleich dem Zielordner: `AtlasServer.exe`, `AtlasSetup.exe`, `Win32\…bpl`, `Win64\…bpl`. Der Installer kopiert aus seinem eigenen Ordner; das Plugin findet den Server eine Ebene über der BPL.
- Deinstallation über „Apps und Features“ (`AtlasSetup.exe /uninstall`).
- Aufbau nach Rollen wie im übrigen Code: `Setup.Core.*` ohne Windows und VCL, alle Zugriffe über `ISetupSystem`; dadurch laufen Erkennung, Installation und Deinstallation in den DUnitX-Tests gegen eine Attrappe. `Setup.Adapters.WindowsSystem` setzt die Schnittstelle um, `Setup.Shell.*` enthält Fenster und Texte.
- Mit dem Plugin teilt der Installer nur `Atlas.Core.Product.Version`, damit beide dieselbe Version tragen.

## Alternativen

- **Inno Setup oder WiX:** üblich und ausgereift, aber ein weiteres Werkzeug auf dem Runner und eine zweite Sprache für die Erkennung der IDEs; die Logik wäre nicht mit DUnitX testbar.
- **Installation für alle Benutzer** unter `Program Files`: braucht Administratorrechte, „Known Packages“ bleibt trotzdem je Benutzer.
- **Nur ZIP mit Anleitung:** kein Werkzeug nötig, aber fehleranfällig und ohne saubere Deinstallation.

## Folgen

- Der Installer wird wie das Plugin über `cc.ps1` gebaut (ADR 0007) und im Release-Workflow gepackt.
- Neue Delphi-Versionen brauchen einen Eintrag im Katalog `Setup.Core.Ides`.
- Der Schlüssel „Known Packages x64“ der 64-Bit-IDE ist aus dem Aufbau der 32-Bit-Liste abgeleitet und muss in einer 64-Bit-IDE geprüft werden (RAD-Studio.md, „Ungeprüft“).
