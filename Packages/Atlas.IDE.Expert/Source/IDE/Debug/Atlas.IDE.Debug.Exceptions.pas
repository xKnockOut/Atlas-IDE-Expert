unit Atlas.IDE.Debug.Exceptions;

// Exception-Verlauf beim Debuggen (#517) in der IDE:
//   - Zuhörer der Debug-Sitzung (TAtlasIdeDebugSession): Start einer Sitzung
//     leert den Verlauf; jeder Halt wegen einer Exception (psException,
//     psFault) wird aufgenommen.
//   - Je Halt: Thread (Kennung, Name), Aufrufstapel (oberster Rahmen mit
//     Quelltext = Ort, sonst die Routine des obersten Rahmens), Klasse und
//     Meldung. Die Open Tools API nennt Klasse und Meldung nicht; sie kommen
//     aus dem Exception-Dialog der IDE (TAtlasIdeExceptionDialog), ersatzweise
//     aus den Zustandstexten von Thread und Prozess. Erscheint bis
//     TAtlasIdeExceptionDialog.WatchMs kein Dialog, steht der Eintrag mit dem,
//     was bekannt ist (Klasse „Exception“ bzw. „Fehler des Betriebssystems“).
//     Liefert der Debugger den Stapel verzögert (csWait, LLDB), fragt Atlas
//     bis zu StackRetries-mal nach.
//   - Still fortsetzen: Steht die Klasse auf der Ignorier-Liste von Atlas
//     („Klasse künftig ignorieren“ im Kontextmenü), schließt Atlas den Dialog
//     mit „Fortsetzen“ und zählt den Eintrag nur (grau). Das wirkt ab dem
//     nächsten Halt, also auch im nächsten Lauf. Ob die IDE Exceptions, die in
//     ihren eigenen Debugger-Optionen ignoriert werden, überhaupt meldet, prüft
//     die Studie (docs/Studie-Exception-Dialog.md, Punkt S1).
//   - Fenster „Exception-Verlauf“ (Befehl Atlas.DebugExceptions): Klick springt
//     zur Stelle (Datei aus dem Stapel, notfalls über die Dateien der
//     Projektgruppe gesucht), Kopieren, Klasse ignorieren und wieder anhalten,
//     Verlauf leeren. Ohne debug.exceptionHistory nimmt Atlas nichts auf, das
//     Fenster und der Befehl fehlen, die IDE verhält sich wie ohne Atlas.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.IgnoreList,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.ExceptionDialog,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.ExceptionDialog,
  Atlas.UI.Debug.ExceptionsFrame;

type
  /// <summary>Gerade aufgenommener Halt wegen einer Exception (für #578 und #783).</summary>
  TAtlasDebugExceptionStop = record
    Exception: TAtlasDebugException;
    Frames: TAtlasDebugFrames;
    /// <summary>Halt Nummer (TAtlasIdeDebugSession.StopCount).</summary>
    Stop: Integer;
    /// <summary>Atlas hat still fortgesetzt.</summary>
    Continued: Boolean;
    /// <summary>Dialog der IDE erkannt (mit „Fortsetzen“).</summary>
    Dialog: TAtlasDebugDialogScan;
  end;

  TAtlasDebugExceptionEvent = reference to procedure(const AStop: TAtlasDebugExceptionStop);

  TAtlasIdeDebugExceptions = class
  public const
    StackRetries = 10;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
    /// <summary>Besitzer des Zeitgebers (OnTimer braucht eine Methode eines Objekts).</summary>
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
  private class var
    FTicker: TTicker;
    FHistory: TAtlasDebugExceptionHistory;
    FIgnore: TAtlasDebugIgnoreList;
    FListener: IAtlasIdeDebugListener;
    FDialog: TAtlasIdeExceptionDialog;
    FRetry: TTimer;
    FRetries: Integer;
    FPending: TAtlasDebugExceptionStop;
    FHasPending: Boolean;
    FDialogDone: Boolean;
    FStackDone: Boolean;
    FMessage: TProc<string>;
    FOnException: TArray<TAtlasDebugExceptionEvent>;
    FSourceCache: TStringList;
    /// <summary>Quelle der Klasse schon protokolliert (Studie #783, Punkt S3; einmal je Sitzung).</summary>
    FStatusLogged: Boolean;
    class procedure Captured(AFault: Boolean); static;
    class procedure ReadStack; static;
    class procedure RetryTick; static;
    class procedure DialogFound(const AScan: TAtlasDebugDialogScan); static;
    class procedure DialogTimeout; static;
    /// <summary>Wenn Stapel und Dialog fertig sind: in den Verlauf, still fortsetzen, melden.</summary>
    class procedure Finish; static;
    class procedure WireFrame(AFrame: TAtlasDebugExceptionsFrame); static;
    class procedure RefreshWindow; static;
    class procedure StatusTexts(out AClass, AMessage: string); static;
    class function Folder: string; static;
    class procedure SetIgnored(const AClass: string; AIgnore: Boolean); static;
  public
    /// <summary>AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Fenster „Exception-Verlauf“ zeigen.</summary>
    class procedure ShowWindow; static;
    /// <summary>Für #578/#783: nach jedem aufgenommenen Halt wegen einer Exception (auch still fortgesetzt).
    /// </summary>
    class procedure AddExceptionHandler(const AHandler: TAtlasDebugExceptionEvent); static;
    class procedure ClearExceptionHandlers; static;
    /// <summary>Datei aus dem Aufrufstapel zu einem Pfad, den die IDE öffnen kann ('' wenn unbekannt): absolut und
    /// vorhanden, sonst gleichnamige Datei der Projektgruppe.</summary>
    class function ResolveSource(const AFileName: string): string; static;
    class function History: TAtlasDebugExceptionHistory; static;
    class function IgnoreList: TAtlasDebugIgnoreList; static;
    class procedure SaveIgnoreList(const AList: TAtlasDebugIgnoreList); static;
    /// <summary>Den erkannten Dialog des aktuellen Halts mit „Fortsetzen“ schließen (#783).</summary>
    class function ContinueDialog: Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.ExceptionsWindow,
  Atlas.UI.Strings;

{ TAtlasIdeDebugExceptions.TListener }

procedure TAtlasIdeDebugExceptions.TListener.DebugStarted;
begin
  if not TAtlasIdeSettings.Current.DebugExceptionHistory then
    Exit;
  FHistory.StartSession;
  FDialog.NewSession;
  FStatusLogged := False;
  FHasPending := False;
  if FSourceCache <> nil then
    FSourceCache.Clear;
  RefreshWindow;
end;

procedure TAtlasIdeDebugExceptions.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  if (AStop = TAtlasDebugStop.Paused) or not TAtlasIdeSettings.Current.DebugExceptionHistory then
    Exit;
  Captured(AStop = TAtlasDebugStop.Fault);
end;

procedure TAtlasIdeDebugExceptions.TListener.DebugResumed;
begin
  // Weiter ohne Dialog (etwa F9 im Dialog): mit dem Bekannten aufnehmen.
  if FHasPending then
  begin
    FDialogDone := True;
    FStackDone := True;
    FDialog.Cancel;
    FRetry.Enabled := False;
    Finish;
  end;
end;

procedure TAtlasIdeDebugExceptions.TListener.DebugEnded;
begin
  DebugResumed;
end;

{ TAtlasIdeDebugExceptions }

class function TAtlasIdeDebugExceptions.Folder: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas');
end;

class procedure TAtlasIdeDebugExceptions.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FHistory = nil then
    FHistory := TAtlasDebugExceptionHistory.Create;
  FIgnore := TAtlasDebugIgnoreList.Load(Folder);
  if FDialog = nil then
    FDialog := TAtlasIdeExceptionDialog.Create;
  if FRetry = nil then
  begin
    FRetry := TTimer.Create(nil);
    FRetry.Enabled := False;
    FRetry.Interval := 100;
    if FTicker = nil then
      FTicker := TTicker.Create;
    FRetry.OnTimer := FTicker.Tick;
  end;
  if FSourceCache = nil then
  begin
    FSourceCache := TStringList.Create;
    FSourceCache.CaseSensitive := False;
  end;
  TAtlasIdeDebugExceptionsWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugExceptionsFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeDebugExceptionsWindow.Prepare;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugExceptions.Release;
begin
  if FListener <> nil then
    TAtlasIdeDebugSession.RemoveListener(FListener);
  FListener := nil;
  FOnException := nil;
  FHasPending := False;
  TAtlasIdeDebugExceptionsWindow.Release;
  FreeAndNil(FRetry);
  FreeAndNil(FTicker);
  FreeAndNil(FDialog);
  FreeAndNil(FHistory);
  FreeAndNil(FSourceCache);
  FMessage := nil;
end;

class function TAtlasIdeDebugExceptions.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDebugExceptions.ApplySettings;
begin
  if not TAtlasIdeSettings.Current.DebugExceptionHistory then
    TAtlasIdeDebugExceptionsWindow.Hide;
end;

class procedure TAtlasIdeDebugExceptions.ThemeChanged;
begin
  TAtlasIdeDebugExceptionsWindow.ApplyTheme;
end;

class procedure TAtlasIdeDebugExceptions.ShowWindow;
var
  Frame: TAtlasDebugExceptionsFrame;
begin
  if not TAtlasIdeSettings.Current.DebugExceptionHistory then
    Exit;
  Frame := TAtlasIdeDebugExceptionsWindow.Show;
  if Frame <> nil then
  begin
    WireFrame(Frame);
    Frame.SetHistory(FHistory, FIgnore);
  end;
end;

class procedure TAtlasIdeDebugExceptions.AddExceptionHandler(const AHandler: TAtlasDebugExceptionEvent);
begin
  if Assigned(AHandler) then
    FOnException := FOnException + [AHandler];
end;

class procedure TAtlasIdeDebugExceptions.ClearExceptionHandlers;
begin
  FOnException := nil;
end;

class function TAtlasIdeDebugExceptions.History: TAtlasDebugExceptionHistory;
begin
  Result := FHistory;
end;

class function TAtlasIdeDebugExceptions.IgnoreList: TAtlasDebugIgnoreList;
begin
  Result := FIgnore;
end;

class procedure TAtlasIdeDebugExceptions.SaveIgnoreList(const AList: TAtlasDebugIgnoreList);
begin
  FIgnore := AList;
  TAtlasDebugIgnoreList.Save(Folder, FIgnore);
  RefreshWindow;
end;

class function TAtlasIdeDebugExceptions.ContinueDialog: Boolean;
begin
  Result := (FDialog <> nil) and FDialog.ContinueFound;
end;

class procedure TAtlasIdeDebugExceptions.StatusTexts(out AClass, AMessage: string);
var
  Thread: IOTAThread;
  Process: IOTAProcess;
  Source: string;
begin
  AClass := '';
  AMessage := '';
  Source := 'keinem';
  Thread := TAtlasIdeDebugSession.StoppedThread;
  Process := TAtlasIdeDebugSession.Process;
  try
    if (Thread <> nil) and TAtlasDebugExceptionText.Parse(Thread.GetStatusString, AClass, AMessage) then
      Source := 'Thread'
    else if (Process <> nil) and TAtlasDebugExceptionText.Parse(Process.GetStatusString, AClass, AMessage) then
      Source := 'Prozess';
  except
    // Ältere Debugger ohne Zustandstexte.
    AClass := '';
    AMessage := '';
  end;
  if Source = 'keinem' then
  begin
    AClass := '';
    AMessage := '';
  end;
  // Für die Studie (#783, S3): woher die Klasse kam, nie der Text (er kann Daten des Programms enthalten).
  if not FStatusLogged then
  begin
    FStatusLogged := True;
    TAtlasGuard.Log(Format('Exception-Halt: Klasse aus dem Zustandstext von %s', [Source]));
  end;
end;

class procedure TAtlasIdeDebugExceptions.Captured(AFault: Boolean);
var
  Thread: IOTAThread;
  ExceptionClass, Message: string;
begin
  Thread := TAtlasIdeDebugSession.StoppedThread;
  if Thread = nil then
    Exit;
  // Ein noch offener Halt (kein Dialog, kein Weiterlaufen dazwischen) zuerst abschließen.
  if FHasPending then
  begin
    FDialogDone := True;
    FStackDone := True;
    Finish;
  end;
  StatusTexts(ExceptionClass, Message);
  if ExceptionClass = '' then
    if AFault then
      ExceptionClass := TAtlasStrings.Text(TAtlasTextId.DebugExceptionsFault)
    else
      ExceptionClass := TAtlasStrings.Text(TAtlasTextId.DebugExceptionsUnknownClass);
  FPending := Default(TAtlasDebugExceptionStop);
  FPending.Stop := TAtlasIdeDebugSession.StopCount;
  FPending.Exception := TAtlasDebugException.Create(Now, ExceptionClass, Message, Thread.GetOSThreadID,
    TAtlasIdeDebugSession.ThreadName(Thread), '', 0, '');
  FHasPending := True;
  FDialogDone := False;
  FStackDone := False;
  FRetries := 0;
  ReadStack;
  FDialog.Watch(DialogFound, DialogTimeout);
end;

class procedure TAtlasIdeDebugExceptions.ReadStack;
var
  Frames: TAtlasDebugFrames;
  Index: Integer;
  Thread: IOTAThread;
begin
  Thread := TAtlasIdeDebugSession.StoppedThread;
  if Thread = nil then
  begin
    FStackDone := True;
    Finish;
    Exit;
  end;
  case TAtlasIdeDebugSession.ReadStack(Thread, TAtlasDebugCallStack.MaxFrames, Frames) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(FRetries);
        if FRetries <= StackRetries then
        begin
          FRetry.Enabled := True;
          Exit;
        end;
      end;
    TAtlasDebugStackRead.Ready:
      begin
        FPending.Frames := Frames;
        Index := TAtlasDebugCallStack.FirstWithSource(Frames);
        if Index >= 0 then
        begin
          FPending.Exception.FileName := Frames[Index].FileName;
          FPending.Exception.Line := Frames[Index].Line;
          FPending.Exception.Routine := Frames[Index].Routine;
        end
        else if Frames <> nil then
          FPending.Exception.Routine := Frames[0].Routine;
      end;
  end;
  FStackDone := True;
  Finish;
end;

{ TAtlasIdeDebugExceptions.TTicker }

procedure TAtlasIdeDebugExceptions.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugExceptions.RetryTick);
end;

class procedure TAtlasIdeDebugExceptions.RetryTick;
begin
  FRetry.Enabled := False;
  if FHasPending and not FStackDone then
    ReadStack;
end;

class procedure TAtlasIdeDebugExceptions.DialogFound(const AScan: TAtlasDebugDialogScan);
begin
  if not FHasPending then
    Exit;
  FPending.Dialog := AScan;
  FPending.Exception.ExceptionClass := AScan.ExceptionClass;
  FPending.Exception.Message := AScan.Message;
  FDialogDone := True;
  Finish;
end;

class procedure TAtlasIdeDebugExceptions.DialogTimeout;
begin
  if not FHasPending then
    Exit;
  FDialogDone := True;
  Finish;
end;

class procedure TAtlasIdeDebugExceptions.Finish;
var
  Done: TAtlasDebugExceptionStop;
  Handler: TAtlasDebugExceptionEvent;
  Handlers: TArray<TAtlasDebugExceptionEvent>;
begin
  if not FHasPending or not FDialogDone or not FStackDone then
    Exit;
  FHasPending := False;
  Done := FPending;
  // Klasse auf der Ignorier-Liste: Dialog mit „Fortsetzen“ schließen und nur zählen.
  if FIgnore.IgnoresClass(Done.Exception.ExceptionClass) and Done.Dialog.CanContinue and
    FDialog.ContinueFound then
  begin
    Done.Continued := True;
    Done.Exception.Ignored := True;
  end;
  FHistory.Add(Done.Exception);
  RefreshWindow;
  Handlers := FOnException;
  for Handler in Handlers do
    TAtlasGuard.Run(TAtlasFeature.Debugger,
      procedure
      begin
        Handler(Done);
      end);
end;

class function TAtlasIdeDebugExceptions.ResolveSource(const AFileName: string): string;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Project: IOTAProject;
  ProjectIndex, FileIndex: Integer;
  Name, Candidate: string;
  Files: TStringList;
begin
  Result := '';
  if AFileName = '' then
    Exit;
  if TPath.IsPathRooted(AFileName) and FileExists(AFileName) then
    Exit(AFileName);
  if (FSourceCache <> nil) and (FSourceCache.IndexOfName(AFileName) >= 0) then
    Exit(FSourceCache.Values[AFileName]);
  Name := ExtractFileName(AFileName);
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Group := Modules.MainProjectGroup;
    Files := TStringList.Create;
    try
      if Group <> nil then
        for ProjectIndex := 0 to Group.ProjectCount - 1 do
        begin
          Project := Group.Projects[ProjectIndex];
          Files.Clear;
          Project.GetCompleteFileList(Files);
          for FileIndex := 0 to Files.Count - 1 do
          begin
            Candidate := Files[FileIndex];
            if SameText(ExtractFileName(Candidate), Name) and FileExists(Candidate) then
            begin
              Result := Candidate;
              Break;
            end;
          end;
          if Result <> '' then
            Break;
        end;
    finally
      Files.Free;
    end;
  end;
  if FSourceCache <> nil then
    FSourceCache.Values[AFileName] := Result;
end;

class procedure TAtlasIdeDebugExceptions.SetIgnored(const AClass: string; AIgnore: Boolean);
var
  List: TAtlasDebugIgnoreList;
  Changed: Boolean;
begin
  List := FIgnore;
  if AIgnore then
    Changed := List.AddClass(AClass)
  else
    Changed := List.RemoveClass(AClass);
  if not Changed then
    Exit;
  SaveIgnoreList(List);
  if Assigned(FMessage) then
    if AIgnore then
      FMessage(TAtlasStrings.Fmt(TAtlasTextId.DebugExceptionsIgnoredClassSaid, [AClass]))
    else
      FMessage(TAtlasStrings.Fmt(TAtlasTextId.DebugExceptionsStopAgainSaid, [AClass]));
end;

class procedure TAtlasIdeDebugExceptions.WireFrame(AFrame: TAtlasDebugExceptionsFrame);
begin
  if AFrame = nil then
    Exit;
  AFrame.OnOpen :=
    procedure(AException: TAtlasDebugException)
    var
      Path: string;
    begin
      Path := ResolveSource(AException.FileName);
      if Path <> '' then
        TAtlasIdeNavigation.GoToLocation(Path, AException.Line - 1, 0)
      else if Assigned(FMessage) then
        FMessage(TAtlasStrings.Fmt(TAtlasTextId.DebugExceptionsNoSource, [AException.FileName]));
    end;
  AFrame.OnCopy :=
    procedure(AException: TAtlasDebugException)
    begin
      Clipboard.AsText := AException.CopyText;
    end;
  AFrame.OnIgnoreClass :=
    procedure(AClass: string; AIgnore: Boolean)
    begin
      SetIgnored(AClass, AIgnore);
    end;
  AFrame.OnClear :=
    procedure
    begin
      if FHistory <> nil then
        FHistory.Clear;
      RefreshWindow;
    end;
  AFrame.SetHistory(FHistory, FIgnore);
end;

class procedure TAtlasIdeDebugExceptions.RefreshWindow;
var
  Frame: TAtlasDebugExceptionsFrame;
begin
  Frame := TAtlasIdeDebugExceptionsWindow.ExistingFrame;
  if Frame <> nil then
    Frame.SetHistory(FHistory, FIgnore);
end;

end.
