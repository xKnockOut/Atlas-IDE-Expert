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
//   Atlas-Befehls in der Befehlspalette (#502, AtlasShortCuts) und spätere
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
    /// <summary>Taste eines Atlas-Befehls der Palette als Text, wenn Atlas sie belegt, sonst '': Belegungen und
    /// Konflikte einmal auswerten, dann nur nachschlagen. Die ganze Palette fragte sonst je Befehl alle
    /// Einstellungen und Aktionen der IDE ab (die Willkommensseite brauchte so 60 s zum Start).</summary>
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
    class procedure RegisterCommands(const ARegistry: IAtlasCommandRegistry); static;
    /// <summary>Package geladen: nach StartDelayMs einmal die eigenen Tasten prüfen (keys.startupCheck).</summary>
    procedure CheckAtStart;
    /// <summary>Eigene Tasten prüfen und neue Konflikte melden; offenes Fenster neu einlesen.</summary>
    procedure CheckNow;
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
  Atlas.Core.Commands.KeyScan,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Keys,
  Atlas.Core.Commands.Usage,
  Atlas.IDE.Commands.Usage,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Foundation.Host;

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

{ TOrigins }

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

/// <summary>Die Tasten von Atlas; ohne eigene Taste (Vervollständigung über Strg+Leer der IDE) oder abgeschaltet
/// keine Zeile. Strg+F12 (#777) kommt mit den Aktionen (AddActions).</summary>
procedure AddAtlasKeys(AItems: TList<TAtlasKeyItem>; const AEntries: TArray<TAtlasKeyEntry>);
var
  mEntry: TAtlasKeyEntry;
  mOwnerOf: TFunc<Word, string>;
begin
  mOwnerOf :=
    function(AKey: Word): string
    begin
      Result := TAtlasIdeKeys.Owner(AKey);
    end;
  for mEntry in AEntries do
  begin
    if TAtlasKeyScan.IsListed(mEntry) then
    begin
      AItems.Add(TAtlasKeyScan.AtlasItem(mEntry, ShortCutToText(TShortCut(mEntry.Key)),
        TAtlasKeyMapWindow.FunctionCaption(mEntry.Func), mOwnerOf));
    end;
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
  else if TAtlasKeyScan.IsAtlasCategory(AAction.Category) then
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
begin
  AItems.Add(TAtlasKeyScan.UnitSearchItem(Word(AShortCut), ShortCutToText(AShortCut),
    TAtlasKeyMapWindow.FunctionCaption(TAtlasKeyFunction.UnitSearchIde), AAction.Category, AOrder));
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
  mScan.TakenOver := TAtlasKeyScan.UnitSearchTakenOver(AEntries);
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
begin
  for mKnown in TAtlasKeyConflicts.KnownIdeKeys do
  begin
    AItems.Add(TAtlasKeyItem.Create(mKnown.ShortCut, ShortCutToText(TShortCut(mKnown.ShortCut)),
      TAtlasKeyScan.KnownIdeCommand(mKnown.Owner),
      TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Ide, TAtlasKeyMap.cIdeName, TAtlasKeyContext.Editor,
      TAtlasKeySource.Binding, 'Editor.' + IntToStr(mKnown.ShortCut), 0)));
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

/// <summary>Neue, wirksame Zeile für eine Belegung des Editors.</summary>
procedure AddEditorBinding(AItems: TList<TAtlasKeyItem>; AKey: Word; AOrigin: TAtlasKeyOrigin; const AName: string;
  AOrder: Integer);
var
  mItem: TAtlasKeyItem;
begin
  mItem := TAtlasKeyItem.Create(AKey, ShortCutToText(TShortCut(AKey)),
    TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapEditorBinding), TAtlasKeyProvenance.Create(AOrigin, AName,
    TAtlasKeyContext.Editor, TAtlasKeySource.Binding, 'Editor.' + IntToStr(AKey), AOrder));
  mItem.Effective := True;
  AItems.Add(mItem);
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
  mOrder := TAtlasKeyScan.cFirstBindingOrder;
  for mKey in TAtlasKeyScan.ProbeKeys(AItems.ToArray) do
  begin
    if not LookupBinding(mKeyboard, mKey, mCode) then
    begin
      Continue;
    end;
    mOrigin := AOrigins.OfAddress(mCode, mName);
    Inc(mOrder);
    case mOrigin of
      TAtlasKeyOrigin.Atlas:
        TAtlasKeyScan.MarkAtlasBinding(AItems, mKey);
      TAtlasKeyOrigin.Ide:
        if TAtlasKeyScan.MarkIdeBinding(AItems, mKey) then
        begin
          AddEditorBinding(AItems, mKey, TAtlasKeyOrigin.Ide, TAtlasKeyMap.cIdeName, mOrder);
        end;
    else
      AddEditorBinding(AItems, mKey, mOrigin, mName, mOrder);
    end;
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
    mId := TAtlasKeyScan.UsageIdOf(AItems[mIndex]);
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

procedure TAtlasIdeKeyMap.Refresh;
begin
  if FWindow <> nil then
  begin
    FWindow.SetItems(Collect);
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
      TAtlasIdeHost.Message(TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapExportFailed, [E.ClassName]));
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

class function TAtlasIdeKeyMap.Instance: TAtlasIdeKeyMap;
begin
  Result := FInstance;
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

class function TAtlasIdeKeyMap.SetupKeys: TArray<TAtlasSetupKey>;
var
  mItems: TArray<TAtlasKeyItem>;
  mEntry: TAtlasKeyEntry;
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
    Result := Result + [TAtlasSetupKey.Create(TAtlasKeyScan.SetupEntry(mItems, mEntry, mOwner), mText, mOwner)];
  end;
end;

/// <summary>Fremde Belegung einer Taste aus den einmal gesammelten Besitzern AOwners.</summary>
function OwnerLookup(AOwners: TDictionary<Word, string>): TFunc<Word, string>;
begin
  Result :=
    function(AKey: Word): string
    begin
      Result := TAtlasIdeKeys.OwnerIn(AOwners, AKey);
    end;
end;

class function TAtlasIdeKeyMap.AtlasShortCuts: TFunc<string, string>;
var
  mEntry: TAtlasKeyEntry;
  mIds, mKeys: TArray<string>;
  mOwners: TDictionary<Word, string>;
begin
  mIds := nil;
  mKeys := nil;
  // Besitzer aller IDE-Tasten in einem Lauf über die ActionList, nicht je Eintrag (Einträge × Aktionen).
  mOwners := TDictionary<Word, string>.Create;
  try
    TAtlasIdeKeys.CollectOwners(mOwners);
    for mEntry in TAtlasKeyScan.HeldCommandKeys(AtlasEntries, OwnerLookup(mOwners)) do
    begin
      mIds := mIds + [TAtlasKeyMap.CommandIdOf(mEntry.Func)];
      mKeys := mKeys + [ShortCutToText(TShortCut(mEntry.Key))];
    end;
  finally
    mOwners.Free;
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

procedure TAtlasIdeKeyMap.ShowWindow;
begin
  ShowWindow('');
end;

procedure TAtlasIdeKeyMap.ShowWindow(const AQuery: string);
begin
  if FWindow = nil then
  begin
    FWindow := TAtlasKeyMapWindow.CreateKeyMap(nil);
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

class procedure TAtlasIdeKeyMap.RegisterCommands(const ARegistry: IAtlasCommandRegistry);
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

/// <summary>Schon beim Belegen (#494) gemeldete Tasten.</summary>
function ReportedKeys: TFunc<Word, Boolean>;
begin
  Result :=
    function(AKey: Word): Boolean
    begin
      Result := TAtlasIdeKeys.Reported(AKey);
    end;
end;

procedure TAtlasIdeKeyMap.CheckNow;
var
  mItems: TArray<TAtlasKeyItem>;
  mConflict: TAtlasKeyStartConflict;
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
  // Anonym: nur Zahlen.
  TAtlasGuard.Log(Format('Tastenkürzel: %d Belegungen, %d mit Konflikt, %d Atlas-Tasten betroffen (#520)',
    [Length(mItems), TAtlasKeyMap.ConflictCount(mItems), Length(TAtlasKeyMap.AtlasConflicts(mItems))]));
  for mConflict in TAtlasKeyScan.StartConflicts(mItems, ReportedKeys()) do
  begin
    if mConflict.Winner >= 0 then
    begin
      mWinner := mItems[mConflict.Winner].Holder;
    end
    else
    begin
      mWinner := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapNobody);
    end;
    TAtlasIdeHost.Message(TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyMapStartConflict,
      [mItems[mConflict.Index].KeyText, mItems[mConflict.Index].Command, mItems[mConflict.Partner].Holder,
      mWinner]));
    TAtlasIdeKeys.MarkReported(mItems[mConflict.Index].ShortCut);
  end;
end;

end.
