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
//     („Klasse künftig ignorieren“ im Kontextmenü) oder Klasse + Datei + Zeile
//     im gestarteten Projekt („Nur an dieser Stelle ignorieren“ der
//     Exception-Leiste, #783, nur mit debug.exceptionBanner und
//     debug.exceptionBanner.ignoreAtLocation), schließt Atlas den Dialog mit
//     „Fortsetzen“ und zählt den Eintrag nur (grau). Ohne erkannten Dialog
//     setzt Atlas den Prozess direkt fort. Das wirkt ab dem nächsten Halt, also
//     auch im nächsten Lauf. Ob die IDE Exceptions, die in ihren eigenen
//     Debugger-Optionen ignoriert werden, überhaupt meldet, prüft die Studie
//     (docs/Studie-Exception-Dialog.md, Punkt S1).
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

  TAtlasDebugExceptionHandler = record
    Handle: Integer;
    Handler: TAtlasDebugExceptionEvent;
  end;

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
    /// <summary>Aufnahme des aktuellen Halts: Stapel und Dialog, beide müssen fertig sein (Finish).</summary>
    TCapture = record
      Pending: TAtlasDebugExceptionStop;
      HasPending: Boolean;
      DialogDone: Boolean;
      StackDone: Boolean;
      Retries: Integer;
      /// <summary>Halt, den der Dialog schon vor der Meldung der Session ausgelöst hat (Arm); 0 = keiner.</summary>
      EarlyStop: Integer;
    end;
    THandlers = record
      Items: TArray<TAtlasDebugExceptionHandler>;
      NextHandle: Integer;
    end;
  private class var
    FTicker: TTicker;
    FHistory: TAtlasDebugExceptionHistory;
    FIgnore: TAtlasDebugIgnoreList;
    FListener: IAtlasIdeDebugListener;
    FDialog: TAtlasIdeExceptionDialog;
    FRetry: TTimer;
    FCapture: TCapture;
    FMessage: TProc<string>;
    FHandlers: THandlers;
    /// <summary>Quelle der Klasse schon protokolliert (Studie #783, Punkt S3; einmal je Sitzung).</summary>
    FStatusLogged: Boolean;
    /// <summary>Rückruf der Exception-Leiste für FDialog.MayHide (auch vor Start gesetzt).</summary>
    FMayHide: TAtlasDebugDialogMayHide;
    class procedure Captured(AFault: Boolean); static;
    /// <summary>Dialog gefunden, während das Programm lief: den Halt sofort aufnehmen (#783).</summary>
    class procedure EarlyFound(const AScan: TAtlasDebugDialogScan); static;
    /// <summary>Während das Programm läuft auf den Exception-Dialog warten.</summary>
    class procedure ArmDialog; static;
    class procedure ReadStack; static;
    class procedure RetryTick; static;
    class procedure DialogFound(const AScan: TAtlasDebugDialogScan); static;
    class procedure DialogTimeout; static;
    /// <summary>Wenn Stapel und Dialog fertig sind: in den Verlauf, still fortsetzen, melden.</summary>
    class procedure Finish; static;
    class procedure CallHandler(const AHandler: TAtlasDebugExceptionEvent;
      const AStop: TAtlasDebugExceptionStop); static;
    class procedure WireFrame(AFrame: TAtlasDebugExceptionsFrame); static;
    class procedure RefreshWindow; static;
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
    /// Liefert die Kennung für RemoveExceptionHandler; 0, wenn AHandler fehlt.</summary>
    class function AddExceptionHandler(const AHandler: TAtlasDebugExceptionEvent): Integer; static;
    class procedure RemoveExceptionHandler(AHandle: Integer); static;
    class function History: TAtlasDebugExceptionHistory; static;
    class function IgnoreList: TAtlasDebugIgnoreList; static;
    class procedure SaveIgnoreList(const AList: TAtlasDebugIgnoreList); static;
    /// <summary>Den erkannten Dialog des aktuellen Halts mit „Fortsetzen“ schließen (#783).</summary>
    class function ContinueDialog: Boolean; static;
    /// <summary>Den erkannten Dialog des aktuellen Halts mit „Anhalten“ schließen (#783: Leiste statt Dialog).
    /// </summary>
    class function BreakDialog: Boolean; static;
    /// <summary>Entscheidet, ob der Exception-Dialog der IDE unsichtbar bleiben darf (nil = immer sichtbar).
    /// </summary>
    class procedure SetDialogMayHide(const AMayHide: TAtlasDebugDialogMayHide); static;
    /// <summary>Klasse künftig still fortsetzen (Ignorier-Liste speichern, Meldung).</summary>
    class procedure IgnoreClass(const AClass: string); static;
    /// <summary>Klasse an Datei und Zeile im Projekt künftig still fortsetzen (#783). False, wenn sie schon
    /// gemerkt war oder etwas fehlt.</summary>
    class function IgnoreLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean; static;
    /// <summary>Gemerkte Orte wirken (debug.exceptionBanner und debug.exceptionBanner.ignoreAtLocation).
    /// </summary>
    class function LocationsActive: Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.ExceptionsWindow,
  Atlas.IDE.Debug.Sources,
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.UI.Debug.Strings;

function Folder: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas');
end;


/// <summary>Klasse und Meldung aus dem Zustandstext von Thread bzw. Prozess; ALogged: Quelle schon protokolliert.
/// </summary>
procedure StatusTexts(var ALogged: Boolean; out AClass, AMessage: string);
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
    begin
      Source := 'Thread';
    end
    else if (Process <> nil) and TAtlasDebugExceptionText.Parse(Process.GetStatusString, AClass, AMessage) then
    begin
      Source := 'Prozess';
    end;
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
  if not ALogged then
  begin
    ALogged := True;
    TAtlasGuard.Log(Format('Exception-Halt: Klasse aus dem Zustandstext von %s', [Source]));
  end;
end;


{ TAtlasIdeDebugExceptions.TListener }

procedure TAtlasIdeDebugExceptions.TListener.DebugStarted;
begin
  if not TAtlasIdeSettings.Current.DebugExceptionHistory then
  begin
    Exit;
  end;
  FHistory.StartSession;
  FDialog.NewSession;
  FStatusLogged := False;
  FCapture.HasPending := False;
  FCapture.EarlyStop := 0;
  TAtlasIdeDebugSources.Clear;
  RefreshWindow;
  ArmDialog;
end;

procedure TAtlasIdeDebugExceptions.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  // Schon über den Dialog aufgenommen (EarlyFound): nicht doppelt.
  if FCapture.EarlyStop = TAtlasIdeDebugSession.StopCount then
  begin
    Exit;
  end;
  // Ein Halt ohne Dialog (Haltepunkt, Schritt): solange er steht, nicht weiter nach dem Dialog suchen.
  if FDialog.Armed then
  begin
    FDialog.Cancel;
  end;
  if (AStop = TAtlasDebugStop.Paused) or not TAtlasIdeSettings.Current.DebugExceptionHistory then
  begin
    Exit;
  end;
  Captured(AStop = TAtlasDebugStop.Fault);
end;

procedure TAtlasIdeDebugExceptions.TListener.DebugResumed;
begin
  // Weiter ohne Dialog (etwa F9 im Dialog): mit dem Bekannten aufnehmen.
  if FCapture.HasPending then
  begin
    FCapture.DialogDone := True;
    FCapture.StackDone := True;
    FDialog.Cancel;
    FRetry.Enabled := False;
    Finish;
  end;
  ArmDialog;
end;

procedure TAtlasIdeDebugExceptions.TListener.DebugEnded;
begin
  DebugResumed;
  FDialog.Cancel;
end;

{ TAtlasIdeDebugExceptions }

class procedure TAtlasIdeDebugExceptions.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FHistory = nil then
  begin
    FHistory := TAtlasDebugExceptionHistory.Create;
  end;
  FIgnore := TAtlasDebugIgnoreList.Load(Folder);
  if FDialog = nil then
  begin
    FDialog := TAtlasIdeExceptionDialog.Create;
  end;
  FDialog.MayHide := FMayHide;
  if FRetry = nil then
  begin
    FRetry := TTimer.Create(nil);
    FRetry.Enabled := False;
    FRetry.Interval := 100;
    if FTicker = nil then
    begin
      FTicker := TTicker.Create;
    end;
    FRetry.OnTimer := FTicker.Tick;
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
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  FHandlers.Items := nil;
  FCapture.HasPending := False;
  TAtlasIdeDebugExceptionsWindow.Release;
  FreeAndNil(FRetry);
  FreeAndNil(FTicker);
  FreeAndNil(FDialog);
  FreeAndNil(FHistory);
  TAtlasIdeDebugSources.Release;
  FMessage := nil;
end;

class function TAtlasIdeDebugExceptions.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDebugExceptions.ApplySettings;
begin
  // debug.ownCodeFolders bzw. debug.justMyCode geändert (#578): Ordner neu, Anzeige des Stapels neu.
  TAtlasIdeDebugSources.Clear;
  if not TAtlasIdeSettings.Current.DebugExceptionHistory then
  begin
    TAtlasIdeDebugExceptionsWindow.Hide;
    Exit;
  end;
  RefreshWindow;
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
  begin
    Exit;
  end;
  Frame := TAtlasIdeDebugExceptionsWindow.Show;
  if Frame <> nil then
  begin
    WireFrame(Frame);
    Frame.SetHistory(FHistory, FIgnore);
  end;
end;

class function TAtlasIdeDebugExceptions.AddExceptionHandler(const AHandler: TAtlasDebugExceptionEvent): Integer;
var
  Entry: TAtlasDebugExceptionHandler;
begin
  Result := 0;
  if not Assigned(AHandler) then
  begin
    Exit;
  end;
  Inc(FHandlers.NextHandle);
  Entry.Handle := FHandlers.NextHandle;
  Entry.Handler := AHandler;
  FHandlers.Items := FHandlers.Items + [Entry];
  Result := Entry.Handle;
end;

class procedure TAtlasIdeDebugExceptions.RemoveExceptionHandler(AHandle: Integer);
var
  Index: Integer;
begin
  for Index := High(FHandlers.Items) downto 0 do
  begin
    if FHandlers.Items[Index].Handle = AHandle then
    begin
      Delete(FHandlers.Items, Index, 1);
    end;
  end;
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

class function TAtlasIdeDebugExceptions.BreakDialog: Boolean;
begin
  Result := (FDialog <> nil) and FDialog.BreakFound;
end;

class procedure TAtlasIdeDebugExceptions.SetDialogMayHide(const AMayHide: TAtlasDebugDialogMayHide);
begin
  FMayHide := AMayHide;
  if FDialog <> nil then
  begin
    FDialog.MayHide := AMayHide;
  end;
end;

class procedure TAtlasIdeDebugExceptions.IgnoreClass(const AClass: string);
begin
  SetIgnored(AClass, True);
end;

class function TAtlasIdeDebugExceptions.IgnoreLocation(const AProject, AClass, AFileName: string;
  ALine: Integer): Boolean;
var
  List: TAtlasDebugIgnoreList;
begin
  List := FIgnore;
  Result := (AProject <> '') and (AFileName <> '') and (ALine > 0) and
    List.AddLocation(AProject, AClass, AFileName, ALine);
  if not Result then
  begin
    Exit;
  end;
  SaveIgnoreList(List);
  if Assigned(FMessage) then
  begin
    FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugBannerIgnoredLocationSaid,
      [AClass, ExtractFileName(AFileName) + ':' + IntToStr(ALine)]));
  end;
end;

class function TAtlasIdeDebugExceptions.LocationsActive: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionBanner and
    TAtlasIdeSettings.Current.DebugExceptionBannerIgnoreAtLocation;
end;

class procedure TAtlasIdeDebugExceptions.Captured(AFault: Boolean);
var
  Thread: IOTAThread;
  ExceptionClass, Message: string;
begin
  Thread := TAtlasIdeDebugSession.StoppedThread;
  if Thread = nil then
  begin
    Exit;
  end;
  // Ein noch offener Halt (kein Dialog, kein Weiterlaufen dazwischen) zuerst abschließen.
  if FCapture.HasPending then
  begin
    FCapture.DialogDone := True;
    FCapture.StackDone := True;
    Finish;
  end;
  StatusTexts(FStatusLogged, ExceptionClass, Message);
  if ExceptionClass = '' then
  begin
    if AFault then
    begin
      ExceptionClass := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsFault);
    end
    else
    begin
      ExceptionClass := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsUnknownClass);
    end;
  end;
  FCapture.Pending := Default(TAtlasDebugExceptionStop);
  FCapture.Pending.Stop := TAtlasIdeDebugSession.StopCount;
  FCapture.Pending.Exception := TAtlasDebugException.Create(Now, ExceptionClass, Message, Thread.GetOSThreadID,
    TAtlasIdeDebugSession.ThreadName(Thread));
  FCapture.HasPending := True;
  FCapture.DialogDone := False;
  FCapture.StackDone := False;
  FCapture.Retries := 0;
  ReadStack;
  FDialog.Watch(DialogFound, DialogTimeout);
end;

class procedure TAtlasIdeDebugExceptions.ArmDialog;
begin
  if (FDialog <> nil) and TAtlasIdeSettings.Current.DebugExceptionHistory then
  begin
    FDialog.Arm(EarlyFound);
  end;
end;

class procedure TAtlasIdeDebugExceptions.EarlyFound(const AScan: TAtlasDebugDialogScan);
var
  Thread: IOTAThread;
begin
  Thread := TAtlasIdeDebugSession.StoppedThread;
  if Thread = nil then
  begin
    Exit;
  end;
  if FCapture.HasPending then
  begin
    FCapture.DialogDone := True;
    FCapture.StackDone := True;
    Finish;
  end;
  // Die Session zählt diesen Halt erst, wenn die IDE ihren Dialog geschlossen hat: Nummer vorwegnehmen.
  FCapture.EarlyStop := TAtlasIdeDebugSession.StopCount + 1;
  FCapture.Pending := Default(TAtlasDebugExceptionStop);
  FCapture.Pending.Stop := FCapture.EarlyStop;
  FCapture.Pending.Exception := TAtlasDebugException.Create(Now, AScan.ExceptionClass, AScan.Message,
    Thread.GetOSThreadID, TAtlasIdeDebugSession.ThreadName(Thread));
  FCapture.HasPending := True;
  FCapture.DialogDone := False;
  FCapture.StackDone := False;
  FCapture.Retries := 0;
  ReadStack;
  // Der Dialog ist schon erkannt (FDialog kennt seine Knöpfe): kein neues Watch, das ihn vergäße.
  DialogFound(AScan);
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
    FCapture.StackDone := True;
    Finish;
    Exit;
  end;
  case TAtlasIdeDebugSession.ReadStack(Thread, TAtlasDebugCallStack.MaxFrames, Frames) of
    TAtlasDebugStackRead.Wait:
      begin
        Inc(FCapture.Retries);
        if FCapture.Retries <= StackRetries then
        begin
          FRetry.Enabled := True;
          Exit;
        end;
      end;
    TAtlasDebugStackRead.Ready:
      begin
        // Pfade auflösen, eigenen Code markieren (#578); mit debug.justMyCode ist der Ort der erste eigene Rahmen.
        TAtlasIdeDebugSources.MarkFrames(Frames);
        FCapture.Pending.Frames := Frames;
        FCapture.Pending.Exception.Frames := Frames;
        Index := TAtlasDebugOwnCode.LocationIndex(Frames, TAtlasIdeSettings.Current.DebugJustMyCode);
        if Index >= 0 then
        begin
          FCapture.Pending.Exception.FileName := Frames[Index].FileName;
          FCapture.Pending.Exception.Line := Frames[Index].Line;
          FCapture.Pending.Exception.Routine := Frames[Index].Routine;
        end
        else if Frames <> nil then
        begin
          FCapture.Pending.Exception.Routine := Frames[0].Routine;
        end;
      end;
  end;
  FCapture.StackDone := True;
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
  if FCapture.HasPending and not FCapture.StackDone then
  begin
    ReadStack;
  end;
end;

class procedure TAtlasIdeDebugExceptions.DialogFound(const AScan: TAtlasDebugDialogScan);
begin
  if not FCapture.HasPending then
  begin
    Exit;
  end;
  FCapture.Pending.Dialog := AScan;
  FCapture.Pending.Exception.ExceptionClass := AScan.ExceptionClass;
  FCapture.Pending.Exception.Message := AScan.Message;
  FCapture.DialogDone := True;
  Finish;
end;

class procedure TAtlasIdeDebugExceptions.DialogTimeout;
begin
  if not FCapture.HasPending then
  begin
    Exit;
  end;
  FCapture.DialogDone := True;
  Finish;
end;

class procedure TAtlasIdeDebugExceptions.Finish;
var
  Done: TAtlasDebugExceptionStop;
  Entry: TAtlasDebugExceptionHandler;
  Handlers: TArray<TAtlasDebugExceptionHandler>;
  Auto: TAtlasDebugAutoContinue;
begin
  if not FCapture.HasPending or not FCapture.DialogDone or not FCapture.StackDone then
  begin
    Exit;
  end;
  FCapture.HasPending := False;
  Done := FCapture.Pending;
  // Klasse bzw. Ort auf der Ignorier-Liste: Dialog mit „Fortsetzen“ schließen und nur zählen.
  Auto := TAtlasDebugBannerRules.AutoContinue(FIgnore.IgnoresClass(Done.Exception.ExceptionClass),
    FIgnore.IgnoresLocation(TAtlasIdeDebugSession.LaunchProject, Done.Exception.ExceptionClass,
    Done.Exception.FileName, Done.Exception.Line), LocationsActive);
  if Auto <> TAtlasDebugAutoContinue.None then
  begin
    // Ohne erkannten Dialog (keiner erschienen oder nicht lesbar) steht der Prozess nur: direkt fortsetzen.
    if Done.Dialog.HasException then
    begin
      Done.Continued := Done.Dialog.CanContinue and FDialog.ContinueFound;
    end
    else
    begin
      Done.Continued := (TAtlasIdeDebugSession.StopCount = Done.Stop) and TAtlasIdeDebugSession.Resume;
    end;
    Done.Exception.Ignored := Done.Continued;
  end;
  FHistory.Add(Done.Exception);
  RefreshWindow;
  Handlers := FHandlers.Items;
  for Entry in Handlers do
  begin
    CallHandler(Entry.Handler, Done);
  end;
end;

/// <summary>Eigene Routine: Jeder Aufruf braucht seine eigene gefangene Variable.</summary>
class procedure TAtlasIdeDebugExceptions.CallHandler(const AHandler: TAtlasDebugExceptionEvent;
  const AStop: TAtlasDebugExceptionStop);
var
  Stop: TAtlasDebugExceptionStop;
begin
  Stop := AStop;
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      AHandler(Stop);
    end);
end;

class procedure TAtlasIdeDebugExceptions.SetIgnored(const AClass: string; AIgnore: Boolean);
var
  List: TAtlasDebugIgnoreList;
  Changed: Boolean;
begin
  List := FIgnore;
  if AIgnore then
  begin
    Changed := List.AddClass(AClass);
  end
  else
  begin
    Changed := List.RemoveClass(AClass);
  end;
  if not Changed then
  begin
    Exit;
  end;
  SaveIgnoreList(List);
  if Assigned(FMessage) then
  begin
    if AIgnore then
    begin
      FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugExceptionsIgnoredClassSaid, [AClass]));
    end
    else
    begin
      FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugExceptionsStopAgainSaid, [AClass]));
    end;
  end;
end;

class procedure TAtlasIdeDebugExceptions.WireFrame(AFrame: TAtlasDebugExceptionsFrame);
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  AFrame.OnOpen :=
    procedure(AException: TAtlasDebugException)
    var
      Path: string;
    begin
      Path := TAtlasIdeDebugSources.Resolve(AException.FileName);
      if Path <> '' then
      begin
        TAtlasIdeNavigation.GoToLocation(Path, AException.Line - 1, 0);
      end
      else if Assigned(FMessage) then
      begin
        FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugExceptionsNoSource, [AException.FileName]));
      end;
    end;
  // Rahmen aus dem Aufrufstapel (#578): Pfad ist schon aufgelöst.
  AFrame.OnOpenFrame :=
    procedure(AFrameInfo: TAtlasDebugFrame)
    begin
      TAtlasIdeNavigation.GoToLocation(AFrameInfo.FileName, AFrameInfo.Line - 1, 0);
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
      begin
        FHistory.Clear;
      end;
      RefreshWindow;
    end;
  AFrame.JustMyCode := TAtlasIdeSettings.Current.DebugJustMyCode;
  AFrame.SetHistory(FHistory, FIgnore);
end;

class procedure TAtlasIdeDebugExceptions.RefreshWindow;
var
  Frame: TAtlasDebugExceptionsFrame;
begin
  Frame := TAtlasIdeDebugExceptionsWindow.ExistingFrame;
  if Frame <> nil then
  begin
    Frame.JustMyCode := TAtlasIdeSettings.Current.DebugJustMyCode;
    Frame.SetHistory(FHistory, FIgnore);
  end;
end;

end.
