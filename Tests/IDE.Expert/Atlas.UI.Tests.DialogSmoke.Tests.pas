unit Atlas.UI.Tests.DialogSmoke.Tests;

// Rauchtest der Dialoge von Atlas.IDE.Tests: Jeder Dialog entsteht mit kleinster Eingabe, bekommt Fenster für
// sich und alle Steuerelemente, durchläuft DoShow wie beim Zeigen und wird freigegeben (TAtlasDialogSmoke).
// Dialoge mit eigenen Tests stehen dort; Tools/Check-DialogTests.ps1 prüft, dass jeder Dialog gebaut wird.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestsDialogSmokeTests = class
  public
    [Test]
    procedure FromDebugStop;
    [Test]
    procedure BoundaryCases;
    [Test]
    procedure CaseTable;
    [Test]
    procedure Compare;
    [Test]
    procedure CompareApproval;
    [Test]
    procedure ListDialog;
    [Test]
    procedure Slowest;
  end;

implementation

uses
  Atlas.Core.Tests.FromDebugStop,
  Atlas.Core.Tests.BoundaryCases,
  Atlas.Core.Tests.CaseTable,
  Atlas.Core.Tests.Lists,
  Atlas.Core.Tests.ListText,
  Atlas.Core.Tests.Durations,
  Atlas.UI.Tests.FromDebugStop,
  Atlas.UI.Tests.BoundaryCases,
  Atlas.UI.Tests.CaseTable,
  Atlas.UI.Tests.Compare,
  Atlas.UI.Tests.ListDialog,
  Atlas.UI.Tests.Slowest,
  Atlas.Tests.DialogSmoke;

{ TAtlasTestsDialogSmokeTests }

procedure TAtlasTestsDialogSmokeTests.FromDebugStop;
var
  mRow: TAtlasStopValueRow;
  mDescription: TAtlasStopDescription;
  mDialog: TAtlasTestFromDebugDialog;
begin
  mRow := Default(TAtlasStopValueRow);
  mRow.Name := 'AWert';
  mRow.TypeName := 'Integer';
  mRow.Accessible := True;
  mRow.Text := '42';
  mRow.Literal := '42';
  mRow.Chosen := True;
  mDescription := Default(TAtlasStopDescription);
  mDescription.ClassName := 'TRechner';
  mDescription.Method := 'Teile';
  mDescription.ResultType := 'Integer';
  mDescription.TestUnit := 'Rechner.Tests';
  mDescription.TestName := 'Teile42';
  mDescription.Rows := TArray<TAtlasStopValueRow>.Create(mRow);
  mDialog := TAtlasTestFromDebugDialog.CreateDialog(nil, mDescription, Default(TAtlasStopChoice), 'Rechner.pas:12');
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(1, mDialog.ValueList.Items.Count, 'Werte nach DoShow');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTestsDialogSmokeTests.BoundaryCases;
var
  mParameter: TAtlasBoundaryParameter;
  mCase: TAtlasBoundaryCase;
  mSuggestion: TAtlasBoundarySuggestion;
  mDialog: TAtlasTestsBoundaryDialog;
begin
  mParameter := Default(TAtlasBoundaryParameter);
  mParameter.Name := 'AWert';
  mParameter.TypeName := 'Integer';
  mCase := Default(TAtlasBoundaryCase);
  mCase.Name := 'Null';
  mCase.Value := '0';
  mCase.Values := TArray<string>.Create('0');
  mCase.Use := True;
  mSuggestion := Default(TAtlasBoundarySuggestion);
  mSuggestion.Routine := 'TRechner.Teile';
  mSuggestion.ResultType := 'Integer';
  mSuggestion.Parameters := TArray<TAtlasBoundaryParameter>.Create(mParameter);
  mSuggestion.Cases := TArray<TAtlasBoundaryCase>.Create(mCase);
  mDialog := TAtlasTestsBoundaryDialog.CreateDialog(nil, mSuggestion, '');
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTestsDialogSmokeTests.CaseTable;
var
  mRow: TAtlasTestCaseRow;
  mTable: TAtlasTestCaseTable;
  mDialog: TAtlasTestsCaseTableDialog;
begin
  mRow := Default(TAtlasTestCaseRow);
  mRow.From := 0;
  mRow.Name := 'Null';
  mRow.Values := TArray<string>.Create('0', '0');
  mTable := Default(TAtlasTestCaseTable);
  mTable.Fixture := 'TRechnerTests';
  mTable.Method := 'Teile';
  mTable.Editable := True;
  mTable.Rows := TArray<TAtlasTestCaseRow>.Create(mRow);
  mDialog := TAtlasTestsCaseTableDialog.CreateDialog(nil, mTable, Default(TAtlasTestsCaseTableDialog.THooks));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(-1, mDialog.DebugRow);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTestsDialogSmokeTests.Compare;
var
  mDialog: TAtlasTestsCompareDialog;
begin
  mDialog := TAtlasTestsCompareDialog.CreateDialog(nil, 'TRechnerTests.Teile', 'a' + sLineBreak + 'b',
    'a' + sLineBreak + 'c', False);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.IsNull(mDialog.AcceptButton, 'ohne Freigabe kein Übernehmen');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTestsDialogSmokeTests.CompareApproval;
var
  mDialog: TAtlasTestsCompareDialog;
begin
  mDialog := TAtlasTestsCompareDialog.CreateDialog(nil, 'TRechnerTests.Bericht', '{"a": 1}', '{"a": 2}', True, True);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.IsNotNull(mDialog.AcceptButton);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTestsDialogSmokeTests.ListDialog;
var
  mList: TAtlasTestList;
  mDialog: TAtlasTestsListDialog;
begin
  mList := Default(TAtlasTestList);
  mList.Name := 'Langsame';
  mDialog := TAtlasTestsListDialog.CreateFor(nil, mList, True, TArray<string>.Create('Alle'),
    TArray<string>.Create('Benchmark'), Default(TAtlasTestListTexts));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTestsDialogSmokeTests.Slowest;
var
  mRow: TAtlasTestSlowRow;
  mDialog: TAtlasTestsSlowestDialog;
begin
  mRow := Default(TAtlasTestSlowRow);
  mRow.Test := 'Rechner.Tests.TRechnerTests.Teile';
  mRow.DurationMs := 1200;
  mRow.DurationText := '1,2 s';
  mRow.Slow := True;
  mDialog := TAtlasTestsSlowestDialog.CreateDialog(nil, TArray<TAtlasTestSlowRow>.Create(mRow), 500);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(1, mDialog.List.Items.Count, 'Zeilen nach DoShow');
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestsDialogSmokeTests);

end.
