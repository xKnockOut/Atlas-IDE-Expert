unit Atlas.IDE.Architecture.Service;

// Fenster „Atlas-Architektur“ (#1118) in der IDE:
// - ShowWindow zeigt das Fenster (Ansicht › Atlas › Architektur,
//   Befehlspalette Atlas.Architecture) und rechnet beim ersten Öffnen.
// - Refresh fragt den Server mit atlas.architecture für das aktive Projekt
//   (Umfang und Bibliotheks-Units aus den Einstellungen) im Hintergrund; die
//   Antwort liest TAtlasArchitectureModel noch im Hintergrund, gezeigt wird im
//   Hauptthread. Eine ältere Antwort, die nach einer neueren Anfrage kommt,
//   fällt weg.
// - Umfang und „Bibliotheks-Units“ im Fenster schreiben architecture.scope
//   bzw. architecture.includeLibraryUnits (settings.json, wie der Server) und
//   rechnen neu.
// - Regler „Feinheit“ (#1366): Wert und Sichtbarkeit aus architecture.grouping
//   in settings.json (TAtlasArchitectureGroupingSettings); Loslassen schreibt
//   den Wert dorthin und rechnet neu (Anfrage mit "resolution", die alte
//   Karte bleibt bis zur Antwort stehen). Berichte nehmen denselben Wert mit.
// - „Bericht speichern …“ geht an atlas.architecture.saveReport; der Server
//   schreibt HTML oder Markdown nach der Endung, „Stand speichern …“ (#1121)
//   ebenso den Stand als .json.
// - Vergleich (#1121): Ohne Wahl vergleicht der Server mit
//   architecture.baseline; „Vergleichen mit …“ setzt den Stand für diese
//   Sitzung ("compareWith"), „Vergleich aufheben“ schaltet ihn ab ("compare":
//   false). Beides gilt auch für gespeicherte Berichte.
// - „Teilsysteme neu benennen“ (#1367, Menü „Teilsysteme ▾“) schickt einmal
//   "renameSubsystems": Der Server rechnet ohne Angleichung an den vorigen
//   Stand.
// - Doppelklick öffnet die Unit bzw. springt zum uses-Eintrag; Strg+Doppelklick
//   auf eine Unit zeigt sie im Fenster „Unit-Beziehungen“ (#593) über
//   OnUnitRelations, das die Zusammensetzung setzt.
// - ShowRanking (Befehl „Teuerste Units bei interface-Änderungen“, #554)
//   zeigt das Fenster auf „Zentrale Units“, sortiert nach „gesamt abhängig“
//   (RecompileCount des Uses-Graphen).
// - architecture.enabled aus schließt das Fenster.
// - ShowRoute (#1117) zeigt das Fenster mit einem Weg aus „Weg zwischen
//   Symbolen“ auf der Karte; fehlen die Daten noch, wird erst gerechnet und
//   der Weg danach markiert.
// Den Server erreicht der Dienst über ARun (Install), damit er die
// Zusammensetzung des Plugins nicht kennen muss. Nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  /// <summary>Befehl des Servers im Hintergrund (wie TAtlasCodeInsightManager.RunCommandAsync); ADone bekommt
  /// die Antwort ('' bei Fehler oder Zeitlimit). False = nicht gestartet (kein Server).</summary>
  TAtlasArchitectureRun = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<string>): Boolean;

  TAtlasIdeArchitecture = class
  private class var
    FState: TObject;
  public class var
    /// <summary>Strg+Doppelklick auf eine Unit (#593); setzt die Zusammensetzung des Plugins.</summary>
    OnUnitRelations: TProc<string>;
  public
    class procedure Install(const ARun: TAtlasArchitectureRun); static;
    class procedure Uninstall; static;
    /// <summary>Fenster zeigen; nichts, solange architecture.enabled aus ist.</summary>
    class procedure ShowWindow; static;
    /// <summary>Fenster auf „Zentrale Units“ nach „gesamt abhängig“ absteigend (#554).</summary>
    class procedure ShowRanking; static;
    /// <summary>Fenster zeigen und die Units AUnits (Reihenfolge des Wegs) als Weg markieren (#1117); False,
    /// solange architecture.enabled aus ist.</summary>
    class function ShowRoute(const AUnits: TArray<string>): Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    class function Enabled: Boolean; static;
  end;

implementation

uses
  System.Classes,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Architecture.Model,
  Atlas.Core.Architecture.Commands,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Analysis.Strings,
  Atlas.UI.Architecture.Frame,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Architecture.Window;

const
  /// <summary>Große Projektgruppen brauchen beim ersten Mal einige Sekunden (Index, Fundstellen).</summary>
  cTimeoutMs = 120000;

type
  TArchitectureState = class
  private
    FRun: TAtlasArchitectureRun;
    /// <summary>Nummer der letzten Anfrage; ältere Antworten fallen weg.</summary>
    FRequest: Integer;
    /// <summary>Eine Anfrage läuft (Antwort steht aus).</summary>
    FPending: Boolean;
    FScope: string;
    FIncludeLibrary: Boolean;
    /// <summary>Feinheit γ aus architecture.grouping.resolution (#1366).</summary>
    FResolution: Double;
    FShowResolution: Boolean;
    /// <summary>Gewählter Stand ("compareWith"); '' = architecture.baseline bzw. keiner.</summary>
    FCompareWith: string;
    /// <summary>False nach „Vergleich aufheben“.</summary>
    FCompare: Boolean;
    /// <summary>Weg (#1117), der nach der nächsten Antwort markiert wird; nil = keiner.</summary>
    FRoute: TArray<string>;
    /// <summary>Nächste Anfrage ohne Angleichung an den vorigen Stand („Teilsysteme neu benennen“, #1367).
    /// </summary>
    FRename: Boolean;
    procedure Wire(AFrame: TAtlasArchitectureFrame);
    /// <summary>Knöpfe Aktualisieren, Speichern und Vergleichen.</summary>
    procedure WireCommands(AFrame: TAtlasArchitectureFrame);
    /// <summary>Umfang, Bibliotheks-Units, Feinheit und „Teilsysteme neu benennen“.</summary>
    procedure WireOptions(AFrame: TAtlasArchitectureFrame);
    /// <summary>Antwort auf die Anfrage ARequest im Hauptthread zeigen.</summary>
    procedure ShowAnswer(ARequest: Integer; AParsed, AEnabled: Boolean; const AModel: TAtlasArchitectureModel);
    function AnswerHandler(ARequest: Integer): TProc<string>;
    function ProjectUri(out AUri: string): Boolean;
    procedure ChangeScope(const AScope: string);
    procedure ChangeLibrary(AValue: Boolean);
    procedure ChangeResolution(AValue: Double);
    /// <summary>architecture.grouping aus settings.json lesen; True, wenn sich die Feinheit geändert hat.</summary>
    function ReadGrouping: Boolean;
    function Options: TAtlasArchitectureOptions;
    procedure CompareWith(const AFileName: string);
    procedure ClearComparison;
    procedure RenameSubsystems;
  public
    constructor Create(const ARun: TAtlasArchitectureRun);
    destructor Destroy; override;
    procedure Refresh;
    /// <summary>Rechnen, wenn das Fenster noch nichts zeigt und keine Anfrage läuft.</summary>
    procedure EnsureData;
    procedure Save(const AFileName: string);
    procedure ApplySettings;
    /// <summary>Weg auf der Karte markieren, sobald Daten da sind.</summary>
    procedure ShowRoute(const AUnits: TArray<string>);
    /// <summary>Wartenden Weg markieren; nichts ohne Weg oder Daten.</summary>
    procedure ApplyRoute;
  end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.ArchitectureEnabled and not TAtlasGuard.Disabled(TAtlasFeature.Architecture);
end;

{ TArchitectureState }

constructor TArchitectureState.Create(const ARun: TAtlasArchitectureRun);
begin
  inherited Create;
  FRun := ARun;
  FCompare := True;
  FScope := TAtlasIdeSettings.Current.ArchitectureScope;
  FIncludeLibrary := TAtlasIdeSettings.Current.ArchitectureIncludeLibraryUnits;
  ReadGrouping;
  TAtlasIdeArchitectureWindow.OnFrame :=
    procedure(AFrame: TAtlasArchitectureFrame)
    begin
      Wire(AFrame);
    end;
  // Früh anmelden, damit die IDE das Fenster im Desktop speichert und wiederherstellt (#879).
  TAtlasIdeArchitectureWindow.Prepare;
  // Das Fenster gab es schon (Paket neu geladen): neu verdrahten.
  if TAtlasIdeArchitectureWindow.ExistingFrame <> nil then
  begin
    Wire(TAtlasIdeArchitectureWindow.ExistingFrame);
  end;
end;

destructor TArchitectureState.Destroy;
var
  mFrame: TAtlasArchitectureFrame;
begin
  // Antworten, die noch unterwegs sind, finden FState nicht mehr und fallen weg.
  Inc(FRequest);
  TAtlasIdeArchitectureWindow.OnFrame := nil;
  mFrame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.OnRefresh := nil;
    mFrame.OnSave := nil;
    mFrame.OnSaveState := nil;
    mFrame.OnCompare := nil;
    mFrame.OnClearComparison := nil;
    mFrame.OnScopeChanged := nil;
    mFrame.OnLibraryChanged := nil;
    mFrame.OnResolutionChanged := nil;
    mFrame.OnRenameSubsystems := nil;
    mFrame.OnOpenUnit := nil;
    mFrame.OnOpenLocation := nil;
    mFrame.OnUnitRelations := nil;
  end;
  inherited Destroy;
end;

procedure TArchitectureState.WireCommands(AFrame: TAtlasArchitectureFrame);
begin
  AFrame.OnRefresh :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Architecture,
        procedure
        begin
          Refresh;
        end);
    end;
  AFrame.OnSave :=
    procedure(AFileName: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Architecture,
        procedure
        begin
          Save(AFileName);
        end);
    end;
  // Der Server unterscheidet Bericht und Stand an der Endung.
  AFrame.OnSaveState := AFrame.OnSave;
  AFrame.OnCompare :=
    procedure(AFileName: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Architecture,
        procedure
        begin
          CompareWith(AFileName);
        end);
    end;
  AFrame.OnClearComparison :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Architecture,
        procedure
        begin
          ClearComparison;
        end);
    end;
end;

procedure TArchitectureState.WireOptions(AFrame: TAtlasArchitectureFrame);
begin
  AFrame.OnScopeChanged :=
    procedure(AScope: string)
    begin
      ChangeScope(AScope);
    end;
  AFrame.OnLibraryChanged :=
    procedure(AValue: Boolean)
    begin
      ChangeLibrary(AValue);
    end;
  AFrame.OnResolutionChanged :=
    procedure(AValue: Double)
    begin
      TAtlasGuard.Run(TAtlasFeature.Architecture,
        procedure
        begin
          ChangeResolution(AValue);
        end);
    end;
  AFrame.OnRenameSubsystems :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Architecture,
        procedure
        begin
          RenameSubsystems;
        end);
    end;
end;

procedure TArchitectureState.Wire(AFrame: TAtlasArchitectureFrame);
begin
  AFrame.ScopeValue := FScope;
  AFrame.IncludeLibrary := FIncludeLibrary;
  AFrame.ResolutionValue := FResolution;
  AFrame.ShowResolution := FShowResolution;
  WireCommands(AFrame);
  WireOptions(AFrame);
  AFrame.OnOpenUnit :=
    procedure(AFileName: string)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, 0, 0);
    end;
  AFrame.OnOpenLocation :=
    procedure(AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine - 1, ACharacter - 1);
    end;
  AFrame.OnUnitRelations :=
    procedure(AFileName: string)
    begin
      if Assigned(TAtlasIdeArchitecture.OnUnitRelations) then
      begin
        TAtlasIdeArchitecture.OnUnitRelations(AFileName);
      end
      else
      begin
        TAtlasIdeNavigation.GoToLocation(AFileName, 0, 0);
      end;
    end;
  // Vom Desktop wiederhergestellt: rechnen, sobald der Aufbau durch ist (dann ist meist auch das Projekt da).
  TAtlasMainThread.Queue(TAtlasFeature.Architecture,
    procedure
    begin
      if (TAtlasIdeArchitecture.FState = Self) and Active and TAtlasIdeArchitectureWindow.Visible then
      begin
        EnsureData;
      end;
    end);
end;

procedure TArchitectureState.EnsureData;
var
  mFrame: TAtlasArchitectureFrame;
begin
  mFrame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if (mFrame <> nil) and not mFrame.HasModel and not FPending then
  begin
    Refresh;
  end;
end;

function TArchitectureState.ProjectUri(out AUri: string): Boolean;
var
  mProject: IOTAProject;
begin
  AUri := '';
  mProject := GetActiveProject;
  Result := (mProject <> nil) and (mProject.FileName <> '');
  if Result then
  begin
    AUri := TLspSession.PathToUri(mProject.FileName);
  end;
end;

procedure TArchitectureState.ChangeScope(const AScope: string);
var
  mNext: TAtlasPluginSettings;
begin
  FScope := AScope;
  mNext := TAtlasIdeSettings.Stored;
  mNext.ArchitectureScope := AScope;
  TAtlasIdeSettings.Update(mNext);
  Refresh;
end;

procedure TArchitectureState.ChangeLibrary(AValue: Boolean);
var
  mNext: TAtlasPluginSettings;
begin
  FIncludeLibrary := AValue;
  mNext := TAtlasIdeSettings.Stored;
  mNext.ArchitectureIncludeLibraryUnits := AValue;
  TAtlasIdeSettings.Update(mNext);
  Refresh;
end;

function TArchitectureState.ReadGrouping: Boolean;
var
  mResolution: Double;
begin
  TAtlasArchitectureGroupingSettings.Read(TAtlasIdeSettings.GlobalText, mResolution, FShowResolution);
  Result := not TAtlasArchResolution.Same(mResolution, FResolution);
  FResolution := mResolution;
end;

procedure TArchitectureState.ChangeResolution(AValue: Double);
begin
  FResolution := TAtlasArchResolution.Clamp(AValue);
  // Benutzereinstellung wie der Server (settings.json): Bericht, --architecture und get_architecture nehmen
  // denselben Wert. Eine unlesbare Datei bleibt unangetastet; der Wert gilt dann für diese Sitzung.
  TAtlasIdeSettings.SaveGlobalText(TAtlasArchitectureGroupingSettings.WithResolution(TAtlasIdeSettings.GlobalText,
    FResolution));
  Refresh;
end;

function TArchitectureState.Options: TAtlasArchitectureOptions;
begin
  Result := TAtlasArchitectureOptions.Create(FScope, FIncludeLibrary);
  Result.CompareWith := FCompareWith;
  Result.Compare := FCompare;
  Result.Resolution := FResolution;
  Result.RenameSubsystems := FRename;
end;

procedure TArchitectureState.CompareWith(const AFileName: string);
begin
  if AFileName = '' then
  begin
    Exit;
  end;
  FCompareWith := AFileName;
  FCompare := True;
  Refresh;
end;

procedure TArchitectureState.RenameSubsystems;
begin
  FRename := True;
  Refresh;
end;

procedure TArchitectureState.ClearComparison;
begin
  FCompareWith := '';
  FCompare := False;
  Refresh;
end;

function TArchitectureState.AnswerHandler(ARequest: Integer): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    var
      mModel: TAtlasArchitectureModel;
      mEnabled, mParsed: Boolean;
    begin
      // Im Hintergrund lesen: Bei einigen tausend Units dauert das spürbar.
      mParsed := TAtlasArchitectureModel.Parse(AAnswer, mModel, mEnabled);
      TAtlasMainThread.Queue(TAtlasFeature.Architecture,
        procedure
        begin
          ShowAnswer(ARequest, mParsed, mEnabled, mModel);
        end);
    end;
end;

procedure TArchitectureState.ShowAnswer(ARequest: Integer; AParsed, AEnabled: Boolean;
  const AModel: TAtlasArchitectureModel);
var
  mCurrent: TAtlasArchitectureFrame;
begin
  if (TAtlasIdeArchitecture.FState <> Self) or (ARequest <> FRequest) then
  begin
    Exit;
  end;
  FPending := False;
  mCurrent := TAtlasIdeArchitectureWindow.ExistingFrame;
  if mCurrent = nil then
  begin
    Exit;
  end;
  if not AParsed then
  begin
    mCurrent.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFailed), False);
  end
  else if not AEnabled then
  begin
    mCurrent.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureDisabled), False);
  end
  else
  begin
    mCurrent.SetModel(AModel);
    ApplyRoute;
  end;
end;

procedure TArchitectureState.Refresh;
var
  mFrame: TAtlasArchitectureFrame;
  mUri, mArguments: string;
  mRequest: Integer;
begin
  mFrame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  if not ProjectUri(mUri) then
  begin
    mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoProject), False);
    Exit;
  end;
  Inc(FRequest);
  mRequest := FRequest;
  FPending := True;
  mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureLoading), True);
  mArguments := TAtlasArchitectureCommands.Arguments(mUri, Options);
  // Neu benennen gilt einmal; der Server legt das Ergebnis als vorigen Stand ab (#1367).
  FRename := False;
  if not FRun(TAtlasArchitectureCommands.cCommand, mArguments, cTimeoutMs, AnswerHandler(mRequest)) then
  begin
    FPending := False;
    mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoServer), True);
  end;
end;

procedure TArchitectureState.Save(const AFileName: string);
var
  mFrame: TAtlasArchitectureFrame;
  mUri: string;
begin
  mFrame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if (mFrame = nil) or (AFileName = '') then
  begin
    Exit;
  end;
  if not ProjectUri(mUri) then
  begin
    mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoProject), True);
    Exit;
  end;
  if not FRun(TAtlasArchitectureCommands.cSaveCommand,
    TAtlasArchitectureCommands.SaveArguments(mUri, AFileName, Options),
    cTimeoutMs,
    procedure(AAnswer: string)
    var
      Saved: string;
    begin
      Saved := TAtlasArchitectureCommands.SavedFile(AAnswer);
      TAtlasMainThread.Queue(TAtlasFeature.Architecture,
        procedure
        var
          Current: TAtlasArchitectureFrame;
        begin
          if TAtlasIdeArchitecture.FState <> Self then
          begin
            Exit;
          end;
          Current := TAtlasIdeArchitectureWindow.ExistingFrame;
          if Current = nil then
          begin
            Exit;
          end;
          if Saved <> '' then
          begin
            Current.SetMessage(TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSaved, [Saved]), True);
          end
          else
          begin
            Current.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFailed), True);
          end;
        end);
    end) then
  begin
    mFrame.SetMessage(TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureNoServer), True);
  end;
end;

procedure TArchitectureState.ShowRoute(const AUnits: TArray<string>);
begin
  FRoute := AUnits;
  ApplyRoute;
end;

procedure TArchitectureState.ApplyRoute;
var
  mFrame: TAtlasArchitectureFrame;
  mUnits, mEdges: TArray<Integer>;
begin
  mFrame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if (Length(FRoute) = 0) or (mFrame = nil) or not mFrame.HasModel then
  begin
    Exit;
  end;
  if mFrame.Model.RouteOf(FRoute, mUnits, mEdges) then
  begin
    mFrame.Map.State.ShowRoute(mUnits, mEdges);
  end
  else
  begin
    mFrame.Map.State.ClearPath;
  end;
  FRoute := nil;
  // Die Karte zeigen, nicht eine Tabelle.
  mFrame.Parts.Pages.ActivePageIndex := 0;
end;

procedure TArchitectureState.ApplySettings;
var
  mFrame: TAtlasArchitectureFrame;
  mChanged: Boolean;
begin
  mChanged := (FScope <> TAtlasIdeSettings.Current.ArchitectureScope) or
    (FIncludeLibrary <> TAtlasIdeSettings.Current.ArchitectureIncludeLibraryUnits);
  // Feinheit und Regler (#1366) stehen in settings.json (Dialog der globalen Einstellungen).
  mChanged := ReadGrouping or mChanged;
  FScope := TAtlasIdeSettings.Current.ArchitectureScope;
  FIncludeLibrary := TAtlasIdeSettings.Current.ArchitectureIncludeLibraryUnits;
  mFrame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mFrame.ScopeValue := FScope;
  mFrame.IncludeLibrary := FIncludeLibrary;
  mFrame.ResolutionValue := FResolution;
  mFrame.ShowResolution := FShowResolution;
  // Umfang oder Bibliotheks-Units auf der Optionsseite geändert: neu rechnen, solange das Fenster offen ist.
  if mChanged and TAtlasIdeArchitectureWindow.Visible then
  begin
    Refresh;
  end;
end;

{ TAtlasIdeArchitecture }

class procedure TAtlasIdeArchitecture.Install(const ARun: TAtlasArchitectureRun);
begin
  FreeAndNil(FState);
  FState := TArchitectureState.Create(ARun);
end;

class procedure TAtlasIdeArchitecture.Uninstall;
begin
  OnUnitRelations := nil;
  FreeAndNil(FState);
  TAtlasIdeArchitectureWindow.Release;
end;

class function TAtlasIdeArchitecture.Enabled: Boolean;
begin
  Result := Active;
end;

class procedure TAtlasIdeArchitecture.ShowWindow;
var
  mFrame: TAtlasArchitectureFrame;
begin
  if (FState = nil) or not Active then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeArchitectureWindow.Show;
  if mFrame = nil then
  begin
    Exit;
  end;
  // Beim ersten Öffnen rechnen; danach nur auf „Neu berechnen“ (die Karte bleibt stehen, während man springt).
  TArchitectureState(FState).EnsureData;
  if mFrame.Parts.Filter.CanFocus then
  begin
    mFrame.Parts.Filter.SetFocus;
  end;
end;

class procedure TAtlasIdeArchitecture.ShowRanking;
var
  mFrame: TAtlasArchitectureFrame;
begin
  ShowWindow;
  mFrame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if (FState <> nil) and Active and (mFrame <> nil) then
  begin
    mFrame.ShowCostRanking;
  end;
end;

class function TAtlasIdeArchitecture.ShowRoute(const AUnits: TArray<string>): Boolean;
begin
  Result := (FState <> nil) and Active;
  if not Result then
  begin
    Exit;
  end;
  ShowWindow;
  TArchitectureState(FState).ShowRoute(AUnits);
end;

class procedure TAtlasIdeArchitecture.ApplySettings;
begin
  if FState = nil then
  begin
    Exit;
  end;
  if not Active then
  begin
    TAtlasIdeArchitectureWindow.Hide;
    Exit;
  end;
  TArchitectureState(FState).ApplySettings;
end;

class procedure TAtlasIdeArchitecture.ThemeChanged;
var
  mFrame: TAtlasArchitectureFrame;
begin
  TAtlasIdeArchitectureWindow.ApplyTheme;
  mFrame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.Map.Invalidate;
  end;
end;

end.
