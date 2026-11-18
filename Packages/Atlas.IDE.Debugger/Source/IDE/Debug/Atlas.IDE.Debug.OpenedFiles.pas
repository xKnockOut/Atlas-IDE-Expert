unit Atlas.IDE.Debug.OpenedFiles;

// Vom Debugger geöffnete Dateien schließen (#842) in der IDE; die Buchführung
// liegt in TAtlasOpenedFiles (Core).
// - Beginn der Sitzung: offene Dateien gelten als „schon vorher offen“.
// - ofnFileOpened während der Sitzung: Ist das Programm angehalten und ist
//   die Datei die Stelle des Halts, hat der Debugger sie geöffnet (F7 in eine
//   Unit der RTL). Öffnet der Benutzer im Halt eine andere Datei
//   (Strg+Klick, Projektverwaltung), zählt sie nicht. Geht sie im laufenden
//   Programm auf, entscheidet ein Halt in ihr kurz danach.
// - Offen bleiben geänderte Dateien, Dateien mit Quelltext-Haltepunkt oder
//   Lesezeichen der IDE und solche, die der Benutzer mit „Vom Debugger
//   geöffnete Datei offen halten“ festhält (Tippen ändert die Datei).
// - Ende der Sitzung (debug.closeOpenedFiles): ask zeigt einen Hinweis mit
//   „Schließen“, „Offen lassen“, „Immer automatisch“; auto schließt und
//   bietet „Wieder öffnen“ an; off tut nichts.
// - Vorschau (debug.previewTab): Beim nächsten Halt in einer weiteren vom
//   Debugger geöffneten Datei schließt Atlas die vorige, wenn sie unberührt
//   ist. Den Reitertitel kursiv zu setzen, sieht die Open Tools API nicht
//   vor; die Statuszeile nennt den Vorschau-Reiter.
// Geschlossen wird über die Warteschlange des Hauptthreads, nie in einer
// Meldung der IDE. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Debug.OpenedFiles,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Notifications.Notice;

type
  TAtlasIdeOpenedFiles = class
  private type
    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugEnded; override;
    end;
  private class var
    FFiles: TAtlasOpenedFiles;
    FListener: IAtlasIdeDebugListener;
    FNotifierIndex: Integer;
    FToast: TAtlasNoticeWindow;
    FToastActions: TArray<TProc>;
    FMessage: TProc<string>;
    class procedure FileOpened(const AFileName: string); static;
    class procedure SessionStarted; static;
    class procedure SessionStopped; static;
    class procedure SessionEnded; static;
    class procedure CloseLater(const AFiles: TArray<string>; AReport: Boolean); static;
    class procedure CloseNow(const AFiles: TArray<string>; AReport: Boolean); static;
    class procedure Ask(const AFiles: TArray<string>); static;
    class procedure Notify(const AText: string; const ACaptions: TArray<string>; const AActions: TArray<TProc>);
      static;
    class procedure ReopenFiles(const AFiles: TArray<string>); static;
    class procedure AlwaysAuto; static;
    class function Keep: TAtlasOpenedFileKeep; static;
    class function OpenModuleFiles: TArray<string>; static;
    class function CurrentStopFile: string; static;
    class function CurrentEditorFile: string; static;
  public
    /// <summary>Notifier und Zuhörer anmelden; AMessage schreibt in die Statuszeile.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl: Datei im aktiven Editor bleibt nach der Sitzung offen.</summary>
    class procedure PinCurrent; static;
    /// <summary>Behält AFileName nach der Sitzung (geändert, Haltepunkt, Lesezeichen der IDE)?</summary>
    class function Touched(const AFileName: string): Boolean; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  System.Types,
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Popup.Window,
  Atlas.UI.Debug.OpenedFiles.Strings;

const
  cBookmarkCount = 10;
  /// <summary>Knöpfe des Hinweises nach der Sitzung: Schließen, Offen lassen, Immer automatisch.</summary>
  cAskActions = 3;

{ TAtlasIdeOpenedFiles.TIdeNotifier }

procedure TAtlasIdeOpenedFiles.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
begin
  if FFiles = nil then
  begin
    Exit;
  end;
  case NotifyCode of
    ofnFileOpened:
      FileOpened(FileName);
    ofnFileClosing:
      FFiles.Closed(FileName);
  end;
end;

procedure TAtlasIdeOpenedFiles.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
  // Nur Dateimeldungen.
end;

procedure TAtlasIdeOpenedFiles.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
  // Nur Dateimeldungen.
end;

{ TAtlasIdeOpenedFiles.TListener }

procedure TAtlasIdeOpenedFiles.TListener.DebugStarted;
begin
  SessionStarted;
end;

procedure TAtlasIdeOpenedFiles.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  SessionStopped;
end;

procedure TAtlasIdeOpenedFiles.TListener.DebugEnded;
begin
  SessionEnded;
end;

{ TAtlasIdeOpenedFiles }

function CloseMode: TAtlasCloseOpenedFiles;
begin
  Result := TAtlasOpenedFiles.ModeOf(TAtlasIdeSettings.Current.DebugCloseOpenedFiles);
end;

class function TAtlasIdeOpenedFiles.OpenModuleFiles: TArray<string>;
var
  mServices: IOTAModuleServices;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  SetLength(Result, mServices.ModuleCount);
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    Result[mIndex] := mServices.Modules[mIndex].FileName;
  end;
end;

class function TAtlasIdeOpenedFiles.CurrentStopFile: string;
var
  mThread: IOTAThread;
begin
  Result := '';
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if mThread <> nil then
  begin
    Result := mThread.CurrentFile;
  end;
end;

class function TAtlasIdeOpenedFiles.CurrentEditorFile: string;
var
  mServices: IOTAEditorServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAEditorServices, mServices) and (mServices.TopBuffer <> nil) then
  begin
    Result := mServices.TopBuffer.FileName;
  end;
end;

class procedure TAtlasIdeOpenedFiles.FileOpened(const AFileName: string);
var
  mAtStop: Boolean;
begin
  if not FFiles.Active then
  begin
    Exit;
  end;
  mAtStop := TAtlasOpenedFiles.KeyOf(CurrentStopFile) = TAtlasOpenedFiles.KeyOf(AFileName);
  FFiles.Opened(AFileName, mAtStop, GetTickCount64);
end;

/// <summary>Hat AFileName einen Quelltext-Haltepunkt?</summary>
function HasBreakpoint(const AFileName: string): Boolean;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mKey: string;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, mServices) then
  begin
    Exit;
  end;
  mKey := TAtlasOpenedFiles.KeyOf(AFileName);
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    if TAtlasOpenedFiles.KeyOf(mServices.SourceBkpts[mIndex].FileName) = mKey then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Hat eine Ansicht von ABuffer ein Lesezeichen 0–9 der IDE?</summary>
function HasBookmark(const ABuffer: IOTAEditBuffer): Boolean;
var
  mView, mMark: Integer;
begin
  Result := False;
  for mView := 0 to ABuffer.EditViewCount - 1 do
  begin
    for mMark := 0 to cBookmarkCount - 1 do
    begin
      if ABuffer.EditViews[mView].BookmarkPos[mMark].Line > 0 then
      begin
        Exit(True);
      end;
    end;
  end;
end;

class function TAtlasIdeOpenedFiles.Touched(const AFileName: string): Boolean;
var
  mBuffer: IOTAEditBuffer;
begin
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  Result := ((mBuffer <> nil) and (mBuffer.Modified or HasBookmark(mBuffer))) or HasBreakpoint(AFileName);
end;

class function TAtlasIdeOpenedFiles.Keep: TAtlasOpenedFileKeep;
begin
  Result :=
    function(const AFileName: string): Boolean
    begin
      Result := Touched(AFileName);
    end;
end;

class procedure TAtlasIdeOpenedFiles.SessionStarted;
begin
  FFiles.BeginSession(OpenModuleFiles);
end;

class procedure TAtlasIdeOpenedFiles.SessionStopped;
var
  mFile, mPrevious: string;
begin
  mFile := CurrentStopFile;
  FFiles.Stopped(mFile, GetTickCount64);
  if not TAtlasIdeSettings.Current.DebugPreviewTab or not FFiles.IsOpenedByDebugger(mFile) then
  begin
    Exit;
  end;
  mPrevious := FFiles.PreviewToClose(mFile, Keep());
  if Assigned(FMessage) then
  begin
    FMessage(TAtlasOpenedFilesStrings.Fmt(TAtlasOpenedFilesTextId.PreviewMessage, [ExtractFileName(mFile)]));
  end;
  if mPrevious <> '' then
  begin
    CloseLater(TArray<string>.Create(mPrevious), False);
  end;
end;

class procedure TAtlasIdeOpenedFiles.SessionEnded;
var
  mFiles: TArray<string>;
begin
  FFiles.EndSession;
  mFiles := FFiles.ToClose(Keep());
  if mFiles = nil then
  begin
    Exit;
  end;
  case CloseMode of
    TAtlasCloseOpenedFiles.Off:
      // Abgeschaltet: Reiter bleiben wie bisher.
      Exit;
    TAtlasCloseOpenedFiles.Ask:
      Ask(mFiles);
    TAtlasCloseOpenedFiles.Auto:
      CloseLater(mFiles, True);
  end;
end;

class procedure TAtlasIdeOpenedFiles.CloseLater(const AFiles: TArray<string>; AReport: Boolean);
var
  mFiles: TArray<string>;
begin
  mFiles := Copy(AFiles);
  TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
    procedure
    begin
      if FFiles <> nil then
      begin
        CloseNow(mFiles, AReport);
      end;
    end);
end;

/// <summary>AFileName schließen, wenn sie offen und unverändert ist; True, wenn sie zu ist.</summary>
function CloseModuleOf(const AFileName: string): Boolean;
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
  mBuffer: IOTAEditBuffer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mModule := mServices.FindModule(AFileName);
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if (mModule = nil) or ((mBuffer <> nil) and mBuffer.Modified) then
  begin
    Exit;
  end;
  // Ohne Zwang: Wäre die Datei inzwischen geändert, fragt die IDE wie sonst.
  Result := mModule.CloseModule(False);
end;

/// <summary>Aktion „Wieder öffnen“ für AFiles (eigene Routine: kein gemeinsamer Rahmen mit anderen Aktionen).
/// </summary>
function ReopenAction(const AFiles: TArray<string>): TProc;
var
  mFiles: TArray<string>;
begin
  mFiles := Copy(AFiles);
  Result :=
    procedure
    begin
      TAtlasIdeOpenedFiles.ReopenFiles(mFiles);
    end;
end;

/// <summary>Aktion „Schließen“ bzw. mit AAlways „Immer automatisch“ für AFiles.</summary>
function CloseAction(const AFiles: TArray<string>; AAlways: Boolean): TProc;
var
  mFiles: TArray<string>;
begin
  mFiles := Copy(AFiles);
  Result :=
    procedure
    begin
      if AAlways then
      begin
        TAtlasIdeOpenedFiles.AlwaysAuto;
      end;
      TAtlasIdeOpenedFiles.CloseLater(mFiles, False);
    end;
end;

class procedure TAtlasIdeOpenedFiles.CloseNow(const AFiles: TArray<string>; AReport: Boolean);
var
  mFile: string;
  mClosed: TArray<string>;
  mActions: TArray<TProc>;
begin
  mClosed := nil;
  for mFile in AFiles do
  begin
    // Seit der Liste angefasst (Haltepunkt, Lesezeichen, Tippen): bleibt offen.
    if not FFiles.IsPinned(mFile) and not Touched(mFile) and CloseModuleOf(mFile) then
    begin
      mClosed := mClosed + [mFile];
    end;
  end;
  if AReport and (mClosed <> nil) then
  begin
    SetLength(mActions, 1);
    mActions[0] := ReopenAction(mClosed);
    Notify(TAtlasOpenedFilesStrings.Fmt(TAtlasOpenedFilesTextId.OpenedClosedText, [Length(mClosed)]),
      TArray<string>.Create(TAtlasOpenedFilesStrings.Text(TAtlasOpenedFilesTextId.OpenedReopen)), mActions);
  end;
end;

class procedure TAtlasIdeOpenedFiles.ReopenFiles(const AFiles: TArray<string>);
var
  mActions: IOTAActionServices;
  mFile: string;
begin
  if not Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    Exit;
  end;
  for mFile in AFiles do
  begin
    mActions.OpenFile(mFile);
  end;
end;

class procedure TAtlasIdeOpenedFiles.AlwaysAuto;
var
  mNext: TAtlasPluginSettings;
begin
  mNext := TAtlasIdeSettings.Stored;
  mNext.DebugCloseOpenedFiles := TAtlasOpenedFiles.NameOf(TAtlasCloseOpenedFiles.Auto);
  TAtlasIdeSettings.Update(mNext);
end;

class procedure TAtlasIdeOpenedFiles.Ask(const AFiles: TArray<string>);
var
  mActions: TArray<TProc>;
begin
  // „Offen lassen“ schließt nur den Hinweis.
  SetLength(mActions, cAskActions);
  mActions[0] := CloseAction(AFiles, False);
  mActions[1] := nil;
  mActions[2] := CloseAction(AFiles, True);
  Notify(TAtlasOpenedFilesStrings.Fmt(TAtlasOpenedFilesTextId.OpenedAskText, [Length(AFiles)]),
    TArray<string>.Create(TAtlasOpenedFilesStrings.Text(TAtlasOpenedFilesTextId.OpenedClose),
    TAtlasOpenedFilesStrings.Text(TAtlasOpenedFilesTextId.OpenedKeep),
    TAtlasOpenedFilesStrings.Text(TAtlasOpenedFilesTextId.OpenedAlways)), mActions);
end;

/// <summary>Aktion der Benachrichtigungszentrale aus Text und Prozedur.</summary>
function Actions(const ACaptions: TArray<string>; const AActions: TArray<TProc>): TArray<TAtlasNotificationAction>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ACaptions) do
  begin
    if Assigned(AActions[mIndex]) then
    begin
      Result := Result + [TAtlasNotificationCenter.Action(ACaptions[mIndex], AActions[mIndex])];
    end;
  end;
end;

class procedure TAtlasIdeOpenedFiles.Notify(const AText: string; const ACaptions: TArray<string>;
  const AActions: TArray<TProc>);
var
  mTitle: string;
  mArea: TRect;
begin
  mTitle := TAtlasOpenedFilesStrings.Text(TAtlasOpenedFilesTextId.OpenedTitle);
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.cDebugFiles, TAtlasNotificationSeverity.Info,
    mTitle, AText, Actions(ACaptions, AActions)) <> TAtlasNotificationMode.Show then
  begin
    Exit;
  end;
  if FToast = nil then
  begin
    FToast := TAtlasNoticeWindow.Create(nil);
    FToast.OnAction :=
      procedure(AIndex: Integer)
      begin
        if (AIndex >= 0) and (AIndex < Length(FToastActions)) and Assigned(FToastActions[AIndex]) then
        begin
          FToastActions[AIndex]();
        end;
      end;
  end;
  FToastActions := Copy(AActions);
  mArea := Screen.WorkAreaRect;
  if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end;
  FToast.Colors := TAtlasIdeStyle.Colors;
  FToast.SetScaling(TAtlasPopupWindow.MonitorPPI(mArea.BottomRight), 1, '', 10);
  FToast.ShowNotice(mTitle, AText, ACaptions, mArea);
end;

class procedure TAtlasIdeOpenedFiles.PinCurrent;
var
  mFile: string;
begin
  mFile := CurrentEditorFile;
  if (FFiles <> nil) and FFiles.IsOpenedByDebugger(mFile) then
  begin
    FFiles.Pin(mFile);
  end;
  if not Assigned(FMessage) then
  begin
    Exit;
  end;
  if (FFiles <> nil) and FFiles.IsPinned(mFile) then
  begin
    FMessage(TAtlasOpenedFilesStrings.Fmt(TAtlasOpenedFilesTextId.PinDone, [ExtractFileName(mFile)]));
  end
  else
  begin
    FMessage(TAtlasOpenedFilesStrings.Text(TAtlasOpenedFilesTextId.PinNotOpenedByDebugger));
  end;
end;

class procedure TAtlasIdeOpenedFiles.Start(const AMessage: TProc<string>);
var
  mServices: IOTAServices;
begin
  FMessage := AMessage;
  if FFiles = nil then
  begin
    FFiles := TAtlasOpenedFiles.Create;
  end;
  if (FNotifierIndex <= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifierIndex := mServices.AddNotifier(TIdeNotifier.Create) + 1;
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
  // Läuft schon eine Sitzung (Modul spät geladen), gilt alles Offene als vorher offen.
  if TAtlasIdeDebugSession.Active then
  begin
    SessionStarted;
  end;
end;

class procedure TAtlasIdeOpenedFiles.Release;
var
  mServices: IOTAServices;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  if (FNotifierIndex > 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mServices.RemoveNotifier(FNotifierIndex - 1);
  end;
  FNotifierIndex := 0;
  FreeAndNil(FToast);
  FToastActions := nil;
  FreeAndNil(FFiles);
  FMessage := nil;
end;

class function TAtlasIdeOpenedFiles.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeOpenedFiles.ThemeChanged;
begin
  if FToast <> nil then
  begin
    FToast.Colors := TAtlasIdeStyle.Colors;
  end;
end;

end.
