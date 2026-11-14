unit Atlas.Common.Index.Adapters.Processes.Tests;

// Tests der Prozesse am Index-Cache (#62): Anmelden, Zustand und Ereignisse,
// Abmelden, verwaiste Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexProcessesTests = class
  private
    FCacheFile: string;
  public
    /// <summary>Erstgebrauch (TMonitor, Sortierung, JSON, Dateien) vor der Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TwoProcessesAreListed;
    [Test]
    procedure UpdateKeepsLastEvents;
    [Test]
    procedure FreeRemovesEntry;
    [Test]
    procedure OrphanFileIsRemoved;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Index.Processes,
  Atlas.Common.Index.Adapters.Processes;

function Info(APid: Cardinal; const AKind: string): TIndexProcessInfo;
begin
  Result := Default(TIndexProcessInfo);
  Result.Pid := APid;
  Result.Kind := AKind;
  Result.Client := 'Claude Code';
  Result.Workspace := 'Kasse';
end;

{ TIndexProcessesTests }

procedure TIndexProcessesTests.WarmUpFirstUse;
begin
  Setup;
  try
    TwoProcessesAreListed;
  finally
    TearDown;
  end;
end;

procedure TIndexProcessesTests.Setup;
begin
  FCacheFile := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'AtlasProzesseTest' + IntToStr(Random(100000))),
    'index.atlasidx');
end;

procedure TIndexProcessesTests.TearDown;
begin
  if TDirectory.Exists(ExtractFileDir(FCacheFile)) then
  begin
    TDirectory.Delete(ExtractFileDir(FCacheFile), True);
  end;
  FCacheFile := '';
end;

procedure TIndexProcessesTests.TwoProcessesAreListed;
var
  mWriter, mReader: TIndexProcessEntry;
  mItems: TArray<TIndexProcessInfo>;
begin
  mWriter := TIndexProcessEntry.Create(FCacheFile, Info(4711, TIndexProcessInfo.cKindLsp));
  mReader := TIndexProcessEntry.Create(FCacheFile, Info(4712, TIndexProcessInfo.cKindMcp));
  try
    mWriter.Update(TIndexProcessInfo.cStateBuilding, True, 'Cache-Sperre erhalten, Index wird aufgebaut');
    mReader.Update(TIndexProcessInfo.cStateReading, False, 'Sperre belegt, lade Cache nur lesend');
    mItems := TIndexProcesses.List(FCacheFile);
    Assert.AreEqual(2, Integer(Length(mItems)));
    Assert.AreEqual(Cardinal(4711), mItems[0].Pid);
    Assert.IsTrue(mItems[0].Writer);
    Assert.AreEqual(TIndexProcessInfo.cStateBuilding, mItems[0].State);
    Assert.AreEqual('MCP', mItems[1].Kind);
    Assert.AreEqual(TIndexProcessInfo.cStateReading, mItems[1].State);
    Assert.AreEqual('Kasse', mItems[1].Workspace);
  finally
    mReader.Free;
    mWriter.Free;
  end;
end;

procedure TIndexProcessesTests.UpdateKeepsLastEvents;
var
  mEntry: TIndexProcessEntry;
  mIndex: Integer;
  mItems: TArray<TIndexProcessInfo>;
begin
  mEntry := TIndexProcessEntry.Create(FCacheFile, Info(1, TIndexProcessInfo.cKindLsp));
  try
    for mIndex := 1 to TIndexProcessEntry.cMaxEvents + 5 do
    begin
      mEntry.Update('Ereignis ' + IntToStr(mIndex));
    end;
    Assert.AreEqual(TIndexProcessEntry.cMaxEvents, Integer(Length(mEntry.Info.Events)));
    Assert.AreEqual('Ereignis 6', mEntry.Info.Events[0].Text);
    mItems := TIndexProcesses.List(FCacheFile);
    Assert.AreEqual('Ereignis 25', mItems[0].Events[High(mItems[0].Events)].Text);
  finally
    mEntry.Free;
  end;
end;

procedure TIndexProcessesTests.FreeRemovesEntry;
var
  mEntry: TIndexProcessEntry;
  mFileName: string;
begin
  mEntry := TIndexProcessEntry.Create(FCacheFile, Info(7, TIndexProcessInfo.cKindLsp));
  mFileName := mEntry.FileName;
  Assert.IsTrue(TFile.Exists(mFileName));
  mEntry.Free;
  Assert.IsFalse(TFile.Exists(mFileName));
  Assert.AreEqual(0, Integer(Length(TIndexProcesses.List(FCacheFile))));
end;

procedure TIndexProcessesTests.OrphanFileIsRemoved;
var
  mFileName: string;
  mJson: string;
begin
  // Datei eines abgestürzten Prozesses: niemand hält sie offen.
  mFileName := TPath.Combine(TIndexProcesses.FolderFor(FCacheFile), '99-0.json');
  ForceDirectories(ExtractFileDir(mFileName));
  mJson := '{"pid":99,"kind":"MCP","state":"bereit"}';
  TFile.WriteAllText(mFileName, mJson);
  Assert.AreEqual(0, Integer(Length(TIndexProcesses.List(FCacheFile))));
  Assert.IsFalse(TFile.Exists(mFileName));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexProcessesTests);

end.
