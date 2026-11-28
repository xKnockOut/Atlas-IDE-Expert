unit Atlas.Core.Debug.DataSetTable.Tests;

// Tests für die Datenmenge als Tabelle (#3024, TAtlasDataSetTable und TAtlasDataSetReader) gegen eine gefälschte
// Datenmenge, die die Ausdrücke des Debuggers beantwortet: Literale lesen und schreiben, Antwort der Hilfs-Unit,
// Wahl des Wegs, Untersuchen, Lesen über Hilfs-Unit, Cursor und nur den aktuellen Datensatz (Rückkehr, Ende,
// Abbrechen, Zelle für Zelle), Springen, Ändern (mit und ohne Hilfs-Unit, Abbruch mit Cancel), CSV, JSON und die
// Einstellung moveCursor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDataSetTableTests = class
  public
    [Test]
    procedure DecodeReadsDebuggerLiterals;
    [Test]
    procedure LiteralRoundTrips;
    [Test]
    procedure ParseHelperRowsReadsCellsAndNulls;
    [Test]
    procedure ParseHelperRowsRejectsWrongShape;
    [Test]
    procedure SplitRowChecksFieldCount;
    [Test]
    procedure WayForPrefersHelperThenConsentedCursor;
    [Test]
    procedure ProbeReadsStateFieldsAndHelper;
    [Test]
    procedure ProbeOfClosedDataSetIsInvalid;
    [Test]
    procedure CursorReaderReadsPageAndReturns;
    [Test]
    procedure CursorReaderStopsAtEnd;
    [Test]
    procedure CursorReaderCancelReturns;
    [Test]
    procedure CursorReaderFallsBackToCells;
    [Test]
    procedure HelperReaderDoesNotMoveCursor;
    [Test]
    procedure CurrentOnlyReadsOneRow;
    [Test]
    procedure MoveToMovesAndReturnsWhenShort;
    [Test]
    procedure EditCellByCursorPostsAndReturns;
    [Test]
    procedure EditCellFailureCancels;
    [Test]
    procedure EditCellUsesHelper;
    [Test]
    procedure EditCellInEditBuffer;
    [Test]
    procedure CopiesAsCsvAndJson;
    [Test]
    procedure MoveCursorOfReadsSetting;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Plugin.Settings.VisualizerKinds,
  Atlas.Core.Debug.Visualizers,
  Atlas.Core.Debug.DataSetTable;

type
  /// <summary>Datenmenge „DS“ im angehaltenen Programm, so weit die Ausdrücke von TAtlasDataSetTable reichen.
  /// </summary>
  TFakeDataSet = class
  public
    Names: TArray<string>;
    Rows: TArray<TArray<string>>;
    RecNo: Integer;
    State: string;
    Helper: Boolean;
    HelperPrefix: string;
    RowExpressionFails: Boolean;
    ModifyFails: Boolean;
    Pending: string;
    PendingField: Integer;
    Moves: Integer;
    Disabled: Integer;
    Enabled: Integer;
    Posted: Integer;
    Cancelled: Integer;
    constructor Create;
    function AnswerProperty(const AExpression: string; out AText: string): Boolean;
    function AnswerMoveBy(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation;
      out AText: string): Boolean;
    function AnswerCall(const AExpression: string): Boolean;
    function AnswerHelper(const AExpression: string; out AText: string): Boolean;
    function AnswerField(const AExpression: string; out AText: string): Boolean;
    function Answer(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation; out AText: string): Boolean;
    function Modify(const AExpression, ANewValue: string; out AResult: string): Boolean;
  end;

const
  cDs = 'DS';

constructor TFakeDataSet.Create;
begin
  inherited Create;
  Names := TArray<string>.Create('ID', 'Name');
  SetLength(Rows, 5);
  Rows[0] := TArray<string>.Create('1', 'Anna');
  Rows[1] := TArray<string>.Create('2', 'Bert');
  Rows[2] := TArray<string>.Create('3', 'Carla');
  Rows[3] := TArray<string>.Create('4', 'Dora');
  Rows[4] := TArray<string>.Create('5', 'Emil');
  RecNo := 3;
  State := 'dsBrowse';
  PendingField := -1;
end;

function HelperEscaped(const AText: string): string;
begin
  Result := StringReplace(AText, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
end;

/// <summary>Zahlen zwischen den Klammern von AExpression ab APrefix: „P(DS, 1, 2, 3)“.</summary>
function Arguments(const AExpression, APrefix: string): TArray<string>;
var
  mInner: string;
  mIndex: Integer;
begin
  mInner := Copy(AExpression, Length(APrefix) + 1, Length(AExpression) - Length(APrefix) - 1);
  Result := mInner.Split([', ']);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := Trim(Result[mIndex]);
  end;
end;

function TFakeDataSet.AnswerProperty(const AExpression: string; out AText: string): Boolean;
begin
  Result := True;
  if AExpression = cDs + '.State' then
  begin
    AText := State;
  end
  else if AExpression = cDs + '.RecNo' then
  begin
    AText := IntToStr(RecNo);
  end
  else if AExpression = cDs + '.RecordCount' then
  begin
    AText := IntToStr(Length(Rows));
  end
  else if AExpression = cDs + '.IsUniDirectional' then
  begin
    AText := 'False';
  end
  else if AExpression = cDs + '.FieldCount' then
  begin
    AText := IntToStr(Length(Names));
  end
  else
  begin
    Result := False;
  end;
end;

function TFakeDataSet.AnswerMoveBy(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation;
  out AText: string): Boolean;
var
  mOld: Integer;
begin
  Result := StartsText(cDs + '.MoveBy(', AExpression);
  if not Result then
  begin
    Exit;
  end;
  Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Calls), Ord(AEvaluation), 'MoveBy braucht Aufrufe');
  Inc(Moves);
  mOld := RecNo;
  RecNo := EnsureRange(mOld + StrToInt(Arguments(AExpression, cDs + '.MoveBy(')[0]), 1, Length(Rows));
  AText := IntToStr(RecNo - mOld);
end;

function TFakeDataSet.AnswerCall(const AExpression: string): Boolean;
begin
  Result := True;
  if AExpression = cDs + '.DisableControls' then
  begin
    Inc(Disabled);
  end
  else if AExpression = cDs + '.EnableControls' then
  begin
    Inc(Enabled);
  end
  else if AExpression = cDs + '.Edit' then
  begin
    State := 'dsEdit';
  end
  else if AExpression = cDs + '.Post' then
  begin
    Inc(Posted);
    Rows[RecNo - 1][PendingField] := Pending;
    State := 'dsBrowse';
  end
  else if AExpression = cDs + '.Cancel' then
  begin
    Inc(Cancelled);
    State := 'dsBrowse';
  end
  else
  begin
    Result := False;
  end;
end;

function TFakeDataSet.AnswerHelper(const AExpression: string; out AText: string): Boolean;
var
  mIndex, mFirst, mCount: Integer;
  mArgs: TArray<string>;
begin
  Result := Helper and StartsText(HelperPrefix + TAtlasDataSetTable.cHelperRows + '(', AExpression);
  if Result then
  begin
    mArgs := Arguments(AExpression, HelperPrefix + TAtlasDataSetTable.cHelperRows + '(');
    mFirst := StrToInt(mArgs[1]);
    // Höchstens zwei Zeilen je Antwort: Der Leser muss nachfragen.
    mCount := Min(Min(StrToInt(mArgs[2]), Max(Length(Rows) - mFirst + 1, 0)), 2);
    AText := IntToStr(mCount);
    for mIndex := mFirst to mFirst + mCount - 1 do
    begin
      AText := AText + #10 + IntToStr(mIndex) + #9 + HelperEscaped(Rows[mIndex - 1][0]) + #9 +
        HelperEscaped(Rows[mIndex - 1][1]);
    end;
    AText := TAtlasDataSetTable.Literal(AText);
    Exit;
  end;
  Result := Helper and StartsText(HelperPrefix + TAtlasDataSetTable.cHelperSetValue + '(', AExpression);
  if Result then
  begin
    mArgs := Arguments(AExpression, HelperPrefix + TAtlasDataSetTable.cHelperSetValue + '(');
    Rows[StrToInt(mArgs[1]) - 1][StrToInt(mArgs[2])] := TAtlasDataSetTable.Decode(mArgs[3]);
    AText := '''''';
  end;
end;

function TFakeDataSet.AnswerField(const AExpression: string; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  for mIndex := 0 to High(Names) do
  begin
    if AExpression = Format('%s.Fields[%d].FieldName', [cDs, mIndex]) then
    begin
      AText := TAtlasDataSetTable.Literal(Names[mIndex]);
      Exit;
    end;
    if AExpression = Format('%s.Fields[%d].DataType', [cDs, mIndex]) then
    begin
      AText := 'ftString';
      Exit;
    end;
    if AExpression = TAtlasDataSetTable.CellExpression(cDs, mIndex) then
    begin
      AText := TAtlasDataSetTable.Literal(Rows[RecNo - 1][mIndex]);
      Exit;
    end;
  end;
  Result := False;
end;

function TFakeDataSet.Answer(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation;
  out AText: string): Boolean;
begin
  AText := '';
  if AExpression = TAtlasDataSetTable.RowExpression(cDs, Length(Names)) then
  begin
    Result := not RowExpressionFails;
    AText := 'E2010 Inkompatible Typen';
    if Result then
    begin
      AText := TAtlasDataSetTable.Literal(string.Join(#9, Rows[RecNo - 1]));
    end;
    Exit;
  end;
  Result := AnswerProperty(AExpression, AText) or AnswerMoveBy(AExpression, AEvaluation, AText) or
    AnswerCall(AExpression) or AnswerHelper(AExpression, AText) or AnswerField(AExpression, AText);
  if not Result then
  begin
    AText := 'E2003 Undeklarierter Bezeichner';
  end;
end;

function TFakeDataSet.Modify(const AExpression, ANewValue: string; out AResult: string): Boolean;
var
  mIndex: Integer;
begin
  AResult := 'Feld nicht gefunden';
  Result := False;
  if ModifyFails or (State <> 'dsEdit') then
  begin
    AResult := 'Wert nicht zulässig';
    Exit;
  end;
  for mIndex := 0 to High(Names) do
  begin
    if AExpression = Format('%s.Fields[%d].AsString', [cDs, mIndex]) then
    begin
      Pending := ANewValue;
      PendingField := mIndex;
      AResult := ANewValue;
      Exit(True);
    end;
  end;
end;

/// <summary>Rückruf für den Kontext in eigener Routine (kein gemeinsamer Rahmen mit anderen Methodenreferenzen).
/// </summary>
function ContextOf(AFake: TFakeDataSet): TAtlasVisualizerContext;
begin
  Result := Default(TAtlasVisualizerContext);
  Result.Eval :=
    function(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation; out AText: string): Boolean
    begin
      Result := AFake.Answer(AExpression, AEvaluation, AText);
    end;
end;

function ModifyOf(AFake: TFakeDataSet): TAtlasDataSetModify;
begin
  Result :=
    function(const AExpression, ANewValue: string; out AResult: string): Boolean
    begin
      Result := AFake.Modify(AExpression, ANewValue, AResult);
    end;
end;

/// <summary>Seite lesen, bis der Leser fertig ist (höchstens 100 Schritte).</summary>
function ReadAll(AReader: TAtlasDataSetReader; const AContext: TAtlasVisualizerContext): Integer;
begin
  Result := 0;
  while not AReader.Step(AContext) do
  begin
    Inc(Result);
    Assert.IsTrue(Result < 100, 'Leser wird nicht fertig');
  end;
end;

function Probe(AFake: TFakeDataSet): TAtlasDataSetInfo;
begin
  Result := TAtlasDataSetTable.Probe(cDs, ContextOf(AFake));
end;

{ TAtlasDataSetTableTests }

procedure TAtlasDataSetTableTests.DecodeReadsDebuggerLiterals;
begin
  Assert.AreEqual('a'#9'b', TAtlasDataSetTable.Decode('''a''#9''b'''));
  Assert.AreEqual('Ax', TAtlasDataSetTable.Decode('#$41''x'''));
  Assert.AreEqual('it''s', TAtlasDataSetTable.Decode(' ''it''''s'' '));
  Assert.AreEqual('42', TAtlasDataSetTable.Decode('42'), 'kein Literal: unverändert');
  Assert.AreEqual('abc', TAtlasDataSetTable.Decode('''abc''...'), 'Zusatz hinter dem Literal');
  Assert.AreEqual('''offen', TAtlasDataSetTable.Decode('''offen'), 'ohne Ende: unverändert');
end;

procedure TAtlasDataSetTableTests.LiteralRoundTrips;
const
  cText = 'a'#9'''b'''#13#10'c\';
begin
  Assert.AreEqual(cText, TAtlasDataSetTable.Decode(TAtlasDataSetTable.Literal(cText)));
  Assert.AreEqual('''''', TAtlasDataSetTable.Literal(''));
  Assert.AreEqual('#9', TAtlasDataSetTable.Literal(#9));
end;

procedure TAtlasDataSetTableTests.ParseHelperRowsReadsCellsAndNulls;
var
  mRows: TArray<TAtlasDataSetRow>;
begin
  Assert.IsTrue(TAtlasDataSetTable.ParseHelperRows('2'#10'7'#9'a\tb'#9'\N'#10'8'#9'x\\y'#9'z\n', 2, mRows));
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual(Int64(7), mRows[0].RecNo);
  Assert.AreEqual('a'#9'b', mRows[0].Cells[0]);
  Assert.IsTrue(mRows[0].Nulls[1], 'NULL');
  Assert.AreEqual('', mRows[0].Cells[1]);
  Assert.AreEqual('x\y', mRows[1].Cells[0]);
  Assert.AreEqual('z'#10, mRows[1].Cells[1]);
  Assert.IsFalse(mRows[1].Nulls[1]);
  Assert.IsTrue(TAtlasDataSetTable.ParseHelperRows('0', 2, mRows), 'leere Seite');
  Assert.AreEqual(0, Integer(Length(mRows)));
end;

procedure TAtlasDataSetTableTests.ParseHelperRowsRejectsWrongShape;
var
  mRows: TArray<TAtlasDataSetRow>;
begin
  Assert.IsFalse(TAtlasDataSetTable.ParseHelperRows('E2003 Undeklarierter Bezeichner', 2, mRows));
  Assert.IsFalse(TAtlasDataSetTable.ParseHelperRows('2'#10'1'#9'a'#9'b', 2, mRows), 'eine Zeile fehlt');
  Assert.IsFalse(TAtlasDataSetTable.ParseHelperRows('1'#10'1'#9'a', 2, mRows), 'eine Zelle fehlt');
  Assert.AreEqual(0, Integer(Length(mRows)));
end;

procedure TAtlasDataSetTableTests.SplitRowChecksFieldCount;
var
  mCells: TArray<string>;
begin
  Assert.IsTrue(TAtlasDataSetTable.SplitRow('a'#9''#9'c', 3, mCells));
  Assert.AreEqual('', mCells[1]);
  Assert.IsTrue(TAtlasDataSetTable.SplitRow('', 1, mCells), 'ein leeres Feld');
  Assert.AreEqual(1, Integer(Length(mCells)));
  Assert.IsFalse(TAtlasDataSetTable.SplitRow('a'#9'b'#9'c', 2, mCells), 'Tabulator im Wert');
  Assert.AreEqual(0, Integer(Length(mCells)));
end;

procedure TAtlasDataSetTableTests.WayForPrefersHelperThenConsentedCursor;
var
  mInfo: TAtlasDataSetInfo;
begin
  mInfo := Default(TAtlasDataSetInfo);
  mInfo.Valid := True;
  mInfo.State := 'dsBrowse';
  mInfo.RecNo := 2;
  mInfo.Names := TArray<string>.Create('ID');
  Assert.AreEqual(Ord(TAtlasDataSetWay.CurrentOnly),
    Ord(TAtlasDataSetTable.WayFor(mInfo, TAtlasDataSetMoveCursor.Ask, False)), 'ohne Zustimmung');
  Assert.AreEqual(Ord(TAtlasDataSetWay.Cursor),
    Ord(TAtlasDataSetTable.WayFor(mInfo, TAtlasDataSetMoveCursor.Ask, True)), 'mit Zustimmung');
  Assert.AreEqual(Ord(TAtlasDataSetWay.Cursor),
    Ord(TAtlasDataSetTable.WayFor(mInfo, TAtlasDataSetMoveCursor.Always, False)), 'immer');
  Assert.AreEqual(Ord(TAtlasDataSetWay.CurrentOnly),
    Ord(TAtlasDataSetTable.WayFor(mInfo, TAtlasDataSetMoveCursor.Never, True)), 'nie');
  mInfo.Unidirectional := True;
  Assert.AreEqual(Ord(TAtlasDataSetWay.CurrentOnly),
    Ord(TAtlasDataSetTable.WayFor(mInfo, TAtlasDataSetMoveCursor.Always, True)), 'unidirektional');
  mInfo.HasHelper := True;
  Assert.AreEqual(Ord(TAtlasDataSetWay.CurrentOnly),
    Ord(TAtlasDataSetTable.WayFor(mInfo, TAtlasDataSetMoveCursor.Always, True)), 'Hilfs-Unit: nicht unidirektional');
  mInfo.Unidirectional := False;
  Assert.AreEqual(Ord(TAtlasDataSetWay.Helper),
    Ord(TAtlasDataSetTable.WayFor(mInfo, TAtlasDataSetMoveCursor.Never, False)), 'Hilfs-Unit');
  mInfo.State := 'dsEdit';
  Assert.AreEqual(Ord(TAtlasDataSetWay.CurrentOnly),
    Ord(TAtlasDataSetTable.WayFor(mInfo, TAtlasDataSetMoveCursor.Always, True)), 'im Bearbeiten');
end;

procedure TAtlasDataSetTableTests.ProbeReadsStateFieldsAndHelper;
var
  mFake: TFakeDataSet;
  mInfo: TAtlasDataSetInfo;
begin
  mFake := TFakeDataSet.Create;
  try
    mInfo := Probe(mFake);
    Assert.IsTrue(mInfo.Valid);
    Assert.AreEqual('dsBrowse', mInfo.State);
    Assert.AreEqual(Int64(3), mInfo.RecNo);
    Assert.AreEqual(Int64(5), mInfo.RecordCount);
    Assert.AreEqual('ID,Name', string.Join(',', mInfo.Names));
    Assert.AreEqual('ftString', mInfo.Types[1]);
    Assert.IsFalse(mInfo.HasHelper, 'ohne Hilfs-Unit');
    Assert.IsTrue(mInfo.CanMoveCursor);
    mFake.Helper := True;
    mFake.HelperPrefix := TAtlasDataSetTable.cHelperUnit + '.';
    mInfo := Probe(mFake);
    Assert.IsTrue(mInfo.HasHelper, 'mit Unitnamen gefunden');
    Assert.AreEqual(TAtlasDataSetTable.cHelperUnit + '.', mInfo.HelperPrefix);
    Assert.AreEqual(0, mFake.Moves, 'Untersuchen bewegt nichts');
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.ProbeOfClosedDataSetIsInvalid;
var
  mFake: TFakeDataSet;
  mInfo: TAtlasDataSetInfo;
begin
  mFake := TFakeDataSet.Create;
  try
    mFake.State := 'dsInactive';
    mInfo := Probe(mFake);
    Assert.IsFalse(mInfo.Valid);
    Assert.AreEqual('dsInactive', mInfo.Problem);
    mInfo := TAtlasDataSetTable.Probe('Unbekannt', ContextOf(mFake));
    Assert.IsFalse(mInfo.Valid);
    Assert.AreEqual('', mInfo.State);
    Assert.AreNotEqual('', mInfo.Problem, 'Meldung des Debuggers');
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.CursorReaderReadsPageAndReturns;
var
  mFake: TFakeDataSet;
  mReader: TAtlasDataSetReader;
begin
  mFake := TFakeDataSet.Create;
  try
    mReader := TAtlasDataSetReader.Create(cDs, Probe(mFake), TAtlasDataSetWay.Cursor, 1, 3);
    try
      ReadAll(mReader, ContextOf(mFake));
      Assert.AreEqual(3, Integer(Length(mReader.Rows)));
      Assert.AreEqual(Int64(1), mReader.Rows[0].RecNo);
      Assert.AreEqual('Anna', mReader.Rows[0].Cells[1]);
      Assert.AreEqual('Carla', mReader.Rows[2].Cells[1]);
      Assert.AreEqual('', mReader.Problem);
      Assert.IsFalse(mReader.AtEnd);
    finally
      mReader.Free;
    end;
    Assert.AreEqual(3, mFake.RecNo, 'zurück auf dem Ausgangsdatensatz');
    Assert.AreEqual(1, mFake.Disabled);
    Assert.AreEqual(1, mFake.Enabled);
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.CursorReaderStopsAtEnd;
var
  mFake: TFakeDataSet;
  mReader: TAtlasDataSetReader;
begin
  mFake := TFakeDataSet.Create;
  try
    mReader := TAtlasDataSetReader.Create(cDs, Probe(mFake), TAtlasDataSetWay.Cursor, 4, 10);
    try
      ReadAll(mReader, ContextOf(mFake));
      Assert.AreEqual(2, Integer(Length(mReader.Rows)));
      Assert.AreEqual(Int64(5), mReader.Rows[1].RecNo);
      Assert.AreEqual('Emil', mReader.Rows[1].Cells[1]);
      Assert.IsTrue(mReader.AtEnd);
    finally
      mReader.Free;
    end;
    Assert.AreEqual(3, mFake.RecNo);
    mReader := TAtlasDataSetReader.Create(cDs, Probe(mFake), TAtlasDataSetWay.Cursor, 9, 10);
    try
      ReadAll(mReader, ContextOf(mFake));
      Assert.AreEqual(0, Integer(Length(mReader.Rows)), 'hinter dem Ende');
      Assert.IsTrue(mReader.AtEnd);
    finally
      mReader.Free;
    end;
    Assert.AreEqual(3, mFake.RecNo);
    Assert.AreEqual(2, mFake.Enabled, 'Steuerelemente jedes Mal wieder an');
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.CursorReaderCancelReturns;
var
  mFake: TFakeDataSet;
  mReader: TAtlasDataSetReader;
  mContext: TAtlasVisualizerContext;
begin
  mFake := TFakeDataSet.Create;
  try
    mContext := ContextOf(mFake);
    mReader := TAtlasDataSetReader.Create(cDs, Probe(mFake), TAtlasDataSetWay.Cursor, 1, 5);
    try
      mReader.Step(mContext);
      mReader.Step(mContext);
      Assert.AreNotEqual(3, mFake.RecNo, 'Cursor unterwegs');
      mReader.Cancel;
      Assert.IsFalse(mReader.Done, 'erst zurückstellen');
      ReadAll(mReader, mContext);
      Assert.IsTrue(mReader.Done);
      Assert.AreEqual('', mReader.Problem, 'Abbrechen ist kein Fehler');
    finally
      mReader.Free;
    end;
    Assert.AreEqual(3, mFake.RecNo);
    Assert.AreEqual(1, mFake.Enabled);
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.CursorReaderFallsBackToCells;
var
  mFake: TFakeDataSet;
  mReader: TAtlasDataSetReader;
begin
  mFake := TFakeDataSet.Create;
  try
    mFake.RowExpressionFails := True;
    mReader := TAtlasDataSetReader.Create(cDs, Probe(mFake), TAtlasDataSetWay.Cursor, 2, 2);
    try
      ReadAll(mReader, ContextOf(mFake));
      Assert.AreEqual(2, Integer(Length(mReader.Rows)));
      Assert.AreEqual('Bert', mReader.Rows[0].Cells[1]);
      Assert.AreEqual('3', mReader.Rows[1].Cells[0]);
    finally
      mReader.Free;
    end;
    Assert.AreEqual(3, mFake.RecNo);
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.HelperReaderDoesNotMoveCursor;
var
  mFake: TFakeDataSet;
  mReader: TAtlasDataSetReader;
  mInfo: TAtlasDataSetInfo;
begin
  mFake := TFakeDataSet.Create;
  try
    mFake.Helper := True;
    mFake.Rows[1][1] := 'B'#9'ert';
    mInfo := Probe(mFake);
    mReader := TAtlasDataSetReader.Create(cDs, mInfo, TAtlasDataSetTable.WayFor(mInfo,
      TAtlasDataSetMoveCursor.Never, False), 2, 10);
    try
      Assert.AreEqual(Ord(TAtlasDataSetWay.Helper), Ord(mReader.Way));
      ReadAll(mReader, ContextOf(mFake));
      Assert.AreEqual(4, Integer(Length(mReader.Rows)), 'in Blöcken bis zum Ende');
      Assert.AreEqual('B'#9'ert', mReader.Rows[0].Cells[1], 'Tabulator im Wert');
      Assert.AreEqual(Int64(5), mReader.Rows[3].RecNo);
      Assert.IsTrue(mReader.AtEnd);
    finally
      mReader.Free;
    end;
    Assert.AreEqual(0, mFake.Moves, 'kein MoveBy');
    Assert.AreEqual(0, mFake.Disabled);
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.CurrentOnlyReadsOneRow;
var
  mFake: TFakeDataSet;
  mReader: TAtlasDataSetReader;
begin
  mFake := TFakeDataSet.Create;
  try
    mReader := TAtlasDataSetReader.Create(cDs, Probe(mFake), TAtlasDataSetWay.CurrentOnly, 1, 50);
    try
      ReadAll(mReader, ContextOf(mFake));
      Assert.AreEqual(1, Integer(Length(mReader.Rows)));
      Assert.AreEqual(Int64(3), mReader.Rows[0].RecNo);
      Assert.AreEqual('Carla', mReader.Rows[0].Cells[1]);
    finally
      mReader.Free;
    end;
    Assert.AreEqual(0, mFake.Moves);
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.MoveToMovesAndReturnsWhenShort;
var
  mFake: TFakeDataSet;
  mMessage: string;
begin
  mFake := TFakeDataSet.Create;
  try
    Assert.IsTrue(TAtlasDataSetTable.MoveTo(cDs, Probe(mFake), 5, ContextOf(mFake), mMessage));
    Assert.AreEqual(5, mFake.RecNo);
    Assert.IsFalse(TAtlasDataSetTable.MoveTo(cDs, Probe(mFake), 9, ContextOf(mFake), mMessage), 'gibt es nicht');
    Assert.AreEqual(5, mFake.RecNo, 'zurück');
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.EditCellByCursorPostsAndReturns;
var
  mFake: TFakeDataSet;
  mMessage: string;
begin
  mFake := TFakeDataSet.Create;
  try
    Assert.IsTrue(TAtlasDataSetTable.EditCell(cDs, Probe(mFake), TAtlasDataSetCell.Create(1, 1, 'Anja'),
      ContextOf(mFake), ModifyOf(mFake), mMessage), mMessage);
    Assert.AreEqual('Anja', mFake.Rows[0][1]);
    Assert.AreEqual(1, mFake.Posted);
    Assert.AreEqual(0, mFake.Cancelled);
    Assert.AreEqual(3, mFake.RecNo, 'zurück');
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.EditCellFailureCancels;
var
  mFake: TFakeDataSet;
  mMessage: string;
begin
  mFake := TFakeDataSet.Create;
  try
    mFake.ModifyFails := True;
    Assert.IsFalse(TAtlasDataSetTable.EditCell(cDs, Probe(mFake), TAtlasDataSetCell.Create(2, 0, 'x'),
      ContextOf(mFake), ModifyOf(mFake), mMessage));
    // Grund mit Schritt (StepFailed), nie leer.
    Assert.IsTrue(EndsText('Wert nicht zulässig', mMessage), mMessage);
    Assert.IsTrue(Length(mMessage) > Length('Wert nicht zulässig'), mMessage);
    Assert.AreEqual(1, mFake.Cancelled);
    Assert.AreEqual(0, mFake.Posted);
    Assert.AreEqual('dsBrowse', mFake.State);
    Assert.AreEqual(3, mFake.RecNo);
    Assert.IsFalse(TAtlasDataSetTable.EditCell(cDs, Probe(mFake), TAtlasDataSetCell.Create(2, 7, 'x'),
      ContextOf(mFake), ModifyOf(mFake), mMessage), 'kein solches Feld');
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.EditCellInEditBuffer;
var
  mFake: TFakeDataSet;
  mInfo: TAtlasDataSetInfo;
  mMessage: string;
begin
  // Programm steht im Bearbeiten (dsEdit): nur der aktuelle Datensatz, nur der Puffer, kein Edit/Post/Bewegen.
  mFake := TFakeDataSet.Create;
  try
    mFake.State := 'dsEdit';
    mInfo := Probe(mFake);
    Assert.IsTrue(mInfo.EditsInBuffer(mFake.RecNo));
    Assert.IsTrue(TAtlasDataSetTable.EditCell(cDs, mInfo, TAtlasDataSetCell.Create(mFake.RecNo, 1, 'Neu'),
      ContextOf(mFake), ModifyOf(mFake), mMessage), mMessage);
    Assert.AreEqual('Neu', mFake.Pending);
    Assert.AreEqual(0, mFake.Posted);
    Assert.AreEqual(0, mFake.Moves);
    Assert.AreEqual('dsEdit', mFake.State);
    Assert.IsFalse(TAtlasDataSetTable.EditCell(cDs, mInfo, TAtlasDataSetCell.Create(mFake.RecNo - 1, 1, 'x'),
      ContextOf(mFake), ModifyOf(mFake), mMessage), 'anderer Datensatz');
    Assert.IsTrue(Pos('dsEdit', mMessage) > 0, mMessage);
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.EditCellUsesHelper;
var
  mFake: TFakeDataSet;
  mMessage: string;
begin
  mFake := TFakeDataSet.Create;
  try
    mFake.Helper := True;
    Assert.IsTrue(TAtlasDataSetTable.EditCell(cDs, Probe(mFake), TAtlasDataSetCell.Create(4, 1, 'Do''ra'),
      ContextOf(mFake), nil, mMessage), mMessage);
    Assert.AreEqual('Do''ra', mFake.Rows[3][1]);
    Assert.AreEqual(0, mFake.Moves, 'ohne Cursor');
  finally
    mFake.Free;
  end;
end;

procedure TAtlasDataSetTableTests.CopiesAsCsvAndJson;
var
  mRows: TArray<TAtlasDataSetRow>;
begin
  SetLength(mRows, 1);
  mRows[0].RecNo := 1;
  mRows[0].Cells := TArray<string>.Create('1', 'a;"b"', '');
  mRows[0].Nulls := TArray<Boolean>.Create(False, False, True);
  Assert.AreEqual('ID;Name;Notiz' + sLineBreak + '1;"a;""b""";' + sLineBreak,
    TAtlasDataSetTable.ToCsv(TArray<string>.Create('ID', 'Name', 'Notiz'), mRows));
  Assert.AreEqual('[' + sLineBreak + '  {"ID": "1", "Name": "a;\"b\"", "Notiz": null}' + sLineBreak + ']',
    TAtlasDataSetTable.ToJson(TArray<string>.Create('ID', 'Name', 'Notiz'), mRows));
  Assert.AreEqual('[]', TAtlasDataSetTable.ToJson(TArray<string>.Create('ID'), nil));
end;

procedure TAtlasDataSetTableTests.MoveCursorOfReadsSetting;
begin
  Assert.AreEqual(Ord(TAtlasDataSetMoveCursor.Never), Ord(TAtlasDataSetTable.MoveCursorOf('never')));
  Assert.AreEqual(Ord(TAtlasDataSetMoveCursor.Always), Ord(TAtlasDataSetTable.MoveCursorOf(' ALWAYS ')));
  Assert.AreEqual(Ord(TAtlasDataSetMoveCursor.Ask), Ord(TAtlasDataSetTable.MoveCursorOf('ask')));
  Assert.AreEqual(Ord(TAtlasDataSetMoveCursor.Ask), Ord(TAtlasDataSetTable.MoveCursorOf('manchmal')));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDataSetTableTests);

end.
