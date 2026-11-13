unit Atlas.IDE.Analysis.Composition;

// Modul Analyse (#1455): einzige Unit, die die Fenster
// „Atlas-Architektur“ (#1118, teuerste Units #554), „Unit-Beziehungen“ (#593,
// Kosten einer interface-Änderung #554), „Atlas-Hotspots“ (#1354) und den Weg
// zwischen Symbolen (#1117) und die Code Lens mit Code-Metriken (#66, #1756)
// einbindet. Sie meldet in ihrer Initialisierung das
// Modul „atlas.analysis“ (Modulschalter analysis, #1454) bei der Registry von
// Base an und stellt über dessen Scope bereit:
// - die Teile Architecture, UnitRelations, Hotspots, SymbolPath und
//   MetricsLens der Feature-Tabelle,
// - Befehle (Palette), Einträge im Atlas-Menü, unter Ansicht › Atlas,
//   „Weg von hier nach …“ im Kontextmenü des Editors sowie „Unit-Beziehungen“
//   und „Abhängige Units (n)“ im Kontextmenü der Projektverwaltung (#1817; nur
//   für genau eine Unit, n aus dem gemerkten Stand) und den Assistenten
//   „Unit nach Architekturrolle“ in Datei › Neu › Weitere (#1821,
//   Atlas.IDE.Architecture.RoleUnit),
// - Hörer für Einstellungen und Thema.
// Das Feld „interface-Änderung“ im Atlas-Statusfeld setzt das Modul über
// TAtlasIdeHost und nimmt es beim Stoppen zurück. Befehle an den Server
// gehen über TAtlasIdeHost: Antworten erreichen das Modul nur, solange es
// angemeldet ist (Regel 3). Die Darstellung eines Wegs im Ergebnisfenster
// (Core.SymbolPath.Model, UI.SymbolPath.Chain) liegt in Base, weil das
// Ergebnisfenster sie zeigt. Die Werte der Metrik-Lens holt Base
// (Atlas.IDE.Editor.MetricsSource), weil die Atlas-Statusleiste sie ebenfalls
// liest. „Graph zeigen“ an einem Unit-Zyklus (#896) ruft
// Base über die Befehls-Id Atlas.UnitDependencies.
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

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
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    procedure ApplySettings;
    procedure ThemeChanged;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.UI.Analysis.SettingsSection,
  System.Types,
  System.JSON,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Host,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Commands.ProjectSelection,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Architecture.Service,
  Atlas.IDE.Architecture.RoleUnit,
  Atlas.IDE.UnitRelations.Service,
  Atlas.IDE.Hotspots.Service,
  Atlas.IDE.SymbolPath.Service,
  Atlas.IDE.Analysis.MetricsLens,
  Atlas.UI.Strings,
  Atlas.UI.Analysis.Strings;

const
  /// <summary>Feld im Atlas-Statusfeld für die Kosten einer interface-Änderung (#554).</summary>
  cInterfaceCostField = 'interfaceCost';

var
  GScope: IAtlasModuleScope;
  GArchitectureStarted: Boolean;
  GUnitRelationsStarted: Boolean;
  GHotspotsStarted: Boolean;
  GSymbolPathStarted: Boolean;
  GMetricsLens: TAtlasAnalysisMetricsLens;

{ Gemeinsam }

function ActiveSession: TLspSession;
begin
  Result := TAtlasIdeHost.ActiveSession;
end;

/// <summary>Befehl über den einen Hintergrundbefehl von Base; startet den Server bei Bedarf.</summary>
function RunCommand(AFeature: TAtlasFeature): TAtlasArchitectureRun;
begin
  Result :=
    function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
    begin
      Result := (TAtlasIdeHost.ActiveSession <> nil) and
        TAtlasIdeHost.RunCommandAsync(GScope, AFeature, ACommand, AArgumentsJson, ATimeoutMs, ADone);
    end;
end;

{ Architektur (#1118) }

procedure ShowUnitRelationsOf(AFileName: string);
begin
  TAtlasIdeUnitRelations.ShowFor(AFileName);
end;

procedure StartArchitecture;
begin
  TAtlasIdeArchitecture.Install(RunCommand(TAtlasFeature.Architecture));
  // Strg+Doppelklick in der Architekturkarte zeigt die Unit dort.
  TAtlasIdeArchitecture.OnUnitRelations := ShowUnitRelationsOf;
  GArchitectureStarted := True;
end;

procedure StopArchitecture;
begin
  GArchitectureStarted := False;
  TAtlasIdeArchitecture.OnUnitRelations := nil;
  TAtlasIdeArchitecture.Uninstall;
end;

function ArchitectureStarted: Boolean;
begin
  Result := GArchitectureStarted;
end;

{ Unit-Beziehungen (#593) }

/// <summary>Antwort als JSON-Wert an ADone (nil ohne Antwort); der Wert wird danach freigegeben. Eigene Routine,
/// damit die anonyme Methode nur ADone einfängt.</summary>
function JsonAnswer(const ADone: TProc<TJSONValue>): TProc<string>;
begin
  Result :=
    procedure(AText: string)
    var
      mValue: TJSONValue;
    begin
      mValue := nil;
      if AText <> '' then
      begin
        mValue := TJSONValue.ParseJSONValue(AText);
      end;
      try
        ADone(mValue);
      finally
        mValue.Free;
      end;
    end;
end;

/// <summary>Fragt regelmäßig nach, daher nebenläufig zum einen Hintergrundbefehl (der bliebe sonst für Architektur
/// und Co. belegt); startet keinen Server.</summary>
function UnitRelationsRun(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TProc<TJSONValue>): Boolean;
begin
  Result := TAtlasIdeHost.RunServerCommandAsync(GScope, TAtlasFeature.UnitRelations, ACommand, AArgumentsJson,
    ATimeoutMs, JsonAnswer(ADone));
end;

procedure ShowCurrentUnit;
begin
  TAtlasGuard.Run(TAtlasFeature.UnitRelations, TAtlasIdeUnitRelations.ShowCurrent);
end;

procedure ShowCostClicked(APoint: TPoint);
begin
  ShowCurrentUnit;
end;

/// <summary>Kosten einer interface-Änderung (#554) im Atlas-Statusfeld; Klick zeigt die Abhängigkeiten.</summary>
procedure ShowInterfaceCost(const AText, AHint: string);
begin
  if AText = '' then
  begin
    TAtlasIdeHost.SetStatusField(cInterfaceCostField, '', '', nil);
  end
  else
  begin
    TAtlasIdeHost.SetStatusField(cInterfaceCostField, AText, AHint, ShowCostClicked);
  end;
end;

procedure StartUnitRelations;
begin
  TAtlasIdeUnitRelations.Install(UnitRelationsRun);
  TAtlasIdeUnitRelations.SetCostHandler(ShowInterfaceCost);
  GUnitRelationsStarted := True;
end;

procedure StopUnitRelations;
begin
  GUnitRelationsStarted := False;
  // Base hält danach keinen Klick des Moduls mehr (Regel 3).
  TAtlasIdeHost.SetStatusField(cInterfaceCostField, '', '', nil);
  TAtlasIdeUnitRelations.Uninstall;
end;

function UnitRelationsStarted: Boolean;
begin
  Result := GUnitRelationsStarted;
end;

{ Hotspots (#1354) }

/// <summary>Nebenläufig zu anderen Befehlen, weil das Fenster nachfragt, solange der Server im Hintergrund rechnet;
/// startet den Server bei Bedarf.</summary>
function HotspotsRun(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TProc<string>): Boolean;
begin
  Result := (TAtlasIdeHost.ActiveSession <> nil) and TAtlasIdeHost.RunServerCommandAsync(GScope,
    TAtlasFeature.Hotspots, ACommand, AArgumentsJson, ATimeoutMs, ADone);
end;

procedure ShowImpactAtCursor;
begin
  // „Auswirkungen anzeigen“ (#1120) auf der Methode, auf die das Fenster den Cursor setzt.
  TAtlasIdeImpact.ShowAtCursor;
end;

procedure StartHotspots;
begin
  TAtlasIdeHotspots.Install(HotspotsRun);
  TAtlasIdeHotspots.OnImpact := ShowImpactAtCursor;
  GHotspotsStarted := True;
end;

procedure StopHotspots;
begin
  GHotspotsStarted := False;
  TAtlasIdeHotspots.OnImpact := nil;
  TAtlasIdeHotspots.Uninstall;
end;

function HotspotsStarted: Boolean;
begin
  Result := GHotspotsStarted;
end;

{ Weg zwischen Symbolen (#1117) }

procedure StartSymbolPath;
begin
  // Suche über den Hintergrundbefehl, Vorschläge aus der Symbolsuche.
  TAtlasIdeSymbolPath.Install(RunCommand(TAtlasFeature.SymbolPath), ActiveSession);
  GSymbolPathStarted := True;
end;

procedure StopSymbolPath;
begin
  GSymbolPathStarted := False;
  TAtlasIdeSymbolPath.Uninstall;
end;

function SymbolPathStarted: Boolean;
begin
  Result := GSymbolPathStarted;
end;

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

{ Code Lens mit Code-Metriken (#66, #1756) }

procedure StartMetricsLens;
begin
  GMetricsLens := TAtlasAnalysisMetricsLens.Create;
end;

procedure StopMetricsLens;
begin
  FreeAndNil(GMetricsLens);
end;

function MetricsLensStarted: Boolean;
begin
  Result := GMetricsLens <> nil;
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

function TAtlasAnalysisModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Architekturübersicht (#1118); nur sichtbar, solange architecture.enabled an ist.
    Command('Atlas.Architecture', TAtlasAnalysisTextId.ArchitectureCommand,
      Guarded(TAtlasFeature.Architecture, ShowArchitecture), ArchitectureVisible),
    // Hotspots (#1354); nur sichtbar, solange hotspots.enabled an ist.
    Command('Atlas.Hotspots', TAtlasAnalysisTextId.HotspotsCommand, Guarded(TAtlasFeature.Hotspots, ShowHotspots),
      HotspotsVisible),
    // Unit-Beziehungen (#593); am selben Schalter wie die Architektur (derselbe Uses-Graph).
    Command('Atlas.UnitRelations', TAtlasAnalysisTextId.UnitRelationsCommand,
      Guarded(TAtlasFeature.UnitRelations, ShowUnitRelations), UnitRelationsVisible),
    // Kosten einer interface-Änderung (#554): Verwender nach Abschnitt und verschiebbare uses der Unit im Editor,
    // dazu die teuersten Units in der Architekturübersicht.
    Command('Atlas.UnitDependencies', TAtlasAnalysisTextId.UnitDependenciesCommand, ShowCurrentUnit,
      UnitRelationsVisible),
    Command('Atlas.InterfaceCostRanking', TAtlasAnalysisTextId.InterfaceCostRankingCommand,
      Guarded(TAtlasFeature.Architecture, ShowRanking), ArchitectureVisible),
    // Weg zwischen Symbolen (#1117); nur sichtbar, solange navigation.symbolPath an ist.
    Command('Atlas.SymbolPath', TAtlasAnalysisTextId.SymbolPathCommand,
      Guarded(TAtlasFeature.SymbolPath, ShowSymbolPath),
      SymbolPathVisible),
    Command('Atlas.SymbolPathFromHere', TAtlasAnalysisTextId.SymbolPathFromHere,
      Guarded(TAtlasFeature.SymbolPath, SymbolPathFromHere), SymbolPathVisible),
    // Assistent in Datei › Neu › Weitere (#1821); auch in der Palette.
    Described(Command('Atlas.NewRoleUnit', TAtlasAnalysisTextId.RoleUnitCommand,
      Guarded(TAtlasFeature.Generate, NewRoleUnit), nil), TAtlasAnalysisTextId.RoleUnitHint),
    // Kontextmenü der Projektverwaltung (#1817); außerhalb unsichtbar.
    Command('Atlas.ProjectUnitRelations', TAtlasAnalysisTextId.ProjectUnitRelations,
      Guarded(TAtlasFeature.UnitRelations, ShowProjectUnitRelations), ProjectUnitVisible),
    Command('Atlas.ProjectDependents', TAtlasAnalysisTextId.ProjectDependents,
      Guarded(TAtlasFeature.UnitRelations, ShowProjectDependents), ProjectUnitVisible)];
  // Text mit der Zahl der Verwender, sobald sie bekannt ist.
  Result[High(Result)].Caption := DependentsCaption;
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

/// <summary>Eintrag unter Ansicht › Atlas mit eigenem Text.</summary>
function ViewEntry(const ACommandId: string; ACaption: TAtlasAnalysisTextId): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.ViewMenu);
  Result.Caption := TAtlasAnalysisStrings.Text(ACaption);
end;

function TAtlasAnalysisModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    MenuEntry('Atlas.Architecture', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.Hotspots', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.UnitRelations', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.SymbolPath', TAtlasMenuPlace.AtlasMenu),
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
  if GMetricsLens <> nil then
  begin
    GMetricsLens.ApplySettings;
  end;
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasAnalysisSettingsSection.ProvideIn(GScope);
  TAtlasAnalysisEditorSection.ProvideIn(GScope);
end;

procedure TAtlasAnalysisModule.ThemeChanged;
begin
  TAtlasIdeArchitecture.ThemeChanged;
  TAtlasIdeHotspots.ThemeChanged;
  TAtlasIdeUnitRelations.ThemeChanged;
end;

class function TAtlasAnalysisModule.Parts: TArray<IAtlasFeaturePart>;
begin
  // Wie bisher mit den Editorbefehlen ab dem abgesicherten Start; ihre Einstellungen prüfen die Teile selbst.
  Result := [
    TAtlasFeaturePart.AtLevel('Architecture', TAtlasSafeLevel.Safe, ArchitectureStarted, StartArchitecture,
      StopArchitecture),
    TAtlasFeaturePart.AtLevel('UnitRelations', TAtlasSafeLevel.Safe, UnitRelationsStarted, StartUnitRelations,
      StopUnitRelations),
    TAtlasFeaturePart.AtLevel('Hotspots', TAtlasSafeLevel.Safe, HotspotsStarted, StartHotspots, StopHotspots),
    TAtlasFeaturePart.AtLevel('SymbolPath', TAtlasSafeLevel.Safe, SymbolPathStarted, StartSymbolPath,
      StopSymbolPath),
    TAtlasFeaturePart.AtLevel('MetricsLens', TAtlasSafeLevel.Safe, MetricsLensStarted, StartMetricsLens,
      StopMetricsLens)];
end;

class function TAtlasAnalysisModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasAnalysisModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasAnalysisModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasAnalysisModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, nil);
end;

initialization
  TAtlasAnalysisModule.RegisterModule;

finalization
  TAtlasAnalysisModule.UnregisterModule;

end.
