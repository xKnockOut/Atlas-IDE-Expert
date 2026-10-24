unit Atlas.IDE.Build.CompilerSwitches;

// Wirksame Compiler-Schalter an der Cursorposition (#558) in der IDE:
//   - Ein Zeitgeber (TickMs) liest Datei, Zeile und Spalte des obersten
//     Editors. TAtlasSwitchFollow entprellt: Erst 150 ms nach der letzten
//     Bewegung gleicht Atlas den Text im Hauptthread ab und fragt
//     atlas/compilerSwitches im Hintergrund-Thread. Gefragt wird nur, solange
//     das Fenster sichtbar ist oder das Statusfeld eingeschaltet ist; ohne
//     laufenden Server steht im Fenster ein Hinweis (startet keinen Server).
//   - Fenster „Compiler-Schalter“ (Befehl Atlas.CompilerSwitches,
//     TAtlasBuildSwitchesFrame): Doppelklick springt zur Direktive bzw.
//     öffnet die Projektoptionen des aktiven Projekts; danach fragt Atlas
//     sofort neu.
//   - Statusfeld (build.showSwitchesInStatusBar): Kurzfassung der Abweichungen
//     („R− Q− HINTS OFF“) über den Empfänger aus Start; ohne Abweichung,
//     ohne Pascal-Datei oder ausgeschaltet meldet Atlas '' (kein Feld).
// Ohne build.compilerSwitches ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Build.CompilerSwitches,
  Atlas.UI.Build.SwitchesFrame;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasCompilerSwitchesSessionFunc = reference to function: TLspSession;
  /// <summary>Text und Tooltip für das Statusfeld; '' = kein Feld.</summary>
  TAtlasCompilerSwitchesStatusProc = reference to procedure(const AText, AHint: string);

  TAtlasIdeCompilerSwitches = class
  public const
    TickMs = 50;
    RequestTimeoutMs = 3000;
  private class var
    FInstance: TAtlasIdeCompilerSwitches;
  private
    FSession: TAtlasCompilerSwitchesSessionFunc;
    FStatus: TAtlasCompilerSwitchesStatusProc;
    FFollow: TAtlasSwitchFollow;
    FTimer: TTimer;
    FWorkers: TList<TThread>;
    FRequest: Integer;
    FHasView: Boolean;
    FView: TAtlasCompilerSwitchView;
    FViewFile: string;
    FViewLine: Integer;
    FStatusText: string;
    FMessage: string;
    constructor Create(const ASession: TAtlasCompilerSwitchesSessionFunc;
      const AStatus: TAtlasCompilerSwitchesStatusProc);
    procedure Tick(Sender: TObject);
    /// <summary>Fenster sichtbar oder Statusfeld an.</summary>
    function Wanted: Boolean;
    procedure Ask;
    procedure Accept(ARequest: Integer; const AFileName: string; ALine: Integer;
      const AView: TAtlasCompilerSwitchView; AKnown: Boolean);
    procedure ShowMessageText(const AText: string);
    procedure UpdateStatus;
    procedure Fill(AFrame: TAtlasBuildSwitchesFrame);
    procedure ReapWorkers(AWait: Boolean);
    /// <summary>Im Hintergrund-Thread: fragen und lesen; False ohne Antwort.</summary>
    class function Fetch(ASession: TLspSession; const AFileName: string; ALine, ACharacter: Integer;
      out AView: TAtlasCompilerSwitchView): Boolean; static;
    class procedure WireFrame(AFrame: TAtlasBuildSwitchesFrame); static;
    class procedure OpenOptions; static;
  public
    destructor Destroy; override;
    class procedure Start(const ASession: TAtlasCompilerSwitchesSessionFunc;
      const AStatus: TAtlasCompilerSwitchesStatusProc); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Fenster „Compiler-Schalter“ zeigen und sofort fragen.</summary>
    class procedure ShowWindow; static;
    /// <summary>Tooltip des Statusfelds: Kopf und je abweichender Zeile Name, Wert und Herkunft.</summary>
    class function StatusHint(const AView: TAtlasCompilerSwitchView): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.JSON,
  Vcl.Clipbrd,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Build.SwitchesWindow,
  Atlas.UI.Strings;

function Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.BuildCompilerSwitches;
end;

{ TAtlasIdeCompilerSwitches }

constructor TAtlasIdeCompilerSwitches.Create(const ASession: TAtlasCompilerSwitchesSessionFunc;
  const AStatus: TAtlasCompilerSwitchesStatusProc);
begin
  inherited Create;
  FSession := ASession;
  FStatus := AStatus;
  FFollow := TAtlasSwitchFollow.Create;
  FWorkers := TList<TThread>.Create;
  FViewLine := -1;
  FMessage := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesEmpty);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeCompilerSwitches.Destroy;
begin
  FreeAndNil(FTimer);
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  FreeAndNil(FFollow);
  FView := Default(TAtlasCompilerSwitchView);
  inherited Destroy;
end;

class procedure TAtlasIdeCompilerSwitches.Start(const ASession: TAtlasCompilerSwitchesSessionFunc;
  const AStatus: TAtlasCompilerSwitchesStatusProc);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeCompilerSwitches.Create(ASession, AStatus);
  TAtlasIdeBuildSwitchesWindow.OnFrame :=
    procedure(AFrame: TAtlasBuildSwitchesFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeBuildSwitchesWindow.Prepare;
end;

class procedure TAtlasIdeCompilerSwitches.Release;
var
  Instance: TAtlasIdeCompilerSwitches;
begin
  if FInstance = nil then
    Exit;
  Instance := FInstance;
  FInstance := nil;
  // Statusfeld entfernen, solange der Empfänger noch da ist.
  if Instance.FStatusText <> '' then
  begin
    Instance.FStatusText := '';
    if Assigned(Instance.FStatus) then
      Instance.FStatus('', '');
  end;
  TAtlasIdeBuildSwitchesWindow.Release;
  Instance.Free;
end;

class function TAtlasIdeCompilerSwitches.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class procedure TAtlasIdeCompilerSwitches.ApplySettings;
begin
  if FInstance = nil then
    Exit;
  if not Enabled then
  begin
    TAtlasIdeBuildSwitchesWindow.Hide;
    Exit;
  end;
  // build.showSwitchesInStatusBar geändert: Feld sofort richtig.
  FInstance.UpdateStatus;
  FInstance.FFollow.Invalidate;
end;

class procedure TAtlasIdeCompilerSwitches.ThemeChanged;
begin
  TAtlasIdeBuildSwitchesWindow.ApplyTheme;
end;

class procedure TAtlasIdeCompilerSwitches.ShowWindow;
var
  Frame: TAtlasBuildSwitchesFrame;
begin
  if (FInstance = nil) or not Enabled then
    Exit;
  Frame := TAtlasIdeBuildSwitchesWindow.Show;
  if Frame <> nil then
  begin
    WireFrame(Frame);
    FInstance.Fill(Frame);
  end;
  FInstance.FFollow.Invalidate;
end;

class function TAtlasIdeCompilerSwitches.StatusHint(const AView: TAtlasCompilerSwitchView): string;
var
  Row: TAtlasSwitchRow;
  Value: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesStatusHint);
  for Row in AView.Deviations do
  begin
    Value := TAtlasCompilerSwitchTexts.Value(Row.Value);
    Result := Result + sLineBreak + Row.Name + ' ' + Value + ': ' + TAtlasBuildSwitchesFrame.OriginText(Row);
  end;
end;

class procedure TAtlasIdeCompilerSwitches.WireFrame(AFrame: TAtlasBuildSwitchesFrame);
begin
  AFrame.OnJump :=
    procedure(ARow: TAtlasSwitchRow)
    begin
      TAtlasIdeNavigation.GoToLocation(ARow.FileName, ARow.Line, 0);
    end;
  AFrame.OnOptions :=
    procedure
    begin
      OpenOptions;
    end;
  AFrame.OnCopy :=
    procedure(AText: string)
    begin
      Clipboard.AsText := AText;
    end;
end;

class procedure TAtlasIdeCompilerSwitches.OpenOptions;
var
  Project: IOTAProject;
begin
  Project := GetActiveProject;
  if (Project = nil) or (Project.ProjectOptions = nil) then
    Exit;
  Project.ProjectOptions.EditOptions;
  // Geänderte Optionen: gleich neu fragen.
  if FInstance <> nil then
    FInstance.FFollow.Invalidate;
end;

function TAtlasIdeCompilerSwitches.Wanted: Boolean;
begin
  Result := TAtlasIdeBuildSwitchesWindow.Visible or TAtlasIdeSettings.Current.BuildSwitchesInStatusBar;
end;

procedure TAtlasIdeCompilerSwitches.Tick(Sender: TObject);
begin
  ReapWorkers(False);
  if not Enabled or TAtlasGuard.Disabled(TAtlasFeature.Build) then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    var
      View: IOTAEditView;
      FileName: string;
      Cursor: TOTAEditPos;
      Character: Integer;
    begin
      if not Wanted then
      begin
        // Fenster zu, Statusfeld aus: nichts fragen, beim Öffnen sofort.
        FFollow.Invalidate;
        UpdateStatus;
        Exit;
      end;
      View := TAtlasEditorBuffer.ActiveView;
      FileName := '';
      if (View <> nil) and (View.Buffer <> nil) then
        FileName := View.Buffer.FileName;
      if not TAtlasSwitchFollow.Applies(FileName) then
      begin
        if FFollow.Moved('', -1, -1, GetTickCount64) or FHasView then
        begin
          FHasView := False;
          Inc(FRequest);
          ShowMessageText(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesEmpty));
        end;
        Exit;
      end;
      Cursor := View.CursorPos;
      if Cursor.Line < 1 then
        Exit;
      Character := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(View, Cursor.Line), Cursor.Col,
        TAtlasEditorBuffer.TabWidth(View.Buffer));
      FFollow.Moved(FileName, Cursor.Line - 1, Character, GetTickCount64);
      if FFollow.Due(GetTickCount64) then
        Ask;
    end);
end;

procedure TAtlasIdeCompilerSwitches.Ask;
var
  Session: TLspSession;
  Buffer: IOTAEditBuffer;
  View: IOTAEditView;
  FileName: string;
  Line, Character, Request: Integer;
  Worker: TThread;
begin
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  if Session = nil then
  begin
    FHasView := False;
    ShowMessageText(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesNoServer));
    Exit;
  end;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Buffer := View.Buffer;
  FileName := FFollow.FileName;
  Line := FFollow.Line;
  Character := FFollow.Character;
  if not SameText(Buffer.FileName, FileName) then
    Exit;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  Session.Sync(FileName, TAtlasEditorBuffer.Text(Buffer));
  if not FHasView then
    ShowMessageText(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesWaiting));
  Inc(FRequest);
  Request := FRequest;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Answer: TAtlasCompilerSwitchView;
      Known: Boolean;
    begin
      Known := Fetch(Session, FileName, Line, Character, Answer);
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Build,
        procedure
        begin
          if FInstance <> nil then
            TAtlasGuard.Run(TAtlasFeature.Build,
              procedure
              begin
                if FInstance <> nil then
                  FInstance.Accept(Request, FileName, Line, Answer, Known);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FWorkers.Add(Worker);
  Worker.Start;
end;

class function TAtlasIdeCompilerSwitches.Fetch(ASession: TLspSession; const AFileName: string;
  ALine, ACharacter: Integer; out AView: TAtlasCompilerSwitchView): Boolean;
var
  Response: TJSONValue;
begin
  AView := Default(TAtlasCompilerSwitchView);
  Response := nil;
  try
    try
      Response := ASession.CompilerSwitches(AFileName, ALine, ACharacter, RequestTimeoutMs);
      Result := TAtlasCompilerSwitchView.FromJson(Response, AView);
    except
      // Server langsam oder weg: kein Stand.
      Result := False;
    end;
  finally
    Response.Free;
  end;
end;

procedure TAtlasIdeCompilerSwitches.Accept(ARequest: Integer; const AFileName: string; ALine: Integer;
  const AView: TAtlasCompilerSwitchView; AKnown: Boolean);
var
  Frame: TAtlasBuildSwitchesFrame;
begin
  // Nur die jüngste Antwort.
  if (ARequest <> FRequest) or not Enabled then
    Exit;
  if not AKnown then
  begin
    // Datei dem Server unbekannt oder Server zu langsam: Hinweis, beim nächsten Halt des Cursors wieder.
    FHasView := False;
    ShowMessageText(TAtlasStrings.Text(TAtlasTextId.CompilerSwitchesNoServer));
    Exit;
  end;
  FHasView := True;
  FView := AView;
  FViewFile := AFileName;
  FViewLine := ALine;
  Frame := TAtlasIdeBuildSwitchesWindow.ExistingFrame;
  if Frame <> nil then
    Fill(Frame);
  UpdateStatus;
end;

procedure TAtlasIdeCompilerSwitches.Fill(AFrame: TAtlasBuildSwitchesFrame);
begin
  if FHasView then
    AFrame.SetView(FView, FViewFile, FViewLine)
  else
    AFrame.SetMessage(FMessage);
end;

procedure TAtlasIdeCompilerSwitches.ShowMessageText(const AText: string);
var
  Frame: TAtlasBuildSwitchesFrame;
begin
  FMessage := AText;
  Frame := TAtlasIdeBuildSwitchesWindow.ExistingFrame;
  if Frame <> nil then
    Fill(Frame);
  UpdateStatus;
end;

procedure TAtlasIdeCompilerSwitches.UpdateStatus;
var
  Text, Hint: string;
begin
  Text := '';
  Hint := '';
  if Enabled and TAtlasIdeSettings.Current.BuildSwitchesInStatusBar and FHasView and (FView.Summary <> '') then
  begin
    Text := FView.Summary;
    Hint := StatusHint(FView);
  end;
  if Text = FStatusText then
    Exit;
  FStatusText := Text;
  if Assigned(FStatus) then
    FStatus(Text, Hint);
end;

procedure TAtlasIdeCompilerSwitches.ReapWorkers(AWait: Boolean);
var
  Index: Integer;
begin
  if FWorkers = nil then
    Exit;
  for Index := FWorkers.Count - 1 downto 0 do
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
      FWorkers.Delete(Index);
    end;
end;

end.
