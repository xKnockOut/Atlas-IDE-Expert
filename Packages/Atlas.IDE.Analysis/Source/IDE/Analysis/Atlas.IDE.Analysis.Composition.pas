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
// Modulklasse, Befehle und Menüeinträge stehen in Atlas.IDE.Analysis.Adapters.Module.

interface

implementation

uses
  System.SysUtils,
  Atlas.UI.Analysis.SettingsSection,
  System.Types,
  System.JSON,
  Atlas.Text.Product.Version,
  Atlas.Core.Modules.Contract,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Architecture.Service,
  Atlas.IDE.UnitRelations.Service,
  Atlas.IDE.Hotspots.Service,
  Atlas.IDE.SymbolPath.Service,
  Atlas.IDE.Analysis.MetricsLens,
  Atlas.IDE.Analysis.Adapters.Module;

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

function Parts: TArray<IAtlasFeaturePart>;
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

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasAnalysisSettingsSection.ProvideIn(GScope);
  TAtlasAnalysisEditorSection.ProvideIn(GScope);
end;

/// <summary>codeLens.metrics (#66) an die laufende Metrik-Lens.</summary>
procedure ApplyLensSettings;
begin
  if GMetricsLens <> nil then
  begin
    GMetricsLens.ApplySettings;
  end;
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasAnalysisModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasAnalysisModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasAnalysisModule.Create(ApplyLensSettings);
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

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasAnalysisModule.cModuleId, HInstance, nil);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
