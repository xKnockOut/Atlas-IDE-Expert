unit Atlas.IDE.Analysis.Adapters.Module;

// Modulklasse der Analyse (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Analysis.Composition) über den Scope des Moduls bereitstellt: Befehle (Palette), Einträge im
// Atlas-Menü, unter Ansicht › Atlas, „Weg von hier nach …“ im Kontextmenü des Editors sowie „Unit-Beziehungen“ und
// „Abhängige Units (n)“ im Kontextmenü der Projektverwaltung (#1817), den Assistenten „Unit nach Architekturrolle“
// (#1821) und Einstellungen und Thema an die Fenster. Die Code Lens mit Code-Metriken (#66) startet die Composition
// als Teil der Feature-Tabelle und reicht ihre Einstellungen als Methode herein.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasAnalysisModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasAppliesSettings, IAtlasFollowsTheme)
  public const
    cModuleId = 'atlas.analysis';
    cSwitch = 'analysis';
  private
    FActive: Boolean;
    FApplyLensSettings: TProc;
  public
    /// <summary>AApplyLensSettings gibt geänderte Einstellungen an die laufende Metrik-Lens.</summary>
    constructor Create(const AApplyLensSettings: TProc);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    procedure ApplySettings;
    procedure ThemeChanged;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Commands.ProjectSelection,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Architecture.Service,
  Atlas.IDE.Architecture.RoleUnit,
  Atlas.IDE.UnitRelations.Service,
  Atlas.IDE.Hotspots.Service,
  Atlas.IDE.SymbolPath.Service,
  Atlas.UI.Strings,
  Atlas.UI.Analysis.Strings;

/// <summary>„Weg von hier nach …“ im Kontextmenü des Editors; ohne Symbol am Cursor trotzdem der Dialog („Von“
/// lässt sich dort eintippen).</summary>
procedure SymbolPathFromHere;
var
  mName: string;
begin
  if not TAtlasIdeSymbolPath.Enabled then
  begin
    Exit;
  end;
  if not TAtlasIdeEditorCommands.QualifiedNameHere(mName) then
  begin
    mName := '';
  end;
  TAtlasIdeSymbolPath.ShowDialogFrom(mName);
end;

/// <summary>Unit-Beziehungen der Unit im Editor (#593), abgesichert.</summary>
procedure ShowCurrentUnit;
begin
  TAtlasGuard.Run(TAtlasFeature.UnitRelations, TAtlasIdeUnitRelations.ShowCurrent);
end;

{ Befehle }

function Command(const AId: string; ACaption: TAtlasAnalysisTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasAnalysisStrings.Text(ACaption);
  Result.Run := ARun;
  Result.Visible := AVisible;
end;
/// <summary>Assistent „Unit nach Architekturrolle“ (#1821).</summary>
procedure NewRoleUnit;
begin
  TAtlasIdeRoleUnit.Execute;
end;
function Described(const ACommand: TAtlasModuleCommand; ADescription: TAtlasAnalysisTextId): TAtlasModuleCommand;
begin
  Result := ACommand;
  Result.Description := TAtlasAnalysisStrings.Text(ADescription);
end;
// Sichtbar nach Schalter und Sicherung, wie bisher im Atlas-Menü.
function ArchitectureVisible: Boolean;
begin
  Result := TAtlasIdeArchitecture.Enabled;
end;
function UnitRelationsVisible: Boolean;
begin
  Result := TAtlasIdeUnitRelations.Enabled;
end;
function HotspotsVisible: Boolean;
begin
  Result := TAtlasIdeHotspots.Enabled;
end;
function SymbolPathVisible: Boolean;
begin
  Result := TAtlasIdeSymbolPath.Enabled;
end;
procedure ShowArchitecture;
begin
  TAtlasIdeArchitecture.ShowWindow;
end;
procedure ShowRanking;
begin
  TAtlasIdeArchitecture.ShowRanking;
end;
procedure ShowUnitRelations;
begin
  TAtlasIdeUnitRelations.ShowWindow;
end;
procedure ShowHotspots;
begin
  TAtlasIdeHotspots.ShowWindow;
end;
procedure ShowSymbolPath;
begin
  TAtlasIdeSymbolPath.ShowDialog;
end;

{ Projektverwaltung (#1817) }

/// <summary>Im Kontextmenü der Projektverwaltung mit genau einer Unit; AFileName erst beim Ausführen gesetzt.
/// </summary>
function ProjectUnit(out AFileName: string): Boolean;
begin
  Result := TAtlasProjectContext.Active and UnitRelationsVisible and
    TAtlasProjectContext.Current.SingleUnit(AFileName);
end;
function ProjectUnitVisible: Boolean;
var
  mFileName: string;
begin
  Result := ProjectUnit(mFileName);
end;
procedure ShowProjectUnitRelations;
var
  mFileName: string;
begin
  if ProjectUnit(mFileName) and (mFileName <> '') then
  begin
    TAtlasIdeUnitRelations.ShowFor(mFileName);
  end;
end;
procedure ShowProjectDependents;
var
  mFileName: string;
begin
  if ProjectUnit(mFileName) and (mFileName <> '') then
  begin
    TAtlasIdeUnitRelations.ShowDependents(mFileName);
  end;
end;
/// <summary>„Abhängige Units (n)“, sobald die Zahl bekannt ist (Auswahl mit Dateinamen, Antwort gemerkt).</summary>
function DependentsCaption: string;
var
  mFileName: string;
  mCount: Integer;
begin
  if ProjectUnit(mFileName) and TAtlasIdeUnitRelations.CachedDependents(mFileName, mCount) then
  begin
    Exit(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ProjectDependentsCount, [mCount]));
  end;
  Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ProjectDependents);
end;
{ TAtlasAnalysisModule }

constructor TAtlasAnalysisModule.Create(const AApplyLensSettings: TProc);
begin
  inherited Create;
  FApplyLensSettings := AApplyLensSettings;
end;

function TAtlasAnalysisModule.Info: TAtlasModuleInfo;
begin
  // Lief mit den Editorbefehlen schon im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Analyse', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
end;
procedure TAtlasAnalysisModule.Start;
begin
  FActive := True;
end;
procedure TAtlasAnalysisModule.Stop;
begin
  FActive := False;
end;
function TAtlasAnalysisModule.IsActive: Boolean;
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
  Result.Section := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MenuGroupAnalysis);
end;
/// <summary>Eintrag unter Ansicht › Atlas mit eigenem Text.</summary>
function ViewEntry(const ACommandId: string; ACaption: TAtlasAnalysisTextId): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.ViewMenu);
  Result.Caption := TAtlasAnalysisStrings.Text(ACaption);
end;
function TAtlasAnalysisModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Architekturübersicht (#1118); nur sichtbar, solange architecture.enabled an ist.
    Command('Atlas.Architecture', TAtlasAnalysisTextId.ArchitectureCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Architecture, ShowArchitecture), ArchitectureVisible),
    // Hotspots (#1354); nur sichtbar, solange hotspots.enabled an ist.
    Command('Atlas.Hotspots', TAtlasAnalysisTextId.HotspotsCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Hotspots, ShowHotspots), HotspotsVisible),
    // Unit-Beziehungen (#593); am selben Schalter wie die Architektur (derselbe Uses-Graph).
    Command('Atlas.UnitRelations', TAtlasAnalysisTextId.UnitRelationsCommand,
      TAtlasGuard.Wrap(TAtlasFeature.UnitRelations, ShowUnitRelations), UnitRelationsVisible),
    // Kosten einer interface-Änderung (#554): Verwender nach Abschnitt und verschiebbare uses der Unit im Editor,
    // dazu die teuersten Units in der Architekturübersicht.
    Command('Atlas.UnitDependencies', TAtlasAnalysisTextId.UnitDependenciesCommand, ShowCurrentUnit,
      UnitRelationsVisible),
    Command('Atlas.InterfaceCostRanking', TAtlasAnalysisTextId.InterfaceCostRankingCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Architecture, ShowRanking), ArchitectureVisible),
    // Weg zwischen Symbolen (#1117); nur sichtbar, solange navigation.symbolPath an ist.
    Command('Atlas.SymbolPath', TAtlasAnalysisTextId.SymbolPathCommand,
      TAtlasGuard.Wrap(TAtlasFeature.SymbolPath, ShowSymbolPath),
      SymbolPathVisible),
    Command('Atlas.SymbolPathFromHere', TAtlasAnalysisTextId.SymbolPathFromHere,
      TAtlasGuard.Wrap(TAtlasFeature.SymbolPath, SymbolPathFromHere), SymbolPathVisible),
    // Assistent in Datei › Neu › Weitere (#1821); auch in der Palette.
    Described(Command('Atlas.NewRoleUnit', TAtlasAnalysisTextId.RoleUnitCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Generate, NewRoleUnit), nil), TAtlasAnalysisTextId.RoleUnitHint),
    // Kontextmenü der Projektverwaltung (#1817); außerhalb unsichtbar.
    Command('Atlas.ProjectUnitRelations', TAtlasAnalysisTextId.ProjectUnitRelations,
      TAtlasGuard.Wrap(TAtlasFeature.UnitRelations, ShowProjectUnitRelations), ProjectUnitVisible),
    Command('Atlas.ProjectDependents', TAtlasAnalysisTextId.ProjectDependents,
      TAtlasGuard.Wrap(TAtlasFeature.UnitRelations, ShowProjectDependents), ProjectUnitVisible)];
  // Text mit der Zahl der Verwender, sobald sie bekannt ist.
  Result[High(Result)].Caption := DependentsCaption;
end;
function TAtlasAnalysisModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    AtlasEntry('Atlas.Architecture'),
    AtlasEntry('Atlas.Hotspots'),
    AtlasEntry('Atlas.UnitRelations'),
    AtlasEntry('Atlas.SymbolPath'),
    ViewEntry('Atlas.Architecture', TAtlasAnalysisTextId.ArchitectureViewMenu),
    ViewEntry('Atlas.Hotspots', TAtlasAnalysisTextId.HotspotsViewMenu),
    ViewEntry('Atlas.UnitRelations', TAtlasAnalysisTextId.UnitRelationsViewMenu),
    MenuEntry('Atlas.SymbolPathFromHere', TAtlasMenuPlace.EditorContext),
    MenuEntry('-', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.ProjectUnitRelations', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.ProjectDependents', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.NewRoleUnit', TAtlasMenuPlace.Gallery)];
end;
procedure TAtlasAnalysisModule.ApplySettings;
begin
  // architecture.* (#1118), hotspots.* (#1354), codeLens.metrics (#66).
  TAtlasIdeArchitecture.ApplySettings;
  TAtlasIdeHotspots.ApplySettings;
  TAtlasIdeUnitRelations.ApplySettings;
  FApplyLensSettings();
end;
procedure TAtlasAnalysisModule.ThemeChanged;
begin
  TAtlasIdeArchitecture.ThemeChanged;
  TAtlasIdeHotspots.ThemeChanged;
  TAtlasIdeUnitRelations.ThemeChanged;
end;

end.
