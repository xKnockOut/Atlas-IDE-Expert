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
// - „Bericht speichern …“ geht an atlas.architecture.saveReport; der Server
//   schreibt HTML oder Markdown nach der Endung, „Stand speichern …“ (#1121)
//   ebenso den Stand als .json.
// - Vergleich (#1121): Ohne Wahl vergleicht der Server mit
//   architecture.baseline; „Vergleichen mit …“ setzt den Stand für diese
//   Sitzung ("compareWith"), „Vergleich aufheben“ schaltet ihn ab ("compare":
//   false). Beides gilt auch für gespeicherte Berichte.
// - Doppelklick öffnet die Unit bzw. springt zum uses-Eintrag; Strg+Doppelklick
//   auf eine Unit zeigt sie im Fenster „Unit-Beziehungen“ (#593) über
//   OnUnitRelations, das die Zusammensetzung setzt.
// - architecture.enabled aus schließt das Fenster.
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
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Architecture.Frame,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Architecture.Window;

const
  /// <summary>Große Projektgruppen brauchen beim ersten Mal einige Sekunden (Index, Fundstellen).</summary>
  TimeoutMs = 120000;

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
    /// <summary>Gewählter Stand ("compareWith"); '' = architecture.baseline bzw. keiner.</summary>
    FCompareWith: string;
    /// <summary>False nach „Vergleich aufheben“.</summary>
    FCompare: Boolean;
    procedure Wire(AFrame: TAtlasArchitectureFrame);
    function ProjectUri(out AUri: string): Boolean;
    procedure ChangeScope(const AScope: string);
    procedure ChangeLibrary(AValue: Boolean);
    procedure CompareWith(const AFileName: string);
    procedure ClearComparison;
  public
    constructor Create(const ARun: TAtlasArchitectureRun);
    destructor Destroy; override;
    procedure Refresh;
    /// <summary>Rechnen, wenn das Fenster noch nichts zeigt und keine Anfrage läuft.</summary>
    procedure EnsureData;
    procedure Save(const AFileName: string);
    procedure ApplySettings;
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
  TAtlasIdeArchitectureWindow.OnFrame :=
    procedure(AFrame: TAtlasArchitectureFrame)
    begin
      Wire(AFrame);
    end;
  // Früh anmelden, damit die IDE das Fenster im Desktop speichert und wiederherstellt (#879).
  TAtlasIdeArchitectureWindow.Prepare;
  // Das Fenster gab es schon (Paket neu geladen): neu verdrahten.
  if TAtlasIdeArchitectureWindow.ExistingFrame <> nil then
    Wire(TAtlasIdeArchitectureWindow.ExistingFrame);
end;

destructor TArchitectureState.Destroy;
var
  Frame: TAtlasArchitectureFrame;
begin
  // Antworten, die noch unterwegs sind, finden FState nicht mehr und fallen weg.
  Inc(FRequest);
  TAtlasIdeArchitectureWindow.OnFrame := nil;
  Frame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if Frame <> nil then
  begin
    Frame.OnRefresh := nil;
    Frame.OnSave := nil;
    Frame.OnSaveState := nil;
    Frame.OnCompare := nil;
    Frame.OnClearComparison := nil;
    Frame.OnScopeChanged := nil;
    Frame.OnLibraryChanged := nil;
    Frame.OnOpenUnit := nil;
    Frame.OnOpenLocation := nil;
    Frame.OnUnitRelations := nil;
  end;
  inherited Destroy;
end;

procedure TArchitectureState.Wire(AFrame: TAtlasArchitectureFrame);
begin
  AFrame.ScopeValue := FScope;
  AFrame.IncludeLibrary := FIncludeLibrary;
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
        TAtlasIdeArchitecture.OnUnitRelations(AFileName)
      else
        TAtlasIdeNavigation.GoToLocation(AFileName, 0, 0);
    end;
  // Vom Desktop wiederhergestellt: rechnen, sobald der Aufbau durch ist (dann ist meist auch das Projekt da).
  TAtlasMainThread.Queue(TAtlasFeature.Architecture,
    procedure
    begin
      if (TAtlasIdeArchitecture.FState = Self) and Active and TAtlasIdeArchitectureWindow.Visible then
        EnsureData;
    end);
end;

procedure TArchitectureState.EnsureData;
var
  Frame: TAtlasArchitectureFrame;
begin
  Frame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if (Frame <> nil) and not Frame.HasModel and not FPending then
    Refresh;
end;

function TArchitectureState.ProjectUri(out AUri: string): Boolean;
var
  Project: IOTAProject;
begin
  AUri := '';
  Project := GetActiveProject;
  Result := (Project <> nil) and (Project.FileName <> '');
  if Result then
    AUri := TLspSession.PathToUri(Project.FileName);
end;

procedure TArchitectureState.ChangeScope(const AScope: string);
var
  Next: TAtlasPluginSettings;
begin
  FScope := AScope;
  Next := TAtlasIdeSettings.Stored;
  Next.ArchitectureScope := AScope;
  TAtlasIdeSettings.Update(Next);
  Refresh;
end;

procedure TArchitectureState.ChangeLibrary(AValue: Boolean);
var
  Next: TAtlasPluginSettings;
begin
  FIncludeLibrary := AValue;
  Next := TAtlasIdeSettings.Stored;
  Next.ArchitectureIncludeLibraryUnits := AValue;
  TAtlasIdeSettings.Update(Next);
  Refresh;
end;

procedure TArchitectureState.CompareWith(const AFileName: string);
begin
  if AFileName = '' then
    Exit;
  FCompareWith := AFileName;
  FCompare := True;
  Refresh;
end;

procedure TArchitectureState.ClearComparison;
begin
  FCompareWith := '';
  FCompare := False;
  Refresh;
end;

procedure TArchitectureState.Refresh;
var
  Frame: TAtlasArchitectureFrame;
  Uri: string;
  Request: Integer;
begin
  Frame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if Frame = nil then
    Exit;
  if not ProjectUri(Uri) then
  begin
    Frame.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureNoProject), False);
    Exit;
  end;
  Inc(FRequest);
  Request := FRequest;
  FPending := True;
  Frame.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureLoading), True);
  if not FRun(TAtlasArchitectureCommands.Command,
    TAtlasArchitectureCommands.Arguments(Uri, FScope, FIncludeLibrary, FCompareWith, FCompare), TimeoutMs,
    procedure(AAnswer: string)
    var
      Model: TAtlasArchitectureModel;
      Enabled, Parsed: Boolean;
    begin
      // Im Hintergrund lesen: Bei einigen tausend Units dauert das spürbar.
      Parsed := TAtlasArchitectureModel.Parse(AAnswer, Model, Enabled);
      TAtlasMainThread.Queue(TAtlasFeature.Architecture,
        procedure
        var
          Current: TAtlasArchitectureFrame;
        begin
          if (TAtlasIdeArchitecture.FState <> Self) or (Request <> FRequest) then
            Exit;
          FPending := False;
          Current := TAtlasIdeArchitectureWindow.ExistingFrame;
          if Current = nil then
            Exit;
          if not Parsed then
            Current.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureFailed), False)
          else if not Enabled then
            Current.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureDisabled), False)
          else
            Current.SetModel(Model);
        end);
    end) then
  begin
    FPending := False;
    Frame.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureNoServer), True);
  end;
end;

procedure TArchitectureState.Save(const AFileName: string);
var
  Frame: TAtlasArchitectureFrame;
  Uri: string;
begin
  Frame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if (Frame = nil) or (AFileName = '') then
    Exit;
  if not ProjectUri(Uri) then
  begin
    Frame.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureNoProject), True);
    Exit;
  end;
  if not FRun(TAtlasArchitectureCommands.SaveCommand,
    TAtlasArchitectureCommands.SaveArguments(Uri, AFileName, FScope, FIncludeLibrary, FCompareWith, FCompare),
    TimeoutMs,
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
            Exit;
          Current := TAtlasIdeArchitectureWindow.ExistingFrame;
          if Current = nil then
            Exit;
          if Saved <> '' then
            Current.SetMessage(TAtlasStrings.Fmt(TAtlasTextId.ArchitectureSaved, [Saved]), True)
          else
            Current.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureFailed), True);
        end);
    end) then
    Frame.SetMessage(TAtlasStrings.Text(TAtlasTextId.ArchitectureNoServer), True);
end;

procedure TArchitectureState.ApplySettings;
var
  Frame: TAtlasArchitectureFrame;
  Changed: Boolean;
begin
  Changed := (FScope <> TAtlasIdeSettings.Current.ArchitectureScope) or
    (FIncludeLibrary <> TAtlasIdeSettings.Current.ArchitectureIncludeLibraryUnits);
  FScope := TAtlasIdeSettings.Current.ArchitectureScope;
  FIncludeLibrary := TAtlasIdeSettings.Current.ArchitectureIncludeLibraryUnits;
  Frame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if Frame = nil then
    Exit;
  Frame.ScopeValue := FScope;
  Frame.IncludeLibrary := FIncludeLibrary;
  // Umfang oder Bibliotheks-Units auf der Optionsseite geändert: neu rechnen, solange das Fenster offen ist.
  if Changed and TAtlasIdeArchitectureWindow.Visible then
    Refresh;
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
  Frame: TAtlasArchitectureFrame;
begin
  if (FState = nil) or not Active then
    Exit;
  Frame := TAtlasIdeArchitectureWindow.Show;
  if Frame = nil then
    Exit;
  // Beim ersten Öffnen rechnen; danach nur auf „Neu berechnen“ (die Karte bleibt stehen, während man springt).
  TArchitectureState(FState).EnsureData;
  if Frame.Filter.CanFocus then
    Frame.Filter.SetFocus;
end;

class procedure TAtlasIdeArchitecture.ApplySettings;
begin
  if FState = nil then
    Exit;
  if not Active then
  begin
    TAtlasIdeArchitectureWindow.Hide;
    Exit;
  end;
  TArchitectureState(FState).ApplySettings;
end;

class procedure TAtlasIdeArchitecture.ThemeChanged;
var
  Frame: TAtlasArchitectureFrame;
begin
  TAtlasIdeArchitectureWindow.ApplyTheme;
  Frame := TAtlasIdeArchitectureWindow.ExistingFrame;
  if Frame <> nil then
    Frame.Map.Invalidate;
end;

end.
