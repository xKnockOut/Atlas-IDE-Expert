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
// Ohne Bedarf (Fenster zu, Statusfeld aus) räumt der Zeitgeber einmal ab und
// läuft danach leer, ohne gesicherten Aufruf je Takt: Vorher zählte das
// Diagnose-Fenster bei „Compile-Ereignisse“ 20 Aufrufe je Sekunde.

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
    cTickMs = 50;
    cRequestTimeoutMs = 3000;
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
    /// <summary>Hat der letzte Takt verfolgt? Ohne Bedarf wird danach einmal abgeräumt.</summary>
    FFollowing: Boolean;
    constructor Create(const ASession: TAtlasCompilerSwitchesSessionFunc;
      const AStatus: TAtlasCompilerSwitchesStatusProc);
    procedure Tick(Sender: TObject);
    /// <summary>Stelle im Editor verfolgen und bei Bedarf fragen (im Hauptthread).</summary>
    procedure Follow;
    /// <summary>Ohne Bedarf: Stand vergessen (beim Öffnen sofort fragen), Statusfeld leeren.</summary>
    procedure Rest;
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
  Atlas.UI.Build.Strings;

function Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.BuildCompilerSwitches;
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
  FMessage := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesEmpty);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
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
  begin
    FInstance := TAtlasIdeCompilerSwitches.Create(ASession, AStatus);
  end;
  TAtlasIdeBuildSwitchesWindow.OnFrame :=
    procedure(AFrame: TAtlasBuildSwitchesFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeBuildSwitchesWindow.Prepare;
end;

class procedure TAtlasIdeCompilerSwitches.Release;
var
  mInstance: TAtlasIdeCompilerSwitches;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mInstance := FInstance;
  FInstance := nil;
  // Statusfeld entfernen, solange der Empfänger noch da ist.
  if mInstance.FStatusText <> '' then
  begin
    mInstance.FStatusText := '';
    if Assigned(mInstance.FStatus) then
    begin
      mInstance.FStatus('', '');
    end;
  end;
  TAtlasIdeBuildSwitchesWindow.Release;
  mInstance.Free;
end;

class function TAtlasIdeCompilerSwitches.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class procedure TAtlasIdeCompilerSwitches.ApplySettings;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
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
  mFrame: TAtlasBuildSwitchesFrame;
begin
  if (FInstance = nil) or not Enabled then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeBuildSwitchesWindow.Show;
  if mFrame <> nil then
  begin
    WireFrame(mFrame);
    FInstance.Fill(mFrame);
  end;
  FInstance.FFollow.Invalidate;
end;

class function TAtlasIdeCompilerSwitches.StatusHint(const AView: TAtlasCompilerSwitchView): string;
var
  mRow: TAtlasSwitchRow;
  mValue: string;
begin
  Result := TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesStatusHint);
  for mRow in AView.Deviations do
  begin
    mValue := TAtlasCompilerSwitchTexts.Value(mRow.Value);
    Result := Result + sLineBreak + mRow.Name + ' ' + mValue + ': ' + TAtlasBuildSwitchesFrame.OriginText(mRow);
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
  mProject: IOTAProject;
begin
  mProject := GetActiveProject;
  if (mProject = nil) or (mProject.ProjectOptions = nil) then
  begin
    Exit;
  end;
  mProject.ProjectOptions.EditOptions;
  // Geänderte Optionen: gleich neu fragen.
  if FInstance <> nil then
  begin
    FInstance.FFollow.Invalidate;
  end;
end;

function TAtlasIdeCompilerSwitches.Wanted: Boolean;
begin
  Result := TAtlasIdeBuildSwitchesWindow.Visible or TAtlasIdeSettings.Current.BuildSwitchesInStatusBar;
end;

procedure TAtlasIdeCompilerSwitches.Tick(Sender: TObject);
begin
  ReapWorkers(False);
  if not Enabled or TAtlasGuard.Disabled(TAtlasFeature.Build) then
  begin
    Exit;
  end;
  if not Wanted then
  begin
    // Fenster zu, Statusfeld aus: einmal abräumen, danach nichts je Takt.
    if FFollowing then
    begin
      FFollowing := False;
      TAtlasGuard.Run(TAtlasFeature.Build,
        procedure
        begin
          Rest;
        end);
    end;
    Exit;
  end;
  FFollowing := True;
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      Follow;
    end);
end;

procedure TAtlasIdeCompilerSwitches.Rest;
begin
  // Nichts fragen; beim Öffnen sofort.
  FFollow.Invalidate;
  UpdateStatus;
end;

procedure TAtlasIdeCompilerSwitches.Follow;
var
  mView: IOTAEditView;
  mFileName: string;
  mCursor: TOTAEditPos;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  mFileName := '';
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    mFileName := mView.Buffer.FileName;
  end;
  if not TAtlasSwitchFollow.Applies(mFileName) then
  begin
    if FFollow.Moved('', -1, -1, GetTickCount64) or FHasView then
    begin
      FHasView := False;
      Inc(FRequest);
      ShowMessageText(TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesEmpty));
    end;
    Exit;
  end;
  mCursor := mView.CursorPos;
  if mCursor.Line < 1 then
  begin
    Exit;
  end;
  FFollow.Moved(mFileName, mCursor.Line - 1, TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(mView,
    mCursor.Line), mCursor.Col, TAtlasEditorBuffer.TabWidth(mView.Buffer)), GetTickCount64);
  if FFollow.Due(GetTickCount64) then
  begin
    Ask;
  end;
end;

/// <summary>Thread, der die Schalter an der Stelle holt und die Antwort im Hauptthread an die Instanz gibt.
/// </summary>
function FetchThread(ASession: TLspSession; const AFileName: string; ALine, ACharacter,
  ARequest: Integer): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      mAnswer: TAtlasCompilerSwitchView;
      mKnown: Boolean;
    begin
      mKnown := TAtlasIdeCompilerSwitches.Fetch(ASession, AFileName, ALine, ACharacter, mAnswer);
      // Atlas gehört der Eintrag: beim Entladen verworfen.
      TAtlasMainThread.Queue(TAtlasFeature.Build,
        procedure
        begin
          if TAtlasIdeCompilerSwitches.FInstance <> nil then
          begin
            TAtlasGuard.Run(TAtlasFeature.Build,
              procedure
              begin
                if TAtlasIdeCompilerSwitches.FInstance <> nil then
                begin
                  TAtlasIdeCompilerSwitches.FInstance.Accept(ARequest, AFileName, ALine, mAnswer, mKnown);
                end;
              end);
          end;
        end);
    end);
end;

procedure TAtlasIdeCompilerSwitches.Ask;
var
  mSession: TLspSession;
  mView: IOTAEditView;
  mWorker: TThread;
begin
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    FHasView := False;
    ShowMessageText(TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesNoServer));
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, FFollow.FileName) then
  begin
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FFollow.FileName, TAtlasEditorBuffer.Text(mView.Buffer));
  if not FHasView then
  begin
    ShowMessageText(TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesWaiting));
  end;
  Inc(FRequest);
  mWorker := FetchThread(mSession, FFollow.FileName, FFollow.Line, FFollow.Character, FRequest);
  mWorker.FreeOnTerminate := False;
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

class function TAtlasIdeCompilerSwitches.Fetch(ASession: TLspSession; const AFileName: string;
  ALine, ACharacter: Integer; out AView: TAtlasCompilerSwitchView): Boolean;
var
  mResponse: TJSONValue;
begin
  AView := Default(TAtlasCompilerSwitchView);
  mResponse := nil;
  try
    try
      mResponse := ASession.CompilerSwitches(AFileName, ALine, ACharacter, cRequestTimeoutMs);
      Result := TAtlasCompilerSwitchView.FromJson(mResponse, AView);
    except
      // Server langsam oder weg: kein Stand.
      Result := False;
    end;
  finally
    mResponse.Free;
  end;
end;

procedure TAtlasIdeCompilerSwitches.Accept(ARequest: Integer; const AFileName: string; ALine: Integer;
  const AView: TAtlasCompilerSwitchView; AKnown: Boolean);
var
  mFrame: TAtlasBuildSwitchesFrame;
begin
  // Nur die jüngste Antwort.
  if (ARequest <> FRequest) or not Enabled then
  begin
    Exit;
  end;
  if not AKnown then
  begin
    // Datei dem Server unbekannt oder Server zu langsam: Hinweis, beim nächsten Halt des Cursors wieder.
    FHasView := False;
    ShowMessageText(TAtlasBuildStrings.Text(TAtlasBuildTextId.CompilerSwitchesNoServer));
    Exit;
  end;
  FHasView := True;
  FView := AView;
  FViewFile := AFileName;
  FViewLine := ALine;
  mFrame := TAtlasIdeBuildSwitchesWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    Fill(mFrame);
  end;
  UpdateStatus;
end;

procedure TAtlasIdeCompilerSwitches.Fill(AFrame: TAtlasBuildSwitchesFrame);
begin
  if FHasView then
  begin
    AFrame.SetView(FView, FViewFile, FViewLine);
  end
  else
  begin
    AFrame.SetMessage(FMessage);
  end;
end;

procedure TAtlasIdeCompilerSwitches.ShowMessageText(const AText: string);
var
  mFrame: TAtlasBuildSwitchesFrame;
begin
  FMessage := AText;
  mFrame := TAtlasIdeBuildSwitchesWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    Fill(mFrame);
  end;
  UpdateStatus;
end;

procedure TAtlasIdeCompilerSwitches.UpdateStatus;
var
  mText, mHint: string;
begin
  mText := '';
  mHint := '';
  if Enabled and TAtlasIdeSettings.Current.BuildSwitchesInStatusBar and FHasView and (FView.Summary <> '') then
  begin
    mText := FView.Summary;
    mHint := StatusHint(FView);
  end;
  if mText = FStatusText then
  begin
    Exit;
  end;
  FStatusText := mText;
  if Assigned(FStatus) then
  begin
    FStatus(mText, mHint);
  end;
end;

procedure TAtlasIdeCompilerSwitches.ReapWorkers(AWait: Boolean);
var
  mIndex: Integer;
begin
  if FWorkers = nil then
  begin
    Exit;
  end;
  for mIndex := FWorkers.Count - 1 downto 0 do
  begin
    if AWait or FWorkers[mIndex].Finished then
    begin
      FWorkers[mIndex].WaitFor;
      FWorkers[mIndex].Free;
      FWorkers.Delete(mIndex);
    end;
  end;
end;

end.
