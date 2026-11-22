unit Atlas.Common.Compiler.ProcessRuns.Tests;

// Tests für die gemeinsamen Teile der Prozessläufer: laufende Prozesse für Cancel
// verfolgen und die Ausgabe zeilenweise weiterreichen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerProcessRunsTests = class
  public
    [Test]
    procedure CancelStopsTrackedProcesses;
    [Test]
    procedure TrackAfterCancelRefuses;
    [Test]
    procedure EmitCompleteKeepsRest;
    [Test]
    procedure EmitDropsCarriageReturn;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.ProcessRuns;

type
  TStopped = class
  public
    Values: TArray<Integer>;
  end;

function StopInto(const AStopped: TStopped): TCompilerProcessStop<Integer>;
begin
  Result :=
    procedure(const AProcess: Integer)
    begin
      AStopped.Values := AStopped.Values + [AProcess];
    end;
end;

type
  TLines = class
  public
    Values: TArray<string>;
  end;

function LinesInto(const ALines: TLines): TCompilerLineEvent;
begin
  Result :=
    procedure(const ALine: string)
    begin
      ALines.Values := ALines.Values + [ALine];
    end;
end;

procedure TCompilerProcessRunsTests.CancelStopsTrackedProcesses;
var
  mList: TCompilerProcessList<Integer>;
  mStopped: TStopped;
begin
  mStopped := TStopped.Create;
  try
    mList := TCompilerProcessList<Integer>.Create;
    try
      Assert.IsTrue(mList.Track(1));
      Assert.IsTrue(mList.Track(2));
      Assert.IsTrue(mList.Track(3));
      mList.Untrack(2);
      Assert.IsFalse(mList.WasCancelled);
      mList.Cancel(StopInto(mStopped));
      Assert.IsTrue(mList.WasCancelled);
      Assert.AreEqual(2, Integer(Length(mStopped.Values)));
      Assert.AreEqual(1, mStopped.Values[0]);
      Assert.AreEqual(3, mStopped.Values[1]);
    finally
      mList.Free;
    end;
  finally
    mStopped.Free;
  end;
end;

procedure TCompilerProcessRunsTests.TrackAfterCancelRefuses;
var
  mList: TCompilerProcessList<Integer>;
  mStopped: TStopped;
begin
  mStopped := TStopped.Create;
  try
    mList := TCompilerProcessList<Integer>.Create;
    try
      mList.Cancel(StopInto(mStopped));
      Assert.IsFalse(mList.Track(7));
      mList.Cancel(StopInto(mStopped));
      Assert.AreEqual(0, Integer(Length(mStopped.Values)));
    finally
      mList.Free;
    end;
  finally
    mStopped.Free;
  end;
end;

procedure TCompilerProcessRunsTests.EmitCompleteKeepsRest;
var
  mPending: TBytes;
  mLines: TLines;
begin
  mLines := TLines.Create;
  try
    mPending := TEncoding.UTF8.GetBytes('eins'#13#10'zwei'#10'dr');
    TCompilerOutputLines.EmitComplete(mPending, TEncoding.UTF8, LinesInto(mLines));
    Assert.AreEqual(2, Integer(Length(mLines.Values)));
    Assert.AreEqual('eins', mLines.Values[0]);
    Assert.AreEqual('zwei', mLines.Values[1]);
    Assert.AreEqual('dr', TEncoding.UTF8.GetString(mPending));
  finally
    mLines.Free;
  end;
end;

procedure TCompilerProcessRunsTests.EmitDropsCarriageReturn;
var
  mBytes: TBytes;
  mLines: TLines;
begin
  mLines := TLines.Create;
  try
    mBytes := TEncoding.UTF8.GetBytes('xÄy'#13);
    TCompilerOutputLines.Emit(mBytes, 0, Length(mBytes), TEncoding.UTF8, LinesInto(mLines));
    Assert.AreEqual(1, Integer(Length(mLines.Values)));
    Assert.AreEqual('xÄy', mLines.Values[0]);
  finally
    mLines.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerProcessRunsTests);

end.
