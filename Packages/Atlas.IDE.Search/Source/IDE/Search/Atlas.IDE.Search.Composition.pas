unit Atlas.IDE.Search.Composition;

// Modul Suche (#1455, ADR 0017): einzige Unit, die die Atlas-Suche (#877,
// #878, Ersetzen #893), „Units suchen“ (#777, Unit verwenden und Formulare
// #786) und das Fenster „Atlas-Abfrage“ (#1351) einbindet. Sie meldet in ihrer
// Initialisierung das Modul „atlas.search“ (Modulschalter search, #1454) bei
// der Registry von Base an und stellt über dessen Scope bereit:
// - die Teile Search, UnitSearch und Query der Feature-Tabelle,
// - Befehle (Palette), Einträge im Atlas-Menü und unter Ansicht › Atlas,
// - die Tasten (Strg+F, Strg+H, F3/Umschalt+F3 samt Austrittspunkten und
//   Markierungssuche von Base, In Methode suchen, Units suchen),
// - Hörer für Einstellungen und Thema,
// - die übernommene IDE-Aktion „Units“ (Strg+F12) für die
//   Tastenkürzel-Übersicht (IAtlasTakenActions).
// Anfragen der Abfrage gehen über TAtlasIdeHost.RunRequestAsync: Antworten
// erreichen das Modul nur, solange es angemeldet ist (Regel 3).
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Commands.KeyMap;

type
  TAtlasSearchModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource, IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasTakenActions)
  public const
    cModuleId = 'atlas.search';
    cSwitch = 'search';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function Keys: TArray<TAtlasModuleKey>;
    procedure ApplySettings;
    procedure ThemeChanged;
    function TakenActions: TArray<TAtlasTakenAction>;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.UI.Search.SettingsSection,
  System.Classes,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Query.Model,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.ExitPoints,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Search.Commands,
  Atlas.IDE.UnitSearch.Commands,
  Atlas.IDE.Query.Service,
  Atlas.UI.Strings,
  Atlas.UI.Search.Strings;

const
  /// <summary>Symbolnamen beim Tippen im Fenster „Atlas-Abfrage“: lieber keine Vorschläge als die IDE aufhalten.
  /// </summary>
  cQuerySymbolTimeoutMs = 1500;

var
  GScope: IAtlasModuleScope;
  GSearchStarted: Boolean;
  GUnitSearchStarted: Boolean;
  GQueryStarted: Boolean;

{ Gemeinsam }

procedure Warn(AText: string);
begin
  TAtlasIdeHost.Warning(AText);
end;

function ActiveSession: TLspSession;
begin
  Result := TAtlasIdeHost.ActiveSession;
end;

{ Atlas-Suche (#877, #878) }

procedure StartSearch;
begin
  TAtlasIdeSearch.Install(Warn);
  GSearchStarted := True;
end;

procedure StopSearch;
begin
  GSearchStarted := False;
  TAtlasIdeSearch.Uninstall;
end;

function SearchStarted: Boolean;
begin
  Result := GSearchStarted;
end;

{ Units suchen (#777) }

procedure StartUnitSearch;
begin
  // Übernimmt Strg+F12, solange die Einstellungen es wollen.
  TAtlasIdeUnitSearch.Install(ActiveSession, Warn);
  GUnitSearchStarted := True;
end;

procedure StopUnitSearch;
begin
  GUnitSearchStarted := False;
  TAtlasIdeUnitSearch.Uninstall;
end;

function UnitSearchStarted: Boolean;
begin
  Result := GUnitSearchStarted;
end;

{ Atlas-Abfrage (#1351) }

/// <summary>Abbrechbare Anfrage an den laufenden Server (startet keinen); die Antwort nur, solange das Modul
/// angemeldet ist.</summary>
function QueryRequest(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal; const ACancelled: TFunc<Boolean>;
  const ADone: TProc<string>): Boolean;
begin
  Result := TAtlasIdeHost.RunRequestAsync(GScope, TAtlasFeature.Query,
    TAtlasServerRequest.Create(AMethod, AParamsJson, ATimeoutMs, ACancelled), ADone);
end;

/// <summary>Symbolnamen hinter APredicate für die Vervollständigung der Abfrage; nur mit laufendem Server.</summary>
function QuerySymbols(const APredicate, APrefix: string): TArray<string>;
var
  mSession: TLspSession;
  mSymbols: TArray<TAtlasSymbol>;
begin
  mSession := TAtlasIdeHost.RunningSession;
  if mSession = nil then
  begin
    Exit(nil);
  end;
  try
    mSymbols := mSession.WorkspaceSymbols(APrefix, cQuerySymbolTimeoutMs);
  except
    on ELspClientError do
      mSymbols := nil;
  end;
  Result := TAtlasQueryCompletion.SymbolNames(APredicate, mSymbols);
end;

procedure StartQuery;
begin
  TAtlasIdeCodeQuery.Install(QueryRequest, QuerySymbols);
  GQueryStarted := True;
end;

procedure StopQuery;
begin
  GQueryStarted := False;
  TAtlasIdeCodeQuery.Uninstall;
end;

function QueryStarted: Boolean;
begin
  Result := GQueryStarted;
end;

{ Befehle }

function Guarded(AFeature: TAtlasFeature; const AProc: TProc): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(AFeature, AProc);
    end;
end;

function Command(const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Run := ARun;
  Result.Visible := AVisible;
end;

function UnitSearchVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.UnitSearchEnabled;
end;

function SearchReplaceVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.SearchReplace;
end;

function QueryVisible: Boolean;
begin
  Result := TAtlasIdeCodeQuery.Enabled;
end;

// Show ist überladen: eigene Routinen statt Methodenzeiger.
procedure ShowUnitSearch;
begin
  TAtlasIdeUnitSearch.Show;
end;

procedure ShowUnitSearchIde;
begin
  TAtlasIdeUnitSearch.ShowIdeDialog;
end;

procedure ShowUseUnit;
begin
  TAtlasIdeUnitSearch.ShowUseUnit;
end;

procedure ShowUseUnitIde;
begin
  TAtlasIdeUnitSearch.ShowUseUnitIdeDialog;
end;

procedure ShowForms;
begin
  TAtlasIdeUnitSearch.ShowForms;
end;

procedure ShowFormsIde;
begin
  TAtlasIdeUnitSearch.ShowFormsIdeDialog;
end;

procedure ShowQuery;
begin
  TAtlasIdeCodeQuery.ShowWindow;
end;

{ Tasten }

function Key(const AId: string; const ACaption: string; AKey: Integer;
  APriority: TAtlasKeyPriority): TAtlasModuleKey;
begin
  Result := Default(TAtlasModuleKey);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Key := AKey;
  Result.Priority := APriority;
end;

/// <summary>F3 bzw. Umschalt+F3: Austrittspunkte (#698), dann die letzte Atlas-Suche, dann Markierung suchen; ohne
/// Treffer an die IDE („Erneut suchen“).</summary>
function SearchStep(ABackward: Boolean): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := TAtlasIdeExitPoints.TryJump(ABackward) or TAtlasIdeSearch.TryNext(ABackward) or
        TAtlasIdeEditorCommands.TryFindSelection(ABackward);
    end;
end;

procedure ShowSearch;
begin
  TAtlasGuard.Run(TAtlasFeature.Search, TAtlasIdeSearch.Show);
end;

procedure ShowReplace;
begin
  TAtlasGuard.Run(TAtlasFeature.Search, TAtlasIdeSearch.ShowReplace);
end;

procedure ShowInMethod;
begin
  TAtlasGuard.Run(TAtlasFeature.Search, TAtlasIdeSearch.ShowInMethod);
end;

procedure ShowUnitSearchGuarded;
begin
  TAtlasGuard.Run(TAtlasFeature.UnitSearch, ShowUnitSearch);
end;

{ TAtlasSearchModule }

function TAtlasSearchModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := cModuleId;
  Result.Name := 'Suche';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Lief mit den Editorbefehlen schon im abgesicherten Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := cSwitch;
end;

procedure TAtlasSearchModule.Start;
begin
  FActive := True;
end;

procedure TAtlasSearchModule.Stop;
begin
  FActive := False;
end;

function TAtlasSearchModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasSearchModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Units suchen (#777), Unit verwenden und Formulare (#786), mit den Dialogen der IDE als Ausweg.
    Command('Atlas.UnitSearch', TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle), ShowUnitSearch, UnitSearchVisible),
    Command('Atlas.UnitSearchIde', TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchIdeDialog), ShowUnitSearchIde,
      nil),
    Command('Atlas.UseUnit', TAtlasSearchStrings.Text(TAtlasSearchTextId.UseUnitCommand), ShowUseUnit,
      UnitSearchVisible),
    Command('Atlas.UseUnitIde', TAtlasSearchStrings.Text(TAtlasSearchTextId.UseUnitIdeDialog), ShowUseUnitIde, nil),
    Command('Atlas.Forms', TAtlasSearchStrings.Text(TAtlasSearchTextId.FormsCommand), ShowForms, UnitSearchVisible),
    Command('Atlas.FormsIde', TAtlasSearchStrings.Text(TAtlasSearchTextId.FormsIdeDialog), ShowFormsIde, nil),
    // Atlas-Suche (#877, #878); Ersetzen (#893) nur mit search.replace.
    Command('Atlas.Search', TAtlasStrings.Text(TAtlasTextId.SearchCommand), TAtlasIdeSearch.Show, nil),
    Command('Atlas.SearchInMethod', TAtlasStrings.Text(TAtlasTextId.SearchInMethodCommand),
      TAtlasIdeSearch.ShowInMethod, nil),
    Command('Atlas.SearchReplace', TAtlasStrings.Text(TAtlasTextId.SearchReplaceCommand), TAtlasIdeSearch.ShowReplace,
      SearchReplaceVisible),
    Command('Atlas.SearchNext', TAtlasStrings.Text(TAtlasTextId.SearchNextCommand), TAtlasIdeSearch.FindNext, nil),
    Command('Atlas.SearchPrevious', TAtlasStrings.Text(TAtlasTextId.SearchPreviousCommand),
      TAtlasIdeSearch.FindPrevious, nil),
    Command('Atlas.SearchClear', TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchClearCommand),
      TAtlasIdeSearch.ClearHighlights, nil),
    // Code-Abfragen (#1351); nur sichtbar, solange query.enabled an ist.
    Command('Atlas.Query', TAtlasSearchStrings.Text(TAtlasSearchTextId.QueryCommand),
      Guarded(TAtlasFeature.Query, ShowQuery), QueryVisible)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

function TAtlasSearchModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    MenuEntry('Atlas.UnitSearch', TAtlasMenuPlace.AtlasMenu),
    // Der IDE-Dialog, falls Atlas Strg+F12 übernimmt.
    MenuEntry('Atlas.UnitSearchIde', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.Query', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.Query', TAtlasMenuPlace.ViewMenu)];
end;

function TAtlasSearchModule.Keys: TArray<TAtlasModuleKey>;
var
  mSettings: TAtlasPluginSettings;
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  mSettings := TAtlasIdeSettings.Current;
  // Atlas-Suche (#878): bewusst übernommen wie Strg+F12 bei „Units suchen“; mit dem Schalter aus belegt Atlas sie
  // nicht. Die Leiste öffnet erst nach der Tastenverarbeitung (sie nimmt den Fokus).
  if mSettings.SearchReplaceIde then
  begin
    mKey := Key('Atlas.Search', TAtlasStrings.Text(TAtlasTextId.SearchCommand), mSettings.SearchKey,
      TAtlasKeyPriority.Take);
    mKey.Run := ShowSearch;
    Result := Result + [mKey];
    // Strg+H (#893): nur mit search.replace, sonst gehört die Taste der IDE.
    if mSettings.SearchReplace then
    begin
      mKey := Key('Atlas.SearchReplace', TAtlasStrings.Text(TAtlasTextId.SearchReplaceCommand),
        mSettings.SearchReplaceKey,
        TAtlasKeyPriority.Take);
      mKey.Run := ShowReplace;
      Result := Result + [mKey];
    end;
    mKey := Key('Atlas.SearchNext', TAtlasStrings.Text(TAtlasTextId.SearchNextCommand), mSettings.SearchNextKey,
      TAtlasKeyPriority.Take);
    mKey.Attempt := SearchStep(False);
    Result := Result + [mKey];
    mKey := Key('Atlas.SearchPrevious', TAtlasStrings.Text(TAtlasTextId.SearchPreviousCommand),
      mSettings.SearchPreviousKey,
      TAtlasKeyPriority.Take);
    mKey.Attempt := SearchStep(True);
    Result := Result + [mKey];
  end;
  // In Methode suchen (#877): gewöhnlicher Editorbefehl.
  mKey := Key('Atlas.SearchInMethod', TAtlasStrings.Text(TAtlasTextId.SearchInMethodCommand), mSettings.SearchMethodKey,
    TAtlasKeyPriority.Shared);
  mKey.Run := ShowInMethod;
  Result := Result + [mKey];
  // Units suchen (#777): aus = keine eigene Taste (die IDE behält Strg+F12 für ihren Dialog).
  if mSettings.UnitSearchEnabled then
  begin
    mKey := Key('Atlas.UnitSearch', TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle), mSettings.UnitSearchKey,
      TAtlasKeyPriority.Shared);
    mKey.Run := ShowUnitSearchGuarded;
    Result := Result + [mKey];
  end;
end;

procedure TAtlasSearchModule.ApplySettings;
begin
  // search.resultsInMessages (#878) und Co.
  TAtlasIdeSearch.ApplySettings;
  // query.enabled (#1351).
  TAtlasIdeCodeQuery.ApplySettings;
end;

procedure TAtlasSearchModule.ThemeChanged;
begin
  TAtlasIdeCodeQuery.ThemeChanged;
  TAtlasIdeSearch.ThemeChanged;
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasSearchUnitSearchSection.ProvideIn(GScope);
  TAtlasSearchQuerySection.ProvideIn(GScope);
end;

function TAtlasSearchModule.TakenActions: TArray<TAtlasTakenAction>;
var
  mAction: TBasicAction;
  mTaken: TAtlasTakenAction;
begin
  Result := nil;
  mAction := TAtlasIdeUnitSearch.HookedAction;
  if (mAction = nil) or (mAction.Name = '') then
  begin
    Exit;
  end;
  mTaken := Default(TAtlasTakenAction);
  mTaken.Func := TAtlasKeyFunction.UnitSearchIde;
  mTaken.ActionName := mAction.Name;
  Result := [mTaken];
end;

class function TAtlasSearchModule.Parts: TArray<IAtlasFeaturePart>;
begin
  // Wie bisher mit den Editorbefehlen ab dem abgesicherten Start; ihre Einstellungen prüfen die Teile selbst.
  Result := [
    TAtlasFeaturePart.AtLevel('Search', TAtlasSafeLevel.Safe, SearchStarted, StartSearch, StopSearch),
    TAtlasFeaturePart.AtLevel('UnitSearch', TAtlasSafeLevel.Safe, UnitSearchStarted, StartUnitSearch,
      StopUnitSearch),
    TAtlasFeaturePart.AtLevel('Query', TAtlasSafeLevel.Safe, QueryStarted, StartQuery, StopQuery)];
end;

class function TAtlasSearchModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasSearchModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry = nil) or (GScope <> nil) then
  begin
    Exit;
  end;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + cModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasSearchModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  GScope.Provide(IAtlasTakenActions, mRef);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasSearchModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
  begin
    Exit;
  end;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
  begin
    for mFailure in mRegistry.UnregisterModule(cModuleId) do
    begin
      TAtlasGuard.Log('Modul ' + cModuleId + ' nicht sauber abgemeldet: ' + mFailure);
    end;
  end;
end;

initialization
  TAtlasSearchModule.RegisterModule;

finalization
  TAtlasSearchModule.UnregisterModule;

end.
