unit Atlas.Common.Rules.Builtin.Platform.Tests;

// Tests der Regeln zur Laufzeitumgebung aus Rules.Builtin.Platform: je Regel
// das Beispiel aus dem Issue, Varianten, stille Fälle, Korrekturen und
// Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPlatformRulesTests = class
  public
    [Test]
    procedure UiCallIssueExample;
    [Test]
    procedure UiCallApplicationKinds;
    [Test]
    procedure UiCallVariants;
    [Test]
    procedure UiCallSilentCases;
    [Test]
    procedure UiCallOptions;
    [Test]
    procedure EncodingIssueExample;
    [Test]
    procedure EncodingVariants;
    [Test]
    procedure EncodingSilentCases;
    [Test]
    procedure EncodingOptions;
    [Test]
    procedure RegistryIssueExample;
    [Test]
    procedure RegistrySilentCases;
    [Test]
    procedure RegistryOptions;
    [Test]
    procedure ElapsedIssueExample;
    [Test]
    procedure ElapsedVariants;
    [Test]
    procedure ElapsedSilentCases;
    [Test]
    procedure ElapsedOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Platform,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit einer Routine Pruefen aus AVars und ABody.</summary>
function Routine(const AVars, ABody: string): string;
begin
  Result := 'unit Werkzeug;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10 +
    'procedure Pruefen;'#10 + AVars + 'begin'#10 + ABody + #10'end;'#10'end.';
end;

/// <summary>Unit eines Windows-Dienstes mit ServiceExecute aus ABody.</summary>
function ServiceUnit(const ABody: string): string;
begin
  Result := 'unit DatenDienst;'#10'interface'#10'uses'#10'  Vcl.SvcMgr;'#10'type'#10 +
    '  TDatenDienst = class(TService)'#10'    procedure ServiceExecute(Sender: TService);'#10'  end;'#10 +
    'implementation'#10'uses'#10'  Vcl.Dialogs;'#10'procedure TDatenDienst.ServiceExecute(Sender: TService);'#10 +
    'begin'#10 + ABody + #10'end;'#10'end.';
end;

{ ui-call-in-console-or-service }

procedure TPlatformRulesTests.UiCallIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUiCallInConsoleOrServiceRule.Create,
    ServiceUnit('  if not Verbinden then'#10'    ShowMessage(''Keine Verbindung'');'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('ShowMessage in einem Windows-Dienst blockiert unsichtbar; protokollieren statt anzeigen.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(14, Findings[0].Range.StartPos.Line);
  // Korrigiert: protokollieren.
  TRuleAssert.Silent(TUiCallInConsoleOrServiceRule.Create,
    ServiceUnit('  if not Verbinden then'#10'    LogMessage(''Keine Verbindung'');'));
end;

procedure TPlatformRulesTests.UiCallApplicationKinds;
begin
  Assert.AreEqual(Ord(TRuleApplicationKind.Service), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'program Dienst;'#10'uses'#10'  Vcl.SvcMgr,'#10'  DatenDienst in ''DatenDienst.pas'' {Dienst: TService};'#10 +
    'begin'#10'  Application.Run;'#10'end.')));
  // Dienst, der auch mit Oberfläche startet.
  Assert.AreEqual(Ord(TRuleApplicationKind.Gui), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'program Dienst;'#10'uses'#10'  Vcl.Forms,'#10'  Vcl.SvcMgr;'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TRuleApplicationKind.Library_), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'library Rechner;'#10'uses'#10'  System.SysUtils,'#10'  Formeln in ''Formeln.pas'';'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TRuleApplicationKind.Library_), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'library Rechner;'#10'uses'#10'  Daten in ''Daten.pas'' {Daten: TDataModule};'#10'begin'#10'end.')));
  // DLL mit Formular: Unknown wie bisher.
  Assert.AreEqual(Ord(TRuleApplicationKind.Unknown), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'library Rechner;'#10'uses'#10'  Haupt in ''Haupt.pas'' {frmHaupt};'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TRuleApplicationKind.Unknown), Ord(TWritelnInGuiAppRule.ApplicationKind('',
    'library Rechner;'#10'uses'#10'  Vcl.Forms;'#10'begin'#10'end.')));
  // writeln-in-gui-app: auch ein Dienst hat keine Konsole.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.ApplicationFindings(TWritelnInGuiAppRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  Writeln(''x'');'#10'end;'#10'end.',
    TRuleApplicationKind.Service))));
end;

procedure TPlatformRulesTests.UiCallVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // Konsolenprogramm: MessageDlg im Ausdruck, qualifiziert, InputBox, Application.MessageBox.
  Findings := TRuleAssert.ApplicationFindings(TUiCallInConsoleOrServiceRule.Create, Routine('',
    '  if MessageDlg(''Weiter?'', mtConfirmation, [mbYes, mbNo], 0) = mrYes then'#10'    Weiter;'#10 +
    '  Vcl.Dialogs.ShowMessage(''x'');'#10'  Name := InputBox(''Name'', ''Name:'', '''');'#10 +
    '  Application.MessageBox(''x'', ''y'', 0);'#10'  TDialogService.ShowMessage(''z'');'),
    TRuleApplicationKind.Console);
  Assert.AreEqual(5, Integer(Length(Findings)));
  Assert.AreEqual('MessageDlg in einem Konsolenprogramm wartet auf einen Klick, wenn das Programm ' +
    'unbeaufsichtigt läuft; protokollieren statt anzeigen.', Findings[0].Message);
  Assert.AreEqual('Vcl.Dialogs.ShowMessage', Copy(Findings[1].Message, 1, Length('Vcl.Dialogs.ShowMessage')));
  Assert.IsTrue(Findings[3].Message.StartsWith('Application.MessageBox in'), Findings[3].Message);
  // DLL ohne Formulare: mittlere Konfidenz.
  Findings := TRuleAssert.ApplicationFindings(TUiCallInConsoleOrServiceRule.Create, Routine('',
    '  ShowMessageFmt(''%d'', [1]);'), TRuleApplicationKind.Library_);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('ShowMessageFmt in einer DLL ohne Formulare blockiert, wenn der Host keine Oberfläche hat ' +
    '(Dienst, Webserver); protokollieren oder einen Fehler zurückgeben.', Findings[0].Message);
  // Eine Unit des Dienstprojekts ohne eigene TService-Klasse.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.ApplicationFindings(TUiCallInConsoleOrServiceRule.Create,
    Routine('', '  ShowMessage(''x'');'), TRuleApplicationKind.Service))));
  // Die .dpr eines Konsolenprogramms ohne Projekt.
  TRuleAssert.Reports(TUiCallInConsoleOrServiceRule.Create, 'program Werkzeug;'#10'{$APPTYPE CONSOLE}'#10 +
    'uses'#10'  Vcl.Dialogs;'#10'begin'#10'  ShowMessage(''Fertig'');'#10'end.');
end;

procedure TPlatformRulesTests.UiCallSilentCases;
const
  Body = '  ShowMessage(''x'');';
begin
  // GUI-Programm und Unit ohne Projekt.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ApplicationFindings(TUiCallInConsoleOrServiceRule.Create,
    Routine('', Body), TRuleApplicationKind.Gui))));
  TRuleAssert.Silent(TUiCallInConsoleOrServiceRule.Create, Routine('', Body));
  // Unit mit Formular in einem Konsolenprogramm.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TUiCallInConsoleOrServiceRule.Create,
    'program Werkzeug;'#10'{$APPTYPE CONSOLE}'#10'begin'#10 + Body + #10'end.', 'object frmHaupt: TfrmHaupt'#10'end'))));
  // Unter IsConsole, eigene Routine ShowMessage, Methode eines anderen Objekts.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ApplicationFindings(TUiCallInConsoleOrServiceRule.Create,
    Routine('', '  if not IsConsole then'#10'    ShowMessage(''x'');'#10'  Log.ShowMessage(''y'');'#10 +
    '  Fenster.MessageBox(''z'');'), TRuleApplicationKind.Console))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ApplicationFindings(TUiCallInConsoleOrServiceRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'procedure ShowMessage(const S: string);'#10'begin'#10'end;'#10 +
    'procedure P;'#10'begin'#10 + Body + #10'end;'#10'end.', TRuleApplicationKind.Console))));
  // Package und DLL mit Formularen (Unknown).
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ApplicationFindings(TUiCallInConsoleOrServiceRule.Create,
    Routine('', Body), TRuleApplicationKind.Package))));
  TRuleAssert.Silent(TUiCallInConsoleOrServiceRule.Create, 'library L;'#10'uses'#10'  Vcl.Forms;'#10'begin'#10 +
    Body + #10'end.');
end;

procedure TPlatformRulesTests.UiCallOptions;
var
  Source: string;
begin
  Source := ServiceUnit('  ShowMessage(''x'');');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUiCallInConsoleOrServiceRule.Create, Source, '',
    'Dienst/DatenDienst.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUiCallInConsoleOrServiceRule.Create, Source,
    '{"rules": {"ui-call-in-console-or-service": "off"}}', 'Dienst/DatenDienst.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUiCallInConsoleOrServiceRule.Create, Source,
    '{"rules": {"ui-call-in-console-or-service": {"exclude": ["Dienst/*"]}}}', 'Dienst/DatenDienst.pas'))));
end;

{ load-without-encoding }

procedure TPlatformRulesTests.EncodingIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Routine('var'#10'  Zeilen: TStringList;'#10, '  Zeilen.LoadFromFile(Pfad);');
  Findings := TRuleAssert.Findings(TLoadWithoutEncodingRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('LoadFromFile ohne Kodierung liest Dateien ohne BOM mit der ANSI-Codepage.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('TEncoding.UTF8 ergänzen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Routine('var'#10'  Zeilen: TStringList;'#10, '  Zeilen.LoadFromFile(Pfad, TEncoding.UTF8);'), Fixed);
  TRuleAssert.Silent(TLoadWithoutEncodingRule.Create, Fixed);
end;

procedure TPlatformRulesTests.EncodingVariants;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  // SaveToFile, Memo.Lines, Query.SQL, TFile.ReadAllText; System.SysUtils fehlt im uses.
  Source := 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.IOUtils;'#10'procedure P;'#10 +
    'var'#10'  Liste: TStrings;'#10'begin'#10'  Liste.SaveToFile(Pfad);'#10'  Memo1.Lines.LoadFromFile(Pfad);'#10 +
    '  Abfrage.SQL.LoadFromStream(Strom);'#10'  Text := TFile.ReadAllText(Pfad);'#10'end;'#10'end.';
  Findings := TRuleAssert.Findings(TLoadWithoutEncodingRule.Create, Source);
  Assert.AreEqual(4, Integer(Length(Findings)));
  Assert.AreEqual('SaveToFile ohne Kodierung schreibt mit der ANSI-Codepage; Umlaute gehen auf anderen Rechnern ' +
    'verloren.', Findings[0].Message);
  Assert.AreEqual('TFile.ReadAllText ohne Kodierung liest Dateien ohne BOM mit der ANSI-Codepage.',
    Findings[3].Message);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[3].Fixes[0].Edits);
  Assert.IsTrue(Pos('TFile.ReadAllText(Pfad, TEncoding.UTF8)', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('System.SysUtils', Fixed) > 0, 'uses ergänzt: ' + Fixed);
end;

procedure TPlatformRulesTests.EncodingSilentCases;
begin
  // Mit Kodierung, DefaultEncoding gesetzt, Speichern nach Laden mit Kodierung.
  TRuleAssert.Silent(TLoadWithoutEncodingRule.Create, Routine('var'#10'  Zeilen: TStringList;'#10,
    '  Zeilen.LoadFromFile(Pfad, TEncoding.UTF8);'#10'  Zeilen.SaveToFile(Pfad);'));
  TRuleAssert.Silent(TLoadWithoutEncodingRule.Create, Routine('var'#10'  Zeilen: TStringList;'#10,
    '  Zeilen.DefaultEncoding := TEncoding.UTF8;'#10'  Zeilen.LoadFromFile(Pfad);'));
  // Andere Typen: Bilder, Streams, Datenmengen, unbekannter Typ; TFile.WriteAllText und TStreamReader nehmen UTF-8.
  TRuleAssert.Silent(TLoadWithoutEncodingRule.Create, Routine('var'#10'  Bild: TBitmap;'#10'  Puffer: TMemoryStream;'#10,
    '  Bild.LoadFromFile(Pfad);'#10'  Puffer.SaveToFile(Pfad);'#10'  Tabelle.SaveToFile(Pfad);'#10 +
    '  TFile.WriteAllText(Pfad, Text);'#10'  Leser := TStreamReader.Create(Pfad);'#10 +
    '  Text := TFile.ReadAllText(Pfad, TEncoding.UTF8);'));
end;

procedure TPlatformRulesTests.EncodingOptions;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Routine('var'#10'  Zeilen: TStringList;'#10, '  Zeilen.LoadFromFile(Pfad);');
  Findings := TRuleAssert.Findings(TLoadWithoutEncodingRule.Create, Source,
    '{"rules": {"load-without-encoding": {"defaultEncoding": "unicode"}}}', 'Werkzeug.pas');
  Assert.AreEqual('TEncoding.Unicode ergänzen', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Pos('LoadFromFile(Pfad, TEncoding.Unicode)', TChangeSignature.ApplyEdits(Source,
    Findings[0].Fixes[0].Edits)) > 0);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLoadWithoutEncodingRule.Create, Source,
    '{"rules": {"load-without-encoding": "off"}}', 'Werkzeug.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TLoadWithoutEncodingRule.Create, Source,
    '{"rules": {"load-without-encoding": {"exclude": ["Werkzeug"]}}}', 'Werkzeug.pas'))));
  TConfigurationParser.Parse('{"rules": {"load-without-encoding": {"defaultEncoding": "Latin1"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"defaultEncoding" muss UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 oder Default sein',
    Issues[0].Message);
end;

{ registry-hklm-write }

procedure TPlatformRulesTests.RegistryIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Routine('', '  Reg.RootKey := HKEY_LOCAL_MACHINE;'#10'  Reg.OpenKey(''Software\Firma\Programm'', True);'#10 +
    '  Reg.WriteString(''Sprache'', Sprache);');
  Findings := TRuleAssert.Findings(TRegistryHklmWriteRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Schreiben nach HKEY_LOCAL_MACHINE braucht Administratorrechte; ohne sie schlägt es fehl oder ' +
    'landet in der Virtualisierung.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual('HKEY_CURRENT_USER verwenden', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.IsTrue(Pos('Reg.RootKey := HKEY_CURRENT_USER;', Fixed) > 0, Fixed);
  TRuleAssert.Silent(TRegistryHklmWriteRule.Create, Fixed);
  // Nur WriteInteger, ohne OpenKey.
  TRuleAssert.Reports(TRegistryHklmWriteRule.Create, Routine('', '  R.RootKey := HKEY_LOCAL_MACHINE;'#10 +
    '  R.DeleteValue(''Alt'');'));
end;

procedure TPlatformRulesTests.RegistrySilentCases;
begin
  // Nur lesen, OpenKey ohne Anlegen, anderes Objekt, RootKey vor dem Schreiben zurückgesetzt.
  TRuleAssert.Silent(TRegistryHklmWriteRule.Create, Routine('', '  Reg.RootKey := HKEY_LOCAL_MACHINE;'#10 +
    '  if Reg.OpenKeyReadOnly(''Software\Firma'') then'#10'    Pfad := Reg.ReadString(''Pfad'');'#10 +
    '  Reg.OpenKey(''Software\Firma'', False);'#10'  Andere.WriteString(''a'', ''b'');'));
  TRuleAssert.Silent(TRegistryHklmWriteRule.Create, Routine('', '  Reg.RootKey := HKEY_LOCAL_MACHINE;'#10 +
    '  Pfad := Reg.ReadString(''Pfad'');'#10'  Reg.RootKey := HKEY_CURRENT_USER;'#10 +
    '  Reg.WriteString(''Pfad'', Pfad);'));
  // Schreiben nur im anderen Zweig der bedingten Übersetzung.
  TRuleAssert.Silent(TRegistryHklmWriteRule.Create, Routine('', '{$IFDEF INSTALLER}'#10 +
    '  Reg.RootKey := HKEY_LOCAL_MACHINE;'#10'  Pfad := Reg.ReadString(''Pfad'');'#10'{$ELSE}'#10 +
    '  Reg.WriteString(''Pfad'', Pfad);'#10'{$ENDIF}'));
end;

procedure TPlatformRulesTests.RegistryOptions;
var
  Source: string;
begin
  Source := Routine('', '  Reg.RootKey := HKEY_LOCAL_MACHINE;'#10'  Reg.WriteBool(''Aktiv'', True);');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRegistryHklmWriteRule.Create, Source, '',
    'Setup/Werkzeug.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRegistryHklmWriteRule.Create, Source,
    '{"rules": {"registry-hklm-write": "off"}}', 'Setup/Werkzeug.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRegistryHklmWriteRule.Create, Source,
    '{"rules": {"registry-hklm-write": {"exclude": ["Setup/**"]}}}', 'Setup/Werkzeug.pas'))));
end;

{ now-for-elapsed-time }

procedure TPlatformRulesTests.ElapsedIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Routine('var'#10'  Start: TDateTime;'#10, '  Start := Now;'#10'  Importieren;'#10 +
    '  Log(MilliSecondsBetween(Now, Start).ToString + '' ms'');');
  Findings := TRuleAssert.Findings(TNowForElapsedTimeRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Laufzeit mit Now gemessen; TStopwatch ist genauer und unabhängig von der Uhrzeit.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual('In TStopwatch umwandeln', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual('unit Werkzeug;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils,'#10 +
    '  System.Diagnostics;'#10'procedure Pruefen;'#10'var'#10'  Uhr: TStopwatch;'#10'begin'#10 +
    '  Uhr := TStopwatch.StartNew;'#10'  Importieren;'#10'  Log(Uhr.ElapsedMilliseconds.ToString + '' ms'');'#10 +
    'end;'#10'end.', Fixed);
  TRuleAssert.Silent(TNowForElapsedTimeRule.Create, Fixed);
end;

procedure TPlatformRulesTests.ElapsedVariants;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  // Differenz, Ende - Start, Feld; ohne Korrektur, weil Start auch anders benutzt wird.
  Findings := TRuleAssert.Findings(TNowForElapsedTimeRule.Create, Routine('var'#10'  Start, Ende: TDateTime;'#10,
    '  Start := Now;'#10'  Arbeiten;'#10'  Ende := Now;'#10'  Dauer := Ende - Start;'#10 +
    '  FBeginn := Now;'#10'  if Now - FBeginn > 1 / 24 then'#10'    Abbrechen;'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)));
  // Inline-Variable, SecondsBetween, Name Uhr schon vergeben.
  Source := Routine('', '  var T := Now;'#10'  Uhr := 1;'#10'  Arbeiten;'#10'  Sekunden := SecondsBetween(Now, T);');
  Findings := TRuleAssert.Findings(TNowForElapsedTimeRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.IsTrue(Pos('  var T := TStopwatch.StartNew;', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('Sekunden := T.ElapsedMilliseconds div 1000;', Fixed) > 0, Fixed);
end;

procedure TPlatformRulesTests.ElapsedSilentCases;
begin
  // Zeitstempel ohne Messung, TStopwatch, Now in einer anderen Routine, Abstand zweier fremder Zeitpunkte.
  TRuleAssert.Silent(TNowForElapsedTimeRule.Create, Routine('var'#10'  Erstellt: TDateTime;'#10,
    '  Erstellt := Now;'#10'  Speichern(Erstellt);'#10'  Tage := DaysBetween(Ende, Beginn);'#10 +
    '  Uhr := TStopwatch.StartNew;'));
  TRuleAssert.Silent(TNowForElapsedTimeRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure A;'#10'begin'#10'  FStart := Now;'#10'end;'#10'procedure B;'#10'begin'#10 +
    '  Dauer := Now - FStart;'#10'end;'#10'end.');
  // Start nur im anderen Zweig der bedingten Übersetzung.
  TRuleAssert.Silent(TNowForElapsedTimeRule.Create, Routine('', '{$IFDEF MESSEN}'#10'  Start := Now;'#10 +
    '{$ELSE}'#10'  Dauer := Now - Start;'#10'{$ENDIF}'));
end;

procedure TPlatformRulesTests.ElapsedOptions;
var
  Source: string;
begin
  Source := Routine('', '  Start := Now;'#10'  Dauer := Now - Start;');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TNowForElapsedTimeRule.Create, Source, '',
    'Werkzeug.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TNowForElapsedTimeRule.Create, Source,
    '{"rules": {"now-for-elapsed-time": "off"}}', 'Werkzeug.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TNowForElapsedTimeRule.Create, Source,
    '{"rules": {"now-for-elapsed-time": {"exclude": ["*.pas"]}}}', 'Werkzeug.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TPlatformRulesTests);

end.
