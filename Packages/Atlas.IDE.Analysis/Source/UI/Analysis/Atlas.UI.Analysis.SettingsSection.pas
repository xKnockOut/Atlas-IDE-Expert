unit Atlas.UI.Analysis.SettingsSection;

// Abschnitt „Allgemein“ des Moduls Analyse im Optionsdialog (#1456, ADR 0017 Entscheidung 3; vorher im Teil
// „Allgemein“ von Base): Modulschalter, Architekturübersicht (#1118) und Hotspots (#1354). Die Unterpunkte
// „Architektur“ und „Hotspots“ entstehen über x-node. Auf der Seite „Editor“ (Unterpunkt Code Lens) steht die
// Code Lens mit Code-Metriken (#66, #1756; vorher im Teil „Editor“ von Base), darum eine zweite Klasse.

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasAnalysisSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.analysis';
    cAreaId = 'Allgemein';
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

  TAtlasAnalysisEditorSection = class(TAtlasSettingsSection)
  public const
    cAreaId = 'Editor';
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

implementation

uses
  Atlas.UI.Analysis.Strings;

{ TAtlasAnalysisSettingsSection }

function TAtlasAnalysisSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasAnalysisSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasAnalysisSettingsSection.BuildRows;
begin
  ModuleSwitch('analysis.enabled');
  // Architekturübersicht (#1118); Reihenfolge wie die Werte von architecture.scope (projectGroup, project).
  Switch('architecture.enabled', TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SettingsArchitecture));
  Choice('architecture.scope', TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SettingsArchitectureScope),
    [TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureScopeGroup),
    TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureScopeProject)], ['projectGroup', 'project']);
  Switch('architecture.includeLibraryUnits', TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SettingsArchitectureLibrary));
  Number('architecture.centralUnits', TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SettingsArchitectureCentral));
  // Hotspots (#1354).
  Switch('hotspots.enabled', TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SettingsHotspots));
  Number('hotspots.months', TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SettingsHotspotsMonths));
  Number('hotspots.coupling.minCommits', TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SettingsHotspotsMinCommits));
end;

{ TAtlasAnalysisEditorSection }

function TAtlasAnalysisEditorSection.OwnerId: string;
begin
  Result := TAtlasAnalysisSettingsSection.cOwnerId;
end;

function TAtlasAnalysisEditorSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasAnalysisEditorSection.BuildRows;
begin
  Switch('codeLens.metrics', TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SettingsCodeLensMetrics));
end;

end.
