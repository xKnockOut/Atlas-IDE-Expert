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
    TDirectory.Delete(ExtractFileDir(FCacheFile), True);
  FCacheFile := '';
end;

procedure TIndexProcessesTests.TwoProcessesAreListed;
var
  Writer, Reader: TIndexProcessEntry;
  Items: TArray<TIndexProcessInfo>;
begin
  Writer := TIndexProcessEntry.Create(FCacheFile, Info(4711, TIndexProcessInfo.KindLsp));
  Reader := TIndexProcessEntry.Create(FCacheFile, Info(4712, TIndexProcessInfo.KindMcp));
  try
    Writer.Update(TIndexProcessInfo.StateBuilding, True, 'Cache-Sperre erhalten, Index wird aufgebaut');
    Reader.Update(TIndexProcessInfo.StateReading, False, 'Sperre belegt, lade Cache nur lesend');
    Items := TIndexProcesses.List(FCacheFile);
    Assert.AreEqual(2, Integer(Length(Items)));
    Assert.AreEqual(Cardinal(4711), Items[0].Pid);
    Assert.IsTrue(Items[0].Writer);
    Assert.AreEqual(TIndexProcessInfo.StateBuilding, Items[0].State);
    Assert.AreEqual('MCP', Items[1].Kind);
    Assert.AreEqual(TIndexProcessInfo.StateReading, Items[1].State);
    Assert.AreEqual('Kasse', Items[1].Workspace);
  finally
    Reader.Free;
    Writer.Free;
  end;
end;

procedure TIndexProcessesTests.UpdateKeepsLastEvents;
var
  Entry: TIndexProcessEntry;
  Index: Integer;
  Items: TArray<TIndexProcessInfo>;
begin
  Entry := TIndexProcessEntry.Create(FCacheFile, Info(1, TIndexProcessInfo.KindLsp));
  try
    for Index := 1 to TIndexProcessEntry.MaxEvents + 5 do
      Entry.Update('Ereignis ' + IntToStr(Index));
    Assert.AreEqual(TIndexProcessEntry.MaxEvents, Integer(Length(Entry.Info.Events)));
    Assert.AreEqual('Ereignis 6', Entry.Info.Events[0].Text);
    Items := TIndexProcesses.List(FCacheFile);
    Assert.AreEqual('Ereignis 25', Items[0].Events[High(Items[0].Events)].Text);
  finally
    Entry.Free;
  end;
end;

procedure TIndexProcessesTests.FreeRemovesEntry;
var
  Entry: TIndexProcessEntry;
  FileName: string;
begin
  Entry := TIndexProcessEntry.Create(FCacheFile, Info(7, TIndexProcessInfo.KindLsp));
  FileName := Entry.FileName;
  Assert.IsTrue(TFile.Exists(FileName));
  Entry.Free;
  Assert.IsFalse(TFile.Exists(FileName));
  Assert.AreEqual(0, Integer(Length(TIndexProcesses.List(FCacheFile))));
end;

procedure TIndexProcessesTests.OrphanFileIsRemoved;
var
  FileName: string;
  Json: string;
begin
  // Datei eines abgestürzten Prozesses: niemand hält sie offen.
  FileName := TPath.Combine(TIndexProcesses.FolderFor(FCacheFile), '99-0.json');
  ForceDirectories(ExtractFileDir(FileName));
  Json := '{"pid":99,"kind":"MCP","state":"bereit"}';
  TFile.WriteAllText(FileName, Json);
  Assert.AreEqual(0, Integer(Length(TIndexProcesses.List(FCacheFile))));
  Assert.IsFalse(TFile.Exists(FileName));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexProcessesTests);

end.
