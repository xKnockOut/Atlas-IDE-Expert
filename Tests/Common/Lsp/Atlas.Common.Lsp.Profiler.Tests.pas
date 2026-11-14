unit Atlas.Common.Lsp.Profiler.Tests;

// Tests der Befehle atlas.server.profilerStart, …Status und …Stop (#2057) mit einem Prober zum
// Testen: ohne Prober (außerhalb von Windows), Start, zweiter Start, Status, Stop schreibt die Datei, Ende des
// Programms vor Stop, fehlende Prozess-ID, Aufräumen auf die neuesten fünf.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Profiling.Contract,
  Atlas.Common.Lsp.Profiler;

type
  [TestFixture]
  TLspProfilerTests = class
  private
    FFolder: string;
    FSampler: IAtlasProfileSampler;
    FProfiler: TLspProfiler;
    /// <summary>Derselbe Prober wie FSampler, um das Ende des Programms vorzuspielen.</summary>
    FEnded: PBoolean;
    function Answer(const ACommand, AArguments: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WithoutSamplerFails;
    [Test]
    procedure StartStatusStopWritesProfile;
    [Test]
    procedure SecondStartAndStopWithoutRunFail;
    [Test]
    procedure EndedProgramIsWrittenByStatus;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.Commands,
  Atlas.Text.Profile;

type
  /// <summary>Prober zum Testen: liefert einen festen Lauf; Ended simuliert das Ende des Programms.</summary>
  TTestSampler = class(TInterfacedObject, IAtlasProfileSampler)
  public
    Started: Boolean;
    Ended: Boolean;
    function Start(AProcessId: Cardinal; AIntervalMs: Integer; out AError: string): Boolean;
    function Stop: TAtlasSampleRun;
    function Running: Boolean;
    function Samples: Integer;
    function MainFileName: string;
  end;

function TTestSampler.Start(AProcessId: Cardinal; AIntervalMs: Integer; out AError: string): Boolean;
begin
  AError := 'Zugriff verweigert';
  Result := AProcessId <> 666;
  Started := Result;
end;

function TTestSampler.Stop: TAtlasSampleRun;
begin
  Result := Default(TAtlasSampleRun);
  SetLength(Result.Modules, 1);
  Result.Modules[0].Base := $400000;
  Result.Modules[0].Size := $1000;
  Result.Modules[0].FileName := MainFileName;
  Result.MainModule := 0;
  SetLength(Result.Stacks, 1);
  Result.Stacks[0].Addresses := TArray<UInt64>.Create($400010);
  Result.Stacks[0].Count := 4;
  Result.DurationMs := 2000;
  Started := False;
end;

function TTestSampler.Running: Boolean;
begin
  Result := Started and not Ended;
end;

function TTestSampler.Samples: Integer;
begin
  Result := 4;
end;

function TTestSampler.MainFileName: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'AtlasProfilerTest.exe');
end;

{ TLspProfilerTests }

procedure TLspProfilerTests.Setup;
var
  mSampler: IAtlasProfileSampler;
  mTest: TTestSampler;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasProfilerTests-' + TGUID.NewGuid.ToString);
  mTest := TTestSampler.Create;
  FEnded := @mTest.Ended;
  FSampler := mTest;
  mSampler := FSampler;
  FProfiler := TLspProfiler.Create(
    function: IAtlasProfileSampler
    begin
      Result := mSampler;
    end, FFolder);
end;

procedure TLspProfilerTests.TearDown;
begin
  FreeAndNil(FProfiler);
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FEnded := nil;
  FSampler := nil;
  FFolder := '';
end;

function TLspProfilerTests.Answer(const ACommand, AArguments: string): string;
var
  mCommands: TLspCommands;
  mDispatcher: TJsonRpcDispatcher;
  mRequest, mResponse: TJSONObject;
  mValue: TJSONValue;
begin
  mCommands := TLspCommands.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    FProfiler.Register(mCommands);
    mCommands.Attach(mDispatcher);
    mRequest := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":1,"method":"' + TLspCommands.cMethod +
      '","params":{"command":"' + ACommand + '","arguments":[' + AArguments + ']}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
    finally
      mRequest.Free;
    end;
    try
      mValue := mResponse.GetValue('result');
      if mValue = nil then
      begin
        mValue := mResponse.GetValue('error');
      end;
      Result := mValue.ToJSON([]);
    finally
      mResponse.Free;
    end;
  finally
    mDispatcher.Free;
    mCommands.Free;
  end;
end;

procedure TLspProfilerTests.WithoutSamplerFails;
begin
  // Außerhalb von Windows liefert die Composition keinen Prober.
  FreeAndNil(FProfiler);
  FProfiler := TLspProfiler.Create(nil, FFolder);
  Assert.Contains(Answer(TLspProfiler.cStartCommand, '{"processId":42}'), 'Windows');
end;

procedure TLspProfilerTests.StartStatusStopWritesProfile;
var
  mAnswer, mFile: string;
  mProfile: TAtlasProfile;
begin
  mAnswer := Answer(TLspProfiler.cStartCommand, '{"processId":42,"intervalMs":5000,"program":"App",' +
    '"platform":"Win64","mapFile":"C:\\fehlt.map"}');
  Assert.AreEqual('{"started":true,"mapFile":"C:\\fehlt.map","routines":0}', mAnswer);
  Assert.Contains(Answer(TLspProfiler.cStatusCommand, '{}'), '"running":true,"processId":42,');
  mAnswer := Answer(TLspProfiler.cStopCommand, '{}');
  Assert.Contains(mAnswer, '"samples":4,"durationMs":2000');
  Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(FFolder, 'profile-*.json'))));
  mFile := TDirectory.GetFiles(FFolder, 'profile-*.json')[0];
  Assert.IsTrue(TAtlasProfileJson.TryParse(TFile.ReadAllText(mFile, TEncoding.UTF8), mProfile));
  Assert.AreEqual('App', mProfile.ProgramName);
  Assert.AreEqual('Win64', mProfile.Platform);
  // intervalMs wird auf 1..1000 begrenzt.
  Assert.AreEqual(TLspProfiler.cMaxIntervalMs, mProfile.IntervalMs);
  Assert.AreEqual(4, mProfile.Samples);
  Assert.AreEqual('[AtlasProfilerTest.exe]', mProfile.Frames[0].Routine);
  Assert.Contains(Answer(TLspProfiler.cStatusCommand, '{}'), '"running":false');
  Assert.Contains(Answer(TLspProfiler.cStatusCommand, '{}'), '"lastFile":"profile-');
end;

procedure TLspProfilerTests.SecondStartAndStopWithoutRunFail;
begin
  Assert.Contains(Answer(TLspProfiler.cStopCommand, '{}'), '"code":');
  Assert.Contains(Answer(TLspProfiler.cStartCommand, '{}'), 'processId');
  Assert.Contains(Answer(TLspProfiler.cStartCommand, '{"processId":666}'), 'Zugriff verweigert');
  Assert.Contains(Answer(TLspProfiler.cStartCommand, '{"processId":42}'), '"started":true');
  Assert.Contains(Answer(TLspProfiler.cStartCommand, '{"processId":43}'), '42');
  Answer(TLspProfiler.cStopCommand, '{}');
end;

procedure TLspProfilerTests.EndedProgramIsWrittenByStatus;
begin
  Answer(TLspProfiler.cStartCommand, '{"processId":42}');
  FEnded^ := True;
  Assert.Contains(Answer(TLspProfiler.cStatusCommand, '{}'), '"running":false');
  Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(FFolder, 'profile-*.json'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspProfilerTests);

end.
