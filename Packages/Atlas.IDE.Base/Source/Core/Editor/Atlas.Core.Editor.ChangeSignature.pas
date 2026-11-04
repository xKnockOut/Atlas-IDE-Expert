unit Atlas.Core.Editor.ChangeSignature;

// Eingabemaske „Signatur ändern“ (#100) ohne VCL: Zeilen der neuen
// Parameterliste mit ihrer Herkunft in der alten, Hinzufügen, Entfernen,
// Verschieben und Umbenennen, die Vorschau der neuen Signatur, die Prüfung
// vor dem Absenden und das JSON für atlas.server.changeSignature. Die
// Prüfung ist dieselbe wie im Server (Atlas.Common.Editing.ChangeSignature),
// damit der Dialog Fehler schon vor dem Absenden zeigt; sie liefert die Art
// des Fehlers, den Text wählt die Oberfläche in ihrer Sprache.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  /// <summary>Erster Fehler der neuen Liste.</summary>
  TAtlasSignatureProblem = (None, BadName, Duplicate, MissingType, MissingValue, AfterDefault, TypesFixed);
  {$SCOPEDENUMS OFF}

  TAtlasSignatureRow = record
    /// <summary>Stelle in der alten Liste; -1 = neu.</summary>
    Origin: Integer;
    Name: string;
    TypeName: string;
    Modifier: string;
    /// <summary>Standardwert aus der alten Deklaration; neue Parameter haben keinen.</summary>
    DefaultValue: string;
    /// <summary>Neue Parameter: Wert für die bisherigen Aufrufer.</summary>
    Value: string;
    function IsNew: Boolean;
  end;

  TAtlasSignatureModel = class
  private
    FName: string;
    FContainer: string;
    FKind: string;
    FResultType: string;
    FOriginal: TArray<TAtlasSignatureRow>;
    FRows: TArray<TAtlasSignatureRow>;
    FOverload: Boolean;
    FOverloadPossible: Boolean;
    FVirtualOverload: Boolean;
    FBoundEvent: string;
    FEventFixed: Boolean;
    FMembers: Integer;
    FWarnings: TArray<string>;
    function GetRow(AIndex: Integer): TAtlasSignatureRow;
    function GetCount: Integer;
  public
    /// <summary>Aus der Antwort von atlas.server.changeSignature.prepare.</summary>
    constructor Create(const APrepared: TJSONObject);
    /// <summary>Neuer Parameter hinter AIndex (-1 = am Anfang); Index der neuen Zeile.</summary>
    function Add(AIndex: Integer; const AName, ATypeName, AModifier, AValue: string): Integer;
    procedure Remove(AIndex: Integer);
    /// <summary>Um ADelta Stellen verschieben; False am Rand.</summary>
    function MoveRow(AIndex, ADelta: Integer): Boolean;
    procedure Rename(AIndex: Integer; const AName: string);
    /// <summary>Typ, Modifizierer und Wert; nur bei neuen Parametern.</summary>
    procedure Change(AIndex: Integer; const ATypeName, AModifier, AValue: string);
    /// <summary>Wie die Deklaration danach aussieht, ohne Standardwerte neuer Parameter.</summary>
    function Preview: string;
    /// <summary>Erster Fehler (Namen, Typen, Werte, Standardwerte, fester Ereignistyp); AName: betroffener
    /// Parameter.</summary>
    function Validate(out AName: string): TAtlasSignatureProblem; overload;
    function Validate: TAtlasSignatureProblem; overload;
    /// <summary>Hat sich etwas geändert?</summary>
    function Changed: Boolean;
    /// <summary>Werden Parameter hinzugefügt?</summary>
    function AddsParameters: Boolean;
    /// <summary>Argument für atlas.server.changeSignature. Der Aufrufer übernimmt das Objekt.</summary>
    function RequestJson: TJSONObject;
    property Name: string read FName;
    property Container: string read FContainer;
    property Kind: string read FKind;
    property ResultType: string read FResultType;
    property Rows[AIndex: Integer]: TAtlasSignatureRow read GetRow; default;
    property Count: Integer read GetCount;
    /// <summary>Neue Parameter als Überladung (True) oder alle Aufrufer ändern.</summary>
    property UseOverload: Boolean read FOverload write FOverload;
    /// <summary>False bei Interface-Methoden und gebundenen Handlern.</summary>
    property OverloadPossible: Boolean read FOverloadPossible;
    property VirtualOverload: Boolean read FVirtualOverload write FVirtualOverload;
    property BoundEvent: string read FBoundEvent;
    /// <summary>Ereignistyp aus einer Bibliothek: nur Umbenennen.</summary>
    property EventFixed: Boolean read FEventFixed;
    property Members: Integer read FMembers;
    property Warnings: TArray<string> read FWarnings;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Core.Editor.LinkedEditing;

function IsName(const AName: string): Boolean;
begin
  Result := IsValidIdent(AName) and not TAtlasLinkedEditing.IsReserved(AName);
end;

{ TAtlasSignatureRow }

function TAtlasSignatureRow.IsNew: Boolean;
begin
  Result := Origin < 0;
end;

{ TAtlasSignatureModel }

constructor TAtlasSignatureModel.Create(const APrepared: TJSONObject);
var
  Items: TJSONArray;
  Item: TJSONValue;
  Row: TAtlasSignatureRow;
  Index: Integer;
begin
  inherited Create;
  FOverloadPossible := True;
  FOverload := True;
  if APrepared = nil then
  begin
    Exit;
  end;
  FName := APrepared.GetValue<string>('name', '');
  FContainer := APrepared.GetValue<string>('container', '');
  FKind := APrepared.GetValue<string>('kind', 'procedure');
  FResultType := APrepared.GetValue<string>('resultType', '');
  FOverloadPossible := APrepared.GetValue<Boolean>('overloadPossible', True);
  FOverload := SameText(APrepared.GetValue<string>('newParameter', 'overload'), 'overload') and FOverloadPossible;
  FVirtualOverload := APrepared.GetValue<Boolean>('virtualOverload', False);
  FBoundEvent := APrepared.GetValue<string>('boundEvent', '');
  FEventFixed := APrepared.GetValue<Boolean>('eventFixed', False);
  FMembers := APrepared.GetValue<Integer>('members', 1);
  Items := APrepared.GetValue('parameters') as TJSONArray;
  Index := 0;
  if Items <> nil then
  begin
    for Item in Items do
    begin
      if not (Item is TJSONObject) then
      begin
        Continue;
      end;
      Row := Default(TAtlasSignatureRow);
      Row.Origin := Index;
      Row.Name := TJSONObject(Item).GetValue<string>('name', '');
      Row.TypeName := TJSONObject(Item).GetValue<string>('type', '');
      Row.Modifier := TJSONObject(Item).GetValue<string>('modifier', '');
      Row.DefaultValue := TJSONObject(Item).GetValue<string>('default', '');
      FOriginal := FOriginal + [Row];
      Inc(Index);
    end;
  end;
  FRows := Copy(FOriginal);
  Items := APrepared.GetValue('warnings') as TJSONArray;
  if Items <> nil then
  begin
    for Item in Items do
    begin
      FWarnings := FWarnings + [Item.Value];
    end;
  end;
end;

function TAtlasSignatureModel.GetCount: Integer;
begin
  Result := Length(FRows);
end;

function TAtlasSignatureModel.GetRow(AIndex: Integer): TAtlasSignatureRow;
begin
  Result := FRows[AIndex];
end;

function TAtlasSignatureModel.Add(AIndex: Integer; const AName, ATypeName, AModifier, AValue: string): Integer;
var
  Row: TAtlasSignatureRow;
begin
  Row := Default(TAtlasSignatureRow);
  Row.Origin := -1;
  Row.Name := Trim(AName);
  Row.TypeName := Trim(ATypeName);
  Row.Modifier := LowerCase(Trim(AModifier));
  Row.Value := Trim(AValue);
  Result := AIndex + 1;
  if Result < 0 then
  begin
    Result := 0;
  end;
  if Result > Length(FRows) then
  begin
    Result := Length(FRows);
  end;
  Insert(Row, FRows, Result);
end;

procedure TAtlasSignatureModel.Remove(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex <= High(FRows)) then
  begin
    Delete(FRows, AIndex, 1);
  end;
end;

function TAtlasSignatureModel.MoveRow(AIndex, ADelta: Integer): Boolean;
var
  Target: Integer;
  Row: TAtlasSignatureRow;
begin
  Target := AIndex + ADelta;
  Result := (AIndex >= 0) and (AIndex <= High(FRows)) and (Target >= 0) and (Target <= High(FRows));
  if not Result then
  begin
    Exit;
  end;
  Row := FRows[AIndex];
  Delete(FRows, AIndex, 1);
  Insert(Row, FRows, Target);
end;

procedure TAtlasSignatureModel.Rename(AIndex: Integer; const AName: string);
begin
  if (AIndex >= 0) and (AIndex <= High(FRows)) then
  begin
    FRows[AIndex].Name := Trim(AName);
  end;
end;

procedure TAtlasSignatureModel.Change(AIndex: Integer; const ATypeName, AModifier, AValue: string);
begin
  if (AIndex < 0) or (AIndex > High(FRows)) or not FRows[AIndex].IsNew then
  begin
    Exit;
  end;
  FRows[AIndex].TypeName := Trim(ATypeName);
  FRows[AIndex].Modifier := LowerCase(Trim(AModifier));
  FRows[AIndex].Value := Trim(AValue);
end;

function TAtlasSignatureModel.Preview: string;
var
  Row: TAtlasSignatureRow;
  Parts: TArray<string>;
  Part: string;
begin
  Parts := nil;
  for Row in FRows do
  begin
    Part := Row.Name;
    if Row.Modifier <> '' then
    begin
      Part := Row.Modifier + ' ' + Part;
    end;
    if Row.TypeName <> '' then
    begin
      Part := Part + ': ' + Row.TypeName;
    end;
    if Row.DefaultValue <> '' then
    begin
      Part := Part + ' = ' + Row.DefaultValue;
    end;
    Parts := Parts + [Part];
  end;
  Result := FName;
  if FContainer <> '' then
  begin
    Result := FContainer + '.' + Result;
  end;
  Result := FKind + ' ' + Result;
  if Length(Parts) > 0 then
  begin
    Result := Result + '(' + string.Join('; ', Parts) + ')';
  end;
  if FResultType <> '' then
  begin
    Result := Result + ': ' + FResultType;
  end;
end;

function TAtlasSignatureModel.AddsParameters: Boolean;
var
  Row: TAtlasSignatureRow;
begin
  for Row in FRows do
  begin
    if Row.IsNew then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasSignatureModel.Changed: Boolean;
var
  Index: Integer;
begin
  Result := Length(FRows) <> Length(FOriginal);
  if not Result then
  begin
    for Index := 0 to High(FRows) do
    begin
      if (FRows[Index].Origin <> Index) or not SameStr(FRows[Index].Name, FOriginal[Index].Name) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

function TAtlasSignatureModel.Validate: TAtlasSignatureProblem;
var
  mName: string;
begin
  Result := Validate(mName);
end;

/// <summary>Name schon in einer früheren Zeile als AIndex.</summary>
function IsDuplicate(const ARows: TArray<TAtlasSignatureRow>; AIndex: Integer): Boolean;
var
  mOther: Integer;
begin
  Result := False;
  for mOther := 0 to AIndex - 1 do
  begin
    Result := Result or SameText(ARows[mOther].Name, ARows[AIndex].Name);
  end;
end;

/// <summary>Problem der Zeile AIndex; ASeenDefault merkt sich, ob ein bestehender Parameter einen Vorgabewert
/// hat (neue Parameter dürfen danach nicht ohne einen stehen).</summary>
function RowProblem(const ARows: TArray<TAtlasSignatureRow>; AIndex: Integer;
  var ASeenDefault: Boolean): TAtlasSignatureProblem;
var
  mRow: TAtlasSignatureRow;
begin
  mRow := ARows[AIndex];
  Result := TAtlasSignatureProblem.None;
  if not IsName(mRow.Name) then
  begin
    Result := TAtlasSignatureProblem.BadName;
  end
  else if IsDuplicate(ARows, AIndex) then
  begin
    Result := TAtlasSignatureProblem.Duplicate;
  end
  else if not mRow.IsNew then
  begin
    ASeenDefault := ASeenDefault or (mRow.DefaultValue <> '');
  end
  else if mRow.TypeName = '' then
  begin
    Result := TAtlasSignatureProblem.MissingType;
  end
  else if mRow.Value = '' then
  begin
    Result := TAtlasSignatureProblem.MissingValue;
  end
  else if ASeenDefault then
  begin
    Result := TAtlasSignatureProblem.AfterDefault;
  end;
end;

function TAtlasSignatureModel.Validate(out AName: string): TAtlasSignatureProblem;
var
  mIndex: Integer;
  mSeenDefault, mTypesChanged: Boolean;
begin
  Result := TAtlasSignatureProblem.None;
  AName := '';
  mSeenDefault := False;
  mTypesChanged := Length(FRows) <> Length(FOriginal);
  mIndex := 0;
  while (Result = TAtlasSignatureProblem.None) and (mIndex <= High(FRows)) do
  begin
    AName := FRows[mIndex].Name;
    mTypesChanged := mTypesChanged or (FRows[mIndex].Origin <> mIndex);
    Result := RowProblem(FRows, mIndex, mSeenDefault);
    Inc(mIndex);
  end;
  if Result = TAtlasSignatureProblem.None then
  begin
    AName := FBoundEvent;
    if mTypesChanged and FEventFixed then
    begin
      Result := TAtlasSignatureProblem.TypesFixed;
    end
    else
    begin
      AName := '';
    end;
  end;
end;

function TAtlasSignatureModel.RequestJson: TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Row: TAtlasSignatureRow;
begin
  Items := TJSONArray.Create;
  for Row in FRows do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('origin', TJSONNumber.Create(Row.Origin));
    Item.AddPair('name', Row.Name);
    if Row.IsNew then
    begin
      Item.AddPair('type', Row.TypeName);
      Item.AddPair('modifier', Row.Modifier);
      Item.AddPair('value', Row.Value);
    end;
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('parameters', Items);
  if FOverload and FOverloadPossible then
  begin
    Result.AddPair('newParameter', 'overload');
  end
  else
  begin
    Result.AddPair('newParameter', 'updateCallers');
  end;
  Result.AddPair('virtualOverload', TJSONBool.Create(FVirtualOverload));
end;

end.
