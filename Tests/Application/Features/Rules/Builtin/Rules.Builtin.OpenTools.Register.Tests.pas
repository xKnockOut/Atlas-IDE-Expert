unit Rules.Builtin.OpenTools.Register.Tests;

// Tests für register-does-work: Timer, Thread, Formular und Aufrufe in Register, reine Anmeldungen, Hilfsroutinen
// nur aus Register bzw. auch von anderswo, anonyme Methoden und eigene Einstiegsroutinen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRegisterDoesWorkRuleTests = class
  public
    [Test]
    procedure IssueExampleReports;
    [Test]
    procedure FormAndCalls;
    [Test]
    procedure OnlyRegistrationsSilent;
    [Test]
    procedure HelperOnlyFromRegister;
    [Test]
    procedure HelperAlsoElsewhereSilent;
    [Test]
    procedure LaterWorkSilent;
    [Test]
    procedure OwnEntriesAndClasses;
    [Test]
    procedure CallPatterns;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Rules.Builtin.OpenTools.Register,
  Atlas.Tests.RuleAssert,
  Atlas.Common.Findings.Contract;

function PackageUnit(const ABody: string; const AHelpers: string = ''): string;
begin
  Result := 'unit U;'#10'interface'#10'procedure Register;'#10'implementation'#10'uses'#10 +
    '  System.Classes, Vcl.ExtCtrls, ToolsAPI;'#10'var'#10'  GTimer: TTimer;'#10 + AHelpers + 'procedure Register;'#10 +
    'begin'#10 + ABody + 'end;'#10'end.';
end;

function Count(const ASource: string; const AConfig: string = ''): Integer;
begin
  Result := Length(TRuleAssert.Findings(TRegisterDoesWorkRule.Create, ASource, AConfig));
end;

{ TRegisterDoesWorkRuleTests }

procedure TRegisterDoesWorkRuleTests.IssueExampleReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TRegisterDoesWorkRule.Create, PackageUnit('  GTimer := TTimer.Create(nil);'#10 +
    '  GTimer.Enabled := True;'#10'  TThread.CreateAnonymousThread(procedure begin Sleep(10) end).Start;'#10 +
    '  RegisterPackageWizard(TMyWizard.Create);'#10));
  Assert.AreEqual(2, Integer(Length(mFindings)), TRuleAssert.LineMessages(mFindings));
  Assert.AreEqual('register-does-work', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Register startet Arbeit (TTimer.Create). Es läuft beim Start der IDE in ungewisser Reihenfolge ' +
    'der Packages: nur anmelden und den Start in einen Wizard, Notifier bzw. die Feature-Tabelle verlegen.',
    mFindings[0].Message);
  Assert.AreEqual(10, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(12, mFindings[0].Range.StartPos.Character);
  Assert.Contains(mFindings[1].Message, '(TThread.CreateAnonymousThread)');
  Assert.AreEqual(12, mFindings[1].Range.StartPos.Line);
end;

procedure TRegisterDoesWorkRuleTests.FormAndCalls;
begin
  Assert.AreEqual(1, Count(PackageUnit('  Application.CreateForm(TSetupForm, SetupForm);'#10)));
  Assert.AreEqual(1, Count(PackageUnit('  TSetupForm.Create(nil).ShowModal;'#10)));
  Assert.AreEqual(1, Count(PackageUnit('  WaitForSingleObject(GEvent, 1000);'#10)));
  Assert.AreEqual(1, Count(PackageUnit('  ShellExecute(0, ''open'', ''x'', nil, nil, 1);'#10)));
  Assert.AreEqual(1, Count(PackageUnit('  TTask.Run(Laden);'#10)));
  Assert.AreEqual(1, Count(PackageUnit('  GThread := TThread.Create(True);'#10)));
  // Eigener Nachfahr von TForm aus der Unit.
  Assert.AreEqual(1, Count('unit U;'#10'interface'#10'procedure Register;'#10'implementation'#10'type'#10 +
    '  TSetupForm = class(TForm)'#10'  end;'#10'procedure Register;'#10'begin'#10'  GForm := TSetupForm.Create(nil);'#10 +
    'end;'#10'end.'));
end;

procedure TRegisterDoesWorkRuleTests.OnlyRegistrationsSilent;
begin
  TRuleAssert.Silent(TRegisterDoesWorkRule.Create, PackageUnit('  RegisterPackageWizard(TMyWizard.Create);'#10 +
    '  RegisterComponents(''Atlas'', [TAtlasButton]);'#10'  RegisterPropertyEditor(TypeInfo(string), nil, '''', ' +
    'TPfadEditor);'#10'  GIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TNotifier.Create);'#10 +
    '  RegisterKeyboardBinding(TBinding.Create);'#10));
end;

procedure TRegisterDoesWorkRuleTests.HelperOnlyFromRegister;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TRegisterDoesWorkRule.Create, PackageUnit('  Starten;'#10,
    'procedure Starten;'#10'begin'#10'  GTimer := TTimer.Create(nil);'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Register startet über Starten Arbeit (TTimer.Create). Es läuft beim Start der IDE in ' +
    'ungewisser Reihenfolge der Packages: nur anmelden und den Start in einen Wizard, Notifier bzw. die ' +
    'Feature-Tabelle verlegen.', mFindings[0].Message);
  // Auch über zwei Stufen.
  Assert.AreEqual(1, Count(PackageUnit('  Starten;'#10, 'procedure Tief;'#10'begin'#10'  Sleep(100);'#10'end;'#10 +
    'procedure Starten;'#10'begin'#10'  Tief;'#10'end;'#10)));
end;

procedure TRegisterDoesWorkRuleTests.HelperAlsoElsewhereSilent;
const
  cHelper = 'procedure Starten;'#10'begin'#10'  GTimer := TTimer.Create(nil);'#10'end;'#10;
begin
  // Auch vom Wizard aufgerufen: kein Teil von Register.
  TRuleAssert.Silent(TRegisterDoesWorkRule.Create, PackageUnit('  Starten;'#10, cHelper +
    'procedure TMyWizard.Execute;'#10'begin'#10'  Starten;'#10'end;'#10));
  // Im interface-Teil: andere Units können sie aufrufen.
  TRuleAssert.Silent(TRegisterDoesWorkRule.Create, StringReplace(PackageUnit('  Starten;'#10, cHelper),
    'procedure Register;'#10'implementation', 'procedure Register;'#10'procedure Starten;'#10'implementation', []));
end;

procedure TRegisterDoesWorkRuleTests.LaterWorkSilent;
begin
  // Anonyme Methoden und übergebene Routinen laufen später.
  TRuleAssert.Silent(TRegisterDoesWorkRule.Create, PackageUnit(
    '  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings, AfterStart);'#10 +
    '  TAtlasMainThread.Queue(procedure begin GTimer := TTimer.Create(nil); end);'#10,
    'procedure AfterStart;'#10'begin'#10'  GTimer := TTimer.Create(nil);'#10'end;'#10));
  // Andere Routinen namens Register (Methoden) sind keine Einstiegsroutinen.
  TRuleAssert.Silent(TRegisterDoesWorkRule.Create, 'unit U;'#10'interface'#10'type'#10'  TPrompts = class'#10 +
    '    procedure Register;'#10'  end;'#10'implementation'#10'procedure TPrompts.Register;'#10'begin'#10 +
    '  Sleep(10);'#10'end;'#10'end.');
end;

procedure TRegisterDoesWorkRuleTests.OwnEntriesAndClasses;
const
  cModule = 'unit U;'#10'interface'#10'type'#10'  TModul = class'#10'    class function RegisterModule: Boolean;'#10 +
    '  end;'#10'implementation'#10'class function TModul.RegisterModule: Boolean;'#10'begin'#10 +
    '  GClient := THTTPClient.Create;'#10'  GSuche := TSuche.Create;'#10'  Result := True;'#10'end;'#10'end.';
begin
  Assert.AreEqual(0, Count(cModule));
  Assert.AreEqual(1, Count(cModule, '{"rules": {"register-does-work": {"entries": ["Register", "*.RegisterModule"]}}}'));
  Assert.AreEqual(2, Count(cModule, '{"rules": {"register-does-work": {"entries": ["*.RegisterModule"], ' +
    '"workClasses": ["THTTPClient", "TSuche"]}}}'));
  Assert.AreEqual(0, Count(PackageUnit('  Sleep(10);'#10), '{"rules": {"register-does-work": {"workCalls": []}}}'));
end;

procedure TRegisterDoesWorkRuleTests.CallPatterns;
begin
  Assert.IsTrue(MatchesCallPattern('mForm.ShowModal', 'ShowModal'));
  Assert.IsTrue(MatchesCallPattern('WaitForSingleObject', 'WaitFor*'));
  Assert.IsTrue(MatchesCallPattern('TTask.Run', 'TTask.Run'));
  Assert.IsFalse(MatchesCallPattern('FQueue.Run', 'TTask.Run'));
  Assert.IsTrue(MatchesCallPattern('Application.CreateForm', 'application.createform'));
end;

procedure TRegisterDoesWorkRuleTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := PackageUnit('  Sleep(10);'#10);
  Assert.AreEqual(0, Count(mSource, '{"rules": {"register-does-work": "off"}}'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRegisterDoesWorkRule.Create, mSource,
    '{"rules": {"register-does-work": {"exclude": ["U.pas"]}}}', 'U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TRegisterDoesWorkRuleTests);

end.
