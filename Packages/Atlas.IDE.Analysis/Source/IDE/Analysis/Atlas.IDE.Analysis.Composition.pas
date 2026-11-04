unit Atlas.IDE.Analysis.Composition;

// Modul Analyse (#1455, ADR 0017): einzige Unit, die die Fenster
// „Atlas-Architektur“ (#1118, teuerste Units #554), „Unit-Beziehungen“ (#593,
// Kosten einer interface-Änderung #554), „Atlas-Hotspots“ (#1354) und den Weg
// zwischen Symbolen (#1117) einbindet. Sie meldet in ihrer Initialisierung das
// Modul „atlas.analysis“ (Modulschalter analysis, #1454) bei der Registry von
// Base an und stellt über dessen Scope bereit:
// - die Teile Architecture, UnitRelations, Hotspots und SymbolPath der
//   Feature-Tabelle,
// - Befehle (Palette), Einträge im Atlas-Menü, unter Ansicht › Atlas und
//   „Weg von hier nach …“ im Kontextmenü des Editors,
// - Hörer für Einstellungen und Thema.
// Das Feld „interface-Änderung“ im Atlas-Statusfeld setzt das Modul über
// TAtlasIdeHost und nimmt es beim Stoppen zurück. Befehle an den Server
// gehen über TAtlasIdeHost: Antworten erreichen das Modul nur, solange es
// angemeldet ist (Regel 3). Die Darstellung eines Wegs im Ergebnisfenster
// (Core.SymbolPath.Model, UI.SymbolPath.Chain) liegt in Base, weil das
// Ergebnisfenster sie zeigt. „Graph zeigen“ an einem Unit-Zyklus (#896) ruft
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
    ModuleId = 'atlas.analysis';
    Switch = 'analysis';
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
  System.Types,
  System.JSON,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Architecture.Service,
  Atlas.IDE.UnitRelations.Service,
  Atlas.IDE.Hotspots.Service,
  Atlas.IDE.SymbolPath.Service,
  Atlas.UI.Strings,
  Atlas.UI.Analysis.Strings;

const
  /// <summary>Feld im Atlas-Statusfeld für die Kosten einer interface-Änderung (#554).</summary>
  InterfaceCostField = 'interfaceCost';

var
  GScope: IAtlasModuleScope;
  GArchitectureStarted: Boolean;
  GUnitRelationsStarted: Boolean;
  GHotspotsStarted: Boolean;
  GSymbolPathStarted: Boolean;

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
    TAtlasIdeHost.SetStatusField(InterfaceCostField, '', '', nil);
  end
  else
  begin
    TAtlasIdeHost.SetStatusField(InterfaceCostField, AText, AHint, ShowCostClicked);
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
  TAtlasIdeHost.SetStatusField(InterfaceCostField, '', '', nil);
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

{ TAtlasAnalysisModule }

function TAtlasAnalysisModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := ModuleId;
  Result.Name := 'Analyse';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Lief mit den Editorbefehlen schon im abgesicherten Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := Switch;
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
      Guarded(TAtlasFeature.SymbolPath, SymbolPathFromHere), SymbolPathVisible)];
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
    MenuEntry('Atlas.SymbolPathFromHere', TAtlasMenuPlace.EditorContext)];
end;

procedure TAtlasAnalysisModule.ApplySettings;
begin
  // architecture.* (#1118), hotspots.* (#1354).
  TAtlasIdeArchitecture.ApplySettings;
  TAtlasIdeHotspots.ApplySettings;
  TAtlasIdeUnitRelations.ApplySettings;
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
      StopSymbolPath)];
end;

class function TAtlasAnalysisModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasAnalysisModule;
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
    TAtlasGuard.Log('Modul ' + ModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
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
  Result := True;
end;

class procedure TAtlasAnalysisModule.UnregisterModule;
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
    for mFailure in mRegistry.UnregisterModule(ModuleId) do
    begin
      TAtlasGuard.Log('Modul ' + ModuleId + ' nicht sauber abgemeldet: ' + mFailure);
    end;
  end;
end;

initialization
  TAtlasAnalysisModule.RegisterModule;

finalization
  TAtlasAnalysisModule.UnregisterModule;

end.
