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
    procedure ReindentUsesServerColumn;
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

/// <summary>Maße mit Schritt 2 und Tabulatorweite ATabWidth; die Spalte bestimmt die Heuristik.</summary>
function Heuristic(ATabWidth: Integer): TAtlasPasteIndent;
begin
  Result := TAtlasPasteIndent.Create(ATabWidth, 2, TAtlasSmartPaste.cNoColumn);
end;

/// <summary>Maße mit Schritt 2, Tabulatorweite 8 und der Spalte AColumn vom Server.</summary>
function FromServer(AColumn: Integer): TAtlasPasteIndent;
begin
  Result := TAtlasPasteIndent.Create(8, 2, AColumn);
end;

function Applied(const APrefix: string; const APasted: TArray<string>; const AEdits: TArray<TAtlasIndentEdit>):
  string;
var
  mLines: TArray<string>;
  mEdit: TAtlasIndentEdit;
begin
  // Puffer nach dem Einfügen: erste Zeile mit dem Leerraum davor.
  mLines := Copy(APasted);
  mLines[0] := APrefix + mLines[0];
  for mEdit in AEdits do
  begin
    mLines[mEdit.Line] := mEdit.Indent + Copy(mLines[mEdit.Line], mEdit.Remove + 1, MaxInt);
  end;
  Result := string.Join('|', mLines);
end;

procedure TAtlasSmartPasteTests.ModesAndThreshold;
begin
  Assert.AreEqual<TAtlasPasteMode>(TAtlasPasteMode.Both, TAtlasSmartPaste.ModeOf('both'));
  Assert.AreEqual<TAtlasPasteMode>(TAtlasPasteMode.UsesOnly, TAtlasSmartPaste.ModeOf('USES'));
  Assert.AreEqual<TAtlasPasteMode>(TAtlasPasteMode.IndentOnly, TAtlasSmartPaste.ModeOf('indent'));
  Assert.AreEqual<TAtlasPasteMode>(TAtlasPasteMode.Off, TAtlasSmartPaste.ModeOf('x'));
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
  mStart: Integer;
begin
  // Eingefügt nach „  “: „X := 1;“, „Y := 2;“ und der Anfang der Cursorzeile.
  Assert.IsTrue(TAtlasSmartPaste.Match(['  X := 1;', 'Y := 2;', '  Z'], 2, ['X := 1;', 'Y := 2;', '  '], mStart));
  Assert.AreEqual(2, mStart);
  Assert.IsFalse(TAtlasSmartPaste.Match(['  X := 1;', 'Y := 3;', '  Z'], 2, ['X := 1;', 'Y := 2;', '  '], mStart));
  Assert.IsFalse(TAtlasSmartPaste.Match(['  X := 1;', 'Y := 2;'], 2, ['X := 1;', 'Y := 2;', ''], mStart),
    'Zeilenzahl');
  Assert.IsTrue(TAtlasSmartPaste.Match(['  S := TJSONObject.Create; // x'], 26, ['TJSONObject.Create;'], mStart));
  Assert.AreEqual(7, mStart);
  Assert.IsFalse(TAtlasSmartPaste.Match(['  S := TJSONObject.Create;'], 20, ['TJSONObject.Create;'], mStart));
end;

procedure TAtlasSmartPasteTests.ReindentsBlockToTarget;
var
  mPasted: TArray<string>;
  mEdits: TArray<TAtlasIndentEdit>;
begin
  // Block mit 8 Leerzeichen, Einfügestelle mit 2.
  mPasted := ['        if A then', '          B;', '', '        C;', ''];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('  ', 'begin', mPasted, Heuristic(8), mEdits));
  Assert.AreEqual('  if A then|    B;||  C;|', Applied('  ', mPasted, mEdits));
  // Schon richtig: nichts zu tun.
  mPasted := ['  A;', '  B;'];
  Assert.IsFalse(TAtlasSmartPaste.Reindent('', '  X;', mPasted, Heuristic(8), mEdits));
  // Tabulatoren zählen bis zur nächsten Position.
  mPasted := [#9'A;', #9#9'B;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('    ', '', mPasted, Heuristic(4), mEdits));
  Assert.AreEqual('    A;|        B;', Applied('    ', mPasted, mEdits));
end;

procedure TAtlasSmartPasteTests.ReindentFromLineStartAndMidLineCopy;
var
  mPasted: TArray<string>;
  mEdits: TArray<TAtlasIndentEdit>;
begin
  // Am Zeilenanfang nach „  begin“: eine Stufe tiefer als die Zeile darüber.
  mPasted := ['      X := 1;', '      Y := 2;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('', '  begin // Start', mPasted, Heuristic(8), mEdits));
  Assert.AreEqual('    X := 1;|    Y := 2;', Applied('', mPasted, mEdits));
  // Aus der Mitte der Zeile kopiert: Die erste Zeile hat keinen Leerraum, die übrigen ihren alten.
  mPasted := ['if A then', '          B', '        else', '          C;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('    ', '', mPasted, Heuristic(8), mEdits));
  Assert.AreEqual('    if A then|      B|    else|      C;', Applied('    ', mPasted, mEdits));
  // Ohne Zeile auf derselben Ebene: eine Stufe über der flachsten.
  mPasted := ['if A then', '          B;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('    ', '', mPasted, Heuristic(8), mEdits));
  Assert.AreEqual('    if A then|      B;', Applied('    ', mPasted, mEdits));
  // Beginnt der Block mit einem Zeilenumbruch, zählt die erste Zeile mit Inhalt.
  mPasted := ['', '        A;', '        B;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('  ', '', mPasted, Heuristic(8), mEdits));
  Assert.AreEqual('  |  A;|  B;', Applied('  ', mPasted, mEdits));
end;

procedure TAtlasSmartPasteTests.ReindentUsesServerColumn;
var
  mPasted: TArray<string>;
  mEdits: TArray<TAtlasIndentEdit>;
begin
  // Nach „  if A then B;“ hielte die Heuristik die Zeile darüber; der Server kennt die Blockstruktur (#1832).
  mPasted := ['      X := 1;', '        Y := 2;'];
  Assert.IsTrue(TAtlasSmartPaste.Reindent('', '  if A then B;', mPasted, FromServer(2), mEdits));
  Assert.AreEqual('  X := 1;|    Y := 2;', Applied('', mPasted, mEdits));
  // Ohne Spalte vom Server dieselbe Heuristik wie bisher.
  Assert.IsTrue(TAtlasSmartPaste.Reindent('', '  if A then', mPasted, Heuristic(8), mEdits));
  Assert.AreEqual('    X := 1;|      Y := 2;', Applied('', mPasted, mEdits));
  // Code vor der Einfügestelle: auch mit Spalte vom Server bleibt alles.
  Assert.IsFalse(TAtlasSmartPaste.Reindent('  S := ', '', mPasted, FromServer(4), mEdits));
end;

procedure TAtlasSmartPasteTests.KeepsSingleLinesAndCodeBefore;
var
  mEdits: TArray<TAtlasIndentEdit>;
begin
  Assert.IsFalse(TAtlasSmartPaste.Reindent('  ', '', ['        TJSONObject.Create;'], Heuristic(8),
    mEdits), 'eine Zeile');
  Assert.IsFalse(TAtlasSmartPaste.Reindent('  S := ', '', ['Foo(', '        1);'], Heuristic(8), mEdits), 'Code davor');
  Assert.IsTrue(TAtlasSmartPaste.Opens('  try'));
  Assert.IsTrue(TAtlasSmartPaste.Opens('  if A then // weiter'));
  Assert.IsFalse(TAtlasSmartPaste.Opens('  A.Then'), 'nach Punkt');
  Assert.IsFalse(TAtlasSmartPaste.Opens('  A;'));
end;

procedure TAtlasSmartPasteTests.ReadsAnalysisAndSelection;
var
  mValue: TJSONValue;
  mAnalysis: TAtlasPasteAnalysis;
begin
  mValue := TJSONObject.ParseJSONValue('{"units":["System.JSON","Data.DB"],"choices":[{"name":"TList","units":' +
    '["System.Classes","System.Generics.Collections"]},{"name":"X","units":["A"]}],"interface":true}');
  try
    mAnalysis := TAtlasSmartPaste.ReadAnalysis(mValue);
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mAnalysis.Valid);
  Assert.IsTrue(mAnalysis.InInterface);
  Assert.AreEqual(2, Integer(Length(mAnalysis.Units)));
  Assert.AreEqual(1, Integer(Length(mAnalysis.Choices)), 'nur mehrdeutige');
  Assert.AreEqual(-1, mAnalysis.Choices[0].Chosen, 'nicht automatisch gewählt');
  Assert.AreEqual('System.JSON|Data.DB', string.Join('|', TAtlasSmartPaste.Selected(mAnalysis)));
  mAnalysis.Choices[0].Chosen := 1;
  Assert.AreEqual('System.JSON|Data.DB|System.Generics.Collections',
    string.Join('|', TAtlasSmartPaste.Selected(mAnalysis)));
  Assert.AreEqual('A, B, C', TAtlasSmartPaste.Named(['A', 'B', 'C']));
  Assert.AreEqual('A, B, C, …', TAtlasSmartPaste.Named(['A', 'B', 'C', 'D']));
  Assert.IsFalse(TAtlasSmartPaste.ReadAnalysis(nil).Valid);
  mAnalysis := Default(TAtlasPasteAnalysis);
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
