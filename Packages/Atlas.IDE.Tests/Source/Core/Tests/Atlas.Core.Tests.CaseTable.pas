unit Atlas.Core.Tests.CaseTable;

// Daten der TestCase-Tabelle (#1879) ohne IDE und VCL: Antwort des Befehls atlas.server.testCases lesen, Zeilen
// der Tabelle bearbeiten (Zelle setzen, Zeile anfügen, löschen, verschieben) und die Anfrage mit den Zeilen
// bauen, auf die der Server mit Fehlern je Zelle und dem Edit antwortet.
//   Spalten der Tabelle: 0 = Name, 1..n = je Parameter ein Wert ("A: Integer"), danach „Letzter Lauf“.
//   From einer Zeile nennt die Zeile des Servers, aus der sie stammt (Form, Trennzeichen, Argumente bleiben);
//   -1 = neue Zeile.

interface

uses
  System.SysUtils;

type
  TAtlasTestCaseColumn = record
    Name: string;
    TypeName: string;
    /// <summary>integer, float, boolean, text, enum, unknown.</summary>
    Kind: string;
    /// <summary>Erlaubte Namen einer Aufzählung ("Rot,Gruen"); '' sonst.</summary>
    EnumNames: string;
    /// <summary>Kopf der Spalte: "A: Integer" bzw. "A" ohne Typ.</summary>
    function Header: string;
  end;

  TAtlasTestCaseRow = record
    /// <summary>Index der Zeile des Servers; -1 = neu.</summary>
    From: Integer;
    Name: string;
    Values: TArray<string>;
    /// <summary>Zeile des Attributs (0-basiert); -1 bei neuen Zeilen.</summary>
    Line: Integer;
    /// <summary>Fehler der Zeile (Zahl der Werte); '' passt.</summary>
    Problem: string;
    /// <summary>Fehler je Wert; '' passt.</summary>
    Cells: TArray<string>;
    /// <summary>Wert AIndex; '' außerhalb.</summary>
    function Value(AIndex: Integer): string;
    /// <summary>Fehler des Werts AIndex; '' außerhalb.</summary>
    function CellProblem(AIndex: Integer): string;
  end;

  TAtlasTestCaseTable = record
    Uri: string;
    Fixture: string;
    Method: string;
    MethodLine: Integer;
    Editable: Boolean;
    /// <summary>Warum nicht bearbeitbar; sonst ''.</summary>
    Reason: string;
    Columns: TArray<TAtlasTestCaseColumn>;
    Rows: TArray<TAtlasTestCaseRow>;
    /// <summary>Wertespalten der Tabelle: Parameter, mindestens so viele wie die längste Zeile Werte hat.</summary>
    function ValueColumns: Integer;
    /// <summary>Kopf der Wertespalte AIndex (Parameter oder "#4" für überzählige Werte).</summary>
    function Header(AIndex: Integer): string;
  end;

  /// <summary>Antwort auf eine Anfrage mit Zeilen: Fehler je Zeile, Edit (WorkspaceEdit als JSON) oder Grund.
  /// </summary>
  TAtlasTestCaseProposal = record
    Problems: TArray<string>;
    Cells: TArray<TArray<string>>;
    /// <summary>WorkspaceEdit als JSON; '' wenn nicht geschrieben werden kann.</summary>
    EditJson: string;
    Reason: string;
  end;

  TAtlasTestCaseTables = class
  public const
    cCommand = 'atlas.server.testCases';
  public
    /// <summary>Argumente der Abfrage: [uri, zeile].</summary>
    class function RequestJson(const AUri: string; ALine: Integer): string; static;
    /// <summary>Argumente mit Zeilen: [uri, zeile, [{from, name, values}]].</summary>
    class function ProposalJson(const AUri: string; ALine: Integer;
      const ARows: TArray<TAtlasTestCaseRow>): string; static;
    /// <summary>Tabelle aus der Antwort; False bei null oder unlesbar.</summary>
    class function Parse(const AJson: string; out ATable: TAtlasTestCaseTable): Boolean; static;
    /// <summary>Fehler und Edit aus der Antwort auf ProposalJson; False bei unlesbar.</summary>
    class function ParseProposal(const AJson: string; out AProposal: TAtlasTestCaseProposal): Boolean; static;
    /// <summary>Fehler aus AProposal in ARows übernehmen (gleiche Reihenfolge).</summary>
    class procedure TakeProblems(var ARows: TArray<TAtlasTestCaseRow>; const AProposal: TAtlasTestCaseProposal);
      static;
    /// <summary>Wert AIndex der Zeile setzen (auf einer eigenen Kopie der Werte); fehlende Werte davor werden
    /// leer angelegt.</summary>
    class procedure SetValue(var ARow: TAtlasTestCaseRow; AIndex: Integer; const AValue: string); static;
    /// <summary>Neue Zeile mit leeren Werten je Parameter.</summary>
    class function NewRow(const ATable: TAtlasTestCaseTable): TAtlasTestCaseRow; static;
    /// <summary>Zeile AIndex um ADelta verschieben; False, wenn das Ziel außerhalb liegt.</summary>
    class function Move(var ARows: TArray<TAtlasTestCaseRow>; AIndex, ADelta: Integer): Boolean; static;
    /// <summary>Zeile AIndex löschen; False außerhalb oder wenn es die letzte ist.</summary>
    class function Delete(var ARows: TArray<TAtlasTestCaseRow>; AIndex: Integer): Boolean; static;
    /// <summary>Haben die Zeilen einen Fehler?</summary>
    class function HasProblems(const ARows: TArray<TAtlasTestCaseRow>): Boolean; static;
    /// <summary>Unterscheiden sich die Zeilen von denen der Tabelle (Reihenfolge, Name, Werte)?</summary>
    class function Changed(const ATable: TAtlasTestCaseTable; const ARows: TArray<TAtlasTestCaseRow>): Boolean;
      static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json;

{ TAtlasTestCaseColumn }

function TAtlasTestCaseColumn.Header: string;
begin
  Result := Name;
  if TypeName <> '' then
  begin
    Result := Result + ': ' + TypeName;
  end;
end;

{ TAtlasTestCaseRow }

function TAtlasTestCaseRow.Value(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(Values)) then
  begin
    Result := Values[AIndex];
  end;
end;

function TAtlasTestCaseRow.CellProblem(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(Cells)) then
  begin
    Result := Cells[AIndex];
  end;
end;

{ TAtlasTestCaseTable }

function TAtlasTestCaseTable.ValueColumns: Integer;
var
  mRow: TAtlasTestCaseRow;
begin
  Result := Length(Columns);
  for mRow in Rows do
  begin
    if Length(mRow.Values) > Result then
    begin
      Result := Length(mRow.Values);
    end;
  end;
end;

function TAtlasTestCaseTable.Header(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(Columns)) then
  begin
    Result := Columns[AIndex].Header;
  end
  else
  begin
    Result := '#' + IntToStr(AIndex + 1);
  end;
end;

{ Lesen }

function StringsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mArray: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  mArray := TJsonRead.Items(AObject, AName);
  if mArray = nil then
  begin
    Exit;
  end;
  SetLength(Result, mArray.Count);
  for mIndex := 0 to mArray.Count - 1 do
  begin
    Result[mIndex] := mArray.Items[mIndex].Value;
  end;
end;

function ObjectsOf(AObject: TJSONObject; const AName: string): TArray<TJSONObject>;
var
  mArray: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  mArray := TJsonRead.Items(AObject, AName);
  if mArray = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mArray.Count - 1 do
  begin
    if mArray.Items[mIndex] is TJSONObject then
    begin
      Result := Result + [TJSONObject(mArray.Items[mIndex])];
    end;
  end;
end;

function ColumnOf(AObject: TJSONObject): TAtlasTestCaseColumn;
begin
  Result.Name := TJsonRead.Text(AObject, 'name');
  Result.TypeName := TJsonRead.Text(AObject, 'type');
  Result.Kind := TJsonRead.Text(AObject, 'kind');
  Result.EnumNames := TJsonRead.Text(AObject, 'enumNames');
end;

function RowOf(AObject: TJSONObject; AIndex: Integer): TAtlasTestCaseRow;
begin
  Result.From := AIndex;
  Result.Name := TJsonRead.Text(AObject, 'name');
  Result.Values := StringsOf(AObject, 'values');
  Result.Line := TJsonRead.IntOr(AObject, 'line', -1);
  Result.Problem := TJsonRead.Text(AObject, 'problem');
  Result.Cells := StringsOf(AObject, 'cells');
end;

class function TAtlasTestCaseTables.Parse(const AJson: string; out ATable: TAtlasTestCaseTable): Boolean;
var
  mValue: TJSONValue;
  mObject, mItem: TJSONObject;
begin
  ATable := Default(TAtlasTestCaseTable);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mObject := TJSONObject(mValue);
    ATable.Uri := TJsonRead.Text(mObject, 'uri');
    ATable.Fixture := TJsonRead.Text(mObject, 'fixture');
    ATable.Method := TJsonRead.Text(mObject, 'method');
    ATable.MethodLine := TJsonRead.IntOr(mObject, 'methodLine', -1);
    ATable.Editable := TJsonRead.FlagOr(mObject, 'editable', False);
    ATable.Reason := TJsonRead.Text(mObject, 'reason');
    for mItem in ObjectsOf(mObject, 'columns') do
    begin
      ATable.Columns := ATable.Columns + [ColumnOf(mItem)];
    end;
    for mItem in ObjectsOf(mObject, 'rows') do
    begin
      ATable.Rows := ATable.Rows + [RowOf(mItem, Length(ATable.Rows))];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasTestCaseTables.ParseProposal(const AJson: string; out AProposal: TAtlasTestCaseProposal): Boolean;
var
  mValue, mEdit: TJSONValue;
  mObject, mItem: TJSONObject;
begin
  AProposal := Default(TAtlasTestCaseProposal);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mObject := TJSONObject(mValue);
    for mItem in ObjectsOf(mObject, 'proposed') do
    begin
      AProposal.Problems := AProposal.Problems + [TJsonRead.Text(mItem, 'problem')];
      AProposal.Cells := AProposal.Cells + [StringsOf(mItem, 'cells')];
    end;
    mEdit := mObject.GetValue('edit');
    if mEdit is TJSONObject then
    begin
      AProposal.EditJson := mEdit.ToJSON;
    end;
    AProposal.Reason := TJsonRead.Text(mObject, 'editReason');
  finally
    mValue.Free;
  end;
end;

{ Anfragen }

class function TAtlasTestCaseTables.RequestJson(const AUri: string; ALine: Integer): string;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(AUri);
    mArguments.Add(ALine);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

function RowToJson(const ARow: TAtlasTestCaseRow): TJSONObject;
var
  mValues: TJSONArray;
  mValue: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('from', TJSONNumber.Create(ARow.From));
  Result.AddPair('name', ARow.Name);
  mValues := TJSONArray.Create;
  Result.AddPair('values', mValues);
  for mValue in ARow.Values do
  begin
    mValues.Add(mValue);
  end;
end;

class function TAtlasTestCaseTables.ProposalJson(const AUri: string; ALine: Integer;
  const ARows: TArray<TAtlasTestCaseRow>): string;
var
  mArguments, mRows: TJSONArray;
  mRow: TAtlasTestCaseRow;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(AUri);
    mArguments.Add(ALine);
    mRows := TJSONArray.Create;
    mArguments.AddElement(mRows);
    for mRow in ARows do
    begin
      mRows.AddElement(RowToJson(mRow));
    end;
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

{ Bearbeiten }

class procedure TAtlasTestCaseTables.TakeProblems(var ARows: TArray<TAtlasTestCaseRow>;
  const AProposal: TAtlasTestCaseProposal);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARows) do
  begin
    ARows[mIndex].Problem := '';
    ARows[mIndex].Cells := nil;
    if mIndex <= High(AProposal.Problems) then
    begin
      ARows[mIndex].Problem := AProposal.Problems[mIndex];
      ARows[mIndex].Cells := AProposal.Cells[mIndex];
    end;
  end;
end;

class procedure TAtlasTestCaseTables.SetValue(var ARow: TAtlasTestCaseRow; AIndex: Integer; const AValue: string);
begin
  if AIndex < 0 then
  begin
    Exit;
  end;
  // Dynamische Arrays teilen sich beim Zuweisen: erst eine eigene Kopie, sonst ändert sich die Zeile der Tabelle mit.
  ARow.Values := Copy(ARow.Values);
  if AIndex > High(ARow.Values) then
  begin
    SetLength(ARow.Values, AIndex + 1);
  end;
  ARow.Values[AIndex] := AValue;
end;

class function TAtlasTestCaseTables.NewRow(const ATable: TAtlasTestCaseTable): TAtlasTestCaseRow;
begin
  Result := Default(TAtlasTestCaseRow);
  Result.From := -1;
  Result.Line := -1;
  SetLength(Result.Values, Length(ATable.Columns));
end;

class function TAtlasTestCaseTables.Move(var ARows: TArray<TAtlasTestCaseRow>; AIndex, ADelta: Integer): Boolean;
var
  mTarget: Integer;
  mRow: TAtlasTestCaseRow;
begin
  mTarget := AIndex + ADelta;
  Result := (AIndex >= 0) and (AIndex <= High(ARows)) and (mTarget >= 0) and (mTarget <= High(ARows)) and
    (ADelta <> 0);
  if Result then
  begin
    mRow := ARows[AIndex];
    System.Delete(ARows, AIndex, 1);
    System.Insert(mRow, ARows, mTarget);
  end;
end;

class function TAtlasTestCaseTables.Delete(var ARows: TArray<TAtlasTestCaseRow>; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(ARows)) and (Length(ARows) > 1);
  if Result then
  begin
    System.Delete(ARows, AIndex, 1);
  end;
end;

class function TAtlasTestCaseTables.HasProblems(const ARows: TArray<TAtlasTestCaseRow>): Boolean;
var
  mRow: TAtlasTestCaseRow;
  mCell: string;
begin
  for mRow in ARows do
  begin
    if mRow.Problem <> '' then
    begin
      Exit(True);
    end;
    for mCell in mRow.Cells do
    begin
      if mCell <> '' then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Gleiche Werte in gleicher Reihenfolge?</summary>
function SameValues(const AOne, ATwo: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AOne) = Length(ATwo);
  for mIndex := 0 to High(AOne) do
  begin
    Result := Result and (AOne[mIndex] = ATwo[mIndex]);
  end;
end;

class function TAtlasTestCaseTables.Changed(const ATable: TAtlasTestCaseTable;
  const ARows: TArray<TAtlasTestCaseRow>): Boolean;
var
  mIndex: Integer;
begin
  if Length(ARows) <> Length(ATable.Rows) then
  begin
    Exit(True);
  end;
  for mIndex := 0 to High(ARows) do
  begin
    if (ARows[mIndex].From <> mIndex) or (ARows[mIndex].Name <> ATable.Rows[mIndex].Name) or
      not SameValues(ARows[mIndex].Values, ATable.Rows[mIndex].Values) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
