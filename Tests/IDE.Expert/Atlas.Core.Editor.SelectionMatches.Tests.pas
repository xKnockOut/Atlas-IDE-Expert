unit Atlas.Core.Editor.SelectionMatches.Tests;

// Gleichen Text wie die Markierung hervorheben (#709): Suchtext aus der
// Markierung, Treffer mit allen Kombinationen aus Groß-/Kleinschreibung und
// ganzen Wörtern, Obergrenze, Zeilenbereich, F3 vorwärts und rückwärts.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Editor.SelectionMatches;

type
  [TestFixture]
  TAtlasSelectionMatchesTests = class
  private
    FLines: TArray<string>;
    function Describe(const AList: TAtlasSelectionMatchList): string;
    function Options(ACaseSensitive, AWholeWord: Boolean): TAtlasSelectionMatchOptions;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TermNeedsSingleLineMinLengthAndText;
    [Test]
    procedure IgnoresCaseAndFindsPartsByDefault;
    [Test]
    procedure CaseSensitive;
    [Test]
    procedure WholeWords;
    [Test]
    procedure CaseSensitiveWholeWords;
    [Test]
    procedure FindsInStringsAndComments;
    [Test]
    procedure StopsAtMaxMatches;
    [Test]
    procedure LimitsToLineRange;
    [Test]
    procedure NextWrapsAroundBothWays;
    [Test]
    procedure LinesAndSelection;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges;

procedure TAtlasSelectionMatchesTests.Setup;
begin
  FLines := [
    'Kunde := TKunde.Create;',             // 0
    '// kunde anlegen',                    // 1
    'Kunden.Add(Kunde);',                  // 2
    'ShowMessage(''Kunde gespeichert'');', // 3
    'FKunde := nil;'];                     // 4
end;

procedure TAtlasSelectionMatchesTests.TearDown;
begin
  FLines := nil;
end;

function TAtlasSelectionMatchesTests.Describe(const AList: TAtlasSelectionMatchList): string;
var
  Match: TAtlasSelectionMatch;
begin
  Result := '';
  for Match in AList.Matches do
    Result := Result + Format('%d:%d ', [Match.Line, Match.Character]);
  Result := Trim(Result);
  if AList.Truncated then
    Result := Result + ' +';
end;

function TAtlasSelectionMatchesTests.Options(ACaseSensitive, AWholeWord: Boolean): TAtlasSelectionMatchOptions;
begin
  Result := TAtlasSelectionMatchOptions.Defaults;
  Result.CaseSensitive := ACaseSensitive;
  Result.WholeWord := AWholeWord;
end;

procedure TAtlasSelectionMatchesTests.TermNeedsSingleLineMinLengthAndText;
var
  Term: string;
  Short: TAtlasSelectionMatchOptions;
begin
  Assert.IsTrue(TAtlasSelectionMatches.Term('Kunde', TAtlasSelectionMatchOptions.Defaults, Term));
  Assert.AreEqual('Kunde', Term);
  Assert.IsFalse(TAtlasSelectionMatches.Term('Ku', TAtlasSelectionMatchOptions.Defaults, Term), 'zu kurz');
  Assert.AreEqual('', Term);
  Assert.IsFalse(TAtlasSelectionMatches.Term('    ', TAtlasSelectionMatchOptions.Defaults, Term), 'nur Leerraum');
  Assert.IsFalse(TAtlasSelectionMatches.Term('Kunde'#13#10'Neu', TAtlasSelectionMatchOptions.Defaults, Term),
    'mehrzeilig ohne Wirkung');
  Assert.IsFalse(TAtlasSelectionMatches.Term('', TAtlasSelectionMatchOptions.Defaults, Term));
  Assert.IsFalse(TAtlasSelectionMatches.Term(StringOfChar('x', TAtlasSelectionMatches.MaxTermLength + 1),
    TAtlasSelectionMatchOptions.Defaults, Term));
  Short := TAtlasSelectionMatchOptions.Defaults;
  Short.MinLength := 1;
  Assert.IsTrue(TAtlasSelectionMatches.Term('K', Short, Term));
  Assert.IsTrue(TAtlasSelectionMatches.Term(' := ', TAtlasSelectionMatchOptions.Defaults, Term),
    'Leerraum mit Text zählt');
end;

procedure TAtlasSelectionMatchesTests.IgnoresCaseAndFindsPartsByDefault;
begin
  Assert.AreEqual('0:0 0:10 1:3 2:0 2:11 3:13 4:1',
    Describe(TAtlasSelectionMatches.Find(FLines, 'Kunde', Options(False, False))));
end;

procedure TAtlasSelectionMatchesTests.CaseSensitive;
begin
  Assert.AreEqual('0:0 0:10 2:0 2:11 3:13 4:1',
    Describe(TAtlasSelectionMatches.Find(FLines, 'Kunde', Options(True, False))));
  Assert.AreEqual('1:3', Describe(TAtlasSelectionMatches.Find(FLines, 'kunde', Options(True, False))));
end;

procedure TAtlasSelectionMatchesTests.WholeWords;
begin
  // TKunde, Kunden und FKunde fallen weg, „kunde“ im Kommentar bleibt.
  Assert.AreEqual('0:0 1:3 2:11 3:13', Describe(TAtlasSelectionMatches.Find(FLines, 'Kunde', Options(False, True))));
end;

procedure TAtlasSelectionMatchesTests.CaseSensitiveWholeWords;
begin
  Assert.AreEqual('0:0 2:11 3:13', Describe(TAtlasSelectionMatches.Find(FLines, 'Kunde', Options(True, True))));
  Assert.AreEqual('', Describe(TAtlasSelectionMatches.Find(FLines, 'unde', Options(True, True))));
end;

procedure TAtlasSelectionMatchesTests.FindsInStringsAndComments;
begin
  Assert.AreEqual('3:19', Describe(TAtlasSelectionMatches.Find(FLines, 'gespeichert', Options(False, True))));
  Assert.AreEqual('1:0', Describe(TAtlasSelectionMatches.Find(FLines, '// ', Options(False, False))));
  // Treffer überlappen nicht.
  Assert.AreEqual('0:0 0:2', Describe(TAtlasSelectionMatches.Find(['aaaaa'], 'aa', Options(False, False))));
end;

procedure TAtlasSelectionMatchesTests.StopsAtMaxMatches;
var
  Limited: TAtlasSelectionMatchOptions;
  List: TAtlasSelectionMatchList;
begin
  Limited := Options(False, False);
  Limited.MaxMatches := 3;
  List := TAtlasSelectionMatches.Find(FLines, 'Kunde', Limited);
  Assert.AreEqual('0:0 0:10 1:3 +', Describe(List));
  Assert.AreEqual(3, List.Count);
  Limited.MaxMatches := 7;
  Assert.IsFalse(TAtlasSelectionMatches.Find(FLines, 'Kunde', Limited).Truncated, 'genau sieben');
end;

procedure TAtlasSelectionMatchesTests.LimitsToLineRange;
begin
  Assert.AreEqual('2:0 2:11 3:13',
    Describe(TAtlasSelectionMatches.Find(FLines, 'Kunde', Options(False, False), 2, 3)));
  Assert.AreEqual('4:1', Describe(TAtlasSelectionMatches.Find(FLines, 'Kunde', Options(False, False), 4, 99)));
  Assert.AreEqual('', Describe(TAtlasSelectionMatches.Find(FLines, '', Options(False, False))));
end;

procedure TAtlasSelectionMatchesTests.NextWrapsAroundBothWays;
var
  Found: TLspRange;
begin
  // Vorwärts ab dem Ende der Markierung 2:11–2:16.
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'Kunde', Options(False, True), TLspTextPosition.Create(2, 16),
    False, Found));
  Assert.AreEqual(3, Found.StartPos.Line);
  Assert.AreEqual(13, Found.StartPos.Character);
  Assert.AreEqual(18, Found.EndPos.Character);
  // Hinter dem letzten Treffer geht es oben weiter.
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'Kunde', Options(False, True), TLspTextPosition.Create(3, 18),
    False, Found));
  Assert.AreEqual(0, Found.StartPos.Line);
  Assert.AreEqual(0, Found.StartPos.Character);
  // Rückwärts ab dem Anfang der Markierung 0:0: unten weiter.
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'Kunde', Options(False, True), TLspTextPosition.Create(0, 0),
    True, Found));
  Assert.AreEqual(3, Found.StartPos.Line);
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'Kunde', Options(False, True), TLspTextPosition.Create(2, 11),
    True, Found));
  Assert.AreEqual(1, Found.StartPos.Line);
  // Einziger Treffer: wieder er selbst.
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'gespeichert', Options(False, False),
    TLspTextPosition.Create(3, 30), False, Found));
  Assert.AreEqual(3, Found.StartPos.Line);
  Assert.AreEqual(19, Found.StartPos.Character);
  Assert.IsFalse(TAtlasSelectionMatches.Next(FLines, 'Lieferant', Options(False, False),
    TLspTextPosition.Create(0, 0), False, Found));
end;

procedure TAtlasSelectionMatchesTests.LinesAndSelection;
var
  List: TAtlasSelectionMatchList;
  Lines: TArray<Integer>;
begin
  List := TAtlasSelectionMatches.Find(FLines, 'Kunde', Options(False, False));
  Lines := TAtlasSelectionMatches.Lines(List);
  Assert.AreEqual(5, Integer(Length(Lines)));
  Assert.AreEqual(0, Lines[0]);
  Assert.AreEqual(4, Lines[4]);
  Assert.AreEqual(2, Integer(Length(List.OnLine(2))));
  Assert.AreEqual(11, List.OnLine(2)[1].Character);
  Assert.AreEqual(0, Integer(Length(List.OnLine(7))));
  Assert.IsTrue(TAtlasSelectionMatches.IsSelection(List.OnLine(2)[1], 2, 11, 16));
  Assert.IsFalse(TAtlasSelectionMatches.IsSelection(List.OnLine(2)[0], 2, 11, 16));
end;

end.
