{$mode delphi}{$H+}{$modeswitch unicodestrings}{$modeswitch advancedrecords}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}
unit AtlasJsonCompat;

// TJSONObject.ParseJSONValue wie in Delphi für den Linux-Bau (#1356).
// In System.JSON aus vcl-compat liefert der Parser bei ungültigem Text ohne
// RaiseExc kein nil, sondern einen nicht gesetzten Result (TJSONParser.Parse
// weist Result im except-Zweig nicht zu): Der Aufrufer prüft auf nil, sieht
// einen beliebigen Zeiger und gibt ihn frei. Delphi liefert nil.
// Convert-ForFpc.py leitet alle Aufrufe von TJSONObject.ParseJSONValue und
// TJSONValue.ParseJSONValue hierher um; mit RaiseExc kommt der Fehler als
// Ausnahme und wird zu nil.

interface

uses
  SysUtils, System.JSON;

function ParseJSONValueOrNil(const AData: UnicodeString): TJSONValue; overload;
function ParseJSONValueOrNil(const AData: TBytes; AOffset: Integer; AIsUTF8: Boolean): TJSONValue; overload;

implementation

function ParseJSONValueOrNil(const AData: UnicodeString): TJSONValue;
begin
  try
    Result := TJSONObject.ParseJSONValue(AData, False, True);
  except
    on Exception do
      Result := nil;
  end;
end;

function ParseJSONValueOrNil(const AData: TBytes; AOffset: Integer; AIsUTF8: Boolean): TJSONValue;
var
  mOptions: TJSONValue.TJSONParseOptions;
begin
  mOptions := [TJSONValue.TJSONParseOption.RaiseExc];
  if AIsUTF8 then
    Include(mOptions, TJSONValue.TJSONParseOption.IsUTF8);
  try
    Result := TJSONObject.ParseJSONValue(PByte(AData), AOffset, Length(AData), mOptions);
  except
    on Exception do
      Result := nil;
  end;
end;

end.
