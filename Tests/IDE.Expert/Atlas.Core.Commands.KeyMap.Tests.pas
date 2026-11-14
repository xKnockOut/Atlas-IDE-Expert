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
    /// <summary>„Datei jetzt prüfen“ (#1744): Vorgabe, Befehl, abgeschaltet ohne Prüfregeln, zurück in die
    /// Einstellungen.</summary>
    [Test]
    procedure CheckFileKeyFollowsProblems;
    /// <summary>„Neue Zeile am Ende des Abschnitts“ (#1768): ohne Vorgabe, Befehl, abgeschaltet mit
    /// editor.breadcrumbsSectionAppend, zurück in die Einstellungen.</summary>
    [Test]
    procedure SectionAppendKeyFollowsSetting;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap;

const
  cCtrlShiftP = $6050;
  cCtrlW = $4057;
  cCtrlE = $4045;
  cCtrlShiftUp = $6026;
  cCtrlShiftDown = $6028;
  cCtrlF12 = $407B;

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
  begin
    Result := ADefault;
  end;
end;

procedure TKeyStore.WriteInteger(const AName: string; AValue: Integer);
begin
  if not FIntegers.ContainsKey(AName) then
  begin
    FNames.Add(AName);
  end;
  FIntegers.AddOrSetValue(AName, AValue);
end;

function TKeyStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TKeyStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(AName, AValue);
end;

function EntryOf(const AEntries: TArray<TAtlasKeyEntry>; AFunc: TAtlasKeyFunction): TAtlasKeyEntry;
var
  mEntry: TAtlasKeyEntry;
begin
  Result := TAtlasKeyEntry.Create(AFunc, 0, False, False);
  for mEntry in AEntries do
  begin
    if mEntry.Func = AFunc then
    begin
      Exit(mEntry);
    end;
  end;
end;

function AtlasKey(AFunc: TAtlasKeyFunction; AKey: Word; APriority, AActive: Boolean): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, 'Taste', 'Atlas ' + IntToStr(Ord(AFunc)),
    TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Atlas, TAtlasKeyMap.cAtlasName, TAtlasKeyMap.ContextOf(AFunc),
    TAtlasKeyMap.SourceOf(AFunc), 'Atlas.Key.' + IntToStr(Ord(AFunc)), Ord(AFunc)));
  Result.Func := AFunc;
  Result.Priority := APriority;
  Result.Active := AActive;
end;

function IdeAction(const AName: string; AKey: Word; AOrder: Integer): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, 'Taste', AName, TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Ide,
    TAtlasKeyMap.cIdeName, TAtlasKeyContext.Global, TAtlasKeySource.Action, AName, AOrder));
end;

function IdeBinding(const AName: string; AKey: Word): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, 'Taste', AName, TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Ide,
    TAtlasKeyMap.cIdeName, TAtlasKeyContext.Editor, TAtlasKeySource.Binding, 'Editor.' + IntToStr(AKey), 0));
end;

procedure TAtlasKeyMapTests.AllFromSettingsListsEveryAtlasKey;
var
  mSettings: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
  mEntry: TAtlasKeyEntry;
  mFunc: TAtlasKeyFunction;
  mFound: Boolean;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.EditorKeysPriority := True;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  // Jede Funktion genau einmal, die ersten neun wie auf der Seite „Tastenkonflikte“ (sechs, dazu drei der schnellen
  // Lesezeichen, #1104).
  Assert.AreEqual(Ord(High(TAtlasKeyFunction)) + 1, Integer(Length(mEntries)));
  for mFunc := Low(TAtlasKeyFunction) to High(TAtlasKeyFunction) do
  begin
    mFound := False;
    for mEntry in mEntries do
    begin
      if mEntry.Func = mFunc then
      begin
        mFound := True;
      end;
    end;
    Assert.IsTrue(mFound, 'Funktion ' + IntToStr(Ord(mFunc)));
  end;
  Assert.AreEqual(Ord(TAtlasKeyFunction.DiagnosticMode), Ord(mEntries[5].Func));
  Assert.AreEqual(Ord(TAtlasKeyFunction.QuickBookmarkJump), Ord(mEntries[8].Func));
  Assert.AreEqual($800D, Integer(mEntries[9].Key), 'Code-Aktionen: Alt+Enter');
  Assert.IsTrue(mEntries[9].Priority, 'Editorbefehle: gemeinsamer Vorrang');
  Assert.AreEqual(cCtrlE, Integer(mEntries[16].Key), 'Suchfeld der Willkommensseite: Strg+E');
  Assert.IsTrue(mEntries[16].Priority, 'Das Suchfeld nimmt die Taste auf der Willkommensseite immer');
  Assert.AreEqual(cCtrlShiftP, Integer(mEntries[0].Key), 'Befehlspalette #502');
end;

procedure TAtlasKeyMapTests.AllFromSettingsRoundTripsEditorKeys;
var
  mSettings, mSaved: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.ExpandKey := $6045;
  mSettings.RedoKey := 0;
  mSettings.WelcomePageSearchKey := $4046;
  mSettings.EditorKeysPriority := True;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  mSaved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(mEntries, mSaved);
  Assert.AreEqual($6045, mSaved.ExpandKey);
  Assert.AreEqual(0, mSaved.RedoKey);
  Assert.AreEqual($4046, mSaved.WelcomePageSearchKey);
  Assert.IsTrue(mSaved.EditorKeysPriority);
  Assert.AreEqual(mSettings.UndoKey, mSaved.UndoKey);
  // #775, #189, #777: eigene Tasten zurück; Strg+F12 ist fest und kein Feld.
  mSettings.MethodToggleUpKey := $6049;
  mSettings.MethodToggleDownKey := 0;
  mSettings.TestUnitKey := $C054;
  mSettings.UnitSearchKey := $C055;
  mSaved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(TAtlasKeyEntry.AllFromSettings(mSettings), mSaved);
  Assert.AreEqual($6049, mSaved.MethodToggleUpKey);
  Assert.AreEqual(0, mSaved.MethodToggleDownKey);
  Assert.AreEqual($C054, mSaved.TestUnitKey);
  Assert.AreEqual($C055, mSaved.UnitSearchKey);
  // Abgeschaltet ändert die Taste nicht: Der Schalter ist eine eigene Einstellung.
  mSettings.MethodToggle := False;
  mSaved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(TAtlasKeyEntry.AllFromSettings(mSettings), mSaved);
  Assert.AreEqual($6049, mSaved.MethodToggleUpKey);
  Assert.IsTrue(mSaved.MethodToggle, 'ToSettings schaltet nichts');
end;

procedure TAtlasKeyMapTests.EveryKeySettingIsInOverview;
var
  mStore: TKeyStore;
  mStoreRef: IAtlasSettingsStore;
  mSettings: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
  mEntry: TAtlasKeyEntry;
  mName: string;
  mKeys: TDictionary<string, Integer>;
  mPair: TPair<string, Integer>;
  mCount: Integer;
  mFound: Boolean;
begin
  // Wächter (#520): Jede gespeicherte Taste (TShortCut, Name auf „Key“) bekommt einen eigenen Wert; jeder muss
  // als eingeschalteter Eintrag in AllFromSettings auftauchen. Fehlt eine neue Taste dort, schlägt der Test fehl:
  // Dann TAtlasKeyFunction, AllFromSettings, ToSettings, CommandIdOf und FunctionCaption ergänzen.
  mStore := TKeyStore.Create;
  mStoreRef := mStore;
  mKeys := TDictionary<string, Integer>.Create;
  try
    // Alle Funktionen an, damit keine Taste wegen eines Schalters fehlt.
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.MethodToggle := True;
    mSettings.UnitSearchEnabled := True;
    mSettings.WelcomePage := True;
    mSettings.WelcomePageSearch := True;
    mSettings.MultiCursor := True;
    mSettings.Save(mStoreRef);
    mCount := 0;
    for mName in mStore.Names.ToArray do
    begin
      // DesignerMeasureAltKey ist ein Schalter (Boolean), keine Taste; der Name endet nur zufällig auf Key.
      if mName.EndsWith('Key') and not SameText(mName, 'DesignerMeasureAltKey') then
      begin
        Inc(mCount);
        mKeys.Add(mName, TAtlasKeyConflicts.cScCtrl or TAtlasKeyConflicts.cScAlt or (Ord('A') + mCount));
        mStore.WriteInteger(mName, mKeys[mName]);
      end;
    end;
    Assert.IsTrue(mCount >= 18, 'Tasten-Einstellungen gefunden: ' + IntToStr(mCount));
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.Load(mStoreRef);
    mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
    for mPair in mKeys do
    begin
      mFound := False;
      for mEntry in mEntries do
      begin
        if (mEntry.Key = mPair.Value) and not mEntry.Disabled then
        begin
          mFound := True;
        end;
      end;
      Assert.IsTrue(mFound, mPair.Key + ' fehlt in TAtlasKeyEntry.AllFromSettings');
    end;
  finally
    mKeys.Free;
  end;
end;

/// <summary>Tasten für Navigationsverlauf, Formatieren und Blockkommentar.</summary>
procedure AssertNavigationAndEditKeys(const AEntries: TArray<TAtlasKeyEntry>);
begin
  // Navigationsverlauf (#504): Alt+Links/Rechts mit Vorrang (der Verlauf führt die Sprünge der IDE mit),
  // Strg+Alt+Q mit dem gemeinsamen Vorrang der Editorbefehle.
  Assert.AreEqual($8025, Integer(EntryOf(AEntries, TAtlasKeyFunction.NavBack).Key));
  Assert.AreEqual($8027, Integer(EntryOf(AEntries, TAtlasKeyFunction.NavForward).Key));
  Assert.AreEqual($C051, Integer(EntryOf(AEntries, TAtlasKeyFunction.LastEdit).Key));
  Assert.IsTrue(EntryOf(AEntries, TAtlasKeyFunction.NavBack).Priority);
  Assert.IsFalse(EntryOf(AEntries, TAtlasKeyFunction.LastEdit).Priority);
  Assert.AreEqual('Atlas.NavBack', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NavBack));
  Assert.AreEqual('Atlas.LastEdit', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.LastEdit));
  // Definition und Referenzen einblenden (#505): Alt+F12 und Umschalt+Alt+F12.
  Assert.AreEqual($807B, Integer(EntryOf(AEntries, TAtlasKeyFunction.PeekDefinition).Key));
  Assert.AreEqual($A07B, Integer(EntryOf(AEntries, TAtlasKeyFunction.PeekReferences).Key));
  Assert.IsFalse(EntryOf(AEntries, TAtlasKeyFunction.PeekDefinition).Disabled);
  Assert.AreEqual('Atlas.PeekDefinition', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.PeekDefinition));
  Assert.AreEqual('Atlas.PeekReferences', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.PeekReferences));
  // Brotkrumenleiste (#590): Strg+Umschalt+. als Editorbefehl.
  Assert.AreEqual($60BE, Integer(EntryOf(AEntries, TAtlasKeyFunction.Breadcrumbs).Key));
  Assert.IsFalse(EntryOf(AEntries, TAtlasKeyFunction.Breadcrumbs).Disabled);
  Assert.AreEqual('Atlas.Breadcrumbs', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Breadcrumbs));
  // Sprung zum Gegenstück (#635): Strg+Ü und Strg+Umschalt+Ü.
  Assert.AreEqual($40BA, Integer(EntryOf(AEntries, TAtlasKeyFunction.JumpToMatch).Key));
  Assert.AreEqual($60BA, Integer(EntryOf(AEntries, TAtlasKeyFunction.JumpToMatchSelect).Key));
  Assert.IsFalse(EntryOf(AEntries, TAtlasKeyFunction.JumpToMatchSelect).Disabled);
  Assert.AreEqual('Atlas.JumpToMatch', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.JumpToMatch));
  Assert.AreEqual('Atlas.JumpToMatchSelect', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.JumpToMatchSelect));
  // Nächste/vorherige Änderung (#507): Strg+Alt+Bild↓ und Strg+Alt+Bild↑.
  Assert.AreEqual($C022, Integer(EntryOf(AEntries, TAtlasKeyFunction.NextChange).Key));
  Assert.AreEqual($C021, Integer(EntryOf(AEntries, TAtlasKeyFunction.PreviousChange).Key));
  Assert.IsFalse(EntryOf(AEntries, TAtlasKeyFunction.NextChange).Disabled);
  Assert.AreEqual('Atlas.NextChange', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NextChange));
  Assert.AreEqual('Atlas.PreviousChange', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.PreviousChange));
  // Zeilen verschieben und duplizieren (#634): mit Vorrang, die IDE-Belegung steht als Konflikt da.
  Assert.AreEqual($8026, Integer(EntryOf(AEntries, TAtlasKeyFunction.MoveLinesUp).Key));
  Assert.AreEqual($A028, Integer(EntryOf(AEntries, TAtlasKeyFunction.DuplicateLinesDown).Key));
  Assert.IsTrue(EntryOf(AEntries, TAtlasKeyFunction.MoveLinesDown).Priority);
  Assert.AreEqual(Ord(TAtlasKeyStatus.AtlasWins), Ord(EntryOf(AEntries, TAtlasKeyFunction.MoveLinesUp).Status(
    TAtlasKeyConflicts.OwnerOf($8026, TAtlasKeyConflicts.KnownIdeKeys))));
  Assert.AreEqual('Atlas.MoveLinesUp', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.MoveLinesUp));
  Assert.AreEqual('Atlas.DuplicateLinesDown', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.DuplicateLinesDown));
  // Anweisung vervollständigen (#697): Strg+Umschalt+Enter mit Vorrang vor „Referenzen suchen“.
  Assert.AreEqual($600D, Integer(EntryOf(AEntries, TAtlasKeyFunction.CompleteStatement).Key));
  Assert.IsTrue(EntryOf(AEntries, TAtlasKeyFunction.CompleteStatement).Priority);
  Assert.AreEqual(Ord(TAtlasKeyStatus.AtlasWins), Ord(EntryOf(AEntries, TAtlasKeyFunction.CompleteStatement).Status(
    TAtlasKeyConflicts.OwnerOf($600D, TAtlasKeyConflicts.KnownIdeKeys))));
  Assert.AreEqual('Atlas.CompleteStatement', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.CompleteStatement));
  // Formatieren (#43): eigene Taste, weil Strg+D die Mehrfachmarken und Strg+Umschalt+Alt+F die Suche in der
  // Methode (#877) haben.
  Assert.AreEqual($E04C, Integer(EntryOf(AEntries, TAtlasKeyFunction.FormatCode).Key));
  Assert.AreEqual('Atlas.FormatCode', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.FormatCode));
  // Blockkommentar umschalten (#703): Umschalt+Alt+A.
  Assert.AreEqual($A041, Integer(EntryOf(AEntries, TAtlasKeyFunction.ToggleBlockComment).Key));
  Assert.AreEqual('Atlas.ToggleBlockComment', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.ToggleBlockComment));
end;

/// <summary>Tasten ab „Neue Zeile ober- oder unterhalb“ (#700) und Vorrang der Editorbefehle.</summary>
procedure AssertLineAndBookmarkKeys(const ASettings: TAtlasPluginSettings; const AEntries: TArray<TAtlasKeyEntry>);
var
  mSettings: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
begin
  mSettings := ASettings;
  mEntries := AEntries;
  // Neue Zeile ober- oder unterhalb (#700): Umschalt+Enter, Strg+Alt+Enter.
  Assert.AreEqual($200D, Integer(EntryOf(mEntries, TAtlasKeyFunction.NewLineBelow).Key));
  Assert.AreEqual($C00D, Integer(EntryOf(mEntries, TAtlasKeyFunction.NewLineAbove).Key));
  Assert.AreEqual('Atlas.NewLineBelow', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NewLineBelow));
  Assert.AreEqual('Atlas.NewLineAbove', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NewLineAbove));
  // Umschließung entfernen (#657): Strg+Umschalt+Entf.
  Assert.AreEqual($602E, Integer(EntryOf(mEntries, TAtlasKeyFunction.Unwrap).Key));
  Assert.AreEqual('Atlas.Unwrap', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.Unwrap));
  // Typ des markierten Ausdrucks (#689): Strg+Umschalt+T mit Vorrang vor „To-Do-Eintrag hinzufügen“.
  Assert.AreEqual($6054, Integer(EntryOf(mEntries, TAtlasKeyFunction.ExpressionType).Key));
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.ExpressionType).Priority);
  Assert.AreEqual(Ord(TAtlasKeyStatus.AtlasWins), Ord(EntryOf(mEntries, TAtlasKeyFunction.ExpressionType).Status(
    TAtlasKeyConflicts.OwnerOf($6054, TAtlasKeyConflicts.KnownIdeKeys))));
  Assert.AreEqual('Atlas.ExpressionType', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.ExpressionType));
  // Sicher löschen (#716): Alt+Entf.
  Assert.AreEqual($802E, Integer(EntryOf(mEntries, TAtlasKeyFunction.SafeDelete).Key));
  Assert.AreEqual('Atlas.SafeDelete', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SafeDelete));
  // Fenster „Atlas-Prüfung“ (#909): Strg+Alt+P.
  Assert.AreEqual($C050, Integer(EntryOf(mEntries, TAtlasKeyFunction.ProblemsWindow).Key));
  Assert.AreEqual('Atlas.ProblemsWindow', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.ProblemsWindow));
  // Abschnittssprünge (#1101): ohne Vorgabetaste, Kennungen wie die Knöpfe der Editorleiste.
  Assert.AreEqual(0, Integer(EntryOf(mEntries, TAtlasKeyFunction.SectionInterface).Key));
  Assert.AreEqual(0, Integer(EntryOf(mEntries, TAtlasKeyFunction.SectionImplementation).Key));
  Assert.AreEqual('Atlas.GotoInterface', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SectionInterface));
  Assert.AreEqual('Atlas.GotoImplementation', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SectionImplementation));
  // Schnelle Lesezeichen (#1104): Strg+Umschalt+K, Strg+Umschalt+1, Strg+1; nächstes/voriges ohne Vorgabe.
  Assert.AreEqual($604B, Integer(EntryOf(mEntries, TAtlasKeyFunction.QuickBookmark).Key));
  Assert.AreEqual($6031, Integer(EntryOf(mEntries, TAtlasKeyFunction.QuickBookmarkSet).Key));
  Assert.AreEqual($4031, Integer(EntryOf(mEntries, TAtlasKeyFunction.QuickBookmarkJump).Key));
  Assert.AreEqual(0, Integer(EntryOf(mEntries, TAtlasKeyFunction.NextBookmark).Key));
  Assert.AreEqual('Atlas.QuickBookmarkToggle', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.QuickBookmark));
  Assert.AreEqual('Atlas.NextBookmark', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NextBookmark));
  Assert.AreEqual('Atlas.PreviousBookmark', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.PreviousBookmark));
  // Gezielt hineinspringen (#836): Strg+Alt+F7, aus = Kürzel frei.
  Assert.AreEqual($C076, Integer(EntryOf(mEntries, TAtlasKeyFunction.StepIntoTarget).Key));
  Assert.AreEqual('Atlas.StepIntoTarget', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.StepIntoTarget));
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.TestUnit)));
  mSettings.EditorKeysPriority := True;
  Assert.IsTrue(EntryOf(TAtlasKeyEntry.AllFromSettings(mSettings), TAtlasKeyFunction.UnitSearch).Priority);
  // Beide Tasten gleich: Atlas belegt sie nur einmal, also kein doppelter Eintrag.
  mSettings.MethodToggleDownKey := mSettings.MethodToggleUpKey;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.MethodToggleUp).Disabled);
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.MethodToggleDown).Disabled);
end;

procedure TAtlasKeyMapTests.NewEditorKeysAreListed;
var
  mSettings: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
  mEntry: TAtlasKeyEntry;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.TestUnitKey := $C054;
  mSettings.UnitSearchKey := $C055;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  // Deklaration ⇄ Implementierung (#775): zwei Tasten, Vorrang wie die übrigen Editorbefehle.
  mEntry := EntryOf(mEntries, TAtlasKeyFunction.MethodToggleUp);
  Assert.AreEqual(cCtrlShiftUp, Integer(mEntry.Key));
  Assert.IsFalse(mEntry.Disabled);
  Assert.IsFalse(mEntry.Priority, 'EditorKeysPriority ist aus');
  mEntry := EntryOf(mEntries, TAtlasKeyFunction.MethodToggleDown);
  Assert.AreEqual(cCtrlShiftDown, Integer(mEntry.Key));
  Assert.IsFalse(mEntry.Disabled);
  // Unit ⇄ Testunit (#189) und eigene Taste für „Units suchen“ (#777).
  Assert.AreEqual($C054, Integer(EntryOf(mEntries, TAtlasKeyFunction.TestUnit).Key));
  Assert.AreEqual($C055, Integer(EntryOf(mEntries, TAtlasKeyFunction.UnitSearch).Key));
  // „Lesezeichen setzen…“ (#622): Strg+Alt+K als Editorbefehl.
  Assert.AreEqual($C04B, Integer(EntryOf(mEntries, TAtlasKeyFunction.Bookmark).Key));
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.Bookmark).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.Bookmark)));
  // Erzeugen-Menü (#719): Alt+Einfg als Editorbefehl.
  Assert.AreEqual($802D, Integer(EntryOf(mEntries, TAtlasKeyFunction.GenerateMenu).Key));
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.GenerateMenu).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.GenerateMenu)));
  // Benachrichtigungen (#601): Strg+Umschalt+Alt+N als Editorbefehl.
  Assert.AreEqual($E04E, Integer(EntryOf(mEntries, TAtlasKeyFunction.Notifications).Key));
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.Notifications).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.Notifications)));
  // Schnellaktionen der Willkommensseite (#764): Strg+B und Strg+T, nur dort und immer mit Vorrang.
  Assert.AreEqual($4042, Integer(EntryOf(mEntries, TAtlasKeyFunction.WelcomeQuickBuild).Key));
  Assert.AreEqual($4054, Integer(EntryOf(mEntries, TAtlasKeyFunction.WelcomeQuickTests).Key));
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.WelcomeQuickBuild).Priority);
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.WelcomeQuickTests).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Window), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.WelcomeQuickBuild)));
  Assert.AreEqual(Ord(TAtlasKeyContext.WelcomePage),
    Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.WelcomeQuickTests)));
  Assert.AreEqual(Ord(TAtlasKeyContext.Editor), Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.MethodToggleDown)));
  // „Element ausblenden …“ (#628): Strg+. als Editorbefehl, immer mit Vorrang (ohne Element geht die Taste weiter).
  Assert.AreEqual($40BE, Integer(EntryOf(mEntries, TAtlasKeyFunction.HideElement).Key));
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.HideElement).Priority);
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.HideElement).Disabled);
  Assert.AreEqual('Atlas.HideElement', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.HideElement));
  // Nächster/vorheriger Befund (#509): Strg+Alt+F8 und Strg+Alt+Umschalt+F8 als Editorbefehle.
  Assert.AreEqual($C077, Integer(EntryOf(mEntries, TAtlasKeyFunction.NextProblem).Key));
  Assert.AreEqual($E077, Integer(EntryOf(mEntries, TAtlasKeyFunction.PreviousProblem).Key));
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.NextProblem).Disabled);
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.PreviousProblem)));
  Assert.AreEqual('Atlas.NextProblem', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.NextProblem));
  Assert.AreEqual('Atlas.PreviousProblem', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.PreviousProblem));
  // Schnell öffnen (#503): Strg+P als Editorbefehl.
  Assert.AreEqual($4050, Integer(EntryOf(mEntries, TAtlasKeyFunction.QuickOpen).Key));
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.QuickOpen).Disabled);
  Assert.AreEqual('Atlas.QuickOpen', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.QuickOpen));
  AssertNavigationAndEditKeys(mEntries);
  AssertLineAndBookmarkKeys(mSettings, mEntries);
end;

procedure TAtlasKeyMapTests.MultiCursorKeys;
var
  mSettings, mSaved: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
  mIndex: Integer;
begin
  // #589: Vorgabe aus (experimentell), dann kein Konflikt; eingeschaltet mit Vorrang vor „Quelltext formatieren“.
  mSettings := TAtlasPluginSettings.Defaults;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorNext).Disabled);
  Assert.AreEqual(Ord(TAtlasKeyStatus.NoKey), Ord(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorNext).Status(
    'IDE: Quelltext formatieren')));
  mSettings.MultiCursor := True;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  Assert.IsFalse(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorNext).Disabled);
  Assert.AreEqual($4044, Integer(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorNext).Key));
  Assert.AreEqual($4044, Integer(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorSkip).Key));
  Assert.AreEqual($A049, Integer(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorLineEnds).Key));
  Assert.AreEqual($C026, Integer(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorAbove).Key));
  Assert.AreEqual($C028, Integer(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorBelow).Key));
  Assert.IsTrue(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorBelow).Priority);
  Assert.AreEqual(Ord(TAtlasKeyStatus.AtlasWins), Ord(EntryOf(mEntries, TAtlasKeyFunction.MultiCursorNext).Status(
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
  for mIndex := 0 to High(mEntries) do
  begin
    if mEntries[mIndex].Func = TAtlasKeyFunction.MultiCursorBelow then
    begin
      mEntries[mIndex].Key := $A028;
    end;
  end;
  mSaved := mSettings;
  TAtlasKeyEntry.ToSettings(mEntries, mSaved);
  Assert.AreEqual($A028, mSaved.MultiCursorBelowKey);
end;

/// <summary>Vorgaben mit allen abschaltbaren Tastenfunktionen aus.</summary>
function SwitchedOffSettings: TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.UnitSearchKey := $C055;
  Result.MethodToggle := False;
  Result.UnitSearchEnabled := False;
  Result.WelcomePageSearch := False;
  Result.BookmarksNamed := False;
  Result.GenerateMenu := False;
  Result.Notifications := False;
  Result.WelcomePageQuickActions := False;
  Result.Problems := False;
  Result.QuickOpen := False;
  Result.NavHistory := False;
  Result.Peek := False;
  Result.Breadcrumbs := False;
  Result.JumpToMatch := False;
  Result.GitGutter := False;
  Result.MoveLines := False;
  Result.CompleteStatement := False;
  Result.MultiCursor := False;
  Result.FormatCode := False;
  Result.ToggleBlockComment := False;
  Result.NewLineAround := False;
  Result.Unwrap := False;
  Result.SafeDelete := False;
  Result.ProblemsWindow := False;
  Result.DebugStepIntoTarget := False;
  Result.ExpressionType := False;
end;

/// <summary>Die Taste bleibt eingestellt; nur der Schalter ist aus.</summary>
procedure AssertSwitchedOffKeysStay(const ASettings: TAtlasPluginSettings; const AEntries: TArray<TAtlasKeyEntry>);
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := ASettings;
  // Die Taste bleibt eingestellt; nur der Schalter ist aus.
  Assert.AreEqual(cCtrlShiftUp, Integer(EntryOf(AEntries, TAtlasKeyFunction.MethodToggleUp).Key));
  // Unit ⇄ Testunit (#189) hat keinen eigenen Schalter (abschalten heißt Taste 0), bleibt also an.
  Assert.IsFalse(EntryOf(AEntries, TAtlasKeyFunction.TestUnit).Disabled);
  // Das Suchfeld ist auch mit abgeschalteter Willkommensseite aus.
  mSettings.WelcomePage := False;
  mSettings.WelcomePageSearch := True;
  Assert.IsTrue(EntryOf(TAtlasKeyEntry.AllFromSettings(mSettings), TAtlasKeyFunction.WelcomeSearch).Disabled,
    'Willkommensseite aus');
  // Ebenso die Schnellaktionen (#764).
  mSettings.WelcomePageQuickActions := True;
  Assert.IsTrue(EntryOf(TAtlasKeyEntry.AllFromSettings(mSettings), TAtlasKeyFunction.WelcomeQuickBuild).Disabled,
    'Willkommensseite aus');
end;

procedure TAtlasKeyMapTests.SwitchedOffFunctionsAreNoConflict;
var
  mSettings: TAtlasPluginSettings;
  mEntries: TArray<TAtlasKeyEntry>;
  mEntry: TAtlasKeyEntry;
begin
  mSettings := SwitchedOffSettings;
  mEntries := TAtlasKeyEntry.AllFromSettings(mSettings);
  for mEntry in mEntries do
  begin
    if mEntry.Func in [TAtlasKeyFunction.MethodToggleUp, TAtlasKeyFunction.MethodToggleDown,
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
      TAtlasKeyFunction.ProblemsWindow, TAtlasKeyFunction.StepIntoTarget,
      TAtlasKeyFunction.ExpressionType, TAtlasKeyFunction.SafeDelete, TAtlasKeyFunction.CheckFile,
      TAtlasKeyFunction.SectionAppend] then
    begin
      Assert.IsTrue(mEntry.Disabled, 'abgeschaltet: ' + IntToStr(Ord(mEntry.Func)));
      Assert.AreEqual(Ord(TAtlasKeyStatus.NoKey), Ord(mEntry.Status('IDE: Klassennavigation')),
        'kein Konflikt: ' + IntToStr(Ord(mEntry.Func)));
    end
    else
    begin
      Assert.IsFalse(mEntry.Disabled, 'an: ' + IntToStr(Ord(mEntry.Func)));
    end;
  end;
  AssertSwitchedOffKeysStay(mSettings, mEntries);
end;

procedure TAtlasKeyMapTests.UnitSearchTakesOverIdeKey;
var
  mSettings: TAtlasPluginSettings;
  mEntry: TAtlasKeyEntry;
  mItems: TArray<TAtlasKeyItem>;
  mPlugin: TAtlasKeyItem;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mEntry := EntryOf(TAtlasKeyEntry.AllFromSettings(mSettings), TAtlasKeyFunction.UnitSearchIde);
  Assert.AreEqual(cCtrlF12, Integer(mEntry.Key), 'Strg+F12 der IDE-Aktion „Units“');
  Assert.IsTrue(mEntry.Priority, 'bewusst übernommen');
  Assert.IsFalse(mEntry.Disabled);
  Assert.AreEqual(Ord(TAtlasKeyContext.Global), Ord(TAtlasKeyMap.ContextOf(TAtlasKeyFunction.UnitSearchIde)));
  Assert.AreEqual(Ord(TAtlasKeySource.Action), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.UnitSearchIde)));
  mSettings.UnitSearchReplaceIdeDialog := False;
  Assert.IsTrue(EntryOf(TAtlasKeyEntry.AllFromSettings(mSettings), TAtlasKeyFunction.UnitSearchIde).Disabled,
    'ohne Übernahme gehört Strg+F12 der IDE');
  // Eine Erweiterung belegt Strg+F12 im Editor: Dort gewinnt ihre Tastaturbelegung vor der Aktion, Atlas meldet es.
  mPlugin := TAtlasKeyItem.Create(cCtrlF12, 'Strg+F12', 'Tastaturbelegung des Editors',
    TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Plugin, 'CnWizards_D120', TAtlasKeyContext.Editor,
    TAtlasKeySource.Binding, 'Editor.' + IntToStr(cCtrlF12), 101));
  mPlugin.Effective := True;
  mItems := [AtlasKey(TAtlasKeyFunction.UnitSearchIde, cCtrlF12, True, True), mPlugin];
  TAtlasKeyMap.Analyze(mItems);
  Assert.IsTrue(mItems[0].Conflict);
  Assert.AreEqual(1, mItems[0].Winner);
  Assert.AreEqual(Ord(TAtlasKeyReason.EditorBinding), Ord(mItems[0].Reason));
  Assert.AreEqual(1, Integer(Length(TAtlasKeyMap.AtlasConflicts(mItems))));
end;

procedure TAtlasKeyMapTests.ParsesGermanAndEnglishShortCuts;
var
  mModifiers: Word;
begin
  Assert.AreEqual(cCtrlShiftP, Integer(TAtlasKeyMap.ParseShortCut('Strg+Umschalt+P', mModifiers)));
  Assert.AreEqual(cCtrlShiftP, Integer(TAtlasKeyMap.ParseShortCut(' ctrl + shift + p ', mModifiers)));
  Assert.AreEqual($800D, Integer(TAtlasKeyMap.ParseShortCut('Alt+Enter', mModifiers)));
  Assert.AreEqual($4020, Integer(TAtlasKeyMap.ParseShortCut('Strg+Leer', mModifiers)));
  Assert.AreEqual($C078, Integer(TAtlasKeyMap.ParseShortCut('Strg+Alt+F9', mModifiers)));
  Assert.AreEqual($74, Integer(TAtlasKeyMap.ParseShortCut('F5', mModifiers)), 'Funktionstaste allein');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('p', mModifiers)), 'ein Zeichen ist Textsuche');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('Strg+Alt', mModifiers)));
  Assert.AreEqual(TAtlasKeyMap.cScCtrl or TAtlasKeyMap.cScAlt, Integer(mModifiers), 'nur Umschalttasten');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('Strg+', mModifiers)));
  Assert.AreEqual(TAtlasKeyMap.cScCtrl, Integer(mModifiers));
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('Strg+Kompilieren', mModifiers)));
  Assert.AreEqual(0, Integer(mModifiers), 'kein Tastenname: Textsuche');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('P+Strg', mModifiers)), 'Taste nur am Ende');
  Assert.AreEqual(0, Integer(TAtlasKeyMap.ParseShortCut('', mModifiers)));
end;

procedure TAtlasKeyMapTests.QueryMatchesKeyModifiersAndText;
var
  mItem: TAtlasKeyItem;
begin
  mItem := IdeAction('Projekt compilieren', $4078, 1);
  mItem.KeyText := 'Strg+F9';
  mItem.Category := 'Projekt';
  Assert.IsTrue(TAtlasKeyQuery.Parse('').Matches(mItem));
  Assert.IsTrue(TAtlasKeyQuery.Parse('Ctrl+F9').Matches(mItem), 'englische Taste');
  Assert.IsFalse(TAtlasKeyQuery.Parse('Strg+Umschalt+F9').Matches(mItem));
  Assert.IsTrue(TAtlasKeyQuery.Parse('Strg').Matches(mItem), 'nur Umschalttaste');
  Assert.IsFalse(TAtlasKeyQuery.Parse('Alt+').Matches(mItem));
  Assert.IsTrue(TAtlasKeyQuery.Parse('compil').Matches(mItem), 'Befehl');
  Assert.IsTrue(TAtlasKeyQuery.Parse('PROJEKT').Matches(mItem), 'Kategorie, Großschreibung egal');
  Assert.IsTrue(TAtlasKeyQuery.Parse('ide').Matches(mItem), 'Herkunft');
  Assert.IsFalse(TAtlasKeyQuery.Parse('formular').Matches(mItem));
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
  A := TAtlasKeyItem.Create($4044, 'Taste', 'X', TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Plugin, 'CnWizards',
    TAtlasKeyContext.Editor, TAtlasKeySource.Binding, 'x', 1));
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
  mItems: TArray<TAtlasKeyItem>;
  mConflicts: TArray<Integer>;
begin
  // Strg+Umschalt+P: Befehlspalette ohne Vorrang gegen „Tastaturmakro abspielen“ (#494).
  mItems := [AtlasKey(TAtlasKeyFunction.Palette, cCtrlShiftP, False, False), IdeBinding('Makro abspielen', cCtrlShiftP),
    IdeAction('Speichern', $4053, 1)];
  mItems[1].Effective := True;
  TAtlasKeyMap.Analyze(mItems);
  Assert.IsTrue(mItems[0].Conflict);
  Assert.IsTrue(mItems[1].Conflict);
  Assert.IsFalse(mItems[2].Conflict);
  Assert.IsTrue(mItems[2].Wins, 'ohne Konflikt gewinnt die Belegung selbst');
  Assert.AreEqual(1, mItems[0].Winner);
  Assert.IsFalse(mItems[0].Wins);
  Assert.IsTrue(mItems[1].Wins);
  Assert.AreEqual(Ord(TAtlasKeyReason.AtlasYields), Ord(mItems[0].Reason));
  Assert.AreEqual(1, TAtlasKeyMap.PartnerOf(mItems, 0));
  Assert.AreEqual(-1, TAtlasKeyMap.PartnerOf(mItems, 2));
  Assert.AreEqual(2, TAtlasKeyMap.ConflictCount(mItems));
  mConflicts := TAtlasKeyMap.AtlasConflicts(mItems);
  Assert.AreEqual(1, Integer(Length(mConflicts)));
  Assert.AreEqual(0, mConflicts[0]);
  Assert.AreEqual('Makro abspielen (IDE)', mItems[1].Holder);
end;

procedure TAtlasKeyMapTests.AtlasWithPriorityWins;
var
  mItems: TArray<TAtlasKeyItem>;
begin
  mItems := [AtlasKey(TAtlasKeyFunction.Palette, cCtrlShiftP, True, True), IdeBinding('Makro abspielen', cCtrlShiftP)];
  mItems[0].Effective := True;
  TAtlasKeyMap.Analyze(mItems);
  Assert.IsTrue(mItems[0].Wins);
  Assert.AreEqual(0, mItems[1].Winner);
  Assert.AreEqual(Ord(TAtlasKeyReason.AtlasPriority), Ord(mItems[1].Reason));
  Assert.AreEqual(0, Integer(Length(TAtlasKeyMap.AtlasConflicts(mItems))), 'bewusst entschieden: nichts zu melden');
  // Ohne Abfrage der IDE entscheidet der Vorrang ebenso.
  mItems[0].Effective := False;
  TAtlasKeyMap.Analyze(mItems);
  Assert.IsTrue(mItems[0].Wins);
end;

procedure TAtlasKeyMapTests.EditorBindingBeatsAction;
var
  mItems: TArray<TAtlasKeyItem>;
begin
  // Die Aktion kam nach dem Belegen dazu: Atlas hält die Taste im Editor ohne Vorrang.
  mItems := [IdeAction('Suchen', cCtrlW, 3), AtlasKey(TAtlasKeyFunction.ExpandSelection, cCtrlW, False, True)];
  mItems[1].Effective := True;
  TAtlasKeyMap.Analyze(mItems);
  Assert.AreEqual(1, mItems[0].Winner, 'im Editor die Tastaturbelegung');
  Assert.AreEqual(Ord(TAtlasKeyReason.EditorBinding), Ord(mItems[0].Reason));
  Assert.IsTrue(mItems[1].Wins);
  Assert.AreEqual(1, Integer(Length(TAtlasKeyMap.AtlasConflicts(mItems))), 'ohne Vorrang offen');
end;

procedure TAtlasKeyMapTests.FirstActionWinsAmongActions;
var
  mItems: TArray<TAtlasKeyItem>;
begin
  mItems := [IdeAction('Neu', $404E, 7), TAtlasKeyItem.Create($404E, 'Taste', 'Fremd',
    TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Plugin, 'GExperts', TAtlasKeyContext.Global, TAtlasKeySource.Action,
    'GxNew', 3)),
    IdeAction('Neu 2', $404E, 9)];
  TAtlasKeyMap.Analyze(mItems);
  Assert.IsTrue(mItems[0].Conflict);
  Assert.AreEqual(1, mItems[0].Winner, 'erste Aktion der Liste');
  Assert.AreEqual(Ord(TAtlasKeyReason.FirstAction), Ord(mItems[0].Reason));
  Assert.IsTrue(mItems[1].Wins);
  Assert.AreEqual(0, Integer(Length(TAtlasKeyMap.AtlasConflicts(mItems))));
end;

procedure TAtlasKeyMapTests.DoubledAtlasKeyIsConflict;
var
  mItems: TArray<TAtlasKeyItem>;
begin
  // Absichtlich doppelt belegt: Befehlspalette auf Strg+W wie „Auswahl erweitern“.
  mItems := [AtlasKey(TAtlasKeyFunction.Palette, cCtrlW, False, True),
    AtlasKey(TAtlasKeyFunction.ExpandSelection, cCtrlW, False, True)];
  TAtlasKeyMap.Analyze(mItems);
  Assert.IsTrue(mItems[0].Conflict, 'rot');
  Assert.IsTrue(mItems[1].Conflict, 'rot');
  Assert.AreEqual(mItems[0].Winner, mItems[1].Winner, 'ein Gewinner für beide');
  Assert.AreEqual(Ord(TAtlasKeyReason.LastBinding), Ord(mItems[0].Reason));
  Assert.AreEqual(2, Integer(Length(TAtlasKeyMap.AtlasConflicts(mItems))));
end;

procedure TAtlasKeyMapTests.WelcomeSearchWinsOnlyOnWelcomePage;
var
  mItems: TArray<TAtlasKeyItem>;
begin
  mItems := [IdeAction('Inkrementelle Suche', cCtrlE, 1), AtlasKey(TAtlasKeyFunction.WelcomeSearch, cCtrlE, True, True),
    IdeBinding('Editor-Suche', cCtrlE)];
  TAtlasKeyMap.Analyze(mItems);
  Assert.IsTrue(mItems[1].Wins);
  Assert.AreEqual(Ord(TAtlasKeyReason.OwnWindow), Ord(mItems[1].Reason));
  Assert.AreEqual(1, mItems[0].Winner, 'die Aktion verliert dort, wo sich beide treffen');
  Assert.IsFalse(mItems[2].Conflict, 'Editor und Willkommensseite überschneiden sich nicht');
  Assert.AreEqual(0, Integer(Length(TAtlasKeyMap.AtlasConflicts(mItems))));
end;

procedure TAtlasKeyMapTests.EffectivePluginBindingWins;
var
  mItems: TArray<TAtlasKeyItem>;
begin
  // Eine Erweiterung hat sich nach Atlas angemeldet: Ihre Belegung ist wirksam, auch gegen den Vorrang.
  mItems := [AtlasKey(TAtlasKeyFunction.ShrinkSelection, $6057, True, True), TAtlasKeyItem.Create($6057, 'Taste',
    'Tastaturbelegung', TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Plugin, 'CnWizards_D120', TAtlasKeyContext.Editor,
    TAtlasKeySource.Binding, 'Editor.24663', 101))];
  mItems[1].Effective := True;
  TAtlasKeyMap.Analyze(mItems);
  Assert.AreEqual(1, mItems[0].Winner);
  Assert.AreEqual(Ord(TAtlasKeyReason.LastBinding), Ord(mItems[0].Reason));
  Assert.AreEqual(1, Integer(Length(TAtlasKeyMap.AtlasConflicts(mItems))), 'Vorrang ohne Wirkung bleibt offen');
end;

procedure TAtlasKeyMapTests.FilterSortsAndKeepsConflicts;
var
  mItems: TArray<TAtlasKeyItem>;
  mShown: TArray<Integer>;
begin
  mItems := [IdeAction('Zeta', $4058, 1), IdeAction('Alpha', $4041, 2),
    AtlasKey(TAtlasKeyFunction.Palette, cCtrlShiftP, False, False), IdeBinding('Makro', cCtrlShiftP)];
  mItems[0].KeyText := 'Strg+X';
  mItems[1].KeyText := 'Strg+A';
  mItems[2].KeyText := 'Strg+Umschalt+P';
  mItems[3].KeyText := 'Strg+Umschalt+P';
  TAtlasKeyMap.Analyze(mItems);
  mShown := TAtlasKeyMap.Filter(mItems, '', False);
  Assert.AreEqual(4, Integer(Length(mShown)));
  Assert.AreEqual(1, mShown[0], 'nach Tastentext');
  Assert.AreEqual(0, mShown[3]);
  mShown := TAtlasKeyMap.Filter(mItems, '', True);
  Assert.AreEqual(2, Integer(Length(mShown)), 'nur Konflikte');
  Assert.AreEqual(2, mShown[0], 'Atlas vor Makro (Befehl)');
  mShown := TAtlasKeyMap.Filter(mItems, 'Strg+Umschalt+P', False);
  Assert.AreEqual(2, Integer(Length(mShown)));
  mShown := TAtlasKeyMap.Filter(mItems, 'alpha', False);
  Assert.AreEqual(1, Integer(Length(mShown)));
  Assert.AreEqual(1, mShown[0]);
end;

procedure TAtlasKeyMapTests.OriginFollowsModule;
var
  mName: string;
begin
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Atlas), Ord(TAtlasKeyMap.OriginOfModule('C:\Atlas\Atlas.IDE.Expert.bpl',
    'C:\Studio\37.0\bin\', 'C:\Atlas\Atlas.IDE.Expert.bpl', mName)));
  Assert.AreEqual('Atlas', mName);
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Ide), Ord(TAtlasKeyMap.OriginOfModule('C:\Studio\37.0\bin\coreide370.bpl',
    'C:\Studio\37.0\bin\', 'C:\Atlas\Atlas.IDE.Expert.bpl', mName)));
  Assert.AreEqual('IDE', mName);
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Ide), Ord(TAtlasKeyMap.OriginOfModule('c:\studio\37.0\BIN\x.bpl',
    'C:\Studio\37.0\bin\', '', mName)), 'Groß-/Kleinschreibung egal');
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Plugin), Ord(TAtlasKeyMap.OriginOfModule(
    'C:\Users\Marco\Documents\Bpl\CnWizards_D120.dll', 'C:\Studio\37.0\bin\', 'C:\Atlas\Atlas.IDE.Expert.bpl',
    mName)));
  Assert.AreEqual('CnWizards_D120', mName, 'ohne Pfad und Benutzernamen');
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Ide), Ord(TAtlasKeyMap.OriginOfModule('', 'C:\Studio\37.0\bin\', '', mName)),
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
  mHtml: string;
begin
  mHtml := TAtlasKeyMap.Html('de', 'Atlas - Tastenkuerzel', 'Stand: heute', 'Drucken', ['Taste', 'Befehl'],
    [TAtlasKeyHtmlRow.Create(['Strg+<P>', 'Suchen & Ersetzen'], True),
    TAtlasKeyHtmlRow.Create(['Strg+S', 'Speichern "alles"'], False)]);
  Assert.StartsWith('<!DOCTYPE html>', mHtml);
  Assert.Contains(mHtml, '<html lang="de">');
  Assert.Contains(mHtml, '<meta charset="utf-8">');
  Assert.Contains(mHtml, '<title>Atlas - Tastenkuerzel</title>');
  Assert.Contains(mHtml, '<p class="sub">Stand: heute</p>');
  Assert.Contains(mHtml, 'window.print()');
  Assert.Contains(mHtml, '@media print');
  Assert.Contains(mHtml, '<th>Taste</th><th>Befehl</th>');
  Assert.Contains(mHtml, '<tr class="conflict"><td class="key">Strg+&lt;P&gt;</td><td>Suchen &amp; Ersetzen</td></tr>');
  Assert.Contains(mHtml, '<tr><td class="key">Strg+S</td><td>Speichern &quot;alles&quot;</td></tr>');
  Assert.Contains(mHtml, 'tr.conflict td{color:#cf222e}');
  Assert.AreEqual('a&#39;b', TAtlasKeyMap.HtmlEscape('a''b'));
  // Ohne Unterzeile und Druckknopf.
  mHtml := TAtlasKeyMap.Html('en', 'T', '', '', ['K'], nil);
  Assert.DoesNotContain(mHtml, 'class="sub"');
  Assert.DoesNotContain(mHtml, 'window.print()');
end;

procedure TAtlasKeyMapTests.CheckFileKeyFollowsProblems;
var
  mSettings, mSaved: TAtlasPluginSettings;
  mEntry: TAtlasKeyEntry;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mEntry := EntryOf(TAtlasKeyEntry.AllFromSettings(mSettings), TAtlasKeyFunction.CheckFile);
  Assert.AreEqual($E050, Integer(mEntry.Key), 'Strg+Umschalt+Alt+P');
  Assert.IsFalse(mEntry.Disabled);
  Assert.AreEqual('Atlas.CheckFile', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.CheckFile));
  Assert.AreEqual(Ord(TAtlasKeySource.Binding), Ord(TAtlasKeyMap.SourceOf(TAtlasKeyFunction.CheckFile)));
  mSettings.Problems := False;
  mEntry := EntryOf(TAtlasKeyEntry.AllFromSettings(mSettings), TAtlasKeyFunction.CheckFile);
  Assert.IsTrue(mEntry.Disabled, 'ohne Prüfregeln kein Konflikt');
  mSettings.Problems := True;
  mSettings.CheckFileKey := $C04D;
  mSaved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(TAtlasKeyEntry.AllFromSettings(mSettings), mSaved);
  Assert.AreEqual($C04D, mSaved.CheckFileKey, 'Strg+Alt+M');
end;

procedure TAtlasKeyMapTests.SectionAppendKeyFollowsSetting;
var
  mSettings, mSaved: TAtlasPluginSettings;
  mEntry: TAtlasKeyEntry;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mEntry := EntryOf(TAtlasKeyEntry.AllFromSettings(mSettings), TAtlasKeyFunction.SectionAppend);
  Assert.AreEqual(0, Integer(mEntry.Key), 'ohne Vorgabe');
  Assert.IsFalse(mEntry.Disabled);
  Assert.AreEqual('Atlas.SectionAppend', TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.SectionAppend));
  mSettings.BreadcrumbsSectionAppend := False;
  mEntry := EntryOf(TAtlasKeyEntry.AllFromSettings(mSettings), TAtlasKeyFunction.SectionAppend);
  Assert.IsTrue(mEntry.Disabled, 'aus = kein Konflikt');
  mSettings.BreadcrumbsSectionAppend := True;
  mSettings.SectionAppendKey := $C04E;
  mSaved := TAtlasPluginSettings.Defaults;
  TAtlasKeyEntry.ToSettings(TAtlasKeyEntry.AllFromSettings(mSettings), mSaved);
  Assert.AreEqual($C04E, mSaved.SectionAppendKey, 'Strg+Alt+N');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyMapTests);

end.
