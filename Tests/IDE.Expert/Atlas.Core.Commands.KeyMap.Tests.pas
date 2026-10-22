unit Atlas.Core.Commands.KeyMap.Tests;

// Tests für die Tastenkürzel-Übersicht (#520): alle Atlas-Tasten, Suche nach
// Taste und Text, Konflikte und Gewinner, Herkunft nach Modul und HTML-Export.
// Wächter: Jede Tasten-Einstellung (Name auf „Key“) muss in
// TAtlasKeyEntry.AllFromSettings stehen, sonst fehlt sie in Übersicht,
// Konfliktprüfung beim Start und Einrichtung (#625). Nachgezogen: #775, #189,
// #777 (eigene Taste und Strg+F12).

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
    procedure EveryKeySettingIsInOverview;
    [Test]
    procedure NewEditorKeysAreListed;
    [Test]
    procedure SwitchedOffFunctionsAreNoConflict;
    [Test]
    procedure MultiCursorKeys;
    [Test]
    procedure UnitSearchTakesOverIdeKey;
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
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap;

const
  CtrlShiftP = $6050;
  CtrlW = $4057;
  CtrlE = $4045;
  CtrlShiftUp = $6026;
  CtrlShiftDown = $6028;
  CtrlF12 = $407B;

type
  /// <summary>Merkt sich, was Save schreibt, und liefert es Load zurück.</summary>
  TKeyStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FNames: TList<string>;
    FIntegers: TDictionary<string, Integer>;
    FStrings: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
    /// <summary>Namen der Zahlen in der Reihenfolge von Save.</summary>
    property Names: TList<string> read FNames;
  end;

constructor TKeyStore.Create;
begin
  inherited Create;
  FNames := TList<string>.Create;
  FIntegers := TDictionary<string, Integer>.Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TKeyStore.Destroy;
begin
  FStrings.Free;
  FIntegers.Free;
  FNames.Free;
  inherited;
end;

function TKeyStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FIntegers.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TKeyStore.WriteInteger(const AName: string; AValue: Integer);
begin
  if not FIntegers.ContainsKey(AName) then
    FNames.Add(AName);
  FIntegers.AddOrSetValue(AName, AValue);
end;

function TKeyStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TKeyStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(AName, AValue);
end;

function EntryOf(const AEntries: TArray<TAtlasKeyEntry>; AFunc: TAtlasKeyFunction): TAtlasKeyEntry;
var
  Entry: TAtlasKeyEntry;
begin
  Result := TAtlasKeyEntry.Create(AFunc, 0, False, False);
  for Entry in AEntries do
    if Entry.Func = AFunc then
      Exit(Entry);
end;

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
  // #775, #189, #777: eigene Tasten zurück; Strg+F12 ist fest und kein Feld.
  Settings.MethodToggleUpKey := $6049;
  Settings.MethodToggleDownKey := 0;
  Settings.TestUnitKey := $C054;
  Settings.UnitSearchKey := $C055;
  Saved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(TAtlasKeyEntry.AllFromSettings(Settings), Saved);
  Assert.AreEqual($6049, Saved.MethodToggleUpKey);
  Assert.AreEqual(0, Saved.MethodToggleDownKey);
  Assert.AreEqual($C054, Saved.TestUnitKey);
  Assert.AreEqual($C055, Saved.UnitSearchKey);
  // Abgeschaltet ändert die Taste nicht: Der Schalter ist eine eigene Einstellung.
  Settings.MethodToggle := False;
  Saved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(TAtlasKeyEntry.AllFromSettings(Settings), Saved);
  Assert.AreEqual($6049, Saved.MethodToggleUpKey);
  Assert.IsTrue(Saved.MethodToggle, 'ToSettings schaltet nichts');
end;

procedure TAtlasKeyMapTests.EveryKeySettingIsInOverview;
var
  Store: TKeyStore;
  StoreRef: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
  Entry: TAtlasKeyEntry;
  Name: string;
  Keys: TDictionary<string, Integer>;
  Pair: TPair<string, Integer>;
  Count: Integer;
  Found: Boolean;
begin
  // Wächter (#520): Jede gespeicherte Taste (TShortCut, Name auf „Key“) bekommt einen eigenen Wert; jeder muss
  // als eingeschalteter Eintrag in AllFromSettings auftauchen. Fehlt eine neue Taste dort, schlägt der Test fehl:
  // Dann TAtlasKeyFunction, AllFromSettings, ToSettings, CommandIdOf und FunctionCaption ergänzen.
  Store := TKeyStore.Create;
  StoreRef := Store;
  Keys := TDictionary<string, Integer>.Create;
  try
    // Alle Funktionen an, damit keine Taste wegen eines Schalters fehlt.
    Settings := TAtlasPluginSettings.Defaults;
    Settings.MethodToggle := True;
    Settings.UnitSearchEnabled := True;
    Settings.WelcomePage := True;
    Settings.WelcomePageSearch := True;
    Settings.MultiCursor := True;
    Settings.Save(StoreRef);
    Count := 0;
    for Name in Store.Names.ToArray do
      if Name.EndsWith('Key') then
      begin
        Inc(Count);
        Keys.Add(Name, TAtlasKeyConflicts.scCtrl or TAtlasKeyConflicts.scAlt or (Ord('A') + Count));
        Store.WriteInteger(Name, Keys[Name]);
      end;
    Assert.IsTrue(Count >= 18, 'Tasten-Einstellungen gefunden: ' + IntToStr(Count));
    Settings := TAtlasPluginSettings.Defaults;
    Settings.Load(StoreRef);
    Entries := TAtlasKeyEntry.AllFromSettings(Settings);
    for Pair in Keys do
    begin
      Found := False;
      for Entry in Entries do
        if (Entry.Key = Pair.Value) and not Entry.Disabled then
          Found := True;
      Assert.IsTrue(Found, Pair.Key + ' fehlt in TAtlasKeyEntry.AllFromSettings');
    end;
  finally
    Keys.Free;
  end;
end;

procedure TAtlasKeyMapTests.NewEditorKeysAreListed;
var
  Settings: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
  Entry: TAtlasKeyEntry;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.TestUnitKey := $C054;
  Settings.UnitSearchKey := $C055;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  // Deklaration ⇄ Implementierung (#775): zwei Tasten, Vorrang wie die übrigen Editorbefehle.
  Entry := EntryOf(Entries, TAtlasKeyFunction.MethodToggleUp);
  Assert.AreEqual(CtrlShiftUp, Integer(Entry.Key));
  Assert.IsFalse(Entry.Disabled);
  Assert.IsFalse(Entry.Priority, 'EditorKeysPriority ist aus');
  Entry := EntryOf(Entries, TAtlasKeyFunction.MethodToggleDown);
  Assert.AreEqual(CtrlShiftDown, Integer(Entry.Key));
  Assert.IsFalse(Entry.Disabled);
  // Unit ⇄ Testunit (#189) und eigene Taste für „Units suchen“ (#777).
  Assert.AreEqual($C054, Integer(EntryOf(Entries, TAtlasKeyFunction.TestUnit).Key));
  Assert.AreEqual($C055, Integer(EntryOf(Entries, TAtlasKeyFunction.UnitSearch).Key));
  // „Lesezeichen setzen…“ (#622): Strg+Alt+K als Editorbefehl.
  Assert.AreEqual($C04B, Integer(EntryOf(Entries, TAtlasKeyFunction.Bookmark).Key));
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.Bookmark).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.Bookmark)));
  // Erzeugen-Menü (#719): Alt+Einfg als Editorbefehl.
  Assert.AreEqual($802D, Integer(EntryOf(Entries, TAtlasKeyFunction.GenerateMenu).Key));
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.GenerateMenu).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.GenerateMenu)));
  // Benachrichtigungen (#601): Strg+Umschalt+Alt+N als Editorbefehl.
  Assert.AreEqual($E04E, Integer(EntryOf(Entries, TAtlasKeyFunction.Notifications).Key));
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.Notifications).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.Notifications)));
  // Schnellaktionen der Willkommensseite (#764): Strg+B und Strg+T, nur dort und immer mit Vorrang.
  Assert.AreEqual($4042, Integer(EntryOf(Entries, TAtlasKeyFunction.WelcomeQuickBuild).Key));
  Assert.AreEqual($4054, Integer(EntryOf(Entries, TAtlasKeyFunction.WelcomeQuickTests).Key));
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.WelcomeQuickBuild).Priority);
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.WelcomeQuickTests).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Window), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.WelcomeQuickBuild)));
  Assert.AreEqual(Ord(TAtlasKeyContext.WelcomePage),
    Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.WelcomeQuickTests)));
  Assert.AreEqual(Ord(TAtlasKeyContext.Editor), Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.MethodToggleDown)));
  // „Element ausblenden …“ (#628): Strg+. als Editorbefehl, immer mit Vorrang (ohne Element geht die Taste weiter).
  Assert.AreEqual($40BE, Integer(EntryOf(Entries, TAtlasKeyFunction.HideElement).Key));
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.HideElement).Priority);
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.HideElement).Disabled);
  Assert.AreEqual('Atlas.HideElement', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.HideElement));
  // Nächster/vorheriger Befund (#509): Strg+Alt+F8 und Strg+Alt+Umschalt+F8 als Editorbefehle.
  Assert.AreEqual($C077, Integer(EntryOf(Entries, TAtlasKeyFunction.NextProblem).Key));
  Assert.AreEqual($E077, Integer(EntryOf(Entries, TAtlasKeyFunction.PreviousProblem).Key));
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.NextProblem).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.PreviousProblem)));
  Assert.AreEqual('Atlas.NextProblem', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NextProblem));
  Assert.AreEqual('Atlas.PreviousProblem', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.PreviousProblem));
  // Schnell öffnen (#503): Strg+P als Editorbefehl.
  Assert.AreEqual($4050, Integer(EntryOf(Entries, TAtlasKeyFunction.QuickOpen).Key));
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.QuickOpen).Disabled);
  Assert.AreEqual('Atlas.QuickOpen', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.QuickOpen));
  // Navigationsverlauf (#504): Alt+Links/Rechts mit Vorrang (der Verlauf führt die Sprünge der IDE mit),
  // Strg+Alt+Q mit dem gemeinsamen Vorrang der Editorbefehle.
  Assert.AreEqual($8025, Integer(EntryOf(Entries, TAtlasKeyFunction.NavBack).Key));
  Assert.AreEqual($8027, Integer(EntryOf(Entries, TAtlasKeyFunction.NavForward).Key));
  Assert.AreEqual($C051, Integer(EntryOf(Entries, TAtlasKeyFunction.LastEdit).Key));
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.NavBack).Priority);
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.LastEdit).Priority);
  Assert.AreEqual('Atlas.NavBack', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NavBack));
  Assert.AreEqual('Atlas.LastEdit', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.LastEdit));
  // Definition und Referenzen einblenden (#505): Alt+F12 und Umschalt+Alt+F12.
  Assert.AreEqual($807B, Integer(EntryOf(Entries, TAtlasKeyFunction.PeekDefinition).Key));
  Assert.AreEqual($A07B, Integer(EntryOf(Entries, TAtlasKeyFunction.PeekReferences).Key));
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.PeekDefinition).Disabled);
  Assert.AreEqual('Atlas.PeekDefinition', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.PeekDefinition));
  Assert.AreEqual('Atlas.PeekReferences', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.PeekReferences));
  // Brotkrumenleiste (#590): Strg+Umschalt+. als Editorbefehl.
  Assert.AreEqual($60BE, Integer(EntryOf(Entries, TAtlasKeyFunction.Breadcrumbs).Key));
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.Breadcrumbs).Disabled);
  Assert.AreEqual('Atlas.Breadcrumbs', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Breadcrumbs));
  // Sprung zum Gegenstück (#635): Strg+Ü und Strg+Umschalt+Ü.
  Assert.AreEqual($40BA, Integer(EntryOf(Entries, TAtlasKeyFunction.JumpToMatch).Key));
  Assert.AreEqual($60BA, Integer(EntryOf(Entries, TAtlasKeyFunction.JumpToMatchSelect).Key));
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.JumpToMatchSelect).Disabled);
  Assert.AreEqual('Atlas.JumpToMatch', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.JumpToMatch));
  Assert.AreEqual('Atlas.JumpToMatchSelect', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.JumpToMatchSelect));
  // Nächste/vorherige Änderung (#507): Strg+Alt+Bild↓ und Strg+Alt+Bild↑.
  Assert.AreEqual($C022, Integer(EntryOf(Entries, TAtlasKeyFunction.NextChange).Key));
  Assert.AreEqual($C021, Integer(EntryOf(Entries, TAtlasKeyFunction.PreviousChange).Key));
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.NextChange).Disabled);
  Assert.AreEqual('Atlas.NextChange', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NextChange));
  Assert.AreEqual('Atlas.PreviousChange', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.PreviousChange));
  // Zeilen verschieben und duplizieren (#634): mit Vorrang, die IDE-Belegung steht als Konflikt da.
  Assert.AreEqual($8026, Integer(EntryOf(Entries, TAtlasKeyFunction.MoveLinesUp).Key));
  Assert.AreEqual($A028, Integer(EntryOf(Entries, TAtlasKeyFunction.DuplicateLinesDown).Key));
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.MoveLinesDown).Priority);
  Assert.AreEqual(Ord(TAtlasKeyStatus.AtlasWins), Ord(EntryOf(Entries, TAtlasKeyFunction.MoveLinesUp).Status(
    TAtlasKeyConflicts.OwnerOf($8026, TAtlasKeyConflicts.KnownIdeKeys))));
  Assert.AreEqual('Atlas.MoveLinesUp', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.MoveLinesUp));
  Assert.AreEqual('Atlas.DuplicateLinesDown', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.DuplicateLinesDown));
  // Anweisung vervollständigen (#697): Strg+Umschalt+Enter mit Vorrang vor „Referenzen suchen“.
  Assert.AreEqual($600D, Integer(EntryOf(Entries, TAtlasKeyFunction.CompleteStatement).Key));
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.CompleteStatement).Priority);
  Assert.AreEqual(Ord(TAtlasKeyStatus.AtlasWins), Ord(EntryOf(Entries, TAtlasKeyFunction.CompleteStatement).Status(
    TAtlasKeyConflicts.OwnerOf($600D, TAtlasKeyConflicts.KnownIdeKeys))));
  Assert.AreEqual('Atlas.CompleteStatement', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.CompleteStatement));
  // Formatieren (#43): eigene Taste, weil Strg+D die Mehrfachmarken und Strg+Umschalt+Alt+F die Suche in der
  // Methode (#877) haben.
  Assert.AreEqual($E04C, Integer(EntryOf(Entries, TAtlasKeyFunction.FormatCode).Key));
  Assert.AreEqual('Atlas.FormatCode', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.FormatCode));
  // Blockkommentar umschalten (#703): Umschalt+Alt+A.
  Assert.AreEqual($A041, Integer(EntryOf(Entries, TAtlasKeyFunction.ToggleBlockComment).Key));
  Assert.AreEqual('Atlas.ToggleBlockComment', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.ToggleBlockComment));
  // Neue Zeile ober- oder unterhalb (#700): Umschalt+Enter, Strg+Alt+Enter.
  Assert.AreEqual($200D, Integer(EntryOf(Entries, TAtlasKeyFunction.NewLineBelow).Key));
  Assert.AreEqual($C00D, Integer(EntryOf(Entries, TAtlasKeyFunction.NewLineAbove).Key));
  Assert.AreEqual('Atlas.NewLineBelow', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NewLineBelow));
  Assert.AreEqual('Atlas.NewLineAbove', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NewLineAbove));
  // Umschließung entfernen (#657): Strg+Umschalt+Entf.
  Assert.AreEqual($602E, Integer(EntryOf(Entries, TAtlasKeyFunction.Unwrap).Key));
  Assert.AreEqual('Atlas.Unwrap', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Unwrap));
  // Fenster „Atlas-Prüfung“ (#909): Strg+Alt+P.
  Assert.AreEqual($C050, Integer(EntryOf(Entries, TAtlasKeyFunction.ProblemsWindow).Key));
  Assert.AreEqual('Atlas.ProblemsWindow', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.ProblemsWindow));
  // Abschnittssprünge (#1101): ohne Vorgabetaste, Kennungen wie die Knöpfe der Editorleiste.
  Assert.AreEqual(0, Integer(EntryOf(Entries, TAtlasKeyFunction.SectionInterface).Key));
  Assert.AreEqual(0, Integer(EntryOf(Entries, TAtlasKeyFunction.SectionImplementation).Key));
  Assert.AreEqual('Atlas.GotoInterface', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SectionInterface));
  Assert.AreEqual('Atlas.GotoImplementation', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SectionImplementation));
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.TestUnit)));
  Settings.EditorKeysPriority := True;
  Assert.IsTrue(EntryOf(TAtlasKeyEntry.AllFromSettings(Settings), TAtlasKeyFunction.UnitSearch).Priority);
  // Beide Tasten gleich: Atlas belegt sie nur einmal, also kein doppelter Eintrag.
  Settings.MethodToggleDownKey := Settings.MethodToggleUpKey;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.MethodToggleUp).Disabled);
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.MethodToggleDown).Disabled);
end;

procedure TAtlasKeyMapTests.MultiCursorKeys;
var
  Settings, Saved: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
  Index: Integer;
begin
  // #589: Vorgabe aus (experimentell), dann kein Konflikt; eingeschaltet mit Vorrang vor „Quelltext formatieren“.
  Settings := TAtlasPluginSettings.Defaults;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.MultiCursorNext).Disabled);
  Assert.AreEqual(Ord(TAtlasKeyStatus.NoKey), Ord(EntryOf(Entries, TAtlasKeyFunction.MultiCursorNext).Status(
    'IDE: Quelltext formatieren')));
  Settings.MultiCursor := True;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.MultiCursorNext).Disabled);
  Assert.AreEqual($4044, Integer(EntryOf(Entries, TAtlasKeyFunction.MultiCursorNext).Key));
  Assert.AreEqual($4044, Integer(EntryOf(Entries, TAtlasKeyFunction.MultiCursorSkip).Key));
  Assert.AreEqual($A049, Integer(EntryOf(Entries, TAtlasKeyFunction.MultiCursorLineEnds).Key));
  Assert.AreEqual($C026, Integer(EntryOf(Entries, TAtlasKeyFunction.MultiCursorAbove).Key));
  Assert.AreEqual($C028, Integer(EntryOf(Entries, TAtlasKeyFunction.MultiCursorBelow).Key));
  Assert.IsTrue(EntryOf(Entries, TAtlasKeyFunction.MultiCursorBelow).Priority);
  Assert.AreEqual(Ord(TAtlasKeyStatus.AtlasWins), Ord(EntryOf(Entries, TAtlasKeyFunction.MultiCursorNext).Status(
    'IDE: Quelltext formatieren')));
  Assert.AreEqual('Atlas.MultiCursorNext', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.MultiCursorNext));
  Assert.AreEqual('Atlas.MultiCursorLineEnds', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.MultiCursorLineEnds));
  Assert.AreEqual('Atlas.MultiCursorAbove', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.MultiCursorAbove));
  Assert.AreEqual('Atlas.MultiCursorBelow', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.MultiCursorBelow));
  // Überspringen ist kein Befehl und keine Bindung: nur nach Strg+K bei aktiven Marken.
  Assert.AreEqual('', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.MultiCursorSkip));
  Assert.AreEqual(Ord(TAtlasKeySource.Window), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.MultiCursorSkip)));
  Assert.AreEqual(Ord(TAtlasKeyContext.Editor), Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.MultiCursorSkip)));
  // Zurück in die Einstellungen (Eintrag gezielt suchen: weitere Funktionen stehen dahinter).
  for Index := 0 to High(Entries) do
    if Entries[Index].Func = TAtlasKeyFunction.MultiCursorBelow then
      Entries[Index].Key := $A028;
  Saved := Settings;
  TAtlasKeyEntry.ToSettings(Entries, Saved);
  Assert.AreEqual($A028, Saved.MultiCursorBelowKey);
end;

procedure TAtlasKeyMapTests.SwitchedOffFunctionsAreNoConflict;
var
  Settings: TAtlasPluginSettings;
  Entries: TArray<TAtlasKeyEntry>;
  Entry: TAtlasKeyEntry;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.UnitSearchKey := $C055;
  Settings.MethodToggle := False;
  Settings.UnitSearchEnabled := False;
  Settings.WelcomePageSearch := False;
  Settings.BookmarksNamed := False;
  Settings.GenerateMenu := False;
  Settings.Notifications := False;
  Settings.WelcomePageQuickActions := False;
  Settings.Problems := False;
  Settings.QuickOpen := False;
  Settings.NavHistory := False;
  Settings.Peek := False;
  Settings.Breadcrumbs := False;
  Settings.JumpToMatch := False;
  Settings.GitGutter := False;
  Settings.MoveLines := False;
  Settings.CompleteStatement := False;
  Settings.MultiCursor := False;
  Settings.FormatCode := False;
  Settings.ToggleBlockComment := False;
  Settings.NewLineAround := False;
  Settings.Unwrap := False;
  Settings.ProblemsWindow := False;
  Entries := TAtlasKeyEntry.AllFromSettings(Settings);
  for Entry in Entries do
    if Entry.Func in [TAtlasKeyFunction.MethodToggleUp, TAtlasKeyFunction.MethodToggleDown,
      TAtlasKeyFunction.UnitSearch, TAtlasKeyFunction.UnitSearchIde, TAtlasKeyFunction.WelcomeSearch,
      TAtlasKeyFunction.Bookmark, TAtlasKeyFunction.GenerateMenu, TAtlasKeyFunction.Notifications,
      TAtlasKeyFunction.WelcomeQuickBuild, TAtlasKeyFunction.WelcomeQuickTests, TAtlasKeyFunction.NextProblem,
      TAtlasKeyFunction.PreviousProblem, TAtlasKeyFunction.QuickOpen, TAtlasKeyFunction.NavBack,
      TAtlasKeyFunction.NavForward, TAtlasKeyFunction.LastEdit, TAtlasKeyFunction.PeekDefinition,
      TAtlasKeyFunction.PeekReferences, TAtlasKeyFunction.Breadcrumbs, TAtlasKeyFunction.JumpToMatch,
      TAtlasKeyFunction.JumpToMatchSelect, TAtlasKeyFunction.NextChange, TAtlasKeyFunction.PreviousChange,
      TAtlasKeyFunction.MoveLinesUp, TAtlasKeyFunction.MoveLinesDown, TAtlasKeyFunction.DuplicateLinesUp,
      TAtlasKeyFunction.DuplicateLinesDown, TAtlasKeyFunction.CompleteStatement, TAtlasKeyFunction.MultiCursorNext,
      TAtlasKeyFunction.MultiCursorSkip, TAtlasKeyFunction.MultiCursorLineEnds, TAtlasKeyFunction.MultiCursorAbove,
      TAtlasKeyFunction.MultiCursorBelow, TAtlasKeyFunction.FormatCode, TAtlasKeyFunction.ToggleBlockComment,
      TAtlasKeyFunction.NewLineBelow, TAtlasKeyFunction.NewLineAbove, TAtlasKeyFunction.Unwrap,
      TAtlasKeyFunction.ProblemsWindow] then
    begin
      Assert.IsTrue(Entry.Disabled, 'abgeschaltet: ' + IntToStr(Ord(Entry.Func)));
      Assert.AreEqual(Ord(TAtlasKeyStatus.NoKey), Ord(Entry.Status('IDE: Klassennavigation')),
        'kein Konflikt: ' + IntToStr(Ord(Entry.Func)));
    end
    else
      Assert.IsFalse(Entry.Disabled, 'an: ' + IntToStr(Ord(Entry.Func)));
  // Die Taste bleibt eingestellt; nur der Schalter ist aus.
  Assert.AreEqual(CtrlShiftUp, Integer(EntryOf(Entries, TAtlasKeyFunction.MethodToggleUp).Key));
  // Unit ⇄ Testunit (#189) hat keinen eigenen Schalter (abschalten heißt Taste 0), bleibt also an.
  Assert.IsFalse(EntryOf(Entries, TAtlasKeyFunction.TestUnit).Disabled);
  // Das Suchfeld ist auch mit abgeschalteter Willkommensseite aus.
  Settings.WelcomePage := False;
  Settings.WelcomePageSearch := True;
  Assert.IsTrue(EntryOf(TAtlasKeyEntry.AllFromSettings(Settings), TAtlasKeyFunction.WelcomeSearch).Disabled,
    'Willkommensseite aus');
  // Ebenso die Schnellaktionen (#764).
  Settings.WelcomePageQuickActions := True;
  Assert.IsTrue(EntryOf(TAtlasKeyEntry.AllFromSettings(Settings), TAtlasKeyFunction.WelcomeQuickBuild).Disabled,
    'Willkommensseite aus');
end;

procedure TAtlasKeyMapTests.UnitSearchTakesOverIdeKey;
var
  Settings: TAtlasPluginSettings;
  Entry: TAtlasKeyEntry;
  Items: TArray<TAtlasKeyItem>;
  Plugin: TAtlasKeyItem;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Entry := EntryOf(TAtlasKeyEntry.AllFromSettings(Settings), TAtlasKeyFunction.UnitSearchIde);
  Assert.AreEqual(CtrlF12, Integer(Entry.Key), 'Strg+F12 der IDE-Aktion „Units“');
  Assert.IsTrue(Entry.Priority, 'bewusst übernommen');
  Assert.IsFalse(Entry.Disabled);
  Assert.AreEqual(Ord(TAtlasKeyContext.Global), Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.UnitSearchIde)));
  Assert.AreEqual(Ord(TAtlasKeySource.Action), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.UnitSearchIde)));
  Settings.UnitSearchReplaceIdeDialog := False;
  Assert.IsTrue(EntryOf(TAtlasKeyEntry.AllFromSettings(Settings), TAtlasKeyFunction.UnitSearchIde).Disabled,
    'ohne Übernahme gehört Strg+F12 der IDE');
  // Eine Erweiterung belegt Strg+F12 im Editor: Dort gewinnt ihre Tastaturbelegung vor der Aktion, Atlas meldet es.
  Plugin := TAtlasKeyItem.Create(CtrlF12, 'Strg+F12', 'Tastaturbelegung des Editors', TAtlasKeyOrigin.Plugin,
    'CnWizards_D120', TAtlasKeyContext.Editor, TAtlasKeySource.Binding, 'Editor.' + IntToStr(CtrlF12), 101);
  Plugin.Effective := True;
  Items := [AtlasKey(TAtlasKeyFunction.UnitSearchIde, CtrlF12, True, True), Plugin];
  TAtlasKeyMap.Analyze(Items);
  Assert.IsTrue(Items[0].Conflict);
  Assert.AreEqual(1, Items[0].Winner);
  Assert.AreEqual(Ord(TAtlasKeyReason.EditorBinding), Ord(Items[0].Reason));
  Assert.AreEqual(1, Integer(Length(TAtlasKeyMap.AtlasConflicts(Items))));
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
  // #775, #189, #777: Befehle der Palette; mehrere Tasten können denselben Befehl haben.
  Assert.AreEqual('Atlas.ToggleMethod', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.MethodToggleUp));
  Assert.AreEqual('Atlas.ToggleMethod', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.MethodToggleDown));
  Assert.AreEqual('Atlas.SwitchTestUnit', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.TestUnit));
  Assert.AreEqual('Atlas.UnitSearch', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.UnitSearch));
  Assert.AreEqual('Atlas.UnitSearch', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.UnitSearchIde));
  // #622: „Lesezeichen setzen…“.
  Assert.AreEqual('Atlas.BookmarkAdd', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Bookmark));
  // #719: Erzeugen-Menü.
  Assert.AreEqual('Atlas.GenerateMenu', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.GenerateMenu));
  // #601: Liste der Benachrichtigungen.
  Assert.AreEqual('Atlas.Notifications', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Notifications));
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
