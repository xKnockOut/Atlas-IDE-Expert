unit Atlas.IDE.Debug.BreakpointAnchors;

// Haltepunkte wandern mit dem Code (#841) im Debugger der IDE:
// - Ein Zeitgeber (2 s) sieht die Quelltext-Haltepunkte durch. Zu jedem merkt
//   sich Atlas einen Anker (TAtlasBreakpointAnchors, derselbe wie bei den
//   Haltepunkt-Sätzen #586); Texte offener Dateien kommen aus dem Editor.
// - Ändert sich eine Datei, entscheidet TAtlasBreakpointAnchors.IsExternal:
//   Von außen (in dieser Sitzung neu gesehen, auf der Platte geändert, also
//   neu geladen oder Branchwechsel, oder viele Zeilen auf einmal) zieht Atlas
//   die Haltepunkte nach (TAtlasIdeBreakpoints.MoveTo, mit allen
//   Eigenschaften); nicht zuordenbare bleiben stehen und kommen in die Liste
//   „Verwaiste Haltepunkte“. Sonst bearbeitet der Benutzer die Datei, die IDE
//   nimmt ihre Haltepunkte selbst mit, und Atlas merkt sich nur den neuen
//   Anker.
// - Eine Zeile in den Meldungen nennt das Ergebnis; „Haltepunkte zurück an
//   alte Zeilen“ nimmt das letzte Nachziehen zurück.
// - Anker liegen in %LOCALAPPDATA%\Atlas\breakpoint-anchors.json, damit auch
//   ein git pull bei geschlossener IDE nachgezogen wird. Gespeicherte Anker
//   ohne Haltepunkt in dieser Sitzung bleiben, solange ihre Datei besteht.
// - Haltepunkt-Regeln (#864) ziehen mit jeder Verschiebung mit.
// Ein Teil der Feature-Tabelle; Release hält den Zeitgeber an und speichert.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Editor.MethodAnchor,
  Atlas.Core.Debug.BreakpointAnchors;

type
  /// <summary>Zuletzt gesehener Stand einer Datei.</summary>
  TAtlasAnchorFileSeen = record
    Hash: Integer;
    Age: TDateTime;
    LineCount: Integer;
  end;

  /// <summary>Ergebnis eines Durchlaufs: neue Anker, Verschiebungen, Verwaiste.</summary>
  TAtlasAnchorBatch = record
    Next: TDictionary<string, TAtlasAnchoredBreakpoint>;
    Moves: TAtlasAnchorMoves;
    Orphans: TAtlasAnchorOrphans;
  end;

  TAtlasIdeBreakpointAnchors = class
  private const
    cStateFile = 'breakpoint-anchors.json';
    cTickMs = 2000;
    cSaveMs = 10000;
  private class var
    FStarted: Boolean;
    FTimer: TObject;
    FMessage: TProc<string>;
    // Anker der Haltepunkte dieser Sitzung, Schlüssel TAtlasBreakpointAnchors.Key.
    FAnchors: TDictionary<string, TAtlasAnchoredBreakpoint>;
    // Gespeicherte Anker, zu denen es in dieser Sitzung (noch) keinen Haltepunkt gab.
    FStored: TDictionary<string, TAtlasAnchoredBreakpoint>;
    FFiles: TDictionary<string, TAtlasAnchorFileSeen>;
    FUndo: TAtlasAnchorMoves;
    FOrphans: TAtlasAnchorOrphans;
    FLoaded: Boolean;
    FBusy: Boolean;
    FDirty: Boolean;
    FSavedAt: UInt64;
    class procedure Tick(Sender: TObject);
    class procedure Process; static;
    class procedure ProcessFile(const AFileName: string; const ALines: TArray<Integer>;
      var ABatch: TAtlasAnchorBatch); static;
    class procedure FollowLine(const AFileName: string; ALine: Integer; const AText: TAtlasMethodAnchorText;
      AChanged, AExternal: Boolean; var ABatch: TAtlasAnchorBatch); static;
    class procedure KeepAnchors(const AFileName: string; const ALines: TArray<Integer>;
      var ABatch: TAtlasAnchorBatch); static;
    class function NeedsWork(const AFileName: string; const ALines: TArray<Integer>; AChanged: Boolean): Boolean;
      static;
    class procedure Finish(const ABatch: TAtlasAnchorBatch); static;
    class function ApplyMoves(const AMoves: TAtlasAnchorMoves; ARelocate: Boolean): Integer; static;
    class procedure Relocate(const AFileName: string; AFromLine, AToLine: Integer); static;
    class procedure MergeOrphans(const ANew: TAtlasAnchorOrphans); static;
    class function OrphanAction(const AOrphan: TAtlasAnchorOrphan; ADelete: Boolean): Boolean; static;
    class function StateFile: string; static;
    class procedure Load; static;
    class procedure Save; static;
    class procedure Report(const AText: string); static;
  public
    /// <summary>Teil starten: Zeitgeber. AMessage schreibt eine Zeile in die Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.breakpointAnchors an und Teil gestartet?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Befehl „Haltepunkte zurück an alte Zeilen“: das letzte Nachziehen zurücknehmen.</summary>
    class procedure Undo; static;
    /// <summary>Befehl „Verwaiste Haltepunkte …“: Liste mit Übernehmen und Löschen.</summary>
    class procedure ShowOrphans; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Hash,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Files.DataFile,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.BreakpointRules,
  Atlas.UI.Debug.BreakpointAnchors,
  Atlas.UI.Debug.Strings;

/// <summary>Quelltext-Haltepunkte der IDE je Datei (Schlüssel: Dateiname wie in der IDE), Zeilen ab 0.</summary>
function BreakpointsByFile: TDictionary<string, TArray<Integer>>;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mBreakpoint: IOTASourceBreakpoint;
  mLines: TArray<Integer>;
begin
  Result := TDictionary<string, TArray<Integer>>.Create;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if (mBreakpoint = nil) or (mBreakpoint.FileName = '') or (mBreakpoint.LineNumber <= 0) then
    begin
      Continue;
    end;
    if not Result.TryGetValue(mBreakpoint.FileName, mLines) then
    begin
      mLines := nil;
    end;
    Result.AddOrSetValue(mBreakpoint.FileName, mLines + [mBreakpoint.LineNumber - 1]);
  end;
end;

function DiskAge(const AFileName: string): TDateTime;
begin
  if not FileAge(AFileName, Result) then
  begin
    Result := 0;
  end;
end;

/// <summary>Anker der Zeile ALine im aktuellen Text von AFileName.</summary>
function CaptureAt(const AFileName: string; ALine: Integer; const AText: TAtlasMethodAnchorText):
  TAtlasAnchoredBreakpoint;
begin
  Result := TAtlasAnchoredBreakpoint.Create(AFileName, ALine, TAtlasMethodAnchors.Capture(AText, ALine));
end;

{ TAtlasIdeBreakpointAnchors }

class procedure TAtlasIdeBreakpointAnchors.Start(const AMessage: TProc<string>);
var
  mTimer: TTimer;
begin
  FMessage := AMessage;
  FAnchors := TDictionary<string, TAtlasAnchoredBreakpoint>.Create;
  FStored := TDictionary<string, TAtlasAnchoredBreakpoint>.Create;
  FFiles := TDictionary<string, TAtlasAnchorFileSeen>.Create;
  FLoaded := False;
  FStarted := True;
  mTimer := TTimer.Create(nil);
  mTimer.Interval := cTickMs;
  mTimer.OnTimer := Tick;
  FTimer := mTimer;
end;

class procedure TAtlasIdeBreakpointAnchors.Release;
begin
  FreeAndNil(FTimer);
  if FStarted and FDirty then
  begin
    Save;
  end;
  FStarted := False;
  FreeAndNil(FAnchors);
  FreeAndNil(FStored);
  FreeAndNil(FFiles);
  FUndo := nil;
  FOrphans := nil;
  FMessage := nil;
  FBusy := False;
  FDirty := False;
end;

class function TAtlasIdeBreakpointAnchors.Started: Boolean;
begin
  Result := FStarted;
end;

class function TAtlasIdeBreakpointAnchors.Enabled: Boolean;
begin
  Result := Started and TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.DebugBreakpointAnchors;
end;

class procedure TAtlasIdeBreakpointAnchors.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class procedure TAtlasIdeBreakpointAnchors.Tick(Sender: TObject);
begin
  if FBusy or not Enabled then
  begin
    Exit;
  end;
  FBusy := True;
  try
    if not FLoaded then
    begin
      Load;
    end;
    Process;
    if FDirty and (TThread.GetTickCount64 - FSavedAt >= cSaveMs) then
    begin
      Save;
    end;
  finally
    FBusy := False;
  end;
end;

class procedure TAtlasIdeBreakpointAnchors.Process;
var
  mFiles: TDictionary<string, TArray<Integer>>;
  mPair: TPair<string, TArray<Integer>>;
  mBatch: TAtlasAnchorBatch;
begin
  mBatch := Default(TAtlasAnchorBatch);
  mFiles := BreakpointsByFile;
  try
    mBatch.Next := TDictionary<string, TAtlasAnchoredBreakpoint>.Create;
    try
      for mPair in mFiles do
      begin
        ProcessFile(mPair.Key, mPair.Value, mBatch);
      end;
      Finish(mBatch);
    except
      mBatch.Next.Free;
      raise;
    end;
  finally
    mFiles.Free;
  end;
end;

class procedure TAtlasIdeBreakpointAnchors.KeepAnchors(const AFileName: string; const ALines: TArray<Integer>;
  var ABatch: TAtlasAnchorBatch);
var
  mLine: Integer;
  mItem: TAtlasAnchoredBreakpoint;
begin
  for mLine in ALines do
  begin
    if FAnchors.TryGetValue(TAtlasBreakpointAnchors.Key(AFileName, mLine), mItem) then
    begin
      ABatch.Next.AddOrSetValue(TAtlasBreakpointAnchors.Key(AFileName, mLine), mItem);
    end;
  end;
end;

class function TAtlasIdeBreakpointAnchors.NeedsWork(const AFileName: string; const ALines: TArray<Integer>;
  AChanged: Boolean): Boolean;
var
  mLine: Integer;
begin
  Result := AChanged;
  for mLine in ALines do
  begin
    Result := Result or not FAnchors.ContainsKey(TAtlasBreakpointAnchors.Key(AFileName, mLine));
  end;
end;

class procedure TAtlasIdeBreakpointAnchors.ProcessFile(const AFileName: string; const ALines: TArray<Integer>;
  var ABatch: TAtlasAnchorBatch);
var
  mSource: string;
  mText: TAtlasMethodAnchorText;
  mSeen, mNow: TAtlasAnchorFileSeen;
  mKnown, mChanged, mExternal: Boolean;
  mLine: Integer;
begin
  mNow := Default(TAtlasAnchorFileSeen);
  // Unlesbar (Datei weg): Anker unverändert behalten.
  if not TAtlasIdeFiles.SourceText(AFileName, mSource) then
  begin
    KeepAnchors(AFileName, ALines, ABatch);
    Exit;
  end;
  mNow.Hash := THashBobJenkins.GetHashValue(mSource);
  mNow.Age := DiskAge(AFileName);
  mKnown := FFiles.TryGetValue(LowerCase(AFileName), mSeen);
  mChanged := not mKnown or (mSeen.Hash <> mNow.Hash);
  if not NeedsWork(AFileName, ALines, mChanged) then
  begin
    KeepAnchors(AFileName, ALines, ABatch);
    Exit;
  end;
  mText := TAtlasMethodAnchorText.Create(mSource);
  mNow.LineCount := Length(mText.Lines);
  mExternal := TAtlasBreakpointAnchors.IsExternal(mKnown, mKnown and (mSeen.Age <> mNow.Age), mSeen.LineCount,
    mNow.LineCount);
  for mLine in ALines do
  begin
    FollowLine(AFileName, mLine, mText, mChanged, mExternal, ABatch);
  end;
  FFiles.AddOrSetValue(LowerCase(AFileName), mNow);
  FDirty := True;
end;

class procedure TAtlasIdeBreakpointAnchors.FollowLine(const AFileName: string; ALine: Integer;
  const AText: TAtlasMethodAnchorText; AChanged, AExternal: Boolean; var ABatch: TAtlasAnchorBatch);
var
  mKey: string;
  mItem: TAtlasAnchoredBreakpoint;
  mFresh: Boolean;
  mResult: TAtlasAnchorResult;
  mOrphan: TAtlasAnchorOrphan;
begin
  mKey := TAtlasBreakpointAnchors.Key(AFileName, ALine);
  // Gespeicherter Anker aus einer früheren Sitzung: immer nachziehen.
  mFresh := not FAnchors.TryGetValue(mKey, mItem) and FStored.TryGetValue(mKey, mItem);
  if mFresh then
  begin
    FStored.Remove(mKey);
  end
  else if not FAnchors.ContainsKey(mKey) then
  begin
    // Neuer Haltepunkt: Anker merken.
    ABatch.Next.AddOrSetValue(mKey, CaptureAt(AFileName, ALine, AText));
    Exit;
  end
  else if not AChanged then
  begin
    // Datei unverändert: Anker bleibt (auch der alte eines verwaisten Haltepunkts).
    ABatch.Next.AddOrSetValue(mKey, mItem);
    Exit;
  end;
  mItem.Line := ALine;
  mResult := TAtlasBreakpointAnchors.Follow(AText, mItem);
  if (mResult.Step = TAtlasAnchorStep.Keep) or not (AExternal or mFresh) then
  begin
    ABatch.Next.AddOrSetValue(mKey, CaptureAt(AFileName, ALine, AText));
  end
  else if mResult.Step = TAtlasAnchorStep.Move then
  begin
    ABatch.Moves := ABatch.Moves + [TAtlasAnchorMove.Create(AFileName, ALine, mResult.Line)];
    ABatch.Next.AddOrSetValue(TAtlasBreakpointAnchors.Key(AFileName, mResult.Line),
      CaptureAt(AFileName, mResult.Line, AText));
  end
  else
  begin
    // Verwaist: alter Anker bleibt, damit ein späterer Stand ihn wiederfinden kann.
    mOrphan.Item := mItem;
    mOrphan.Suggestion := mResult.Line;
    ABatch.Orphans := ABatch.Orphans + [mOrphan];
    ABatch.Next.AddOrSetValue(mKey, mItem);
  end;
end;

class procedure TAtlasIdeBreakpointAnchors.Finish(const ABatch: TAtlasAnchorBatch);
var
  mMoved: Integer;
  mMove: TAtlasAnchorMove;
begin
  FAnchors.Free;
  FAnchors := ABatch.Next;
  if (ABatch.Moves = nil) and (ABatch.Orphans = nil) then
  begin
    Exit;
  end;
  mMoved := ApplyMoves(ABatch.Moves, False);
  if ABatch.Moves <> nil then
  begin
    FUndo := ABatch.Moves;
  end;
  MergeOrphans(ABatch.Orphans);
  for mMove in ABatch.Moves do
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointAnchorsMovedLine,
      [ExtractFileName(mMove.FileName), mMove.FromLine + 1, mMove.ToLine + 1]));
  end;
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointAnchorsSummary, [mMoved, Length(ABatch.Orphans)]));
end;

class function TAtlasIdeBreakpointAnchors.ApplyMoves(const AMoves: TAtlasAnchorMoves; ARelocate: Boolean): Integer;
var
  mMove: TAtlasAnchorMove;
  mBreakpoint: IOTABreakpoint;
begin
  Result := 0;
  for mMove in TAtlasBreakpointAnchors.Ordered(AMoves) do
  begin
    mBreakpoint := TAtlasIdeBreakpoints.Find(mMove.FileName, mMove.FromLine);
    if (mBreakpoint = nil) or (TAtlasIdeBreakpoints.MoveTo(mBreakpoint, mMove.ToLine) = nil) then
    begin
      Continue;
    end;
    Inc(Result);
    // Regeln (#864) hängen an der Zeile: mitziehen.
    TAtlasIdeBreakpointRules.Moved(mMove.FileName, mMove.FromLine, mMove.ToLine);
    if ARelocate then
    begin
      Relocate(mMove.FileName, mMove.FromLine, mMove.ToLine);
    end;
  end;
end;

class procedure TAtlasIdeBreakpointAnchors.Relocate(const AFileName: string; AFromLine, AToLine: Integer);
var
  mSource: string;
begin
  FAnchors.Remove(TAtlasBreakpointAnchors.Key(AFileName, AFromLine));
  if TAtlasIdeFiles.SourceText(AFileName, mSource) then
  begin
    FAnchors.AddOrSetValue(TAtlasBreakpointAnchors.Key(AFileName, AToLine),
      CaptureAt(AFileName, AToLine, TAtlasMethodAnchorText.Create(mSource)));
  end;
  FDirty := True;
end;

class procedure TAtlasIdeBreakpointAnchors.MergeOrphans(const ANew: TAtlasAnchorOrphans);
var
  mOld, mNew: TAtlasAnchorOrphan;
  mKnown: Boolean;
begin
  for mOld in FOrphans do
  begin
    mKnown := False;
    for mNew in ANew do
    begin
      mKnown := mKnown or (TAtlasBreakpointAnchors.Key(mNew.Item.FileName, mNew.Item.Line) =
        TAtlasBreakpointAnchors.Key(mOld.Item.FileName, mOld.Item.Line));
    end;
    if not mKnown and (TAtlasIdeBreakpoints.Find(mOld.Item.FileName, mOld.Item.Line) <> nil) then
    begin
      FOrphans := FOrphans + [mOld];
    end;
  end;
  FOrphans := FOrphans + ANew;
end;

class procedure TAtlasIdeBreakpointAnchors.Undo;
var
  mMoved: Integer;
begin
  if FUndo = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointAnchorsNothingToUndo));
    Exit;
  end;
  mMoved := ApplyMoves(TAtlasBreakpointAnchors.Reversed(FUndo), True);
  FUndo := nil;
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointAnchorsUndone, [mMoved]));
end;

class function TAtlasIdeBreakpointAnchors.OrphanAction(const AOrphan: TAtlasAnchorOrphan; ADelete: Boolean): Boolean;
var
  mBreakpoints: TArray<IOTABreakpoint>;
  mBreakpoint: IOTABreakpoint;
begin
  mBreakpoint := TAtlasIdeBreakpoints.Find(AOrphan.Item.FileName, AOrphan.Item.Line);
  // Schon vom Benutzer gelöscht oder verschoben: nichts mehr zu tun.
  Result := mBreakpoint = nil;
  if Result then
  begin
    Exit;
  end;
  if ADelete then
  begin
    mBreakpoints := [mBreakpoint];
    TAtlasIdeBreakpoints.RemoveAll(mBreakpoints);
    FAnchors.Remove(TAtlasBreakpointAnchors.Key(AOrphan.Item.FileName, AOrphan.Item.Line));
    FDirty := True;
    Exit(True);
  end;
  Result := TAtlasIdeBreakpoints.MoveTo(mBreakpoint, AOrphan.Suggestion) <> nil;
  if Result then
  begin
    TAtlasIdeBreakpointRules.Moved(AOrphan.Item.FileName, AOrphan.Item.Line, AOrphan.Suggestion);
    Relocate(AOrphan.Item.FileName, AOrphan.Item.Line, AOrphan.Suggestion);
  end;
end;

class procedure TAtlasIdeBreakpointAnchors.ShowOrphans;
var
  mOrphans: TAtlasAnchorOrphans;
  mOrphan: TAtlasAnchorOrphan;
begin
  mOrphans := nil;
  for mOrphan in FOrphans do
  begin
    if TAtlasIdeBreakpoints.Find(mOrphan.Item.FileName, mOrphan.Item.Line) <> nil then
    begin
      mOrphans := mOrphans + [mOrphan];
    end;
  end;
  FOrphans := mOrphans;
  if FOrphans = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointAnchorsNoOrphans));
    Exit;
  end;
  FOrphans := TAtlasBreakpointOrphanDialog.Execute(FOrphans, OrphanAction);
end;

class function TAtlasIdeBreakpointAnchors.StateFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), cStateFile);
end;

class procedure TAtlasIdeBreakpointAnchors.Load;
var
  mText: string;
  mItems: TAtlasAnchoredBreakpoints;
  mItem: TAtlasAnchoredBreakpoint;
begin
  FLoaded := True;
  if not (TAtlasDataFile.TryRead(StateFile, mText) and TAtlasBreakpointAnchors.Parse(mText, mItems)) then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    // Anker gelöschter Dateien fallen weg.
    if TFile.Exists(mItem.FileName) then
    begin
      FStored.AddOrSetValue(TAtlasBreakpointAnchors.Key(mItem.FileName, mItem.Line), mItem);
    end;
  end;
end;

class procedure TAtlasIdeBreakpointAnchors.Save;
var
  mItems: TAtlasAnchoredBreakpoints;
begin
  FDirty := False;
  FSavedAt := TThread.GetTickCount64;
  mItems := FAnchors.Values.ToArray + FStored.Values.ToArray;
  try
    ForceDirectories(ExtractFileDir(StateFile));
    TAtlasDataFile.Write(StateFile, TAtlasBreakpointAnchors.ToJson(mItems));
  except
    // Ohne Datei geht nur das Nachziehen nach einem Neustart verloren.
    on E: Exception do
      Report(E.Message);
  end;
end;

end.
