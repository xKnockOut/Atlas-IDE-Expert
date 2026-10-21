unit Atlas.Core.Search.Tests;

// Tests für die Atlas-Suche (#877, #878): Treffer mit Optionen, Bezeichner-Modus,
// Bereiche (Routine, Unit, Auswahl), Weitersuchen mit Umlauf, Tasten und Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSearchTests = class
  public
    [Test]
    procedure TextModeFindsAllIgnoringCase;
    [Test]
    procedure CaseSensitiveAndWholeWord;
    [Test]
    procedure IdentifierModeSkipsCommentsStringsAndNumbers;
    [Test]
    procedure IdentifierModeHandlesMultiLineCommentsAndStrings;
    [Test]
    procedure IdentifierModeSkipsKeywordsButNotEscapedNames;
    [Test]
    procedure AreaLimitsHits;
    [Test]
    procedure NextWrapsForwardAndBackward;
    [Test]
    procedure RoutinesAtListInnermostFirstWithLocalDeclarations;
    [Test]
    procedure AreaForMethodUnitAndSelection;
    [Test]
    procedure WordAtAndHitCaption;
    [Test]
    procedure KeysComeFromSettingsAndFollowTheSwitch;
    [Test]
    procedure SettingsDefaultsAndRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Scopes,
  Atlas.Text.Lines,
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

function Find(const AText, ANeedle: string; ACase, AWhole, AIdent: Boolean): string;
var
  Lines: TArray<string>;
begin
  Lines := TTextLines.SplitLines(AText);
  Result := Describe(TAtlasTextSearch.FindAll(Lines, ANeedle, TAtlasSearchOptions.Create(ACase, AWhole, AIdent),
    TAtlasSearchArea.Whole(Lines)));
end;

function EntryOf(const AEntries: TArray<TAtlasKeyEntry>; AFunc: TAtlasKeyFunction): TAtlasKeyEntry;
var
  Entry: TAtlasKeyEntry;
begin
  for Entry in AEntries do
    if Entry.Func = AFunc then
      Exit(Entry);
  Result := Default(TAtlasKeyEntry);
  Assert.Fail('Eintrag fehlt');
end;

{ TAtlasSearchTests }

procedure TAtlasSearchTests.TextModeFindsAllIgnoringCase;
begin
  Assert.AreEqual('0:0+3 0:7+3 1:2+3', Find('Foo := foo;'#13#10'  FOO', 'foo', False, False, False));
  // Ohne Überlappung: „aaaa“ enthält „aa“ zweimal.
  Assert.AreEqual('0:0+2 0:2+2', Find('aaaa', 'aa', False, False, False));
  Assert.AreEqual('', Find('abc', '', False, False, False), 'leerer Suchtext');
end;

procedure TAtlasSearchTests.CaseSensitiveAndWholeWord;
begin
  Assert.AreEqual('0:7+3', Find('Foo := foo;', 'foo', True, False, False));
  Assert.AreEqual('0:0+3', Find('Foo FooBar BarFoo', 'foo', False, True, False));
  Assert.AreEqual('0:5+5', Find('Foo_ Foo_1 x', 'foo_1', False, True, False));
  // Im Textmodus zählen Kommentare und Strings mit.
  Assert.AreEqual('0:0+1 0:6+1 0:9+1', Find('X; // X ''X''', 'x', False, True, False));
end;

procedure TAtlasSearchTests.IdentifierModeSkipsCommentsStringsAndNumbers;
begin
  Assert.AreEqual('0:0+5 1:18+5', Find('Count := 1; // Count'#10'S := ''Count''; Inc(Count);',
    'count', False, False, True));
  // $FF, #13 und 1E5 sind keine Bezeichner.
  Assert.AreEqual('0:23+2', Find('X := $FF + #13 + 1E5 + FF;', 'FF', False, False, True));
  Assert.AreEqual('0:0+1 0:22+1', Find('X := ''It''''s X''; { X } X', 'x', False, False, True));
  // Ganze Bezeichner: „Counter“ ist kein Treffer für „Count“.
  Assert.AreEqual('', Find('Counter := 1;', 'Count', False, False, True));
end;

procedure TAtlasSearchTests.IdentifierModeHandlesMultiLineCommentsAndStrings;
const
  Text = 'A := 1;'#10'{ A'#10'  A }'#10'(* A'#10'A *) A'#10'S := '''''''#10'  A'#10'  '''''';'#10'A';
begin
  Assert.AreEqual('0:0+1 4:5+1 8:0+1', Find(Text, 'a', False, False, True));
end;

procedure TAtlasSearchTests.IdentifierModeSkipsKeywordsButNotEscapedNames;
begin
  Assert.AreEqual('', Find('begin end;', 'begin', False, False, True));
  Assert.AreEqual('0:1+5', Find('&begin := begin;', 'begin', False, False, True));
  Assert.AreEqual('0:1+5', Find('&begin := begin;', '&begin', False, False, True));
  // Mitglieder hinter "." zählen mit (der Lexer kennt keine Symbole).
  Assert.AreEqual('0:0+4 0:10+4', Find('Name := X.Name;', 'Name', False, False, True));
end;

procedure TAtlasSearchTests.AreaLimitsHits;
var
  Lines: TArray<string>;
  Options: TAtlasSearchOptions;
begin
  Lines := TTextLines.SplitLines('a a'#10'a a'#10'a a');
  Options := TAtlasSearchOptions.Create(False, False, False);
  // Von Zeile 0, Zeichen 2 bis Zeile 1, Zeichen 1: nur die Treffer ganz darin.
  Assert.AreEqual('0:2+1 1:0+1', Describe(TAtlasTextSearch.FindAll(Lines, 'a', Options,
    TAtlasSearchArea.Create(0, 2, 1, 1))));
  Options.Identifier := True;
  Assert.AreEqual('0:2+1 1:0+1', Describe(TAtlasTextSearch.FindAll(Lines, 'a', Options,
    TAtlasSearchArea.Create(0, 2, 1, 1))));
  Assert.AreEqual('', Describe(TAtlasTextSearch.FindAll(Lines, 'a', Options, TAtlasSearchArea.Create(1, 1, 1, 1))),
    'leerer Bereich');
end;

procedure TAtlasSearchTests.NextWrapsForwardAndBackward;
var
  Hits: TArray<TAtlasSearchHit>;
  Wrapped: Boolean;
begin
  Hits := [TAtlasSearchHit.Create(1, 0, 3), TAtlasSearchHit.Create(3, 4, 3), TAtlasSearchHit.Create(5, 0, 3)];
  Assert.AreEqual(0, TAtlasTextSearch.Next(Hits, TAtlasSearchPos.Create(0, 0), False, Wrapped));
  Assert.IsFalse(Wrapped);
  // Ein Treffer am Cursor zählt vorwärts; nach dem Markieren steht der Cursor hinter ihm.
  Assert.AreEqual(1, TAtlasTextSearch.Next(Hits, TAtlasSearchPos.Create(3, 4), False, Wrapped));
  Assert.AreEqual(2, TAtlasTextSearch.Next(Hits, TAtlasSearchPos.Create(3, 7), False, Wrapped));
  Assert.AreEqual(0, TAtlasTextSearch.Next(Hits, TAtlasSearchPos.Create(5, 3), False, Wrapped));
  Assert.IsTrue(Wrapped, 'Umlauf vorwärts');
  Assert.AreEqual(0, TAtlasTextSearch.Next(Hits, TAtlasSearchPos.Create(3, 4), True, Wrapped));
  Assert.IsFalse(Wrapped);
  Assert.AreEqual(2, TAtlasTextSearch.Next(Hits, TAtlasSearchPos.Create(1, 0), True, Wrapped));
  Assert.IsTrue(Wrapped, 'Umlauf rückwärts');
  Assert.AreEqual(-1, TAtlasTextSearch.Next(nil, TAtlasSearchPos.Create(0, 0), False, Wrapped));
end;

procedure TAtlasSearchTests.RoutinesAtListInnermostFirstWithLocalDeclarations;
const
  Text = 'implementation'#10 + // 0
    'procedure TFoo.Outer;'#10 + // 1
    'var'#10 + // 2
    '  X: Integer;'#10 + // 3
    '  procedure Inner;'#10 + // 4
    '  begin'#10 + // 5
    '    X := 1;'#10 + // 6
    '  end;'#10 + // 7
    'begin'#10 + // 8
    '  Inner;'#10 + // 9
    'end;'#10 + // 10
    'type TBar = class end;'#10 + // 11
    'class function TFoo.Make: TFoo;'#10 + // 12
    'begin'#10 + // 13
    'end;'; // 14
var
  Around: TArray<TAtlasSearchRoutine>;
begin
  Assert.AreEqual(3, Integer(Length(TAtlasSearchScopes.Routines(Text))), 'Klassentyp ist keine Routine');
  Around := TAtlasSearchScopes.RoutinesAt(Text, TAtlasSearchPos.Create(6, 5));
  Assert.AreEqual(2, Integer(Length(Around)));
  Assert.AreEqual('procedure Inner;', Around[0].Caption);
  Assert.AreEqual(4, Around[0].Area.Start.Line);
  Assert.AreEqual(7, Around[0].Area.Stop.Line);
  Assert.AreEqual('procedure TFoo.Outer;', Around[1].Caption);
  Assert.AreEqual(1, Around[1].Area.Start.Line);
  Assert.AreEqual(10, Around[1].Area.Stop.Line);
  // Lokale Deklarationen gehören zur Routine.
  Assert.AreEqual(1, Integer(Length(TAtlasSearchScopes.RoutinesAt(Text, TAtlasSearchPos.Create(3, 3)))));
  Around := TAtlasSearchScopes.RoutinesAt(Text, TAtlasSearchPos.Create(13, 0));
  Assert.AreEqual(1, Integer(Length(Around)));
  Assert.AreEqual('class function TFoo.Make: TFoo;', Around[0].Caption);
  Assert.AreEqual(0, Integer(Length(TAtlasSearchScopes.RoutinesAt(Text, TAtlasSearchPos.Create(0, 2)))));
end;

procedure TAtlasSearchTests.AreaForMethodUnitAndSelection;
const
  Text = 'procedure A;'#10'  procedure B;'#10'  begin'#10'  end;'#10'begin'#10'end;'#10'X';
var
  Area, Selection: TAtlasSearchArea;
  Cursor: TAtlasSearchPos;
begin
  Cursor := TAtlasSearchPos.Create(2, 3);
  Selection := TAtlasSearchArea.Create(0, 0, 0, 0);
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(Text, TAtlasSearchScope.Method, Cursor, Selection, 0, Area));
  Assert.AreEqual(1, Area.Start.Line, 'innerste');
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(Text, TAtlasSearchScope.Method, Cursor, Selection, 1, Area));
  Assert.AreEqual(0, Area.Start.Line, 'äußere');
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(Text, TAtlasSearchScope.Method, Cursor, Selection, 9, Area));
  Assert.AreEqual(0, Area.Start.Line, 'zu hohe Stufe bleibt bei der äußersten');
  Assert.IsFalse(TAtlasSearchScopes.AreaFor(Text, TAtlasSearchScope.Method, TAtlasSearchPos.Create(6, 0),
    Selection, 0, Area), 'außerhalb jeder Routine');
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(Text, TAtlasSearchScope.UnitFile, Cursor, Selection, 0, Area));
  Assert.AreEqual(6, Area.Stop.Line);
  Assert.AreEqual(1, Area.Stop.Character);
  Assert.IsFalse(TAtlasSearchScopes.AreaFor(Text, TAtlasSearchScope.Selection, Cursor, Selection, 0, Area),
    'leere Auswahl');
  Selection := TAtlasSearchArea.Create(1, 0, 3, 2);
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(Text, TAtlasSearchScope.Selection, Cursor, Selection, 0, Area));
  Assert.AreEqual(3, Area.Stop.Line);
end;

procedure TAtlasSearchTests.WordAtAndHitCaption;
var
  Lines: TArray<string>;
begin
  Assert.AreEqual('Foo', TAtlasTextSearch.WordAt('  Foo := 1;', 3));
  Assert.AreEqual('Foo', TAtlasTextSearch.WordAt('  Foo := 1;', 5), 'direkt hinter dem Wort');
  Assert.AreEqual('', TAtlasTextSearch.WordAt('  Foo := 1;', 7));
  Assert.AreEqual('', TAtlasTextSearch.WordAt('', 0));
  Lines := ['x', #9'  Foo := 1;'#13];
  Assert.AreEqual('2: Foo := 1;', TAtlasTextSearch.HitCaption(Lines, TAtlasSearchHit.Create(1, 3, 3)));
end;

procedure TAtlasSearchTests.KeysComeFromSettingsAndFollowTheSwitch;
var
  Settings: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  Assert.AreEqual($4046, Integer(EntryOf(Entries, TAtlasKeyFunction.Search).Key), 'Strg+F');
  Assert.AreEqual($72, Integer(EntryOf(Entries, TAtlasKeyFunction.SearchNext).Key), 'F3');
  Assert.AreEqual($2072, Integer(EntryOf(Entries, TAtlasKeyFunction.SearchPrevious).Key), 'Umschalt+F3');
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.Search).Priority, 'bewusst übernommen');
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.Search).Disabled);
  Assert.AreEqual('Atlas.Search', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Search));
  Assert.AreEqual('Atlas.SearchNext', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SearchNext));
  Assert.AreEqual('Atlas.SearchPrevious', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SearchPrevious));
  Assert.AreEqual('Atlas.SearchInMethod', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SearchMethod));
  Assert.AreEqual(Ord(TAtlasKeyContext.Editor), Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.Search)));
  // Schalter aus: die IDE behält Strg+F und F3; „In Methode suchen“ bleibt.
  Settings.SearchReplaceIde := False;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.Search).Disabled);
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.SearchNext).Disabled);
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.SearchPrevious).Disabled);
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.SearchMethod).Disabled);
  // Zurück in die Einstellungen.
  Entries[High(Entries)].Key := $C046;
  TAtlasKeyEntry.ToSettings(Entries, Settings);
  Assert.AreEqual($C046, Settings.SearchMethodKey);
end;

procedure TAtlasSearchTests.SettingsDefaultsAndRoundTrip;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  // Entscheidung #878: Atlas ersetzt die IDE-Suche standardmäßig.
  Assert.IsTrue(Settings.SearchReplaceIde);
  Assert.AreEqual($4046, Settings.SearchKey);
  Assert.AreEqual($72, Settings.SearchNextKey);
  Assert.AreEqual($2072, Settings.SearchPreviousKey);
  Assert.AreEqual($E046, Settings.SearchMethodKey);
  Settings.SearchKey := -3;
  Settings.SearchMethodKey := $1FFFF;
  Settings.Normalize;
  Assert.AreEqual(0, Settings.SearchKey);
  Assert.AreEqual($FFFF, Settings.SearchMethodKey);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchTests);

end.
