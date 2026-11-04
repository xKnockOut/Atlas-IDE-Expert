unit Atlas.IDE.Commands.KeyMap;

// Tastenkürzel-Übersicht mit Konflikterkennung (#520) in der IDE:
// - Collect sammelt alle Belegungen: Aktionen aus INTAServices.ActionList
//   (Taste und Zweittasten, Herkunft über das Modul des OnExecute-Handlers bzw.
//   des Besitzers: Ordner der IDE = IDE, Atlas-Package = Atlas, sonst die
//   Erweiterung mit ihrem Package-Namen), die Tasten von Atlas
//   (TAtlasKeyEntry.AllFromSettings) und Tastaturbelegungen des Editors über
//   IOTAKeyboardServices.LookupKeyBinding, soweit auslesbar: Die IDE nennt je
//   Taste nur die wirksame Belegung und deren Modul, keinen Befehlsnamen.
//   Abgefragt werden die Tasten aller Einträge, die bekannten Editor-Tasten
//   (#494) und alle Kombinationen mit Strg oder Alt sowie F1–F12.
//   TAtlasKeyMap.Analyze wertet aus.
// - Fenster „Atlas – Tastenkürzel“ (nicht modal) aus Menü Atlas ›
//   „Tastenkürzel-Übersicht…“ und Befehlspalette (keys.overview, Befehl
//   Atlas.KeyOverview); Export als HTML nach
//   %LOCALAPPDATA%\Atlas\Tastenkuerzel.html, geöffnet im Browser.
// - Beim Start (keys.startupCheck) prüft Atlas nach StartDelayMs seine eigenen
//   Tasten und meldet jeden Konflikt einmal in der Meldungsansicht, mit Verweis
//   auf Übersicht und Einstellungen; was #494 beim Belegen schon gemeldet hat,
//   nicht noch einmal. Nach Package-Änderungen prüft CheckNow erneut.
// - Gemeinsame Quelle für die Einrichtung (#625, SetupKeys), die Taste eines
//   Atlas-Befehls in der Befehlspalette (#502, AtlasShortCut) und spätere
//   Einstiege (#600 Tastenkürzel-Tipps, #766 Knopf auf der Willkommensseite:
//   ShowWindow mit Suchtext).
// - Spalte „Selten per Tastatur“ (#600): Collect übernimmt je Zeile die Zählung
//   der Tastenkürzel-Tipps (TAtlasIdeCommandUsage.UsageOf), Aktionen über ihren
//   Namen, Atlas-Tasten über den Befehl der Palette.
// - Abgeschaltete Funktionen (TAtlasKeyEntry.Disabled, etwa #775 aus oder
//   „Units suchen“ aus) bekommen keine Zeile und sind kein Konflikt.
// - Strg+F12 (#777): Die IDE-Aktion „Units“, an die sich „Units suchen“ hängt
//   (das Modul Suche meldet sie über IAtlasTakenActions, #1455), erscheint bei unitSearch.enabled und
//   unitSearch.replaceIdeDialog als Atlas-Zeile mit ihren echten Tasten, sonst
//   als Aktion der IDE (ihr Handler liegt dann zwar in Atlas, ruft aber nur
//   den Dialog der IDE).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap,
  Atlas.Core.Setup.Checklist,
  Atlas.UI.Commands.KeyMap,
  Atlas.Core.Commands.Palette;

type
  TAtlasIdeKeyMap = class
  public const
    CommandId = 'Atlas.KeyOverview';
    /// <summary>Wartezeit nach dem Laden, bis die übrigen Packages ihre Tasten angemeldet haben.</summary>
    StartDelayMs = 3000;
    ExportFileName = 'Tastenkuerzel.html';
  private class var
    FInstance: TAtlasIdeKeyMap;
  private
    FWindow: TAtlasKeyMapWindow;
    FTimer: TTimer;
    procedure TimerTick(Sender: TObject);
    procedure Refresh;
    procedure ExportHtml;
    procedure OpenKeyConflicts;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Die laufende Übersicht oder nil.</summary>
    class function Instance: TAtlasIdeKeyMap; static;
    /// <summary>Alle Belegungen aus IDE, Atlas und anderen Erweiterungen, ausgewertet (Hauptthread).</summary>
    class function Collect: TArray<TAtlasKeyItem>; static;
    /// <summary>TAtlasKeyEntry.AllFromSettings mit den aktuellen Einstellungen; bei Strg+F12 (#777) die Taste,
    /// die die übernommene Aktion der IDE wirklich hat (0, wenn Atlas sich nicht anhängen konnte).</summary>
    class function AtlasEntries: TArray<TAtlasKeyEntry>; static;
    /// <summary>Jede Atlas-Taste mit fremder Belegung für die Einrichtung (#625); Vorrang zählt nur, wenn Atlas
    /// die Taste auch wirklich hat.</summary>
    class function SetupKeys: TArray<TAtlasSetupKey>; static;
    /// <summary>Taste eines Atlas-Befehls der Palette als Text, wenn Atlas sie belegt; sonst ''.</summary>
    class function AtlasShortCut(const ACommandId: string): string; static;
    /// <summary>Ziel des HTML-Exports.</summary>
    class function ExportFile: string; static;
    /// <summary>Fenster zeigen und neu einlesen; Suche und Filter bleiben.</summary>
    procedure ShowWindow; overload;
    /// <summary>Fenster zeigen und nach AQuery suchen (Taste oder Text).</summary>
    procedure ShowWindow(const AQuery: string); overload;
    /// <summary>Fenster zeigen, Suche leeren: alle Kürzel (Link „Alle Kürzel“ der Tastenkürzel-Tipps, #600).
    /// </summary>
    procedure ShowAll;
    /// <summary>„Tastenkürzel-Übersicht…“ in der Befehlspalette, sichtbar nach keys.overview.</summary>
    procedure RegisterCommands(const ARegistry: IAtlasCommandRegistry);
    /// <summary>Package geladen: nach StartDelayMs die eigenen Tasten prüfen (keys.startupCheck).</summary>
    procedure CheckAtStart;
    /// <summary>Eigene Tasten prüfen und neue Konflikte melden; offenes Fenster neu einlesen.</summary>
    procedure CheckNow;
    procedure ThemeChanged;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.IOUtils,
  System.Generics.Collections,
  Vcl.ActnList,
  Vcl.Menus,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Keys,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.IDE.Commands.Usage,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions;

const
  KeyIdPrefix = 'Atlas.Key.';
  // Reihenfolge, in der die Komposition die Tasten anmeldet (RebindKeys); bei mehreren Atlas-Belegungen
  // derselben Taste gilt die zuletzt angemeldete. 3 = Editorbefehle (eine Bindung); Strg+F12 (#777) ist keine
  // Bindung, sondern eine Aktion und bekommt ihren Platz in der Aktionsliste.
  BindOrder: array[TAtlasKeyFunction] of Integer = (1, 2, 4, 5, 6, 7, 3, 3, 3, 3, 3, 3, 3, 8, 3, 3, 3, 3, 0, 3, 3, 3,
    8, 8, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    // Mehrfachmarken (#589): Editorbefehle.
    3, 3, 3, 3, 3,
    // Atlas-Suche (#877, #878): Editorbefehle.
    3, 3, 3, 3,
    // Formatieren (#43): Editorbefehl.
    3,
    // Blockkommentar umschalten (#703): Editorbefehl.
    3,
    // Neue Zeile ober- oder unterhalb (#700): Editorbefehle.
    3, 3,
    // Umschließung entfernen (#657): Editorbefehl.
    3,
    // Fenster „Atlas-Prüfung“ (#909): Editorbefehl.
    3,
    // Abschnittsknöpfe der Editorleiste (#1101): Editorbefehle.
    3, 3,
    // Schnelle Lesezeichen (#1104): Editorbefehle.
    3, 3, 3, 3, 3,
    // Ersetzen in der Atlas-Suche (#893): Editorbefehl.
    3,
    // Gezielt hineinspringen (#836): Editorbefehl.
    3,
    // Typ des markierten Ausdrucks (#689): Editorbefehl.
    3,
    // Sicher löschen (#716): Editorbefehl.
    3,
    // Issue anlegen (#1268): Editorbefehl.
    3,
    // Komponenten suchen (#1442): keine Bindung, TAtlasKeyHook nur im Designer.
    0);

type
  /// <summary>Herkunft je Modul, einmal ermittelt.</summary>
  TOrigins = class
  private type
    TOrigin = record
      Origin: TAtlasKeyOrigin;
      Name: string;
    end;
  private
    FCache: TDictionary<HMODULE, TOrigin>;
    FIdeFolder: string;
    FAtlasModule: string;
  public
    constructor Create;
    destructor Destroy; override;
    function AtlasModuleOf(AModule: HMODULE): string;
    function OfModule(AModule: HMODULE; out AName: string): TAtlasKeyOrigin;
    function OfAddress(AAddress: Pointer; out AName: string): TAtlasKeyOrigin;
  end;

constructor TOrigins.Create;
begin
  inherited Create;
  FCache := TDictionary<HMODULE, TOrigin>.Create;
  FIdeFolder := ExtractFilePath(ParamStr(0));
  FAtlasModule := GetModuleName(HInstance);
end;

destructor TOrigins.Destroy;
begin
  FCache.Free;
  inherited;
end;

/// <summary>Regel 8 (#1456): Tasten aus Base und aus jedem angemeldeten Modul (eigenes Package) gelten als
/// Atlas-Tasten; dafür bekommt OriginOfModule den Namen des Moduls selbst, sonst den von Base.</summary>
function TOrigins.AtlasModuleOf(AModule: HMODULE): string;
var
  mRegistry: IAtlasModuleRegistry;
begin
  Result := FAtlasModule;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry <> nil) and mRegistry.IsModuleHandle(NativeUInt(AModule)) then
  begin
    Result := GetModuleName(AModule);
  end;
end;

function TOrigins.OfModule(AModule: HMODULE; out AName: string): TAtlasKeyOrigin;
var
  Entry: TOrigin;
begin
  if not FCache.TryGetValue(AModule, Entry) then
  begin
    if AModule = 0 then
    begin
      Entry.Origin := TAtlasKeyOrigin.Ide;
      Entry.Name := TAtlasKeyMap.IdeName;
    end
    else
    begin
      Entry.Origin := TAtlasKeyMap.OriginOfModule(GetModuleName(AModule), FIdeFolder, AtlasModuleOf(AModule),
        Entry.Name);
    end;
    FCache.Add(AModule, Entry);
  end;
  AName := Entry.Name;
  Result := Entry.Origin;
end;

function TOrigins.OfAddress(AAddress: Pointer; out AName: string): TAtlasKeyOrigin;
begin
  if AAddress = nil then
  begin
    Result := OfModule(0, AName);
  end
  else
  begin
    Result := OfModule(HMODULE(FindHInstance(AAddress)), AName);
  end;
end;

function IndexOfFunc(const AItems: TArray<TAtlasKeyItem>; AFunc: TAtlasKeyFunction): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(AItems) do
  begin
    if (AItems[Index].Origin = TAtlasKeyOrigin.Atlas) and (AItems[Index].Id = KeyIdPrefix + IntToStr(Ord(AFunc))) then
    begin
      Exit(Index);
    end;
  end;
end;

/// <summary>Die Tasten von Atlas; ohne eigene Taste (Vervollständigung über Strg+Leer der IDE) oder abgeschaltet
/// keine Zeile. Strg+F12 (#777) kommt mit den Aktionen (AddActions).</summary>
procedure AddAtlasKeys(AItems: TList<TAtlasKeyItem>; const AEntries: TArray<TAtlasKeyEntry>);
var
  Entry: TAtlasKeyEntry;
  Item: TAtlasKeyItem;
begin
  for Entry in AEntries do
  begin
    if (Entry.Key = 0) or Entry.Disabled or (TAtlasKeyMap.SourceOf(Entry.Func) = TAtlasKeySource.Action) then
    begin
      Continue;
    end;
    Item := TAtlasKeyItem.Create(Entry.Key, ShortCutToText(TShortCut(Entry.Key)),
      TAtlasKeyMapWindow.FunctionCaption(Entry.Func), TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Atlas,
      TAtlasKeyMap.AtlasName, TAtlasKeyMap.ContextOf(Entry.Func), TAtlasKeyMap.SourceOf(Entry.Func),
      KeyIdPrefix + IntToStr(Ord(Entry.Func)), BindOrder[Entry.Func]));
    Item.Category := TAtlasKeyMap.AtlasName;
    Item.Func := Entry.Func;
    Item.Priority := Entry.Priority;
    if Item.Source = TAtlasKeySource.Window then
    begin
      // Abgeschaltet (Willkommensseite oder Suchfeld aus) kommt es oben gar nicht an.
      Item.Active := True;
    end
    else
    begin
      // Wie beim Belegen (#494): frei oder mit Vorrang.
      Item.Active := TAtlasKeyConflicts.ShouldBind(Entry.Key, TAtlasIdeKeys.Owner(Entry.Key), Entry.Priority);
    end;
    AItems.Add(Item);
  end;
end;

/// <summary>Namen der Aktionen, die laufende Module für AFunc übernommen haben, in der Reihenfolge der Module.
/// </summary>
function TakenNames(AFunc: TAtlasKeyFunction): TArray<string>;
var
  mItem: IInterface;
  mSource: IAtlasTakenActions;
  mTaken: TAtlasTakenAction;
begin
  Result := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTakenActions) do
  begin
    if not Supports(mItem, IAtlasTakenActions, mSource) then
    begin
      Continue;
    end;
    for mTaken in mSource.TakenActions do
    begin
      if (mTaken.Func = AFunc) and (mTaken.ActionName <> '') then
      begin
        Result := Result + [mTaken.ActionName];
      end;
    end;
  end;
end;

/// <summary>Aktion namens AName in AList; nil ohne.</summary>
function ActionNamed(AList: TCustomActionList; const AName: string): TBasicAction;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AList.ActionCount - 1 do
  begin
    if SameText(AList.Actions[mIndex].Name, AName) then
    begin
      Result := AList.Actions[mIndex];
      Break;
    end;
  end;
end;

/// <summary>Aktion der IDE, die ein laufendes Modul für AFunc übernommen hat; nil ohne.</summary>
function TakenAction(AFunc: TAtlasKeyFunction): TBasicAction;
var
  mServices: INTAServices;
  mName: string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mName in TakenNames(AFunc) do
  begin
    Result := ActionNamed(mServices.ActionList, mName);
    if Result <> nil then
    begin
      Break;
    end;
  end;
end;

procedure AddAction(AItems: TList<TAtlasKeyItem>; AOrigins: TOrigins; AAction: TCustomAction;
  AShortCut: TShortCut; AOrder: Integer; AHooked: Boolean);
var
  Origin: TAtlasKeyOrigin;
  Name, Caption: string;
  Item: TAtlasKeyItem;
begin
  // Die Aktion „Units“ ohne Übernahme durch Atlas (#777): Der Handler liegt in Atlas, ruft aber den Dialog der IDE.
  if AHooked then
  begin
    Origin := TAtlasKeyOrigin.Ide;
    Name := TAtlasKeyMap.IdeName;
  end
  else if SameText(AAction.Category, 'Atlas') or AAction.Category.StartsWith('Atlas.', True) then
  begin
    Origin := TAtlasKeyOrigin.Atlas;
    Name := TAtlasKeyMap.AtlasName;
  end
  // Der Handler liegt im Modul dessen, der die Aktion angelegt hat; ohne Handler zählt der Besitzer.
  else if Assigned(AAction.OnExecute) then
  begin
    Origin := AOrigins.OfAddress(TMethod(AAction.OnExecute).Code, Name);
  end
  else if AAction.Owner <> nil then
  begin
    Origin := AOrigins.OfAddress(Pointer(AAction.Owner.ClassType), Name);
  end
  else
  begin
    Origin := AOrigins.OfAddress(Pointer(AAction.ClassType), Name);
  end;
  Caption := TAtlasCommandPalette.CleanCaption(AAction.Caption);
  if Caption = '' then
  begin
    Caption := AAction.Name;
  end;
  Item := TAtlasKeyItem.Create(Word(AShortCut), ShortCutToText(AShortCut), Caption, TAtlasKeyProvenance.Create(Origin,
    Name, TAtlasKeyMap.ContextOfCategory(AAction.Category), TAtlasKeySource.Action, AAction.Name, AOrder));
  Item.Category := AAction.Category;
  AItems.Add(Item);
end;

/// <summary>Die von „Units suchen“ übernommene Aktion „Units“ (#777) als Atlas-Taste: bewusst übernommen, also
/// mit Vorrang; Platz in der Aktionsliste wie die Aktion selbst.</summary>
procedure AddUnitSearchAction(AItems: TList<TAtlasKeyItem>; AAction: TCustomAction; AShortCut: TShortCut;
  AOrder: Integer);
const
  Func = TAtlasKeyFunction.UnitSearchIde;
var
  Item: TAtlasKeyItem;
begin
  Item := TAtlasKeyItem.Create(Word(AShortCut), ShortCutToText(AShortCut), TAtlasKeyMapWindow.FunctionCaption(Func),
    TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Atlas, TAtlasKeyMap.AtlasName, TAtlasKeyMap.ContextOf(Func),
    TAtlasKeyMap.SourceOf(Func), KeyIdPrefix + IntToStr(Ord(Func)), AOrder));
  Item.Category := AAction.Category;
  Item.Func := Func;
  Item.Priority := True;
  AItems.Add(Item);
end;

type
  /// <summary>Was beim Durchgehen der Aktionen für jede Taste gleich bleibt.</summary>
  TActionScan = record
    Items: TList<TAtlasKeyItem>;
    Origins: TOrigins;
    /// <summary>Von „Units suchen“ übernommene Aktion „Units“ (#777); nil ohne.</summary>
    Hooked: TBasicAction;
    /// <summary>Übernahme eingeschaltet (Taste UnitSearchIde nicht abgeschaltet).</summary>
    TakenOver: Boolean;
  end;

/// <summary>Taste der Aktion oder, bei der übernommenen Aktion „Units“ (#777) und eingeschalteter Übernahme, die
/// Atlas-Zeile dafür.</summary>
procedure AddActionKey(const AScan: TActionScan; AAction: TCustomAction; AShortCut: TShortCut; AOrder: Integer);
var
  mHooked: Boolean;
begin
  mHooked := (AScan.Hooked <> nil) and (AAction = AScan.Hooked);
  if mHooked and AScan.TakenOver then
  begin
    AddUnitSearchAction(AScan.Items, AAction, AShortCut, AOrder);
  end
  else
  begin
    AddAction(AScan.Items, AScan.Origins, AAction, AShortCut, AOrder, mHooked);
  end;
end;

/// <summary>Erste und weitere Tasten einer Aktion; doppelte der ersten zählen nicht noch einmal.</summary>
procedure AddActionKeys(const AScan: TActionScan; AAction: TCustomAction; AOrder: Integer);
var
  mSecondary: Integer;
  mKey: TShortCut;
begin
  if AAction.ShortCut <> 0 then
  begin
    AddActionKey(AScan, AAction, AAction.ShortCut, AOrder);
  end;
  for mSecondary := 0 to AAction.SecondaryShortCuts.Count - 1 do
  begin
    mKey := AAction.SecondaryShortCuts.ShortCuts[mSecondary];
    if (mKey <> 0) and (mKey <> AAction.ShortCut) then
    begin
      AddActionKey(AScan, AAction, mKey, AOrder);
    end;
  end;
end;

/// <summary>Übernahme der Aktion „Units“ eingeschaltet: Taste UnitSearchIde nicht abgeschaltet.</summary>
function UnitSearchTakenOver(const AEntries: TArray<TAtlasKeyEntry>): Boolean;
var
  mEntry: TAtlasKeyEntry;
begin
  Result := False;
  for mEntry in AEntries do
  begin
    if mEntry.Func = TAtlasKeyFunction.UnitSearchIde then
    begin
      Result := not mEntry.Disabled;
    end;
  end;
end;

procedure AddActions(AItems: TList<TAtlasKeyItem>; AOrigins: TOrigins; const AEntries: TArray<TAtlasKeyEntry>);
var
  Services: INTAServices;
  Index: Integer;
  Scan: TActionScan;
begin
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
  begin
    Exit;
  end;
  Scan.Items := AItems;
  Scan.Origins := AOrigins;
  Scan.Hooked := TakenAction(TAtlasKeyFunction.UnitSearchIde);
  Scan.TakenOver := UnitSearchTakenOver(AEntries);
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    if Services.ActionList.Actions[Index] is TCustomAction then
    begin
      AddActionKeys(Scan, TCustomAction(Services.ActionList.Actions[Index]), Index);
    end;
  end;
end;

/// <summary>Bekannte Belegungen der Standard-Tastaturbelegung (#494), die keine Aktionen sind.</summary>
procedure AddKnownIdeKeys(AItems: TList<TAtlasKeyItem>);
var
  Known: TAtlasKeyOwner;
  Command: string;
begin
  for Known in TAtlasKeyConflicts.KnownIdeKeys do
  begin
    Command := Known.Owner;
    if Command.StartsWith('IDE: ') then
    begin
      Command := Copy(Command, 6, MaxInt);
    end;
    AItems.Add(TAtlasKeyItem.Create(Known.ShortCut, ShortCutToText(TShortCut(Known.ShortCut)), Command,
      TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Ide, TAtlasKeyMap.IdeName, TAtlasKeyContext.Editor,
      TAtlasKeySource.Binding, 'Editor.' + IntToStr(Known.ShortCut), 0)));
  end;
end;

/// <summary>Abzufragende Tasten: alle Einträge, dazu Strg/Alt mit Buchstaben, Ziffern, Leer und Enter sowie
/// F1–F12 mit jeder Umschaltung.</summary>
function ProbeKeys(const AItems: TArray<TAtlasKeyItem>): TArray<Word>;
const
  Modifiers: array[0..5] of Word = (TAtlasKeyMap.scCtrl, TAtlasKeyMap.scCtrl or TAtlasKeyMap.scShift,
    TAtlasKeyMap.scCtrl or TAtlasKeyMap.scAlt, TAtlasKeyMap.scCtrl or TAtlasKeyMap.scAlt or TAtlasKeyMap.scShift,
    TAtlasKeyMap.scAlt, TAtlasKeyMap.scAlt or TAtlasKeyMap.scShift);
var
  Seen: TDictionary<Word, Boolean>;
  Item: TAtlasKeyItem;
  Modifier: Word;
  Key: Integer;

  procedure Add(AKey: Word);
  begin
    if (AKey <> 0) and not Seen.ContainsKey(AKey) then
    begin
      Seen.Add(AKey, True);
      Result := Result + [AKey];
    end;
  end;

begin
  Result := nil;
  Seen := TDictionary<Word, Boolean>.Create;
  try
    for Item in AItems do
    begin
      Add(Item.ShortCut);
    end;
    for Modifier in Modifiers do
    begin
      for Key := Ord('A') to Ord('Z') do
      begin
        Add(Modifier or Word(Key));
      end;
      for Key := Ord('0') to Ord('9') do
      begin
        Add(Modifier or Word(Key));
      end;
      Add(Modifier or $20);
      Add(Modifier or $0D);
    end;
    for Key := $70 to $7B do
    begin
      Add(Word(Key));
      Add(TAtlasKeyMap.scShift or Word(Key));
      for Modifier in Modifiers do
      begin
        Add(Modifier or Word(Key));
      end;
    end;
  finally
    Seen.Free;
  end;
end;

/// <summary>Wirksame Tastaturbelegung des Editors für AKey: Code ihres Handlers; False ohne.</summary>
function LookupBinding(const AKeyboard: IOTAKeyboardServices; AKey: Word; out ACode: Pointer): Boolean;
var
  Binding: TKeyBindingRec;
begin
  ACode := nil;
  Binding := Default(TKeyBindingRec);
  try
    Result := AKeyboard.LookupKeyBinding([TShortCut(AKey)], Binding);
  except
    // Eine Taste, die die IDE nicht auflösen kann, zählt als frei.
    Result := False;
  end;
  if Result then
  begin
    ACode := TMethod(Binding.KeyProc).Code;
  end;
  Result := Result and (ACode <> nil);
end;

/// <summary>Atlas-Belegung von AKey als wirksam markieren; nur eindeutig, wenn genau eine Atlas-Belegung die Taste hat.
/// </summary>
procedure MarkAtlasBinding(AItems: TList<TAtlasKeyItem>; AKey: Word);
var
  mIndex, mFound, mCount: Integer;
  mItem: TAtlasKeyItem;
begin
  mFound := -1;
  mCount := 0;
  for mIndex := 0 to AItems.Count - 1 do
  begin
    if (AItems[mIndex].Origin = TAtlasKeyOrigin.Atlas) and (AItems[mIndex].Source = TAtlasKeySource.Binding) and
      (AItems[mIndex].ShortCut = AKey) then
    begin
      mFound := mIndex;
      Inc(mCount);
    end;
  end;
  if mCount = 1 then
  begin
    mItem := AItems[mFound];
    mItem.Effective := True;
    mItem.Active := True;
    AItems[mFound] := mItem;
  end;
end;

/// <summary>Neue, wirksame Zeile für eine Belegung des Editors.</summary>
procedure AddEditorBinding(AItems: TList<TAtlasKeyItem>; AKey: Word; AOrigin: TAtlasKeyOrigin; const AName: string;
  AOrder: Integer);
var
  mItem: TAtlasKeyItem;
begin
  mItem := TAtlasKeyItem.Create(AKey, ShortCutToText(TShortCut(AKey)),
    TAtlasStrings.Text(TAtlasTextId.KeyMapEditorBinding), TAtlasKeyProvenance.Create(AOrigin, AName,
    TAtlasKeyContext.Editor, TAtlasKeySource.Binding, 'Editor.' + IntToStr(AKey), AOrder));
  mItem.Effective := True;
  AItems.Add(mItem);
end;

/// <summary>Belegung der IDE auf AKey: vorhandene IDE-Zeile wirksam; sonst eine neue Zeile, wenn die Taste auch
/// Atlas oder einer Erweiterung gehört.</summary>
procedure MarkIdeBinding(AItems: TList<TAtlasKeyItem>; AKey: Word; AOrder: Integer);
var
  mIndex, mFound: Integer;
  mShared: Boolean;
  mItem: TAtlasKeyItem;
begin
  mFound := -1;
  mShared := False;
  for mIndex := 0 to AItems.Count - 1 do
  begin
    if AItems[mIndex].ShortCut <> AKey then
    begin
      Continue;
    end;
    if (AItems[mIndex].Origin = TAtlasKeyOrigin.Ide) and (AItems[mIndex].Source = TAtlasKeySource.Binding) then
    begin
      mFound := mIndex;
    end;
    if AItems[mIndex].Origin <> TAtlasKeyOrigin.Ide then
    begin
      mShared := True;
    end;
  end;
  if mFound >= 0 then
  begin
    mItem := AItems[mFound];
    mItem.Effective := True;
    AItems[mFound] := mItem;
  end
  else if mShared then
  begin
    AddEditorBinding(AItems, AKey, TAtlasKeyOrigin.Ide, TAtlasKeyMap.IdeName, AOrder);
  end;
end;

/// <summary>Tastaturbelegungen des Editors, soweit die IDE sie nennt: je Taste die wirksame mit ihrem Modul.
/// Atlas-Belegungen markieren die Atlas-Zeile als wirksam; Belegungen der IDE nur, wenn sie eine Taste von Atlas
/// oder einer Erweiterung treffen; Belegungen anderer Erweiterungen immer.</summary>
procedure AddBindings(AItems: TList<TAtlasKeyItem>; AOrigins: TOrigins);
var
  Keyboard: IOTAKeyboardServices;
  Key: Word;
  Code: Pointer;
  Origin: TAtlasKeyOrigin;
  Name: string;
  Order: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    Exit;
  end;
  Order := 100;
  for Key in ProbeKeys(AItems.ToArray) do
  begin
    if not LookupBinding(Keyboard, Key, Code) then
    begin
      Continue;
    end;
    Origin := AOrigins.OfAddress(Code, Name);
    Inc(Order);
    case Origin of
      TAtlasKeyOrigin.Atlas:
        MarkAtlasBinding(AItems, Key);
      TAtlasKeyOrigin.Ide:
        MarkIdeBinding(AItems, Key, Order);
    else
      AddEditorBinding(AItems, Key, Origin, Name, Order);
    end;
  end;
end;

/// <summary>Befehl, unter dem die Zählung einer Zeile steht; '' ohne.</summary>
function UsageIdOf(const AItem: TAtlasKeyItem): string;
begin
  Result := '';
  case AItem.Source of
    TAtlasKeySource.Action:
      // Strg+F12 für „Units suchen“ (#777) zählt beim Befehl der Palette.
      if (AItem.Origin = TAtlasKeyOrigin.Atlas) and AItem.Id.StartsWith(KeyIdPrefix) then
      begin
        Result := TAtlasShortcutTips.AtlasCommandId(AItem.Func);
      end
      else
      begin
        Result := AItem.Id;
      end;
    TAtlasKeySource.Binding:
      if AItem.Origin = TAtlasKeyOrigin.Atlas then
      begin
        Result := TAtlasShortcutTips.AtlasCommandId(AItem.Func);
      end;
  else
    // Fenster-Tasten zählen nicht.
  end;
end;

/// <summary>Zählung je Befehl aus der gemeinsamen Zählung (#600, #757); ohne sie bleibt sie 0.</summary>
procedure AddUsage(var AItems: TArray<TAtlasKeyItem>);
var
  Index: Integer;
  Id: string;
  Entry: TAtlasCommandUsageEntry;
begin
  if TAtlasIdeCommandUsage.Instance = nil then
  begin
    Exit;
  end;
  for Index := 0 to High(AItems) do
  begin
    Id := UsageIdOf(AItems[Index]);
    if (Id <> '') and TAtlasIdeCommandUsage.UsageOf(Id, Entry) then
    begin
      AItems[Index].MouseUses := Entry.Mouse;
      AItems[Index].KeyUses := Entry.Keyboard;
    end;
  end;
end;

type
  /// <summary>Was ein Knopf des Fensters mit der laufenden Übersicht tut.</summary>
  TKeyMapAction = reference to procedure(AMap: TAtlasIdeKeyMap);

/// <summary>Knopf des Fensters: führt AAction geschützt aus, solange es die Übersicht noch gibt.</summary>
function GuardedAction(const AAction: TKeyMapAction): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          if TAtlasIdeKeyMap.Instance <> nil then
          begin
            AAction(TAtlasIdeKeyMap.Instance);
          end;
        end);
    end;
end;

{ TAtlasIdeKeyMap }

constructor TAtlasIdeKeyMap.Create;
begin
  inherited Create;
  FInstance := Self;
end;

destructor TAtlasIdeKeyMap.Destroy;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
  FreeAndNil(FTimer);
  FreeAndNil(FWindow);
  inherited;
end;

class function TAtlasIdeKeyMap.Instance: TAtlasIdeKeyMap;
begin
  Result := FInstance;
end;

class function TAtlasIdeKeyMap.AtlasEntries: TArray<TAtlasKeyEntry>;
var
  Index: Integer;
  Hooked: TBasicAction;
begin
  Result := TAtlasKeyEntry.AllFromSettings(TAtlasIdeSettings.Current);
  Hooked := TakenAction(TAtlasKeyFunction.UnitSearchIde);
  for Index := 0 to High(Result) do
  begin
    if Result[Index].Func = TAtlasKeyFunction.UnitSearchIde then
    begin
      if Hooked is TCustomAction then
      begin
        Result[Index].Key := Word(TCustomAction(Hooked).ShortCut);
      end
      else
      begin
        Result[Index].Key := 0;
      end;
    end;
  end;
end;

class function TAtlasIdeKeyMap.Collect: TArray<TAtlasKeyItem>;
var
  Origins: TOrigins;
  Items: TList<TAtlasKeyItem>;
  Entries: TArray<TAtlasKeyEntry>;
begin
  Entries := AtlasEntries;
  // Liste statt Anhängen ans Array: Die IDE hat weit über tausend Aktionen.
  Items := TList<TAtlasKeyItem>.Create;
  Origins := TOrigins.Create;
  try
    AddAtlasKeys(Items, Entries);
    AddActions(Items, Origins, Entries);
    AddKnownIdeKeys(Items);
    AddBindings(Items, Origins);
    Result := Items.ToArray;
  finally
    Origins.Free;
    Items.Free;
  end;
  TAtlasKeyMap.Analyze(Result);
  AddUsage(Result);
end;

class function TAtlasIdeKeyMap.SetupKeys: TArray<TAtlasSetupKey>;
var
  Items: TArray<TAtlasKeyItem>;
  Entry, Current: TAtlasKeyEntry;
  Index, Partner: Integer;
  Text, Owner: string;
begin
  Result := nil;
  Items := Collect;
  for Entry in AtlasEntries do
  begin
    Text := '';
    if Entry.Key <> 0 then
    begin
      Text := ShortCutToText(TShortCut(Entry.Key));
    end;
    Owner := '';
    Current := Entry;
    Index := IndexOfFunc(Items, Entry.Func);
    if (Index >= 0) and Items[Index].Conflict then
    begin
      Partner := TAtlasKeyMap.PartnerOf(Items, Index);
      if Partner >= 0 then
      begin
        Owner := Items[Partner].Holder;
      end;
      Current.Priority := Entry.Priority and Items[Index].Wins;
    end;
    Result := Result + [TAtlasSetupKey.Create(Current, Text, Owner)];
  end;
end;

class function TAtlasIdeKeyMap.AtlasShortCut(const ACommandId: string): string;
var
  Entry: TAtlasKeyEntry;
begin
  Result := '';
  if ACommandId = '' then
  begin
    Exit;
  end;
  // Mehrere Tasten für einen Befehl (#775, #777): die erste, die Atlas hält.
  for Entry in AtlasEntries do
  begin
    if (Entry.Key <> 0) and not Entry.Disabled and SameText(TAtlasKeyMap.CommandIdOf(Entry.Func), ACommandId) and
      TAtlasKeyConflicts.ShouldBind(Entry.Key, TAtlasIdeKeys.Owner(Entry.Key), Entry.Priority) then
    begin
      Exit(ShortCutToText(TShortCut(Entry.Key)));
    end;
  end;
end;

class function TAtlasIdeKeyMap.ExportFile: string;
var
  Folder: string;
begin
  Folder := GetEnvironmentVariable('LOCALAPPDATA');
  if Folder = '' then
  begin
    Folder := TPath.GetTempPath;
  end;
  Result := TPath.Combine(TPath.Combine(Folder, 'Atlas'), ExportFileName);
end;

procedure TAtlasIdeKeyMap.Refresh;
begin
  if FWindow <> nil then
  begin
    FWindow.SetItems(Collect);
  end;
end;

procedure TAtlasIdeKeyMap.ShowWindow;
begin
  ShowWindow('');
end;

procedure TAtlasIdeKeyMap.ShowWindow(const AQuery: string);
begin
  if FWindow = nil then
  begin
    FWindow := TAtlasKeyMapWindow.CreateKeyMap(nil, TAtlasIdeStyle.Colors);
    if Application.MainForm <> nil then
    begin
      FWindow.PopupMode := pmExplicit;
      FWindow.PopupParent := Application.MainForm;
    end;
    FWindow.OnExport := GuardedAction(
      procedure(AMap: TAtlasIdeKeyMap)
      begin
        AMap.ExportHtml;
      end);
    FWindow.OnSettings := GuardedAction(
      procedure(AMap: TAtlasIdeKeyMap)
      begin
        AMap.OpenKeyConflicts;
      end);
    FWindow.OnRefresh := GuardedAction(
      procedure(AMap: TAtlasIdeKeyMap)
      begin
        AMap.Refresh;
      end);
  end;
  FWindow.SetColors(TAtlasIdeStyle.Colors);
  Refresh;
  if AQuery <> '' then
  begin
    FWindow.SetQuery(AQuery);
  end;
  FWindow.Show;
  FWindow.BringToFront;
end;

procedure TAtlasIdeKeyMap.ShowAll;
begin
  ShowWindow;
  if FWindow <> nil then
  begin
    FWindow.SetQuery('');
  end;
end;

procedure TAtlasIdeKeyMap.ExportHtml;
var
  FileName, Html: string;
begin
  if FWindow = nil then
  begin
    Exit;
  end;
  FileName := ExportFile;
  try
    Html := FWindow.ExportHtml(FormatDateTime('ddddd t', Now));
    ForceDirectories(ExtractFileDir(FileName));
    TFile.WriteAllText(FileName, Html, TEncoding.UTF8);
    ShellExecute(0, 'open', PChar(FileName), nil, nil, SW_SHOWNORMAL);
    // Anonym: nur die Anzahl, kein Pfad.
    TAtlasGuard.Log(Format('Tastenkürzel-Übersicht exportiert: %d Zeilen (#520)', [Length(FWindow.Shown)]));
  except
    on E: Exception do
      TAtlasIdeKeys.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.KeyMapExportFailed, [E.ClassName]));
  end;
end;

procedure TAtlasIdeKeyMap.OpenKeyConflicts;
var
  Options: IOTAEnvironmentOptions140;
  Services: IOTAServices;
begin
  // Seite „Atlas.Tastenkonflikte“ (#494) unter Tools › Optionen; danach neu einlesen.
  if Supports(BorlandIDEServices, IOTAServices, Services) and
    Supports(Services.GetEnvironmentOptions, IOTAEnvironmentOptions140, Options) then
  begin
    Options.EditOptions('', 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.KeysTitle));
  end;
  Refresh;
end;

procedure TAtlasIdeKeyMap.RegisterCommands(const ARegistry: IAtlasCommandRegistry);
var
  Run: TProc;
  Visible: TFunc<Boolean>;
begin
  // Typisierte Variablen: Delphi wählt die Überladung mit anonymen Methoden sonst nicht (E2250).
  Run :=
    procedure
    begin
      if FInstance <> nil then
      begin
        FInstance.ShowWindow;
      end;
    end;
  Visible :=
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.KeyOverview;
    end;
  ARegistry.RegisterCommand(CommandId, TAtlasStrings.Text(TAtlasTextId.KeyMapMenu), '', Run, Visible);
end;

procedure TAtlasIdeKeyMap.CheckAtStart;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.OnTimer := TimerTick;
  end;
  FTimer.Interval := StartDelayMs;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeKeyMap.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      if FInstance <> nil then
      begin
        FInstance.CheckNow;
      end;
    end);
end;

procedure TAtlasIdeKeyMap.CheckNow;
var
  Items: TArray<TAtlasKeyItem>;
  Conflicts: TArray<Integer>;
  Index, Partner: Integer;
  Winner: string;
begin
  if (FWindow <> nil) and FWindow.Visible then
  begin
    Refresh;
  end;
  if not TAtlasIdeSettings.Current.KeyStartupCheck then
  begin
    Exit;
  end;
  Items := Collect;
  Conflicts := TAtlasKeyMap.AtlasConflicts(Items);
  // Anonym: nur Zahlen.
  TAtlasGuard.Log(Format('Tastenkürzel: %d Belegungen, %d mit Konflikt, %d Atlas-Tasten betroffen (#520)',
    [Length(Items), TAtlasKeyMap.ConflictCount(Items), Length(Conflicts)]));
  for Index in Conflicts do
  begin
    // Was #494 beim Belegen gemeldet hat, nicht noch einmal.
    if TAtlasIdeKeys.Reported(Items[Index].ShortCut) then
    begin
      Continue;
    end;
    Partner := TAtlasKeyMap.PartnerOf(Items, Index);
    if Partner < 0 then
    begin
      Continue;
    end;
    if Items[Index].Winner >= 0 then
    begin
      Winner := Items[Items[Index].Winner].Holder;
    end
    else
    begin
      Winner := TAtlasStrings.Text(TAtlasTextId.KeyMapNobody);
    end;
    TAtlasIdeKeys.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.KeyMapStartConflict,
      [Items[Index].KeyText, Items[Index].Command, Items[Partner].Holder, Winner]));
    TAtlasIdeKeys.MarkReported(Items[Index].ShortCut);
  end;
end;

procedure TAtlasIdeKeyMap.ThemeChanged;
begin
  if FWindow <> nil then
  begin
    FWindow.SetColors(TAtlasIdeStyle.Colors);
  end;
end;

end.
