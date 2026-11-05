unit Atlas.IDE.Debug.Report;

// Bericht über die laufende Debug-Sitzung für andere Module (#1455): stellt
// IAtlasDebugReportSource bereit (Prozess, gestartetes Projekt, Debug-Notiz
// #582, Exception-Verlauf #517). Der Tracker („An Issue anhängen …“, #1276)
// fragt den Vertrag über die Registry und kennt den Debugger nicht; Notiz
// und Verlauf lagen bis #1455 in Atlas.IDE.Tracker.Attach.

interface

uses
  Atlas.Core.Debug.Note,
  Atlas.IDE.Contracts.DebugReport;

type
  TAtlasIdeDebugReport = class(TInterfacedObject, IAtlasDebugReportSource)
  private
    class function NoteTexts: TAtlasDebugNoteTexts; static;
  public
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
  Atlas.Core.Files.Contract,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.UI.Debug.Strings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Exceptions;

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

class function TAtlasIdeDebugReport.NoteTexts: TAtlasDebugNoteTexts;
begin
  Result.Title := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteTitle);
  Result.Project := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteProject);
  Result.Configuration := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteConfiguration);
  Result.TargetPlatform := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNotePlatform);
  Result.Time := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteTime);
  Result.Thread := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteThread);
  Result.Location := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteLocation);
  Result.CallStack := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteCallStack);
  Result.LastException := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteLastException);
  Result.Count := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteCount);
  Result.NoLocation := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteNoLocation);
end;

/// <summary>Aufrufstapel des Halts mit eigenem Code markiert, dazu die Routine des obersten Rahmens.</summary>
procedure AddFrames(var AData: TAtlasDebugNoteData; const AThread: IOTAThread);
var
  mFrames: TAtlasDebugFrames;
begin
  if TAtlasIdeDebugSession.ReadStack(AThread, TAtlasDebugNote.MaxFrames, mFrames) <> TAtlasDebugStackRead.Ready then
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

function TAtlasIdeDebugReport.DebugNote(out AMarkdown, AFileName: string): Boolean;
var
  mThread: IOTAThread;
  mData: TAtlasDebugNoteData;
begin
  AMarkdown := '';
  AFileName := '';
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if mThread = nil then
  begin
    Exit(False);
  end;
  mData := TAtlasDebugNoteData.Empty;
  mData.Project := TAtlasIdeDebugSession.LaunchProject;
  mData.Configuration := TAtlasIdeDebugSession.LaunchConfiguration;
  mData.TargetPlatform := TAtlasIdeDebugSession.LaunchPlatform;
  mData.Time := Now;
  mData.Thread := TAtlasDebugException.Create(0, '', '', mThread.GetOSThreadID,
    TAtlasIdeDebugSession.ThreadName(mThread)).ThreadText(
    TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsThread));
  mData.FileName := mThread.CurrentFile;
  mData.Line := Integer(mThread.CurrentLine);
  AddFrames(mData, mThread);
  AddSource(mData);
  AddException(mData);
  AMarkdown := TAtlasDebugNote.Markdown(mData, NoteTexts);
  AFileName := TAtlasDebugNote.FileName(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugNoteFileStem), mData.Time);
  Result := True;
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
