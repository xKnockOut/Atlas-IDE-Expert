unit Bericht.Approval.Tests;

// Beispiel für Vergleichsdateien mit Atlas.Testing.Approval (#1881).
// Atlas.Testing.Approval liegt der Installation unter Setup\Vorlagen bei; die Unit ins
// Testprojekt kopieren oder ihren Ordner in den Suchpfad aufnehmen.
//
// Ablauf:
// 1. Erster Lauf: rot mit „Approval: neu, bitte prüfen“; daneben liegt
//    Tests\Erwartet\TBerichtTests.Monatsbericht.received.txt.
// 2. Datei prüfen und übernehmen: in .approved.txt umbenennen (in Atlas an der
//    Testmarke „Als neue Erwartung übernehmen“). Die approved-Datei einchecken.
// 3. Nächster Lauf: grün. Ändert sich die Ausgabe, wird der Test rot und nennt die
//    erste abweichende Zeile; „Vergleichen“ zeigt beide Fassungen nebeneinander.
// .received.* gehört in die Ignorierliste der Versionsverwaltung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBerichtTests = class
  public
    [Test]
    procedure Monatsbericht;
    [Test]
    procedure ExportAlsJson;
  end;

implementation

uses
  System.SysUtils,
  System.RegularExpressions,
  Atlas.Testing.Approval,
  Bericht;

/// <summary>Zeitstempel und GUIDs ändern sich bei jedem Lauf: vor dem Vergleich ersetzen.</summary>
function OhneVeraenderliches(const AText: string): string;
begin
  Result := TRegEx.Replace(AText, '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', '<Zeit>');
  Result := TRegEx.Replace(Result, '\{[0-9A-F-]{36}\}', '<GUID>', [roIgnoreCase]);
end;

procedure TBerichtTests.Monatsbericht;
begin
  // Datei: Tests\Erwartet\TBerichtTests.Monatsbericht.approved.txt
  TApproval.Verify(TBericht.Monat(2026, 11), 'TBerichtTests.Monatsbericht');
end;

procedure TBerichtTests.ExportAlsJson;
begin
  // Eigene Endung und Normalisierer: TBerichtTests.ExportAlsJson.approved.json
  TApproval.Verify(TBericht.AlsJson(2026, 11), 'TBerichtTests.ExportAlsJson', '.json', OhneVeraenderliches);
end;

initialization
  TDUnitX.RegisterTestFixture(TBerichtTests);

end.
