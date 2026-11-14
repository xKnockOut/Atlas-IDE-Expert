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
  System.Generics.Collections,
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
  mTransport: TRecordingTransport;
  mKeep: IJsonRpcTransport;
  mProgress: TLspWorkDoneProgress;
begin
  mTransport := TRecordingTransport.Create;
  mKeep := mTransport;
  mProgress := TLspWorkDoneProgress.Create(mKeep, 'index');
  try
    Assert.IsFalse(mProgress.Active);
    mProgress.Start('Index aufbauen');
    Assert.IsTrue(mProgress.Active);
    Assert.AreEqual(0, mProgress.Percent);
    Assert.AreEqual(2, Integer(mTransport.Messages.Count));
    Assert.Contains(mTransport.Messages[0], '"method":"window/workDoneProgress/create"');
    Assert.Contains(mTransport.Messages[0], '"id":"atlas/index"');
    Assert.Contains(mTransport.Messages[0], '"token":"index"');
    Assert.Contains(mTransport.Messages[1], '"method":"$/progress"');
    Assert.Contains(mTransport.Messages[1], '"kind":"begin"');
    Assert.Contains(mTransport.Messages[1], '"title":"Index aufbauen"');
    Assert.Contains(mTransport.Messages[1], '"cancellable":false');
    Assert.Contains(mTransport.Messages[1], '"percentage":0');
  finally
    mProgress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.ReportIsThrottled;
var
  mTransport: TRecordingTransport;
  mKeep: IJsonRpcTransport;
  mProgress: TLspWorkDoneProgress;
begin
  mTransport := TRecordingTransport.Create;
  mKeep := mTransport;
  mProgress := TLspWorkDoneProgress.Create(mKeep, 't');
  try
    mProgress.Start('Titel');
    // Direkt nach begin: gedrosselt, der Prozentwert gilt trotzdem (#647).
    mProgress.Report('A.pas', 10);
    Assert.AreEqual(2, Integer(mTransport.Messages.Count));
    Assert.AreEqual(10, mProgress.Percent);
    Sleep(TLspWorkDoneProgress.cMinReportIntervalMs + 50);
    mProgress.Report('B.pas', 20);
    Assert.AreEqual(3, Integer(mTransport.Messages.Count));
    Assert.Contains(mTransport.Messages[2], '"kind":"report"');
    Assert.Contains(mTransport.Messages[2], '"message":"B.pas"');
    Assert.Contains(mTransport.Messages[2], '"percentage":20');
    // Gleich danach wieder gedrosselt.
    mProgress.Report('C.pas', 30);
    Assert.AreEqual(3, Integer(mTransport.Messages.Count));
    Assert.AreEqual(30, mProgress.Percent);
  finally
    mProgress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.ReportWithoutPercentage;
var
  mTransport: TRecordingTransport;
  mKeep: IJsonRpcTransport;
  mProgress: TLspWorkDoneProgress;
begin
  mTransport := TRecordingTransport.Create;
  mKeep := mTransport;
  mProgress := TLspWorkDoneProgress.Create(mKeep, 't');
  try
    mProgress.Start('Titel');
    mProgress.Report('', 40);
    Sleep(TLspWorkDoneProgress.cMinReportIntervalMs + 50);
    mProgress.Report('ohne Zahl', -1);
    Assert.AreEqual(3, Integer(mTransport.Messages.Count));
    Assert.IsFalse(Pos('percentage', mTransport.Messages[2]) > 0, mTransport.Messages[2]);
    // Ohne Prozentangabe bleibt der letzte Wert.
    Assert.AreEqual(40, mProgress.Percent);
  finally
    mProgress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.FinishSendsEndOnce;
var
  mTransport: TRecordingTransport;
  mKeep: IJsonRpcTransport;
  mProgress: TLspWorkDoneProgress;
begin
  mTransport := TRecordingTransport.Create;
  mKeep := mTransport;
  mProgress := TLspWorkDoneProgress.Create(mKeep, 't');
  try
    mProgress.Start('Titel');
    mProgress.Finish('Fertig');
    Assert.IsFalse(mProgress.Active);
    Assert.AreEqual(3, Integer(mTransport.Messages.Count));
    Assert.Contains(mTransport.Messages[2], '"kind":"end"');
    Assert.Contains(mTransport.Messages[2], '"message":"Fertig"');
    Assert.IsFalse(Pos('percentage', mTransport.Messages[2]) > 0, mTransport.Messages[2]);
    mProgress.Finish('Noch einmal');
    Assert.AreEqual(3, Integer(mTransport.Messages.Count));
  finally
    mProgress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.NothingBeforeStart;
var
  mTransport: TRecordingTransport;
  mKeep: IJsonRpcTransport;
  mProgress: TLspWorkDoneProgress;
begin
  mTransport := TRecordingTransport.Create;
  mKeep := mTransport;
  mProgress := TLspWorkDoneProgress.Create(mKeep, 't');
  try
    mProgress.Report('A.pas', 50);
    mProgress.Finish('Ende');
    Assert.AreEqual(0, Integer(mTransport.Messages.Count));
    Assert.AreEqual(0, mProgress.Percent);
  finally
    mProgress.Free;
  end;
end;

procedure TLspWorkDoneProgressTests.IndexAdapterShowsFileNameOnly;
var
  mTransport: TRecordingTransport;
  mKeep: IJsonRpcTransport;
  mProgress: TLspWorkDoneProgress;
  mEvent: TIndexProgressEvent;
begin
  mTransport := TRecordingTransport.Create;
  mKeep := mTransport;
  mProgress := TLspWorkDoneProgress.Create(mKeep, 't');
  try
    mEvent := mProgress.AsIndexProgress();
    mEvent(TIndexProgressKind.Started, 'Index', 0);
    Assert.IsTrue(mProgress.Active);
    Sleep(TLspWorkDoneProgress.cMinReportIntervalMs + 50);
    mEvent(TIndexProgressKind.Report, 'C:\Projekt\Quellen\Haupt.pas', 25);
    Assert.AreEqual(3, Integer(mTransport.Messages.Count));
    Assert.Contains(mTransport.Messages[2], '"message":"Haupt.pas"');
    Assert.IsFalse(Pos('Projekt', mTransport.Messages[2]) > 0, 'Kein Pfad in der Meldung');
    mEvent(TIndexProgressKind.Finished, 'Fertig', 100);
    Assert.IsFalse(mProgress.Active);
    mEvent := nil;
  finally
    mProgress.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspWorkDoneProgressTests);

end.
