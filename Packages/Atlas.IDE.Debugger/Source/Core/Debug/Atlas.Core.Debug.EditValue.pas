unit Atlas.Core.Debug.EditValue;

// Werte ändern beim Debuggen (#868), ohne VCL und Open Tools API:
//   - Antwort des Servers (atlas.server.valueEdit) lesen: Typ und Art der
//     Eingabe (Zahl mit Grenzen, Gleitkomma, Boolean, Zeichen, String,
//     Aufzählung, Menge, Farbe), Setter und nur lesbare Eigenschaften.
//   - Eingabe prüfen und in den Text für IOTAThread.Modify umsetzen: Zahlen im
//     Bereich, Komma als Dezimaltrennzeichen, Strings und Zeichen in
//     Hochkommas, Aufzählungswerte mit Typpräfix bei {$SCOPEDENUMS ON},
//     Mengen als [a, b], Farben als $00BBGGRR (#RRGGBB wird umgedreht).
//   - Geänderte Werte bis zum nächsten Schritt merken (alter Wert für die
//     Anzeige und „Rückgängig“).

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasEditKind = (Other, Integer_, Float, Boolean_, Char_, String_, Enum, Set_, Color);
  /// <summary>Warum eine Eingabe nicht übernommen wird.</summary>
  TAtlasEditProblem = (None, Empty, NotInteger, OutOfRange, NotFloat, NotBoolean, NotChar, UnknownValue, ReadOnly);
  {$SCOPEDENUMS OFF}

  TAtlasEditInfo = record
    Expression: string;
    TypeName: string;
    Kind: TAtlasEditKind;
    /// <summary>Werte bei Aufzählung und Menge, in Deklarationsreihenfolge.</summary>
    Values: TArray<string>;
    /// <summary>„TModus.“ bei {$SCOPEDENUMS ON}; '' sonst.</summary>
    Prefix: string;
    /// <summary>Grenzen einer Ganzzahl als Text; '' ohne.</summary>
    Low: string;
    High: string;
    /// <summary>Schreibmethode einer Eigenschaft; '' ohne (Feld oder Variable).</summary>
    Setter: string;
    ReadOnly: Boolean;
    /// <summary>Ohne Antwort des Servers: freie Eingabe.</summary>
    class function Plain(const AExpression: string): TAtlasEditInfo; static;
  end;

  TAtlasEditCheck = record
    Problem: TAtlasEditProblem;
    /// <summary>Zum Text des Problems: der unbekannte Wert bzw. „0..255“.</summary>
    Detail: string;
    /// <summary>Text für IOTAThread.Modify.</summary>
    Value: string;
    function Ok: Boolean;
  end;

  TAtlasEditValue = class
  public const
    cCommand = 'atlas.server.valueEdit';
  private
    class function CheckInteger(const AInfo: TAtlasEditInfo; const AInput: string): TAtlasEditCheck; static;
    class function CheckFloat(const AInput: string): TAtlasEditCheck; static;
    class function CheckBoolean(const AInput: string): TAtlasEditCheck; static;
    class function CheckChar(const AInput: string): TAtlasEditCheck; static;
    class function CheckEnum(const AInfo: TAtlasEditInfo; const AInput: string): TAtlasEditCheck; static;
    class function CheckSet(const AInfo: TAtlasEditInfo; const AInput: string): TAtlasEditCheck; static;
    class function CheckColor(const AInput: string): TAtlasEditCheck; static;
    class function KindOf(const AName: string): TAtlasEditKind; static;
  public
    /// <summary>Argumente des Befehls als JSON: [uri, line (ab 0), expression].</summary>
    class function Arguments(const AUri: string; ALine: Integer; const AExpression: string): string; static;
    /// <summary>Antwort des Servers; bei leerem oder kaputtem Text Plain(AExpression).</summary>
    class function ReadAnswerText(const AText, AExpression: string): TAtlasEditInfo; static;
    /// <summary>Eingabe AInput für AInfo prüfen und umsetzen.</summary>
    class function Check(const AInfo: TAtlasEditInfo; const AInput: string): TAtlasEditCheck; static;
    /// <summary>Namen einer Menge wie „[mdAuto,mdHand]“ (auch mit Präfix); leer bei „[]“.</summary>
    class function SetItems(const AValue: string): TArray<string>; static;
    /// <summary>„[TModus.a, TModus.b]“ aus den Namen.</summary>
    class function SetText(const AInfo: TAtlasEditInfo; const ANames: TArray<string>): string; static;
    /// <summary>True ↔ False; False bei einem anderen Wert.</summary>
    class function Toggled(const AValue: string; out ANew: string): Boolean; static;
    /// <summary>Farbe aus „$000000FF“, „255“ oder „#FF0000“ (RGB); False sonst.</summary>
    class function ColorOf(const AValue: string; out AColor: Integer): Boolean; static;
    /// <summary>„$00BBGGRR“.</summary>
    class function ColorText(AColor: Integer): string; static;
    /// <summary>In Hochkommas, innere Hochkommas verdoppelt.</summary>
    class function Quote(const AText: string): string; static;
    /// <summary>Aufruf des Setters für AValue: „K.SetBetrag(150)“ zu „K.Betrag“; '' ohne Setter.</summary>
    class function SetterCall(const AInfo: TAtlasEditInfo; const AValue: string): string; static;
  end;

  TAtlasEditChange = record
    FileName: string;
    Line: Integer;
    Expression: string;
    OldValue: string;
    NewValue: string;
  end;

  /// <summary>Geänderte Werte seit dem Halt; der nächste Schritt leert die Liste.</summary>
  TAtlasEditChanges = class
  private
    FItems: TArray<TAtlasEditChange>;
    function IndexOf(const AFileName, AExpression: string): Integer;
  public
    destructor Destroy; override;
    /// <summary>Merkt die Änderung; bei wiederholter Änderung bleibt der erste alte Wert.</summary>
    procedure Add(const AChange: TAtlasEditChange);
    function Find(const AFileName, AExpression: string; out AChange: TAtlasEditChange): Boolean;
    procedure Remove(const AFileName, AExpression: string);
    procedure Clear;
    function Count: Integer;
    /// <summary>Alle gemerkten Änderungen (zum Zeichnen).</summary>
    function Items: TArray<TAtlasEditChange>;
  end;

implementation

uses
  System.JSON,
  Atlas.Text.Json;

const
  cTrue = 'True';
  cFalse = 'False';
  cQuote = '''';
  /// <summary>Stellen einer Farbe in Hex.</summary>
  cColorDigits = 8;
  /// <summary>„#RRGGBB“: Länge und Stellen je Farbe.</summary>
  cHtmlColorLength = 7;
  cByteShift = 8;
  cTwoByteShift = 16;
  cByteMask = $FF;
  cKindNames: array[TAtlasEditKind] of string = ('other', 'integer', 'float', 'boolean', 'char', 'string', 'enum',
    'set', 'color');

{ TAtlasEditInfo }

class function TAtlasEditInfo.Plain(const AExpression: string): TAtlasEditInfo;
begin
  Result := Default(TAtlasEditInfo);
  Result.Expression := AExpression;
  Result.Kind := TAtlasEditKind.Other;
end;

{ TAtlasEditCheck }

function TAtlasEditCheck.Ok: Boolean;
begin
  Result := Problem = TAtlasEditProblem.None;
end;

function Accepted(const AValue: string): TAtlasEditCheck;
begin
  Result := Default(TAtlasEditCheck);
  Result.Value := AValue;
end;

function Rejected(AProblem: TAtlasEditProblem; const ADetail: string): TAtlasEditCheck;
begin
  Result := Default(TAtlasEditCheck);
  Result.Problem := AProblem;
  Result.Detail := ADetail;
end;

{ TAtlasEditValue }

class function TAtlasEditValue.Arguments(const AUri: string; ALine: Integer; const AExpression: string): string;
var
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    mItems.Add(ALine);
    mItems.Add(AExpression);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasEditValue.KindOf(const AName: string): TAtlasEditKind;
var
  mKind: TAtlasEditKind;
begin
  for mKind := Low(TAtlasEditKind) to High(TAtlasEditKind) do
  begin
    if cKindNames[mKind] = AName then
    begin
      Exit(mKind);
    end;
  end;
  Result := TAtlasEditKind.Other;
end;

class function TAtlasEditValue.ReadAnswerText(const AText, AExpression: string): TAtlasEditInfo;
var
  mJson: TJSONValue;
  mAnswer: TJSONObject;
  mValues: TJSONArray;
  mIndex: Integer;
begin
  Result := TAtlasEditInfo.Plain(AExpression);
  if AText = '' then
  begin
    Exit;
  end;
  mJson := TJSONObject.ParseJSONValue(AText);
  try
    if not (mJson is TJSONObject) then
    begin
      Exit;
    end;
    mAnswer := TJSONObject(mJson);
    Result.TypeName := TJsonRead.Text(mAnswer, 'type');
    Result.Kind := KindOf(TJsonRead.Text(mAnswer, 'kind'));
    Result.Prefix := TJsonRead.Text(mAnswer, 'prefix');
    Result.Low := TJsonRead.Text(mAnswer, 'low');
    Result.High := TJsonRead.Text(mAnswer, 'high');
    Result.Setter := TJsonRead.Text(mAnswer, 'setter');
    Result.ReadOnly := TJsonRead.Flag(mAnswer, 'readOnly');
    mValues := TJsonRead.Items(mAnswer, 'values');
    if mValues <> nil then
    begin
      for mIndex := 0 to mValues.Count - 1 do
      begin
        Result.Values := Result.Values + [mValues.Items[mIndex].Value];
      end;
    end;
  finally
    mJson.Free;
  end;
end;

class function TAtlasEditValue.Quote(const AText: string): string;
begin
  Result := cQuote + StringReplace(AText, cQuote, cQuote + cQuote, [rfReplaceAll]) + cQuote;
end;

class function TAtlasEditValue.SetterCall(const AInfo: TAtlasEditInfo; const AValue: string): string;
var
  mDot: Integer;
begin
  Result := '';
  if AInfo.Setter = '' then
  begin
    Exit;
  end;
  mDot := AInfo.Expression.LastIndexOf('.');
  Result := Copy(AInfo.Expression, 1, mDot + 1) + AInfo.Setter + '(' + AValue + ')';
end;

/// <summary>Steht AText in Hochkommas?</summary>
function IsQuoted(const AText: string): Boolean;
begin
  Result := (Length(AText) >= 2) and (AText[1] = cQuote) and (AText[Length(AText)] = cQuote);
end;

class function TAtlasEditValue.CheckInteger(const AInfo: TAtlasEditInfo; const AInput: string): TAtlasEditCheck;
var
  mValue, mLow, mHigh: Int64;
  mRange: string;
begin
  if not TryStrToInt64(AInput, mValue) then
  begin
    Exit(Rejected(TAtlasEditProblem.NotInteger, AInput));
  end;
  mRange := AInfo.Low + '..' + AInfo.High;
  // Grenzen über Int64 hinaus (UInt64) prüft Atlas nur nach unten.
  if (TryStrToInt64(AInfo.Low, mLow) and (mValue < mLow)) or
    (TryStrToInt64(AInfo.High, mHigh) and (mValue > mHigh)) then
  begin
    Exit(Rejected(TAtlasEditProblem.OutOfRange, mRange));
  end;
  Result := Accepted(IntToStr(mValue));
end;

class function TAtlasEditValue.CheckFloat(const AInput: string): TAtlasEditCheck;
var
  mText: string;
  mValue: Double;
  mFormat: TFormatSettings;
begin
  mText := StringReplace(AInput, ',', '.', [rfReplaceAll]);
  mFormat := TFormatSettings.Invariant;
  if not TryStrToFloat(mText, mValue, mFormat) then
  begin
    Exit(Rejected(TAtlasEditProblem.NotFloat, AInput));
  end;
  Result := Accepted(mText);
end;

class function TAtlasEditValue.CheckBoolean(const AInput: string): TAtlasEditCheck;
begin
  if SameText(AInput, cTrue) then
  begin
    Result := Accepted(cTrue);
  end
  else if SameText(AInput, cFalse) then
  begin
    Result := Accepted(cFalse);
  end
  else
  begin
    Result := Rejected(TAtlasEditProblem.NotBoolean, AInput);
  end;
end;

class function TAtlasEditValue.CheckChar(const AInput: string): TAtlasEditCheck;
var
  mCode: Integer;
begin
  if Length(AInput) = 1 then
  begin
    Result := Accepted(Quote(AInput));
  end
  else if (Length(AInput) > 1) and (AInput[1] = '#') and TryStrToInt(Copy(AInput, 2, MaxInt), mCode) then
  begin
    Result := Accepted(AInput);
  end
  else if IsQuoted(AInput) and (Length(Copy(AInput, 2, Length(AInput) - 2).Replace(cQuote + cQuote, cQuote)) = 1)
    then
  begin
    Result := Accepted(AInput);
  end
  else
  begin
    Result := Rejected(TAtlasEditProblem.NotChar, AInput);
  end;
end;

/// <summary>Wert AName aus AInfo.Values (mit oder ohne Präfix, Groß-/Kleinschreibung egal); '' ohne.</summary>
function KnownValue(const AInfo: TAtlasEditInfo; const AName: string): string;
var
  mName, mValue: string;
begin
  mName := Trim(AName);
  if (AInfo.Prefix <> '') and mName.StartsWith(AInfo.Prefix, True) then
  begin
    mName := Copy(mName, Length(AInfo.Prefix) + 1, MaxInt);
  end;
  for mValue in AInfo.Values do
  begin
    if SameText(mValue, mName) then
    begin
      Exit(AInfo.Prefix + mValue);
    end;
  end;
  Result := '';
end;

class function TAtlasEditValue.CheckEnum(const AInfo: TAtlasEditInfo; const AInput: string): TAtlasEditCheck;
var
  mValue: string;
begin
  mValue := KnownValue(AInfo, AInput);
  if mValue = '' then
  begin
    Exit(Rejected(TAtlasEditProblem.UnknownValue, AInput));
  end;
  Result := Accepted(mValue);
end;

class function TAtlasEditValue.SetItems(const AValue: string): TArray<string>;
var
  mText, mItem: string;
begin
  Result := nil;
  mText := Trim(AValue);
  if mText.StartsWith('[') then
  begin
    mText := Copy(mText, 2, MaxInt);
  end;
  if mText.EndsWith(']') then
  begin
    mText := Copy(mText, 1, Length(mText) - 1);
  end;
  for mItem in mText.Split([',']) do
  begin
    if Trim(mItem) <> '' then
    begin
      Result := Result + [Trim(mItem)];
    end;
  end;
end;

class function TAtlasEditValue.SetText(const AInfo: TAtlasEditInfo; const ANames: TArray<string>): string;
var
  mNames: TArray<string>;
  mName, mValue: string;
begin
  mNames := nil;
  for mName in ANames do
  begin
    mValue := KnownValue(AInfo, mName);
    if mValue = '' then
    begin
      mValue := Trim(mName);
    end;
    mNames := mNames + [mValue];
  end;
  Result := '[' + string.Join(', ', mNames) + ']';
end;

class function TAtlasEditValue.CheckSet(const AInfo: TAtlasEditInfo; const AInput: string): TAtlasEditCheck;
var
  mItem: string;
begin
  for mItem in SetItems(AInput) do
  begin
    if KnownValue(AInfo, mItem) = '' then
    begin
      Exit(Rejected(TAtlasEditProblem.UnknownValue, mItem));
    end;
  end;
  Result := Accepted(SetText(AInfo, SetItems(AInput)));
end;

class function TAtlasEditValue.ColorOf(const AValue: string; out AColor: Integer): Boolean;
var
  mText: string;
  mRgb: Integer;
begin
  mText := Trim(AValue);
  AColor := 0;
  if (Length(mText) = cHtmlColorLength) and (mText[1] = '#') and TryStrToInt('$' + Copy(mText, 2, MaxInt), mRgb) then
  begin
    // #RRGGBB → $00BBGGRR.
    AColor := ((mRgb and cByteMask) shl cTwoByteShift) or (mRgb and (cByteMask shl cByteShift)) or
      ((mRgb shr cTwoByteShift) and cByteMask);
    Exit(True);
  end;
  Result := TryStrToInt(mText, AColor);
end;

class function TAtlasEditValue.ColorText(AColor: Integer): string;
begin
  Result := '$' + IntToHex(AColor, cColorDigits);
end;

class function TAtlasEditValue.CheckColor(const AInput: string): TAtlasEditCheck;
var
  mColor: Integer;
begin
  // Farbnamen (clRed) kennt der Debugger selbst.
  if AInput.StartsWith('cl') then
  begin
    Exit(Accepted(AInput));
  end;
  if not ColorOf(AInput, mColor) then
  begin
    Exit(Rejected(TAtlasEditProblem.NotInteger, AInput));
  end;
  Result := Accepted(ColorText(mColor));
end;

class function TAtlasEditValue.Toggled(const AValue: string; out ANew: string): Boolean;
begin
  ANew := '';
  if SameText(Trim(AValue), cTrue) then
  begin
    ANew := cFalse;
  end
  else if SameText(Trim(AValue), cFalse) then
  begin
    ANew := cTrue;
  end;
  Result := ANew <> '';
end;

class function TAtlasEditValue.Check(const AInfo: TAtlasEditInfo; const AInput: string): TAtlasEditCheck;
var
  mInput: string;
begin
  if AInfo.ReadOnly then
  begin
    Exit(Rejected(TAtlasEditProblem.ReadOnly, AInfo.Expression));
  end;
  // Strings dürfen leer sein und Leerzeichen am Rand haben.
  if AInfo.Kind = TAtlasEditKind.String_ then
  begin
    if IsQuoted(AInput) then
    begin
      Exit(Accepted(AInput));
    end;
    Exit(Accepted(Quote(AInput)));
  end;
  mInput := Trim(AInput);
  if (mInput = '') and (AInfo.Kind <> TAtlasEditKind.Set_) then
  begin
    Exit(Rejected(TAtlasEditProblem.Empty, ''));
  end;
  case AInfo.Kind of
    TAtlasEditKind.Integer_:
      Result := CheckInteger(AInfo, mInput);
    TAtlasEditKind.Float:
      Result := CheckFloat(mInput);
    TAtlasEditKind.Boolean_:
      Result := CheckBoolean(mInput);
    TAtlasEditKind.Char_:
      Result := CheckChar(mInput);
    TAtlasEditKind.Enum:
      Result := CheckEnum(AInfo, mInput);
    TAtlasEditKind.Set_:
      Result := CheckSet(AInfo, mInput);
    TAtlasEditKind.Color:
      Result := CheckColor(mInput);
  else
    Result := Accepted(mInput);
  end;
end;

{ TAtlasEditChanges }

destructor TAtlasEditChanges.Destroy;
begin
  FItems := nil;
  inherited Destroy;
end;

function TAtlasEditChanges.IndexOf(const AFileName, AExpression: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FItems) do
  begin
    if SameText(FItems[mIndex].FileName, AFileName) and SameText(FItems[mIndex].Expression, AExpression) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasEditChanges.Add(const AChange: TAtlasEditChange);
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AChange.FileName, AChange.Expression);
  if mIndex < 0 then
  begin
    FItems := FItems + [AChange];
  end
  else
  begin
    FItems[mIndex].NewValue := AChange.NewValue;
  end;
end;

function TAtlasEditChanges.Find(const AFileName, AExpression: string; out AChange: TAtlasEditChange): Boolean;
var
  mIndex: Integer;
begin
  AChange := Default(TAtlasEditChange);
  mIndex := IndexOf(AFileName, AExpression);
  Result := mIndex >= 0;
  if Result then
  begin
    AChange := FItems[mIndex];
  end;
end;

procedure TAtlasEditChanges.Remove(const AFileName, AExpression: string);
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AFileName, AExpression);
  if mIndex >= 0 then
  begin
    Delete(FItems, mIndex, 1);
  end;
end;

procedure TAtlasEditChanges.Clear;
begin
  FItems := nil;
end;

function TAtlasEditChanges.Count: Integer;
begin
  Result := Length(FItems);
end;

function TAtlasEditChanges.Items: TArray<TAtlasEditChange>;
begin
  Result := FItems;
end;

end.
