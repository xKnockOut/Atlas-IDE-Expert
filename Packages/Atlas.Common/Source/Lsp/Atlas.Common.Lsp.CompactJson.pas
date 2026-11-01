unit Atlas.Common.Lsp.CompactJson;

// Kompakte Ablage gespeicherter JSON-Befunde (#1237). Die Projektprüfung hält
// die Befunde aller Units; als TJSONArray kostet jeder Befund dutzende
// Objekte (Paare, Schlüssel, Werte, Bereiche) und ein Vielfaches seines
// Texts. Bei 900+ Units lag das im Gigabyte-Bereich. Abgelegt wird deshalb
// der JSON-Text als UTF-8; erst beim Ausliefern entsteht wieder ein Baum, und
// nur für die Dateien, die die Antwort tatsächlich enthält.

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
  TCompactJson = record
  public
    /// <summary>JSON-Text von AValue als UTF-8; AValue bleibt beim Aufrufer.</summary>
    class function Pack(const AValue: TJSONValue): TBytes; static;
    /// <summary>Neues Array aus Pack; leer bei leerem oder ungültigem Inhalt. Der Aufrufer gibt es frei.</summary>
    class function UnpackArray(const ABytes: TBytes): TJSONArray; static;
  end;

implementation

class function TCompactJson.Pack(const AValue: TJSONValue): TBytes;
begin
  // Zeichen über 127 unmaskiert: In UTF-8 sind sie kürzer als \uXXXX. Steuerzeichen bleiben maskiert,
  // sonst wäre der Text kein gültiges JSON mehr.
  Result := nil;
  if AValue <> nil then
  begin
    Result := TEncoding.UTF8.GetBytes(AValue.ToJSON([TJSONAncestor.TJSONOutputOption.EncodeBelow32]));
  end;
end;

class function TCompactJson.UnpackArray(const ABytes: TBytes): TJSONArray;
var
  mValue: TJSONValue;
begin
  mValue := nil;
  if Length(ABytes) > 0 then
  begin
    mValue := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(ABytes));
  end;
  if mValue is TJSONArray then
  begin
    Exit(TJSONArray(mValue));
  end;
  mValue.Free;
  Result := TJSONArray.Create;
end;

end.
