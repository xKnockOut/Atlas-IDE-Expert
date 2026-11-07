unit Atlas.Core.Search.Replace.Tests;

// Tests für Regex und Ersetzen der Atlas-Suchleiste (#893): Treffer mit Regex,
// Fehlerfall, Filter Bezeichner/Kommentar/String, Ersetzen mit Gruppen,
// Vorschau, Auswahl über Dateien und Plan (schreibgeschützt, geändert),
// Einstellungen und Tasten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TAtlasSearchReplaceTests = class
  public
    /// <summary>Einmalige Puffer der Regex-Engine (Fehlertexte, Gruppen) vor dem Leckmonitor anlegen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure RegexFindsMatchesPerLine;
    [Test]
    procedure RegexIgnoresCaseUnlessAsked;
    [Test]
    procedure RegexSkipsEmptyMatches;
    [Test]
    procedure RegexWholeWordNeedsWordBoundaries;
    [Test]
    procedure RegexWithIdentifierSkipsCommentsAndStrings;
    [Test]
    procedure InvalidRegexReportsErrorAndFindsNothing;
    [Test]
    procedure CodeOnlyMasksCommentsStringsAndDirectives;
    [Test]
    procedure IdentifierModeStillFindsOnlyIdentifiers;
    [Test]
    procedure ExpandHandlesGroupsNamesAndDollar;
    [Test]
    procedure ReplaceWithGroupsFromTheIssue;
    [Test]
    procedure TextModeReplacesLiterally;
    [Test]
    procedure PreviewShowsBeforeAndAfter;
    [Test]
    procedure EditsKeepLineEndings;
    [Test]
    procedure ReplaceListChecksFilesAndHits;
    [Test]
    procedure PlanOnlyTakesCheckedHits;
    [Test]
    procedure PlanSkipsReadOnlyAndChangedFiles;
    [Test]
    procedure RowsCarryPreview;
    [Test]
    procedure FollowSelectionSwitchesRegexOff;
    [Test]
    procedure SettingsDefaultsNormalizeAndKeys;
  end;

implementation

uses
  System.SysUtils,
  System.RegularExpressions,
  Atlas.Text.Lines,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Results,
  Atlas.Core.Search.Replace,
  Atlas.Core.Search.ReplaceList,
  Atlas.Core.Search.Files,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap;

/// <summary>"Zeile:Zeichen+Länge" je Treffer, durch Leerzeichen getrennt.</summary>
function Describe(const AHits: TArray<TAtlasSearchHit>): string;
var
  mHit: TAtlasSearchHit;
begin
  Result := '';
  for mHit in AHits do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + Format('%d:%d+%d', [mHit.Line, mHit.Character, mHit.Length]);
  end;
end;

function Query(const AText: string; ACase, AWhole, AIdent, ARegex: Boolean): TAtlasSearchQuery;
begin
  Result := Default(TAtlasSearchQuery);
  Result.Text := AText;
  Result.Options := TAtlasSearchOptions.Create(ACase, AWhole, AIdent, ARegex);
end;

function FindIn(const AText: string; const AQuery: TAtlasSearchQuery): string;
var
  mLines: TArray<string>;
begin
  mLines := TTextLines.SplitLines(AText);
  Result := Describe(TAtlasTextSearch.FindAll(mLines, AQuery.Text, AQuery.Options, TAtlasSearchArea.Whole(mLines)));
end;

/// <summary>Text nach dem Ersetzen aller Treffer.</summary>
function ReplaceAll(const AText: string; const AQuery: TAtlasSearchQuery; const AReplace: string): string;
var
  mLines: TArray<string>;
  mHits: TArray<TAtlasSearchHit>;
begin
  mLines := TTextLines.SplitLines(AText);
  mHits := TAtlasTextSearch.FindAll(mLines, AQuery.Text, AQuery.Options, TAtlasSearchArea.Whole(mLines));
  Result := TLspEdits.Apply(AText, TAtlasSearchReplace.Edits(mLines, mHits, AQuery, AReplace));
end;

procedure TAtlasSearchReplaceTests.WarmUpFirstUse;
begin
  InvalidRegexReportsErrorAndFindsNothing;
  ExpandHandlesGroupsNamesAndDollar;
end;

procedure TAtlasSearchReplaceTests.RegexFindsMatchesPerLine;
begin
  Assert.AreEqual('0:2+4 0:9+4 1:0+4', FindIn('a foo1 x foo2' + #13#10 + 'foo3 b', Query('foo\d', False, False,
    False, True)));
end;

procedure TAtlasSearchReplaceTests.RegexIgnoresCaseUnlessAsked;
begin
  Assert.AreEqual('0:0+3 0:4+3', FindIn('Abc abc', Query('abc', False, False, False, True)));
  Assert.AreEqual('0:4+3', FindIn('Abc abc', Query('abc', True, False, False, True)));
end;

procedure TAtlasSearchReplaceTests.RegexSkipsEmptyMatches;
begin
  // „x*“ passt auch leer: nur die nicht leeren Treffer zählen.
  Assert.AreEqual('0:1+2', FindIn('axxb', Query('x*', False, False, False, True)));
  Assert.AreEqual('', FindIn('abc', Query('^', False, False, False, True)));
end;

procedure TAtlasSearchReplaceTests.RegexWholeWordNeedsWordBoundaries;
begin
  Assert.AreEqual('0:5+3', FindIn('Foo1 Foo _Foo', Query('Fo+', True, True, False, True)));
end;

procedure TAtlasSearchReplaceTests.RegexWithIdentifierSkipsCommentsAndStrings;
const
  cSource = 'X := IntToStr(A.Nr); // IntToStr(B.Nr)' + #13#10 +
    'S := ''IntToStr(C.Nr)''; { IntToStr(D.Nr)' + #13#10 +
    'IntToStr(E.Nr) } Y := IntToStr(F.Nr);';
begin
  Assert.AreEqual('0:5+14 2:22+14', FindIn(cSource, Query('IntToStr\((\w+)\.Nr\)', False, False, True, True)));
  // Ohne Bezeichner-Modus zählen alle.
  Assert.AreEqual('0:5+14 0:24+14 1:6+14 1:25+14 2:0+14 2:22+14',
    FindIn(cSource, Query('IntToStr\((\w+)\.Nr\)', False, False, False, True)));
end;

procedure TAtlasSearchReplaceTests.InvalidRegexReportsErrorAndFindsNothing;
var
  mError: string;
begin
  Assert.IsFalse(TAtlasSearchRegex.Check('(abc', mError));
  Assert.IsTrue(mError <> '', 'Fehlertext der Engine');
  Assert.AreEqual('', FindIn('(abc abc', Query('(abc', False, False, False, True)));
  Assert.IsTrue(TAtlasSearchRegex.Check('a(b)c', mError));
  Assert.AreEqual('', mError);
  Assert.IsTrue(TAtlasSearchRegex.Check('', mError), 'leer ist gültig');
  // Ohne Regex ist „(abc“ ein gewöhnlicher Text.
  Assert.AreEqual('0:0+4', FindIn('(abc abc', Query('(abc', False, False, False, False)));
end;

procedure TAtlasSearchReplaceTests.CodeOnlyMasksCommentsStringsAndDirectives;
var
  mCode: TArray<string>;
  M: Char;
begin
  M := TAtlasTextSearch.cCodeMask;
  mCode := TAtlasTextSearch.CodeOnly(TTextLines.SplitLines('a {$IFDEF X} b ''c'' d // e' + #13#10 +
    '(* f' + #13#10 + 'g *) h' + #13#10 + 'S := ''''''' + #13#10 + '  text' + #13#10 + '  '''''';'));
  Assert.AreEqual('a ' + StringOfChar(M, 10) + ' b ' + StringOfChar(M, 3) + ' d ' + StringOfChar(M, 4), mCode[0]);
  Assert.AreEqual(StringOfChar(M, 4), mCode[1]);
  Assert.AreEqual(StringOfChar(M, 4) + ' h', mCode[2]);
  Assert.AreEqual('S := ' + StringOfChar(M, 3), mCode[3]);
  Assert.AreEqual(StringOfChar(M, 6), mCode[4]);
  Assert.AreEqual(StringOfChar(M, 5) + ';', mCode[5]);
end;

procedure TAtlasSearchReplaceTests.IdentifierModeStillFindsOnlyIdentifiers;
begin
  // Derselbe Lexer wie vor #893: Kommentare, Strings, Zahlen und Schlüsselwörter zählen nicht.
  Assert.AreEqual('0:0+3 2:3+3', FindIn('Foo { Foo } ''Foo''' + #13#10 + '$Foo 1Foo // Foo' + #13#10 +
    'X.&Foo; begin', Query('foo', False, False, True, False)));
end;

procedure TAtlasSearchReplaceTests.ExpandHandlesGroupsNamesAndDollar;
var
  mFound: TMatch;
begin
  mFound := TRegEx.Create('(?<name>\w+)=(\d+)').Match('Wert=42');
  Assert.IsTrue(mFound.Success);
  Assert.AreEqual('42:Wert', TAtlasSearchReplace.Expand('$2:$1', mFound));
  Assert.AreEqual('Wert/Wert=42', TAtlasSearchReplace.Expand('${name}/$0', mFound));
  Assert.AreEqual('$1 kostet $', TAtlasSearchReplace.Expand('$$1 kostet $', mFound));
  Assert.AreEqual('42', TAtlasSearchReplace.Expand('${2}', mFound));
  // Unbekannte Gruppen ergeben nichts; ein offenes ${ bleibt stehen.
  Assert.AreEqual('[]', TAtlasSearchReplace.Expand('[$9${gibt_es_nicht}]', mFound));
  Assert.AreEqual('${x', TAtlasSearchReplace.Expand('${x', mFound));
end;

procedure TAtlasSearchReplaceTests.ReplaceWithGroupsFromTheIssue;
begin
  // Akzeptanzkriterium #893.
  Assert.AreEqual('S := Kunde.Nr.ToString + Auftrag.Nr.ToString;',
    ReplaceAll('S := IntToStr(Kunde.Nr) + IntToStr(Auftrag.Nr);', Query('IntToStr\((\w+)\.Nr\)', False, False,
    False, True), '$1.Nr.ToString'));
end;

procedure TAtlasSearchReplaceTests.TextModeReplacesLiterally;
begin
  Assert.AreEqual('b $1 b', ReplaceAll('a $1 a', Query('a', True, True, False, False), 'b'));
  Assert.AreEqual('x$1x', ReplaceAll('xax', Query('a', False, False, False, False), '$1'));
end;

procedure TAtlasSearchReplaceTests.PreviewShowsBeforeAndAfter;
var
  mLines: TArray<string>;
  mHits: TArray<TAtlasSearchHit>;
  mSearch: TAtlasSearchQuery;
  mPreview: TAtlasReplacePreview;
begin
  mLines := TTextLines.SplitLines('X := IntToStr(Kunde.Nr);');
  mSearch := Query('IntToStr\((\w+)\.Nr\)', False, False, False, True);
  mHits := TAtlasTextSearch.FindAll(mLines, mSearch.Text, mSearch.Options, TAtlasSearchArea.Whole(mLines));
  mPreview := TAtlasSearchReplace.Preview(mLines, mHits[0], mSearch, '$1.Nr.ToString');
  Assert.AreEqual('IntToStr(Kunde.Nr)', mPreview.Before);
  Assert.AreEqual('Kunde.Nr.ToString', mPreview.After);
  Assert.AreEqual('IntToStr(Kunde.Nr) → Kunde.Nr.ToString', mPreview.Caption);
end;

procedure TAtlasSearchReplaceTests.EditsKeepLineEndings;
begin
  Assert.AreEqual('neu' + #13#10 + 'x neu' + #10 + 'neu',
    ReplaceAll('alt' + #13#10 + 'x alt' + #10 + 'alt', Query('alt', False, False, False, False), 'neu'));
end;

function Hits(const AFileName, AText: string; const AQuery: TAtlasSearchQuery): TAtlasFileHits;
begin
  Result := TAtlasFileSearch.SearchText(AFileName, AText, AQuery);
end;

procedure TAtlasSearchReplaceTests.ReplaceListChecksFilesAndHits;
var
  mList: TAtlasReplaceList;
  mSearch: TAtlasSearchQuery;
begin
  mSearch := Query('a', False, False, False, False);
  mList := TAtlasReplaceList.Create(mSearch, 'b');
  try
    mList.Add(Hits('C:\P\Eins.pas', 'a a', mSearch));
    mList.Add(Hits('C:\P\Zwei.pas', 'a', mSearch));
    mList.Add(Hits('C:\P\Leer.pas', 'x', mSearch));
    Assert.AreEqual(2, Integer(Length(mList.Results)), 'Dateien ohne Treffer kommen nicht in die Liste');
    Assert.AreEqual(3, mList.CheckedCount, 'Vorgabe: alles angehakt');
    Assert.IsTrue(mList.FileChecked(0));
    mList.SetHitChecked(0, 1, False);
    Assert.IsFalse(mList.FileChecked(0), 'Datei nur angehakt, solange alle Treffer es sind');
    Assert.AreEqual(2, mList.CheckedCount);
    mList.SetFileChecked(0, True);
    Assert.IsTrue(mList.HitChecked(0, 1));
    mList.SetFileChecked(1, False);
    Assert.AreEqual(2, mList.CheckedCount);
    Assert.AreEqual(3, mList.HitCount);
  finally
    mList.Free;
  end;
end;

procedure TAtlasSearchReplaceTests.PlanOnlyTakesCheckedHits;
var
  mList: TAtlasReplaceList;
  mSearch: TAtlasSearchQuery;
  mPlan: TAtlasReplacePlan;
begin
  mSearch := Query('a', False, False, False, False);
  mList := TAtlasReplaceList.Create(mSearch, 'b');
  try
    mList.Add(Hits('C:\P\Eins.pas', 'a a a', mSearch));
    mList.Add(Hits('C:\P\Zwei.pas', 'a', mSearch));
    mList.SetHitChecked(0, 1, False);
    mPlan := mList.Plan(nil, nil);
    Assert.AreEqual(3, mPlan.Replacements);
    Assert.AreEqual(2, mPlan.Files);
    Assert.AreEqual('b a b', TLspEdits.Apply('a a a', mPlan.Edit.Files[0].Edits));
    Assert.AreEqual('C:\P\Zwei.pas', mPlan.Edit.Files[1].FileName);
    mList.SetFileChecked(1, False);
    mPlan := mList.Plan(nil, nil);
    Assert.AreEqual(1, mPlan.Files, 'Datei ohne angehakte Treffer fehlt');
  finally
    mList.Free;
  end;
end;

procedure TAtlasSearchReplaceTests.PlanSkipsReadOnlyAndChangedFiles;
var
  mList: TAtlasReplaceList;
  mSearch: TAtlasSearchQuery;
  mPlan: TAtlasReplacePlan;
  mReadOnly: TAtlasReplaceFileCheck;
  mCurrent: TAtlasReplaceFileText;
begin
  mReadOnly :=
    function(const AFileName: string): Boolean
    begin
      Result := SameText(ExtractFileName(AFileName), 'Fest.pas');
    end;
  mCurrent :=
    function(const AFileName: string): string
    begin
      if SameText(ExtractFileName(AFileName), 'Neu.pas') then
      begin
        Result := 'xa';
      end
      else
      begin
        Result := 'a';
      end;
    end;
  mSearch := Query('a', False, False, False, False);
  mList := TAtlasReplaceList.Create(mSearch, 'b');
  try
    mList.Add(Hits('C:\P\Eins.pas', 'a', mSearch));
    mList.Add(Hits('C:\P\Fest.pas', 'a', mSearch));
    mList.Add(Hits('C:\P\Neu.pas', 'a', mSearch));
    mPlan := mList.Plan(mReadOnly, mCurrent);
    Assert.AreEqual(1, mPlan.Files);
    Assert.AreEqual('C:\P\Eins.pas', mPlan.Edit.Files[0].FileName);
    Assert.AreEqual(1, Integer(Length(mPlan.ReadOnly)));
    Assert.AreEqual('C:\P\Fest.pas', mPlan.ReadOnly[0]);
    Assert.AreEqual(1, Integer(Length(mPlan.Changed)));
    Assert.AreEqual('C:\P\Neu.pas', mPlan.Changed[0]);
  finally
    mList.Free;
  end;
end;

procedure TAtlasSearchReplaceTests.RowsCarryPreview;
var
  mList: TAtlasReplaceList;
  mSearch: TAtlasSearchQuery;
  mRows: TArray<TAtlasReplaceRow>;
begin
  mSearch := Query('(\w+)\.Free', False, False, False, True);
  mList := TAtlasReplaceList.Create(mSearch, 'FreeAndNil($1)');
  try
    mList.Add(Hits('C:\P\Eins.pas', 'begin' + #13#10 + '  X.Free;', mSearch));
    mRows := mList.Rows;
    Assert.AreEqual(2, Integer(Length(mRows)));
    Assert.AreEqual(Ord(TAtlasReplaceRowKind.FileRow), Ord(mRows[0].Kind));
    Assert.AreEqual('Eins.pas', mRows[0].Text);
    Assert.AreEqual(Ord(TAtlasReplaceRowKind.HitRow), Ord(mRows[1].Kind));
    Assert.AreEqual(2, mRows[1].Line);
    Assert.AreEqual('X.Free;', mRows[1].Text);
    Assert.AreEqual('X.Free → FreeAndNil(X)', mRows[1].Preview);
  finally
    mList.Free;
  end;
  // Ohne Regex: der gefundene Text (hier in anderer Schreibweise) und der Ersatz.
  mSearch := Query('free', False, False, False, False);
  mList := TAtlasReplaceList.Create(mSearch, 'Destroy');
  try
    mList.Add(Hits('C:\P\Eins.pas', 'X.Free;', mSearch));
    Assert.AreEqual('Free → Destroy', mList.Rows[1].Preview, 'Vorschau auch ohne Regex');
  finally
    mList.Free;
  end;
end;

procedure TAtlasSearchReplaceTests.FollowSelectionSwitchesRegexOff;
var
  mLast, mNext: TAtlasSearchQuery;
  mChanged: Boolean;
begin
  mLast := Query('a+', False, False, False, True);
  mNext := TAtlasSearchResults.FollowSelection(mLast, 'x.y', mChanged);
  Assert.IsTrue(mChanged);
  Assert.IsFalse(mNext.Options.Regex, 'Markierung ist Text, kein Ausdruck');
  Assert.AreEqual('x.y', mNext.Text);
end;

/// <summary>Strg+H nur mit search.replaceIdeSearch und search.replace; aus = die IDE behält die Taste.</summary>
procedure AssertReplaceKeys;
var
  mSettings: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
  mEntry: TAtlasKeyEntry;
  mFound: Boolean;
  mIndex: Integer;
begin
  // Strg+H nur mit search.replaceIdeSearch und search.replace; aus = die IDE behält die Taste.
  mSettings := TAtlasPluginSettings.Defaults;
  mFound := False;
  for mEntry in TAtlasKeyEntry.AllFromSettings(mSettings) do
  begin
    if mEntry.Func = TAtlasKeyFunction.SearchReplace then
    begin
      mFound := True;
      Assert.AreEqual($4048, Integer(mEntry.Key));
      Assert.IsFalse(mEntry.Disabled);
      Assert.IsTrue(mEntry.Priority, 'bewusst übernommen wie Strg+F');
    end;
  end;
  Assert.IsTrue(mFound);
  Assert.AreEqual('Atlas.SearchReplace', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SearchReplace));
  mSettings.SearchReplace := False;
  for mEntry in TAtlasKeyEntry.AllFromSettings(mSettings) do
  begin
    if mEntry.Func = TAtlasKeyFunction.SearchReplace then
    begin
      Assert.IsTrue(mEntry.Disabled);
    end;
  end;
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.SearchReplaceIde := False;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  for mEntry in mEntries do
  begin
    if mEntry.Func = TAtlasKeyFunction.SearchReplace then
    begin
      Assert.IsTrue(mEntry.Disabled);
    end;
  end;
  for mIndex := 0 to High(mEntries) do
  begin
    if mEntries[mIndex].Func = TAtlasKeyFunction.SearchReplace then
    begin
      mEntries[mIndex].Key := $C048;
    end;
  end;
  TAtlasKeyEntry.ToSettings(mEntries, mSettings);
  Assert.AreEqual($C048, mSettings.SearchReplaceKey);
end;

procedure TAtlasSearchReplaceTests.SettingsDefaultsNormalizeAndKeys;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.SearchReplace);
  Assert.IsTrue(mSettings.SearchRegex);
  Assert.AreEqual(20, mSettings.SearchHistory);
  Assert.IsTrue(mSettings.SearchMultiFile);
  Assert.AreEqual($4048, mSettings.SearchReplaceKey, 'Strg+H');
  mSettings.SearchHistory := -1;
  mSettings.SearchReplaceKey := $1FFFF;
  mSettings.Normalize;
  Assert.AreEqual(0, mSettings.SearchHistory);
  Assert.AreEqual($FFFF, mSettings.SearchReplaceKey);
  mSettings.SearchHistory := 1000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxSearchHistory, mSettings.SearchHistory);
  AssertReplaceKeys;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchReplaceTests);

end.
