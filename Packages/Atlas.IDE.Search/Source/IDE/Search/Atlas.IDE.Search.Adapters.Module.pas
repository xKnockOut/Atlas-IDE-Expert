unit Atlas.IDE.Search.Adapters.Module;

// Modulklasse der Suche (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Search.Composition) über den Scope des Moduls bereitstellt: Befehle und Menüeinträge von Units suchen
// (#777, #786), Atlas-Suche (#877, #878, #893) und Atlas-Abfrage (#1351), ihre Tasten, übernommene Einstellungen,
// das Thema und die übernommene IDE-Aktion von Strg+F12.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Commands.Contract;

type
  TAtlasSearchModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource, IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasTakenActions)
  public const
    cModuleId = 'atlas.search';
    cSwitch = 'search';
  private
    FActive: Boolean;
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
  end;

implementation

uses
  System.Classes,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.ExitPoints,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Search.Commands,
  Atlas.IDE.UnitSearch.Commands,
  Atlas.IDE.Query.Service,
  Atlas.UI.Strings,
  Atlas.UI.Search.Strings,
  Atlas.Core.Modules.Contributions;

{ Befehle }

function Command(const AId: string; const ACaption: string; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := TAtlasModuleContributions.NewCommand(AId, ACaption, ARun, AVisible);
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
function TAtlasSearchModule.Info: TAtlasModuleInfo;
begin
  // Lief mit den Editorbefehlen schon im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Suche', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
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
function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;
/// <summary>Eintrag im eigenen Untermenü des Atlas-Menüs („-“ = Trennlinie).</summary>
function AtlasEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.AtlasMenu);
  Result.Section := TAtlasSearchStrings.Text(TAtlasSearchTextId.MenuGroupUnits);
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
      TAtlasGuard.Wrap(TAtlasFeature.Query, ShowQuery), QueryVisible)];
end;
function TAtlasSearchModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    AtlasEntry('Atlas.UnitSearch'),
    // Der IDE-Dialog, falls Atlas Strg+F12 übernimmt.
    AtlasEntry('Atlas.UnitSearchIde'),
    AtlasEntry('Atlas.Query'),
    MenuEntry('Atlas.Query', TAtlasMenuPlace.ViewMenu),
    // Fenster „Atlas-Suche: Ersetzen“ auch unter Ansicht › Atlas.
    MenuEntry('Atlas.SearchReplace', TAtlasMenuPlace.ViewMenu)];
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

end.
