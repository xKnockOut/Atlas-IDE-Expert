unit Atlas.Common.Rules.CompilerPitfallFixes.Tests;

// Tests für die sicheren Korrekturen des Fallenkatalogs (#2621): Jede Korrektur greift nur, wenn ihre Voraussetzung
// am Text erfüllt ist.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerPitfallFixesTests = class
  public
    [Test]
    procedure QualifiesMonitor;
    [Test]
    procedure LeavesQualifiedMonitor;
    [Test]
    procedure AddsMissingUnit;
    [Test]
    procedure KeepsUsedUnit;
    [Test]
    procedure SplitsExitAfterStatement;
    [Test]
    procedure KeepsExitAfterThen;
    [Test]
    procedure PitfallWithoutFixGivesNothing;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Rules.CompilerPitfalls,
  Atlas.Common.Rules.CompilerPitfallFixes;

const
  cUnit = 'unit A;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  System.SysUtils;'#13#10#13#10 +
    'implementation'#13#10#13#10'function Liste: TArray<string>;'#13#10'begin'#13#10'  Zeige;'#13#10 +
    '  Exit([''a'', ''b'']);'#13#10'end;'#13#10#13#10'procedure Warte;'#13#10'begin'#13#10'  if Bereit then'#13#10 +
    '    Exit([''c'']);'#13#10'  TMonitor.Enter(FLock);'#13#10'end;'#13#10#13#10'end.'#13#10;
  // Zeilen ab 0 in cUnit.
  cExitLine = 12;
  cExitAfterThenLine = 18;
  cMonitorLine = 19;
  cSystemMonitor = 'System' + '.TMonitor.';

/// <summary>Text nach der Korrektur; '' ohne Korrektur.</summary>
function Fixed(APitfall: TCompilerPitfall; const AText: string; ALine: Integer): string;
var
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
begin
  Result := '';
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    if TCompilerPitfallFixes.Edits(APitfall, AText, mTree, ALine, mEdits) then
    begin
      Result := TTextChanges.Apply(AText, mEdits);
    end;
  finally
    mTree.Free;
  end;
end;

{ TCompilerPitfallFixesTests }

procedure TCompilerPitfallFixesTests.QualifiesMonitor;
begin
  Assert.AreEqual(StringReplace(cUnit, '  TMonitor.', '  ' + cSystemMonitor, []),
    Fixed(TCompilerPitfall.HiddenMonitor, cUnit, cMonitorLine));
end;

procedure TCompilerPitfallFixesTests.LeavesQualifiedMonitor;
var
  mText: string;
begin
  mText := StringReplace(cUnit, '  TMonitor.', '  ' + cSystemMonitor, []);
  Assert.AreEqual('', Fixed(TCompilerPitfall.HiddenMonitor, mText, cMonitorLine));
end;

procedure TCompilerPitfallFixesTests.AddsMissingUnit;
var
  mText: string;
begin
  mText := Fixed(TCompilerPitfall.WinapiUsesMissing, cUnit, cMonitorLine);
  Assert.IsTrue(Pos('Winapi.Windows', mText) > 0, mText);
  Assert.IsTrue(Pos('System.SysUtils', mText) > 0, mText);
end;

procedure TCompilerPitfallFixesTests.KeepsUsedUnit;
begin
  Assert.AreEqual('', Fixed(TCompilerPitfall.SysUtilsUsesMissing, cUnit, cMonitorLine));
end;

procedure TCompilerPitfallFixesTests.SplitsExitAfterStatement;
begin
  Assert.AreEqual(StringReplace(cUnit, '  Exit([''a'', ''b'']);', '  Result := [''a'', ''b''];'#13#10'  Exit;', []),
    Fixed(TCompilerPitfall.ExitArrayLiteral, cUnit, cExitLine));
end;

procedure TCompilerPitfallFixesTests.KeepsExitAfterThen;
begin
  // Nach then würden aus einer Anweisung zwei: keine sichere Korrektur.
  Assert.AreEqual('', Fixed(TCompilerPitfall.ExitArrayLiteral, cUnit, cExitAfterThenLine));
end;

procedure TCompilerPitfallFixesTests.PitfallWithoutFixGivesNothing;
begin
  Assert.AreEqual('', Fixed(TCompilerPitfall.ReferenceTwins, cUnit, cMonitorLine));
  Assert.AreEqual('', Fixed(TCompilerPitfall.HiddenMonitor, cUnit, -1));
end;

end.
