unit Atlas.IDE.Debug.AsyncOrigin;

// Herkunft eingereihter Methoden (#859, experimentell): woher eine anonyme Methode kam, die über TThread.Queue,
// Synchronize, ForceQueue, TTask.Run, TTask.Create oder TParallel.For gestartet wurde.
//   - Beim Start der Sitzung (oder beim Einschalten während einer) sucht Atlas in den Units des gestarteten Projekts
//     die Aufrufstellen (Atlas.Core.Debug.AsyncOrigin) und setzt auf jede einen Haltepunkt der Gruppe Atlas.Herkunft.
//     Steht dort schon ein Haltepunkt des Benutzers, bleibt er, wie er ist.
//   - Hält das Programm an einer Aufrufstelle, merkt Atlas Thread und Aufrufstapel und setzt sofort fort; die übrigen
//     Funktionen des Debuggers erfahren davon nichts (Filter in TAtlasIdeDebugSession). Am Haltepunkt des Benutzers
//     merkt Atlas ebenso, hält aber.
//   - Hält das Programm später in der anonymen Methode einer Aufrufstelle, ordnet Atlas die Einreihung zu (die älteste
//     offene der Stelle) und zeigt sie im Ergebnisfenster: „Eingereiht mit TThread.Queue von Thread 4120“, darunter der
//     damalige Stapel, Bibliothek zusammengefasst; Doppelklick springt zur Zeile. Weitere Halte desselben Threads in
//     derselben Methode (Schritte) behalten die Zuordnung.
//   - Die Statusleiste von Atlas zeigt, solange Haltepunkte gesetzt sind, „Herkunft: 12 Aufrufstellen“ in Gelb: Das
//     Anhalten an jeder Stelle bremst das Programm.
// Die Adresse der übergebenen Methode liest Atlas nicht (am Haltepunkt ist sie noch nicht gebaut); die Zuordnung
// folgt deshalb der Reihenfolge je Aufrufstelle.
// Teil „DebugAsyncOrigin“ (debug.asyncOrigin); Release entfernt Haltepunkte, Filter, Zuhörer, Statuszeile und die
// Liste im Ergebnisfenster (Regel 3). Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.AsyncOrigin,
  Atlas.IDE.Debug.Session;

type
  TAtlasIdeDebugAsyncOrigin = class
  public const
    /// <summary>Besitzer der Liste im Ergebnisfenster.</summary>
    cOwner = 'debug.asyncOrigin';
    cBreakpointGroup = 'Atlas.Herkunft';
    cStatusId = 'atlas.debug.asyncOrigin';
    cStatusOrder = 87;
    /// <summary>Rahmen, die Atlas an einer Aufrufstelle merkt.</summary>
    cMaxFrames = 32;
    cIntervalMs = 150;
    cRetries = 10;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugEnded; override;
    end;
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
    /// <summary>Zuletzt gezeigte Zuordnung: gilt weiter, solange derselbe Thread in derselben Methode hält.</summary>
    TShown = record
      Has: Boolean;
      ThreadId: Cardinal;
      Site: Integer;
      Entry: TAtlasAsyncEntry;
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FRetries: Integer;
    FMessage: TProc<string>;
    FRegistry: IAtlasStatusRegistry;
    FStatusRef: IAtlasStatusItem;
    FSites: TAtlasAsyncSiteList;
    /// <summary>Je Aufrufstelle: Haltepunkt von Atlas (True) oder des Benutzers.</summary>
    FOwnBreak: TArray<Boolean>;
    FBreaks: TArray<IOTABreakpoint>;
    FOrigins: TAtlasAsyncOrigins;
    FShown: TShown;
    FStarted: Boolean;
    class procedure Arm; static;
    class procedure Disarm; static;
    /// <summary>Halt an einer Aufrufstelle: merken; True, wenn es ein Haltepunkt von Atlas war (dann fortgesetzt).
    /// </summary>
    class function Remember(AStop: TAtlasDebugStop): Boolean; static;
    /// <summary>Halt in einer eingereihten Methode zuordnen und zeigen; False, solange der Stapel noch fehlt.</summary>
    class function TryShow: Boolean; static;
    /// <summary>Stapel des angehaltenen Threads, Rahmen aufgelöst und eigener Code markiert.</summary>
    class function StoppedFrames(out AThread: IOTAThread; out AFrames: TAtlasDebugFrames): TAtlasDebugStackRead;
      static;
    /// <summary>Halt von Thread AThreadId in der Methode von ASite: Einreihung zuordnen und zeigen.</summary>
    class procedure AssignOrigin(AThreadId: Cardinal; ASite: Integer); static;
    class procedure Show; static;
    class procedure Open(const AItemId: string); static;
    class procedure UpdateStatus; static;
    class function CurrentPosition(const AThread: IOTAThread; out AFileName: string; out ALine: Integer): Boolean;
      static;
  public
    class procedure Start(const AMessage: TProc<string>; const ARegistry: IAtlasStatusRegistry); static;
    class procedure Release; static;
    class function Started: Boolean; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Results.Items,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.Sources,
  Atlas.UI.Debug.AsyncOrigin,
  Atlas.UI.Debug.Strings;

/// <summary>Quelltexte (.pas, .dpr) des Projekts AProjectFile, sonst des aktiven Projekts.</summary>
function ProjectSources(const AProjectFile: string): TArray<string>;
var
  mProject: IOTAProject;
  mIndex: Integer;
  mFileName: string;
begin
  Result := nil;
  mProject := nil;
  if AProjectFile <> '' then
  begin
    mProject := TAtlasIdeFiles.GroupProject(AProjectFile);
  end;
  if mProject = nil then
  begin
    mProject := GetActiveProject;
  end;
  if mProject = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mProject.GetModuleCount - 1 do
  begin
    mFileName := mProject.GetModule(mIndex).FileName;
    if SameText(ExtractFileExt(mFileName), '.pas') or SameText(ExtractFileExt(mFileName), '.dpr') then
    begin
      Result := Result + [mFileName];
    end;
  end;
end;

{ TAtlasIdeDebugAsyncOrigin.TListener }

procedure TAtlasIdeDebugAsyncOrigin.TListener.DebugStarted;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugAsyncOrigin.Arm);
end;

procedure TAtlasIdeDebugAsyncOrigin.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      TAtlasIdeDebugAsyncOrigin.FRetries := 0;
      TAtlasIdeDebugAsyncOrigin.FTimer.Enabled := not TAtlasIdeDebugAsyncOrigin.TryShow;
    end);
end;

procedure TAtlasIdeDebugAsyncOrigin.TListener.DebugEnded;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugAsyncOrigin.Disarm);
end;

{ TAtlasIdeDebugAsyncOrigin.TTicker }

procedure TAtlasIdeDebugAsyncOrigin.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      if TAtlasIdeDebugAsyncOrigin.TryShow then
      begin
        TAtlasIdeDebugAsyncOrigin.FTimer.Enabled := False;
      end;
    end);
end;

{ TAtlasIdeDebugAsyncOrigin }

class procedure TAtlasIdeDebugAsyncOrigin.Start(const AMessage: TProc<string>; const ARegistry: IAtlasStatusRegistry);
begin
  FMessage := AMessage;
  FRegistry := ARegistry;
  if FTicker = nil then
  begin
    FTicker := TTicker.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cIntervalMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
  TAtlasIdeDebugSession.SetStopFilter(
    function(AStop: TAtlasDebugStop): Boolean
    begin
      Result := TAtlasIdeDebugAsyncOrigin.Remember(AStop);
    end);
  FStarted := True;
  // Eingeschaltet während einer Sitzung: gleich beobachten.
  if TAtlasIdeDebugSession.Active then
  begin
    Arm;
  end;
end;

class procedure TAtlasIdeDebugAsyncOrigin.Release;
begin
  FStarted := False;
  TAtlasIdeDebugSession.SetStopFilter(nil);
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  Disarm;
  FRegistry := nil;
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  FMessage := nil;
  TAtlasIdeResultsWindow.ReleaseItems(cOwner);
end;

class function TAtlasIdeDebugAsyncOrigin.Started: Boolean;
begin
  Result := FStarted;
end;

class procedure TAtlasIdeDebugAsyncOrigin.Arm;
var
  mFileName, mText: string;
  mIndex: Integer;
  mBreakpoint: IOTABreakpoint;
begin
  Disarm;
  FOrigins.MaxPerSite := TAtlasIdeSettings.Current.DebugAsyncOriginMaxPerSite;
  for mFileName in ProjectSources(TAtlasIdeDebugSession.LaunchProject) do
  begin
    if TAtlasIdeFiles.SourceText(mFileName, mText) then
    begin
      FSites := FSites + TAtlasAsyncSites.Find(mFileName, mText);
    end;
  end;
  if FSites = nil then
  begin
    FMessage(TAtlasDebugStrings.Text(TAtlasDebugTextId.AsyncOriginNoSites));
    Exit;
  end;
  SetLength(FOwnBreak, Length(FSites));
  for mIndex := 0 to High(FSites) do
  begin
    // Haltepunkte zählen Zeilen ab 0.
    mBreakpoint := TAtlasIdeBreakpoints.Add(FSites[mIndex].FileName, FSites[mIndex].Line - 1, cBreakpointGroup);
    FOwnBreak[mIndex] := mBreakpoint <> nil;
    if mBreakpoint <> nil then
    begin
      FBreaks := FBreaks + [mBreakpoint];
    end;
  end;
  FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.AsyncOriginArmed, [Length(FSites)]));
  UpdateStatus;
end;

class procedure TAtlasIdeDebugAsyncOrigin.Disarm;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  FSites := nil;
  FOwnBreak := nil;
  FOrigins.Clear;
  FShown := Default(TShown);
  UpdateStatus;
end;

class function TAtlasIdeDebugAsyncOrigin.CurrentPosition(const AThread: IOTAThread; out AFileName: string;
  out ALine: Integer): Boolean;
var
  mResolved: string;
begin
  Result := TAtlasIdeBreakpoints.Position(AThread, AFileName, ALine);
  // Die IDE nennt oft nur den Dateinamen; die Aufrufstellen tragen den vollen Pfad.
  mResolved := TAtlasIdeDebugSources.Resolve(AFileName);
  if mResolved <> '' then
  begin
    AFileName := mResolved;
  end;
end;

class function TAtlasIdeDebugAsyncOrigin.Remember(AStop: TAtlasDebugStop): Boolean;
var
  mThread: IOTAThread;
  mFileName: string;
  mLine, mSite: Integer;
  mFrames: TAtlasDebugFrames;
begin
  Result := False;
  if (FSites = nil) or (AStop <> TAtlasDebugStop.Paused) then
  begin
    Exit;
  end;
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if (mThread = nil) or not CurrentPosition(mThread, mFileName, mLine) then
  begin
    Exit;
  end;
  mSite := TAtlasAsyncSites.SiteOnLine(FSites, mFileName, mLine + 1);
  if mSite < 0 then
  begin
    Exit;
  end;
  // Liefert der Debugger den Stapel erst später (LLDB), bleibt die Einreihung ohne Stapel: Warten bremste das
  // Programm an jeder Stelle.
  mFrames := nil;
  if TAtlasIdeDebugSession.ReadStack(mThread, cMaxFrames, mFrames) = TAtlasDebugStackRead.Ready then
  begin
    TAtlasIdeDebugSources.MarkFrames(mFrames);
  end;
  FOrigins.Add(mSite, mThread.OSThreadID, 0, mFrames);
  Result := FOwnBreak[mSite] and TAtlasIdeDebugSession.Resume;
end;

class function TAtlasIdeDebugAsyncOrigin.StoppedFrames(out AThread: IOTAThread;
  out AFrames: TAtlasDebugFrames): TAtlasDebugStackRead;
begin
  AFrames := nil;
  AThread := TAtlasIdeDebugSession.StoppedThread;
  if (FSites = nil) or (AThread = nil) then
  begin
    Exit(TAtlasDebugStackRead.None);
  end;
  Result := TAtlasIdeDebugSession.ReadStack(AThread, TAtlasDebugCallStack.cMaxFrames, AFrames);
  if Result = TAtlasDebugStackRead.Ready then
  begin
    TAtlasIdeDebugSources.MarkFrames(AFrames);
  end;
end;

class function TAtlasIdeDebugAsyncOrigin.TryShow: Boolean;
var
  mThread: IOTAThread;
  mFrames: TAtlasDebugFrames;
  mRead: TAtlasDebugStackRead;
  mSite: Integer;
begin
  Result := True;
  mRead := StoppedFrames(mThread, mFrames);
  if mRead = TAtlasDebugStackRead.Wait then
  begin
    Inc(FRetries);
    Result := FRetries > cRetries;
  end
  else if (mRead = TAtlasDebugStackRead.Ready) and (TAtlasAsyncSites.OriginFrame(FSites, mFrames, mSite) >= 0) then
  begin
    AssignOrigin(mThread.OSThreadID, mSite);
  end;
end;

class procedure TAtlasIdeDebugAsyncOrigin.AssignOrigin(AThreadId: Cardinal; ASite: Integer);
var
  mEntry: TAtlasAsyncEntry;
begin
  // Weitere Halte desselben Threads in derselben Methode (Schritte): Zuordnung bleibt.
  if FShown.Has and (FShown.ThreadId = AThreadId) and (FShown.Site = ASite) then
  begin
    Exit;
  end;
  FShown := Default(TShown);
  if not FOrigins.Take(ASite, 0, mEntry) then
  begin
    FMessage(TAtlasAsyncOriginTexts.NoneText(FSites[ASite].Kind));
    Exit;
  end;
  FShown.Has := True;
  FShown.ThreadId := AThreadId;
  FShown.Site := ASite;
  FShown.Entry := mEntry;
  Show;
end;

class procedure TAtlasIdeDebugAsyncOrigin.Show;
var
  mList: TAtlasResultsItemList;
  mGroup: TAtlasResultsItemGroup;
  mItem: TAtlasResultsItem;
  mRows: TArray<string>;
  mFrameIndex: TArray<Integer>;
  mIndex: Integer;
begin
  mList := Default(TAtlasResultsItemList);
  mList.Owner := cOwner;
  mList.Title := TAtlasAsyncOriginTexts.Title(FShown.Entry, FSites[FShown.Site].Kind);
  mList.OnOpen := Open;
  mGroup := Default(TAtlasResultsItemGroup);
  mGroup.Caption := mList.Title;
  mRows := TAtlasAsyncOriginTexts.Rows(FShown.Entry.Frames, mFrameIndex);
  for mIndex := 0 to High(mRows) do
  begin
    mItem := Default(TAtlasResultsItem);
    mItem.Id := IntToStr(mFrameIndex[mIndex]);
    mItem.Caption := mRows[mIndex];
    mGroup.Items := mGroup.Items + [mItem];
  end;
  mList.Groups := [mGroup];
  TAtlasIdeResultsWindow.ShowItems(mList);
  FMessage(mList.Title);
end;

class procedure TAtlasIdeDebugAsyncOrigin.Open(const AItemId: string);
var
  mIndex: Integer;
  mFrame: TAtlasDebugFrame;
begin
  mIndex := StrToIntDef(AItemId, -1);
  if not FShown.Has or (mIndex < 0) or (mIndex > High(FShown.Entry.Frames)) then
  begin
    Exit;
  end;
  mFrame := FShown.Entry.Frames[mIndex];
  if mFrame.HasSource then
  begin
    TAtlasIdeNavigation.MarkLine(mFrame.FileName, mFrame.Line - 1);
  end;
end;

class procedure TAtlasIdeDebugAsyncOrigin.UpdateStatus;
var
  mLine: TAtlasStatusLine;
begin
  if FRegistry = nil then
  begin
    Exit;
  end;
  if FBreaks = nil then
  begin
    if FStatusRef <> nil then
    begin
      FRegistry.Remove(cStatusId);
    end;
    FStatusRef := nil;
    Exit;
  end;
  if FStatusRef <> nil then
  begin
    FRegistry.Remove(cStatusId);
  end;
  mLine := TAtlasStatusLine.Create(FRegistry, cStatusId, cStatusOrder);
  FStatusRef := mLine;
  FRegistry.Add(FStatusRef);
  // Gelb: Das Anhalten an jeder Aufrufstelle bremst das Programm.
  mLine.Update(TAtlasAsyncOriginTexts.StatusText(Length(FSites)), TAtlasStatusState.Yellow,
    TAtlasDebugStrings.Fmt(TAtlasDebugTextId.AsyncOriginArmed, [Length(FSites)]));
end;

end.
