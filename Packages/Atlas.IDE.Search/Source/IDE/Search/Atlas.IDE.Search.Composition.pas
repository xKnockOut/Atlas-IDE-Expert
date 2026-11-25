unit Atlas.IDE.Search.Composition;

// Modul Suche (#1455): einzige Unit, die die Atlas-Suche (#877,
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
// Modulklasse, Befehle, Menü und Tasten stehen in Atlas.IDE.Search.Adapters.Module.

interface

implementation

uses
  System.SysUtils,
  Atlas.UI.Search.SettingsSection,
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.Core.Commands.Contract,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.IDE.Base.Core.Modules.FeatureParts,
  Atlas.Plugin.Lsp.Client,
  Atlas.Plugin.Lsp.Contract,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Query.Model,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Search.Commands,
  Atlas.IDE.UnitSearch.Commands,
  Atlas.IDE.Query.Service,
  Atlas.IDE.Search.Adapters.Module;

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

/// <summary>Befehl der Unit-Suche im Hintergrund, nebenläufig zu anderen Befehlen (atlas.server.units braucht bei
/// großen Gruppen Sekunden); startet keinen Server. Die Antwort nur, solange das Modul angemeldet ist.</summary>
function UnitSearchCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TProc<string>): Boolean;
begin
  Result := TAtlasIdeHost.RunServerCommandAsync(GScope, TAtlasFeature.UnitSearch, ACommand, AArgumentsJson,
    ATimeoutMs, ADone);
end;

procedure StartUnitSearch;
begin
  // Übernimmt Strg+F12, solange die Einstellungen es wollen.
  TAtlasIdeUnitSearch.Install(ActiveSession, Warn, UnitSearchCommand);
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

function Parts: TArray<IAtlasFeaturePart>;
begin
  // Wie bisher mit den Editorbefehlen ab dem abgesicherten Start; ihre Einstellungen prüfen die Teile selbst.
  Result := [
    TAtlasFeaturePart.AtLevel('Search', TAtlasSafeLevel.Safe, SearchStarted, StartSearch, StopSearch),
    TAtlasFeaturePart.AtLevel('UnitSearch', TAtlasSafeLevel.Safe, UnitSearchStarted, StartUnitSearch,
      StopUnitSearch),
    TAtlasFeaturePart.AtLevel('Query', TAtlasSafeLevel.Safe, QueryStarted, StartQuery, StopQuery)];
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasSearchUnitSearchSection.ProvideIn(GScope);
  TAtlasSearchQuerySection.ProvideIn(GScope);
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasSearchModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasSearchModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
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

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasSearchModule.cModuleId, HInstance, nil);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
