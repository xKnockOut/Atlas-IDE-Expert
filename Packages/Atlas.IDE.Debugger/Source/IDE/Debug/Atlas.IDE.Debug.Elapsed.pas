unit Atlas.IDE.Debug.Elapsed;

// Laufzeit zwischen Haltepunkten (#579) in der IDE:
//   - Messung: Die Debug-Sitzung zählt, wie lange der Prozess vor dem gemeldeten Halt lief
//     (TAtlasIdeDebugSession.RunTimeBeforeStop); angehaltene Zeit und eigene Auswertungen zählen nicht.
//   - Ort: oberster Rahmen des angehaltenen Threads (LLDB liefert ihn verzögert, dann erneut über den Takt
//     der Basis); ohne Quelltext keine Anzeige, die Messung steht trotzdem im Verlauf.
//   - Anzeige: „+124 ms“ am Ende der Zeile des Ausführungspunkts (Zeichnen und Klick in der Basis
//     TAtlasIdeDebugLineNote). Am Haltepunkt immer, bei Schritten und Pausen ab 1 ms (TAtlasElapsed).
//   - Klick auf den Text: Menü mit dem Hinweis, dass die Zeit Debugger-Aufwand enthält, und den letzten 20
//     Messungen mit Start- und Zielzeile.
//   - Fortsetzen und Ende der Sitzung nehmen die Anzeige weg; eine neue Sitzung leert den Verlauf.
// Ohne debug.showElapsed ist nichts angemeldet. Nur im Hauptthread verwenden.

interface

uses
  Atlas.Core.Debug.Elapsed,
  Atlas.IDE.Debug.LineNote;

type
  TAtlasIdeDebugElapsed = class(TAtlasIdeDebugLineNote)
  private class var
    FInstance: TAtlasIdeDebugElapsed;
  private
    FModel: TAtlasElapsed;
    /// <summary>Laufzeit des jüngsten Halts, bis sein Ort gelesen ist.</summary>
    FMicros: Int64;
    FFileName: string;
    FLine: Integer;
    FLineText: string;
    constructor Create;
    procedure Drop;
  protected
    procedure SessionStarted; override;
    procedure SessionStopped; override;
    procedure SessionResumed; override;
    procedure SessionEnded; override;
    function ReadLocation: Boolean; override;
    procedure Ask; override;
    function NoteText(const AFileName: string; ALine: Integer; out ALineText: string): string; override;
    function NoteShown: Boolean; override;
    procedure HistoryItems(out AHint, AHeader: string; out ALines: TArray<string>); override;
  public
    destructor Destroy; override;
    class procedure Start; static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.showElapsed an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.StopProgress,
  Atlas.Core.Settings.Plugin,
  Atlas.ToolsApi.Editor.Buffer,
  Atlas.ToolsApi.Files.Service,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.LineEnd,
  Atlas.UI.Debug.Elapsed.Strings;

const
  cTickMs = 10;
  cLocationRetries = 20;
  /// <summary>Wartezeit zwischen zwei Versuchen, den Ausführungspunkt zu lesen: so viele Takte.</summary>
  cLocationTicks = 5;

{ TAtlasIdeDebugElapsed }

constructor TAtlasIdeDebugElapsed.Create;
begin
  inherited Create;
  FLine := -1;
  FModel := TAtlasElapsed.Create;
  CreateTimer(cTickMs);
end;

destructor TAtlasIdeDebugElapsed.Destroy;
begin
  FreeAndNil(FModel);
  FFileName := '';
  FLineText := '';
  inherited Destroy;
end;

procedure TAtlasIdeDebugElapsed.Drop;
var
  mHad: Boolean;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FProgress.Discard;
  ForgetHit;
  mHad := FModel.LineText(FFileName, FLine) <> '';
  FModel.Hide;
  if mHad then
  begin
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

procedure TAtlasIdeDebugElapsed.SessionStarted;
begin
  Drop;
  FModel.Clear;
end;

procedure TAtlasIdeDebugElapsed.SessionStopped;
begin
  Drop;
  if not Enabled then
  begin
    Exit;
  end;
  // Gleich lesen: Die Sitzung zählt bis zum nächsten gemeldeten Halt weiter.
  FMicros := TAtlasIdeDebugSession.RunTimeBeforeStop;
  FProgress.Restart(TAtlasIdeDebugSession.StopCount);
  if ReadLocation then
  begin
    Ask;
  end;
end;

procedure TAtlasIdeDebugElapsed.SessionResumed;
begin
  Drop;
end;

procedure TAtlasIdeDebugElapsed.SessionEnded;
begin
  Drop;
end;

function TAtlasIdeDebugElapsed.ReadLocation: Boolean;
var
  mFrames: TAtlasDebugFrames;
  mBuffer: IOTAEditBuffer;
  mRead: TAtlasDebugStackRead;
  mWithoutSource: Boolean;
  mLines: TArray<string>;
begin
  mBuffer := nil;
  mRead := TAtlasIdeDebugSession.ReadStack(TAtlasIdeDebugSession.StoppedThread, 1, mFrames);
  mWithoutSource := (mRead = TAtlasDebugStackRead.Ready) and ((Length(mFrames) = 0) or not mFrames[0].HasSource);
  if (mRead = TAtlasDebugStackRead.Ready) and not mWithoutSource then
  begin
    TAtlasIdeDebugSources.MarkFrames(mFrames);
    mBuffer := TAtlasIdeFiles.BufferOf(mFrames[0].FileName);
  end;
  case FProgress.Locate(mRead = TAtlasDebugStackRead.None, mWithoutSource, mBuffer <> nil, cLocationRetries) of
    TAtlasStopLocation.Retry:
      begin
        FTimer.Interval := cTickMs * cLocationTicks;
        FTimer.Enabled := True;
        Exit(False);
      end;
    TAtlasStopLocation.GiveUp:
      begin
        // Ohne Quelltext: nur in den Verlauf.
        FModel.Add(FMicros, '', -1, False);
        Exit(False);
      end;
  end;
  FFileName := mBuffer.FileName;
  FLine := mFrames[0].Line - 1;
  mLines := TAtlasEditorBuffer.Text(mBuffer).Split([#13#10, #10]);
  FLineText := '';
  if (FLine >= 0) and (FLine <= High(mLines)) then
  begin
    FLineText := mLines[FLine];
  end;
  Result := True;
end;

procedure TAtlasIdeDebugElapsed.Ask;
begin
  FTimer.Enabled := False;
  FProgress.Phase := TAtlasStopPhase.Idle;
  if FModel.Add(FMicros, FFileName, FLine, TAtlasIdeBreakpoints.Exists(FFileName, FLine)) then
  begin
    TAtlasDebugLineEnd.Invalidate;
  end;
end;

function TAtlasIdeDebugElapsed.NoteText(const AFileName: string; ALine: Integer; out ALineText: string): string;
begin
  ALineText := FLineText;
  Result := FModel.LineText(AFileName, ALine);
end;

function TAtlasIdeDebugElapsed.NoteShown: Boolean;
begin
  Result := FModel.LineText(FFileName, FLine) <> '';
end;

procedure TAtlasIdeDebugElapsed.HistoryItems(out AHint, AHeader: string; out ALines: TArray<string>);
var
  mEntries: TArray<TAtlasElapsedEntry>;
  mIndex: Integer;
begin
  AHint := TAtlasElapsedStrings.Text(TAtlasElapsedTextId.ElapsedHint);
  AHeader := TAtlasElapsedStrings.Text(TAtlasElapsedTextId.ElapsedHistory);
  mEntries := FModel.Entries;
  ALines := nil;
  SetLength(ALines, Length(mEntries));
  for mIndex := 0 to High(mEntries) do
  begin
    ALines[mIndex] := TAtlasElapsed.HistoryLine(mEntries[mIndex]);
  end;
end;

class procedure TAtlasIdeDebugElapsed.Start;
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDebugElapsed.Create;
    FInstance.Listen;
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugElapsed.Release;
var
  mInstance: TAtlasIdeDebugElapsed;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mInstance := FInstance;
  FInstance := nil;
  mInstance.Free;
  TAtlasDebugLineEnd.Invalidate;
end;

class function TAtlasIdeDebugElapsed.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugElapsed.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugShowElapsed;
end;

end.
