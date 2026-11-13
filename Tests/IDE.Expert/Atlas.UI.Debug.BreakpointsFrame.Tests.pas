unit Atlas.UI.Debug.BreakpointsFrame.Tests;

// Haltepunktfenster (#863), Oberfläche: Zellen und Gruppenüberschriften, Liste
// mit Suche, Chips und Gruppen, Auswahl über SetRows hinweg, Befehle melden die
// gewählten Haltepunkte (ohne Doppel bei zwei Etiketten), Spalten ein- und
// ausblenden.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugBreakpointsFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Einmal-Belegungen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CellTexts;
    [Test]
    procedure GroupCaptionsAndSummary;
    [Test]
    procedure RuleTexts;
    [Test]
    procedure ListFollowsSearchChipsAndGrouping;
    [Test]
    procedure SelectionSurvivesSetRows;
    [Test]
    procedure CommandsReportSelectedRows;
    [Test]
    procedure ColumnsHideAndShow;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Debug.BreakpointList,
  Atlas.Core.Debug.BreakpointRules,
  Atlas.UI.Debug.BreakpointsFrame;

type
  TCommandLog = class
  public
    Rows: TArray<TAtlasBreakpointRow>;
    Enable: Boolean;
    Tag: string;
    Add: Boolean;
    Count: Integer;
  end;

function Rows: TArray<TAtlasBreakpointRow>;
var
  mRow: TAtlasBreakpointRow;
begin
  Result := nil;
  mRow := TAtlasBreakpointRow.Create('C:\App\Kunde.pas', 42);
  mRow.Method := 'TKunde.Speichern';
  mRow.Tags := TArray<string>.Create('Import', 'Bug 4711');
  mRow.Hits := 3;
  Result := Result + [mRow];
  mRow := TAtlasBreakpointRow.Create('C:\App\Import.pas', 10);
  mRow.Condition := 'Zeile > 100';
  mRow.Enabled := False;
  Result := Result + [mRow];
end;

function WatchToggle(ALog: TCommandLog): TAtlasBreakpointToggleEvent;
begin
  Result :=
    procedure(const ARows: TArray<TAtlasBreakpointRow>; AEnable: Boolean)
    begin
      Inc(ALog.Count);
      ALog.Rows := Copy(ARows);
      ALog.Enable := AEnable;
    end;
end;

function WatchTag(ALog: TCommandLog): TAtlasBreakpointTagEvent;
begin
  Result :=
    procedure(const ARows: TArray<TAtlasBreakpointRow>; const ATag: string; AAdd: Boolean)
    begin
      Inc(ALog.Count);
      ALog.Rows := Copy(ARows);
      ALog.Tag := ATag;
      ALog.Add := AAdd;
    end;
end;

{ TAtlasDebugBreakpointsFrameTests }

procedure TAtlasDebugBreakpointsFrameTests.WarmUpFirstUse;
begin
  Setup;
  try
    ListFollowsSearchChipsAndGrouping;
  finally
    TearDown;
  end;
end;

procedure TAtlasDebugBreakpointsFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugBreakpointsFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugBreakpointsFrameTests.CellTexts;
var
  mRows: TArray<TAtlasBreakpointRow>;
begin
  mRows := Rows;
  Assert.AreEqual('✓', TAtlasBreakpointTexts.Cell(mRows[0], TAtlasBreakpointColumn.Enabled, True));
  Assert.AreEqual('–', TAtlasBreakpointTexts.Cell(mRows[1], TAtlasBreakpointColumn.Enabled, True));
  Assert.AreEqual('Kunde · TKunde.Speichern · 42',
    TAtlasBreakpointTexts.Cell(mRows[0], TAtlasBreakpointColumn.Location, True));
  Assert.AreEqual('Import, Bug 4711', TAtlasBreakpointTexts.Cell(mRows[0], TAtlasBreakpointColumn.Tags, True));
  Assert.AreEqual('3', TAtlasBreakpointTexts.Cell(mRows[0], TAtlasBreakpointColumn.Hits, True));
  Assert.AreEqual('', TAtlasBreakpointTexts.Cell(mRows[0], TAtlasBreakpointColumn.Hits, False), 'vor einer Sitzung');
  Assert.AreEqual('', TAtlasBreakpointTexts.Cell(mRows[0], TAtlasBreakpointColumn.PassCount, True), 'ohne');
  Assert.AreEqual('Treffer', TAtlasBreakpointTexts.ColumnCaption(TAtlasBreakpointColumn.Hits));
  mRows := nil;
end;

procedure TAtlasDebugBreakpointsFrameTests.GroupCaptionsAndSummary;
begin
  Assert.AreEqual('Import (2)', TAtlasBreakpointTexts.GroupCaption('Import', TAtlasBreakpointGrouping.ByTag, 2));
  Assert.AreEqual('(ohne Etikett) (1)', TAtlasBreakpointTexts.GroupCaption('', TAtlasBreakpointGrouping.ByTag, 1));
  Assert.AreEqual('(ohne Gruppe) (1)', TAtlasBreakpointTexts.GroupCaption('', TAtlasBreakpointGrouping.ByGroup, 1));
  Assert.AreEqual('1 von 2 Haltepunkten', TAtlasBreakpointTexts.Summary(1, 2, True));
  Assert.IsTrue(TAtlasBreakpointTexts.Summary(1, 2, False).Contains('nächsten Debug-Sitzung'));
end;

procedure TAtlasDebugBreakpointsFrameTests.RuleTexts;
var
  mRule: TAtlasBreakpointRule;
  mRow: TAtlasBreakpointRow;
begin
  mRule := Default(TAtlasBreakpointRule);
  Assert.AreEqual('', TAtlasBreakpointTexts.RuleText(mRule, 'Kunde.pas:42'), 'ohne Regel');
  mRule.Hit := TAtlasHitMode.AtLeast;
  mRule.HitCount := 3;
  mRule.Thread := TAtlasThreadFilter.MainThread;
  mRule.Depend := TAtlasDependMode.Once;
  mRule.TriggerFile := 'C:\App\Kunde.pas';
  mRule.TriggerLine := 41;
  Assert.AreEqual('ab 3. Treffer · Hauptthread · einmal nach Kunde.pas:42',
    TAtlasBreakpointTexts.RuleText(mRule, 'Kunde.pas:42'));
  mRule := Default(TAtlasBreakpointRule);
  mRule.Thread := TAtlasThreadFilter.NameContains;
  mRule.ThreadText := 'Import';
  Assert.AreEqual('Thread „Import“', TAtlasBreakpointTexts.RuleText(mRule, ''));
  mRow := TAtlasBreakpointRow.Create('C:\App\Kunde.pas', 42);
  mRow.Rules := 'Hauptthread';
  Assert.AreEqual('Hauptthread', TAtlasBreakpointTexts.Cell(mRow, TAtlasBreakpointColumn.Rules, True));
  Assert.AreEqual('Regeln', TAtlasBreakpointTexts.ColumnCaption(TAtlasBreakpointColumn.Rules));
  mRule := Default(TAtlasBreakpointRule);
  mRow := Default(TAtlasBreakpointRow);
end;

procedure TAtlasDebugBreakpointsFrameTests.ListFollowsSearchChipsAndGrouping;
var
  mHost: TForm;
  mFrame: TAtlasDebugBreakpointsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugBreakpointsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.SetRows(Rows, True);
    Assert.AreEqual(2, mFrame.List.Items.Count);
    mFrame.Search.Text := 'speich';
    Assert.AreEqual(1, mFrame.List.Items.Count);
    mFrame.Search.Text := '';
    mFrame.SetChip(TAtlasBreakpointFilter.Active, True);
    Assert.AreEqual(1, mFrame.List.Items.Count, 'nur eingeschaltete');
    mFrame.SetChip(TAtlasBreakpointFilter.Active, False);
    mFrame.SetGrouping(TAtlasBreakpointGrouping.ByTag);
    Assert.IsTrue(mFrame.List.GroupView);
    Assert.AreEqual(3, mFrame.List.Groups.Count, 'Bug 4711, Import, ohne Etikett');
    Assert.AreEqual(3, mFrame.List.Items.Count, 'Kunde steht in zwei Gruppen');
    mFrame.SetGrouping(TAtlasBreakpointGrouping.None);
    Assert.IsFalse(mFrame.List.GroupView);
    Assert.AreEqual('2 von 2 Haltepunkten', mFrame.SummaryLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugBreakpointsFrameTests.SelectionSurvivesSetRows;
var
  mHost: TForm;
  mFrame: TAtlasDebugBreakpointsFrame;
  mRows: TArray<TAtlasBreakpointRow>;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugBreakpointsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.SetRows(Rows, True);
    // Sortiert: Import.pas vor Kunde.pas.
    mFrame.List.Items[1].Selected := True;
    mRows := Rows;
    mRows[0].Hits := 4;
    mFrame.SetRows(mRows, True);
    Assert.AreEqual(1, Integer(Length(mFrame.SelectedRows)));
    Assert.AreEqual(42, mFrame.SelectedRows[0].Line);
    Assert.AreEqual(4, mFrame.SelectedRows[0].Hits, 'neuer Stand');
    mFrame.SetRows(Copy(mRows, 1, 1), True);
    Assert.AreEqual(0, Integer(Length(mFrame.SelectedRows)), 'gelöscht: keine Auswahl');
  finally
    mHost.Free;
  end;
  mRows := nil;
end;

procedure TAtlasDebugBreakpointsFrameTests.CommandsReportSelectedRows;
var
  mHost: TForm;
  mFrame: TAtlasDebugBreakpointsFrame;
  mLog: TCommandLog;
  mIndex: Integer;
begin
  mLog := TCommandLog.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugBreakpointsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.Events.OnToggle := WatchToggle(mLog);
    mFrame.SetRows(Rows, True);
    mFrame.SetGrouping(TAtlasBreakpointGrouping.ByTag);
    for mIndex := 0 to mFrame.List.Items.Count - 1 do
    begin
      mFrame.List.Items[mIndex].Selected := True;
    end;
    Assert.AreEqual(2, Integer(Length(mFrame.SelectedRows)), 'Kunde nur einmal');
    mFrame.Events.OnTag := WatchTag(mLog);
    mFrame.TagBox.Text := ' Import ';
    mFrame.TagSelected(True);
    Assert.AreEqual(1, mLog.Count);
    Assert.AreEqual('Import', mLog.Tag);
    Assert.IsTrue(mLog.Add);
    Assert.AreEqual(2, Integer(Length(mLog.Rows)));
  finally
    mHost.Free;
    mLog.Free;
  end;
end;

procedure TAtlasDebugBreakpointsFrameTests.ColumnsHideAndShow;
var
  mHost: TForm;
  mFrame: TAtlasDebugBreakpointsFrame;
  mColumns: TAtlasBreakpointColumns;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugBreakpointsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    Assert.AreEqual(Integer(Ord(High(TAtlasBreakpointColumn))) + 1, mFrame.List.Columns.Count);
    mColumns := mFrame.Columns;
    mColumns.SetVisible(TAtlasBreakpointColumn.Group, False);
    mColumns.MoveTo(TAtlasBreakpointColumn.Hits, 0);
    mFrame.Columns := mColumns;
    Assert.AreEqual(Integer(Ord(High(TAtlasBreakpointColumn))), mFrame.List.Columns.Count);
    Assert.AreEqual('Treffer', mFrame.List.Columns[0].Caption);
    Assert.IsFalse(mFrame.Columns.IsVisible(TAtlasBreakpointColumn.Group));
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugBreakpointsFrameTests);

end.
