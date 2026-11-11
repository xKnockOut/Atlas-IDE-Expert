unit Atlas.Text.Json;

// JSON-Strings von Hand schreiben (gemeinsam für Server und Plugin):
// Anführungszeichen, Backslash und Steuerzeichen wie RFC 8259 maskieren, alle
// übrigen Zeichen unverändert (auch Umlaute, anders als TJSONValue.ToJSON).
// Ausgaben, die den Text selbst zusammensetzen (Linter-Befunde, Baseline,
// Metriken), teilen sich diese eine Regel (#1450).
//
// JSON nachsichtig lesen (TJsonRead, #1969): Ein fehlendes Objekt, ein fehlender
// Wert, null oder ein falscher Typ liefern die Vorgabe, nie eine Ausnahme. Server
// und Plugin lesen damit Antworten, Einstellungen und gespeicherte Daten nach
// derselben Regel.

interface

uses
  System.SysUtils,
  System.JSON;

type
  TJsonText = class
  public
    /// <summary>AText als JSON-String samt Anführungszeichen.</summary>
    class function Quote(const AText: string): string; static;
  end;

  /// <summary>Nachsichtiges Lesen aus TJSONObject: nil, fehlender Wert, null und falscher Typ geben die
  /// Vorgabe.</summary>
  TJsonRead = record
  private
    class function NumberText(AValue: TJSONValue; out AText: string): Boolean; static;
  public
    /// <summary>AValue als Objekt, sonst nil.</summary>
    class function AsObject(AValue: TJSONValue): TJSONObject; static;
    /// <summary>Der Wert AName in AObject; nil, wenn AObject nil ist oder den Namen nicht hat.</summary>
    class function Value(AObject: TJSONObject; const AName: string): TJSONValue; static;
    /// <summary>Zeichenkette AName, sonst ''. Eine Zahl liefert ihren Text (TJSONNumber erbt bis Delphi 12
    /// von TJSONString, ab Delphi 13 nicht mehr; beide Fälle werden geprüft).</summary>
    class function Text(AObject: TJSONObject; const AName: string): string; static;
    /// <summary>Wie Text, aber nur echte Zeichenketten: Eine Zahl gibt ''.</summary>
    class function StrictText(AObject: TJSONObject; const AName: string): string; static;
    /// <summary>Text ohne führenden und folgenden Leerraum.</summary>
    class function TrimmedText(AObject: TJSONObject; const AName: string): string; static;
    /// <summary>True, wenn AName eine Zeichenkette (oder Zahl) ist; AValue ist dann ihr Text, sonst ''.</summary>
    class function TryText(AObject: TJSONObject; const AName: string; out AValue: string): Boolean; static;
    /// <summary>Ganzzahl AName, sonst 0. Liest auch 12.0 und "12".</summary>
    class function Int(AObject: TJSONObject; const AName: string): Integer; static;
    /// <summary>Ganzzahl AName, sonst ADefault. Werte außerhalb von Integer geben ADefault.</summary>
    class function IntOr(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer; static;
    /// <summary>64-Bit-Ganzzahl AName, sonst ADefault.</summary>
    class function Int64Or(AObject: TJSONObject; const AName: string; ADefault: Int64): Int64; static;
    /// <summary>True, wenn AName eine Ganzzahl ist (auch 12.0 oder "12"); AValue ist sonst 0.</summary>
    class function TryInt64(AObject: TJSONObject; const AName: string; out AValue: Int64): Boolean; static;
    /// <summary>Zahl AName, sonst 0.</summary>
    class function Float(AObject: TJSONObject; const AName: string): Double; static;
    /// <summary>Wahrheitswert AName, sonst False.</summary>
    class function Flag(AObject: TJSONObject; const AName: string): Boolean; static;
    /// <summary>Wahrheitswert AName, sonst ADefault.</summary>
    class function FlagOr(AObject: TJSONObject; const AName: string; ADefault: Boolean): Boolean; static;
    /// <summary>Objekt AName, sonst nil. Gehört weiter AObject.</summary>
    class function Obj(AObject: TJSONObject; const AName: string): TJSONObject; static;
    /// <summary>Array AName, sonst nil. Gehört weiter AObject.</summary>
    class function Items(AObject: TJSONObject; const AName: string): TJSONArray; static;
  end;

implementation

{ TJsonText }

class function TJsonText.Quote(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mChar: Char;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('"');
    for mChar in AText do
      case mChar of
        '"':
          mBuilder.Append('\"');
        '\':
          mBuilder.Append('\\');
        #8:
          mBuilder.Append('\b');
        #9:
          mBuilder.Append('\t');
        #10:
          mBuilder.Append('\n');
        #12:
          mBuilder.Append('\f');
        #13:
          mBuilder.Append('\r');
      else
        if Ord(mChar) < 32 then
        begin
          mBuilder.Append('\u' + IntToHex(Ord(mChar), 4));
        end
        else
        begin
          mBuilder.Append(mChar);
        end;
      end;
    mBuilder.Append('"');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TJsonRead }

class function TJsonRead.AsObject(AValue: TJSONValue): TJSONObject;
begin
  Result := nil;
  if AValue is TJSONObject then
  begin
    Result := TJSONObject(AValue);
  end;
end;

class function TJsonRead.Value(AObject: TJSONObject; const AName: string): TJSONValue;
begin
  Result := nil;
  if AObject <> nil then
  begin
    Result := AObject.GetValue(AName);
  end;
end;

class function TJsonRead.Text(AObject: TJSONObject; const AName: string): string;
begin
  TryText(AObject, AName, Result);
end;

class function TJsonRead.StrictText(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := Value(AObject, AName);
  if (mValue is TJSONString) and not (mValue is TJSONNumber) then
  begin
    Result := mValue.Value;
  end;
end;

class function TJsonRead.TrimmedText(AObject: TJSONObject; const AName: string): string;
begin
  Result := Trim(Text(AObject, AName));
end;

class function TJsonRead.TryText(AObject: TJSONObject; const AName: string; out AValue: string): Boolean;
var
  mValue: TJSONValue;
begin
  AValue := '';
  mValue := Value(AObject, AName);
  // Zahl zählt als Text; ab Delphi 13 ist TJSONNumber kein TJSONString mehr.
  Result := (mValue is TJSONString) or (mValue is TJSONNumber);
  if Result then
  begin
    AValue := mValue.Value;
  end;
end;

class function TJsonRead.NumberText(AValue: TJSONValue; out AText: string): Boolean;
begin
  AText := '';
  // TJSONNumber erbt bis Delphi 12 (und unter FPC) von TJSONString, ab Delphi 13 direkt von TJSONValue.
  Result := (AValue is TJSONString) or (AValue is TJSONNumber);
  if Result then
  begin
    AText := Trim(AValue.Value);
  end;
end;

class function TJsonRead.TryInt64(AObject: TJSONObject; const AName: string; out AValue: Int64): Boolean;
const
  // Etwas unter High(Int64): als Double gerundet läge High(Int64) schon außerhalb, Trunc liefe über.
  cInt64Range = 9.2e18;
var
  mValue: TJSONValue;
  mText: string;
  mDouble: Double;
begin
  AValue := 0;
  mValue := Value(AObject, AName);
  if not NumberText(mValue, mText) then
  begin
    Exit(False);
  end;
  Result := TryStrToInt64(mText, AValue);
  // Zähler kommen auch als 12.0 oder 1e3; Zeitstempel in ms passen nicht in 32 Bit.
  if not Result and (mValue is TJSONNumber) then
  begin
    mDouble := TJSONNumber(mValue).AsDouble;
    Result := (mDouble >= -cInt64Range) and (mDouble <= cInt64Range);
    if Result then
    begin
      AValue := Trunc(mDouble);
    end;
  end;
end;

class function TJsonRead.Int(AObject: TJSONObject; const AName: string): Integer;
begin
  Result := IntOr(AObject, AName, 0);
end;

class function TJsonRead.IntOr(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  mValue: Int64;
begin
  Result := ADefault;
  if TryInt64(AObject, AName, mValue) and (mValue >= Low(Integer)) and (mValue <= High(Integer)) then
  begin
    Result := Integer(mValue);
  end;
end;

class function TJsonRead.Int64Or(AObject: TJSONObject; const AName: string; ADefault: Int64): Int64;
begin
  if not TryInt64(AObject, AName, Result) then
  begin
    Result := ADefault;
  end;
end;

class function TJsonRead.Float(AObject: TJSONObject; const AName: string): Double;
var
  mValue: TJSONValue;
begin
  Result := 0;
  mValue := Value(AObject, AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsDouble;
  end;
end;

class function TJsonRead.Flag(AObject: TJSONObject; const AName: string): Boolean;
begin
  Result := FlagOr(AObject, AName, False);
end;

class function TJsonRead.FlagOr(AObject: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  mValue := Value(AObject, AName);
  if mValue is TJSONBool then
  begin
    Result := TJSONBool(mValue).AsBoolean;
  end;
end;

class function TJsonRead.Obj(AObject: TJSONObject; const AName: string): TJSONObject;
begin
  Result := AsObject(Value(AObject, AName));
end;

class function TJsonRead.Items(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  mValue := Value(AObject, AName);
  if mValue is TJSONArray then
  begin
    Result := TJSONArray(mValue);
  end;
end;

end.
