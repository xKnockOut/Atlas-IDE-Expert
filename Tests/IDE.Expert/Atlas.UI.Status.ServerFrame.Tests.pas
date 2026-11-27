unit Atlas.UI.Status.ServerFrame.Tests;

// Fenster „Atlas-Server“ (#1356): Kopf je nach Stand (kein Server, wartet,
// älterer Server, Diagnose), Hinweis bei überschrittenem Budget, Zeilen der
// Tabellen, Doppelklick auf Unit und Regel, Knöpfe; Reiter „KI-Assistenten“ (#2611) mit Zeilen je Sitzung,
// auffälliger Fehlerquote und Hinweis ohne Assistenten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Plugin.Localization.Strings;

type
  [TestFixture]
  TAtlasServerFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure HeaderFollowsState;
    [Test]
    procedure TablesAndOverBudget;
    [Test]
    procedure DoubleClicksAndButtonsAreReported;
    [Test]
    procedure AssistantsTabShowsSessions;
  end;

implementation

uses
  Atlas.UI.Status.Strings,
  System.SysUtils,
  Vcl.Forms,
  Atlas.Plugin.Status.Server,
  Atlas.Text.McpStatistics,
  Atlas.Text.McpStatistics.TestSupport,
  Atlas.UI.Status.ServerFrame;

function Sample: TAtlasServerSnapshot;
var
  mUnit: TAtlasServerSlowUnit;
  mRule: TAtlasServerSlowRule;
  mRequest: TAtlasServerRequest;
begin
  Result := Default(TAtlasServerSnapshot);
  Result.Valid := True;
  Result.Known := True;
  Result.ProcessId := 4711;
  Result.Version := '1.2.0';
  Result.UptimeMs := 3900000;
  Result.State := TAtlasServerState.Ready;
  Result.Units := 12;
  Result.MemoryTotal := 500 * 1024 * 1024;
  Result.MemoryBudget := 400 * 1024 * 1024;
  Result.OverBudget := True;
  Result.CheckSerial := 1;
  Result.CheckUnits := 3;
  Result.CheckDurationMs := 1500;
  Result.IndexHitPercent := 90;
  Result.TreeHitPercent := -1;
  mUnit := Default(TAtlasServerSlowUnit);
  mUnit.Name := 'Haupt';
  mUnit.FileName := 'C:\P\Haupt.pas';
  mUnit.Ms := 120;
  Result.SlowUnits := [mUnit];
  mRule := Default(TAtlasServerSlowRule);
  mRule.Id := 'unused-uses';
  mRule.Ms := 80;
  mRule.Calls := 3;
  Result.SlowRules := [mRule];
  mRequest := Default(TAtlasServerRequest);
  mRequest.Method := 'textDocument/hover';
  mRequest.Count := 2;
  mRequest.MaxMs := 9;
  Result.Requests := [mRequest, mRequest];
end;

{ TAtlasServerFrameTests }

procedure TAtlasServerFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasServerFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasServerFrameTests.HeaderFollowsState;
var
  mHost: TForm;
  mFrame: TAtlasServerFrame;
  mSnapshot: TAtlasServerSnapshot;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasServerFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetSnapshot(Sample, False, 0);
    Assert.AreEqual(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowNoServer), mFrame.Header.Caption);
    Assert.IsFalse(mFrame.Buttons.RebuildButton.Enabled, 'ohne Server kein Neuaufbau');
    Assert.AreEqual(0, mFrame.Tables.Units.Items.Count, 'ohne Server leer');
    mFrame.SetSnapshot(Default(TAtlasServerSnapshot), True, 0);
    Assert.AreEqual(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowWaiting), mFrame.Header.Caption);
    mSnapshot := Sample;
    mSnapshot.Known := False;
    mFrame.SetSnapshot(mSnapshot, True, 0);
    Assert.AreEqual(TAtlasStatusStrings.Text(TAtlasStatusTextId.ServerWindowOldServer), mFrame.Header.Caption);
    mFrame.SetSnapshot(Sample, True, 2);
    Assert.IsTrue(string(mFrame.Header.Caption).Contains('4711'), mFrame.Header.Caption);
    Assert.IsTrue(string(mFrame.Header.Caption).Contains('1 h 05 min'), mFrame.Header.Caption);
    Assert.IsTrue(string(mFrame.Header.Caption).Contains('bereit'), mFrame.Header.Caption);
    Assert.IsTrue(string(mFrame.Header.Caption).EndsWith(': 2'), mFrame.Header.Caption);
    Assert.IsTrue(string(mFrame.QueueLine.Caption).Contains('90 %'), mFrame.QueueLine.Caption);
    Assert.IsTrue(string(mFrame.CheckRunLine.Caption).Contains('3 Units'), mFrame.CheckRunLine.Caption);
    Assert.IsTrue(mFrame.Buttons.RebuildButton.Enabled);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasServerFrameTests.TablesAndOverBudget;
var
  mHost: TForm;
  mFrame: TAtlasServerFrame;
  mSnapshot: TAtlasServerSnapshot;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasServerFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetSnapshot(Sample, True, 0);
    Assert.AreEqual(1, mFrame.Tables.Units.Items.Count);
    Assert.AreEqual(1, mFrame.Tables.Rules.Items.Count);
    Assert.AreEqual(2, mFrame.Tables.Requests.Items.Count);
    Assert.AreEqual('Haupt', mFrame.Tables.Units.Items[0].Caption);
    Assert.AreEqual('unused-uses', mFrame.Tables.Rules.Items[0].Caption);
    Assert.AreEqual('3', mFrame.Tables.Rules.Items[0].SubItems[1]);
    Assert.IsTrue(mFrame.OverBudget.Visible, 'Budget überschritten');
    mSnapshot := Sample;
    mSnapshot.OverBudget := False;
    mFrame.SetSnapshot(mSnapshot, True, 0);
    Assert.IsFalse(mFrame.OverBudget.Visible);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasServerFrameTests.DoubleClicksAndButtonsAreReported;
var
  mHost: TForm;
  mFrame: TAtlasServerFrame;
  mOpenedUnit, mOpenedRule: string;
  mRefreshed, mRebuilt, mPacked: Integer;
begin
  mOpenedUnit := '';
  mOpenedRule := '';
  mRefreshed := 0;
  mRebuilt := 0;
  mPacked := 0;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasServerFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Tables.OnOpenUnit :=
      procedure(AUnit: TAtlasServerSlowUnit)
      begin
        mOpenedUnit := AUnit.FileName;
      end;
    mFrame.Tables.OnOpenRule :=
      procedure(ARule: string)
      begin
        mOpenedRule := ARule;
      end;
    mFrame.Buttons.OnRefresh :=
      procedure
      begin
        Inc(mRefreshed);
      end;
    mFrame.Buttons.OnRebuild :=
      procedure
      begin
        Inc(mRebuilt);
      end;
    mFrame.Buttons.OnPackage :=
      procedure
      begin
        Inc(mPacked);
      end;
    mFrame.SetSnapshot(Sample, True, 0);
    mFrame.Tables.OpenUnit(0);
    mFrame.Tables.OpenRule(0);
    mFrame.Tables.OpenUnit(5);
    Assert.AreEqual('C:\P\Haupt.pas', mOpenedUnit);
    Assert.AreEqual('unused-uses', mOpenedRule);
    mFrame.Buttons.RefreshButton.Click;
    mFrame.Buttons.RebuildButton.Click;
    mFrame.Buttons.PackageButton.Click;
    Assert.AreEqual(1, mRefreshed);
    Assert.AreEqual(1, mRebuilt);
    Assert.AreEqual(1, mPacked);
  finally
    mHost.Free;
  end;
  mOpenedUnit := '';
  mOpenedRule := '';
end;

/// <summary>Sitzung des Clients „Assistent A“ (pid 4711) mit check_code (6 Aufrufe, 2 Fehler) und find_symbol.
/// </summary>
function AssistantSession: TMcpAssistantSession;
begin
  Result := Default(TMcpAssistantSession);
  Result.Pid := 4711;
  Result.HasStatistics := True;
  Result.Statistics.Client := 'Assistent A';
  Result.Statistics.Calls := TArray<TMcpCallSummary>.Create(TMcpStatisticsTestSupport.Called('check_code', 6, 2),
    TMcpStatisticsTestSupport.Called('find_symbol', 10, 0));
end;

procedure TAtlasServerFrameTests.AssistantsTabShowsSessions;
var
  mHost: TForm;
  mFrame: TAtlasServerFrame;
  mCells: TArray<string>;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasServerFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.SetAssistants(nil);
    Assert.IsTrue(string(mFrame.Assistants.Summary.Caption).StartsWith('Kein KI-Assistent'),
      mFrame.Assistants.Summary.Caption);
    Assert.AreEqual(0, mFrame.Assistants.List.Items.Count);
    mFrame.SetAssistants(TArray<TMcpAssistantSession>.Create(AssistantSession));
    Assert.AreEqual(2, mFrame.Assistants.List.Items.Count);
    mCells := mFrame.Assistants.Cells(0);
    Assert.AreEqual('Assistent A (4711)', mCells[0]);
    Assert.AreEqual('check_code', mCells[1]);
    Assert.AreEqual('2 (33 %)', mCells[1 + Ord(TMcpCallColumn.Errors)]);
    Assert.IsTrue(mFrame.Assistants.Conspicuous(0), '33 % bei 6 Aufrufen');
    Assert.IsFalse(mFrame.Assistants.Conspicuous(1));
    Assert.IsTrue(string(mFrame.Assistants.Summary.Caption).Contains('(Prozess 4711)'),
      mFrame.Assistants.Summary.Caption);
    Assert.IsTrue(string(mFrame.Assistants.Summary.Caption).Contains('rot): 1'), mFrame.Assistants.Summary.Caption);
    Assert.AreEqual(2, mFrame.Pages.PageCount, 'Reiter Server und KI-Assistenten');
  finally
    mHost.Free;
  end;
  mCells := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasServerFrameTests);

end.
