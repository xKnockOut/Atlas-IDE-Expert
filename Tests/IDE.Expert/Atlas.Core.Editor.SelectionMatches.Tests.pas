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
  mMatch: TAtlasSelectionMatch;
begin
  Result := '';
  for mMatch in AList.Matches do
  begin
    Result := Result + Format('%d:%d ', [mMatch.Line, mMatch.Character]);
  end;
  Result := Trim(Result);
  if AList.Truncated then
  begin
    Result := Result + ' +';
  end;
end;

function TAtlasSelectionMatchesTests.Options(ACaseSensitive, AWholeWord: Boolean): TAtlasSelectionMatchOptions;
begin
  Result := TAtlasSelectionMatchOptions.Defaults;
  Result.CaseSensitive := ACaseSensitive;
  Result.WholeWord := AWholeWord;
end;

procedure TAtlasSelectionMatchesTests.TermNeedsSingleLineMinLengthAndText;
var
  mTerm: string;
  mShort: TAtlasSelectionMatchOptions;
begin
  Assert.IsTrue(TAtlasSelectionMatches.Term('Kunde', TAtlasSelectionMatchOptions.Defaults, mTerm));
  Assert.AreEqual('Kunde', mTerm);
  Assert.IsFalse(TAtlasSelectionMatches.Term('Ku', TAtlasSelectionMatchOptions.Defaults, mTerm), 'zu kurz');
  Assert.AreEqual('', mTerm);
  Assert.IsFalse(TAtlasSelectionMatches.Term('    ', TAtlasSelectionMatchOptions.Defaults, mTerm), 'nur Leerraum');
  Assert.IsFalse(TAtlasSelectionMatches.Term('Kunde'#13#10'Neu', TAtlasSelectionMatchOptions.Defaults, mTerm),
    'mehrzeilig ohne Wirkung');
  Assert.IsFalse(TAtlasSelectionMatches.Term('', TAtlasSelectionMatchOptions.Defaults, mTerm));
  Assert.IsFalse(TAtlasSelectionMatches.Term(StringOfChar('x', TAtlasSelectionMatches.cMaxTermLength + 1),
    TAtlasSelectionMatchOptions.Defaults, mTerm));
  mShort := TAtlasSelectionMatchOptions.Defaults;
  mShort.MinLength := 1;
  Assert.IsTrue(TAtlasSelectionMatches.Term('K', mShort, mTerm));
  Assert.IsTrue(TAtlasSelectionMatches.Term(' := ', TAtlasSelectionMatchOptions.Defaults, mTerm),
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
  mLimited: TAtlasSelectionMatchOptions;
  mList: TAtlasSelectionMatchList;
begin
  mLimited := Options(False, False);
  mLimited.MaxMatches := 3;
  mList := TAtlasSelectionMatches.Find(FLines, 'Kunde', mLimited);
  Assert.AreEqual('0:0 0:10 1:3 +', Describe(mList));
  Assert.AreEqual(3, mList.Count);
  mLimited.MaxMatches := 7;
  Assert.IsFalse(TAtlasSelectionMatches.Find(FLines, 'Kunde', mLimited).Truncated, 'genau sieben');
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
  mFound: TLspRange;
begin
  // Vorwärts ab dem Ende der Markierung 2:11–2:16.
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'Kunde', Options(False, True), TLspTextPosition.Create(2, 16),
    False, mFound));
  Assert.AreEqual(3, mFound.StartPos.Line);
  Assert.AreEqual(13, mFound.StartPos.Character);
  Assert.AreEqual(18, mFound.EndPos.Character);
  // Hinter dem letzten Treffer geht es oben weiter.
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'Kunde', Options(False, True), TLspTextPosition.Create(3, 18),
    False, mFound));
  Assert.AreEqual(0, mFound.StartPos.Line);
  Assert.AreEqual(0, mFound.StartPos.Character);
  // Rückwärts ab dem Anfang der Markierung 0:0: unten weiter.
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'Kunde', Options(False, True), TLspTextPosition.Create(0, 0),
    True, mFound));
  Assert.AreEqual(3, mFound.StartPos.Line);
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'Kunde', Options(False, True), TLspTextPosition.Create(2, 11),
    True, mFound));
  Assert.AreEqual(1, mFound.StartPos.Line);
  // Einziger Treffer: wieder er selbst.
  Assert.IsTrue(TAtlasSelectionMatches.Next(FLines, 'gespeichert', Options(False, False),
    TLspTextPosition.Create(3, 30), False, mFound));
  Assert.AreEqual(3, mFound.StartPos.Line);
  Assert.AreEqual(19, mFound.StartPos.Character);
  Assert.IsFalse(TAtlasSelectionMatches.Next(FLines, 'Lieferant', Options(False, False),
    TLspTextPosition.Create(0, 0), False, mFound));
end;

procedure TAtlasSelectionMatchesTests.LinesAndSelection;
var
  mList: TAtlasSelectionMatchList;
  mLines: TArray<Integer>;
begin
  mList := TAtlasSelectionMatches.Find(FLines, 'Kunde', Options(False, False));
  mLines := TAtlasSelectionMatches.Lines(mList);
  Assert.AreEqual(5, Integer(Length(mLines)));
  Assert.AreEqual(0, mLines[0]);
  Assert.AreEqual(4, mLines[4]);
  Assert.AreEqual(2, Integer(Length(mList.OnLine(2))));
  Assert.AreEqual(11, mList.OnLine(2)[1].Character);
  Assert.AreEqual(0, Integer(Length(mList.OnLine(7))));
  Assert.IsTrue(TAtlasSelectionMatches.IsSelection(mList.OnLine(2)[1], 2, 11, 16));
  Assert.IsFalse(TAtlasSelectionMatches.IsSelection(mList.OnLine(2)[0], 2, 11, 16));
end;

end.
