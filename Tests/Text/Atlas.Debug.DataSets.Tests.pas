unit Atlas.Debug.DataSets.Tests;

// Tests der mitgelieferten Unit Atlas.Debug.DataSets (#3024) an einem TClientDataSet: Seite lesen, ohne dass der
// Cursor wandert oder Scroll-Ereignisse laufen; Sonderzeichen und NULL so, wie TAtlasDataSetTable.ParseHelperRows
// sie liest; Längengrenze der Antwort; geschlossene und bearbeitete Datenmengen; Wert ändern und Fehlerfälle.

interface

uses
  Data.DB,
  Datasnap.DBClient,
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDebugDataSetsTests = class
  private
    FData: TClientDataSet;
    FScrolls: Integer;
    procedure CountScroll(ADataSet: TDataSet);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RowsReadPageWithoutMovingCursor;
    [Test]
    procedure RowsEscapeSpecialCharsAndNull;
    [Test]
    procedure RowsRespectMaxChars;
    [Test]
    procedure RowsOfClosedOrEditingDataSetAreEmpty;
    [Test]
    procedure SetValueChangesAndKeepsRecord;
    [Test]
    procedure SetValueReportsProblems;
  end;

implementation

uses
  System.SysUtils,
  System.Variants,
  MidasLib,
  Atlas.Core.Debug.DataSetTable,
  Atlas.Debug.DataSets;

{ TAtlasDebugDataSetsTests }

procedure TAtlasDebugDataSetsTests.Setup;
begin
  FScrolls := 0;
  FData := TClientDataSet.Create(nil);
  FData.FieldDefs.Add('ID', ftInteger);
  FData.FieldDefs.Add('Name', ftString, 20);
  FData.FieldDefs.Add('Notiz', ftString, 50);
  FData.CreateDataSet;
  FData.AppendRecord([1, 'Anna', 'a'#9'b'#13#10'c\d']);
  FData.AppendRecord([2, 'Bert', Null]);
  FData.AppendRecord([3, 'Carla', 'x']);
  FData.RecNo := 2;
end;

procedure TAtlasDebugDataSetsTests.TearDown;
begin
  FreeAndNil(FData);
end;

procedure TAtlasDebugDataSetsTests.CountScroll(ADataSet: TDataSet);
begin
  Inc(FScrolls);
end;

procedure TAtlasDebugDataSetsTests.RowsReadPageWithoutMovingCursor;
var
  mRows: TArray<TAtlasDataSetRow>;
begin
  FData.AfterScroll := CountScroll;
  Assert.IsTrue(TAtlasDataSetTable.ParseHelperRows(AtlasDataSetRows(FData, 1, 10, 2000), 3, mRows));
  Assert.AreEqual(3, Integer(Length(mRows)));
  Assert.AreEqual(Int64(3), mRows[2].RecNo);
  Assert.AreEqual('Carla', mRows[2].Cells[1]);
  Assert.AreEqual(2, FData.RecNo, 'Cursor zurück');
  Assert.AreEqual(0, FScrolls, 'AfterScroll ruht');
  Assert.IsTrue(Assigned(FData.AfterScroll), 'Ereignis wieder angehängt');
  Assert.IsTrue(TAtlasDataSetTable.ParseHelperRows(AtlasDataSetRows(FData, 3, 10, 2000), 3, mRows), 'ab 3');
  Assert.AreEqual(1, Integer(Length(mRows)));
  Assert.AreEqual('0', AtlasDataSetRows(FData, 9, 10, 2000), 'hinter dem Ende');
end;

procedure TAtlasDebugDataSetsTests.RowsEscapeSpecialCharsAndNull;
var
  mText: string;
  mRows: TArray<TAtlasDataSetRow>;
begin
  mText := AtlasDataSetRows(FData, 1, 2, 2000);
  Assert.AreEqual('2'#10'1'#9'1'#9'Anna'#9'a\tb\r\nc\\d'#10'2'#9'2'#9'Bert'#9'\N', mText);
  Assert.IsTrue(TAtlasDataSetTable.ParseHelperRows(mText, 3, mRows));
  Assert.AreEqual('a'#9'b'#13#10'c\d', mRows[0].Cells[2]);
  Assert.IsTrue(mRows[1].Nulls[2], 'NULL');
end;

procedure TAtlasDebugDataSetsTests.RowsRespectMaxChars;
var
  mRows: TArray<TAtlasDataSetRow>;
  mText: string;
begin
  mText := AtlasDataSetRows(FData, 1, 10, 30);
  Assert.IsTrue(TAtlasDataSetTable.ParseHelperRows(mText, 3, mRows));
  Assert.IsTrue(Length(mRows) >= 1, 'mindestens ein Datensatz');
  Assert.IsTrue(Length(mRows) < 3, 'gekürzt');
  Assert.AreEqual(2, FData.RecNo);
end;

procedure TAtlasDebugDataSetsTests.RowsOfClosedOrEditingDataSetAreEmpty;
begin
  Assert.AreEqual('0', AtlasDataSetRows(nil, 1, 10, 2000));
  FData.Edit;
  Assert.AreEqual('0', AtlasDataSetRows(FData, 1, 10, 2000), 'im Bearbeiten');
  Assert.AreEqual(Ord(dsEdit), Ord(FData.State), 'Bearbeiten bleibt');
  FData.Cancel;
  FData.Close;
  Assert.AreEqual('0', AtlasDataSetRows(FData, 1, 10, 2000), 'geschlossen');
end;

procedure TAtlasDebugDataSetsTests.SetValueChangesAndKeepsRecord;
begin
  Assert.AreEqual('', AtlasDataSetSetValue(FData, 3, 1, 'Zoe'));
  Assert.AreEqual(2, FData.RecNo, 'Cursor zurück');
  Assert.AreEqual(Ord(dsBrowse), Ord(FData.State));
  FData.RecNo := 3;
  Assert.AreEqual('Zoe', FData.Fields[1].AsString);
end;

procedure TAtlasDebugDataSetsTests.SetValueReportsProblems;
begin
  Assert.AreNotEqual('', AtlasDataSetSetValue(FData, 1, 9, 'x'), 'kein solches Feld');
  Assert.AreEqual('Record not found.', AtlasDataSetSetValue(FData, 9, 0, '1'));
  Assert.AreNotEqual('', AtlasDataSetSetValue(FData, 1, 0, 'keine Zahl'), 'Wert passt nicht');
  Assert.AreEqual(Ord(dsBrowse), Ord(FData.State), 'abgebrochen');
  Assert.AreEqual(2, FData.RecNo);
  FData.RecNo := 1;
  Assert.AreEqual(1, FData.Fields[0].AsInteger, 'unverändert');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugDataSetsTests);

end.
