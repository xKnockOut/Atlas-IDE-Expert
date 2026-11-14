unit Atlas.Common.Diagnostics.BugReport.Tests;

// Fehlerbericht des Servers (#108): Ringpuffer der Anfragen und der
// Logzeilen mit fester Größe, kein Dokumentinhalt aus didOpen/didChange,
// Anonymisierung ohne absoluten Pfad des Arbeitsbereichs.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBugReportTests = class
  public
    [Test]
    procedure RecentRequestsKeepFixedCapacity;
    [Test]
    procedure RecentLogLinesKeepFixedCapacity;
    [Test]
    procedure ReportHasNoDocumentContent;
    [Test]
    procedure AnonymizedReportHasNoWorkspacePath;
    [Test]
    procedure AnonymizesPathsUsersAndQuotedValues;
    [Test]
    procedure WithoutAnonymizationKeepsPaths;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Diagnostics.BugReport;

const
  cRoot = 'C:\Projekte\Geheim';
  cSecret = 'GeheimeProzedurXyz';

function Input: TBugReportInput;
begin
  Result := Default(TBugReportInput);
  Result.ServerVersion := '0.1.0';
  Result.Client := 'Atlas-Plugin 0.1.0, IDE 37.0, Win32';
  Result.Created := EncodeDate(2026, 10, 14);
  Result.Workspaces := [cRoot + '\'];
  Result.Identity := ['marco', 'PC1'];
  Result.Anonymize := True;
  Result.Configuration := '{"workspaces": [{"root": "C:\\Projekte\\Geheim", "file": "atlas.json"}],' +
    ' "editor": {"serverPath": "D:\\Tools\\AtlasServer.exe"}}';
  Result.LogLines := ['2026-10-14 10:00:00.000 [INFO] Projektdatei in ' + cRoot + '\App.dproj geändert',
    '2026-10-14 10:00:01.000 [INFO] Datei file:///c%3A/Projekte/Geheim/Main.pas geöffnet',
    '2026-10-14 10:00:02.000 [WARNING] Unit "' + cSecret + '" fehlt, Benutzer marco'];
end;

{ TBugReportTests }

procedure TBugReportTests.RecentRequestsKeepFixedCapacity;
var
  mStatistics: IJsonRpcStatistics;
  mRecent: TArray<TRecentRequest>;
  mIndex: Integer;
begin
  mStatistics := TJsonRpcStatistics.Create;
  Assert.AreEqual(0, Integer(Length(mStatistics.Recent)));
  for mIndex := 1 to TJsonRpcStatistics.cRecentCapacity + 7 do
  begin
    mStatistics.Add('m' + IntToStr(mIndex), mIndex, mIndex mod 2 = 0);
  end;
  mRecent := mStatistics.Recent;
  Assert.AreEqual(TJsonRpcStatistics.cRecentCapacity, Integer(Length(mRecent)));
  // Die ältesten sieben sind verdrängt, Reihenfolge älteste zuerst.
  Assert.AreEqual('m8', mRecent[0].Method);
  Assert.AreEqual('m57', mRecent[High(mRecent)].Method);
  Assert.IsFalse(mRecent[High(mRecent)].Failed);
  Assert.AreEqual(Int64(57), mRecent[High(mRecent)].ElapsedMs);
end;

procedure TBugReportTests.RecentLogLinesKeepFixedCapacity;
var
  mSink: TRecentLogSink;
  mLines: IRecentLogLines;
  mIndex: Integer;
begin
  mSink := TRecentLogSink.Create(3);
  mLines := mSink;
  Assert.AreEqual(0, Integer(Length(mLines.Lines)));
  for mIndex := 1 to 5 do
  begin
    mSink.Write(TLogEntry.Create(Now, TLogLevel.Info, 'Zeile ' + IntToStr(mIndex)));
  end;
  Assert.AreEqual(3, Integer(Length(mLines.Lines)));
  Assert.EndsWith('Zeile 3', mLines.Lines[0]);
  Assert.EndsWith('Zeile 5', mLines.Lines[2]);
  Assert.AreEqual(200, TRecentLogSink.cDefaultCapacity);
end;

procedure TBugReportTests.ReportHasNoDocumentContent;
var
  mDispatcher: TJsonRpcDispatcher;
  mStatistics: IJsonRpcStatistics;
  mReport: TBugReportInput;
  mMessage, mAnswer: TJSONObject;
  mText: string;

  procedure Send(const AJson: string);
  begin
    mMessage := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
    try
      mAnswer := mDispatcher.DispatchMessage(mMessage);
      mAnswer.Free;
    finally
      mMessage.Free;
    end;
  end;

begin
  mStatistics := TJsonRpcStatistics.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mDispatcher.Statistics := mStatistics;
    mDispatcher.RegisterNotification('textDocument/didOpen',
      procedure(const AParams: TJSONValue)
      begin
      end);
    mDispatcher.RegisterNotification('textDocument/didChange',
      procedure(const AParams: TJSONValue)
      begin
      end);
    mDispatcher.RegisterRequest('textDocument/hover',
      function(const AParams: TJSONValue): TJSONValue
      begin
        Result := TJSONString.Create('procedure ' + cSecret + ';');
      end);
    Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///c%3A/x.pas",' +
      '"text":"unit X; procedure ' + cSecret + '; begin end; end."}}}');
    Send('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"contentChanges":[{"text":"' + cSecret +
      'Neu"}]}}');
    Send('{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"position":{"line":0,"character":3}}}');
  finally
    mDispatcher.Free;
  end;
  mReport := Input;
  mReport.LogLines := nil;
  mReport.Requests := mStatistics.Recent;
  mText := TBugReport.Build(mReport);
  Assert.Contains(mText, 'textDocument/hover');
  Assert.DoesNotContain(mText, cSecret);
  Assert.DoesNotContain(mText, 'unit X');
end;

procedure TBugReportTests.AnonymizedReportHasNoWorkspacePath;
var
  mText: string;
begin
  mText := TBugReport.Build(Input);
  Assert.DoesNotContain(mText, 'Projekte', True);
  Assert.DoesNotContain(mText, 'Geheim\', True);
  Assert.DoesNotContain(mText, 'D:\Tools', True);
  Assert.DoesNotContain(mText, cSecret);
  Assert.DoesNotContain(mText, 'marco', True);
  // Unter dem Arbeitsbereich bleiben nur Wurzel und Endung (#1478).
  Assert.Contains(mText, '<ws>/<datei>.dproj');
  Assert.Contains(mText, '<ws>/<datei>.pas');
  Assert.Contains(mText, 'anonymisiert');
  Assert.Contains(mText, 'Server: 0.1.0');
  Assert.Contains(mText, 'IDE 37.0');
end;

procedure TBugReportTests.AnonymizesPathsUsersAndQuotedValues;
begin
  Assert.AreEqual('Datei <pfad> und <pfad> fehlt',
    TBugReport.AnonymizePaths('Datei E:\Andere\a.pas und \\server\share\b.inc fehlt', [cRoot], []));
  Assert.AreEqual('<ws>/<datei>.pas', TBugReport.AnonymizePaths(cRoot + '\src\a.pas', [cRoot], []));
  Assert.AreEqual('"<ws>/<datei>"', TBugReport.AnonymizePaths('"C:\\Projekte\\Geheim\\src"', [cRoot], []));
  Assert.AreEqual('Zeit 10:00:01, http://x.de', TBugReport.AnonymizePaths('Zeit 10:00:01, http://x.de', [cRoot], []));
  Assert.AreEqual('Hallo <benutzer>', TBugReport.AnonymizePaths('Hallo Marco', [], ['marco', 'ab']));
  Assert.AreEqual('Unit "<wert>" und „<wert>“, don''t',
    TBugReport.AnonymizeLogLine('Unit "Foo" und „Bar“, don''t', [], []));
end;

procedure TBugReportTests.WithoutAnonymizationKeepsPaths;
var
  mReport: TBugReportInput;
  mText: string;
begin
  mReport := Input;
  mReport.Anonymize := False;
  mText := TBugReport.Build(mReport);
  Assert.Contains(mText, cRoot + '\App.dproj');
  Assert.DoesNotContain(mText, 'anonymisiert');
end;

initialization
  TDUnitX.RegisterTestFixture(TBugReportTests);

end.
