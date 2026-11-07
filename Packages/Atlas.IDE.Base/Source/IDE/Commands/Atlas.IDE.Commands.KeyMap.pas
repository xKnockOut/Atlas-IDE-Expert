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
//   nicht noch einmal. Nach Package-Änderungen prüft es erneut, einmal für alle Module.
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
    cCommandId = 'Atlas.KeyOverview';
    /// <summary>Wartezeit nach dem Laden, bis die übrigen Packages ihre Tasten angemeldet haben.</summary>
    cStartDelayMs = 3000;
    cExportFileName = 'Tastenkuerzel.html';
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
    /// <summary>Wie AtlasShortCut für viele Befehle: Belegungen und Konflikte einmal auswerten, dann nur
    /// nachschlagen. Die ganze Palette fragte sonst je Befehl alle Einstellungen und Aktionen der IDE ab
    /// (Willkommensseite: 60 s Start, 06.11.2026).</summary>
    class function AtlasShortCuts: TFunc<string, string>; static;
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
    /// <summary>Package geladen: nach StartDelayMs einmal die eigenen Tasten prüfen (keys.startupCheck).</summary>
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
  cKeyIdPrefix = 'Atlas.Key.';
  // Reihenfolge, in der die Komposition die Tasten anmeldet (RebindKeys); bei mehreren Atlas-Belegungen
  // derselben Taste gilt die zuletzt angemeldete. 3 = Editorbefehle (eine Bindung); Strg+F12 (#777) ist keine
  // Bindung, sondern eine Aktion und bekommt ihren Platz in der Aktionsliste.
  cBindOrder: array[TAtlasKeyFunction] of Integer = (1, 2, 4, 5, 6, 7, 3, 3, 3, 3, 3, 3, 3, 8, 3, 3, 3, 3, 0, 3, 3, 3,
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
    0,
    // Datei jetzt prüfen (#1744): Editorbefehl.
    3);

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
  mEntry: TOrigin;
begin
  if not FCache.TryGetValue(AModule, mEntry) then
  begin
    if AModule = 0 then
    begin
      mEntry.Origin := TAtlasKeyOrigin.Ide;
      mEntry.Name := TAtlasKeyMap.cIdeName;
    end
    else
    begin
      mEntry.Origin := TAtlasKeyMap.OriginOfModule(GetModuleName(AModule), FIdeFolder, AtlasModuleOf(AModule),
        mEntry.Name);
    end;
    FCache.Add(AModule, mEntry);
  end;
  AName := mEntry.Name;
  Result := mEntry.Origin;
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
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AItems) do
  begin
    if (AItems[mIndex].Origin = TAtlasKeyOrigin.Atlas) and
      (AItems[mIndex].Id = cKeyIdPrefix + IntToStr(Ord(AFunc))) then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Die Tasten von Atlas; ohne eigene Taste (Vervollständigung über Strg+Leer der IDE) oder abgeschaltet
/// keine Zeile. Strg+F12 (#777) kommt mit den Aktionen (AddActions).</summary>
procedure AddAtlasKeys(AItems: TList<TAtlasKeyItem>; const AEntries: TArray<TAtlasKeyEntry>);
var
  mEntry: TAtlasKeyEntry;
  mItem: TAtlasKeyItem;
begin
  for mEntry in AEntries do
  begin
    if (mEntry.Key = 0) or mEntry.Disabled or (TAtlasKeyMap.SourceOf(mEntry.Func) = TAtlasKeySource.Action) then
    begin
      Continue;
    end;
    mItem := TAtlasKeyItem.Create(mEntry.Key, ShortCutToText(TShortCut(mEntry.Key)),
      TAtlasKeyMapWindow.FunctionCaption(mEntry.Func), TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Atlas,
      TAtlasKeyMap.cAtlasName, TAtlasKeyMap.ContextOf(mEntry.Func), TAtlasKeyMap.SourceOf(mEntry.Func),
      cKeyIdPrefix + IntToStr(Ord(mEntry.Func)), cBindOrder[mEntry.Func]));
    mItem.Category := TAtlasKeyMap.cAtlasName;
    mItem.Func := mEntry.Func;
    mItem.Priority := mEntry.Priority;
    if mItem.Source = TAtlasKeySource.Window then
    begin
      // Abgeschaltet (Willkommensseite oder Suchfeld aus) kommt es oben gar nicht an.
      mItem.Active := True;
    end
    else
    begin
      // Wie beim Belegen (#494): frei oder mit Vorrang.
      mItem.Active := TAtlasKeyConflicts.ShouldBind(mEntry.Key, TAtlasIdeKeys.Owner(mEntry.Key), mEntry.Priority);
    end;
    AItems.Add(mItem);
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
  mOrigin: TAtlasKeyOrigin;
  mName, mCaption: string;
  mItem: TAtlasKeyItem;
begin
  // Die Aktion „Units“ ohne Übernahme durch Atlas (#777): Der Handler liegt in Atlas, ruft aber den Dialog der IDE.
  if AHooked then
  begin
    mOrigin := TAtlasKeyOrigin.Ide;
    mName := TAtlasKeyMap.cIdeName;
  end
  else if SameText(AAction.Category, 'Atlas') or AAction.Category.StartsWith('Atlas.', True) then
  begin
    mOrigin := TAtlasKeyOrigin.Atlas;
    mName := TAtlasKeyMap.cAtlasName;
  end
  // Der Handler liegt im Modul dessen, der die Aktion angelegt hat; ohne Handler zählt der Besitzer.
  else if Assigned(AAction.OnExecute) then
  begin
    mOrigin := AOrigins.OfAddress(TMethod(AAction.OnExecute).Code, mName);
  end
  else if AAction.Owner <> nil then
  begin
    mOrigin := AOrigins.OfAddress(Pointer(AAction.Owner.ClassType), mName);
  end
  else
  begin
    mOrigin := AOrigins.OfAddress(Pointer(AAction.ClassType), mName);
  end;
  mCaption := TAtlasCommandPalette.CleanCaption(AAction.Caption);
  if mCaption = '' then
  begin
    mCaption := AAction.Name;
  end;
  mItem := TAtlasKeyItem.Create(Word(AShortCut), ShortCutToText(AShortCut), mCaption,
    TAtlasKeyProvenance.Create(mOrigin,
    mName, TAtlasKeyMap.ContextOfCategory(AAction.Category), TAtlasKeySource.Action, AAction.Name, AOrder));
  mItem.Category := AAction.Category;
  AItems.Add(mItem);
end;

/// <summary>Die von „Units suchen“ übernommene Aktion „Units“ (#777) als Atlas-Taste: bewusst übernommen, also
/// mit Vorrang; Platz in der Aktionsliste wie die Aktion selbst.</summary>
procedure AddUnitSearchAction(AItems: TList<TAtlasKeyItem>; AAction: TCustomAction; AShortCut: TShortCut;
  AOrder: Integer);
const
  cFunc = TAtlasKeyFunction.UnitSearchIde;
var
  mItem: TAtlasKeyItem;
begin
  mItem := TAtlasKeyItem.Create(Word(AShortCut), ShortCutToText(AShortCut), TAtlasKeyMapWindow.FunctionCaption(cFunc),
    TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Atlas, TAtlasKeyMap.cAtlasName, TAtlasKeyMap.ContextOf(cFunc),
    TAtlasKeyMap.SourceOf(cFunc), cKeyIdPrefix + IntToStr(Ord(cFunc)), AOrder));
  mItem.Category := AAction.Category;
  mItem.Func := cFunc;
  mItem.Priority := True;
  AItems.Add(mItem);
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
  mServices: INTAServices;
  mIndex: Integer;
  mScan: TActionScan;
begin
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  mScan.Items := AItems;
  mScan.Origins := AOrigins;
  mScan.Hooked := TakenAction(TAtlasKeyFunction.UnitSearchIde);
  mScan.TakenOver := UnitSearchTakenOver(AEntries);
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    if mServices.ActionList.Actions[mIndex] is TCustomAction then
    begin
      AddActionKeys(mScan, TCustomAction(mServices.ActionList.Actions[mIndex]), mIndex);
    end;
  end;
end;

/// <summary>Bekannte Belegungen der Standard-Tastaturbelegung (#494), die keine Aktionen sind.</summary>
procedure AddKnownIdeKeys(AItems: TList<TAtlasKeyItem>);
var
  mKnown: TAtlasKeyOwner;
  mCommand: string;
begin
  for mKnown in TAtlasKeyConflicts.KnownIdeKeys do
  begin
    mCommand := mKnown.Owner;
    if mCommand.StartsWith('IDE: ') then
    begin
      mCommand := Copy(mCommand, 6, MaxInt);
    end;
    AItems.Add(TAtlasKeyItem.Create(mKnown.ShortCut, ShortCutToText(TShortCut(mKnown.ShortCut)), mCommand,
      TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Ide, TAtlasKeyMap.cIdeName, TAtlasKeyContext.Editor,
      TAtlasKeySource.Binding, 'Editor.' + IntToStr(mKnown.ShortCut), 0)));
  end;
end;

/// <summary>Abzufragende Tasten: alle Einträge, dazu Strg/Alt mit Buchstaben, Ziffern, Leer und Enter sowie
/// F1–F12 mit jeder Umschaltung.</summary>
function ProbeKeys(const AItems: TArray<TAtlasKeyItem>): TArray<Word>;
const
  cModifiers: array[0..5] of Word = (TAtlasKeyMap.cScCtrl, TAtlasKeyMap.cScCtrl or TAtlasKeyMap.cScShift,
    TAtlasKeyMap.cScCtrl or TAtlasKeyMap.cScAlt, TAtlasKeyMap.cScCtrl or TAtlasKeyMap.cScAlt or TAtlasKeyMap.cScShift,
    TAtlasKeyMap.cScAlt, TAtlasKeyMap.cScAlt or TAtlasKeyMap.cScShift);
var
  mSeen: TDictionary<Word, Boolean>;
  mItem: TAtlasKeyItem;
  mModifier: Word;
  mKey: Integer;

  procedure Add(AKey: Word);
  begin
    if (AKey <> 0) and not mSeen.ContainsKey(AKey) then
    begin
      mSeen.Add(AKey, True);
      Result := Result + [AKey];
    end;
  end;

begin
  Result := nil;
  mSeen := TDictionary<Word, Boolean>.Create;
  try
    for mItem in AItems do
    begin
      Add(mItem.ShortCut);
    end;
    for mModifier in cModifiers do
    begin
      for mKey := Ord('A') to Ord('Z') do
      begin
        Add(mModifier or Word(mKey));
      end;
      for mKey := Ord('0') to Ord('9') do
      begin
        Add(mModifier or Word(mKey));
      end;
      Add(mModifier or $20);
      Add(mModifier or $0D);
    end;
    for mKey := $70 to $7B do
    begin
      Add(Word(mKey));
      Add(TAtlasKeyMap.cScShift or Word(mKey));
      for mModifier in cModifiers do
      begin
        Add(mModifier or Word(mKey));
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

/// <summary>Wirksame Tastaturbelegung des Editors für AKey: Code ihres Handlers; False ohne.</summary>
function LookupBinding(const AKeyboard: IOTAKeyboardServices; AKey: Word; out ACode: Pointer): Boolean;
var
  mBinding: TKeyBindingRec;
begin
  ACode := nil;
  mBinding := Default(TKeyBindingRec);
  try
    Result := AKeyboard.LookupKeyBinding([TShortCut(AKey)], mBinding);
  except
    // Eine Taste, die die IDE nicht auflösen kann, zählt als frei.
    Result := False;
  end;
  if Result then
  begin
    ACode := TMethod(mBinding.KeyProc).Code;
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
    AddEditorBinding(AItems, AKey, TAtlasKeyOrigin.Ide, TAtlasKeyMap.cIdeName, AOrder);
  end;
end;

/// <summary>Tastaturbelegungen des Editors, soweit die IDE sie nennt: je Taste die wirksame mit ihrem Modul.
/// Atlas-Belegungen markieren die Atlas-Zeile als wirksam; Belegungen der IDE nur, wenn sie eine Taste von Atlas
/// oder einer Erweiterung treffen; Belegungen anderer Erweiterungen immer.</summary>
procedure AddBindings(AItems: TList<TAtlasKeyItem>; AOrigins: TOrigins);
var
  mKeyboard: IOTAKeyboardServices;
  mKey: Word;
  mCode: Pointer;
  mOrigin: TAtlasKeyOrigin;
  mName: string;
  mOrder: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAKeyboardServices, mKeyboard) then
  begin
    Exit;
  end;
  mOrder := 100;
  for mKey in ProbeKeys(AItems.ToArray) do
  begin
    if not LookupBinding(mKeyboard, mKey, mCode) then
    begin
      Continue;
    end;
    mOrigin := AOrigins.OfAddress(mCode, mName);
    Inc(mOrder);
    case mOrigin of
      TAtlasKeyOrigin.Atlas:
        MarkAtlasBinding(AItems, mKey);
      TAtlasKeyOrigin.Ide:
        MarkIdeBinding(AItems, mKey, mOrder);
    else
      AddEditorBinding(AItems, mKey, mOrigin, mName, mOrder);
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
      if (AItem.Origin = TAtlasKeyOrigin.Atlas) and AItem.Id.StartsWith(cKeyIdPrefix) then
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
  mIndex: Integer;
  mId: string;
  mEntry: TAtlasCommandUsageEntry;
begin
  if TAtlasIdeCommandUsage.Instance = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AItems) do
  begin
    mId := UsageIdOf(AItems[mIndex]);
    if (mId <> '') and TAtlasIdeCommandUsage.UsageOf(mId, mEntry) then
    begin
      AItems[mIndex].MouseUses := mEntry.Mouse;
      AItems[mIndex].KeyUses := mEntry.Keyboard;
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
  mIndex: Integer;
  mHooked: TBasicAction;
begin
  Result := TAtlasKeyEntry.AllFromSettings(TAtlasIdeSettings.Current);
  mHooked := TakenAction(TAtlasKeyFunction.UnitSearchIde);
  for mIndex := 0 to High(Result) do
  begin
    if Result[mIndex].Func = TAtlasKeyFunction.UnitSearchIde then
    begin
      if mHooked is TCustomAction then
      begin
        Result[mIndex].Key := Word(TCustomAction(mHooked).ShortCut);
      end
      else
      begin
        Result[mIndex].Key := 0;
      end;
    end;
  end;
end;

class function TAtlasIdeKeyMap.Collect: TArray<TAtlasKeyItem>;
var
  mOrigins: TOrigins;
  mItems: TList<TAtlasKeyItem>;
  mEntries: TArray<TAtlasKeyEntry>;
begin
  mEntries := AtlasEntries;
  // Liste statt Anhängen ans Array: Die IDE hat weit über tausend Aktionen.
  mItems := TList<TAtlasKeyItem>.Create;
  mOrigins := TOrigins.Create;
  try
    AddAtlasKeys(mItems, mEntries);
    AddActions(mItems, mOrigins, mEntries);
    AddKnownIdeKeys(mItems);
    AddBindings(mItems, mOrigins);
    Result := mItems.ToArray;
  finally
    mOrigins.Free;
    mItems.Free;
  end;
  TAtlasKeyMap.Analyze(Result);
  AddUsage(Result);
end;

class function TAtlasIdeKeyMap.SetupKeys: TArray<TAtlasSetupKey>;
var
  mItems: TArray<TAtlasKeyItem>;
  mEntry, mCurrent: TAtlasKeyEntry;
  mIndex, mPartner: Integer;
  mText, mOwner: string;
begin
  Result := nil;
  mItems := Collect;
  for mEntry in AtlasEntries do
  begin
    mText := '';
    if mEntry.Key <> 0 then
    begin
      mText := ShortCutToText(TShortCut(mEntry.Key));
    end;
    mOwner := '';
    mCurrent := mEntry;
    mIndex := IndexOfFunc(mItems, mEntry.Func);
    if (mIndex >= 0) and mItems[mIndex].Conflict then
    begin
      mPartner := TAtlasKeyMap.PartnerOf(mItems, mIndex);
      if mPartner >= 0 then
      begin
        mOwner := mItems[mPartner].Holder;
      end;
      mCurrent.Priority := mEntry.Priority and mItems[mIndex].Wins;
    end;
    Result := Result + [TAtlasSetupKey.Create(mCurrent, mText, mOwner)];
  end;
end;

class function TAtlasIdeKeyMap.AtlasShortCut(const ACommandId: string): string;
begin
  Result := '';
  if ACommandId <> '' then
  begin
    Result := AtlasShortCuts()(ACommandId);
  end;
end;

/// <summary>Nachschlagen in AIds/AKeys (gleich lang); eigene Routine, damit die Methodenreferenz nur die Arrays hält.
/// </summary>
function ShortCutLookup(const AIds, AKeys: TArray<string>): TFunc<string, string>;
begin
  Result :=
    function(AId: string): string
    var
      mIndex: Integer;
    begin
      Result := '';
      for mIndex := 0 to High(AIds) do
      begin
        if SameText(AIds[mIndex], AId) then
        begin
          Exit(AKeys[mIndex]);
        end;
      end;
    end;
end;

class function TAtlasIdeKeyMap.AtlasShortCuts: TFunc<string, string>;
var
  mEntry: TAtlasKeyEntry;
  mId: string;
  mIds, mKeys: TArray<string>;
  mKnown: Boolean;
  mIndex: Integer;
begin
  mIds := nil;
  mKeys := nil;
  // Mehrere Tasten für einen Befehl (#775, #777): die erste, die Atlas hält.
  for mEntry in AtlasEntries do
  begin
    mId := TAtlasKeyMap.CommandIdOf(mEntry.Func);
    if (mEntry.Key = 0) or mEntry.Disabled or (mId = '') then
    begin
      Continue;
    end;
    mKnown := False;
    for mIndex := 0 to High(mIds) do
    begin
      mKnown := mKnown or SameText(mIds[mIndex], mId);
    end;
    if not mKnown and TAtlasKeyConflicts.ShouldBind(mEntry.Key, TAtlasIdeKeys.Owner(mEntry.Key), mEntry.Priority) then
    begin
      mIds := mIds + [mId];
      mKeys := mKeys + [ShortCutToText(TShortCut(mEntry.Key))];
    end;
  end;
  Result := ShortCutLookup(mIds, mKeys);
end;

class function TAtlasIdeKeyMap.ExportFile: string;
var
  mFolder: string;
begin
  mFolder := GetEnvironmentVariable('LOCALAPPDATA');
  if mFolder = '' then
  begin
    mFolder := TPath.GetTempPath;
  end;
  Result := TPath.Combine(TPath.Combine(mFolder, 'Atlas'), cExportFileName);
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
  mFileName, mHtml: string;
begin
  if FWindow = nil then
  begin
    Exit;
  end;
  mFileName := ExportFile;
  try
    mHtml := FWindow.ExportHtml(FormatDateTime('ddddd t', Now));
    ForceDirectories(ExtractFileDir(mFileName));
    TFile.WriteAllText(mFileName, mHtml, TEncoding.UTF8);
    ShellExecute(0, 'open', PChar(mFileName), nil, nil, SW_SHOWNORMAL);
    // Anonym: nur die Anzahl, kein Pfad.
    TAtlasGuard.Log(Format('Tastenkürzel-Übersicht exportiert: %d Zeilen (#520)', [Length(FWindow.Shown)]));
  except
    on E: Exception do
      TAtlasIdeKeys.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.KeyMapExportFailed, [E.ClassName]));
  end;
end;

procedure TAtlasIdeKeyMap.OpenKeyConflicts;
var
  mOptions: IOTAEnvironmentOptions140;
  mServices: IOTAServices;
begin
  // Seite „Atlas.Tastenkonflikte“ (#494) unter Tools › Optionen; danach neu einlesen.
  if Supports(BorlandIDEServices, IOTAServices, mServices) and
    Supports(mServices.GetEnvironmentOptions, IOTAEnvironmentOptions140, mOptions) then
  begin
    mOptions.EditOptions('', 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.KeysTitle));
  end;
  Refresh;
end;

procedure TAtlasIdeKeyMap.RegisterCommands(const ARegistry: IAtlasCommandRegistry);
var
  mRun: TProc;
  mVisible: TFunc<Boolean>;
begin
  // Typisierte Variablen: Delphi wählt die Überladung mit anonymen Methoden sonst nicht (E2250).
  mRun :=
    procedure
    begin
      if FInstance <> nil then
      begin
        FInstance.ShowWindow;
      end;
    end;
  mVisible :=
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.KeyOverview;
    end;
  ARegistry.RegisterCommand(cCommandId, TAtlasStrings.Text(TAtlasTextId.KeyMapMenu), '', mRun, mVisible);
end;

procedure TAtlasIdeKeyMap.CheckAtStart;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.OnTimer := TimerTick;
  end;
  FTimer.Interval := cStartDelayMs;
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
  mItems: TArray<TAtlasKeyItem>;
  mConflicts: TArray<Integer>;
  mIndex, mPartner: Integer;
  mWinner: string;
begin
  if (FWindow <> nil) and FWindow.Visible then
  begin
    Refresh;
  end;
  if not TAtlasIdeSettings.Current.KeyStartupCheck then
  begin
    Exit;
  end;
  mItems := Collect;
  mConflicts := TAtlasKeyMap.AtlasConflicts(mItems);
  // Anonym: nur Zahlen.
  TAtlasGuard.Log(Format('Tastenkürzel: %d Belegungen, %d mit Konflikt, %d Atlas-Tasten betroffen (#520)',
    [Length(mItems), TAtlasKeyMap.ConflictCount(mItems), Length(mConflicts)]));
  for mIndex in mConflicts do
  begin
    // Was #494 beim Belegen gemeldet hat, nicht noch einmal.
    if TAtlasIdeKeys.Reported(mItems[mIndex].ShortCut) then
    begin
      Continue;
    end;
    mPartner := TAtlasKeyMap.PartnerOf(mItems, mIndex);
    if mPartner < 0 then
    begin
      Continue;
    end;
    if mItems[mIndex].Winner >= 0 then
    begin
      mWinner := mItems[mItems[mIndex].Winner].Holder;
    end
    else
    begin
      mWinner := TAtlasStrings.Text(TAtlasTextId.KeyMapNobody);
    end;
    TAtlasIdeKeys.AddMessage(TAtlasStrings.Fmt(TAtlasTextId.KeyMapStartConflict,
      [mItems[mIndex].KeyText, mItems[mIndex].Command, mItems[mPartner].Holder, mWinner]));
    TAtlasIdeKeys.MarkReported(mItems[mIndex].ShortCut);
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
