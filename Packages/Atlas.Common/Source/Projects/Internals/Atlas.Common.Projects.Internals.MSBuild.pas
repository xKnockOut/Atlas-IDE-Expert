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
  Key: string;
begin
  Key := UpperCase(AName);
  if not FValues.ContainsKey(Key) then
  begin
    FNames.Add(AName);
  end;
  FValues.AddOrSetValue(Key, AValue);
end;

function TMSBuildProperties.Expand(const AText: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  Close: Integer;
begin
  if Pos('$(', AText) = 0 then
  begin
    Exit(AText);
  end;
  Builder := TStringBuilder.Create;
  try
    Index := 1;
    while Index <= Length(AText) do
    begin
      if (AText[Index] = '$') and (Index < Length(AText)) and (AText[Index + 1] = '(') then
      begin
        Close := Pos(')', AText, Index + 2);
        if Close > 0 then
        begin
          Builder.Append(Get(Trim(Copy(AText, Index + 2, Close - Index - 2))));
          Index := Close + 1;
          Continue;
        end;
      end;
      Builder.Append(AText[Index]);
      Inc(Index);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function TMSBuildProperties.Evaluate(const ACondition: string): Boolean;
var
  Parser: TConditionParser;
begin
  if Trim(ACondition) = '' then
  begin
    Exit(True);
  end;
  Parser := TConditionParser.Create(ACondition, Self);
  try
    try
      Result := Parser.Run;
    except
      on EConditionError do
        Result := False;
    end;
  finally
    Parser.Free;
  end;
end;

function TMSBuildProperties.ToArray: TArray<TPair<string, string>>;
var
  Index: Integer;
begin
  SetLength(Result, FNames.Count);
  for Index := 0 to FNames.Count - 1 do
  begin
    Result[Index] := TPair<string, string>.Create(FNames[Index], Get(FNames[Index]));
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
  After: Integer;
begin
  SkipSpace;
  After := FPos + Length(AWord);
  Result := SameText(Copy(FText, FPos, Length(AWord)), AWord) and
    ((After > Length(FText)) or not CharInSet(FText[After], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
  if Result then
  begin
    FPos := After;
  end;
end;

function TConditionParser.Run: Boolean;
begin
  Result := ParseOr;
  SkipSpace;
  if FPos <= Length(FText) then
  begin
    raise EConditionError.Create('Unerwartetes Zeichen');
  end;
end;

function TConditionParser.ParseOr: Boolean;
var
  Right: Boolean;
begin
  Result := ParseAnd;
  while TryKeyword('or') do
  begin
    Right := ParseAnd;
    Result := Result or Right;
  end;
end;

function TConditionParser.ParseAnd: Boolean;
var
  Right: Boolean;
begin
  Result := ParseNot;
  while TryKeyword('and') do
  begin
    Right := ParseNot;
    Result := Result and Right;
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

function TConditionParser.ParseOperand: string;
var
  Quote: Char;
  Start: Integer;
begin
  SkipSpace;
  if FPos > Length(FText) then
  begin
    raise EConditionError.Create('Operand erwartet');
  end;
  if CharInSet(FText[FPos], ['''', '"']) then
  begin
    Quote := FText[FPos];
    Inc(FPos);
    Start := FPos;
    while (FPos <= Length(FText)) and (FText[FPos] <> Quote) do
    begin
      Inc(FPos);
    end;
    if FPos > Length(FText) then
    begin
      raise EConditionError.Create('String nicht abgeschlossen');
    end;
    Result := FProperties.Expand(Copy(FText, Start, FPos - Start));
    Inc(FPos);
  end
  else
  begin
    // Unquotierte Werte wie true, false, Zahlen oder $(X).
    Start := FPos;
    while (FPos <= Length(FText)) and not CharInSet(FText[FPos], [' ', #9, #10, #13, '=', '!', '<', '>', '(', ')']) do
    begin
      if (FText[FPos] = '$') and (FPos < Length(FText)) and (FText[FPos + 1] = '(') then
      begin
        while (FPos <= Length(FText)) and (FText[FPos] <> ')') do
        begin
          Inc(FPos);
        end;
      end;
      Inc(FPos);
    end;
    if FPos = Start then
    begin
      raise EConditionError.Create('Operand erwartet');
    end;
    Result := FProperties.Expand(Copy(FText, Start, FPos - Start));
  end;
end;

function TConditionParser.ParseFunction(const AName: string): Boolean;
var
  Argument: string;
begin
  Argument := ParseOperand;
  SkipSpace;
  if (FPos > Length(FText)) or (FText[FPos] <> ')') then
  begin
    raise EConditionError.Create('")" erwartet');
  end;
  Inc(FPos);
  if SameText(AName, 'Exists') then
  begin
    Result := Assigned(FProperties.FFileExists) and FProperties.FFileExists(Argument);
  end
  else if SameText(AName, 'HasTrailingSlash') then
  begin
    Result := (Argument <> '') and CharInSet(Argument[Length(Argument)], ['\', '/']);
  end
  else
  begin
    Result := False;
  end;
end;

function TConditionParser.ParsePrimary: Boolean;
var
  Left: string;
  Right: string;
  Op: string;
  Start: Integer;
  Name: string;
  LeftNumber: Double;
  RightNumber: Double;
begin
  SkipSpace;
  if (FPos <= Length(FText)) and (FText[FPos] = '(') then
  begin
    Inc(FPos);
    Result := ParseOr;
    SkipSpace;
    if (FPos > Length(FText)) or (FText[FPos] <> ')') then
    begin
      raise EConditionError.Create('")" erwartet');
    end;
    Inc(FPos);
    Exit;
  end;

  // Funktionsaufruf: Name(
  Start := FPos;
  while (FPos <= Length(FText)) and CharInSet(FText[FPos], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(FPos);
  end;
  if (FPos > Start) and (FPos <= Length(FText)) and (FText[FPos] = '(') then
  begin
    Name := Copy(FText, Start, FPos - Start);
    Inc(FPos);
    Exit(ParseFunction(Name));
  end;
  FPos := Start;

  Left := ParseOperand;
  SkipSpace;
  Op := Copy(FText, FPos, 2);
  if (Op = '==') or (Op = '!=') or (Op = '<=') or (Op = '>=') then
  begin
    Inc(FPos, 2);
  end
  else if (Op <> '') and CharInSet(Op[1], ['<', '>']) then
  begin
    Op := Op[1];
    Inc(FPos);
  end
  else
  begin
    // Einzelner Wert: true/false.
    if SameText(Left, 'true') then
    begin
      Exit(True);
    end;
    if SameText(Left, 'false') then
    begin
      Exit(False);
    end;
    raise EConditionError.Create('Vergleich erwartet');
  end;
  Right := ParseOperand;
  if Op = '==' then
  begin
    Result := SameText(Left, Right);
  end
  else if Op = '!=' then
  begin
    Result := not SameText(Left, Right);
  end
  else
  begin
    if not (TryStrToFloat(Left, LeftNumber, TFormatSettings.Invariant) and
      TryStrToFloat(Right, RightNumber, TFormatSettings.Invariant)) then
    begin
      raise EConditionError.Create('Zahl erwartet');
    end;
    if Op = '<' then
    begin
      Result := LeftNumber < RightNumber;
    end
    else if Op = '>' then
    begin
      Result := LeftNumber > RightNumber;
    end
    else if Op = '<=' then
    begin
      Result := LeftNumber <= RightNumber;
    end
    else
    begin
      Result := LeftNumber >= RightNumber;
    end;
  end;
end;

end.
