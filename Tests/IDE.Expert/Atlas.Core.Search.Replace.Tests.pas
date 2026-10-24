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
  TAtlasSearchReplaceTests = class
  public
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
    procedure RowsCarryPreviewOnlyWithRegex;
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
  Hit: TAtlasSearchHit;
begin
  Result := '';
  for Hit in AHits do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Format('%d:%d+%d', [Hit.Line, Hit.Character, Hit.Length]);
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
  Lines: TArray<string>;
begin
  Lines := TTextLines.SplitLines(AText);
  Result := Describe(TAtlasTextSearch.FindAll(Lines, AQuery.Text, AQuery.Options, TAtlasSearchArea.Whole(Lines)));
end;

/// <summary>Text nach dem Ersetzen aller Treffer.</summary>
function ReplaceAll(const AText: string; const AQuery: TAtlasSearchQuery; const AReplace: string): string;
var
  Lines: TArray<string>;
  Hits: TArray<TAtlasSearchHit>;
begin
  Lines := TTextLines.SplitLines(AText);
  Hits := TAtlasTextSearch.FindAll(Lines, AQuery.Text, AQuery.Options, TAtlasSearchArea.Whole(Lines));
  Result := TLspEdits.Apply(AText, TAtlasSearchReplace.Edits(Lines, Hits, AQuery, AReplace));
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
  Source = 'X := IntToStr(A.Nr); // IntToStr(B.Nr)' + #13#10 +
    'S := ''IntToStr(C.Nr)''; { IntToStr(D.Nr)' + #13#10 +
    'IntToStr(E.Nr) } Y := IntToStr(F.Nr);';
begin
  Assert.AreEqual('0:5+14 2:22+14', FindIn(Source, Query('IntToStr\((\w+)\.Nr\)', False, False, True, True)));
  // Ohne Bezeichner-Modus zählen alle.
  Assert.AreEqual('0:5+14 0:24+14 1:6+14 1:25+14 2:0+14 2:22+14',
    FindIn(Source, Query('IntToStr\((\w+)\.Nr\)', False, False, False, True)));
end;

procedure TAtlasSearchReplaceTests.InvalidRegexReportsErrorAndFindsNothing;
var
  Error: string;
begin
  Assert.IsFalse(TAtlasSearchRegex.Check('(abc', Error));
  Assert.IsTrue(Error <> '', 'Fehlertext der Engine');
  Assert.AreEqual('', FindIn('(abc abc', Query('(abc', False, False, False, True)));
  Assert.IsTrue(TAtlasSearchRegex.Check('a(b)c', Error));
  Assert.AreEqual('', Error);
  Assert.IsTrue(TAtlasSearchRegex.Check('', Error), 'leer ist gültig');
  // Ohne Regex ist „(abc“ ein gewöhnlicher Text.
  Assert.AreEqual('0:0+4', FindIn('(abc abc', Query('(abc', False, False, False, False)));
end;

procedure TAtlasSearchReplaceTests.CodeOnlyMasksCommentsStringsAndDirectives;
var
  Code: TArray<string>;
  M: Char;
begin
  M := TAtlasTextSearch.CodeMask;
  Code := TAtlasTextSearch.CodeOnly(TTextLines.SplitLines('a {$IFDEF X} b ''c'' d // e' + #13#10 +
    '(* f' + #13#10 + 'g *) h' + #13#10 + 'S := ''''''' + #13#10 + '  text' + #13#10 + '  '''''';'));
  Assert.AreEqual('a ' + StringOfChar(M, 10) + ' b ' + StringOfChar(M, 3) + ' d ' + StringOfChar(M, 4), Code[0]);
  Assert.AreEqual(StringOfChar(M, 4), Code[1]);
  Assert.AreEqual(StringOfChar(M, 4) + ' h', Code[2]);
  Assert.AreEqual('S := ' + StringOfChar(M, 3), Code[3]);
  Assert.AreEqual(StringOfChar(M, 6), Code[4]);
  Assert.AreEqual(StringOfChar(M, 5) + ';', Code[5]);
end;

procedure TAtlasSearchReplaceTests.IdentifierModeStillFindsOnlyIdentifiers;
begin
  // Derselbe Lexer wie vor #893: Kommentare, Strings, Zahlen und Schlüsselwörter zählen nicht.
  Assert.AreEqual('0:0+3 2:3+3', FindIn('Foo { Foo } ''Foo''' + #13#10 + '$Foo 1Foo // Foo' + #13#10 +
    'X.&Foo; begin', Query('foo', False, False, True, False)));
end;

procedure TAtlasSearchReplaceTests.ExpandHandlesGroupsNamesAndDollar;
var
  Found: TMatch;
begin
  Found := TRegEx.Create('(?<name>\w+)=(\d+)').Match('Wert=42');
  Assert.IsTrue(Found.Success);
  Assert.AreEqual('42:Wert', TAtlasSearchReplace.Expand('$2:$1', Found));
  Assert.AreEqual('Wert/Wert=42', TAtlasSearchReplace.Expand('${name}/$0', Found));
  Assert.AreEqual('$1 kostet $', TAtlasSearchReplace.Expand('$$1 kostet $', Found));
  Assert.AreEqual('42', TAtlasSearchReplace.Expand('${2}', Found));
  // Unbekannte Gruppen ergeben nichts; ein offenes ${ bleibt stehen.
  Assert.AreEqual('[]', TAtlasSearchReplace.Expand('[$9${gibt_es_nicht}]', Found));
  Assert.AreEqual('${x', TAtlasSearchReplace.Expand('${x', Found));
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
  Lines: TArray<string>;
  Hits: TArray<TAtlasSearchHit>;
  Search: TAtlasSearchQuery;
  Preview: TAtlasReplacePreview;
begin
  Lines := TTextLines.SplitLines('X := IntToStr(Kunde.Nr);');
  Search := Query('IntToStr\((\w+)\.Nr\)', False, False, False, True);
  Hits := TAtlasTextSearch.FindAll(Lines, Search.Text, Search.Options, TAtlasSearchArea.Whole(Lines));
  Preview := TAtlasSearchReplace.Preview(Lines, Hits[0], Search, '$1.Nr.ToString');
  Assert.AreEqual('IntToStr(Kunde.Nr)', Preview.Before);
  Assert.AreEqual('Kunde.Nr.ToString', Preview.After);
  Assert.AreEqual('IntToStr(Kunde.Nr) → Kunde.Nr.ToString', Preview.Caption);
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
  List: TAtlasReplaceList;
  Search: TAtlasSearchQuery;
begin
  Search := Query('a', False, False, False, False);
  List := TAtlasReplaceList.Create(Search, 'b');
  try
    List.Add(Hits('C:\P\Eins.pas', 'a a', Search));
    List.Add(Hits('C:\P\Zwei.pas', 'a', Search));
    List.Add(Hits('C:\P\Leer.pas', 'x', Search));
    Assert.AreEqual(2, Integer(Length(List.Results)), 'Dateien ohne Treffer kommen nicht in die Liste');
    Assert.AreEqual(3, List.CheckedCount, 'Vorgabe: alles angehakt');
    Assert.IsTrue(List.FileChecked(0));
    List.SetHitChecked(0, 1, False);
    Assert.IsFalse(List.FileChecked(0), 'Datei nur angehakt, solange alle Treffer es sind');
    Assert.AreEqual(2, List.CheckedCount);
    List.SetFileChecked(0, True);
    Assert.IsTrue(List.HitChecked(0, 1));
    List.SetFileChecked(1, False);
    Assert.AreEqual(2, List.CheckedCount);
    Assert.AreEqual(3, List.HitCount);
  finally
    List.Free;
  end;
end;

procedure TAtlasSearchReplaceTests.PlanOnlyTakesCheckedHits;
var
  List: TAtlasReplaceList;
  Search: TAtlasSearchQuery;
  Plan: TAtlasReplacePlan;
begin
  Search := Query('a', False, False, False, False);
  List := TAtlasReplaceList.Create(Search, 'b');
  try
    List.Add(Hits('C:\P\Eins.pas', 'a a a', Search));
    List.Add(Hits('C:\P\Zwei.pas', 'a', Search));
    List.SetHitChecked(0, 1, False);
    Plan := List.Plan(nil, nil);
    Assert.AreEqual(3, Plan.Replacements);
    Assert.AreEqual(2, Plan.Files);
    Assert.AreEqual('b a b', TLspEdits.Apply('a a a', Plan.Edit.Files[0].Edits));
    Assert.AreEqual('C:\P\Zwei.pas', Plan.Edit.Files[1].FileName);
    List.SetFileChecked(1, False);
    Plan := List.Plan(nil, nil);
    Assert.AreEqual(1, Plan.Files, 'Datei ohne angehakte Treffer fehlt');
  finally
    List.Free;
  end;
end;

procedure TAtlasSearchReplaceTests.PlanSkipsReadOnlyAndChangedFiles;
var
  List: TAtlasReplaceList;
  Search: TAtlasSearchQuery;
  Plan: TAtlasReplacePlan;
  ReadOnly: TAtlasReplaceFileCheck;
  Current: TAtlasReplaceFileText;
begin
  ReadOnly :=
    function(const AFileName: string): Boolean
    begin
      Result := SameText(ExtractFileName(AFileName), 'Fest.pas');
    end;
  Current :=
    function(const AFileName: string): string
    begin
      if SameText(ExtractFileName(AFileName), 'Neu.pas') then
        Result := 'xa'
      else
        Result := 'a';
    end;
  Search := Query('a', False, False, False, False);
  List := TAtlasReplaceList.Create(Search, 'b');
  try
    List.Add(Hits('C:\P\Eins.pas', 'a', Search));
    List.Add(Hits('C:\P\Fest.pas', 'a', Search));
    List.Add(Hits('C:\P\Neu.pas', 'a', Search));
    Plan := List.Plan(ReadOnly, Current);
    Assert.AreEqual(1, Plan.Files);
    Assert.AreEqual('C:\P\Eins.pas', Plan.Edit.Files[0].FileName);
    Assert.AreEqual(1, Integer(Length(Plan.ReadOnly)));
    Assert.AreEqual('C:\P\Fest.pas', Plan.ReadOnly[0]);
    Assert.AreEqual(1, Integer(Length(Plan.Changed)));
    Assert.AreEqual('C:\P\Neu.pas', Plan.Changed[0]);
  finally
    List.Free;
  end;
end;

procedure TAtlasSearchReplaceTests.RowsCarryPreviewOnlyWithRegex;
var
  List: TAtlasReplaceList;
  Search: TAtlasSearchQuery;
  Rows: TArray<TAtlasReplaceRow>;
begin
  Search := Query('(\w+)\.Free', False, False, False, True);
  List := TAtlasReplaceList.Create(Search, 'FreeAndNil($1)');
  try
    List.Add(Hits('C:\P\Eins.pas', 'begin' + #13#10 + '  X.Free;', Search));
    Rows := List.Rows;
    Assert.AreEqual(2, Integer(Length(Rows)));
    Assert.AreEqual(Ord(TAtlasReplaceRowKind.FileRow), Ord(Rows[0].Kind));
    Assert.AreEqual('Eins.pas', Rows[0].Text);
    Assert.AreEqual(Ord(TAtlasReplaceRowKind.HitRow), Ord(Rows[1].Kind));
    Assert.AreEqual(2, Rows[1].Line);
    Assert.AreEqual('X.Free;', Rows[1].Text);
    Assert.AreEqual('X.Free → FreeAndNil(X)', Rows[1].Preview);
  finally
    List.Free;
  end;
  Search := Query('Free', False, False, False, False);
  List := TAtlasReplaceList.Create(Search, 'Destroy');
  try
    List.Add(Hits('C:\P\Eins.pas', 'X.Free;', Search));
    Assert.AreEqual('', List.Rows[1].Preview, 'Vorschau nur mit Regex');
  finally
    List.Free;
  end;
end;

procedure TAtlasSearchReplaceTests.FollowSelectionSwitchesRegexOff;
var
  Last, Next: TAtlasSearchQuery;
  Changed: Boolean;
begin
  Last := Query('a+', False, False, False, True);
  Next := TAtlasSearchResults.FollowSelection(Last, 'x.y', Changed);
  Assert.IsTrue(Changed);
  Assert.IsFalse(Next.Options.Regex, 'Markierung ist Text, kein Ausdruck');
  Assert.AreEqual('x.y', Next.Text);
end;

procedure TAtlasSearchReplaceTests.SettingsDefaultsNormalizeAndKeys;
var
  Settings: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
  Entry: TAtlasKeyEntry;
  Found: Boolean;
  Index: Integer;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.SearchReplace);
  Assert.IsTrue(Settings.SearchRegex);
  Assert.AreEqual(20, Settings.SearchHistory);
  Assert.IsTrue(Settings.SearchMultiFile);
  Assert.AreEqual($4048, Settings.SearchReplaceKey, 'Strg+H');
  Settings.SearchHistory := -1;
  Settings.SearchReplaceKey := $1FFFF;
  Settings.Normalize;
  Assert.AreEqual(0, Settings.SearchHistory);
  Assert.AreEqual($FFFF, Settings.SearchReplaceKey);
  Settings.SearchHistory := 1000;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxSearchHistory, Settings.SearchHistory);
  // Strg+H nur mit search.replaceIdeSearch und search.replace; aus = die IDE behält die Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Found := False;
  for Entry in TAtlasKeyEntry.AllFromSettings(Settings) do
    if Entry.Func = TAtlasKeyFunction.SearchReplace then
    begin
      Found := True;
      Assert.AreEqual($4048, Integer(Entry.Key));
      Assert.IsFalse(Entry.Disabled);
      Assert.IsTrue(Entry.Priority, 'bewusst übernommen wie Strg+F');
    end;
  Assert.IsTrue(Found);
  Assert.AreEqual('Atlas.SearchReplace', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SearchReplace));
  Settings.SearchReplace := False;
  for Entry in TAtlasKeyEntry.AllFromSettings(Settings) do
    if Entry.Func = TAtlasKeyFunction.SearchReplace then
      Assert.IsTrue(Entry.Disabled);
  Settings := TAtlasPluginSettings.Defaults;
  Settings.SearchReplaceIde := False;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  for Entry in Entries do
    if Entry.Func = TAtlasKeyFunction.SearchReplace then
      Assert.IsTrue(Entry.Disabled);
  for Index := 0 to High(Entries) do
    if Entries[Index].Func = TAtlasKeyFunction.SearchReplace then
      Entries[Index].Key := $C048;
  TAtlasKeyEntry.ToSettings(Entries, Settings);
  Assert.AreEqual($C048, Settings.SearchReplaceKey);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchReplaceTests);

end.
