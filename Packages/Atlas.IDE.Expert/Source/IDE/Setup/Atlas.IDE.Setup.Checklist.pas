unit Atlas.IDE.Setup.Checklist;

// Einrichtung mit Prüfliste (#625) in der IDE:
// - Sammelt im Hauptthread, was die Prüfungen brauchen (TAtlasSetupInput):
//   Pfad und Phase des Servers, Version der IDE aus ihrem Registry-Schlüssel,
//   Plattform des aktiven Projekts, Projekte der Gruppe, Error Insight und
//   Atlas-Probleme, Belegung der Atlas-Tasten aus der Tastenkürzel-Übersicht
//   (#520: alle Atlas-Tasten gegen Aktionen, Editor-Belegungen und andere
//   Erweiterungen). Index je Projekt und
//   Bibliotheks-Cache kommen aus der letzten Antwort von atlas.server.status,
//   die das Statusfeld ohnehin alle 5 s im Hintergrund holt; die Prüfliste
//   fragt den Server nie selbst und startet ihn nur auf Knopfdruck.
// - Fenster „Atlas-Einrichtung“ (nicht modal) aus Menü Atlas › „Einrichtung
//   prüfen…“, Befehlspalette und Klick auf die Zeile im Statusfeld; es prüft
//   alle 2 s neu, solange es offen ist. Die Knöpfe gehen über den Controller
//   (Server-Pfad wählen und speichern, Server (neu) starten, Index neu
//   aufbauen, Error Insight schalten, Tastenkonflikte öffnen).
// - Beim IDE-Start (ui.setupChecklist): erster Start immer, sonst nur, solange
//   ein Punkt fest gelb oder rot ist; Punkte im Gange (Server startet, Index
//   wird aufgebaut) wartet der Start höchstens 2 Minuten ab.
// - Zeile atlas.setup im Atlas-Statusfeld (#591): „Einrichtung: 5 von 6
//   erledigt“, gelb solange unvollständig, Klick öffnet die Prüfliste. Die
//   Zustandskachel (#754) liest dieselbe Zeile oder Progress/ShowWindow.
// - „Bericht kopieren“ (#108): Ergebnis als Text ohne Pfade und Namen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Vcl.ExtCtrls,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.Core.Setup.Checklist,
  Atlas.IDE.Commands.Palette,
  Atlas.UI.Setup.Window;

type
  TAtlasSetupIndexingFunc = reference to function(out APercent: Integer): Boolean;

  /// <summary>Verbindung zum Code Insight-Manager und zum Statusfeld; gesetzt von der Komposition.</summary>
  TAtlasSetupHooks = record
    ServerInfo: TFunc<TAtlasServerInfo>;
    Indexing: TAtlasSetupIndexingFunc;
    /// <summary>Letzte Antwort von atlas.server.status ('' ohne).</summary>
    StatusJson: TFunc<string>;
    /// <summary>Server starten (False) bzw. neu starten (True); True, wenn er läuft.</summary>
    StartServer: TFunc<Boolean, Boolean>;
    /// <summary>Befehl an den laufenden Server; Ergebnis gehört dem Aufrufer, nil ohne Server.</summary>
    ServerCommand: TFunc<string, TJSONValue>;
  end;

  TAtlasIdeSetupChecklist = class
  public const
    /// <summary>Neu prüfen, solange das Fenster offen ist oder der Start entscheidet.</summary>
    TickMs = 2000;
    /// <summary>Sonst nur für die Zeile im Statusfeld.</summary>
    IdleTicks = 5;
    /// <summary>Belegung der Tasten höchstens so oft neu lesen (Aktionsliste der IDE).</summary>
    KeysMaxAgeMs = 30000;
  private class var
    FInstance: TAtlasIdeSetupChecklist;
  private
    FRegistry: IAtlasStatusRegistry;
    FHooks: TAtlasSetupHooks;
    FEnvironment: IAtlasSetupEnvironment;
    // Dasselbe Objekt wie FEnvironment, für ForgetKeys; Lebensdauer über FEnvironment.
    FIdeEnvironment: TObject;
    FController: TAtlasSetupController;
    FWindow: TAtlasSetupWindow;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    FTimer: TTimer;
    FStarting: Boolean;
    FStartedAt: UInt64;
    FIdle: Integer;
    FLineAdded: Boolean;
    FShownVersion: Integer;
    procedure TimerTick(Sender: TObject);
    procedure Refresh;
    procedure UpdateLine;
    procedure UpdateWindow(AForce: Boolean);
    procedure Fix(const AResult: TAtlasSetupResult);
    procedure CopyReport;
    procedure SaveShowAtStart(AValue: Boolean);
    procedure MarkSeen;
    procedure DecideAtStart;
    function WindowVisible: Boolean;
    class function TryKey: string; static;
  public
    constructor Create(const ARegistry: IAtlasStatusRegistry; const AHooks: TAtlasSetupHooks);
    destructor Destroy; override;
    /// <summary>Package geladen: ab jetzt entscheidet der Start, ob die Prüfliste von selbst aufgeht.</summary>
    procedure Start;
    /// <summary>Prüfliste zeigen und sofort neu prüfen (Menü, Palette, Statusfeld, Zustandskachel #754).</summary>
    procedure ShowWindow;
    /// <summary>„Einrichtung prüfen…“ in der Befehlspalette.</summary>
    procedure RegisterCommands(APalette: TAtlasIdePalette);
    procedure ThemeChanged;
    /// <summary>Für die Zustandskachel (#754): grüne Punkte und alle; False vor der ersten Prüfung.</summary>
    function Progress(out ADone, ATotal: Integer): Boolean;
    function Results: TArray<TAtlasSetupResult>;
    /// <summary>Text von „Bericht kopieren“.</summary>
    function Report: string;
    /// <summary>Die laufende Prüfliste oder nil (abgesicherter Start minimal, entladen).</summary>
    class function Instance: TAtlasIdeSetupChecklist; static;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Menus,
  Vcl.Clipbrd,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Product.Version,
  Atlas.Core.Projects.Context,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Updates.Check,
  Atlas.UI.Strings,
  Atlas.IDE.CodeInsight.Manager,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Editor.Structure,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Settings.Store;

type
  /// <summary>Was die Knöpfe in der IDE tun; Snapshot sammelt den Zustand.</summary>
  TIdeEnvironment = class(TInterfacedObject, IAtlasSetupEnvironment)
  private
    FHooks: TAtlasSetupHooks;
    FKeys: TArray<TAtlasSetupKey>;
    FKeysAt: UInt64;
    FKeysRead: Boolean;
    function Keys: TArray<TAtlasSetupKey>;
  public
    constructor Create(const AHooks: TAtlasSetupHooks);
    /// <summary>Tasten beim nächsten Snapshot neu lesen („Erneut prüfen“, nach den Tastenkonflikten).</summary>
    procedure ForgetKeys;
    function Snapshot: TAtlasSetupInput;
    function ChooseServerPath(out APath: string): Boolean;
    procedure SaveServerPath(const APath: string);
    function StartServer(ARestart: Boolean): Boolean;
    function RebuildIndex: Boolean;
    function SetErrorInsight(AEnabled: Boolean): Boolean;
    procedure OpenKeyConflicts;
  end;

{ TIdeEnvironment }

constructor TIdeEnvironment.Create(const AHooks: TAtlasSetupHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

procedure TIdeEnvironment.ForgetKeys;
begin
  FKeysRead := False;
end;

function TIdeEnvironment.Keys: TArray<TAtlasSetupKey>;
begin
  if FKeysRead and (TThread.GetTickCount64 - FKeysAt < TAtlasIdeSetupChecklist.KeysMaxAgeMs) then
    Exit(FKeys);
  // Gemeinsame Quelle mit der Tastenkürzel-Übersicht (#520): auch Editorbefehle, Undo/Redo, das Suchfeld der
  // Willkommensseite und Tastaturbelegungen anderer Erweiterungen.
  FKeys := TAtlasIdeKeyMap.SetupKeys;
  FKeysAt := TThread.GetTickCount64;
  FKeysRead := True;
  Result := FKeys;
end;

function TIdeEnvironment.Snapshot: TAtlasSetupInput;
var
  Settings: TAtlasPluginSettings;
  Services: IOTAServices;
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Active: IOTAProject;
  Path, Arguments: string;
  Index, Percent: Integer;
begin
  Result := Default(TAtlasSetupInput);
  Settings := TAtlasIdeSettings.Current;
  Path := TAtlasCodeInsightManager.ServerPath(Arguments);
  Result.ServerFound := (Path <> '') and FileExists(Path);
  if Assigned(FHooks.ServerInfo) then
    Result.Server := FHooks.ServerInfo();
  Result.PluginVersion := TAtlasPluginVersion.Version;
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Result.BdsVersion := TAtlasProjectContext.VersionOfRegistryKey(Services.GetBaseRegistryKey);
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Active := Modules.GetActiveProject;
    if Active <> nil then
      Result.Platform := Active.CurrentPlatform;
    Group := Modules.MainProjectGroup;
    if Group <> nil then
      for Index := 0 to Group.ProjectCount - 1 do
        if SameText(ExtractFileExt(Group.Projects[Index].FileName), '.dproj') then
          Result.Projects := Result.Projects +
            [TAtlasSetupChecklist.ProjectName(Group.Projects[Index].FileName)];
  end;
  Result.IndexPercent := -1;
  if (Result.Server.Phase = TAtlasServerPhase.Running) and Assigned(FHooks.Indexing) then
  begin
    Result.Indexing := FHooks.Indexing(Percent);
    Result.IndexPercent := Percent;
  end;
  if Assigned(FHooks.StatusJson) and (Result.Server.Phase = TAtlasServerPhase.Running) then
    Result.Status := TAtlasSetupServerStatus.Parse(FHooks.StatusJson());
  Result.ErrorInsight := TAtlasIdeStructureSwitch.ErrorInsight;
  Result.ErrorInsightRestart := TAtlasIdeStructureSwitch.ErrorInsightChanged;
  Result.AtlasProblems := Settings.Enabled and Settings.Problems;
  Result.Keys := Keys;
end;

function TIdeEnvironment.ChooseServerPath(out APath: string): Boolean;
var
  Dialog: TOpenDialog;
  Arguments: string;
begin
  APath := '';
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Title := TAtlasStrings.Text(TAtlasTextId.SetupChooseTitle);
    Dialog.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsServerFilter);
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    Dialog.InitialDir := ExtractFilePath(TAtlasCodeInsightManager.ServerPath(Arguments));
    Result := Dialog.Execute;
    if Result then
      APath := Dialog.FileName;
  finally
    Dialog.Free;
  end;
end;

procedure TIdeEnvironment.SaveServerPath(const APath: string);
var
  Settings: TAtlasPluginSettings;
begin
  // Wie die Optionsseite: gespeicherte Werte, ohne Sitzungswerte der Schnellschalter.
  Settings := TAtlasIdeSettings.Stored;
  Settings.ServerPath := APath;
  TAtlasIdeSettings.Update(Settings);
  TAtlasGuard.Log('Einrichtung: Server-Pfad gewählt (#625)');
end;

function TIdeEnvironment.StartServer(ARestart: Boolean): Boolean;
begin
  Result := Assigned(FHooks.StartServer) and FHooks.StartServer(ARestart);
end;

function TIdeEnvironment.RebuildIndex: Boolean;
var
  Answer: TJSONValue;
begin
  Answer := nil;
  if Assigned(FHooks.ServerCommand) then
    Answer := FHooks.ServerCommand(TAtlasSetupChecklist.RebuildCommand);
  try
    Result := Answer <> nil;
  finally
    Answer.Free;
  end;
end;

function TIdeEnvironment.SetErrorInsight(AEnabled: Boolean): Boolean;
begin
  Result := TAtlasIdeStructureSwitch.SetErrorInsight(AEnabled);
end;

procedure TIdeEnvironment.OpenKeyConflicts;
var
  Options: IOTAEnvironmentOptions140;
  Services: IOTAServices;
begin
  // Seite „Atlas.Tastenkonflikte“ (#494) unter Tools › Optionen; danach Tasten neu lesen.
  if Supports(BorlandIDEServices, IOTAServices, Services) and
    Supports(Services.GetEnvironmentOptions, IOTAEnvironmentOptions140, Options) then
    Options.EditOptions('', 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.KeysTitle));
  ForgetKeys;
end;

{ TAtlasIdeSetupChecklist }

constructor TAtlasIdeSetupChecklist.Create(const ARegistry: IAtlasStatusRegistry; const AHooks: TAtlasSetupHooks);
begin
  inherited Create;
  FInstance := Self;
  FRegistry := ARegistry;
  FHooks := AHooks;
  FShownVersion := -1;
  FIdeEnvironment := TIdeEnvironment.Create(AHooks);
  FEnvironment := TIdeEnvironment(FIdeEnvironment);
  FController := TAtlasSetupController.Create(FEnvironment);
  FLine := TAtlasStatusLine.Create(FRegistry, TAtlasSetupChecklist.StatusId, TAtlasSetupChecklist.StatusOrder,
    procedure
    begin
      if FInstance <> nil then
        FInstance.ShowWindow;
    end);
  FLineRef := FLine;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := TimerTick;
  // Erste Prüfung im ersten Takt, nicht beim Laden des Packages; erst dann erscheint die Zeile.
  FTimer.Enabled := True;
end;

destructor TAtlasIdeSetupChecklist.Destroy;
begin
  if FInstance = Self then
    FInstance := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FWindow);
  if FLine <> nil then
    FLine.Detach;
  if FLineAdded and (FRegistry <> nil) then
    FRegistry.Remove(TAtlasSetupChecklist.StatusId);
  FLineRef := nil;
  FLine := nil;
  FreeAndNil(FController);
  FEnvironment := nil;
  FIdeEnvironment := nil;
  inherited;
end;

class function TAtlasIdeSetupChecklist.Instance: TAtlasIdeSetupChecklist;
begin
  Result := FInstance;
end;

procedure TAtlasIdeSetupChecklist.Start;
begin
  FStarting := True;
  FStartedAt := TThread.GetTickCount64;
end;

function TAtlasIdeSetupChecklist.WindowVisible: Boolean;
begin
  Result := (FWindow <> nil) and FWindow.Visible;
end;

procedure TAtlasIdeSetupChecklist.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      // Fenster offen oder Start offen: alle 2 s; sonst nur gelegentlich für die Statuszeile.
      Inc(FIdle);
      if FLineAdded and not WindowVisible and not FStarting and (FIdle < IdleTicks) then
        Exit;
      FIdle := 0;
      Refresh;
      if FStarting then
        DecideAtStart;
    end);
end;

procedure TAtlasIdeSetupChecklist.Refresh;
begin
  FController.Refresh;
  UpdateLine;
  if not FLineAdded and (FRegistry <> nil) then
  begin
    FLineAdded := True;
    FRegistry.Add(FLineRef);
  end;
  UpdateWindow(False);
end;

procedure TAtlasIdeSetupChecklist.UpdateLine;
var
  Done, Total: Integer;
begin
  if FLine = nil then
    Exit;
  FController.Progress(Done, Total);
  if FController.Complete then
    FLine.Update(TAtlasStrings.Fmt(TAtlasTextId.SetupStatusComplete, [Done, Total]), TAtlasStatusState.Green)
  else
    // Gelb, solange unvollständig (#754); die roten Punkte meldet schon die Zeile des Servers.
    FLine.Update(TAtlasStrings.Fmt(TAtlasTextId.SetupStatusLine, [Done, Total]), TAtlasStatusState.Yellow,
      TAtlasStrings.Fmt(TAtlasTextId.SetupStatusSummary, [Done, Total]));
end;

procedure TAtlasIdeSetupChecklist.UpdateWindow(AForce: Boolean);
begin
  if FWindow = nil then
    Exit;
  if not AForce and (FController.Version = FShownVersion) then
    Exit;
  FShownVersion := FController.Version;
  FWindow.SetResults(FController.Results);
end;

procedure TAtlasIdeSetupChecklist.DecideAtStart;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  case TAtlasSetupChecklist.StartAction(Settings.SetupChecklist, not Settings.SetupChecklistSeen,
    FController.Results, Int64(TThread.GetTickCount64 - FStartedAt), TAtlasSetupChecklist.StartWaitMs) of
    TAtlasSetupStartAction.Open:
      begin
        FStarting := False;
        TAtlasGuard.Log('Einrichtung: Prüfliste beim Start geöffnet (#625)');
        ShowWindow;
      end;
    TAtlasSetupStartAction.Skip:
      FStarting := False;
  end;
end;

class function TAtlasIdeSetupChecklist.TryKey: string;
var
  Settings: TAtlasPluginSettings;
begin
  // Eigene Taste der Vervollständigung (#494), sonst die der IDE.
  Settings := TAtlasIdeSettings.Current;
  if Settings.CompletionKey <> 0 then
    Result := ShortCutToText(TShortCut(Settings.CompletionKey))
  else
    Result := ShortCutToText(TShortCut(TAtlasKeyConflicts.IdeCompletionKey));
end;

procedure TAtlasIdeSetupChecklist.ShowWindow;
begin
  if FWindow = nil then
  begin
    FWindow := TAtlasSetupWindow.CreateSetup(nil, TAtlasIdeStyle.Colors);
    if Application.MainForm <> nil then
    begin
      FWindow.PopupMode := pmExplicit;
      FWindow.PopupParent := Application.MainForm;
    end;
    FWindow.OnFix :=
      procedure(AResult: TAtlasSetupResult)
      begin
        if FInstance <> nil then
          FInstance.Fix(AResult);
      end;
    FWindow.OnCopy :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Settings,
          procedure
          begin
            if FInstance <> nil then
              FInstance.CopyReport;
          end);
      end;
    FWindow.OnRecheck :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Settings,
          procedure
          begin
            if FInstance = nil then
              Exit;
            TIdeEnvironment(FInstance.FIdeEnvironment).ForgetKeys;
            FInstance.Refresh;
          end);
      end;
    FWindow.OnShowAtStart :=
      procedure(AValue: Boolean)
      begin
        if FInstance <> nil then
          FInstance.SaveShowAtStart(AValue);
      end;
  end;
  FWindow.SetColors(TAtlasIdeStyle.Colors);
  FWindow.SetTryKey(TryKey);
  FWindow.SetShowAtStart(TAtlasIdeSettings.Current.SetupChecklist);
  Refresh;
  UpdateWindow(True);
  FWindow.Show;
  FWindow.BringToFront;
  MarkSeen;
end;

procedure TAtlasIdeSetupChecklist.Fix(const AResult: TAtlasSetupResult);
var
  Fix_: TAtlasSetupFix;
  Check_: TAtlasSetupCheck;
begin
  // Anonyme Methoden dürfen const-Parameter nicht einfangen.
  Fix_ := AResult.Fix;
  Check_ := AResult.Check;
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasGuard.Log(Format('Einrichtung: Knopf %d für Prüfung %d (#625)', [Ord(Fix_), Ord(Check_)]));
      FController.Apply(Fix_);
      UpdateLine;
      UpdateWindow(True);
    end);
end;

function TAtlasIdeSetupChecklist.Report: string;
var
  Input: TAtlasSetupReportInput;
  Results_: TArray<TAtlasSetupResult>;
begin
  Results_ := FController.Results;
  Input := Default(TAtlasSetupReportInput);
  Input.Title := TAtlasStrings.Text(TAtlasTextId.SetupTitle);
  Input.Summary := TAtlasSetupWindow.ProgressText(Results_);
  Input.AtlasVersion := TAtlasPluginVersion.Version;
  Input.IdeVersion := TAtlasUpdates.IdeVersion;
  {$IFDEF WIN64}
  Input.Platform := 'Win64';
  {$ELSE}
  Input.Platform := 'Win32';
  {$ENDIF}
  Input.Created := Now;
  Input.Identity := [GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')];
  Input.Lines := TAtlasSetupWindow.ReportLines(Results_);
  Result := TAtlasSetupChecklist.Report(Input);
end;

procedure TAtlasIdeSetupChecklist.CopyReport;
begin
  Clipboard.AsText := Report;
  if FWindow <> nil then
    FWindow.ShowNote(TAtlasStrings.Text(TAtlasTextId.SetupCopied));
end;

procedure TAtlasIdeSetupChecklist.SaveShowAtStart(AValue: Boolean);
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Stored;
  if Settings.SetupChecklist = AValue then
    Exit;
  Settings.SetupChecklist := AValue;
  TAtlasIdeSettings.Update(Settings);
end;

procedure TAtlasIdeSetupChecklist.MarkSeen;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Stored;
  if Settings.SetupChecklistSeen then
    Exit;
  Settings.SetupChecklistSeen := True;
  TAtlasIdeSettings.Update(Settings);
end;

procedure TAtlasIdeSetupChecklist.RegisterCommands(APalette: TAtlasIdePalette);
begin
  APalette.RegisterCommand(TAtlasSetupChecklist.CommandId, TAtlasStrings.Text(TAtlasTextId.SetupMenu), '',
    procedure
    begin
      if FInstance <> nil then
        FInstance.ShowWindow;
    end);
end;

procedure TAtlasIdeSetupChecklist.ThemeChanged;
begin
  if FWindow <> nil then
    FWindow.SetColors(TAtlasIdeStyle.Colors);
end;

function TAtlasIdeSetupChecklist.Progress(out ADone, ATotal: Integer): Boolean;
begin
  FController.Progress(ADone, ATotal);
  Result := ATotal > 0;
end;

function TAtlasIdeSetupChecklist.Results: TArray<TAtlasSetupResult>;
begin
  Result := FController.Results;
end;

end.
