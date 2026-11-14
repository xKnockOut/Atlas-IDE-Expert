unit Atlas.Common.Editing.DisableWarning.Tests;

// Tests für „Warnung hier abschalten“ (#531): erzeugter Text für Zeile,
// Routine und Unit ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDisableWarningTests = class
  public
    /// <summary>Abnahme: W1000 bekommt {$WARN SYMBOL_DEPRECATED OFF} … ON um die Zeile.</summary>
    [Test]
    procedure WarningAroundLine;
    /// <summary>Abnahme: H2164 bekommt {$HINTS OFF} … {$HINTS ON}, als Ablaufmeldung um die Routine.</summary>
    [Test]
    procedure HintAroundRoutine;
    [Test]
    procedure WarningWithoutIdentifierSwitchesAll;
    [Test]
    procedure ReasonBecomesComment;
    [Test]
    procedure UnitWideAfterHeader;
    [Test]
    procedure NestedRoutineWins;
    [Test]
    procedure NoRoutineOutsideBodies;
    [Test]
    procedure KeepsLineBreaks;
    [Test]
    procedure RefusesErrors;
    [Test]
    procedure OlderVersionFallsBackToWarnings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.DisableWarning;

const
  cSource =
    'unit A;' + #10 +                    // 0
    '' + #10 +                           // 1
    'interface' + #10 +                  // 2
    '' + #10 +                           // 3
    'implementation' + #10 +             // 4
    '' + #10 +                           // 5
    'procedure Foo;' + #10 +             // 6
    'var' + #10 +                        // 7
    '  X: Integer;' + #10 +              // 8
    'begin' + #10 +                      // 9
    '  Alt;' + #10 +                     // 10
    'end;' + #10 +                       // 11
    '' + #10 +                           // 12
    'end.';                              // 13

function Disabled(const AText: string; ALine: Integer; const ACode: string; AScope: TDisableWarningScope;
  const AReason: string; const AVersion: string): string; overload;
var
  mTree: TSyntaxTree;
  mSwitch: TDisableWarningSwitch;
  mEdits: TArray<TTextEdit>;
begin
  Result := '';
  Assert.IsTrue(TDisableWarning.SwitchFor(ACode, AVersion, mSwitch), ACode);
  mTree := TPascalParser.Parse(AText);
  try
    if TDisableWarning.Edits(AText, mTree, ALine, TDisableWarningRequest.Create(mSwitch, AScope, AReason), mEdits) then
    begin
      Result := TChangeSignature.ApplyEdits(AText, mEdits);
    end;
  finally
    mTree.Free;
  end;
end;

function Disabled(const AText: string; ALine: Integer; const ACode: string;
  AScope: TDisableWarningScope): string; overload;
begin
  Result := Disabled(AText, ALine, ACode, AScope, '', '');
end;

procedure TDisableWarningTests.WarningAroundLine;
begin
  Assert.AreEqual(StringReplace(cSource, '  Alt;' + #10, '  {$WARN SYMBOL_DEPRECATED OFF}' + #10 + '  Alt;' + #10 +
    '  {$WARN SYMBOL_DEPRECATED ON}' + #10, []), Disabled(cSource, 10, 'W1000', TDisableWarningScope.Line));
end;

procedure TDisableWarningTests.HintAroundRoutine;
var
  mSwitch: TDisableWarningSwitch;
begin
  Assert.IsTrue(TDisableWarning.SwitchFor('H2164', '', mSwitch));
  Assert.IsTrue(mSwitch.RoutineWide);
  Assert.AreEqual(StringReplace(StringReplace(cSource, 'procedure Foo;', '{$HINTS OFF}' + #10 + 'procedure Foo;', []),
    'end;' + #10, 'end;' + #10 + '{$HINTS ON}' + #10, []), Disabled(cSource, 8, 'H2164',
    TDisableWarningScope.Routine));
  // Auch um die Zeile möglich (der Server bietet das für Ablaufmeldungen nicht an).
  Assert.AreEqual(StringReplace(cSource, '  X: Integer;' + #10, '  {$HINTS OFF}' + #10 + '  X: Integer;' + #10 +
    '  {$HINTS ON}' + #10, []), Disabled(cSource, 8, 'H2164', TDisableWarningScope.Line));
end;

procedure TDisableWarningTests.WarningWithoutIdentifierSwitchesAll;
var
  mSwitch: TDisableWarningSwitch;
begin
  Assert.IsTrue(TDisableWarning.SwitchFor('W1999', '', mSwitch));
  Assert.IsTrue(mSwitch.AllWarnings);
  Assert.AreEqual('{$WARNINGS OFF}', mSwitch.OffText);
  Assert.AreEqual('{$WARNINGS ON}', mSwitch.OnText);
  Assert.IsTrue(TDisableWarning.SwitchFor('W1000', '', mSwitch));
  Assert.IsFalse(mSwitch.AllWarnings);
  Assert.IsTrue(TDisableWarning.SwitchFor('H2443', '', mSwitch));
  Assert.IsFalse(mSwitch.AllWarnings, 'Hinweise betreffen nur Hinweise');
end;

procedure TDisableWarningTests.ReasonBecomesComment;
begin
  Assert.AreEqual(StringReplace(cSource, '  Alt;' + #10, '  {$WARN SYMBOL_DEPRECATED OFF} // bewusst, bis 2027' +
    #10 + '  Alt;' + #10 + '  {$WARN SYMBOL_DEPRECATED ON}' + #10, []), Disabled(cSource, 10, 'W1000',
    TDisableWarningScope.Line, '  bewusst,'#13#10'bis 2027 ', ''));
  Assert.AreEqual('', TDisableWarning.ReasonComment('   '));
end;

procedure TDisableWarningTests.UnitWideAfterHeader;
const
  cHeader = '// Kopfkommentar' + #10 + '{$I Atlas.inc}' + #10 + 'unit' + #10 + '  A.B;' + #10 + 'interface' + #10 +
    'end.';
begin
  Assert.AreEqual(StringReplace(cSource, 'unit A;', 'unit A;' + #10 + '{$WARN SYMBOL_DEPRECATED OFF} // Altlast', []),
    Disabled(cSource, 10, 'W1000', TDisableWarningScope.UnitWide, 'Altlast', ''));
  Assert.AreEqual(StringReplace(cHeader, '  A.B;', '  A.B;' + #10 + '{$HINTS OFF}', []),
    Disabled(cHeader, 4, 'H2443', TDisableWarningScope.UnitWide));
  Assert.AreEqual('', Disabled('procedure X;' + #10 + 'begin' + #10 + 'end;', 1, 'H2443',
    TDisableWarningScope.UnitWide), 'Include-Datei ohne Kopf');
end;

procedure TDisableWarningTests.NestedRoutineWins;
const
  cNested =
    'unit A;' + #10 + 'interface' + #10 + 'implementation' + #10 +
    'procedure Outer;' + #10 +           // 3
    '  procedure Inner;' + #10 +         // 4
    '  var' + #10 +                      // 5
    '    Y: Integer;' + #10 +            // 6
    '  begin' + #10 +                    // 7
    '  end;' + #10 +                     // 8
    'begin' + #10 +                      // 9
    '  Inner;' + #10 +                   // 10
    'end;' + #10 + 'end.';
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cNested);
  try
    Assert.AreEqual('Inner', TDisableWarning.RoutineAt(mTree, 6).Name);
    Assert.AreEqual('Outer', TDisableWarning.RoutineAt(mTree, 10).Name);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(StringReplace(StringReplace(cNested, '  procedure Inner;', '  {$HINTS OFF}' + #10 +
    '  procedure Inner;', []), '  end;' + #10, '  end;' + #10 + '  {$HINTS ON}' + #10, []),
    Disabled(cNested, 6, 'H2164', TDisableWarningScope.Routine));
end;

procedure TDisableWarningTests.NoRoutineOutsideBodies;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsNull(TDisableWarning.RoutineAt(mTree, 2));
    Assert.IsNull(TDisableWarning.RoutineAt(mTree, 13));
  finally
    mTree.Free;
  end;
  Assert.AreEqual('', Disabled(cSource, 2, 'W1000', TDisableWarningScope.Routine));
  Assert.AreEqual('', Disabled(cSource, 99, 'W1000', TDisableWarningScope.Line));
end;

procedure TDisableWarningTests.KeepsLineBreaks;
var
  mCrlf: string;
begin
  mCrlf := StringReplace(cSource, #10, #13#10, [rfReplaceAll]);
  Assert.AreEqual(StringReplace(mCrlf, '  Alt;' + #13#10, '  {$WARN SYMBOL_DEPRECATED OFF}' + #13#10 + '  Alt;' +
    #13#10 + '  {$WARN SYMBOL_DEPRECATED ON}' + #13#10, []), Disabled(mCrlf, 10, 'W1000', TDisableWarningScope.Line));
  // Letzte Zeile ohne Umbruch am Ende.
  Assert.AreEqual(StringReplace(cSource, 'end.', '{$HINTS OFF}' + #10 + 'end.' + #10 + '{$HINTS ON}', []),
    Disabled(cSource, 13, 'H2443', TDisableWarningScope.Line));
end;

procedure TDisableWarningTests.RefusesErrors;
var
  mSwitch: TDisableWarningSwitch;
begin
  Assert.IsFalse(TDisableWarning.SwitchFor('E2003', '', mSwitch));
  Assert.IsFalse(TDisableWarning.SwitchFor('F2613', '', mSwitch));
  Assert.IsFalse(TDisableWarning.SwitchFor('', '', mSwitch));
end;

procedure TDisableWarningTests.OlderVersionFallsBackToWarnings;
var
  mSwitch: TDisableWarningSwitch;
begin
  Assert.IsTrue(TDisableWarning.SwitchFor('W1071', '21.0', mSwitch));
  Assert.IsTrue(mSwitch.AllWarnings);
  Assert.AreEqual('{$WARNINGS OFF}', mSwitch.OffText);
  Assert.IsTrue(TDisableWarning.SwitchFor('W1071', '37.0', mSwitch));
  Assert.AreEqual('{$WARN IMPLICIT_INTEGER_CAST_LOSS OFF}', mSwitch.OffText);
end;

initialization
  TDUnitX.RegisterTestFixture(TDisableWarningTests);

end.
