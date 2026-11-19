unit Atlas.Text.Json;

// JSON-Strings von Hand schreiben (gemeinsam für Server und Plugin):
// Anführungszeichen, Backslash und Steuerzeichen wie RFC 8259 maskieren, alle
// übrigen Zeichen unverändert (auch Umlaute, anders als TJSONValue.ToJSON).
// Ausgaben, die den Text selbst zusammensetzen (Linter-Befunde, Baseline,
// Metriken), teilen sich diese eine Regel (#1450). Auch wer einzelne Strings in
// selbst gebauten JSON-Text setzt, maskiert über TJsonText.Quote und nicht über
// TJSONString.ToJSON (das je nach Option Umlaute als \u-Folge schreibt).
//
// JSON-Werte bauen (TJsonBuild): Listen von Strings als TJSONArray für Server,
// Plugin und gespeicherte Daten.
//
// JSON nachsichtig lesen (TJsonRead, #1969): Ein fehlendes Objekt, ein fehlender
// Wert, null oder ein falscher Typ liefern die Vorgabe, nie eine Ausnahme. Server
// und Plugin lesen damit Antworten, Einstellungen und gespeicherte Daten nach
// derselben Regel.

interface

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.JSON;

type
  TJsonText = class
  public
    /// <summary>AText als JSON-String samt Anführungszeichen.</summary>
    class function Quote(const AText: string): string; static;
    /// <summary>AItems als JSON-Array von Strings in einer Zeile, getrennt durch ", ".</summary>
    class function List(const AItems: array of string): string; static;
  end;

  /// <summary>JSON-Werte aus Pascal-Werten bauen.</summary>
  TJsonBuild = record
  public
    /// <summary>AItems als JSON-Array von Strings in derselben Reihenfolge. Der Aufrufer gibt das Array frei.
    /// </summary>
    class function Strings(const AItems: array of string): TJSONArray; static;
    /// <summary>AValue unter AName in AObject; ein leerer Wert bleibt weg.</summary>
    class procedure AddText(AObject: TJSONObject; const AName, AValue: string); static;
    /// <summary>Zeitpunkt AValue (UTC) als ISO 8601 mit „Z“; '' für 0 und davor. Gegenstück zu
    /// TJsonRead.IsoTime.</summary>
    class function IsoTime(AValue: TDateTime): string; static;
  end;

  /// <summary>Nachsichtiges Lesen aus TJSONObject: nil, fehlender Wert, null und falscher Typ geben die
  /// Vorgabe.</summary>
  TJsonRead = record
  private
    class function NumberText(AValue: TJSONValue; out AText: string): Boolean; static;
    class function TryInt64Of(AValue: TJSONValue; out AInt: Int64): Boolean; static;
  public
    /// <summary>AJson als JSON-Wert; nil bei leerem oder ungültigem Text. Der Aufrufer gibt den Wert frei.
    /// </summary>
    class function Parse(const AJson: string): TJSONValue; static;
    /// <summary>AJson als JSON-Objekt; nil bei leerem, ungültigem Text oder anderem Wert. Der Aufrufer gibt das
    /// Objekt frei.</summary>
    class function ParseObject(const AJson: string): TJSONObject; static;
    /// <summary>Wie ParseObject, aber ein leeres Objekt statt nil. Der Aufrufer gibt das Objekt frei.</summary>
    class function ParseObjectOrEmpty(const AJson: string): TJSONObject; static;
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
    /// <summary>Wert AName als JSON-Text (TJSONValue.ToJSON, null als "null"); '' ohne Wert.</summary>
    class function Json(AObject: TJSONObject; const AName: string): string; static;
    /// <summary>Zeitpunkt AName nach ISO 8601 (Zeichenkette mit Zeitzone); mit AReturnUTC in UTC, sonst in
    /// Ortszeit. 0 ohne Wert, bei leerem, unlesbarem Text oder anderem Typ.</summary>
    class function IsoTime(AObject: TJSONObject; const AName: string; AReturnUTC: Boolean): TDateTime; static;
    /// <summary>True, wenn AValue eine echte Zeichenkette ist, keine Zahl (TJSONNumber erbt bis Delphi 12 von
    /// TJSONString).</summary>
    class function IsString(AValue: TJSONValue): Boolean; static;
    /// <summary>Die Zeichenketten des Arrays AValue in ihrer Reihenfolge; Zahlen, Wahrheitswerte, null, Objekte
    /// und Arrays darin werden übersprungen. Kein Array gibt nil.</summary>
    class function Strings(AValue: TJSONValue): TArray<string>; overload; static;
    /// <summary>Strings des Werts AName in AObject.</summary>
    class function Strings(AObject: TJSONObject; const AName: string): TArray<string>; overload; static;
    /// <summary>Wie Strings, jede ohne führenden und folgenden Leerraum; leere fallen weg.</summary>
    class function TrimmedStrings(AValue: TJSONValue): TArray<string>; overload; static;
    /// <summary>Die ganzen Zahlen des Arrays AName in ihrer Reihenfolge (auch 12.0); Zeichenketten, andere Werte
    /// und Zahlen außerhalb von Integer werden übersprungen. Kein Array gibt nil.</summary>
    class function Ints(AObject: TJSONObject; const AName: string): TArray<Integer>; static;
    /// <summary>TrimmedStrings des Werts AName in AObject.</summary>
    class function TrimmedStrings(AObject: TJSONObject; const AName: string): TArray<string>; overload; static;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Text.Timestamps;

const
  /// <summary>Hexadezimalstellen einer Folge \uXXXX.</summary>
  cUnicodeEscapeDigits = 4;

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
        if mChar < ' ' then
        begin
          mBuilder.Append('\u' + IntToHex(Ord(mChar), cUnicodeEscapeDigits));
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

class function TJsonText.List(const AItems: array of string): string;
var
  mIndex: Integer;
begin
  Result := '[';
  for mIndex := 0 to High(AItems) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + Quote(AItems[mIndex]);
  end;
  Result := Result + ']';
end;

{ TJsonBuild }

class function TJsonBuild.Strings(const AItems: array of string): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
  begin
    Result.Add(mItem);
  end;
end;

class procedure TJsonBuild.AddText(AObject: TJSONObject; const AName, AValue: string);
begin
  if AValue <> '' then
  begin
    AObject.AddPair(AName, AValue);
  end;
end;

class function TJsonBuild.IsoTime(AValue: TDateTime): string;
begin
  Result := '';
  if AValue > 0 then
  begin
    Result := DateToISO8601(AValue, True);
  end;
end;

{ TJsonRead }

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

class function TJsonRead.Parse(const AJson: string): TJSONValue;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  try
    Result := TJSONObject.ParseJSONValue(AJson);
  except
    // Ungültiger Text ist kein Fehler des Aufrufers: Er bekommt nil wie bei leerem Text.
    on EJSONException do
      Result := nil;
  end;
end;

class function TJsonRead.ParseObject(const AJson: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  // Kein Objekt: gar nicht erst parsen.
  if Copy(TrimLeft(AJson), 1, 1) <> '{' then
  begin
    Exit;
  end;
  mValue := Parse(AJson);
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end
  else
  begin
    mValue.Free;
  end;
end;

class function TJsonRead.ParseObjectOrEmpty(const AJson: string): TJSONObject;
begin
  Result := ParseObject(AJson);
  if Result = nil then
  begin
    Result := TJSONObject.Create;
  end;
end;

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
  if IsString(mValue) then
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

class function TJsonRead.TryInt64Of(AValue: TJSONValue; out AInt: Int64): Boolean;
const
  // Etwas unter High(Int64): als Double gerundet läge High(Int64) schon außerhalb, Trunc liefe über.
  cInt64Range = 9.2e18;
var
  mText: string;
  mDouble: Double;
begin
  AInt := 0;
  if not NumberText(AValue, mText) then
  begin
    Exit(False);
  end;
  Result := TryStrToInt64(mText, AInt);
  // Zähler kommen auch als 12.0 oder 1e3; Zeitstempel in ms passen nicht in 32 Bit.
  if not Result and (AValue is TJSONNumber) then
  begin
    mDouble := TJSONNumber(AValue).AsDouble;
    Result := (mDouble >= -cInt64Range) and (mDouble <= cInt64Range);
    if Result then
    begin
      AInt := Trunc(mDouble);
    end;
  end;
end;

class function TJsonRead.TryInt64(AObject: TJSONObject; const AName: string; out AValue: Int64): Boolean;
begin
  Result := TryInt64Of(Value(AObject, AName), AValue);
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

class function TJsonRead.Json(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := Value(AObject, AName);
  if mValue <> nil then
  begin
    Result := mValue.ToJSON;
  end;
end;

class function TJsonRead.IsoTime(AObject: TJSONObject; const AName: string; AReturnUTC: Boolean): TDateTime;
begin
  Result := TTextTimestamp.IsoOrZero(StrictText(AObject, AName), AReturnUTC);
end;

class function TJsonRead.IsString(AValue: TJSONValue): Boolean;
begin
  Result := (AValue is TJSONString) and not (AValue is TJSONNumber);
end;

class function TJsonRead.Strings(AValue: TJSONValue): TArray<string>;
var
  mList: TJSONArray;
  mIndex: Integer;
  mCount: Integer;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  mList := TJSONArray(AValue);
  SetLength(Result, mList.Count);
  mCount := 0;
  for mIndex := 0 to mList.Count - 1 do
  begin
    if IsString(mList.Items[mIndex]) then
    begin
      Result[mCount] := mList.Items[mIndex].Value;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TJsonRead.Strings(AObject: TJSONObject; const AName: string): TArray<string>;
begin
  Result := Strings(Value(AObject, AName));
end;

class function TJsonRead.TrimmedStrings(AValue: TJSONValue): TArray<string>;
var
  mIndex: Integer;
  mCount: Integer;
begin
  Result := Strings(AValue);
  mCount := 0;
  for mIndex := 0 to High(Result) do
  begin
    if Trim(Result[mIndex]) <> '' then
    begin
      Result[mCount] := Trim(Result[mIndex]);
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TJsonRead.Ints(AObject: TJSONObject; const AName: string): TArray<Integer>;
var
  mList: TJSONArray;
  mIndex: Integer;
  mCount: Integer;
  mValue: Int64;
begin
  Result := nil;
  mList := Items(AObject, AName);
  if mList = nil then
  begin
    Exit;
  end;
  SetLength(Result, mList.Count);
  mCount := 0;
  for mIndex := 0 to mList.Count - 1 do
  begin
    if (mList.Items[mIndex] is TJSONNumber) and TryInt64Of(mList.Items[mIndex], mValue) and
      (mValue >= Low(Integer)) and (mValue <= High(Integer)) then
    begin
      Result[mCount] := Integer(mValue);
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TJsonRead.TrimmedStrings(AObject: TJSONObject; const AName: string): TArray<string>;
begin
  Result := TrimmedStrings(Value(AObject, AName));
end;

end.
