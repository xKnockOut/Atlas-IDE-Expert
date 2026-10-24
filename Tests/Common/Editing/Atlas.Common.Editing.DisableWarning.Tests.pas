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
  Source =
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
  Tree: TSyntaxTree;
  Switch: TDisableWarningSwitch;
  Edits: TArray<TTextEdit>;
begin
  Result := '';
  Assert.IsTrue(TDisableWarning.SwitchFor(ACode, AVersion, Switch), ACode);
  Tree := TPascalParser.Parse(AText);
  try
    if TDisableWarning.Edits(AText, Tree, ALine, Switch, AScope, AReason, Edits) then
      Result := TChangeSignature.ApplyEdits(AText, Edits);
  finally
    Tree.Free;
  end;
end;

function Disabled(const AText: string; ALine: Integer; const ACode: string;
  AScope: TDisableWarningScope): string; overload;
begin
  Result := Disabled(AText, ALine, ACode, AScope, '', '');
end;

procedure TDisableWarningTests.WarningAroundLine;
begin
  Assert.AreEqual(StringReplace(Source, '  Alt;' + #10, '  {$WARN SYMBOL_DEPRECATED OFF}' + #10 + '  Alt;' + #10 +
    '  {$WARN SYMBOL_DEPRECATED ON}' + #10, []), Disabled(Source, 10, 'W1000', TDisableWarningScope.Line));
end;

procedure TDisableWarningTests.HintAroundRoutine;
var
  Switch: TDisableWarningSwitch;
begin
  Assert.IsTrue(TDisableWarning.SwitchFor('H2164', '', Switch));
  Assert.IsTrue(Switch.RoutineWide);
  Assert.AreEqual(StringReplace(StringReplace(Source, 'procedure Foo;', '{$HINTS OFF}' + #10 + 'procedure Foo;', []),
    'end;' + #10, 'end;' + #10 + '{$HINTS ON}' + #10, []), Disabled(Source, 8, 'H2164',
    TDisableWarningScope.Routine));
  // Auch um die Zeile möglich (der Server bietet das für Ablaufmeldungen nicht an).
  Assert.AreEqual(StringReplace(Source, '  X: Integer;' + #10, '  {$HINTS OFF}' + #10 + '  X: Integer;' + #10 +
    '  {$HINTS ON}' + #10, []), Disabled(Source, 8, 'H2164', TDisableWarningScope.Line));
end;

procedure TDisableWarningTests.WarningWithoutIdentifierSwitchesAll;
var
  Switch: TDisableWarningSwitch;
begin
  Assert.IsTrue(TDisableWarning.SwitchFor('W1999', '', Switch));
  Assert.IsTrue(Switch.AllWarnings);
  Assert.AreEqual('{$WARNINGS OFF}', Switch.OffText);
  Assert.AreEqual('{$WARNINGS ON}', Switch.OnText);
  Assert.IsTrue(TDisableWarning.SwitchFor('W1000', '', Switch));
  Assert.IsFalse(Switch.AllWarnings);
  Assert.IsTrue(TDisableWarning.SwitchFor('H2443', '', Switch));
  Assert.IsFalse(Switch.AllWarnings, 'Hinweise betreffen nur Hinweise');
end;

procedure TDisableWarningTests.ReasonBecomesComment;
begin
  Assert.AreEqual(StringReplace(Source, '  Alt;' + #10, '  {$WARN SYMBOL_DEPRECATED OFF} // bewusst, bis 2027' +
    #10 + '  Alt;' + #10 + '  {$WARN SYMBOL_DEPRECATED ON}' + #10, []), Disabled(Source, 10, 'W1000',
    TDisableWarningScope.Line, '  bewusst,'#13#10'bis 2027 ', ''));
  Assert.AreEqual('', TDisableWarning.ReasonComment('   '));
end;

procedure TDisableWarningTests.UnitWideAfterHeader;
const
  Header = '// Kopfkommentar' + #10 + '{$I Atlas.inc}' + #10 + 'unit' + #10 + '  A.B;' + #10 + 'interface' + #10 +
    'end.';
begin
  Assert.AreEqual(StringReplace(Source, 'unit A;', 'unit A;' + #10 + '{$WARN SYMBOL_DEPRECATED OFF} // Altlast', []),
    Disabled(Source, 10, 'W1000', TDisableWarningScope.UnitWide, 'Altlast', ''));
  Assert.AreEqual(StringReplace(Header, '  A.B;', '  A.B;' + #10 + '{$HINTS OFF}', []),
    Disabled(Header, 4, 'H2443', TDisableWarningScope.UnitWide));
  Assert.AreEqual('', Disabled('procedure X;' + #10 + 'begin' + #10 + 'end;', 1, 'H2443',
    TDisableWarningScope.UnitWide), 'Include-Datei ohne Kopf');
end;

procedure TDisableWarningTests.NestedRoutineWins;
const
  Nested =
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
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Nested);
  try
    Assert.AreEqual('Inner', TDisableWarning.RoutineAt(Tree, 6).Name);
    Assert.AreEqual('Outer', TDisableWarning.RoutineAt(Tree, 10).Name);
  finally
    Tree.Free;
  end;
  Assert.AreEqual(StringReplace(StringReplace(Nested, '  procedure Inner;', '  {$HINTS OFF}' + #10 +
    '  procedure Inner;', []), '  end;' + #10, '  end;' + #10 + '  {$HINTS ON}' + #10, []),
    Disabled(Nested, 6, 'H2164', TDisableWarningScope.Routine));
end;

procedure TDisableWarningTests.NoRoutineOutsideBodies;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsNull(TDisableWarning.RoutineAt(Tree, 2));
    Assert.IsNull(TDisableWarning.RoutineAt(Tree, 13));
  finally
    Tree.Free;
  end;
  Assert.AreEqual('', Disabled(Source, 2, 'W1000', TDisableWarningScope.Routine));
  Assert.AreEqual('', Disabled(Source, 99, 'W1000', TDisableWarningScope.Line));
end;

procedure TDisableWarningTests.KeepsLineBreaks;
var
  Crlf: string;
begin
  Crlf := StringReplace(Source, #10, #13#10, [rfReplaceAll]);
  Assert.AreEqual(StringReplace(Crlf, '  Alt;' + #13#10, '  {$WARN SYMBOL_DEPRECATED OFF}' + #13#10 + '  Alt;' +
    #13#10 + '  {$WARN SYMBOL_DEPRECATED ON}' + #13#10, []), Disabled(Crlf, 10, 'W1000', TDisableWarningScope.Line));
  // Letzte Zeile ohne Umbruch am Ende.
  Assert.AreEqual(StringReplace(Source, 'end.', '{$HINTS OFF}' + #10 + 'end.' + #10 + '{$HINTS ON}', []),
    Disabled(Source, 13, 'H2443', TDisableWarningScope.Line));
end;

procedure TDisableWarningTests.RefusesErrors;
var
  Switch: TDisableWarningSwitch;
begin
  Assert.IsFalse(TDisableWarning.SwitchFor('E2003', '', Switch));
  Assert.IsFalse(TDisableWarning.SwitchFor('F2613', '', Switch));
  Assert.IsFalse(TDisableWarning.SwitchFor('', '', Switch));
end;

procedure TDisableWarningTests.OlderVersionFallsBackToWarnings;
var
  Switch: TDisableWarningSwitch;
begin
  Assert.IsTrue(TDisableWarning.SwitchFor('W1071', '21.0', Switch));
  Assert.IsTrue(Switch.AllWarnings);
  Assert.AreEqual('{$WARNINGS OFF}', Switch.OffText);
  Assert.IsTrue(TDisableWarning.SwitchFor('W1071', '37.0', Switch));
  Assert.AreEqual('{$WARN IMPLICIT_INTEGER_CAST_LOSS OFF}', Switch.OffText);
end;

initialization
  TDUnitX.RegisterTestFixture(TDisableWarningTests);

end.
