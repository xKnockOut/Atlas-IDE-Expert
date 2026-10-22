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

initialization
  TDUnitX.RegisterTestFixture(TPlatformRulesTests);

end.
