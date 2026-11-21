unit Atlas.Common.Rules.Builtin.OpenTools.EntryGuard.Tests;

// Tests für ota-entry-without-guard: Notifier ohne Schutz, mit try … except, mit Schutzroutine, leere Rümpfe und
// reine Zuweisungen, Methoden außerhalb eines Einstiegspunkts, Tastaturbindungen, Menüeinträge und die Korrekturen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TOtaEntryWithoutGuardRuleTests = class
  public
    [Test]
    procedure IssueExampleReports;
    [Test]
    procedure TryExceptIsSilent;
    [Test]
    procedure GuardRoutineIsSilent;
    [Test]
    procedure EmptyAndAssigningBodiesSilent;
    [Test]
    procedure NoEntryPointSilent;
    [Test]
    procedure SafeCallsAndUnitRoutines;
    [Test]
    procedure CallAndAsCastReport;
    [Test]
    procedure InheritedInterfaceAndOption;
    [Test]
    procedure KeyBindingProcedures;
    [Test]
    procedure MenuHandlersInPackage;
    [Test]
    procedure GuardFixWrapsBody;
    [Test]
    procedure LoggerFixWrapsTry;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.OpenTools.EntryGuard,
  Atlas.Common.Documents.TextChanges,
  Atlas.Tests.RuleAssert;

const
  cGuardConfig = '{"rules": {"ota-entry-without-guard": {"guards": ["TAtlasGuard.Run"]}}}';

function NotifierUnit(const AFields, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils, ToolsAPI;'#10'type'#10 +
    '  TSaveNotifier = class(TNotifierObject, IOTAIDENotifier)'#10'  private'#10 + AFields +
    '    procedure Helper;'#10'  public'#10 +
    '    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);'#10 +
    '  end;'#10'implementation'#10'procedure TSaveNotifier.Helper;'#10'begin'#10'  Pruefen;'#10'end;'#10 +
    'procedure TSaveNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;'#10 +
    '  var Cancel: Boolean);'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

function Count(const ASource: string; const AConfig: string = ''): Integer;
begin
  Result := Length(TRuleAssert.Findings(TOtaEntryWithoutGuardRule.Create, ASource, AConfig));
end;

{ TOtaEntryWithoutGuardRuleTests }

procedure TOtaEntryWithoutGuardRuleTests.IssueExampleReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOtaEntryWithoutGuardRule.Create,
    NotifierUnit('', '  if FileName = '''' then'#10'    raise Exception.Create(''leer'');'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('ota-entry-without-guard', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Die IDE ruft FileNotification auf; raise erreicht die IDE. Den Rumpf in try … except legen ' +
    'oder über eine Schutzroutine laufen lassen.', mFindings[0].Message);
  Assert.AreEqual(16, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(24, mFindings[0].Range.StartPos.Character);
  // Ohne Schutzroutine und ohne Protokoll keine Korrektur.
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TOtaEntryWithoutGuardRuleTests.TryExceptIsSilent;
begin
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, NotifierUnit('', '  try'#10'    Pruefen(FileName);'#10 +
    '  except'#10'    on E: Exception do'#10'      Log(E.Message);'#10'  end;'#10));
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, NotifierUnit('', '  if FileName = '''' then'#10'    Exit;'#10 +
    '  try'#10'    Pruefen(FileName);'#10'  except'#10'  end;'#10));
  // Nur EConvertError gefangen, oder raise im Handler: Die Ausnahme erreicht die IDE.
  Assert.AreEqual(1, Count(NotifierUnit('', '  try'#10'    Pruefen(FileName);'#10'  except'#10 +
    '    on E: EConvertError do'#10'      Log(E.Message);'#10'  end;'#10)));
  Assert.AreEqual(1, Count(NotifierUnit('', '  try'#10'    Pruefen(FileName);'#10'  except'#10 +
    '    Log(''x'');'#10'    raise;'#10'  end;'#10)));
  // try … finally schützt nicht.
  Assert.AreEqual(1, Count(NotifierUnit('', '  try'#10'    Pruefen(FileName);'#10'  finally'#10'    Cancel := False;'#10 +
    '  end;'#10)));
end;

procedure TOtaEntryWithoutGuardRuleTests.GuardRoutineIsSilent;
var
  mSource: string;
begin
  mSource := NotifierUnit('', '  if FileName = '''' then'#10'    Exit;'#10 +
    '  TAtlasGuard.Run(TAtlasFeature.Hover,'#10'    procedure'#10'    begin'#10'      Pruefen(FileName);'#10 +
    '    end);'#10);
  Assert.AreEqual(0, Count(mSource, cGuardConfig));
  // Ohne die Option ist TAtlasGuard.Run ein gewöhnlicher Aufruf.
  Assert.AreEqual(1, Count(mSource));
  // Auch als Bedingung und mit Klammer in der Option.
  Assert.AreEqual(0, Count(NotifierUnit('', '  if not TAtlasGuard.Run(TAtlasFeature.Hover, Helper) then'#10 +
    '    Cancel := True;'#10),
    '{"rules": {"ota-entry-without-guard": {"guards": ["TAtlasGuard.Run(TAtlasFeature.Hover, "]}}}'));
end;

procedure TOtaEntryWithoutGuardRuleTests.EmptyAndAssigningBodiesSilent;
const
  cWizard = 'unit U;'#10'interface'#10'type'#10'  TWizard = class(TNotifierObject, IOTAWizard)'#10'  private'#10 +
    '    FState: Integer;'#10'  public'#10'    function GetIDString: string;'#10'    function GetName: string;'#10 +
    '    procedure Execute;'#10'  end;'#10'implementation'#10'function TWizard.GetIDString: string;'#10'begin'#10 +
    '  Result := ''Atlas.Wizard'';'#10'end;'#10'function TWizard.GetName: string;'#10'begin'#10 +
    '  Result := Format(''%s'', [''Atlas'']);'#10'  FState := 1;'#10'end;'#10'procedure TWizard.Execute;'#10 +
    'begin'#10'end;'#10'end.';
begin
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, NotifierUnit('', ''));
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, NotifierUnit('', '  Cancel := False;'#10));
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, cWizard);
  // Eine Zuweisung mit as kann scheitern.
  Assert.AreEqual(1, Count(StringReplace(cWizard, '  FState := 1;', '  FState := (FOwner as TState).Wert;', []
    )));
end;

procedure TOtaEntryWithoutGuardRuleTests.NoEntryPointSilent;
begin
  // Klasse ohne IDE-Interface.
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, StringReplace(NotifierUnit('', '  Pruefen(FileName);'#10),
    'class(TNotifierObject, IOTAIDENotifier)', 'class(TObject)', []));
  // Private Hilfsmethode eines Notifiers ist kein Einstiegspunkt (Helper ruft Pruefen).
  Assert.AreEqual(0, Count(NotifierUnit('', '')));
end;

procedure TOtaEntryWithoutGuardRuleTests.SafeCallsAndUnitRoutines;
const
  cFree = 'unit U;'#10'interface'#10'type'#10'  TN = class(TNotifierObject, IOTAIDENotifier)'#10'  public'#10 +
    '    procedure AfterCompile(Succeeded: Boolean);'#10'  end;'#10'implementation'#10 +
    'function Wichtig(AValue: Boolean): Boolean;'#10'begin'#10'  Result := not AValue;'#10'end;'#10 +
    'procedure TN.AfterCompile(Succeeded: Boolean);'#10'begin'#10'  if Wichtig(Succeeded) and Assigned(Self) and ' +
    '(Length(ClassName) > 0) then'#10'    Inc(GCount);'#10'  inherited;'#10'end;'#10'end.';
begin
  // Eingebaute Routinen, inherited und Routinen der Unit, die selbst nicht werfen.
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, cFree);
  // Wirft die Routine der Unit, zählt ihr Aufruf.
  Assert.AreEqual(1, Count(StringReplace(cFree, '  Result := not AValue;', '  Result := Pruefen(AValue);', [])));
  // Anonyme Methoden laufen später; ihr Rumpf zählt nicht, der Aufruf schon.
  Assert.AreEqual(1, Count(NotifierUnit('', '  TAtlasMainThread.Queue(procedure begin Pruefen(FileName); end);'#10
    )));
  // Typumwandlung.
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, NotifierUnit('', '  if Integer(NotifyCode) = 3 then'#10 +
    '    Cancel := Pointer(Self) = nil;'#10));
  // Harte Umwandlung in einen Typ, den der Index nicht kennt (VCL, Open Tools API).
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, NotifierUnit('', '  if TMenuItem(Self).Tag = 1 then'#10 +
    '    Cancel := IOTAModule(Self) = nil;'#10));
end;

procedure TOtaEntryWithoutGuardRuleTests.CallAndAsCastReport;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOtaEntryWithoutGuardRule.Create, NotifierUnit('',
    '  if FileName = '''' then'#10'    Exit;'#10'  FOwner.Notified(FileName);'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Die IDE ruft FileNotification auf; eine Ausnahme aus FOwner.Notified erreicht die IDE. Den ' +
    'Rumpf in try … except legen oder über eine Schutzroutine laufen lassen.', mFindings[0].Message);
  mFindings := TRuleAssert.Findings(TOtaEntryWithoutGuardRule.Create, NotifierUnit('',
    '  if (FOwner as TOwner).Active then'#10'    Cancel := True;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'Umwandlung mit as');
end;

procedure TOtaEntryWithoutGuardRuleTests.InheritedInterfaceAndOption;
const
  cDerived = 'unit U;'#10'interface'#10'type'#10'  TBase = class(TNotifierObject, INTAEditServicesNotifier)'#10 +
    '  end;'#10'  TEdit = class(TBase)'#10'  public'#10'    procedure WindowActivated(const EditWindow: INTAEditWindow);'#10 +
    '  end;'#10'implementation'#10'procedure TEdit.WindowActivated(const EditWindow: INTAEditWindow);'#10'begin'#10 +
    '  Aktualisieren;'#10'end;'#10'end.';
begin
  // Das Interface kommt über den Vorfahren der Unit.
  Assert.AreEqual(1, Count(cDerived));
  // Eigene Liste der Interfaces ersetzt die Vorgabe.
  Assert.AreEqual(0, Count(cDerived, '{"rules": {"ota-entry-without-guard": {"interfaces": ["IOTAWizard"]}}}'));
  Assert.AreEqual(1, Count(StringReplace(cDerived, 'INTAEditServicesNotifier', 'IMeinPlugin', []),
    '{"rules": {"ota-entry-without-guard": {"interfaces": ["IMein*"]}}}'));
end;

procedure TOtaEntryWithoutGuardRuleTests.KeyBindingProcedures;
const
  cBinding = 'unit U;'#10'interface'#10'type'#10'  TBinding = class(TNotifierObject, IOTAKeyboardBinding)'#10 +
    '  private'#10'    procedure Springen(const Context: IOTAKeyContext; KeyCode: TShortcut;'#10 +
    '      var BindingResult: TKeyBindingResult);'#10'  public'#10 +
    '    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);'#10'  end;'#10'implementation'#10 +
    'procedure TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);'#10'begin'#10 +
    '  try'#10'    BindingServices.AddKeyBinding([ShortCut(Ord(''J''), [ssCtrl])], Springen, nil);'#10 +
    '  except'#10'  end;'#10'end;'#10 +
    'procedure TBinding.Springen(const Context: IOTAKeyContext; KeyCode: TShortcut;'#10 +
    '  var BindingResult: TKeyBindingResult);'#10'begin'#10'  Context.EditBuffer.EditPosition.MoveBOL;'#10 +
    '  BindingResult := krHandled;'#10'end;'#10'end.';
var
  mFindings: TArray<TRuleFinding>;
begin
  // Die gebundene private Methode ist ein Einstiegspunkt.
  mFindings := TRuleAssert.Findings(TOtaEntryWithoutGuardRule.Create, cBinding);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'Springen');
end;

procedure TOtaEntryWithoutGuardRuleTests.MenuHandlersInPackage;
const
  cMenu = 'unit U;'#10'interface'#10'type'#10'  TExpert = class'#10'  private'#10 +
    '    procedure Klick(Sender: TObject);'#10'    procedure Anderes(Sender: TObject);'#10'  public'#10 +
    '    procedure Einhaengen;'#10'  end;'#10'implementation'#10'procedure TExpert.Einhaengen;'#10'var'#10 +
    '  mItem: TMenuItem;'#10'begin'#10'  mItem := TMenuItem.Create(nil);'#10'  mItem.OnClick := Klick;'#10 +
    '  (BorlandIDEServices as INTAServices).MainMenu.Items.Add(mItem);'#10'end;'#10'procedure TExpert.Klick(Sender: TObject);'#10'begin'#10'  Ausfuehren;'#10'end;'#10 +
    'procedure TExpert.Anderes(Sender: TObject);'#10'begin'#10'  Ausfuehren;'#10'end;'#10'end.';
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.PackageFindings(TOtaEntryWithoutGuardRule.Create, cMenu, 'P', '', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'Klick');
  // Außerhalb eines Packages fängt die Anwendung die Ausnahme.
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, cMenu);
  // Eigenes Kontextmenü, nicht in die IDE gehängt: Die Anwendung fängt die Ausnahme.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.PackageFindings(TOtaEntryWithoutGuardRule.Create,
    StringReplace(cMenu, '  (BorlandIDEServices as INTAServices).MainMenu.Items.Add(mItem);'#10, '', []), 'P', '',
    'U.pas'))));
end;

procedure TOtaEntryWithoutGuardRuleTests.GuardFixWrapsBody;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := StringReplace(NotifierUnit('', '  if FileName = '''' then'#10'    Exit;'#10'  Pruefen(FileName);'#10),
    'var Cancel: Boolean', 'Cancel: Boolean', [rfReplaceAll]);
  mFindings := TRuleAssert.Findings(TOtaEntryWithoutGuardRule.Create, mSource,
    '{"rules": {"ota-entry-without-guard": {"guards": ["TAtlasGuard.Run(TAtlasFeature.Hover, "]}}}');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Rumpf über TAtlasGuard.Run laufen lassen', mFindings[0].Fixes[0].Title);
  mFixed := TTextChanges.Apply(mSource, mFindings[0].Fixes[0].Edits);
  Assert.Contains(mFixed, 'begin'#10'  TAtlasGuard.Run(TAtlasFeature.Hover,'#10'    procedure'#10'    begin'#10 +
    '      if FileName = '''' then'#10'        Exit;'#10'      Pruefen(FileName);'#10'    end);'#10'end;');
  Assert.AreEqual(0, Count(mFixed, cGuardConfig));
  // Ein var-Parameter im Rumpf lässt sich nicht einfangen: keine Korrektur.
  mFindings := TRuleAssert.Findings(TOtaEntryWithoutGuardRule.Create, NotifierUnit('',
    '  Cancel := Pruefen(FileName);'#10'  Melden;'#10), cGuardConfig);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TOtaEntryWithoutGuardRuleTests.LoggerFixWrapsTry;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := NotifierUnit('    FLogger: ILogger;'#10, '  Pruefen(FileName);'#10'  Melden;'#10);
  mFindings := TRuleAssert.Findings(TOtaEntryWithoutGuardRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Rumpf in try … except mit Meldung über FLogger einschließen', mFindings[0].Fixes[0].Title);
  mFixed := TTextChanges.Apply(mSource, mFindings[0].Fixes[0].Edits);
  Assert.Contains(mFixed, '  try'#10'    Pruefen(FileName);'#10'    Melden;'#10'  except'#10'    on E: Exception do'#10 +
    '      FLogger.Error(ClassName + ''.FileNotification: '' + E.Message);'#10'  end;'#10);
  TRuleAssert.Silent(TOtaEntryWithoutGuardRule.Create, mFixed);
end;

procedure TOtaEntryWithoutGuardRuleTests.OffAndExclude;
var
  mSource: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSource := NotifierUnit('', '  Pruefen(FileName);'#10);
  Assert.AreEqual(0, Count(mSource, '{"rules": {"ota-entry-without-guard": "off"}}'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOtaEntryWithoutGuardRule.Create, mSource,
    '{"rules": {"ota-entry-without-guard": {"exclude": ["U.pas"]}}}', 'U.pas'))));
  TConfigurationParser.Parse('{"rules": {"ota-entry-without-guard": {"guards": "TAtlasGuard.Run"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;

initialization
  TDUnitX.RegisterTestFixture(TOtaEntryWithoutGuardRuleTests);

end.
