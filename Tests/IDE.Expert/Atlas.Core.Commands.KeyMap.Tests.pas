unit Atlas.Core.Commands.KeyMap.Tests;

// Tests für die Tastenkürzel-Übersicht (#520): alle Atlas-Tasten, Suche nach
// Taste und Text, Konflikte und Gewinner, Herkunft nach Modul und HTML-Export.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasKeyMapTests = class
  public
    [Test]
    procedure AllFromSettingsListsEveryAtlasKey;
    [Test]
    procedure AllFromSettingsRoundTripsEditorKeys;
    [Test]
    procedure ParsesGermanAndEnglishShortCuts;
    [Test]
    procedure QueryMatchesKeyModifiersAndText;
    [Test]
    procedure CollideNeedsSameKeyOverlapAndOtherOwner;
    [Test]
    procedure AtlasYieldsToIdeBinding;
    [Test]
    procedure AtlasWithPriorityWins;
    [Test]
    procedure EditorBindingBeatsAction;
    [Test]
    procedure FirstActionWinsAmongActions;
    [Test]
    procedure DoubledAtlasKeyIsConflict;
    [Test]
    procedure WelcomeSearchWinsOnlyOnWelcomePage;
    [Test]
    procedure EffectivePluginBindingWins;
    [Test]
    procedure FilterSortsAndKeepsConflicts;
    [Test]
    procedure OriginFollowsModule;
    [Test]
    procedure ContextFollowsCategory;
    [Test]
    procedure CommandIdsMatchPalette;
    [Test]
    procedure HtmlIsEscapedAndMarksConflicts;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap;

const
  CtrlShiftP = $6050;
  CtrlW = $4057;
  CtrlE = $4045;

function AtlasKey(AFunc: TAtlasKeyFunction; AKey: Word; APriority, AActive: Boolean): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, 'Taste', 'Atlas ' + IntToStr(Ord(AFunc)), TAtlasKeyOrigin.Atlas,
    TAtlasKeyMap.AtlasName, TAtlasKeyMap.ContextOf(AFunc), TAtlasKeyMap.SourceOf(AFunc),
    'Atlas.Key.' + IntToStr(Ord(AFunc)), Ord(AFunc));
  Result.Func := AFunc;
  Result.Priority := APriority;
  Result.Active := AActive;
end;

function IdeAction(const AName: string; AKey: Word; AOrder: Integer): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, 'Taste', AName, TAtlasKeyOrigin.Ide, TAtlasKeyMap.IdeName,
    TAtlasKeyContext.Global, TAtlasKeySource.Action, AName, AOrder);
end;

function IdeBinding(const AName: string; AKey: Word): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, 'Taste', AName, TAtlasKeyOrigin.Ide, TAtlasKeyMap.IdeName,
    TAtlasKeyContext.Editor, TAtlasKeySource.Binding, 'Editor.' + IntToStr(AKey), 0);
end;

procedure TAtlasKeyMapTests.AllFromSettingsListsEveryAtlasKey;
var
  Settings: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
  Entry: TAtlasKeyEntry;
  Func: TAtlasKeyFunction;
  Found: Boolean;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.EditorKeysPriority := True;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  // Jede Funktion genau einmal, die ersten sechs wie auf der Seite „Tastenkonflikte“.
  Assert.AreEqual(Ord(High(TAtlasKeyFunction)) + 1, Integer(Length(Entries)));
  for Func := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
  begin
    Found := False;
    for Entry in Entries do
      if Entry.Func = Func then
        Found := True;
    Assert.IsTrue(Found, 'Funktion ' + IntToStr(Ord(Func)));
  end;
  Assert.AreEqual(Ord(TAtlasKeyFunction.DiagnosticMode), Ord(Entries[5].Func));
  Assert.AreEqual($800D, Integer(Entries[6].Key), 'Code-Aktionen: Alt+Enter');
  Assert.IsTrue(Entries[6].Priority, 'Editorbefehle: gemeinsamer Vorrang');
  Assert.AreEqual(CtrlE, Integer(Entries[13].Key), 'Suchfeld der Willkommensseite: Strg+E');
  Assert.IsTrue(Entries[13].Priority, 'Das Suchfeld nimmt die Taste auf der Willkommensseite immer');
  Assert.AreEqual(CtrlShiftP, Integer(Entries[0].Key), 'Befehlspalette #502');
end;

procedure TAtlasKeyMapTests.AllFromSettingsRoundTripsEditorKeys;
var
  Settings, Saved: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.ExpandKey := $6045;
  Settings.RedoKey := 0;
  Settings.WelcomePageSearchKey := $4046;
  Settings.EditorKeysPriority := True;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  Saved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(Entries, Saved);
  Assert.AreEqual($6045, Saved.ExpandKey);
  Assert.AreEqual(0, Saved.RedoKey);
  Assert.AreEqual($4046, Saved.WelcomePageSearchKey);
  Assert.IsTrue(Saved.EditorKeysPriority);
  Assert.AreEqual(Settings.UndoKey, Saved.UndoKey);
end;

procedure TAtlasKeyMapTests.ParsesGermanAndEnglishShortCuts;
var
  Modifiers: Word;
begin
  Assert.AreEqual(CtrlShiftP, Integer(TAtlasKeyMap.ParseShortCut('Strg+Umschalt+P', Modifiers)));
  Assert.AreEqual(CtrlShiftP, Integer(TAtlasKeyMap.ParseShortCut(' ctrl + shift + p ', Modifiers)));
  Assert.AreEqual($800D, Integer(TAtlasKeyMap.ParseShortCut('Alt+Enter', Modifiers)));
  Assert.AreEqual($4020, Integer(TAtlasKeyMap.ParseShortCut('Strg+Leer', Modifiers)));
  Assert.AreEqual($C078, Integer(TAtlasKeyMap.ParseShortCut('Strg+Alt+F9', Modifiers)));
  Assert.AreEqual($74, Integer(TAtlasKeyMap.ParseShortCut('F5', Modifiers)), 'Funktionstaste allein');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('p', Modifiers)), 'ein Zeichen ist Textsuche');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('Strg+Alt', Modifiers)));
  Assert.AreEqual(TAtlasKeyMap.scCtrl or TAtlasKeyMap.scAlt, Integer(Modifiers), 'nur Umschalttasten');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('Strg+', Modifiers)));
  Assert.AreEqual(TAtlasKeyMap.scCtrl, Integer(Modifiers));
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('Strg+Kompilieren', Modifiers)));
  Assert.AreEqual(0, Integer(Modifiers), 'kein Tastenname: Textsuche');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('P+Strg', Modifiers)), 'Taste nur am Ende');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('', Modifiers)));
end;

procedure TAtlasKeyMapTests.QueryMatchesKeyModifiersAndText;
var
  Item: TAtlasKeyItem;
begin
  Item := IdeAction('Projekt compilieren', $4078, 1);
  Item.KeyText := 'Strg+F9';
  Item.Category := 'Projekt';
  Assert.IsTrue(TAtlasKeyQuery.Parse('').Matches(Item));
  Assert.IsTrue(TAtlasKeyQuery.Parse('Ctrl+F9').Matches(Item), 'englische Taste');
  Assert.IsFalse(TAtlasKeyQuery.Parse('Strg+Umschalt+F9').Matches(Item));
  Assert.IsTrue(TAtlasKeyQuery.Parse('Strg').Matches(Item), 'nur Umschalttaste');
  Assert.IsFalse(TAtlasKeyQuery.Parse('Alt+').Matches(Item));
  Assert.IsTrue(TAtlasKeyQuery.Parse('compil').Matches(Item), 'Befehl');
  Assert.IsTrue(TAtlasKeyQuery.Parse('PROJEKT').Matches(Item), 'Kategorie, Großschreibung egal');
  Assert.IsTrue(TAtlasKeyQuery.Parse('ide').Matches(Item), 'Herkunft');
  Assert.IsFalse(TAtlasKeyQuery.Parse('formular').Matches(Item));
end;

procedure TAtlasKeyMapTests.CollideNeedsSameKeyOverlapAndOtherOwner;
var
  A, B: TAtlasKeyItem;
begin
  A := IdeAction('Kopieren', $4043, 1);
  B := IdeBinding('Kopieren im Editor', $4043);
  Assert.IsFalse(TAtlasKeyMap.Collide(A, B), 'innerhalb der IDE kein Konflikt');
  B := AtlasKey(TAtlasKeyFunction.ExpandSelection, $4043, False, True);
  Assert.IsTrue(TAtlasKeyMap.Collide(A, B), 'global überschneidet sich mit dem Editor');
  B.ShortCut := $4044;
  Assert.IsFalse(TAtlasKeyMap.Collide(A, B), 'andere Taste');
  A := AtlasKey(TAtlasKeyFunction.WelcomeSearch, $4044, True, True);
  Assert.IsFalse(TAtlasKeyMap.Collide(A, B), 'Willkommensseite und Editor überschneiden sich nicht');
  A := TAtlasKeyItem.Create($4044, 'Taste', 'X', TAtlasKeyOrigin.Plugin, 'CnWizards', TAtlasKeyContext.Editor,
    TAtlasKeySource.Binding, 'x', 1);
  B := A;
  B.Id := 'y';
  Assert.IsFalse(TAtlasKeyMap.Collide(A, B), 'dieselbe Erweiterung');
  B.OriginName := 'GExperts';
  Assert.IsTrue(TAtlasKeyMap.Collide(A, B), 'zwei Erweiterungen');
  Assert.IsTrue(TAtlasKeyMap.Overlaps(TAtlasKeyContext.Global, TAtlasKeyContext.Designer));
  Assert.IsFalse(TAtlasKeyMap.Overlaps(TAtlasKeyContext.Editor, TAtlasKeyContext.Designer));
end;

procedure TAtlasKeyMapTests.AtlasYieldsToIdeBinding;
var
  Items: TArray<TAtlasKeyItem>;
  Conflicts: TArray<Integer>;
begin
  // Strg+Umschalt+P: Befehlspalette ohne Vorrang gegen „Tastaturmakro abspielen“ (#494).
  Items := [AtlasKey(TAtlasKeyFunction.Palette, CtrlShiftP, False, False), IdeBinding('Makro abspielen', CtrlShiftP),
    IdeAction('Speichern', $4053, 1)];
  Items[1].Effective := True;
  TAtlasKeyMap.Analyze(Items);
  Assert.IsTrue(Items[0].Conflict);
  Assert.IsTrue(Items[1].Conflict);
  Assert.IsFalse(Items[2].Conflict);
  Assert.IsTrue(Items[2].Wins, 'ohne Konflikt gewinnt die Belegung selbst');
  Assert.AreEqual(1, Items[0].Winner);
  Assert.IsFalse(Items[0].Wins);
  Assert.IsTrue(Items[1].Wins);
  Assert.AreEqual(Ord(TAtlasKeyReason.AtlasYields), Ord(Items[0].Reason));
  Assert.AreEqual(1, TAtlasKeyMap.PartnerOf(Items, 0));
  Assert.AreEqual(-1, TAtlasKeyMap.PartnerOf(Items, 2));
  Assert.AreEqual(2, TAtlasKeyMap.ConflictCount(Items));
  Conflicts := TAtlasKeyMap.AtlasConflicts(Items);
  Assert.AreEqual(1, Integer(Length(Conflicts)));
  Assert.AreEqual(0, Conflicts[0]);
  Assert.AreEqual('Makro abspielen (IDE)', Items[1].Holder);
end;

procedure TAtlasKeyMapTests.AtlasWithPriorityWins;
var
  Items: TArray<TAtlasKeyItem>;
begin
  Items := [AtlasKey(TAtlasKeyFunction.Palette, CtrlShiftP, True, True), IdeBinding('Makro abspielen', CtrlShiftP)];
  Items[0].Effective := True;
  TAtlasKeyMap.Analyze(Items);
  Assert.IsTrue(Items[0].Wins);
  Assert.AreEqual(0, Items[1].Winner);
  Assert.AreEqual(Ord(TAtlasKeyReason.AtlasPriority), Ord(Items[1].Reason));
  Assert.AreEqual(0, Integer(Length(TAtlasKeyMap.AtlasConflicts(Items))), 'bewusst entschieden: nichts zu melden');
  // Ohne Abfrage der IDE entscheidet der Vorrang ebenso.
  Items[0].Effective := False;
  TAtlasKeyMap.Analyze(Items);
  Assert.IsTrue(Items[0].Wins);
end;

procedure TAtlasKeyMapTests.EditorBindingBeatsAction;
var
  Items: TArray<TAtlasKeyItem>;
begin
  // Die Aktion kam nach dem Belegen dazu: Atlas hält die Taste im Editor ohne Vorrang.
  Items := [IdeAction('Suchen', CtrlW, 3), AtlasKey(TAtlasKeyFunction.ExpandSelection, CtrlW, False, True)];
  Items[1].Effective := True;
  TAtlasKeyMap.Analyze(Items);
  Assert.AreEqual(1, Items[0].Winner, 'im Editor die Tastaturbelegung');
  Assert.AreEqual(Ord(TAtlasKeyReason.EditorBinding), Ord(Items[0].Reason));
  Assert.IsTrue(Items[1].Wins);
  Assert.AreEqual(1, Integer(Length(TAtlasKeyMap.AtlasConflicts(Items))), 'ohne Vorrang offen');
end;

procedure TAtlasKeyMapTests.FirstActionWinsAmongActions;
var
  Items: TArray<TAtlasKeyItem>;
begin
  Items := [IdeAction('Neu', $404E, 7), TAtlasKeyItem.Create($404E, 'Taste', 'Fremd',
    TAtlasKeyOrigin.Plugin, 'GExperts', TAtlasKeyContext.Global, TAtlasKeySource.Action, 'GxNew', 3),
    IdeAction('Neu 2', $404E, 9)];
  TAtlasKeyMap.Analyze(Items);
  Assert.IsTrue(Items[0].Conflict);
  Assert.AreEqual(1, Items[0].Winner, 'erste Aktion der Liste');
  Assert.AreEqual(Ord(TAtlasKeyReason.FirstAction), Ord(Items[0].Reason));
  Assert.IsTrue(Items[1].Wins);
  Assert.AreEqual(0, Integer(Length(TAtlasKeyMap.AtlasConflicts(Items))));
end;

procedure TAtlasKeyMapTests.DoubledAtlasKeyIsConflict;
var
  Items: TArray<TAtlasKeyItem>;
begin
  // Absichtlich doppelt belegt: Befehlspalette auf Strg+W wie „Auswahl erweitern“.
  Items := [AtlasKey(TAtlasKeyFunction.Palette, CtrlW, False, True),
    AtlasKey(TAtlasKeyFunction.ExpandSelection, CtrlW, False, True)];
  TAtlasKeyMap.Analyze(Items);
  Assert.IsTrue(Items[0].Conflict, 'rot');
  Assert.IsTrue(Items[1].Conflict, 'rot');
  Assert.AreEqual(Items[0].Winner, Items[1].Winner, 'ein Gewinner für beide');
  Assert.AreEqual(Ord(TAtlasKeyReason.LastBinding), Ord(Items[0].Reason));
  Assert.AreEqual(2, Integer(Length(TAtlasKeyMap.AtlasConflicts(Items))));
end;

procedure TAtlasKeyMapTests.WelcomeSearchWinsOnlyOnWelcomePage;
var
  Items: TArray<TAtlasKeyItem>;
begin
  Items := [IdeAction('Inkrementelle Suche', CtrlE, 1), AtlasKey(TAtlasKeyFunction.WelcomeSearch, CtrlE, True, True),
    IdeBinding('Editor-Suche', CtrlE)];
  TAtlasKeyMap.Analyze(Items);
  Assert.IsTrue(Items[1].Wins);
  Assert.AreEqual(Ord(TAtlasKeyReason.OwnWindow), Ord(Items[1].Reason));
  Assert.AreEqual(1, Items[0].Winner, 'die Aktion verliert dort, wo sich beide treffen');
  Assert.IsFalse(Items[2].Conflict, 'Editor und Willkommensseite überschneiden sich nicht');
  Assert.AreEqual(0, Integer(Length(TAtlasKeyMap.AtlasConflicts(Items))));
end;

procedure TAtlasKeyMapTests.EffectivePluginBindingWins;
var
  Items: TArray<TAtlasKeyItem>;
begin
  // Eine Erweiterung hat sich nach Atlas angemeldet: Ihre Belegung ist wirksam, auch gegen den Vorrang.
  Items := [AtlasKey(TAtlasKeyFunction.ShrinkSelection, $6057, True, True), TAtlasKeyItem.Create($6057, 'Taste',
    'Tastaturbelegung', TAtlasKeyOrigin.Plugin, 'CnWizards_D120', TAtlasKeyContext.Editor, TAtlasKeySource.Binding,
    'Editor.24663', 101)];
  Items[1].Effective := True;
  TAtlasKeyMap.Analyze(Items);
  Assert.AreEqual(1, Items[0].Winner);
  Assert.AreEqual(Ord(TAtlasKeyReason.LastBinding), Ord(Items[0].Reason));
  Assert.AreEqual(1, Integer(Length(TAtlasKeyMap.AtlasConflicts(Items))), 'Vorrang ohne Wirkung bleibt offen');
end;

procedure TAtlasKeyMapTests.FilterSortsAndKeepsConflicts;
var
  Items: TArray<TAtlasKeyItem>;
  Shown: TArray<Integer>;
begin
  Items := [IdeAction('Zeta', $4058, 1), IdeAction('Alpha', $4041, 2),
    AtlasKey(TAtlasKeyFunction.Palette, CtrlShiftP, False, False), IdeBinding('Makro', CtrlShiftP)];
  Items[0].KeyText := 'Strg+X';
  Items[1].KeyText := 'Strg+A';
  Items[2].KeyText := 'Strg+Umschalt+P';
  Items[3].KeyText := 'Strg+Umschalt+P';
  TAtlasKeyMap.Analyze(Items);
  Shown := TAtlasKeyMap.Filter(Items, '', False);
  Assert.AreEqual(4, Integer(Length(Shown)));
  Assert.AreEqual(1, Shown[0], 'nach Tastentext');
  Assert.AreEqual(0, Shown[3]);
  Shown := TAtlasKeyMap.Filter(Items, '', True);
  Assert.AreEqual(2, Integer(Length(Shown)), 'nur Konflikte');
  Assert.AreEqual(2, Shown[0], 'Atlas vor Makro (Befehl)');
  Shown := TAtlasKeyMap.Filter(Items, 'Strg+Umschalt+P', False);
  Assert.AreEqual(2, Integer(Length(Shown)));
  Shown := TAtlasKeyMap.Filter(Items, 'alpha', False);
  Assert.AreEqual(1, Integer(Length(Shown)));
  Assert.AreEqual(1, Shown[0]);
end;

procedure TAtlasKeyMapTests.OriginFollowsModule;
var
  Name: string;
begin
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Atlas), Ord(TAtlasKeyMap.OriginOfModule('C:\Atlas\Atlas.IDE.Expert.bpl',
    'C:\Studio\37.0\bin\', 'C:\Atlas\Atlas.IDE.Expert.bpl', Name)));
  Assert.AreEqual('Atlas', Name);
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Ide), Ord(TAtlasKeyMap.OriginOfModule('C:\Studio\37.0\bin\coreide370.bpl',
    'C:\Studio\37.0\bin\', 'C:\Atlas\Atlas.IDE.Expert.bpl', Name)));
  Assert.AreEqual('IDE', Name);
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Ide), Ord(TAtlasKeyMap.OriginOfModule('c:\studio\37.0\BIN\x.bpl',
    'C:\Studio\37.0\bin\', '', Name)), 'Groß-/Kleinschreibung egal');
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Plugin), Ord(TAtlasKeyMap.OriginOfModule(
    'C:\Users\Marco\Documents\Bpl\CnWizards_D120.dll', 'C:\Studio\37.0\bin\', 'C:\Atlas\Atlas.IDE.Expert.bpl',
    Name)));
  Assert.AreEqual('CnWizards_D120', Name, 'ohne Pfad und Benutzernamen');
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Ide), Ord(TAtlasKeyMap.OriginOfModule('', 'C:\Studio\37.0\bin\', '', Name)),
    'unbekanntes Modul');
end;

procedure TAtlasKeyMapTests.ContextFollowsCategory;
begin
  Assert.AreEqual(Ord(TAtlasKeyContext.Global), Ord(TAtlasKeyMap.ContextOfCategory('Project')));
  Assert.AreEqual(Ord(TAtlasKeyContext.Designer), Ord(TAtlasKeyMap.ContextOfCategory('Form Designer')));
  Assert.AreEqual(Ord(TAtlasKeyContext.Designer), Ord(TAtlasKeyMap.ContextOfCategory('Formular')));
  Assert.AreEqual(Ord(TAtlasKeyContext.Editor), Ord(TAtlasKeyMap.ContextOfCategory('Code Editor')));
  Assert.AreEqual(Ord(TAtlasKeyContext.Editor), Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.Palette)));
  Assert.AreEqual(Ord(TAtlasKeyContext.WelcomePage), Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.WelcomeSearch)));
  Assert.AreEqual(Ord(TAtlasKeySource.Window), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.WelcomeSearch)));
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.UndoChange)));
end;

procedure TAtlasKeyMapTests.CommandIdsMatchPalette;
begin
  Assert.AreEqual('Atlas.CodeActions', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.CodeActions));
  Assert.AreEqual('Atlas.Implementations', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.GoToImplementation));
  Assert.AreEqual('Atlas.UndoChange', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.UndoChange));
  Assert.AreEqual('Atlas.CheckNow', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Check));
  Assert.AreEqual('', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Palette), 'die Palette selbst ist kein Befehl');
end;

procedure TAtlasKeyMapTests.HtmlIsEscapedAndMarksConflicts;
var
  Html: string;
begin
  Html := TAtlasKeyMap.Html('de', 'Atlas - Tastenkuerzel', 'Stand: heute', 'Drucken', ['Taste', 'Befehl'],
    [TAtlasKeyHtmlRow.Create(['Strg+<P>', 'Suchen & Ersetzen'], True),
    TAtlasKeyHtmlRow.Create(['Strg+S', 'Speichern "alles"'], False)]);
  Assert.StartsWith('<!DOCTYPE html>', Html);
  Assert.Contains(Html, '<html lang="de">');
  Assert.Contains(Html, '<meta charset="utf-8">');
  Assert.Contains(Html, '<title>Atlas - Tastenkuerzel</title>');
  Assert.Contains(Html, '<p class="sub">Stand: heute</p>');
  Assert.Contains(Html, 'window.print()');
  Assert.Contains(Html, '@media print');
  Assert.Contains(Html, '<th>Taste</th><th>Befehl</th>');
  Assert.Contains(Html, '<tr class="conflict"><td class="key">Strg+&lt;P&gt;</td><td>Suchen &amp; Ersetzen</td></tr>');
  Assert.Contains(Html, '<tr><td class="key">Strg+S</td><td>Speichern &quot;alles&quot;</td></tr>');
  Assert.Contains(Html, 'tr.conflict td{color:#cf222e}');
  Assert.AreEqual('a&#39;b', TAtlasKeyMap.HtmlEscape('a''b'));
  // Ohne Unterzeile und Druckknopf.
  Html := TAtlasKeyMap.Html('en', 'T', '', '', ['K'], nil);
  Assert.DoesNotContain(Html, 'class="sub"');
  Assert.DoesNotContain(Html, 'window.print()');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyMapTests);

end.
