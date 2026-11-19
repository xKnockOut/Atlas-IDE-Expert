unit Atlas.Common.History.Report.Tests;

// Tests der Antwort von get_symbol_history (#2641): Zeilen je Commit, Umbenennen und Verschieben, Issues, erreichte
// Grenze und JSON.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.History.Contract;

type
  [TestFixture]
  TSymbolHistoryReportTests = class
  private
    function Sample: TSymbolHistoryResult;
  public
    [Test]
    procedure MarkdownHasOneLinePerCommit;
    [Test]
    procedure MarkdownNamesLimit;
    [Test]
    procedure JsonHasEventsAndStop;
    [Test]
    procedure UnitOfPathDropsFolderAndExtension;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.History.Report;

function Event(AKind: TSymbolEventKind; const ARevision, ASymbol, APath: string): TSymbolEvent;
begin
  Result := Default(TSymbolEvent);
  Result.Kind := AKind;
  Result.Revision := ARevision;
  Result.Author := 'anna';
  Result.Date := EncodeDateTime(2026, 11, 7, 10, 0, 0, 0);
  Result.Summary := 'Nachricht ' + ARevision;
  Result.Added := 4;
  Result.Deleted := 1;
  Result.Symbol := ASymbol;
  Result.Path := APath;
end;

function TSymbolHistoryReportTests.Sample: TSymbolHistoryResult;
begin
  Result := Default(TSymbolHistoryResult);
  Result.Symbol := 'TRun.Cancel';
  Result.Path := 'Src/Run.pas';
  Result.Kind := THotspotVcsKind.Git;
  Result.Head := '0123456789abcdef';
  Result.FollowedMoves := True;
  Result.Events := [Event(TSymbolEventKind.Changed, 'bab7c0c8ff', 'TRun.Cancel', 'Src/Run.pas'),
    Event(TSymbolEventKind.Renamed, '41aa02f1ff', 'TRun.Cancel', 'Src/Run.pas'),
    Event(TSymbolEventKind.Moved, '9c12d7e0ff', 'TRun.Abort', 'Src/Run.pas'),
    Event(TSymbolEventKind.Introduced, '1f0e3a22ff', 'TRun.Abort', 'Src/Runner.pas')];
  Result.Events[0].Issues := ['#2504'];
  Result.Events[1].FromSymbol := 'TRun.Abort';
  Result.Events[1].FromPath := 'Src/Run.pas';
  Result.Events[1].Similarity := 0.97;
  Result.Events[2].FromSymbol := 'TRun.Abort';
  Result.Events[2].FromPath := 'Src/Runner.pas';
  Result.Events[2].Similarity := 1;
  Result.Events[3].Issues := ['#1776', '#2504'];
end;

procedure TSymbolHistoryReportTests.MarkdownHasOneLinePerCommit;
var
  mText: string;
begin
  mText := TSymbolHistoryReport.Markdown(Sample, 20, 0);
  Assert.Contains(mText, 'TRun.Cancel – 4 Änderungen (git, Stand 01234567)');
  Assert.Contains(mText, '2026-11-07  bab7c0c8  geändert (+4 −1)  anna  Nachricht bab7c0c8ff');
  Assert.Contains(mText, '41aa02f1  umbenannt aus TRun.Abort (+4 −1)');
  Assert.Contains(mText, '9c12d7e0  verschoben aus Runner nach Run (+4 −1)');
  Assert.Contains(mText, '1f0e3a22  eingeführt (+4 −1)');
  Assert.Contains(mText, 'Issues: #2504, #1776');
  Assert.DoesNotContain(mText, 'Grenze');
end;

procedure TSymbolHistoryReportTests.MarkdownNamesLimit;
var
  mResult: TSymbolHistoryResult;
begin
  mResult := Sample;
  mResult.Stop := TSymbolHistoryStop.Limit;
  Assert.Contains(TSymbolHistoryReport.Markdown(mResult, 4, 0), 'höchstens 4 Einträge (limit)');
  mResult.Stop := TSymbolHistoryStop.TimeLimit;
  Assert.Contains(TSymbolHistoryReport.Markdown(mResult, 4, 10000), 'Zeitlimit von 10000 ms');
end;

procedure TSymbolHistoryReportTests.JsonHasEventsAndStop;
var
  mRoot: TJSONObject;
  mEvents: TJSONArray;
  mResult: TSymbolHistoryResult;
begin
  mResult := Sample;
  mResult.Stop := TSymbolHistoryStop.Cancelled;
  mRoot := TJSONObject.ParseJSONValue(TSymbolHistoryReport.Json(mResult, 20)) as TJSONObject;
  try
    Assert.AreEqual('json', mRoot.GetValue<string>('format'));
    Assert.AreEqual(4, mRoot.GetValue<Integer>('count'));
    Assert.IsFalse(mRoot.GetValue<Boolean>('complete'));
    Assert.AreEqual('cancelled', mRoot.GetValue<string>('stop'));
    mEvents := mRoot.GetValue('events') as TJSONArray;
    Assert.AreEqual('renamed', (mEvents.Items[1] as TJSONObject).GetValue<string>('kind'));
    Assert.AreEqual('TRun.Abort', (mEvents.Items[1] as TJSONObject).GetValue<string>('fromSymbol'));
    Assert.AreEqual('2026-11-07T10:00:00Z', (mEvents.Items[0] as TJSONObject).GetValue<string>('date'));
    Assert.IsNull((mEvents.Items[0] as TJSONObject).GetValue('fromSymbol'), 'nur bei renamed und moved');
  finally
    mRoot.Free;
  end;
end;

procedure TSymbolHistoryReportTests.UnitOfPathDropsFolderAndExtension;
begin
  Assert.AreEqual('Atlas.IDE.Tests.Run', TSymbolHistoryReport.UnitOfPath('Packages/X/Atlas.IDE.Tests.Run.pas'));
  Assert.AreEqual('Foo', TSymbolHistoryReport.UnitOfPath('Foo.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TSymbolHistoryReportTests);

end.
