unit Atlas.Common.Rules.WarnSwitches.Tests;

// Tests von TRuleWarnSwitches (#1378): Vorgabe von dcc, Projektoption
// DCC_<Bezeichner> und DCC_Warnings, {$WARN …} ON/OFF/ERROR/DEFAULT, {$WARNINGS},
// Schalter in {$IF}-Zweigen, MentionsAny und die Einträge aus der .dproj.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleWarnSwitchesTests = class
  public
    [Test]
    procedure DefaultAndProjectOption;
    [Test]
    procedure FileSwitchesFromTheirPosition;
    [Test]
    procedure SwitchesInConditionalBranches;
    [Test]
    procedure MentionsAny;
    [Test]
    procedure ProjectEntries;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.WarnSwitches;

/// <summary>Stand der Warnung AName am ersten Bezeichner "Hier" in ASource, als Text.</summary>
function StateText(const ASource, AName: string; ADefaultOn: Boolean;
  const AProjectWarnings: TArray<string>): string;
const
  cNames: array[TRuleWarnState] of string = ('an', 'Fehler', 'aus', 'unbekannt');
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mSwitches: TRuleWarnSwitches;
  mIndex, mHere: Integer;
begin
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.ProjectWarnings := AProjectWarnings;
    mHere := -1;
    for mIndex := 0 to High(mTree.Tokens) do
      if SameText(mTree.Tokens[mIndex].Text, 'Hier') then
      begin
        mHere := mIndex;
        Break;
      end;
    mSwitches := TRuleWarnSwitches.Create(mContext);
    try
      Result := cNames[mSwitches.StateAt(AName, ADefaultOn, mHere)];
    finally
      mSwitches.Free;
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Unit mit ABefore vor und AAfter hinter der Anweisung Hier.</summary>
function Around(const ABefore, AAfter: string): string;
begin
  Result := 'unit Fall;'#10'interface'#10'implementation'#10'procedure Lauf;'#10'begin'#10 + ABefore +
    '  Hier;'#10 + AAfter + 'end;'#10'end.';
end;

function Body(const AText: string): string;
begin
  Result := Around(AText, '');
end;

{ TRuleWarnSwitchesTests }

procedure TRuleWarnSwitchesTests.DefaultAndProjectOption;
begin
  Assert.AreEqual('an', StateText(Body(''), 'SYMBOL_PLATFORM', True, nil));
  Assert.AreEqual('aus', StateText(Body(''), 'UNSAFE_CODE', False, nil));
  Assert.AreEqual('aus', StateText(Body(''), 'SYMBOL_PLATFORM', True, ['SYMBOL_PLATFORM=false']));
  Assert.AreEqual('an', StateText(Body(''), 'UNSAFE_CODE', False, ['UNSAFE_CODE=true']));
  Assert.AreEqual('Fehler', StateText(Body(''), 'unsafe_code', False, ['UNSAFE_CODE=error']));
  Assert.AreEqual('aus', StateText(Body(''), 'SYMBOL_PLATFORM', True, ['WARNINGS=false']));
  // Andere Warnungen der .dproj zählen nicht.
  Assert.AreEqual('an', StateText(Body(''), 'SYMBOL_PLATFORM', True, ['UNIT_PLATFORM=false']));
end;

procedure TRuleWarnSwitchesTests.FileSwitchesFromTheirPosition;
begin
  Assert.AreEqual('aus', StateText(Body('  {$WARN SYMBOL_PLATFORM OFF}'#10), 'SYMBOL_PLATFORM', True, nil));
  Assert.AreEqual('an', StateText(Body('  {$WARN UNSAFE_CODE ON}'#10), 'UNSAFE_CODE', False, nil));
  Assert.AreEqual('Fehler', StateText(Body('  (*$WARN UNSAFE_CODE ERROR*)'#10), 'UNSAFE_CODE', False, nil));
  // DEFAULT kehrt zum Stand des Projekts zurück.
  Assert.AreEqual('an', StateText(Body('  {$WARN UNSAFE_CODE OFF}'#10'  {$WARN UNSAFE_CODE DEFAULT}'#10),
    'UNSAFE_CODE', False, ['UNSAFE_CODE=true']));
  Assert.AreEqual('aus', StateText(Body('  {$WARNINGS OFF}'#10), 'SYMBOL_PLATFORM', True, nil));
  Assert.AreEqual('an', StateText(Body('  {$WARNINGS OFF}'#10'  {$WARNINGS ON}'#10), 'SYMBOL_PLATFORM', True, nil));
  // Ein Schalter hinter der Stelle wirkt dort noch nicht, ein fremder Bezeichner gar nicht.
  Assert.AreEqual('an', StateText(Around('', '  {$WARN SYMBOL_PLATFORM OFF}'#10), 'SYMBOL_PLATFORM', True, nil));
  Assert.AreEqual('an', StateText(Body('  {$WARN UNIT_PLATFORM OFF}'#10), 'SYMBOL_PLATFORM', True, nil));
  // Schalter vor dem Unit-Kopf gelten ebenso.
  Assert.AreEqual('an', StateText('{$WARN UNSAFE_CAST ON}'#10 + Body(''), 'UNSAFE_CAST', False, nil));
end;

procedure TRuleWarnSwitchesTests.SwitchesInConditionalBranches;
begin
  // Im selben Zweig gilt der Schalter, im anderen Zweig nie, danach ist der Stand nicht sicher.
  Assert.AreEqual('aus', StateText(Around('  {$IFDEF DEBUG}'#10'  {$WARN SYMBOL_PLATFORM OFF}'#10, '  {$ENDIF}'#10),
    'SYMBOL_PLATFORM', True, nil));
  Assert.AreEqual('an', StateText(Around('  {$IFDEF DEBUG}'#10'  {$WARN SYMBOL_PLATFORM OFF}'#10'  {$ELSE}'#10,
    '  {$ENDIF}'#10), 'SYMBOL_PLATFORM', True, nil));
  Assert.AreEqual('unbekannt', StateText(Body('  {$IFDEF DEBUG}'#10'  {$WARN SYMBOL_PLATFORM OFF}'#10'  {$ENDIF}'#10),
    'SYMBOL_PLATFORM', True, nil));
end;

procedure TRuleWarnSwitchesTests.MentionsAny;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mSwitches: TRuleWarnSwitches;
begin
  mTree := TPascalParser.Parse(Body('  {$WARN UNSAFE_CAST ON}'#10'  {$WARNINGS ON}'#10));
  try
    mContext := Default(TRuleContext);
    mContext.Tree := mTree;
    mSwitches := TRuleWarnSwitches.Create(mContext);
    try
      Assert.IsTrue(mSwitches.MentionsAny(['UNSAFE_CODE', 'unsafe_cast']));
      Assert.IsFalse(mSwitches.MentionsAny(['UNSAFE_CODE', 'WARNINGS']));
    finally
      mSwitches.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TRuleWarnSwitchesTests.ProjectEntries;
begin
  Assert.AreEqual('SYMBOL_PLATFORM=false', TRuleWarnSwitches.ProjectEntry('DCC_SYMBOL_PLATFORM', 'false'));
  Assert.AreEqual('UNSAFE_CODE=true', TRuleWarnSwitches.ProjectEntry('dcc_unsafe_code', ' True '));
  Assert.AreEqual('WARNINGS=false', TRuleWarnSwitches.ProjectEntry('DCC_Warnings', 'false'));
  Assert.AreEqual('', TRuleWarnSwitches.ProjectEntry('DCC_UnitSearchPath', 'C:\X'));
  Assert.AreEqual('', TRuleWarnSwitches.ProjectEntry('DCC_Define', 'DEBUG'));
  Assert.AreEqual('', TRuleWarnSwitches.ProjectEntry('SYMBOL_PLATFORM', 'false'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleWarnSwitchesTests);

end.
