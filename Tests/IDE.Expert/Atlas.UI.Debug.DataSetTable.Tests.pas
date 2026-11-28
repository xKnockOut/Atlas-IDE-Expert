unit Atlas.UI.Debug.DataSetTable.Tests;

// Tests des Fensters „Datenmenge als Tabelle“ (#3024, TAtlasDebugDataSetForm): Es entsteht mit Fenstern für alle
// Steuerelemente (TAtlasDialogSmoke), zeigt Spalten und Zeilen virtuell mit Markierung des aktuellen Datensatzes,
// blendet Hinweis und Knöpfe zur Cursorbewegung ein und aus, sperrt beim Lesen alles außer „Abbrechen“ und graut
// aus, wenn das Programm weiterläuft.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugDataSetFormTests = class
  public
    [Test]
    procedure ShowsColumnsAndRows;
    [Test]
    procedure ConsentRowFollowsNote;
    [Test]
    procedure ReadingLeavesOnlyCancel;
    [Test]
    procedure UnavailableGraysOut;
  end;

implementation

uses
  System.SysUtils,
  System.Classes, // Inline TCollection.GetCount (H2443)
  Atlas.Core.Debug.DataSetTable,
  Atlas.UI.Debug.DataSetTable,
  Atlas.Tests.DialogSmoke;

function NewRow(ARecNo: Int64; const AId, AName: string): TAtlasDataSetRow;
begin
  Result := Default(TAtlasDataSetRow);
  Result.RecNo := ARecNo;
  Result.Cells := TArray<string>.Create(AId, AName);
  Result.Nulls := TArray<Boolean>.Create(False, AName = '');
end;

function NewForm: TAtlasDebugDataSetForm;
begin
  Result := TAtlasDebugDataSetForm.CreateTable(nil);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(Result) > 1);
    Result.SetColumns(TArray<string>.Create('ID', 'Name'));
    Result.SetRows(TArray<TAtlasDataSetRow>.Create(NewRow(1, '1', 'Anna'), NewRow(2, '2', '')), 2, True, True);
  except
    Result.Free;
    raise;
  end;
end;

{ TAtlasDebugDataSetFormTests }

procedure TAtlasDebugDataSetFormTests.ShowsColumnsAndRows;
var
  mForm: TAtlasDebugDataSetForm;
begin
  mForm := NewForm;
  try
    mForm.ShowHeader('Query1', 'Query1 · dsBrowse · record 2 of 2');
    Assert.AreEqual(3, mForm.Parts.List.Columns.Count, 'Nummer und zwei Felder');
    Assert.AreEqual(2, mForm.Parts.List.Items.Count);
    Assert.AreEqual(2, Integer(Length(mForm.Rows)));
    Assert.IsTrue(mForm.Parts.LoadMoreButton.Enabled, 'weitere Zeilen');
    Assert.IsFalse(mForm.Parts.GoToButton.Enabled, 'ohne Markierung');
    Assert.AreEqual('Query1 · dsBrowse · record 2 of 2', mForm.Parts.Header.Caption);
    mForm.Parts.List.Items[0].Selected := True;
    Assert.IsTrue(Pos('Anna', mForm.SelectedText) > 0, mForm.SelectedText);
  finally
    mForm.Free;
  end;
end;

procedure TAtlasDebugDataSetFormTests.ConsentRowFollowsNote;
var
  mForm: TAtlasDebugDataSetForm;
begin
  mForm := NewForm;
  try
    Assert.IsFalse(mForm.Parts.ConsentRow.Visible, 'anfangs aus');
    mForm.ShowConsent('Atlas has to move the cursor.', 50);
    Assert.IsTrue(mForm.Parts.ConsentRow.Visible);
    mForm.ShowConsent('', 50);
    Assert.IsFalse(mForm.Parts.ConsentRow.Visible);
    mForm.ShowHint(True);
    Assert.IsTrue(mForm.Parts.Hint.Visible);
  finally
    mForm.Free;
  end;
end;

procedure TAtlasDebugDataSetFormTests.ReadingLeavesOnlyCancel;
var
  mForm: TAtlasDebugDataSetForm;
begin
  mForm := NewForm;
  try
    mForm.SetReading(True);
    Assert.IsTrue(mForm.Parts.CancelButton.Enabled);
    Assert.IsFalse(mForm.Parts.LoadMoreButton.Enabled);
    Assert.IsFalse(mForm.Parts.EditButton.Enabled);
    mForm.SetReading(False);
    Assert.IsFalse(mForm.Parts.CancelButton.Enabled);
    Assert.IsTrue(mForm.Parts.LoadMoreButton.Enabled);
  finally
    mForm.Free;
  end;
end;

procedure TAtlasDebugDataSetFormTests.UnavailableGraysOut;
var
  mForm: TAtlasDebugDataSetForm;
begin
  mForm := NewForm;
  try
    mForm.MarkUnavailable('The program is running.');
    Assert.IsFalse(mForm.Parts.List.Enabled);
    Assert.IsFalse(mForm.Parts.LoadMoreButton.Enabled);
    Assert.IsTrue(Pos('running', mForm.Parts.Status.Caption) > 0, mForm.Parts.Status.Caption);
  finally
    mForm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugDataSetFormTests);

end.
