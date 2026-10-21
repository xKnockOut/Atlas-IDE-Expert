unit Atlas.Core.Editor.GutterColumn.Tests;

// Atlas-Spalte in der Zeilenleiste (#768): Vorrang der Symbole, Unterschalter,
// Probleme je Zeile, Antwort von atlas.server.overrideMarks, Breite und Texte.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Editor.GutterColumn;

type
  [TestFixture]
  TAtlasGutterColumnTests = class
  private
    FProblems: TArray<TAtlasProblem>;
    function Problem(ALine: Integer; ASeverity: TAtlasProblemSeverity; const ACode: string): TAtlasProblem;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ChoosesByPriority;
    [Test]
    procedure SubSwitchesLetNextSymbolMoveUp;
    [Test]
    procedure ProblemSymbolTakesWorstStartingInLine;
    [Test]
    procedure ProblemsAtSortsBySeverity;
    [Test]
    procedure ReadsOverrideMarks;
    [Test]
    procedure IgnoresBrokenAnswers;
    [Test]
    procedure WidthFollowsLineHeight;
    [Test]
    procedure TextsForPanel;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

function TAtlasGutterColumnTests.Problem(ALine: Integer; ASeverity: TAtlasProblemSeverity;
  const ACode: string): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.EndLine := ALine;
  Result.Severity := ASeverity;
  Result.Code := ACode;
  Result.Message := 'Meldung ' + ACode;
end;

procedure TAtlasGutterColumnTests.TearDown;
begin
  FProblems := nil;
end;

procedure TAtlasGutterColumnTests.ChoosesByPriority;
var
  Line: TAtlasGutterLine;
begin
  Line := Default(TAtlasGutterLine);
  Assert.AreEqual(Ord(TAtlasGutterSymbol.None), Ord(TAtlasGutterColumn.Choose(Line, TAtlasGutterColumnOptions.All)));
  Line.Overridden := True;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Overridden),
    Ord(TAtlasGutterColumn.Choose(Line, TAtlasGutterColumnOptions.All)));
  Line.Overrides := True;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Overrides),
    Ord(TAtlasGutterColumn.Choose(Line, TAtlasGutterColumnOptions.All)));
  Line.Action := True;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Action), Ord(TAtlasGutterColumn.Choose(Line, TAtlasGutterColumnOptions.All)));
  Line.Problem := TAtlasGutterSymbol.Hint;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Hint), Ord(TAtlasGutterColumn.Choose(Line, TAtlasGutterColumnOptions.All)));
  Line.Problem := TAtlasGutterSymbol.Error;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Error), Ord(TAtlasGutterColumn.Choose(Line, TAtlasGutterColumnOptions.All)));
end;

procedure TAtlasGutterColumnTests.SubSwitchesLetNextSymbolMoveUp;
var
  Line: TAtlasGutterLine;
  Options: TAtlasGutterColumnOptions;
begin
  Line := Default(TAtlasGutterLine);
  Line.Problem := TAtlasGutterSymbol.Warning;
  Line.Action := True;
  Line.Overridden := True;
  Options := TAtlasGutterColumnOptions.All;
  Options.Problems := False;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Action), Ord(TAtlasGutterColumn.Choose(Line, Options)));
  Options.CodeActions := False;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Overridden), Ord(TAtlasGutterColumn.Choose(Line, Options)));
  Options.Overrides := False;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.None), Ord(TAtlasGutterColumn.Choose(Line, Options)));
  // Ein Wert außerhalb der Problemarten zählt nicht als Problem.
  Line := Default(TAtlasGutterLine);
  Line.Problem := TAtlasGutterSymbol.Overrides;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.None), Ord(TAtlasGutterColumn.Choose(Line, TAtlasGutterColumnOptions.All)));
end;

procedure TAtlasGutterColumnTests.ProblemSymbolTakesWorstStartingInLine;
var
  Inactive, UsesHint, Spanning: TAtlasProblem;
begin
  Inactive := Problem(3, TAtlasProblemSeverity.Error, '');
  Inactive.Unnecessary := True;
  UsesHint := Problem(3, TAtlasProblemSeverity.Error, 'unused-uses');
  UsesHint.UsesUnit := 'System.Classes';
  // Beginnt in Zeile 1 und reicht bis 4: Das Symbol steht nur in Zeile 1.
  Spanning := Problem(1, TAtlasProblemSeverity.Error, 'E2029');
  Spanning.EndLine := 4;
  FProblems := [Problem(3, TAtlasProblemSeverity.Hint, 'H2164'), Problem(3, TAtlasProblemSeverity.Warning, 'W1036'),
    Inactive, UsesHint, Spanning, Problem(5, TAtlasProblemSeverity.Information, 'naming')];
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Warning), Ord(TAtlasGutterColumn.ProblemSymbol(FProblems, 3)));
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Error), Ord(TAtlasGutterColumn.ProblemSymbol(FProblems, 1)));
  Assert.AreEqual(Ord(TAtlasGutterSymbol.None), Ord(TAtlasGutterColumn.ProblemSymbol(FProblems, 2)));
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Hint), Ord(TAtlasGutterColumn.ProblemSymbol(FProblems, 5)));
end;

procedure TAtlasGutterColumnTests.ProblemsAtSortsBySeverity;
var
  Found: TArray<TAtlasProblem>;
begin
  FProblems := [Problem(2, TAtlasProblemSeverity.Hint, 'H1'), Problem(2, TAtlasProblemSeverity.Error, 'E1'),
    Problem(2, TAtlasProblemSeverity.Hint, 'H2'), Problem(2, TAtlasProblemSeverity.Error, 'E2'),
    Problem(7, TAtlasProblemSeverity.Error, 'E3')];
  Found := TAtlasGutterColumn.ProblemsAt(FProblems, 2);
  Assert.AreEqual(4, Integer(Length(Found)));
  Assert.AreEqual('E1', Found[0].Code);
  Assert.AreEqual('E2', Found[1].Code);
  Assert.AreEqual('H1', Found[2].Code);
  Assert.AreEqual('H2', Found[3].Code);
end;

procedure TAtlasGutterColumnTests.ReadsOverrideMarks;
var
  Json: TJSONValue;
  Marks: TAtlasFileOverrides;
  Entry: TAtlasGutterOverrides;
begin
  Json := TJSONObject.ParseJSONValue('{"lines": [' +
    '{"line": 5, "overrides": [{"name": "TBasis.Zeichne", "uri": "file:///C:/P/Basis.pas", "line": 4, ' +
    '"character": 14}], "overridden": []},' +
    '{"line": 9, "overrides": [], "overridden": [{"name": "TEnkel.Zeichne", "uri": "file:///C:/P/Enkel.pas", ' +
    '"line": 12, "character": 16}, {"name": "", "uri": "file:///x", "line": 1}]}]}');
  try
    Marks := TAtlasFileOverrides.FromJson(Json,
      function(AUri: string): string
      begin
        Result := 'Pfad:' + AUri;
      end);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Marks.HasLines);
  Assert.IsTrue(Marks.At(5, Entry));
  Assert.AreEqual(1, Integer(Length(Entry.Overrides)));
  Assert.AreEqual('TBasis.Zeichne', Entry.Overrides[0].Name);
  Assert.AreEqual('Pfad:file:///C:/P/Basis.pas', Entry.Overrides[0].FileName);
  Assert.AreEqual(4, Entry.Overrides[0].Line);
  Assert.AreEqual(14, Entry.Overrides[0].Character);
  Assert.IsTrue(Marks.At(9, Entry));
  // Ziel ohne Namen entfällt.
  Assert.AreEqual(1, Integer(Length(Entry.Overridden)));
  Assert.AreEqual(12, Entry.Overridden[0].Line);
  Assert.IsFalse(Marks.At(6, Entry));
end;

procedure TAtlasGutterColumnTests.IgnoresBrokenAnswers;
var
  Json: TJSONValue;
  Marks: TAtlasFileOverrides;
begin
  Assert.IsFalse(TAtlasFileOverrides.FromJson(nil, nil).HasLines);
  Json := TJSONObject.ParseJSONValue('{"lines": 3}');
  try
    Assert.IsFalse(TAtlasFileOverrides.FromJson(Json, nil).HasLines);
  finally
    Json.Free;
  end;
  // Zeile ohne Ziele oder mit negativer Zeile entfällt.
  Json := TJSONObject.ParseJSONValue('{"lines": [{"line": 2, "overrides": [], "overridden": []}, 7, ' +
    '{"line": -1, "overrides": [{"name": "A.B", "uri": "u", "line": 0}]}]}');
  try
    Marks := TAtlasFileOverrides.FromJson(Json, nil);
    Assert.IsFalse(Marks.HasLines);
  finally
    Json.Free;
  end;
end;

procedure TAtlasGutterColumnTests.WidthFollowsLineHeight;
begin
  Assert.AreEqual(12, TAtlasGutterColumn.Width(6));
  Assert.AreEqual(16, TAtlasGutterColumn.Width(16));
  Assert.AreEqual(24, TAtlasGutterColumn.Width(24));
end;

procedure TAtlasGutterColumnTests.TextsForPanel;
var
  Target: TAtlasGutterTarget;
begin
  Assert.AreEqual('E2003 · Fehler', TAtlasGutterColumn.ProblemTitle(Problem(0, TAtlasProblemSeverity.Error, 'E2003'),
    'Fehler'));
  Assert.AreEqual('Warnung', TAtlasGutterColumn.ProblemTitle(Problem(0, TAtlasProblemSeverity.Warning, ''),
    'Warnung'));
  Target := Default(TAtlasGutterTarget);
  Target.Name := 'TKnopf.Paint';
  Target.FileName := 'Knopf.pas';
  Target.Line := 41;
  Assert.AreEqual('TKnopf.Paint — Knopf.pas:42', TAtlasGutterColumn.TargetText(Target));
  Assert.AreEqual('✕', TAtlasGutterColumn.Glyph(TAtlasGutterSymbol.Error));
  Assert.AreEqual('↓', TAtlasGutterColumn.Glyph(TAtlasGutterSymbol.Overridden));
  Assert.AreEqual('', TAtlasGutterColumn.Glyph(TAtlasGutterSymbol.None));
end;

end.
