unit Atlas.Common.Projects.Internals.MSBuild;

// Auswertung der MSBuild-Teile, die in .dproj-Dateien vorkommen:
// Eigenschaften mit $(Name)-Verweisen und Bedingungen wie
//   '$(Config)'=='Debug' or '$(Cfg_1)'!=''
//   ('$(Platform)'=='Win64' and '$(Base)'=='true')
//   Exists('$(BDS)\Bin\CodeGear.Delphi.Targets')
// Namen sind wie in MSBuild ohne Beachtung der Groß-/Kleinschreibung.
// Unbekannte Eigenschaften sind leer. Unbekannte Funktionen gelten als
// falsch, damit ein unbekannter Zweig nichts überschreibt.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TMSBuildProperties = class
  private
    FValues: TDictionary<string, string>;
    FNames: TList<string>;
    FFileExists: TFunc<string, Boolean>;
  public
    /// <summary>AFileExists beantwortet Exists(...); nil = immer falsch.</summary>
    constructor Create(const AFileExists: TFunc<string, Boolean>); overload;
    /// <summary>Wie oben mit AFileExists = nil.</summary>
    constructor Create; overload;
    destructor Destroy; override;
    function Get(const AName: string): string;
    procedure SetValue(const AName, AValue: string);
    function Has(const AName: string): Boolean;
    /// <summary>Ersetzt $(Name) durch den Wert; unbekannte Namen durch ''.</summary>
    function Expand(const AText: string): string;
    /// <summary>Wertet eine Bedingung aus; '' ist wahr. Syntaxfehler gelten als falsch.</summary>
    function Evaluate(const ACondition: string): Boolean;
    /// <summary>Alle gesetzten Eigenschaften in Reihenfolge des ersten Setzens.</summary>
    function ToArray: TArray<TPair<string, string>>;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TMSBuildText = (StringNotClosed, ComparisonExpected, UnexpectedCharacter, OperandExpected, Expected,
    NumberExpected);

const
  cTexts: array[TMSBuildText] of TAtlasText = (
    (De: 'String nicht abgeschlossen'; En: 'String not closed'),
    (De: 'Vergleich erwartet'; En: 'Comparison expected'),
    (De: 'Unerwartetes Zeichen'; En: 'Unexpected character'),
    (De: 'Operand erwartet'; En: 'Operand expected'),
    (De: '")" erwartet'; En: '")" expected'),
    (De: 'Zahl erwartet'; En: 'Number expected'));

{$SCOPEDENUMS OFF}

type
  EConditionError = class(Exception);

  TConditionParser = class
  private
    FText: string;
    FPos: Integer;
    FProperties: TMSBuildProperties;
    procedure SkipSpace;
    function TryKeyword(const AWord: string): Boolean;
    function ParseOr: Boolean;
    function ParseAnd: Boolean;
    function ParseNot: Boolean;
    function ParsePrimary: Boolean;
    function ParseOperand: string;
    function ParseFunction(const AName: string): Boolean;
    function ParseQuoted: string;
    function ParseBare: string;
    procedure ExpectClose;
    /// <summary>Name direkt vor "("; True, dann steht die Stelle hinter "(". Sonst bleibt sie unverändert.</summary>
    function TryFunctionName(out AName: string): Boolean;
    function ReadComparison: string;
  public
    constructor Create(const AText: string; AProperties: TMSBuildProperties);
    function Run: Boolean;
  end;

{ TMSBuildProperties }

constructor TMSBuildProperties.Create;
begin
  Create(nil);
end;

constructor TMSBuildProperties.Create(const AFileExists: TFunc<string, Boolean>);
begin
  inherited Create;
  FValues := TDictionary<string, string>.Create;
  FNames := TList<string>.Create;
  FFileExists := AFileExists;
end;

destructor TMSBuildProperties.Destroy;
begin
  FNames.Free;
  FValues.Free;
  inherited;
end;

function TMSBuildProperties.Get(const AName: string): string;
begin
  if not FValues.TryGetValue(UpperCase(AName), Result) then
  begin
    Result := '';
  end;
end;

function TMSBuildProperties.Has(const AName: string): Boolean;
begin
  Result := FValues.ContainsKey(UpperCase(AName));
end;

procedure TMSBuildProperties.SetValue(const AName, AValue: string);
var
  mKey: string;
begin
  mKey := UpperCase(AName);
  if not FValues.ContainsKey(mKey) then
  begin
    FNames.Add(AName);
  end;
  FValues.AddOrSetValue(mKey, AValue);
end;

function TMSBuildProperties.Expand(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mClose: Integer;
begin
  if Pos('$(', AText) = 0 then
  begin
    Exit(AText);
  end;
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      if (AText[mIndex] = '$') and (mIndex < Length(AText)) and (AText[mIndex + 1] = '(') then
      begin
        mClose := Pos(')', AText, mIndex + 2);
        if mClose > 0 then
        begin
          mBuilder.Append(Get(Trim(Copy(AText, mIndex + 2, mClose - mIndex - 2))));
          mIndex := mClose + 1;
          Continue;
        end;
      end;
      mBuilder.Append(AText[mIndex]);
      Inc(mIndex);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function TMSBuildProperties.Evaluate(const ACondition: string): Boolean;
var
  mParser: TConditionParser;
begin
  if Trim(ACondition) = '' then
  begin
    Exit(True);
  end;
  mParser := TConditionParser.Create(ACondition, Self);
  try
    try
      Result := mParser.Run;
    except
      on EConditionError do
        Result := False;
    end;
  finally
    mParser.Free;
  end;
end;

function TMSBuildProperties.ToArray: TArray<TPair<string, string>>;
var
  mIndex: Integer;
begin
  SetLength(Result, FNames.Count);
  for mIndex := 0 to FNames.Count - 1 do
  begin
    Result[mIndex] := TPair<string, string>.Create(FNames[mIndex], Get(FNames[mIndex]));
  end;
end;

{ TConditionParser }

constructor TConditionParser.Create(const AText: string; AProperties: TMSBuildProperties);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
  FProperties := AProperties;
end;

procedure TConditionParser.SkipSpace;
begin
  while (FPos <= Length(FText)) and CharInSet(FText[FPos], [' ', #9, #10, #13]) do
  begin
    Inc(FPos);
  end;
end;

function TConditionParser.TryKeyword(const AWord: string): Boolean;
var
  mAfter: Integer;
begin
  SkipSpace;
  mAfter := FPos + Length(AWord);
  Result := SameText(Copy(FText, FPos, Length(AWord)), AWord) and
    ((mAfter > Length(FText)) or not CharInSet(FText[mAfter], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
  if Result then
  begin
    FPos := mAfter;
  end;
end;

function TConditionParser.Run: Boolean;
begin
  Result := ParseOr;
  SkipSpace;
  if FPos <= Length(FText) then
  begin
    raise EConditionError.Create(cTexts[TMSBuildText.UnexpectedCharacter].Text);
  end;
end;

function TConditionParser.ParseOr: Boolean;
var
  mRight: Boolean;
begin
  Result := ParseAnd;
  while TryKeyword('or') do
  begin
    mRight := ParseAnd;
    Result := Result or mRight;
  end;
end;

function TConditionParser.ParseAnd: Boolean;
var
  mRight: Boolean;
begin
  Result := ParseNot;
  while TryKeyword('and') do
  begin
    mRight := ParseNot;
    Result := Result and mRight;
  end;
end;

function TConditionParser.ParseNot: Boolean;
begin
  SkipSpace;
  if (FPos <= Length(FText)) and (FText[FPos] = '!') and
    ((FPos = Length(FText)) or (FText[FPos + 1] <> '=')) then
  begin
    Inc(FPos);
    Exit(not ParseNot);
  end;
  Result := ParsePrimary;
end;

function TConditionParser.ParseQuoted: string;
var
  mQuote: Char;
  mStart: Integer;
begin
  mQuote := FText[FPos];
  Inc(FPos);
  mStart := FPos;
  while (FPos <= Length(FText)) and (FText[FPos] <> mQuote) do
  begin
    Inc(FPos);
  end;
  if FPos > Length(FText) then
  begin
    raise EConditionError.Create(cTexts[TMSBuildText.StringNotClosed].Text);
  end;
  Result := FProperties.Expand(Copy(FText, mStart, FPos - mStart));
  Inc(FPos);
end;

function TConditionParser.ParseBare: string;
var
  mStart: Integer;
begin
  // Unquotierte Werte wie true, false, Zahlen oder $(X).
  mStart := FPos;
  while (FPos <= Length(FText)) and not CharInSet(FText[FPos], [' ', #9, #10, #13, '=', '!', '<', '>', '(', ')']) do
  begin
    if (FText[FPos] = '$') and (FPos < Length(FText)) and (FText[FPos + 1] = '(') then
    begin
      FPos := PosEx(')', FText, FPos);
      if FPos = 0 then
      begin
        FPos := Length(FText) + 1;
      end;
    end;
    Inc(FPos);
  end;
  if FPos = mStart then
  begin
    raise EConditionError.Create(cTexts[TMSBuildText.OperandExpected].Text);
  end;
  Result := FProperties.Expand(Copy(FText, mStart, FPos - mStart));
end;

function TConditionParser.ParseOperand: string;
begin
  SkipSpace;
  if FPos > Length(FText) then
  begin
    raise EConditionError.Create(cTexts[TMSBuildText.OperandExpected].Text);
  end;
  if CharInSet(FText[FPos], ['''', '"']) then
  begin
    Result := ParseQuoted;
  end
  else
  begin
    Result := ParseBare;
  end;
end;

function TConditionParser.ParseFunction(const AName: string): Boolean;
var
  mArgument: string;
begin
  mArgument := ParseOperand;
  ExpectClose;
  if SameText(AName, 'Exists') then
  begin
    Result := Assigned(FProperties.FFileExists) and FProperties.FFileExists(mArgument);
  end
  else if SameText(AName, 'HasTrailingSlash') then
  begin
    Result := (mArgument <> '') and CharInSet(mArgument[Length(mArgument)], ['\', '/']);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TConditionParser.ExpectClose;
begin
  SkipSpace;
  if (FPos > Length(FText)) or (FText[FPos] <> ')') then
  begin
    raise EConditionError.Create(cTexts[TMSBuildText.Expected].Text);
  end;
  Inc(FPos);
end;

function TConditionParser.TryFunctionName(out AName: string): Boolean;
var
  mStart: Integer;
begin
  mStart := FPos;
  while (FPos <= Length(FText)) and CharInSet(FText[FPos], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(FPos);
  end;
  Result := (FPos > mStart) and (FPos <= Length(FText)) and (FText[FPos] = '(');
  if Result then
  begin
    AName := Copy(FText, mStart, FPos - mStart);
    Inc(FPos);
  end
  else
  begin
    FPos := mStart;
  end;
end;

/// <summary>Vergleichsoperator an der Stelle; '' = keiner.</summary>
function TConditionParser.ReadComparison: string;
begin
  Result := Copy(FText, FPos, 2);
  if (Result = '==') or (Result = '!=') or (Result = '<=') or (Result = '>=') then
  begin
    Inc(FPos, 2);
  end
  else if (Result <> '') and CharInSet(Result[1], ['<', '>']) then
  begin
    Result := Result[1];
    Inc(FPos);
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Einzelner Wert ohne Vergleich: true oder false.</summary>
function SingleValue(const AValue: string): Boolean;
begin
  if not SameText(AValue, 'true') and not SameText(AValue, 'false') then
  begin
    raise EConditionError.Create(cTexts[TMSBuildText.ComparisonExpected].Text);
  end;
  Result := SameText(AValue, 'true');
end;

function CompareNumbers(const ALeft, AOperator, ARight: string): Boolean;
var
  mLeft, mRight: Double;
begin
  if not (TryStrToFloat(ALeft, mLeft, TFormatSettings.Invariant) and
    TryStrToFloat(ARight, mRight, TFormatSettings.Invariant)) then
  begin
    raise EConditionError.Create(cTexts[TMSBuildText.NumberExpected].Text);
  end;
  case IndexStr(AOperator, ['<', '>', '<=']) of
    0:
      Result := mLeft < mRight;
    1:
      Result := mLeft > mRight;
    2:
      Result := mLeft <= mRight;
  else
    Result := mLeft >= mRight;
  end;
end;

function Compare(const ALeft, AOperator, ARight: string): Boolean;
begin
  if AOperator = '==' then
  begin
    Result := SameText(ALeft, ARight);
  end
  else if AOperator = '!=' then
  begin
    Result := not SameText(ALeft, ARight);
  end
  else
  begin
    Result := CompareNumbers(ALeft, AOperator, ARight);
  end;
end;

function TConditionParser.ParsePrimary: Boolean;
var
  mLeft, mOperator, mName: string;
begin
  SkipSpace;
  if (FPos <= Length(FText)) and (FText[FPos] = '(') then
  begin
    Inc(FPos);
    Result := ParseOr;
    ExpectClose;
  end
  else if TryFunctionName(mName) then
  begin
    // Funktionsaufruf: Name(
    Result := ParseFunction(mName);
  end
  else
  begin
    mLeft := ParseOperand;
    SkipSpace;
    mOperator := ReadComparison;
    if mOperator = '' then
    begin
      Result := SingleValue(mLeft);
    end
    else
    begin
      Result := Compare(mLeft, mOperator, ParseOperand);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Projects.Internals.MSBuild', cTexts);

end.
