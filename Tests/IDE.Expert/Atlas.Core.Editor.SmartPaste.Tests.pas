unit Atlas.Core.Editor.SmartPaste.Tests;

// Tests für Einfügen mit uses-Ergänzung (#515), Plugin-Kern: Einstellung,
// Erkennen vor dem Cursor, Einrückung, Antwort des Servers und Argumente.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSmartPasteTests = class
  public
    [Test]
    procedure ModesAndThreshold;
    [Test]
    procedure MatchesTextBeforeCaret;
    [Test]
    procedure ReindentsBlockToTarget;
    [Test]
    procedure ReindentFromLineStartAndMidLineCopy;
    [Test]
    procedure KeepsSingleLinesAndCodeBefore;
    [Test]
    procedure ReadsAnalysisAndSelection;
    [Test]
    procedure BuildsArguments;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.SmartPaste;

function Applied(const APrefix: string; const APasted: TArray<string>; const AEdits: TArray<TAtlasIndentEdit>):
  string;
var
  Lines: TArray<string>;
  Edit: TAtlasIndentEdit;
begin
  // Puffer nach dem Einfügen: erste Zeile mit dem Leerraum davor.
  Lines := Copy(APasted);
  Lines[0] := APrefix + Lines[0];
  for Edit in AEdits do
    Lines[Edit.Line] := Edit.Indent + Copy(Lines[Edit.Line], Edit.Remove + 1, MaxInt);
  Result := string.Join('|', Lines);
end;

procedure TAtlasSmartPasteTests.ModesAndThreshold;
begin
  Assert.IsTrue(TAtlasSmartPaste.ModeOf('both') = TAtlasPasteMode.Both);
  Assert.IsTrue(TAtlasSmartPaste.ModeOf('USES') = TAtlasPasteMode.UsesOnly);
  Assert.IsTrue(TAtlasSmartPaste.ModeOf('indent') = TAtlasPasteMode.IndentOnly);
  Assert.IsTrue(TAtlasSmartPaste.ModeOf('x') = TAtlasPasteMode.Off);
  Assert.IsTrue(TAtlasSmartPaste.WantsUses(TAtlasPasteMode.Both));
  Assert.IsFalse(TAtlasSmartPaste.WantsUses(TAtlasPasteMode.IndentOnly));
  Assert.IsTrue(TAtlasSmartPaste.WantsIndent(TAtlasPasteMode.IndentOnly));
  Assert.IsFalse(TAtlasSmartPaste.WantsIndent(TAtlasPasteMode.Off));
  Assert.IsFalse(TAtlasSmartPaste.Qualifies('Foo(1);'));
  Assert.IsTrue(TAtlasSmartPaste.Qualifies('A;'#13#10'B;'));
  Assert.IsTrue(TAtlasSmartPaste.Qualifies('TJSONObject.Create(nil);'));
end;

procedure TAtlasSmartPasteTests.MatchesTextBeforeCaret;
var
  Start: Integer;
begin
  // Eingefügt nach „  “: „X := 1;“, „Y := 2;“ und der Anfang der Cursorzeile.
  Assert.IsTrue(TAtlasSmartPaste.Match(['  X := 1;', 'Y := 2;', '  Z'], 2, ['X := 1;', 'Y := 2;', '  '], Start));
  Assert.AreEqual(2, Start);
  Assert.IsFalse(TAtlasSmartPaste.Match(['  X := 1;', 'Y := 3;', '  Z'], 2, ['X := 1;', 'Y := 2;', '  '], Start));
  Assert.IsFalse(TAtlasSmartPaste.Match(['  X := 1;', 'Y := 2;'], 2, ['X := 1;', 'Y := 2;', ''], Start),
    'Zeilenzahl');
  Assert.IsTrue(TAtlasSmartPaste.Match(['  S := TJSONObject.Create; // x'], 26, ['TJSONObject.Create;'], Start));
  Assert.AreEqual(7, Start);
  Assert.IsFalse(TAtlasSmartPaste.Match(['  S := TJSONObject.Create;'], 20, ['TJSONObject.Create;'], Start));
end;

procedure TAtlasSmartPasteTests.ReindentsBlockToTarget;
var
  Pasted: TArray<string>;
  Edits: TArray<TAtlasIndentEdit>;
begin
  // Block mit 8 Leerzeichen, Einfügestelle mit 2.
  Pasted := ['        if A then', '          B;', '', '        C;', ''];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('  ', 'begin', Pasted, 8, 2, Edits));
  Assert.AreEqual('  if A then|    B;||  C;|', Applied('  ', Pasted, Edits));
  // Schon richtig: nichts zu tun.
  Pasted := ['  A;', '  B;'];
  Assert.IsFalse(TAtlasSmartPaste.Reindent('', '  X;', Pasted, 8, 2, Edits));
  // Tabulatoren zählen bis zur nächsten Position.
  Pasted := [#9'A;', #9#9'B;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('    ', '', Pasted, 4, 2, Edits));
  Assert.AreEqual('    A;|        B;', Applied('    ', Pasted, Edits));
end;

procedure TAtlasSmartPasteTests.ReindentFromLineStartAndMidLineCopy;
var
  Pasted: TArray<string>;
  Edits: TArray<TAtlasIndentEdit>;
begin
  // Am Zeilenanfang nach „  begin“: eine Stufe tiefer als die Zeile darüber.
  Pasted := ['      X := 1;', '      Y := 2;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('', '  begin // Start', Pasted, 8, 2, Edits));
  Assert.AreEqual('    X := 1;|    Y := 2;', Applied('', Pasted, Edits));
  // Aus der Mitte der Zeile kopiert: Die erste Zeile hat keinen Leerraum, die übrigen ihren alten.
  Pasted := ['if A then', '          B', '        else', '          C;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('    ', '', Pasted, 8, 2, Edits));
  Assert.AreEqual('    if A then|      B|    else|      C;', Applied('    ', Pasted, Edits));
  // Ohne Zeile auf derselben Ebene: eine Stufe über der flachsten.
  Pasted := ['if A then', '          B;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('    ', '', Pasted, 8, 2, Edits));
  Assert.AreEqual('    if A then|      B;', Applied('    ', Pasted, Edits));
  // Beginnt der Block mit einem Zeilenumbruch, zählt die erste Zeile mit Inhalt.
  Pasted := ['', '        A;', '        B;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('  ', '', Pasted, 8, 2, Edits));
  Assert.AreEqual('  |  A;|  B;', Applied('  ', Pasted, Edits));
end;

procedure TAtlasSmartPasteTests.KeepsSingleLinesAndCodeBefore;
var
  Edits: TArray<TAtlasIndentEdit>;
begin
  Assert.IsFalse(TAtlasSmartPaste.Reindent('  ', '', ['        TJSONObject.Create;'], 8, 2, Edits), 'eine Zeile');
  Assert.IsFalse(TAtlasSmartPaste.Reindent('  S := ', '', ['Foo(', '        1);'], 8, 2, Edits), 'Code davor');
  Assert.IsTrue(TAtlasSmartPaste.Opens('  try'));
  Assert.IsTrue(TAtlasSmartPaste.Opens('  if A then // weiter'));
  Assert.IsFalse(TAtlasSmartPaste.Opens('  A.Then'), 'nach Punkt');
  Assert.IsFalse(TAtlasSmartPaste.Opens('  A;'));
end;

procedure TAtlasSmartPasteTests.ReadsAnalysisAndSelection;
var
  Value: TJSONValue;
  Analysis: TAtlasPasteAnalysis;
begin
  Value := TJSONObject.ParseJSONValue('{"units":["System.JSON","Data.DB"],"choices":[{"name":"TList","units":' +
    '["System.Classes","System.Generics.Collections"]},{"name":"X","units":["A"]}],"interface":true}');
  try
    Analysis := TAtlasSmartPaste.ReadAnalysis(Value);
  finally
    Value.Free;
  end;
  Assert.IsTrue(Analysis.Valid);
  Assert.IsTrue(Analysis.InInterface);
  Assert.AreEqual(2, Integer(Length(Analysis.Units)));
  Assert.AreEqual(1, Integer(Length(Analysis.Choices)), 'nur mehrdeutige');
  Assert.AreEqual(-1, Analysis.Choices[0].Chosen, 'nicht automatisch gewählt');
  Assert.AreEqual('System.JSON|Data.DB', string.Join('|', TAtlasSmartPaste.Selected(Analysis)));
  Analysis.Choices[0].Chosen := 1;
  Assert.AreEqual('System.JSON|Data.DB|System.Generics.Collections',
    string.Join('|', TAtlasSmartPaste.Selected(Analysis)));
  Assert.AreEqual('A, B, C', TAtlasSmartPaste.Named(['A', 'B', 'C']));
  Assert.AreEqual('A, B, C, …', TAtlasSmartPaste.Named(['A', 'B', 'C', 'D']));
  Assert.IsFalse(TAtlasSmartPaste.ReadAnalysis(nil).Valid);
  Analysis := Default(TAtlasPasteAnalysis);
end;

procedure TAtlasSmartPasteTests.BuildsArguments;
begin
  Assert.AreEqual('["file:///c%3A/p/A.pas",{"start":{"line":3,"character":2},"end":{"line":5,"character":7}}]',
    TAtlasSmartPaste.Arguments('file:///c%3A/p/A.pas', 3, 2, 5, 7));
  Assert.AreEqual('["u",{"start":{"line":0,"character":0},"end":{"line":1,"character":0}},["System.JSON"]]',
    TAtlasSmartPaste.Arguments('u', 0, 0, 1, 0, ['System.JSON']));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSmartPasteTests);

end.
