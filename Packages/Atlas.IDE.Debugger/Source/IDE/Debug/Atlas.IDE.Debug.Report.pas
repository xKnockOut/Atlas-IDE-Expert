unit Atlas.IDE.Debug.Report;

// Bericht über die laufende Debug-Sitzung für andere Module (#1455): stellt
// IAtlasDebugReportSource bereit (Prozess, gestartetes Projekt, Debug-Notiz
// #582, Exception-Verlauf #517). Der Tracker („An Issue anhängen …“, #1276)
// fragt den Vertrag über die Registry und kennt den Debugger nicht.
// NoteData und NoteTexts nutzt auch „Debug-Zustand festhalten“ (#582,
// Atlas.IDE.Debug.Note), das die Werte des Halts selbst nachlädt.

interface

uses
  Atlas.Core.Debug.Note,
  Atlas.IDE.Contracts.DebugReport;

type
  TAtlasIdeDebugReport = class(TInterfacedObject, IAtlasDebugReportSource)
  public const
    /// <summary>Zeilen des Ereignisprotokolls in der Notiz.</summary>
    cNoteEvents = TAtlasDebugNote.cMaxEvents;
  public
    /// <summary>Überschriften der Notiz in der Sprache der Oberfläche.</summary>
    class function NoteTexts: TAtlasDebugNoteTexts; static;
    /// <summary>Zustand des Halts ohne Werte: Projekt, Ort mit Ausschnitt, Aufrufstapel, letzte Exception und die
    /// letzten Zeilen des Ereignisprotokolls; False, wenn das Programm nicht angehalten ist.</summary>
    class function NoteData(out AData: TAtlasDebugNoteData): Boolean; static;
    /// <summary>Dateiname der Notiz zur Zeit ATime in der Sprache der Oberfläche.</summary>
    class function NoteFileName(ATime: TDateTime): string; static;
    function DebuggedProcessId: Cardinal;
    function LaunchProject: string;
    function DebugNote(out AMarkdown, AFileName: string): Boolean;
    function ExceptionsText(AMax: Integer; out ACount: Integer): string;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.UI.Debug.Exceptions.Strings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.EventLog,
  Atlas.UI.Debug.Note.Strings,
  Atlas.IDE.Debug.Exceptions;

{ TAtlasIdeDebugReport }

class function TAtlasIdeDebugReport.NoteTexts: TAtlasDebugNoteTexts;
begin
  Result.Title := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteTitle);
  Result.Project := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteProject);
  Result.Configuration := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteConfiguration);
  Result.TargetPlatform := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNotePlatform);
  Result.Time := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteTime);
  Result.Thread := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteThread);
  Result.Location := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteLocation);
  Result.CallStack := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteCallStack);
  Result.LastException := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteLastException);
  Result.Count := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteCount);
  Result.NoLocation := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteNoLocation);
  Result.Locals := TAtlasNoteStrings.Text(TAtlasNoteTextId.NoteLocals);
  Result.Watches := TAtlasNoteStrings.Text(TAtlasNoteTextId.NoteWatches);
  Result.Events := TAtlasNoteStrings.Text(TAtlasNoteTextId.NoteEvents);
  Result.Unavailable := TAtlasNoteStrings.Text(TAtlasNoteTextId.NoteUnavailable);
  Result.Pending := TAtlasNoteStrings.Text(TAtlasNoteTextId.NotePending);
end;

class function TAtlasIdeDebugReport.NoteFileName(ATime: TDateTime): string;
begin
  Result := TAtlasDebugNote.FileName(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugNoteFileStem), ATime);
end;

function TAtlasIdeDebugReport.DebuggedProcessId: Cardinal;
var
  mProcess: IOTAProcess;
begin
  Result := 0;
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess <> nil then
  begin
    Result := mProcess.ProcessId;
  end;
end;

function TAtlasIdeDebugReport.LaunchProject: string;
begin
  Result := TAtlasIdeDebugSession.LaunchProject;
end;

/// <summary>Aufrufstapel des Halts mit eigenem Code markiert, dazu die Routine des obersten Rahmens.</summary>
procedure AddFrames(var AData: TAtlasDebugNoteData; const AThread: IOTAThread);
var
  mFrames: TAtlasDebugFrames;
begin
  if TAtlasIdeDebugSession.ReadStack(AThread, TAtlasDebugNote.cMaxFrames, mFrames) <> TAtlasDebugStackRead.Ready then
  begin
    Exit;
  end;
  TAtlasIdeDebugSources.MarkFrames(mFrames);
  AData.Frames := mFrames;
  if Length(mFrames) > 0 then
  begin
    AData.Routine := TAtlasDebugCallStack.RoutineOf(mFrames[0].Header);
  end;
end;

/// <summary>Ausschnitt von der Platte; ohne Datei bleibt der Ort ohne Code.</summary>
procedure AddSource(var AData: TAtlasDebugNoteData);
var
  mFile: string;
begin
  if AData.FileName = '' then
  begin
    Exit;
  end;
  mFile := TAtlasIdeDebugSources.Resolve(AData.FileName);
  if mFile = '' then
  begin
    Exit;
  end;
  try
    // Kodierung wie die IDE: BOM, sonst UTF-8, sonst ANSI des Systems.
    AData.Source := TTextLines.SplitLines(TAtlasTextFile.Decode(TFile.ReadAllBytes(mFile)).Text);
    AData.SourceFirstLine := 1;
  except
    on E: EInOutError do
      AData.Source := nil;
    on E: EFileStreamError do
      AData.Source := nil;
    on E: EAtlasTextFileError do
      AData.Source := nil;
  end;
end;

/// <summary>Neueste Exception der Sitzung.</summary>
procedure AddException(var AData: TAtlasDebugNoteData);
var
  mHistory: TAtlasDebugExceptionHistory;
  mNewest: TArray<Integer>;
begin
  mHistory := TAtlasIdeDebugExceptions.History;
  if mHistory = nil then
  begin
    Exit;
  end;
  mNewest := mHistory.Filter('', '');
  if Length(mNewest) > 0 then
  begin
    AData.HasException := True;
    AData.Exception := mHistory[mNewest[0]];
  end;
end;

class function TAtlasIdeDebugReport.NoteData(out AData: TAtlasDebugNoteData): Boolean;
var
  mThread: IOTAThread;
begin
  AData := TAtlasDebugNoteData.Empty;
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if mThread = nil then
  begin
    Exit(False);
  end;
  AData.Project := TAtlasIdeDebugSession.LaunchProject;
  AData.Configuration := TAtlasIdeDebugSession.LaunchConfiguration;
  AData.TargetPlatform := TAtlasIdeDebugSession.LaunchPlatform;
  AData.Time := Now;
  AData.Thread := TAtlasDebugException.Create(0, '', '', mThread.GetOSThreadID,
    TAtlasIdeDebugSession.ThreadName(mThread)).ThreadText(
    TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsThread));
  AData.FileName := mThread.CurrentFile;
  AData.Line := Integer(mThread.CurrentLine);
  AddFrames(AData, mThread);
  AddSource(AData);
  AddException(AData);
  AData.Events := TAtlasIdeDebugEventLog.LastLines(cNoteEvents);
  Result := True;
end;

function TAtlasIdeDebugReport.DebugNote(out AMarkdown, AFileName: string): Boolean;
var
  mData: TAtlasDebugNoteData;
begin
  AMarkdown := '';
  AFileName := '';
  Result := NoteData(mData);
  if Result then
  begin
    AMarkdown := TAtlasDebugNote.Markdown(mData, NoteTexts);
    AFileName := NoteFileName(mData.Time);
  end;
end;

function TAtlasIdeDebugReport.ExceptionsText(AMax: Integer; out ACount: Integer): string;
var
  mHistory: TAtlasDebugExceptionHistory;
  mIndexes: TArray<Integer>;
  mItems: TAtlasDebugExceptions;
  mIndex: Integer;
begin
  Result := '';
  ACount := 0;
  mHistory := TAtlasIdeDebugExceptions.History;
  if mHistory = nil then
  begin
    Exit;
  end;
  mIndexes := mHistory.Filter('', '');
  ACount := Length(mIndexes);
  mItems := nil;
  for mIndex in mIndexes do
  begin
    if Length(mItems) >= AMax then
    begin
      Break;
    end;
    mItems := mItems + [mHistory[mIndex]];
  end;
  Result := TAtlasDebugNote.HistoryText(mItems, AMax);
end;

end.
