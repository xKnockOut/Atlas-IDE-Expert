unit Atlas.Core.Tests.BoundaryCases;

// Daten von „Grenzfälle vorschlagen …“ (#2173) ohne IDE und VCL:
// - Vorschlag lesen: Antwort von atlas.server.boundaryCases [uri, zeile, höchstens] mit Parametern, Ergebnistyp
//   und Fällen (je Fall die Werte aller Parameter, der Grund und ob er in ein [TestCase] passt). Jeder Fall
//   bekommt einen Namen aus Parameter und Wert („AMenge 99“); nur Fälle, die passen, sind vorab gewählt.
// - Übernehmen: Anfrage an atlas.server.boundaryTests [uri, zeile, fälle, kommentar, platzhalter] mit den
//   gewählten Fällen bauen und die Antwort ({uri, method, appended, edit, reason}) lesen.
// - Heutiges Ergebnis: nach dem Lauf mit Platzhaltern die Werte, die DUnitX als „erhalten“ meldet, in die Spalte
//   AExpected der TestCase-Tabelle (#1879) eintragen; die übrigen Zeilen bleiben, wie sie sind.

interface

uses
  System.SysUtils,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.CaseTable;

type
  TAtlasBoundaryParameter = record
    Name: string;
    TypeName: string;
    /// <summary>ordinal, float, text, boolean, enum, reference, unknown.</summary>
    Kind: string;
  end;

  TAtlasBoundaryCase = record
    /// <summary>Index des Parameters, an dem der Fall hängt.</summary>
    Parameter: Integer;
    /// <summary>Wert des Parameters in der Schreibweise von [TestCase].</summary>
    Value: string;
    Reason: string;
    /// <summary>Zeile der Bedingung in der Unit (0-basiert).</summary>
    Line: Integer;
    /// <summary>Passt der Fall in ein [TestCase] (Werte ohne nil, Zeiger, Objekte)?</summary>
    TestCase: Boolean;
    /// <summary>Werte aller Parameter.</summary>
    Values: TArray<string>;
    /// <summary>Name des Testfalls, vorgeschlagen aus Parameter und Wert; änderbar.</summary>
    Name: string;
    /// <summary>Erwartetes Ergebnis; '' = noch offen.</summary>
    Expected: string;
    /// <summary>Gewählt zum Übernehmen.</summary>
    Use: Boolean;
  end;

  TAtlasBoundarySuggestion = record
    Uri: string;
    Routine: string;
    /// <summary>Ergebnistyp der Funktion; '' bei Prozeduren.</summary>
    ResultType: string;
    Line: Integer;
    /// <summary>Mehr Fälle als tests.boundaryCases.maxCases: der Rest fehlt.</summary>
    Truncated: Boolean;
    Parameters: TArray<TAtlasBoundaryParameter>;
    Cases: TArray<TAtlasBoundaryCase>;
    /// <summary>Funktion: Spalte Erwartet zeigen.</summary>
    function HasResult: Boolean;
  end;

  /// <summary>Antwort von atlas.server.boundaryTests.</summary>
  TAtlasBoundaryApplied = record
    /// <summary>Uri der Testunit.</summary>
    Uri: string;
    Method: string;
    /// <summary>An eine vorhandene Testmethode angefügt.</summary>
    Appended: Boolean;
    /// <summary>WorkspaceEdit als JSON; '' wenn nicht geschrieben werden kann.</summary>
    EditJson: string;
    Reason: string;
  end;

  /// <summary>Optionen der Übernahme: Kommentar über den Fällen und Platzhalter für offene Erwartungen.</summary>
  TAtlasBoundaryApply = record
    Comment: string;
    Placeholders: Boolean;
  end;

  TAtlasBoundaryCases = class
  public const
    cCommand = 'atlas.server.boundaryCases';
    cApplyCommand = 'atlas.server.boundaryTests';
    /// <summary>Name des Parameters der Testmethode mit dem erwarteten Ergebnis.</summary>
    cExpectedName = 'AExpected';
    cMaxNameLength = 40;
  public
    /// <summary>Argumente der Abfrage: [uri, zeile, höchstens].</summary>
    class function RequestJson(const AUri: string; ALine, AMax: Integer): string; static;
    /// <summary>Vorschlag aus der Antwort; False bei null oder unlesbar.</summary>
    class function Parse(const AJson: string; out ASuggestion: TAtlasBoundarySuggestion): Boolean; static;
    /// <summary>Name eines Falls: Parameter und Wert, ohne Zeichen, die DUnitX in Namen stören (Punkt, Klammern,
    /// Anführung); leerer Text heißt „leer“.</summary>
    class function CaseName(const AParameter, AValue: string): string; static;
    /// <summary>Gewählte Fälle, die in ein [TestCase] passen.</summary>
    class function Chosen(const ACases: TArray<TAtlasBoundaryCase>): TArray<TAtlasBoundaryCase>; static;
    /// <summary>Argumente der Übernahme der gewählten Fälle.</summary>
    class function ApplyJson(const AUri: string; ALine: Integer; const ACases: TArray<TAtlasBoundaryCase>;
      const AOptions: TAtlasBoundaryApply): string; static;
    /// <summary>Antwort der Übernahme; False bei unlesbar.</summary>
    class function ParseApplied(const AJson: string; out AApplied: TAtlasBoundaryApplied): Boolean; static;
    /// <summary>Spalte AExpected der Tabelle; -1 ohne.</summary>
    class function ExpectedColumn(const ATable: TAtlasTestCaseTable): Integer; static;
    /// <summary>Welche der gewählten Fälle warten auf das heutige Ergebnis (Erwartet leer)?</summary>
    class function OpenCases(const ACases: TArray<TAtlasBoundaryCase>): TArray<Boolean>; static;
    /// <summary>Zeilen der Tabelle mit den Werten des Laufs ARun in der Spalte AExpected. AOpen nennt für die
    /// letzten Length(AOpen) Zeilen (die gerade übernommenen), welche offen waren; nur sie bekommen einen Wert.
    /// AFilled zählt die eingetragenen Werte. Fälle ohne „erhalten“ (bestanden oder Ausnahme) behalten ihren
    /// Wert.</summary>
    class function TodayRows(const ATable: TAtlasTestCaseTable; const AOpen: TArray<Boolean>;
      const ARun: TTestRunResult; out AFilled: Integer): TArray<TAtlasTestCaseRow>; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json;

{ TAtlasBoundarySuggestion }

function TAtlasBoundarySuggestion.HasResult: Boolean;
begin
  Result := ResultType <> '';
end;

{ TAtlasBoundaryCases }

class function TAtlasBoundaryCases.RequestJson(const AUri: string; ALine, AMax: Integer): string;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(AUri);
    mArguments.Add(ALine);
    mArguments.Add(AMax);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

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

function ParameterOf(AObject: TJSONObject): TAtlasBoundaryParameter;
begin
  Result.Name := TJsonRead.Text(AObject, 'name');
  Result.TypeName := TJsonRead.Text(AObject, 'type');
  Result.Kind := TJsonRead.Text(AObject, 'kind');
end;

function CaseOf(AObject: TJSONObject; const AParameters: TArray<TAtlasBoundaryParameter>): TAtlasBoundaryCase;
var
  mName: string;
begin
  Result := Default(TAtlasBoundaryCase);
  Result.Parameter := TJsonRead.IntOr(AObject, 'parameter', -1);
  Result.Value := TJsonRead.Text(AObject, 'value');
  Result.Reason := TJsonRead.Text(AObject, 'reason');
  Result.Line := TJsonRead.IntOr(AObject, 'line', -1);
  Result.TestCase := TJsonRead.FlagOr(AObject, 'testCase', False);
  Result.Values := StringsOf(AObject, 'values');
  mName := '';
  if (Result.Parameter >= 0) and (Result.Parameter <= High(AParameters)) then
  begin
    mName := AParameters[Result.Parameter].Name;
  end;
  Result.Name := TAtlasBoundaryCases.CaseName(mName, Result.Value);
  Result.Use := Result.TestCase;
end;

class function TAtlasBoundaryCases.Parse(const AJson: string; out ASuggestion: TAtlasBoundarySuggestion): Boolean;
var
  mValue: TJSONValue;
  mObject, mItem: TJSONObject;
begin
  ASuggestion := Default(TAtlasBoundarySuggestion);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mObject := TJSONObject(mValue);
    ASuggestion.Uri := TJsonRead.Text(mObject, 'uri');
    ASuggestion.Routine := TJsonRead.Text(mObject, 'routine');
    ASuggestion.ResultType := TJsonRead.Text(mObject, 'resultType');
    ASuggestion.Line := TJsonRead.IntOr(mObject, 'line', -1);
    ASuggestion.Truncated := TJsonRead.FlagOr(mObject, 'truncated', False);
    for mItem in ObjectsOf(mObject, 'parameters') do
    begin
      ASuggestion.Parameters := ASuggestion.Parameters + [ParameterOf(mItem)];
    end;
    for mItem in ObjectsOf(mObject, 'cases') do
    begin
      ASuggestion.Cases := ASuggestion.Cases + [CaseOf(mItem, ASuggestion.Parameters)];
    end;
  finally
    mValue.Free;
  end;
end;

function NameChar(AChar: Char): Char;
begin
  Result := AChar;
  if CharInSet(AChar, ['.', '(', ')', '''', '"', ',', ';', '|', '#']) or (AChar < ' ') then
  begin
    Result := '_';
  end;
end;

class function TAtlasBoundaryCases.CaseName(const AParameter, AValue: string): string;
var
  mValue: string;
  mIndex: Integer;
begin
  mValue := AValue;
  if (mValue = '') or (mValue = '''''') then
  begin
    mValue := 'leer';
  end;
  for mIndex := 1 to Length(mValue) do
  begin
    mValue[mIndex] := NameChar(mValue[mIndex]);
  end;
  Result := Trim(Trim(AParameter) + ' ' + mValue);
  if Length(Result) > cMaxNameLength then
  begin
    Result := Trim(Copy(Result, 1, cMaxNameLength));
  end;
end;

class function TAtlasBoundaryCases.Chosen(const ACases: TArray<TAtlasBoundaryCase>): TArray<TAtlasBoundaryCase>;
var
  mCase: TAtlasBoundaryCase;
begin
  Result := nil;
  for mCase in ACases do
  begin
    if mCase.Use and mCase.TestCase then
    begin
      Result := Result + [mCase];
    end;
  end;
end;

function CaseToJson(const ACase: TAtlasBoundaryCase): TJSONObject;
var
  mValues: TJSONArray;
  mValue: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Trim(ACase.Name));
  mValues := TJSONArray.Create;
  Result.AddPair('values', mValues);
  for mValue in ACase.Values do
  begin
    mValues.Add(mValue);
  end;
  Result.AddPair('expected', Trim(ACase.Expected));
end;

class function TAtlasBoundaryCases.ApplyJson(const AUri: string; ALine: Integer;
  const ACases: TArray<TAtlasBoundaryCase>; const AOptions: TAtlasBoundaryApply): string;
var
  mArguments, mCases: TJSONArray;
  mCase: TAtlasBoundaryCase;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(AUri);
    mArguments.Add(ALine);
    mCases := TJSONArray.Create;
    mArguments.AddElement(mCases);
    for mCase in ACases do
    begin
      mCases.AddElement(CaseToJson(mCase));
    end;
    mArguments.Add(AOptions.Comment);
    mArguments.Add(AOptions.Placeholders);
    Result := mArguments.ToJSON([]);
  finally
    mArguments.Free;
  end;
end;

class function TAtlasBoundaryCases.ParseApplied(const AJson: string; out AApplied: TAtlasBoundaryApplied): Boolean;
var
  mValue, mEdit: TJSONValue;
  mObject: TJSONObject;
begin
  AApplied := Default(TAtlasBoundaryApplied);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mObject := TJSONObject(mValue);
    AApplied.Uri := TJsonRead.Text(mObject, 'uri');
    AApplied.Method := TJsonRead.Text(mObject, 'method');
    AApplied.Appended := TJsonRead.FlagOr(mObject, 'appended', False);
    AApplied.Reason := TJsonRead.Text(mObject, 'reason');
    mEdit := mObject.GetValue('edit');
    if mEdit is TJSONObject then
    begin
      AApplied.EditJson := mEdit.ToJSON([]);
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasBoundaryCases.ExpectedColumn(const ATable: TAtlasTestCaseTable): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ATable.Columns) do
  begin
    if SameText(ATable.Columns[mIndex].Name, cExpectedName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Erhaltener Wert des Falls ACase der Methode AMethod im Lauf ARun; False ohne.</summary>
function ActualOf(const ARun: TTestRunResult; const AMethod, ACase: string; out AActual: string): Boolean;
var
  mCase: TTestCaseResult;
begin
  for mCase in ARun.Cases do
  begin
    if SameText(mCase.Method, AMethod) and SameText(mCase.CaseName, ACase) and mCase.HasValues then
    begin
      AActual := mCase.Actual;
      Exit(True);
    end;
  end;
  AActual := '';
  Result := False;
end;

class function TAtlasBoundaryCases.OpenCases(const ACases: TArray<TAtlasBoundaryCase>): TArray<Boolean>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ACases));
  for mIndex := 0 to High(ACases) do
  begin
    Result[mIndex] := Trim(ACases[mIndex].Expected) = '';
  end;
end;

class function TAtlasBoundaryCases.TodayRows(const ATable: TAtlasTestCaseTable; const AOpen: TArray<Boolean>;
  const ARun: TTestRunResult; out AFilled: Integer): TArray<TAtlasTestCaseRow>;
var
  mColumn, mFirst, mIndex: Integer;
  mActual: string;
begin
  AFilled := 0;
  Result := Copy(ATable.Rows);
  mColumn := ExpectedColumn(ATable);
  if mColumn < 0 then
  begin
    Exit;
  end;
  mFirst := Length(Result) - Length(AOpen);
  for mIndex := Max(0, mFirst) to High(Result) do
  begin
    if AOpen[mIndex - mFirst] and ActualOf(ARun, ATable.Method, Result[mIndex].Name, mActual) then
    begin
      TAtlasTestCaseTables.SetValue(Result[mIndex], mColumn, mActual);
      Inc(AFilled);
    end;
  end;
end;

end.
