unit Atlas.Core.Lsp.IdeMembers;

// Mitglieder der Typen aus Packages ohne Quelltext für den Server (atlas/ideMembers). Der Server fragt nach dem
// Index mit atlas/ideMembersWanted nach den Units, die er nur aus atlas/ideTypes kennt; das Plugin antwortet je
// Unit mit Vorfahr, Interfaces, Aufzählungswerten und den Mitgliedern samt Typen und Parametern. Daraus baut der
// Server eine Ersatz-Unit für Hover, Vervollständigung und Parameterhilfe. Hier ohne Open Tools API und RTTI:
// die Datensätze und ihr JSON; gelesen wird die RTTI in Atlas.IDE.CodeInsight.IdeTypes.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  /// <summary>Parameter einer Methode oder einer Array-Property.</summary>
  TAtlasIdeParam = record
    Name: string;
    /// <summary>Typ mit Unit (System.Integer); '' bei untypisierten Parametern.</summary>
    TypeName: string;
    /// <summary>const, var, out oder ''.</summary>
    Flag: string;
    class function Make(const AName, ATypeName, AFlag: string): TAtlasIdeParam; static;
  end;

  /// <summary>Feld, Property oder Methode eines Typs.</summary>
  TAtlasIdeMember = record
    /// <summary>field, property, procedure, function, constructor, destructor.</summary>
    Kind: string;
    Name: string;
    /// <summary>Typ des Felds bzw. der Property, Ergebnis der Funktion; mit Unit.</summary>
    TypeName: string;
    /// <summary>protected, public oder published.</summary>
    Visibility: string;
    /// <summary>Klassenmethode (class procedure/function).</summary>
    IsStatic: Boolean;
    /// <summary>Default-Property einer Array-Property.</summary>
    IsDefault: Boolean;
    Params: TArray<TAtlasIdeParam>;
    /// <summary>Indexparameter einer Array-Property.</summary>
    Index: TArray<TAtlasIdeParam>;
  end;

  /// <summary>Ein Typ mit seinen Mitgliedern.</summary>
  TAtlasIdeTypeDetail = record
    UnitName: string;
    Name: string;
    /// <summary>class, interface, record oder enum.</summary>
    Kind: string;
    /// <summary>Vorfahr mit Unit; '' ohne.</summary>
    Parent: string;
    /// <summary>Implementierte Interfaces mit Unit.</summary>
    Interfaces: TArray<string>;
    /// <summary>Werte eines Aufzählungstyps.</summary>
    Values: TArray<string>;
    Members: TArray<TAtlasIdeMember>;
  end;

  TAtlasIdeMembers = class
  public const
    cWantedMethod = 'atlas/ideMembersWanted';
    cMethod = 'atlas/ideMembers';
  public
    /// <summary>Units aus den Parametern von atlas/ideMembersWanted ({"units": ["A", "B"]}); leer bei anderem
    /// Aufbau.</summary>
    class function WantedUnits(const AParams: TJSONValue): TArray<string>; static;
    /// <summary>Parameter von atlas/ideMembers: je Unit ein Eintrag in der Reihenfolge des ersten Vorkommens.
    /// Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const ADetails: TArray<TAtlasIdeTypeDetail>): TJSONObject; static;
  end;

implementation

{ TAtlasIdeParam }

class function TAtlasIdeParam.Make(const AName, ATypeName, AFlag: string): TAtlasIdeParam;
begin
  Result.Name := AName;
  Result.TypeName := ATypeName;
  Result.Flag := AFlag;
end;

{ TAtlasIdeMembers }

class function TAtlasIdeMembers.WantedUnits(const AParams: TJSONValue): TArray<string>;
var
  mUnits: TJSONArray;
  mValue: TJSONValue;
begin
  Result := nil;
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('units', mUnits)) then
  begin
    Exit;
  end;
  for mValue in mUnits do
  begin
    // TJSONNumber erbt von TJSONString.
    if (mValue is TJSONString) and not (mValue is TJSONNumber) and (Trim(mValue.Value) <> '') then
    begin
      Result := Result + [Trim(mValue.Value)];
    end;
  end;
end;

/// <summary>Liste "params" bzw. "index".</summary>
function ParamsJson(const AParams: TArray<TAtlasIdeParam>): TJSONArray;
var
  mParam: TAtlasIdeParam;
  mObject: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mParam in AParams do
  begin
    mObject := TJSONObject.Create;
    mObject.AddPair('name', mParam.Name);
    if mParam.TypeName <> '' then
    begin
      mObject.AddPair('type', mParam.TypeName);
    end;
    if mParam.Flag <> '' then
    begin
      mObject.AddPair('flag', mParam.Flag);
    end;
    Result.AddElement(mObject);
  end;
end;

function MemberJson(const AMember: TAtlasIdeMember): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', AMember.Kind);
  Result.AddPair('name', AMember.Name);
  if AMember.TypeName <> '' then
  begin
    Result.AddPair('type', AMember.TypeName);
  end;
  Result.AddPair('visibility', AMember.Visibility);
  if AMember.IsStatic then
  begin
    Result.AddPair('static', TJSONTrue.Create);
  end;
  if AMember.IsDefault then
  begin
    Result.AddPair('default', TJSONTrue.Create);
  end;
  if Length(AMember.Params) > 0 then
  begin
    Result.AddPair('params', ParamsJson(AMember.Params));
  end;
  if Length(AMember.Index) > 0 then
  begin
    Result.AddPair('index', ParamsJson(AMember.Index));
  end;
end;

function StringsJson(const AValues: TArray<string>): TJSONArray;
var
  mValue: string;
begin
  Result := TJSONArray.Create;
  for mValue in AValues do
  begin
    Result.Add(mValue);
  end;
end;

function DetailJson(const ADetail: TAtlasIdeTypeDetail): TJSONObject;
var
  mMembers: TJSONArray;
  mMember: TAtlasIdeMember;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ADetail.Name);
  Result.AddPair('kind', ADetail.Kind);
  if ADetail.Parent <> '' then
  begin
    Result.AddPair('parent', ADetail.Parent);
  end;
  if Length(ADetail.Interfaces) > 0 then
  begin
    Result.AddPair('interfaces', StringsJson(ADetail.Interfaces));
  end;
  if Length(ADetail.Values) > 0 then
  begin
    Result.AddPair('values', StringsJson(ADetail.Values));
  end;
  if Length(ADetail.Members) > 0 then
  begin
    mMembers := TJSONArray.Create;
    for mMember in ADetail.Members do
    begin
      mMembers.AddElement(MemberJson(mMember));
    end;
    Result.AddPair('members', mMembers);
  end;
end;

/// <summary>Liste "types" der Unit AUnit, bei Bedarf als neuer Eintrag in AOrder angelegt.</summary>
function UnitTypes(AUnits: TDictionary<string, TJSONArray>; AOrder: TJSONArray; const AUnit: string): TJSONArray;
var
  mEntry: TJSONObject;
begin
  if AUnits.TryGetValue(UpperCase(AUnit), Result) then
  begin
    Exit;
  end;
  Result := TJSONArray.Create;
  mEntry := TJSONObject.Create;
  mEntry.AddPair('unit', AUnit);
  mEntry.AddPair('types', Result);
  AOrder.AddElement(mEntry);
  AUnits.Add(UpperCase(AUnit), Result);
end;

class function TAtlasIdeMembers.ToJson(const ADetails: TArray<TAtlasIdeTypeDetail>): TJSONObject;
var
  mOrder: TJSONArray;
  mUnits: TDictionary<string, TJSONArray>;
  mDetail: TAtlasIdeTypeDetail;
begin
  Result := TJSONObject.Create;
  mOrder := TJSONArray.Create;
  Result.AddPair('units', mOrder);
  mUnits := TDictionary<string, TJSONArray>.Create;
  try
    for mDetail in ADetails do
    begin
      if (mDetail.Name <> '') and (mDetail.UnitName <> '') then
      begin
        UnitTypes(mUnits, mOrder, mDetail.UnitName).AddElement(DetailJson(mDetail));
      end;
    end;
  finally
    mUnits.Free;
  end;
end;

end.
