unit Atlas.Common.Lsp.WorkDoneProgress.Tests;

// Tests für die Fortschrittsanzeige über window/workDoneProgress/create und
// $/progress (#415): Ablauf begin/report/end, Drosselung auf höchstens fünf
// Meldungen je Sekunde, Prozent trotz Drosselung und der Adapter für den Index.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspWorkDoneProgressTests = class
  public
    [Test]
    procedure StartSendsCreateAndBegin;
    [Test]
    procedure ReportIsThrottled;
    [Test]
    procedure ReportWithoutPercentage;
    [Test]
    procedure FinishSendsEndOnce;
    [Test]
    procedure NothingBeforeStart;
    [Test]
    procedure IndexAdapterShowsFileNameOnly;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.WorkDoneProgress;

type
  /// <summary>Sammelt die geschriebenen Nachrichten als JSON-Text.</summary>
  TRecordingTransport = class(TInterfacedObject, IJsonRpcTransport)
  public
    Messages: TStringList;
    constructor Create;
    destructor Destroy; override;
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
  end;

constructor TRecordingTransport.Create;
begin
  inherited Create;
  Messages := TStringList.Create;
end;

destructor TRecordingTransport.Destroy;
begin
  Messages.Free;
  inherited;
end;

function TRecordingTransport.ReadMessage: TJSONObject;
begin
  raise EJsonRpcTransportClosed.Create('Keine Eingabe');
end;

procedure TRecordingTransport.WriteMessage(const AMessage: TJSONObject);
begin
  Messages.Add(AMessage.ToJSON);
end;

{ TLspWorkDoneProgressTests }

procedure TLspWorkDoneProgressTests.StartSendsCreateAndBegin;
var
  Transport: TRecordingTransport;
  Keep: IJsonRpcTransport;
  Progress: TLspWorkDoneProgress;
begin
  Transport := TRecordingTransport.Create;
  Keep := Transport;
  Progress := TLspWorkDoneProgress.Create(Keep, 'index');
  try
    Assert.IsFalse(Progress.Active);
    Progress.Start('Index aufbauen');
    Assert.IsTrue(Progress.Active);
    Assert.AreEqual(0, Progress.Percent);
    Assert.AreEqual(2, Transport.Messages.Count);
    Assert.Contains(Transport.Messages[0], '"method":"window/workDoneProgress/create"');
    Assert.Contains(Transport.Messages[0], '"id":"atlas/index"');
    Assert.Contains(Transport.Messages[0], '"token":"index"');
    Assert.Contains(Transport.Messages[1], '"method":"$/progress"');
    Assert.Contains(Transport.Messages[1], '"kind":"begin"');
    Assert.Contains(Transport.Messages[1], '"title":"Index aufbauen"');
    Assert.Contains(Transport.Messages[1], '"cancellable":false');
    Assert.Contains(Transport.Messages[1], '"percentage":0');
  finally
    Progress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.ReportIsThrottled;
var
  Transport: TRecordingTransport;
  Keep: IJsonRpcTransport;
  Progress: TLspWorkDoneProgress;
begin
  Transport := TRecordingTransport.Create;
  Keep := Transport;
  Progress := TLspWorkDoneProgress.Create(Keep, 't');
  try
    Progress.Start('Titel');
    // Direkt nach begin: gedrosselt, der Prozentwert gilt trotzdem (#647).
    Progress.Report('A.pas', 10);
    Assert.AreEqual(2, Transport.Messages.Count);
    Assert.AreEqual(10, Progress.Percent);
    Sleep(TLspWorkDoneProgress.MinReportIntervalMs + 50);
    Progress.Report('B.pas', 20);
    Assert.AreEqual(3, Transport.Messages.Count);
    Assert.Contains(Transport.Messages[2], '"kind":"report"');
    Assert.Contains(Transport.Messages[2], '"message":"B.pas"');
    Assert.Contains(Transport.Messages[2], '"percentage":20');
    // Gleich danach wieder gedrosselt.
    Progress.Report('C.pas', 30);
    Assert.AreEqual(3, Transport.Messages.Count);
    Assert.AreEqual(30, Progress.Percent);
  finally
    Progress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.ReportWithoutPercentage;
var
  Transport: TRecordingTransport;
  Keep: IJsonRpcTransport;
  Progress: TLspWorkDoneProgress;
begin
  Transport := TRecordingTransport.Create;
  Keep := Transport;
  Progress := TLspWorkDoneProgress.Create(Keep, 't');
  try
    Progress.Start('Titel');
    Progress.Report('', 40);
    Sleep(TLspWorkDoneProgress.MinReportIntervalMs + 50);
    Progress.Report('ohne Zahl', -1);
    Assert.AreEqual(3, Transport.Messages.Count);
    Assert.IsFalse(Pos('percentage', Transport.Messages[2]) > 0, Transport.Messages[2]);
    // Ohne Prozentangabe bleibt der letzte Wert.
    Assert.AreEqual(40, Progress.Percent);
  finally
    Progress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.FinishSendsEndOnce;
var
  Transport: TRecordingTransport;
  Keep: IJsonRpcTransport;
  Progress: TLspWorkDoneProgress;
begin
  Transport := TRecordingTransport.Create;
  Keep := Transport;
  Progress := TLspWorkDoneProgress.Create(Keep, 't');
  try
    Progress.Start('Titel');
    Progress.Finish('Fertig');
    Assert.IsFalse(Progress.Active);
    Assert.AreEqual(3, Transport.Messages.Count);
    Assert.Contains(Transport.Messages[2], '"kind":"end"');
    Assert.Contains(Transport.Messages[2], '"message":"Fertig"');
    Assert.IsFalse(Pos('percentage', Transport.Messages[2]) > 0, Transport.Messages[2]);
    Progress.Finish('Noch einmal');
    Assert.AreEqual(3, Transport.Messages.Count);
  finally
    Progress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.NothingBeforeStart;
var
  Transport: TRecordingTransport;
  Keep: IJsonRpcTransport;
  Progress: TLspWorkDoneProgress;
begin
  Transport := TRecordingTransport.Create;
  Keep := Transport;
  Progress := TLspWorkDoneProgress.Create(Keep, 't');
  try
    Progress.Report('A.pas', 50);
    Progress.Finish('Ende');
    Assert.AreEqual(0, Transport.Messages.Count);
    Assert.AreEqual(0, Progress.Percent);
  finally
    Progress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.IndexAdapterShowsFileNameOnly;
var
  Transport: TRecordingTransport;
  Keep: IJsonRpcTransport;
  Progress: TLspWorkDoneProgress;
  Event: TIndexProgressEvent;
begin
  Transport := TRecordingTransport.Create;
  Keep := Transport;
  Progress := TLspWorkDoneProgress.Create(Keep, 't');
  try
    Event := Progress.AsIndexProgress;
    Event(TIndexProgressKind.Started, 'Index', 0);
    Assert.IsTrue(Progress.Active);
    Sleep(TLspWorkDoneProgress.MinReportIntervalMs + 50);
    Event(TIndexProgressKind.Report, 'C:\Projekt\Quellen\Haupt.pas', 25);
    Assert.AreEqual(3, Transport.Messages.Count);
    Assert.Contains(Transport.Messages[2], '"message":"Haupt.pas"');
    Assert.IsFalse(Pos('Projekt', Transport.Messages[2]) > 0, 'Kein Pfad in der Meldung');
    Event(TIndexProgressKind.Finished, 'Fertig', 100);
    Assert.IsFalse(Progress.Active);
    Event := nil;
  finally
    Progress.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspWorkDoneProgressTests);

end.
