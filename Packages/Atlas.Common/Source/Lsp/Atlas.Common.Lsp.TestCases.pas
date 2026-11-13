unit Atlas.Common.Lsp.TestCases;

// Befehl atlas.server.testCases [uri, zeile, zeilen?] (#1879): Fälle ([TestCase]) der Testmethode an zeile als
// Tabelle für das Plugin, mit den Zeilen des Plugins dazu ein Edit, das sie zurückschreibt. Logik in
// Atlas.Common.Rules.Builtin.Testing.TestCaseTable; den Text (offenes Dokument vor der Platte) liefert die Shell.
//
// Anfrage: zeile 0-basiert, irgendwo von den Attributen bis zur Deklaration der Methode. zeilen (optional):
//   [{from, name, values: [..]}], from = Index der bisherigen Zeile (behält Form, Trennzeichen, Argumente)
//   oder -1 für eine neue.
// Antwort: null ohne [TestCase]-Methode an der Zeile, sonst
//   { uri, fixture, method, methodLine, firstLine, editable, reason,
//     columns: [{name, type, kind, enumNames}],      kind: integer, float, boolean, text, enum, unknown
//     rows: [{name, values, separator, form, line, problem, cells: [..]}],   form: classic, valuesOnly, named
//     mit zeilen zusätzlich: proposed: [{problem, cells}], edit: {range, newText} | null, editReason }
// problem und cells: Fehlertext der Zeile bzw. je Wert, '' passt.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Rules.Builtin.Testing.TestCases,
  Atlas.Common.Rules.Builtin.Testing.TestCaseTable;

type
  /// <summary>Text des Dokuments AUri; False, wenn es nicht lesbar ist.</summary>
  TLspTestCasesReadText = reference to function(const AUri: string; out AText: string): Boolean;

  TLspTestCases = class
  public const
    cCommand = 'atlas.server.testCases';
    cKindNames: array[TDUnitXValueKind] of string = ('unknown', 'text', 'integer', 'float', 'boolean', 'enum');
    cFormNames: array[TTestCaseForm] of string = ('classic', 'valuesOnly', 'named');
  public
    /// <summary>Meldet den Befehl an (nebenläufig: liest nur).</summary>
    class procedure Attach(ACommands: TLspCommands; const AReadText: TLspTestCasesReadText); static;
    /// <summary>Tabelle als JSON. Der Aufrufer übernimmt das Objekt.</summary>
    class function TableToJson(const AUri: string; const ATable: TTestCaseTable): TJSONObject; static;
    /// <summary>Zeilen aus der Anfrage; neue übernehmen Form und Trennzeichen der letzten Zeile.</summary>
    class function RowsFromJson(const ATable: TTestCaseTable; AArray: TJSONArray): TArray<TTestCaseRow>; static;
    /// <summary>Befehl mit dem Text AText des Dokuments AArguments[0].</summary>
    class function Execute(const AArguments: TJSONArray; const AReadText: TLspTestCasesReadText): TJSONValue; static;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TLspTestCasesText = (NeedsUriAndLine, NotReadable);

const
  cTexts: array[TLspTestCasesText] of TAtlasText = (
    (De: '%s braucht URI und Zeile'; En: '%s needs a URI and a line'),
    (De: '%s ist nicht lesbar'; En: '%s cannot be read'));

{$SCOPEDENUMS OFF}

function StringsToJson(const AValues: TArray<string>): TJSONArray;
var
  mValue: string;
begin
  Result := TJSONArray.Create;
  for mValue in AValues do
  begin
    Result.Add(mValue);
  end;
end;

/// <summary>Fehler der Zeile und je Wert.</summary>
procedure AddProblems(AObject: TJSONObject; const ATable: TTestCaseTable; const ARow: TTestCaseRow);
var
  mCells: TJSONArray;
  mIndex: Integer;
begin
  AObject.AddPair('problem', TTestCaseTables.RowProblem(ATable, ARow));
  mCells := TJSONArray.Create;
  AObject.AddPair('cells', mCells);
  for mIndex := 0 to High(ARow.Values) do
  begin
    if mIndex <= High(ATable.Columns) then
    begin
      mCells.Add(TTestCaseTables.CellProblem(ATable.Columns[mIndex], ARow.Values[mIndex], ARow.Separator));
    end
    else
    begin
      mCells.Add('');
    end;
  end;
end;

function ColumnToJson(const AColumn: TTestCaseColumn): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AColumn.Name);
  Result.AddPair('type', AColumn.TypeName);
  Result.AddPair('kind', TLspTestCases.cKindNames[AColumn.Kind]);
  Result.AddPair('enumNames', AColumn.EnumNames);
end;

function RowToJson(const ATable: TTestCaseTable; const ARow: TTestCaseRow): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ARow.Name);
  Result.AddPair('values', StringsToJson(ARow.Values));
  Result.AddPair('separator', ARow.Separator);
  Result.AddPair('form', TLspTestCases.cFormNames[ARow.Form]);
  Result.AddPair('line', TJSONNumber.Create(ARow.Line));
  AddProblems(Result, ATable, ARow);
end;

class function TLspTestCases.TableToJson(const AUri: string; const ATable: TTestCaseTable): TJSONObject;
var
  mColumns, mRows: TJSONArray;
  mColumn: TTestCaseColumn;
  mRow: TTestCaseRow;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  Result.AddPair('fixture', ATable.Fixture);
  Result.AddPair('method', ATable.Method);
  Result.AddPair('methodLine', TJSONNumber.Create(ATable.MethodLine));
  Result.AddPair('firstLine', TJSONNumber.Create(ATable.FirstLine));
  Result.AddPair('editable', TJSONBool.Create(ATable.Editable));
  Result.AddPair('reason', ATable.Reason);
  mColumns := TJSONArray.Create;
  Result.AddPair('columns', mColumns);
  for mColumn in ATable.Columns do
  begin
    mColumns.AddElement(ColumnToJson(mColumn));
  end;
  mRows := TJSONArray.Create;
  Result.AddPair('rows', mRows);
  for mRow in ATable.Rows do
  begin
    mRows.AddElement(RowToJson(ATable, mRow));
  end;
end;

/// <summary>Werte einer Zeile der Anfrage.</summary>
function ValuesOf(AObject: TJSONObject): TArray<string>;
var
  mArray: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  if not AObject.TryGetValue<TJSONArray>('values', mArray) then
  begin
    Exit;
  end;
  SetLength(Result, mArray.Count);
  for mIndex := 0 to mArray.Count - 1 do
  begin
    Result[mIndex] := mArray.Items[mIndex].Value;
  end;
end;

class function TLspTestCases.RowsFromJson(const ATable: TTestCaseTable; AArray: TJSONArray): TArray<TTestCaseRow>;
var
  mIndex, mFrom: Integer;
  mObject: TJSONObject;
  mRow: TTestCaseRow;
  mName: string;
begin
  Result := nil;
  for mIndex := 0 to AArray.Count - 1 do
  begin
    if not (AArray.Items[mIndex] is TJSONObject) then
    begin
      Continue;
    end;
    mObject := TJSONObject(AArray.Items[mIndex]);
    if not mObject.TryGetValue<Integer>('from', mFrom) then
    begin
      mFrom := -1;
    end;
    if not mObject.TryGetValue<string>('name', mName) then
    begin
      mName := '';
    end;
    if (mFrom >= 0) and (mFrom <= High(ATable.Rows)) then
    begin
      mRow := ATable.Rows[mFrom];
      mRow.Name := mName;
      mRow.Values := ValuesOf(mObject);
    end
    else
    begin
      mRow := TTestCaseTables.NewRow(ATable, mName, ValuesOf(mObject));
    end;
    Result := Result + [mRow];
  end;
end;

/// <summary>Zeilenende des Texts: CRLF, wenn er eins enthält.</summary>
function LineEndOf(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
  begin
    Result := #13#10;
  end
  else
  begin
    Result := #10;
  end;
end;

/// <summary>Vorschlag der Anfrage: Fehler je Zeile und das Edit bzw. warum es keins gibt.</summary>
procedure AddProposal(AResult: TJSONObject; const ATable: TTestCaseTable; const ARows: TArray<TTestCaseRow>;
  const AText: string);
var
  mProposed: TJSONArray;
  mEntry, mEdit: TJSONObject;
  mRow: TTestCaseRow;
  mTextEdit: TTextEdit;
  mReason: string;
begin
  mProposed := TJSONArray.Create;
  AResult.AddPair('proposed', mProposed);
  for mRow in ARows do
  begin
    mEntry := TJSONObject.Create;
    mProposed.AddElement(mEntry);
    AddProblems(mEntry, ATable, mRow);
  end;
  if TTestCaseTables.Write(ATable, ARows, LineEndOf(AText), mTextEdit, mReason) then
  begin
    mEdit := TJSONObject.Create;
    AResult.AddPair('edit', mEdit);
    mEdit.AddPair('range', TLspPositions.RangeToJson(mTextEdit.Range));
    mEdit.AddPair('newText', mTextEdit.NewText);
  end
  else
  begin
    AResult.AddPair('edit', TJSONNull.Create);
  end;
  AResult.AddPair('editReason', mReason);
end;

class function TLspTestCases.Execute(const AArguments: TJSONArray; const AReadText: TLspTestCasesReadText): TJSONValue;
var
  mUri, mText: string;
  mLine: Integer;
  mTree: TSyntaxTree;
  mTable: TTestCaseTable;
  mResult: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONNumber) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspTestCasesText.NeedsUriAndLine].Fmt([cCommand]));
  end;
  mUri := AArguments.Items[0].Value;
  mLine := TJSONNumber(AArguments.Items[1]).AsInt;
  if not AReadText(mUri, mText) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspTestCasesText.NotReadable].Fmt([mUri]));
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    if not TTestCaseTables.Find(mTree, mText, mLine, mTable) then
    begin
      Exit(TJSONNull.Create);
    end;
    mResult := TableToJson(mUri, mTable);
    try
      if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONArray) then
      begin
        AddProposal(mResult, mTable, RowsFromJson(mTable, TJSONArray(AArguments.Items[2])), mText);
      end;
    except
      mResult.Free;
      raise;
    end;
    Result := mResult;
  finally
    mTree.Free;
  end;
end;

class procedure TLspTestCases.Attach(ACommands: TLspCommands; const AReadText: TLspTestCasesReadText);
var
  mReadText: TLspTestCasesReadText;
begin
  mReadText := AReadText;
  ACommands.RegisterConcurrent(cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := Execute(AArguments, mReadText);
    end);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.TestCases', cTexts);

end.
