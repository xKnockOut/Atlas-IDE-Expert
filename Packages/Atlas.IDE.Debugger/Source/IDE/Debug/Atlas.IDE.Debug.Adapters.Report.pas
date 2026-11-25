unit Atlas.IDE.Debug.Adapters.Report;

// Bericht über die laufende Debug-Sitzung für andere Module (#1455): stellt
// IAtlasDebugReportSource (Atlas.IDE.Base.Foundation.DebugReport) bereit (Prozess,
// gestartetes Projekt, Debug-Notiz #582, Exception-Verlauf #517). Der Tracker
// („An Issue anhängen …“, #1276) fragt den Vertrag über die Registry und kennt
// den Debugger nicht. Die Notiz kommt aus Atlas.IDE.Debug.Report.

interface

uses
  Atlas.IDE.Base.Foundation.DebugReport;

type
  TAtlasIdeDebugReportSource = class(TInterfacedObject, IAtlasDebugReportSource)
  public
    function DebuggedProcessId: Cardinal;
    function LaunchProject: string;
    function DebugNote(out AMarkdown, AFileName: string): Boolean;
    function ExceptionsText(AMax: Integer; out ACount: Integer): string;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Debug.Note,
  Atlas.Core.Debug.Exceptions,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Debug.Report;

{ TAtlasIdeDebugReportSource }

function TAtlasIdeDebugReportSource.DebuggedProcessId: Cardinal;
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

function TAtlasIdeDebugReportSource.LaunchProject: string;
begin
  Result := TAtlasIdeDebugSession.LaunchProject;
end;

function TAtlasIdeDebugReportSource.DebugNote(out AMarkdown, AFileName: string): Boolean;
var
  mData: TAtlasDebugNoteData;
begin
  AMarkdown := '';
  AFileName := '';
  Result := TAtlasIdeDebugReport.NoteData(mData);
  if Result then
  begin
    AMarkdown := TAtlasDebugNote.Markdown(mData, TAtlasIdeDebugReport.NoteTexts);
    AFileName := TAtlasIdeDebugReport.NoteFileName(mData.Time);
  end;
end;

function TAtlasIdeDebugReportSource.ExceptionsText(AMax: Integer; out ACount: Integer): string;
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
