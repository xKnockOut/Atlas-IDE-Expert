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
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.RecentSink,
  Atlas.Common.JsonRpc.Statistics,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Diagnostics.BugReport;

const
  Root = 'C:\Projekte\Geheim';
  Secret = 'GeheimeProzedurXyz';

function Input: TBugReportInput;
begin
  Result := Default(TBugReportInput);
  Result.ServerVersion := '0.1.0';
  Result.Client := 'Atlas-Plugin 0.1.0, IDE 37.0, Win32';
  Result.Created := EncodeDate(2026, 10, 14);
  Result.Workspaces := [Root + '\'];
  Result.Identity := ['marco', 'PC1'];
  Result.Anonymize := True;
  Result.Configuration := '{"workspaces": [{"root": "C:\\Projekte\\Geheim", "file": "atlas.json"}],' +
    ' "editor": {"serverPath": "D:\\Tools\\AtlasServer.exe"}}';
  Result.LogLines := ['2026-10-14 10:00:00.000 [INFO] Projektdatei in ' + Root + '\App.dproj geändert',
    '2026-10-14 10:00:01.000 [INFO] Datei file:///c%3A/Projekte/Geheim/Main.pas geöffnet',
    '2026-10-14 10:00:02.000 [WARNING] Unit "' + Secret + '" fehlt, Benutzer marco'];
end;

{ TBugReportTests }

procedure TBugReportTests.RecentRequestsKeepFixedCapacity;
var
  Statistics: IJsonRpcStatistics;
  Recent: TArray<TRecentRequest>;
  Index: Integer;
begin
  Statistics := TJsonRpcStatistics.Create;
  Assert.AreEqual(0, Integer(Length(Statistics.Recent)));
  for Index := 1 to TJsonRpcStatistics.RecentCapacity + 7 do
    Statistics.Add('m' + IntToStr(Index), Index, Index mod 2 = 0);
  Recent := Statistics.Recent;
  Assert.AreEqual(TJsonRpcStatistics.RecentCapacity, Integer(Length(Recent)));
  // Die ältesten sieben sind verdrängt, Reihenfolge älteste zuerst.
  Assert.AreEqual('m8', Recent[0].Method);
  Assert.AreEqual('m57', Recent[High(Recent)].Method);
  Assert.IsTrue(Recent[High(Recent)].Failed = False);
  Assert.AreEqual(Int64(57), Recent[High(Recent)].ElapsedMs);
end;

procedure TBugReportTests.RecentLogLinesKeepFixedCapacity;
var
  Sink: TRecentLogSink;
  Lines: IRecentLogLines;
  Index: Integer;
begin
  Sink := TRecentLogSink.Create(3);
  Lines := Sink;
  Assert.AreEqual(0, Integer(Length(Lines.Lines)));
  for Index := 1 to 5 do
    Sink.Write(TLogEntry.Create(Now, TLogLevel.Info, 'Zeile ' + IntToStr(Index)));
  Assert.AreEqual(3, Integer(Length(Lines.Lines)));
  Assert.EndsWith('Zeile 3', Lines.Lines[0]);
  Assert.EndsWith('Zeile 5', Lines.Lines[2]);
  Assert.AreEqual(TRecentLogSink.DefaultCapacity, 200);
end;

procedure TBugReportTests.ReportHasNoDocumentContent;
var
  Dispatcher: TJsonRpcDispatcher;
  Statistics: IJsonRpcStatistics;
  Report: TBugReportInput;
  Message, Answer: TJSONObject;
  Text: string;

  procedure Send(const AJson: string);
  begin
    Message := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
    try
      Answer := Dispatcher.DispatchMessage(Message);
      Answer.Free;
    finally
      Message.Free;
    end;
  end;

begin
  Statistics := TJsonRpcStatistics.Create;
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Dispatcher.Statistics := Statistics;
    Dispatcher.RegisterNotification('textDocument/didOpen',
      procedure(const AParams: TJSONValue)
      begin
      end);
    Dispatcher.RegisterNotification('textDocument/didChange',
      procedure(const AParams: TJSONValue)
      begin
      end);
    Dispatcher.RegisterRequest('textDocument/hover',
      function(const AParams: TJSONValue): TJSONValue
      begin
        Result := TJSONString.Create('procedure ' + Secret + ';');
      end);
    Send('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///c%3A/x.pas",' +
      '"text":"unit X; procedure ' + Secret + '; begin end; end."}}}');
    Send('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"contentChanges":[{"text":"' + Secret +
      'Neu"}]}}');
    Send('{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"position":{"line":0,"character":3}}}');
  finally
    Dispatcher.Free;
  end;
  Report := Input;
  Report.LogLines := nil;
  Report.Requests := Statistics.Recent;
  Text := TBugReport.Build(Report);
  Assert.Contains(Text, 'textDocument/hover');
  Assert.DoesNotContain(Text, Secret);
  Assert.DoesNotContain(Text, 'unit X');
end;

procedure TBugReportTests.AnonymizedReportHasNoWorkspacePath;
var
  Text: string;
begin
  Text := TBugReport.Build(Input);
  Assert.DoesNotContain(Text, 'Projekte', True);
  Assert.DoesNotContain(Text, 'Geheim\', True);
  Assert.DoesNotContain(Text, 'D:\Tools', True);
  Assert.DoesNotContain(Text, Secret);
  Assert.DoesNotContain(Text, 'marco', True);
  Assert.Contains(Text, '<ws>\App.dproj');
  Assert.Contains(Text, '<ws>/Main.pas');
  Assert.Contains(Text, 'anonymisiert');
  Assert.Contains(Text, 'Server: 0.1.0');
  Assert.Contains(Text, 'IDE 37.0');
end;

procedure TBugReportTests.AnonymizesPathsUsersAndQuotedValues;
begin
  Assert.AreEqual('Datei <pfad> und <pfad> fehlt',
    TBugReport.AnonymizePaths('Datei E:\Andere\a.pas und \\server\share\b.inc fehlt', [Root], []));
  Assert.AreEqual('<ws>\src\a.pas', TBugReport.AnonymizePaths(Root + '\src\a.pas', [Root], []));
  Assert.AreEqual('"<ws>\\src"', TBugReport.AnonymizePaths('"C:\\Projekte\\Geheim\\src"', [Root], []));
  Assert.AreEqual('Zeit 10:00:01, http://x.de', TBugReport.AnonymizePaths('Zeit 10:00:01, http://x.de', [Root], []));
  Assert.AreEqual('Hallo <benutzer>', TBugReport.AnonymizePaths('Hallo Marco', [], ['marco', 'ab']));
  Assert.AreEqual('Unit "<wert>" und „<wert>“, don''t',
    TBugReport.AnonymizeLogLine('Unit "Foo" und „Bar“, don''t', [], []));
end;

procedure TBugReportTests.WithoutAnonymizationKeepsPaths;
var
  Report: TBugReportInput;
  Text: string;
begin
  Report := Input;
  Report.Anonymize := False;
  Text := TBugReport.Build(Report);
  Assert.Contains(Text, Root + '\App.dproj');
  Assert.DoesNotContain(Text, 'anonymisiert');
end;

initialization
  TDUnitX.RegisterTestFixture(TBugReportTests);

end.
