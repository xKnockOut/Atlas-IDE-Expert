unit Atlas.Core.Search.Tests;

// Tests für die Atlas-Suche (#877, #878): Treffer mit Optionen, Bezeichner-Modus,
// Bereiche (Routine, Unit, Auswahl), Weitersuchen mit Umlauf, Tasten und Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
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
    procedure IndexAtFindsMarkedOrContainingHit;
    [Test]
    procedure EntriesCarryLineColumnAndText;
    [Test]
    procedure EntriesAreCapped;
    [Test]
    procedure RoutineNameFromHeader;
    [Test]
    procedure FollowSelectionTakesOtherMarkedText;
    [Test]
    procedure StartQuerySearchesTheUnitUnlessAskedForTheMethod;
    [Test]
    procedure KeysComeFromSettingsAndFollowTheSwitch;
    [Test]
    procedure SettingsDefaultsAndRoundTrip;
    /// <summary>#1227: Ein Buchstabe in einer großen Unit (80 000 Treffer) blockiert die Suchleiste nicht.</summary>
    [Test]
    [Category('Benchmark')]
    procedure ManyHitsStayFast;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Scopes,
  Atlas.Core.Search.Results,
  Atlas.Text.Lines,
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

function Find(const AText, ANeedle: string; ACase, AWhole, AIdent: Boolean): string;
var
  mLines: TArray<string>;
begin
  mLines := TTextLines.SplitLines(AText);
  Result := Describe(TAtlasTextSearch.FindAll(mLines, ANeedle, TAtlasSearchOptions.Create(ACase, AWhole, AIdent),
    TAtlasSearchArea.Whole(mLines)));
end;

function EntryOf(const AEntries: TArray<TAtlasKeyEntry>; AFunc: TAtlasKeyFunction): TAtlasKeyEntry;
var
  mEntry: TAtlasKeyEntry;
begin
  for mEntry in AEntries do
  begin
    if mEntry.Func = AFunc then
    begin
      Exit(mEntry);
    end;
  end;
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
  cText = 'A := 1;'#10'{ A'#10'  A }'#10'(* A'#10'A *) A'#10'S := '''''''#10'  A'#10'  '''''';'#10'A';
begin
  Assert.AreEqual('0:0+1 4:5+1 8:0+1', Find(cText, 'a', False, False, True));
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
  mLines: TArray<string>;
  mOptions: TAtlasSearchOptions;
begin
  mLines := TTextLines.SplitLines('a a'#10'a a'#10'a a');
  mOptions := TAtlasSearchOptions.Create(False, False, False);
  // Von Zeile 0, Zeichen 2 bis Zeile 1, Zeichen 1: nur die Treffer ganz darin.
  Assert.AreEqual('0:2+1 1:0+1', Describe(TAtlasTextSearch.FindAll(mLines, 'a', mOptions,
    TAtlasSearchArea.Create(0, 2, 1, 1))));
  mOptions.Identifier := True;
  Assert.AreEqual('0:2+1 1:0+1', Describe(TAtlasTextSearch.FindAll(mLines, 'a', mOptions,
    TAtlasSearchArea.Create(0, 2, 1, 1))));
  Assert.AreEqual('', Describe(TAtlasTextSearch.FindAll(mLines, 'a', mOptions, TAtlasSearchArea.Create(1, 1, 1, 1))),
    'leerer Bereich');
end;

procedure TAtlasSearchTests.NextWrapsForwardAndBackward;
var
  mHits: TArray<TAtlasSearchHit>;
  mWrapped: Boolean;
begin
  mHits := [TAtlasSearchHit.Create(1, 0, 3), TAtlasSearchHit.Create(3, 4, 3), TAtlasSearchHit.Create(5, 0, 3)];
  Assert.AreEqual(0, TAtlasTextSearch.Next(mHits, TAtlasSearchPos.Create(0, 0), False, mWrapped));
  Assert.IsFalse(mWrapped);
  // Ein Treffer am Cursor zählt vorwärts; nach dem Markieren steht der Cursor hinter ihm.
  Assert.AreEqual(1, TAtlasTextSearch.Next(mHits, TAtlasSearchPos.Create(3, 4), False, mWrapped));
  Assert.AreEqual(2, TAtlasTextSearch.Next(mHits, TAtlasSearchPos.Create(3, 7), False, mWrapped));
  Assert.AreEqual(0, TAtlasTextSearch.Next(mHits, TAtlasSearchPos.Create(5, 3), False, mWrapped));
  Assert.IsTrue(mWrapped, 'Umlauf vorwärts');
  Assert.AreEqual(0, TAtlasTextSearch.Next(mHits, TAtlasSearchPos.Create(3, 4), True, mWrapped));
  Assert.IsFalse(mWrapped);
  Assert.AreEqual(2, TAtlasTextSearch.Next(mHits, TAtlasSearchPos.Create(1, 0), True, mWrapped));
  Assert.IsTrue(mWrapped, 'Umlauf rückwärts');
  Assert.AreEqual(-1, TAtlasTextSearch.Next(nil, TAtlasSearchPos.Create(0, 0), False, mWrapped));
end;

procedure TAtlasSearchTests.RoutinesAtListInnermostFirstWithLocalDeclarations;
const
  cText = 'implementation'#10 + // 0
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
  mAround: TArray<TAtlasSearchRoutine>;
begin
  Assert.AreEqual(3, Integer(Length(TAtlasSearchScopes.Routines(cText))), 'Klassentyp ist keine Routine');
  mAround := TAtlasSearchScopes.RoutinesAt(cText, TAtlasSearchPos.Create(6, 5));
  Assert.AreEqual(2, Integer(Length(mAround)));
  Assert.AreEqual('procedure Inner;', mAround[0].Caption);
  Assert.AreEqual(4, mAround[0].Area.Start.Line);
  Assert.AreEqual(7, mAround[0].Area.Stop.Line);
  Assert.AreEqual('procedure TFoo.Outer;', mAround[1].Caption);
  Assert.AreEqual(1, mAround[1].Area.Start.Line);
  Assert.AreEqual(10, mAround[1].Area.Stop.Line);
  // Lokale Deklarationen gehören zur Routine.
  Assert.AreEqual(1, Integer(Length(TAtlasSearchScopes.RoutinesAt(cText, TAtlasSearchPos.Create(3, 3)))));
  mAround := TAtlasSearchScopes.RoutinesAt(cText, TAtlasSearchPos.Create(13, 0));
  Assert.AreEqual(1, Integer(Length(mAround)));
  Assert.AreEqual('class function TFoo.Make: TFoo;', mAround[0].Caption);
  Assert.AreEqual(0, Integer(Length(TAtlasSearchScopes.RoutinesAt(cText, TAtlasSearchPos.Create(0, 2)))));
end;

procedure TAtlasSearchTests.AreaForMethodUnitAndSelection;
const
  cText = 'procedure A;'#10'  procedure B;'#10'  begin'#10'  end;'#10'begin'#10'end;'#10'X';
var
  mArea, mSelection: TAtlasSearchArea;
  mCursor: TAtlasSearchPos;
begin
  mCursor := TAtlasSearchPos.Create(2, 3);
  mSelection := TAtlasSearchArea.Create(0, 0, 0, 0);
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(cText, TAtlasSearchScope.Method, mCursor, mSelection, 0, mArea));
  Assert.AreEqual(1, mArea.Start.Line, 'innerste');
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(cText, TAtlasSearchScope.Method, mCursor, mSelection, 1, mArea));
  Assert.AreEqual(0, mArea.Start.Line, 'äußere');
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(cText, TAtlasSearchScope.Method, mCursor, mSelection, 9, mArea));
  Assert.AreEqual(0, mArea.Start.Line, 'zu hohe Stufe bleibt bei der äußersten');
  Assert.IsFalse(TAtlasSearchScopes.AreaFor(cText, TAtlasSearchScope.Method, TAtlasSearchPos.Create(6, 0),
    mSelection, 0, mArea), 'außerhalb jeder Routine');
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(cText, TAtlasSearchScope.UnitFile, mCursor, mSelection, 0, mArea));
  Assert.AreEqual(6, mArea.Stop.Line);
  Assert.AreEqual(1, mArea.Stop.Character);
  Assert.IsFalse(TAtlasSearchScopes.AreaFor(cText, TAtlasSearchScope.Selection, mCursor, mSelection, 0, mArea),
    'leere Auswahl');
  mSelection := TAtlasSearchArea.Create(1, 0, 3, 2);
  Assert.IsTrue(TAtlasSearchScopes.AreaFor(cText, TAtlasSearchScope.Selection, mCursor, mSelection, 0, mArea));
  Assert.AreEqual(3, mArea.Stop.Line);
end;

procedure TAtlasSearchTests.WordAtAndHitCaption;
var
  mLines: TArray<string>;
begin
  Assert.AreEqual('Foo', TAtlasTextSearch.WordAt('  Foo := 1;', 3));
  Assert.AreEqual('Foo', TAtlasTextSearch.WordAt('  Foo := 1;', 5), 'direkt hinter dem Wort');
  Assert.AreEqual('', TAtlasTextSearch.WordAt('  Foo := 1;', 7));
  Assert.AreEqual('', TAtlasTextSearch.WordAt('', 0));
  mLines := ['x', #9'  Foo := 1;'#13];
  Assert.AreEqual('2: Foo := 1;', TAtlasTextSearch.HitCaption(mLines, TAtlasSearchHit.Create(1, 3, 3)));
  Assert.AreEqual('Foo := 1;', TAtlasTextSearch.HitText(mLines, TAtlasSearchHit.Create(1, 3, 3)));
end;

procedure TAtlasSearchTests.IndexAtFindsMarkedOrContainingHit;
var
  mHits: TArray<TAtlasSearchHit>;
begin
  // Open in Zeile 0 ab 2 und 10, Zeile 3 ab 0.
  mHits := [TAtlasSearchHit.Create(0, 2, 4), TAtlasSearchHit.Create(0, 10, 4), TAtlasSearchHit.Create(3, 0, 4)];
  Assert.AreEqual(1, TAtlasSearchResults.IndexAt(mHits, TAtlasSearchPos.Create(0, 10)), 'Anfang der Markierung');
  Assert.AreEqual(0, TAtlasSearchResults.IndexAt(mHits, TAtlasSearchPos.Create(0, 4)), 'Cursor im Treffer');
  Assert.AreEqual(0, TAtlasSearchResults.IndexAt(mHits, TAtlasSearchPos.Create(0, 6)), 'Cursor direkt dahinter');
  Assert.AreEqual(-1, TAtlasSearchResults.IndexAt(mHits, TAtlasSearchPos.Create(0, 7)), 'zwischen zwei Treffern');
  Assert.AreEqual(2, TAtlasSearchResults.IndexAt(mHits, TAtlasSearchPos.Create(3, 0)));
  Assert.AreEqual(-1, TAtlasSearchResults.IndexAt(nil, TAtlasSearchPos.Create(0, 0)));
end;

procedure TAtlasSearchTests.EntriesCarryLineColumnAndText;
var
  mLines: TArray<string>;
  mHits: TArray<TAtlasSearchHit>;
  mEntries: TArray<TAtlasSearchEntry>;
begin
  mLines := TTextLines.SplitLines('unit A;'#13#10#9'Open := 1;'#13#10'  if Open > 0 then'#13#10);
  mHits := TAtlasTextSearch.FindAll(mLines, 'Open', TAtlasSearchOptions.Create(False, True, False),
    TAtlasSearchArea.Whole(mLines));
  mEntries := TAtlasSearchResults.Entries(mLines, mHits, 4);
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.AreEqual(2, mEntries[0].Line);
  Assert.AreEqual(5, mEntries[0].Column, 'Tab bis Spalte 5 aufgelöst');
  Assert.AreEqual('Open := 1;', mEntries[0].Text);
  Assert.AreEqual(3, mEntries[1].Line);
  Assert.AreEqual(6, mEntries[1].Column);
  Assert.AreEqual('if Open > 0 then', mEntries[1].Text);
end;

procedure TAtlasSearchTests.EntriesAreCapped;
var
  mLines: TArray<string>;
  mHits: TArray<TAtlasSearchHit>;
  mIndex: Integer;
begin
  mLines := ['x'];
  SetLength(mHits, TAtlasSearchResults.cMaxEntries + 5);
  for mIndex := 0 to High(mHits) do
  begin
    mHits[mIndex] := TAtlasSearchHit.Create(0, 0, 1);
  end;
  Assert.AreEqual(TAtlasSearchResults.cMaxEntries, Integer(Length(TAtlasSearchResults.Entries(mLines, mHits, 2))));
end;

procedure TAtlasSearchTests.RoutineNameFromHeader;
begin
  Assert.AreEqual('ReadLocation', TAtlasSearchResults.RoutineName(
    'function ReadLocation(const AText: string; out AFileName: string): Boolean;'));
  Assert.AreEqual('TFoo.Bar', TAtlasSearchResults.RoutineName('class procedure TFoo.Bar;'));
  Assert.AreEqual('TList<T>.Add', TAtlasSearchResults.RoutineName('function TList<T>.Add(const A: T): Integer;'));
  Assert.AreEqual('TFoo.Create', TAtlasSearchResults.RoutineName('constructor TFoo.Create(AOwner: TComponent);'));
  Assert.AreEqual('Inner', TAtlasSearchResults.RoutineName('  procedure Inner'));
  Assert.AreEqual('begin', TAtlasSearchResults.RoutineName('begin'), 'ohne Namen bleibt die Zeile');
end;

procedure TAtlasSearchTests.FollowSelectionTakesOtherMarkedText;
var
  mLast, mQuery: TAtlasSearchQuery;
  mChanged: Boolean;
begin
  mLast := Default(TAtlasSearchQuery);
  mLast.Text := 'Open';
  mLast.Options := TAtlasSearchOptions.Create(False, True, True);
  mLast.Scope := TAtlasSearchScope.Method;
  mLast.Area := TAtlasSearchArea.Create(1, 0, 4, 0);
  // Markierung auf einem Treffer der letzten Suche: weitersuchen.
  mQuery := TAtlasSearchResults.FollowSelection(mLast, 'open', mChanged);
  Assert.IsFalse(mChanged, 'Bezeichner-Modus ohne Groß-/Kleinschreibung');
  Assert.AreEqual('Open', mQuery.Text);
  Assert.AreEqual(1, mQuery.Area.Start.Line, 'Bereich bleibt');
  // Anderer Bezeichner, etwa außerhalb jeder Methode markiert.
  mQuery := TAtlasSearchResults.FollowSelection(mLast, 'TFormMain', mChanged);
  Assert.IsTrue(mChanged);
  Assert.AreEqual('TFormMain', mQuery.Text);
  Assert.AreEqual(Ord(TAtlasSearchScope.Method), Ord(mQuery.Scope), 'Bereich wählt TryNext');
  Assert.IsTrue(mQuery.Area.IsEmpty, 'kein gemerkter Bereich');
  Assert.IsTrue(mQuery.Options.Identifier);
  Assert.IsTrue(mQuery.Options.WholeWord);
  // Kein Bezeichner: Textsuche; Bereich Auswahl wird Unit.
  mLast.Scope := TAtlasSearchScope.Selection;
  mQuery := TAtlasSearchResults.FollowSelection(mLast, 'Self.Close', mChanged);
  Assert.IsTrue(mChanged);
  Assert.IsFalse(mQuery.Options.Identifier);
  Assert.AreEqual(Ord(TAtlasSearchScope.UnitFile), Ord(mQuery.Scope));
  // Groß-/Kleinschreibung zählt nur in der Textsuche mit Groß/klein.
  mLast.Options := TAtlasSearchOptions.Create(True, False, False);
  TAtlasSearchResults.FollowSelection(mLast, 'open', mChanged);
  Assert.IsTrue(mChanged);
  // Leer oder mehrzeilig: nichts.
  TAtlasSearchResults.FollowSelection(mLast, '', mChanged);
  Assert.IsFalse(mChanged);
  mQuery := TAtlasSearchResults.FollowSelection(mLast, 'a'#13#10'b', mChanged);
  Assert.IsFalse(mChanged);
  Assert.AreEqual('Open', mQuery.Text);
end;

procedure TAtlasSearchTests.StartQuerySearchesTheUnitUnlessAskedForTheMethod;
var
  mLast, mQuery: TAtlasSearchQuery;
begin
  Assert.AreEqual(Ord(TAtlasSearchScope.UnitFile), Ord(Default(TAtlasSearchQuery).Scope), 'Vorgabe Unit');
  // Zuletzt gezielt in der zweiten Routine gesucht: Die nächste Suche beginnt trotzdem in der Unit.
  mLast := Default(TAtlasSearchQuery);
  mLast.Text := 'Open';
  mLast.Options := TAtlasSearchOptions.Create(True, True, False);
  mLast.Scope := TAtlasSearchScope.Method;
  mLast.Level := 1;
  mLast.Area := TAtlasSearchArea.Create(2, 0, 9, 0);
  mQuery := TAtlasSearchResults.StartQuery(mLast, 'Close', False, False);
  Assert.AreEqual('Close', mQuery.Text);
  Assert.AreEqual(Ord(TAtlasSearchScope.UnitFile), Ord(mQuery.Scope));
  Assert.AreEqual(0, mQuery.Level);
  Assert.IsTrue(mQuery.Area.IsEmpty);
  Assert.IsTrue(mQuery.Options.CaseSensitive, 'Optionen bleiben');
  Assert.IsTrue(mQuery.Options.WholeWord);
  // Mehrzeilige Markierung: Auswahl; „In Methode suchen“: Methode, innerste Routine.
  Assert.AreEqual(Ord(TAtlasSearchScope.Selection), Ord(TAtlasSearchResults.StartQuery(mLast, 'x', True, False).Scope));
  mQuery := TAtlasSearchResults.StartQuery(mLast, 'x', True, True);
  Assert.AreEqual(Ord(TAtlasSearchScope.Method), Ord(mQuery.Scope));
  Assert.AreEqual(0, mQuery.Level);
end;

procedure TAtlasSearchTests.KeysComeFromSettingsAndFollowTheSwitch;
var
  mSettings: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
  I: Integer;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  Assert.AreEqual($4046, Integer(EntryOf(mEntries, TAtlasKeyFunction.Search).Key), 'Strg+F');
  Assert.AreEqual($72, Integer(EntryOf(mEntries, TAtlasKeyFunction.SearchNext).Key), 'F3');
  Assert.AreEqual($2072, Integer(EntryOf(mEntries, TAtlasKeyFunction.SearchPrevious).Key), 'Umschalt+F3');
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.Search).Priority, 'bewusst übernommen');
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.Search).Disabled);
  Assert.AreEqual('Atlas.Search', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Search));
  Assert.AreEqual('Atlas.SearchNext', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SearchNext));
  Assert.AreEqual('Atlas.SearchPrevious', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SearchPrevious));
  Assert.AreEqual('Atlas.SearchInMethod', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SearchMethod));
  Assert.AreEqual(Ord(TAtlasKeyContext.Editor), Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.Search)));
  // Schalter aus: die IDE behält Strg+F und F3; „In Methode suchen“ bleibt.
  mSettings.SearchReplaceIde := False;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.Search).Disabled);
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.SearchNext).Disabled);
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.SearchPrevious).Disabled);
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.SearchMethod).Disabled);
  // Zurück in die Einstellungen.
  // Eintrag gezielt suchen: seit FormatCode (#43) ist SearchMethod nicht mehr der letzte.
  for I := 0 to High(mEntries) do
  begin
    if mEntries[I].Func = TAtlasKeyFunction.SearchMethod then
    begin
      mEntries[I].Key := $C046;
    end;
  end;
  TAtlasKeyEntry.ToSettings(mEntries, mSettings);
  Assert.AreEqual($C046, mSettings.SearchMethodKey);
end;

procedure TAtlasSearchTests.SettingsDefaultsAndRoundTrip;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  // Entscheidung #878: Atlas ersetzt die IDE-Suche standardmäßig.
  Assert.IsTrue(mSettings.SearchReplaceIde);
  Assert.IsTrue(mSettings.SearchResultsInMessages, 'Liste in den Meldungen standardmäßig an');
  Assert.IsFalse(mSettings.SearchFromFirstHit, '#1242: Vorgabe ab Cursor');
  Assert.AreEqual($4046, mSettings.SearchKey);
  Assert.AreEqual($72, mSettings.SearchNextKey);
  Assert.AreEqual($2072, mSettings.SearchPreviousKey);
  Assert.AreEqual($E046, mSettings.SearchMethodKey);
  mSettings.SearchKey := -3;
  mSettings.SearchMethodKey := $1FFFF;
  mSettings.Normalize;
  Assert.AreEqual(0, mSettings.SearchKey);
  Assert.AreEqual($FFFF, mSettings.SearchMethodKey);
end;

procedure TAtlasSearchTests.ManyHitsStayFast;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mWatch: TStopwatch;
  mHits: TArray<TAtlasSearchHit>;
begin
  SetLength(mLines, 20000);
  for mIndex := 0 to High(mLines) do
  begin
    mLines[mIndex] := '  Ergebnis := Wert + Eintrag;';
  end;
  mWatch := TStopwatch.StartNew;
  mHits := TAtlasTextSearch.FindAll(mLines, 'e', TAtlasSearchOptions.Create(False, False, False),
    TAtlasSearchArea.Whole(mLines));
  mWatch.Stop;
  // „Ergebnis“ (2), „Wert“, „Eintrag“: vier e je Zeile, Groß-/Kleinschreibung egal.
  Assert.AreEqual(80000, Integer(Length(mHits)));
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 500, 'Dauer ' + IntToStr(mWatch.ElapsedMilliseconds) + ' ms');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchTests);

end.
