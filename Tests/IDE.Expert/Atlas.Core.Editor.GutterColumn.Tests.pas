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
    /// <summary>Wartezeit nach Fehlschlägen verdoppelt sich bis zur Obergrenze; eine Antwort setzt sie zurück.
    /// </summary>
    [Test]
    procedure RetryDoublesUpToLimit;
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
  mLine: TAtlasGutterLine;
begin
  mLine := Default(TAtlasGutterLine);
  Assert.AreEqual(Ord(TAtlasGutterSymbol.None), Ord(TAtlasGutterColumn.Choose(mLine, TAtlasGutterColumnOptions.All)));
  mLine.Overridden := True;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Overridden),
    Ord(TAtlasGutterColumn.Choose(mLine, TAtlasGutterColumnOptions.All)));
  mLine.Overrides := True;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Overrides),
    Ord(TAtlasGutterColumn.Choose(mLine, TAtlasGutterColumnOptions.All)));
  mLine.Action := True;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Action), Ord(TAtlasGutterColumn.Choose(mLine, TAtlasGutterColumnOptions.All)));
  mLine.Problem := TAtlasGutterSymbol.Hint;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Action), Ord(TAtlasGutterColumn.Choose(mLine, TAtlasGutterColumnOptions.All)));
  mLine.Problem := TAtlasGutterSymbol.Error;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Error), Ord(TAtlasGutterColumn.Choose(mLine, TAtlasGutterColumnOptions.All)));
end;

procedure TAtlasGutterColumnTests.SubSwitchesLetNextSymbolMoveUp;
var
  mLine: TAtlasGutterLine;
  mOptions: TAtlasGutterColumnOptions;
begin
  mLine := Default(TAtlasGutterLine);
  mLine.Problem := TAtlasGutterSymbol.Warning;
  mLine.Action := True;
  mLine.Overridden := True;
  mOptions := TAtlasGutterColumnOptions.All;
  mOptions.Problems := False;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Action), Ord(TAtlasGutterColumn.Choose(mLine, mOptions)));
  mOptions.CodeActions := False;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Overridden), Ord(TAtlasGutterColumn.Choose(mLine, mOptions)));
  mOptions.Overrides := False;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.None), Ord(TAtlasGutterColumn.Choose(mLine, mOptions)));
  // Ein Wert außerhalb der Problemarten zählt nicht als Problem.
  mLine := Default(TAtlasGutterLine);
  mLine.Problem := TAtlasGutterSymbol.Overrides;
  Assert.AreEqual(Ord(TAtlasGutterSymbol.None), Ord(TAtlasGutterColumn.Choose(mLine, TAtlasGutterColumnOptions.All)));
end;

procedure TAtlasGutterColumnTests.ProblemSymbolTakesWorstStartingInLine;
var
  mInactive, mUsesHint, mSpanning: TAtlasProblem;
begin
  mInactive := Problem(3, TAtlasProblemSeverity.Error, '');
  mInactive.Unnecessary := True;
  mUsesHint := Problem(3, TAtlasProblemSeverity.Error, 'unused-uses');
  mUsesHint.UsesUnit := 'System.Classes';
  // Beginnt in Zeile 1 und reicht bis 4: Das Symbol steht nur in Zeile 1.
  mSpanning := Problem(1, TAtlasProblemSeverity.Error, 'E2029');
  mSpanning.EndLine := 4;
  FProblems := [Problem(3, TAtlasProblemSeverity.Hint, 'H2164'), Problem(3, TAtlasProblemSeverity.Warning, 'W1036'),
    mInactive, mUsesHint, mSpanning, Problem(5, TAtlasProblemSeverity.Information, 'naming')];
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Warning), Ord(TAtlasGutterColumn.ProblemSymbol(FProblems, 3)));
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Error), Ord(TAtlasGutterColumn.ProblemSymbol(FProblems, 1)));
  Assert.AreEqual(Ord(TAtlasGutterSymbol.None), Ord(TAtlasGutterColumn.ProblemSymbol(FProblems, 2)));
  Assert.AreEqual(Ord(TAtlasGutterSymbol.Hint), Ord(TAtlasGutterColumn.ProblemSymbol(FProblems, 5)));
end;

procedure TAtlasGutterColumnTests.ProblemsAtSortsBySeverity;
var
  mFound: TArray<TAtlasProblem>;
begin
  FProblems := [Problem(2, TAtlasProblemSeverity.Hint, 'H1'), Problem(2, TAtlasProblemSeverity.Error, 'E1'),
    Problem(2, TAtlasProblemSeverity.Hint, 'H2'), Problem(2, TAtlasProblemSeverity.Error, 'E2'),
    Problem(7, TAtlasProblemSeverity.Error, 'E3')];
  mFound := TAtlasGutterColumn.ProblemsAt(FProblems, 2);
  Assert.AreEqual(4, Integer(Length(mFound)));
  Assert.AreEqual('E1', mFound[0].Code);
  Assert.AreEqual('E2', mFound[1].Code);
  Assert.AreEqual('H1', mFound[2].Code);
  Assert.AreEqual('H2', mFound[3].Code);
end;

procedure TAtlasGutterColumnTests.ReadsOverrideMarks;
var
  mJson: TJSONValue;
  mMarks: TAtlasFileOverrides;
  mEntry: TAtlasGutterOverrides;
begin
  mJson := TJSONObject.ParseJSONValue('{"lines": [' +
    '{"line": 5, "overrides": [{"name": "TBasis.Zeichne", "uri": "file:///C:/P/Basis.pas", "line": 4, ' +
    '"character": 14}], "overridden": []},' +
    '{"line": 9, "overrides": [], "overridden": [{"name": "TEnkel.Zeichne", "uri": "file:///C:/P/Enkel.pas", ' +
    '"line": 12, "character": 16}, {"name": "", "uri": "file:///x", "line": 1}]}]}');
  try
    mMarks := TAtlasFileOverrides.FromJson(mJson,
      function(AUri: string): string
      begin
        Result := 'Pfad:' + AUri;
      end);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mMarks.HasLines);
  Assert.IsTrue(mMarks.At(5, mEntry));
  Assert.AreEqual(1, Integer(Length(mEntry.Overrides)));
  Assert.AreEqual('TBasis.Zeichne', mEntry.Overrides[0].Name);
  Assert.AreEqual('Pfad:file:///C:/P/Basis.pas', mEntry.Overrides[0].FileName);
  Assert.AreEqual(4, mEntry.Overrides[0].Line);
  Assert.AreEqual(14, mEntry.Overrides[0].Character);
  Assert.IsTrue(mMarks.At(9, mEntry));
  // Ziel ohne Namen entfällt.
  Assert.AreEqual(1, Integer(Length(mEntry.Overridden)));
  Assert.AreEqual(12, mEntry.Overridden[0].Line);
  Assert.IsFalse(mMarks.At(6, mEntry));
end;

procedure TAtlasGutterColumnTests.IgnoresBrokenAnswers;
var
  mJson: TJSONValue;
  mMarks: TAtlasFileOverrides;
begin
  Assert.IsFalse(TAtlasFileOverrides.FromJson(nil, nil).HasLines);
  mJson := TJSONObject.ParseJSONValue('{"lines": 3}');
  try
    Assert.IsFalse(TAtlasFileOverrides.FromJson(mJson, nil).HasLines);
  finally
    mJson.Free;
  end;
  // Zeile ohne Ziele oder mit negativer Zeile entfällt.
  mJson := TJSONObject.ParseJSONValue('{"lines": [{"line": 2, "overrides": [], "overridden": []}, 7, ' +
    '{"line": -1, "overrides": [{"name": "A.B", "uri": "u", "line": 0}]}]}');
  try
    mMarks := TAtlasFileOverrides.FromJson(mJson, nil);
    Assert.IsFalse(mMarks.HasLines);
  finally
    mJson.Free;
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
  mTarget: TAtlasGutterTarget;
begin
  Assert.AreEqual('E2003 · Fehler', TAtlasGutterColumn.ProblemTitle(Problem(0, TAtlasProblemSeverity.Error, 'E2003'),
    'Fehler'));
  Assert.AreEqual('Warnung', TAtlasGutterColumn.ProblemTitle(Problem(0, TAtlasProblemSeverity.Warning, ''),
    'Warnung'));
  mTarget := Default(TAtlasGutterTarget);
  mTarget.Name := 'TKnopf.Paint';
  mTarget.FileName := 'Knopf.pas';
  mTarget.Line := 41;
  Assert.AreEqual('TKnopf.Paint — Knopf.pas:42', TAtlasGutterColumn.TargetText(mTarget));
  Assert.AreEqual('✕', TAtlasGutterColumn.Glyph(TAtlasGutterSymbol.Error));
  Assert.AreEqual('↓', TAtlasGutterColumn.Glyph(TAtlasGutterSymbol.Overridden));
  Assert.AreEqual('', TAtlasGutterColumn.Glyph(TAtlasGutterSymbol.None));
end;

procedure TAtlasGutterColumnTests.RetryDoublesUpToLimit;
var
  mRetry: TAtlasGutterRetry;
  mStep: Integer;
begin
  mRetry := Default(TAtlasGutterRetry);
  mRetry.Failed(1000);
  Assert.AreEqual(Int64(1000 + TAtlasGutterRetry.cRetryMs), Int64(mRetry.RetryAt));
  mRetry.Failed(1000);
  Assert.AreEqual(Int64(1000 + 2 * TAtlasGutterRetry.cRetryMs), Int64(mRetry.RetryAt));
  for mStep := 1 to 20 do
  begin
    mRetry.Failed(1000);
  end;
  Assert.AreEqual(Int64(1000 + TAtlasGutterRetry.cMaxRetryMs), Int64(mRetry.RetryAt));
  mRetry.Succeeded;
  mRetry.Failed(5000);
  Assert.AreEqual(Int64(5000 + TAtlasGutterRetry.cRetryMs), Int64(mRetry.RetryAt));
end;

end.
