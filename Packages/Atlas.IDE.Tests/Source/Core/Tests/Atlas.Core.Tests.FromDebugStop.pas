unit Atlas.Core.Tests.FromDebugStop;

// „Test daraus anlegen …“ (#1873) ohne IDE: Was das Modul Tests zwischen dem
// Halt des Debuggers und dem Befehl atlas.server.testFromDebugStop braucht.
//   - Argumente der Kopfzeile des Aufrufstacks („Unit1.TGewicht.Parse('12,5
//     kg', 3)“) für Rahmen, in denen der Debugger nicht auswerten kann.
//   - Antwort von "describe" lesen: Ziel, Parameter und Felder als Zeilen,
//     vorgeschlagener Name; Werte aus dem Debugger bleiben über die zweite
//     Antwort erhalten.
//   - Argumente für "describe" und "create" bauen: nur gewählte Zeilen mit
//     Wert, Art (funktioniert bzw. wirft), erwarteter Wert, Name.
//   - Antwort von "create" lesen (Datei, Name, Grund) und die Zeile des neuen
//     Tests finden.
// Felder wertet der Debugger als Self.FName aus.

interface

type
  /// <summary>Parameter oder Feld der getesteten Methode mit dem Wert beim Halt.</summary>
  TAtlasStopValueRow = record
    Name: string;
    TypeName: string;
    /// <summary>const, var, out oder ''.</summary>
    Modifier: string;
    /// <summary>Feld der Klasse statt Parameter.</summary>
    Field: Boolean;
    /// <summary>Der Test kann das Feld setzen (public, published); Parameter immer.</summary>
    Accessible: Boolean;
    /// <summary>Text, wie der Debugger ihn zeigt; '' = nicht gelesen.</summary>
    Text: string;
    /// <summary>Delphi-Literal laut Server; '' vor der zweiten Antwort.</summary>
    Literal: string;
    /// <summary>Der Server übernimmt den Wert nicht (Objekt, Zeiger, Record, zu langes Array): TODO im Test.</summary>
    Todo: Boolean;
    /// <summary>Im Test verwenden (Dialog).</summary>
    Chosen: Boolean;
  end;

  TAtlasStopValueRows = TArray<TAtlasStopValueRow>;

  /// <summary>Antwort auf "describe".</summary>
  TAtlasStopDescription = record
    /// <summary>Warum es keinen Test gibt; '' wenn alles da ist.</summary>
    Reason: string;
    /// <summary>„TGewicht.Parse“.</summary>
    Target: string;
    ClassName: string;
    Method: string;
    ClassMethod: Boolean;
    ResultType: string;
    TestUnit: string;
    TestUnitExists: Boolean;
    TestName: string;
    Rows: TAtlasStopValueRows;
    function ParameterCount: Integer;
  end;

  /// <summary>Was im Dialog gewählt wurde bzw. vom Halt kommt.</summary>
  TAtlasStopChoice = record
    /// <summary>Soll die Exception ExceptionClass werfen statt zu funktionieren.</summary>
    Raises: Boolean;
    Expected: string;
    ExceptionClass: string;
    TestName: string;
    MaxArray: Integer;
    StoppedAt: string;
  end;

  /// <summary>Antwort auf "create".</summary>
  TAtlasStopCreated = record
    Reason: string;
    Uri: string;
    TestName: string;
    Fixture: string;
  end;

  TAtlasTestFromDebugStop = class
  public const
    cServerCommand = 'atlas.server.testFromDebugStop';
    cModeDescribe = 'describe';
    cModeCreate = 'create';
  public
    /// <summary>Argumente in den äußeren Klammern von AHeader, getrennt an Kommas außerhalb von Strings und
    /// Klammern; ohne Klammern leer.</summary>
    class function HeaderArguments(const AHeader: string): TArray<string>; static;
    /// <summary>Antwort AJson auf "describe"; AFallbackReason, wenn sie fehlt oder kaputt ist.</summary>
    class function ReadDescription(const AJson, AFallbackReason: string): TAtlasStopDescription; static;
    /// <summary>Texte und Auswahl aus AOld in die neuere Antwort ANew übernehmen (gleicher Name, gleiche Art).
    /// </summary>
    class procedure KeepValues(var ANew: TAtlasStopDescription; const AOld: TAtlasStopDescription); static;
    /// <summary>Werte der Parameter der Reihe nach aus AArguments (Kopfzeile); Felder bleiben ungelesen.</summary>
    class procedure TakeArguments(var ADescription: TAtlasStopDescription; const AArguments: TArray<string>);
      static;
    /// <summary>Was der Debugger für ARow auswertet: Name bzw. Self.Name.</summary>
    class function Expression(const ARow: TAtlasStopValueRow): string; static;
    /// <summary>Vorauswahl: Parameter mit Wert immer, Felder mit Wert, wenn der Test sie setzen kann und der
    /// Server ein Literal hat.</summary>
    class procedure Preselect(var ADescription: TAtlasStopDescription); static;
    /// <summary>JSON-Array [uri, zeile, anfrage] für AMode; nur gewählte Zeilen mit Wert.</summary>
    class function Arguments(const AUri: string; ALine: Integer; const AMode: string;
      const ADescription: TAtlasStopDescription; const AChoice: TAtlasStopChoice): string; static;
    /// <summary>Antwort AJson auf "create"; ohne "edit" steht der Grund in Reason (sonst AFallbackReason).
    /// </summary>
    class function ReadCreated(const AJson, AFallbackReason: string): TAtlasStopCreated; static;
    /// <summary>Zeile (0-basiert) des Rumpfs „procedure AFixture.ATestName“ in AText; -1 ohne.</summary>
    class function TestLine(const AText, AFixture, ATestName: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json;

const
  /// <summary>Art des Tests für den Server: funktioniert bzw. wirft.</summary>
  cKinds: array[Boolean] of string = ('works', 'raises');

{ TAtlasStopDescription }

function TAtlasStopDescription.ParameterCount: Integer;
var
  mRow: TAtlasStopValueRow;
begin
  Result := 0;
  for mRow in Rows do
  begin
    if not mRow.Field then
    begin
      Inc(Result);
    end;
  end;
end;

{ Kopfzeile }

/// <summary>Index nach dem String, der bei AIndex mit ' beginnt ('' im String zählt als ein Zeichen).</summary>
function SkipString(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while Result <= Length(AText) do
  begin
    if AText[Result] <> '''' then
    begin
      Inc(Result);
    end
    else if (Result < Length(AText)) and (AText[Result + 1] = '''') then
    begin
      Inc(Result, 2);
    end
    else
    begin
      Exit(Result + 1);
    end;
  end;
end;

/// <summary>Neue Tiefe nach dem Zeichen AChar.</summary>
function DepthAfter(AChar: Char; ADepth: Integer): Integer;
begin
  Result := ADepth;
  case AChar of
    '(', '[':
      Inc(Result);
    ')', ']':
      Dec(Result);
  end;
end;

class function TAtlasTestFromDebugStop.HeaderArguments(const AHeader: string): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
begin
  Result := nil;
  mStart := Pos('(', AHeader);
  if mStart = 0 then
  begin
    Exit;
  end;
  mIndex := mStart + 1;
  mDepth := 0;
  while mIndex <= Length(AHeader) do
  begin
    if AHeader[mIndex] = '''' then
    begin
      mIndex := SkipString(AHeader, mIndex);
      Continue;
    end;
    if (mDepth = 0) and CharInSet(AHeader[mIndex], [',', ')']) then
    begin
      if (AHeader[mIndex] = ',') or (Trim(Copy(AHeader, mStart + 1, mIndex - mStart - 1)) <> '') or
        (Result <> nil) then
      begin
        Result := Result + [Trim(Copy(AHeader, mStart + 1, mIndex - mStart - 1))];
      end;
      if AHeader[mIndex] = ')' then
      begin
        Exit;
      end;
      mStart := mIndex;
    end;
    mDepth := DepthAfter(AHeader[mIndex], mDepth);
    Inc(mIndex);
  end;
end;

{ Antworten }

function ReadRows(AObject: TJSONObject; const AName: string; AField: Boolean): TAtlasStopValueRows;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mRow: TAtlasStopValueRow;
begin
  Result := nil;
  mItems := TJsonRead.Items(AObject, AName);
  if mItems = nil then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mRow := Default(TAtlasStopValueRow);
    mRow.Name := TJsonRead.Text(TJSONObject(mItem), 'name');
    mRow.TypeName := TJsonRead.Text(TJSONObject(mItem), 'type');
    mRow.Modifier := TJsonRead.Text(TJSONObject(mItem), 'modifier');
    mRow.Accessible := TJsonRead.FlagOr(TJSONObject(mItem), 'accessible', True);
    mRow.Literal := TJsonRead.Text(TJSONObject(mItem), 'literal');
    mRow.Todo := TJsonRead.Flag(TJSONObject(mItem), 'todo');
    mRow.Field := AField;
    Result := Result + [mRow];
  end;
end;

class function TAtlasTestFromDebugStop.ReadDescription(const AJson,
  AFallbackReason: string): TAtlasStopDescription;
var
  mValue: TJSONValue;
  mObject: TJSONObject;
begin
  Result := Default(TAtlasStopDescription);
  Result.Reason := AFallbackReason;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mObject := TJsonRead.AsObject(mValue);
    if mObject = nil then
    begin
      Exit;
    end;
    Result.Reason := TJsonRead.Text(mObject, 'reason');
    Result.Target := TJsonRead.Text(mObject, 'target');
    Result.ClassName := TJsonRead.Text(mObject, 'className');
    Result.Method := TJsonRead.Text(mObject, 'method');
    Result.ClassMethod := TJsonRead.Flag(mObject, 'classMethod');
    Result.ResultType := TJsonRead.Text(mObject, 'resultType');
    Result.TestUnit := TJsonRead.Text(mObject, 'testUnit');
    Result.TestUnitExists := TJsonRead.Flag(mObject, 'testUnitExists');
    Result.TestName := TJsonRead.Text(mObject, 'testName');
    Result.Rows := ReadRows(mObject, 'parameters', False) + ReadRows(mObject, 'fields', True);
    if (Result.Reason = '') and (Result.Method = '') then
    begin
      Result.Reason := AFallbackReason;
    end;
  finally
    mValue.Free;
  end;
end;

class procedure TAtlasTestFromDebugStop.KeepValues(var ANew: TAtlasStopDescription;
  const AOld: TAtlasStopDescription);
var
  mIndex: Integer;
  mOld: TAtlasStopValueRow;
begin
  for mIndex := 0 to High(ANew.Rows) do
  begin
    for mOld in AOld.Rows do
    begin
      if (mOld.Field = ANew.Rows[mIndex].Field) and SameText(mOld.Name, ANew.Rows[mIndex].Name) then
      begin
        ANew.Rows[mIndex].Text := mOld.Text;
        ANew.Rows[mIndex].Chosen := mOld.Chosen;
      end;
    end;
  end;
end;

class procedure TAtlasTestFromDebugStop.TakeArguments(var ADescription: TAtlasStopDescription;
  const AArguments: TArray<string>);
var
  mIndex, mArgument: Integer;
begin
  mArgument := 0;
  for mIndex := 0 to High(ADescription.Rows) do
  begin
    if ADescription.Rows[mIndex].Field then
    begin
      Continue;
    end;
    if mArgument > High(AArguments) then
    begin
      Exit;
    end;
    ADescription.Rows[mIndex].Text := AArguments[mArgument];
    Inc(mArgument);
  end;
end;

class function TAtlasTestFromDebugStop.Expression(const ARow: TAtlasStopValueRow): string;
begin
  Result := ARow.Name;
  if ARow.Field then
  begin
    Result := 'Self.' + ARow.Name;
  end;
end;

class procedure TAtlasTestFromDebugStop.Preselect(var ADescription: TAtlasStopDescription);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ADescription.Rows) do
  begin
    ADescription.Rows[mIndex].Chosen := (ADescription.Rows[mIndex].Text <> '') and
      (not ADescription.Rows[mIndex].Field or
      (ADescription.Rows[mIndex].Accessible and not ADescription.Rows[mIndex].Todo));
  end;
end;

/// <summary>[{name, text}] der gewählten Zeilen mit Wert und Art AField.</summary>
function ValuesJson(const ARows: TAtlasStopValueRows; AField: Boolean): TJSONArray;
var
  mRow: TAtlasStopValueRow;
begin
  Result := TJSONArray.Create;
  for mRow in ARows do
  begin
    if (mRow.Field = AField) and mRow.Chosen and (mRow.Text <> '') then
    begin
      Result.AddElement(TJSONObject.Create.AddPair('name', mRow.Name).AddPair('text', mRow.Text));
    end;
  end;
end;

class function TAtlasTestFromDebugStop.Arguments(const AUri: string; ALine: Integer; const AMode: string;
  const ADescription: TAtlasStopDescription; const AChoice: TAtlasStopChoice): string;
var
  mValues: TJSONArray;
  mRequest: TJSONObject;
begin
  mRequest := TJSONObject.Create;
  mRequest.AddPair('mode', AMode);
  mRequest.AddPair('parameters', ValuesJson(ADescription.Rows, False));
  mRequest.AddPair('fields', ValuesJson(ADescription.Rows, True));
  mRequest.AddPair('kind', cKinds[AChoice.Raises]);
  mRequest.AddPair('expected', AChoice.Expected);
  mRequest.AddPair('exceptionClass', AChoice.ExceptionClass);
  mRequest.AddPair('testName', AChoice.TestName);
  mRequest.AddPair('maxArray', TJSONNumber.Create(AChoice.MaxArray));
  mRequest.AddPair('stoppedAt', AChoice.StoppedAt);
  mValues := TJSONArray.Create;
  try
    mValues.Add(AUri);
    mValues.Add(ALine);
    mValues.AddElement(mRequest);
    Result := mValues.ToJSON([]);
  finally
    mValues.Free;
  end;
end;

class function TAtlasTestFromDebugStop.ReadCreated(const AJson, AFallbackReason: string): TAtlasStopCreated;
var
  mValue: TJSONValue;
  mObject: TJSONObject;
begin
  Result := Default(TAtlasStopCreated);
  Result.Reason := AFallbackReason;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mObject := TJsonRead.AsObject(mValue);
    if mObject = nil then
    begin
      Exit;
    end;
    Result.Uri := TJsonRead.Text(mObject, 'uri');
    Result.TestName := TJsonRead.Text(mObject, 'testName');
    Result.Fixture := TJsonRead.Text(mObject, 'fixture');
    if TJsonRead.Obj(mObject, 'edit') <> nil then
    begin
      Result.Reason := '';
    end
    else if TJsonRead.Text(mObject, 'reason') <> '' then
    begin
      Result.Reason := TJsonRead.Text(mObject, 'reason');
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasTestFromDebugStop.TestLine(const AText, AFixture, ATestName: string): Integer;
var
  mLines: TArray<string>;
  mWanted, mLine: string;
  mIndex: Integer;
begin
  Result := -1;
  mWanted := LowerCase('procedure ' + AFixture + '.' + ATestName);
  mLines := AText.Replace(#13#10, #10).Split([#10]);
  for mIndex := 0 to High(mLines) do
  begin
    mLine := LowerCase(Trim(mLines[mIndex]));
    if mLine.StartsWith(mWanted) and ((Length(mLine) = Length(mWanted)) or
      CharInSet(mLine.Chars[Length(mWanted)], [';', '(', ' '])) then
    begin
      Exit(mIndex);
    end;
  end;
end;

end.
