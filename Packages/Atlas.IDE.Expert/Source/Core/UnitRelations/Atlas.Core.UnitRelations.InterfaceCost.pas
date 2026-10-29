unit Atlas.Core.UnitRelations.InterfaceCost;

// Kosten einer Änderung im interface-Teil (#554), Kern ohne VCL und OTA:
// - Parse liest die Antwort von atlas.interfaceCost ({"found", "unit",
//   "file", "recompileCount", "units", "generation"}).
// - InInterfacePart sagt, ob die Einfügemarke im interface-Teil einer Unit
//   steht (vom Schlüsselwort interface bis vor implementation, die
//   interface-uses eingeschlossen). Programme, Packages, Bibliotheken und
//   Include-Dateien haben keinen. Die Abschnitte liest
//   TAtlasSectionScanner (#1101) direkt aus dem Editortext.
// - Visible: Feld in der Statusleiste nur mit build.showInterfaceCost, im
//   interface-Teil und wenn mindestens eine Unit neu übersetzt wird.
// - UnitList nennt die ersten Units („A, B, C“) und wie viele es außerdem
//   sind; die Wörter dazu setzt der Aufrufer (Atlas.UI.Strings).

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Core.EditorToolbar.Sections;

type
  TAtlasInterfaceCost = record
    Found: Boolean;
    UnitName: string;
    FileName: string;
    /// <summary>Units, die nach einer Änderung im interface neu übersetzt werden.</summary>
    RecompileCount: Integer;
    /// <summary>Die ersten davon nach Name.</summary>
    Units: TArray<string>;
    Generation: Int64;
  end;

  TAtlasInterfaceCostModel = class
  public const
    Command = 'atlas.interfaceCost';
  public
    /// <summary>[uri] für atlas.interfaceCost.</summary>
    class function Arguments(const AUri: string): string; static;
    /// <summary>Antwort von atlas.interfaceCost; False bei leerer oder unlesbarer Antwort.</summary>
    class function Parse(const AJson: string; out ACost: TAtlasInterfaceCost): Boolean; static;
    /// <summary>Steht die Stelle ALine/ACharacter (0-basiert) im interface-Teil einer Unit?</summary>
    class function InInterfacePart(const ASections: TAtlasUnitSections; ALine, ACharacter: Integer): Boolean;
      static;
    /// <summary>Feld in der Statusleiste zeigen?</summary>
    class function Visible(AEnabled, AInInterface: Boolean; const ACost: TAtlasInterfaceCost): Boolean; static;
    /// <summary>Die Namen aus ACost.Units mit Komma; AMore = wie viele Units darüber hinaus neu übersetzt
    /// werden.</summary>
    class function UnitList(const ACost: TAtlasInterfaceCost; out AMore: Integer): string; static;
  end;

implementation

{ TAtlasInterfaceCostModel }

class function TAtlasInterfaceCostModel.Arguments(const AUri: string): string;
var
  Items: TJSONArray;
begin
  Items := TJSONArray.Create;
  try
    Items.Add(AUri);
    Result := Items.ToJSON;
  finally
    Items.Free;
  end;
end;

class function TAtlasInterfaceCostModel.Parse(const AJson: string; out ACost: TAtlasInterfaceCost): Boolean;
var
  Value, Item: TJSONValue;
  Root: TJSONObject;
begin
  ACost := Default(TAtlasInterfaceCost);
  Result := False;
  if Trim(AJson) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    if not (Root.GetValue('recompileCount') is TJSONNumber) then
      Exit;
    ACost.Found := (Root.GetValue('found') is TJSONBool) and TJSONBool(Root.GetValue('found')).AsBoolean;
    if Root.GetValue('unit') is TJSONString then
      ACost.UnitName := Root.GetValue('unit').Value;
    if Root.GetValue('file') is TJSONString then
      ACost.FileName := Root.GetValue('file').Value;
    ACost.RecompileCount := TJSONNumber(Root.GetValue('recompileCount')).AsInt;
    if Root.GetValue('units') is TJSONArray then
      for Item in TJSONArray(Root.GetValue('units')) do
        if Item is TJSONString then
          ACost.Units := ACost.Units + [Item.Value];
    if Root.GetValue('generation') is TJSONNumber then
      ACost.Generation := TJSONNumber(Root.GetValue('generation')).AsInt64;
    Result := True;
  finally
    Value.Free;
  end;
end;

class function TAtlasInterfaceCostModel.InInterfacePart(const ASections: TAtlasUnitSections; ALine,
  ACharacter: Integer): Boolean;
begin
  Result := (ASections.Kind = TAtlasSourceKind.Unit_) and ASections.InterfacePart.Before(ALine, ACharacter) and
    not ASections.ImplementationPart.Before(ALine, ACharacter);
end;

class function TAtlasInterfaceCostModel.Visible(AEnabled, AInInterface: Boolean;
  const ACost: TAtlasInterfaceCost): Boolean;
begin
  Result := AEnabled and AInInterface and ACost.Found and (ACost.RecompileCount > 0);
end;

class function TAtlasInterfaceCostModel.UnitList(const ACost: TAtlasInterfaceCost; out AMore: Integer): string;
begin
  Result := string.Join(', ', ACost.Units);
  AMore := ACost.RecompileCount - Length(ACost.Units);
  if AMore < 0 then
    AMore := 0;
end;

end.
