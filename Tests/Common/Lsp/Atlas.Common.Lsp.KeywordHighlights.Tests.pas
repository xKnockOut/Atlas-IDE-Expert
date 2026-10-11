unit Atlas.Common.Lsp.KeywordHighlights.Tests;

// Tests für die Hervorhebung zusammengehöriger Schlüsselwörter (#307).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TKeywordHighlightsTests = class
  public
    [Test]
    procedure NestedBeginEndPairsInnermost;
    [Test]
    procedure TryFinallyEnd;
    [Test]
    procedure RoutineKeywordWithBeginAndEnd;
    [Test]
    procedure DirectiveElse;
    [Test]
    procedure ExitPointsSkipNestedRoutines;
    [Test]
    procedure ExitPointsSwitchedOff;
    [Test]
    procedure UnfinishedBlockKeepsKeyword;
    [Test]
    procedure IdentifierIsNotKeyword;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.KeywordHighlights;

/// <summary>Bereiche als "Zeile:Spalte" (0-basiert), durch Leerzeichen getrennt.</summary>
function Run(const ASource: string; ALine, ACharacter: Integer; const ASettings: THighlightSettings;
  out AFound: Boolean): string;
var
  Tree: TSyntaxTree;
  Position: TTextPosition;
  Ranges: TArray<TTextRange>;
  Range: TTextRange;
begin
  Result := '';
  Tree := TPascalParser.Parse(ASource);
  try
    Position.Line := ALine;
    Position.Character := ACharacter;
    AFound := TKeywordHighlights.Find(Tree, Position, ASettings, Ranges);
    for Range in Ranges do
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Format('%d:%d', [Range.StartPos.Line, Range.StartPos.Character]);
    end;
  finally
    Tree.Free;
  end;
end;

function Highlight(const ASource: string; ALine, ACharacter: Integer): string;
var
  Found: Boolean;
begin
  Result := Run(ASource, ALine, ACharacter, THighlightSettings.Default, Found);
  Assert.IsTrue(Found);
end;

const
  Nested =
    'unit U;'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  if A then'#10'  begin'#10'    B;'#10'  end;'#10'end;'#10'end.';

procedure TKeywordHighlightsTests.NestedBeginEndPairsInnermost;
begin
  // inneres begin (Zeile 5) gehört zum end in Zeile 7
  Assert.AreEqual('5:2 7:2', Highlight(Nested, 5, 3));
  Assert.AreEqual('5:2 7:2', Highlight(Nested, 7, 2));
end;

procedure TKeywordHighlightsTests.TryFinallyEnd;
const
  Source =
    'unit U;'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  try'#10'    A;'#10'  finally'#10'    B;'#10'  end;'#10'end;'#10'end.';
begin
  Assert.AreEqual('4:2 6:2 8:2', Highlight(Source, 6, 4));
end;

procedure TKeywordHighlightsTests.RoutineKeywordWithBeginAndEnd;
begin
  Assert.AreEqual('2:0 3:0 8:0', Highlight(Nested, 2, 2));
end;

procedure TKeywordHighlightsTests.DirectiveElse;
const
  Source =
    'unit U;'#10'implementation'#10'{$IFDEF X}'#10'const A = 1;'#10'{$ELSE}'#10'const A = 2;'#10 +
    '{$ENDIF}'#10'end.';
begin
  Assert.AreEqual('2:0 4:0 6:0', Highlight(Source, 4, 3));
end;

procedure TKeywordHighlightsTests.ExitPointsSkipNestedRoutines;
const
  Source =
    'unit U;'#10'implementation'#10'procedure P;'#10 +
    '  procedure Q;'#10'  begin'#10'    Exit;'#10'  end;'#10 +
    'begin'#10'  if A then'#10'    Exit;'#10'  raise E.Create;'#10'end;'#10'end.';
begin
  // Exit in P: eigenes Exit, raise und end von P, nicht das Exit in Q
  Assert.AreEqual('9:4 10:2 11:0', Highlight(Source, 9, 5));
  // Routinenname im Kopf zeigt dasselbe
  Assert.AreEqual('9:4 10:2 11:0', Highlight(Source, 2, 10));
end;

procedure TKeywordHighlightsTests.ExitPointsSwitchedOff;
const
  Source = 'unit U;'#10'implementation'#10'procedure P;'#10'begin'#10'  Exit;'#10'end;'#10'end.';
var
  Settings: THighlightSettings;
  Found: Boolean;
begin
  Settings := THighlightSettings.Default;
  Settings.ExitPoints := False;
  Assert.AreEqual('', Run(Source, 4, 3, Settings, Found));
  Assert.IsTrue(Found);
end;

procedure TKeywordHighlightsTests.UnfinishedBlockKeepsKeyword;
const
  Source = 'unit U;'#10'implementation'#10'procedure P;'#10'begin'#10'  try'#10'    A;'#10;
begin
  Assert.AreEqual('4:2', Highlight(Source, 4, 3));
end;

procedure TKeywordHighlightsTests.IdentifierIsNotKeyword;
var
  Found: Boolean;
begin
  Run(Nested, 6, 4, THighlightSettings.Default, Found);
  Assert.IsFalse(Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TKeywordHighlightsTests);

end.
