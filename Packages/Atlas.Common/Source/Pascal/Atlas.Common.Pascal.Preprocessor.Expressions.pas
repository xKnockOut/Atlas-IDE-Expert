unit Atlas.Common.Pascal.Preprocessor.Expressions;

// Auswerter für $IF-Ausdrücke des Präprozessors (#847), aus
// Atlas.Common.Pascal.Preprocessor ausgelagert: Defined, Declared,
// CompilerVersion, RTLVersion, die booleschen Versionskonstanten RTLVersion111 …,
// SizeOf/High/Low der Grundtypen aus der Zielplattform, Ord, Zahlen, Konstanten
// aus den Einstellungen, Vergleiche, and/or/xor/not und Klammern.
// - Unbekannte Werte: Konstanten aus dem Code, Declared ohne Treffer und
//   unbekannte Typen ergeben „unbekannt“.
// - Jeder ausgewertete Teilausdruck mit Wert und Herkunft steht in Parts, für
//   den Hover.
// - Syntaxfehler lösen EPreprocessorExpression aus.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract;

type
  EPreprocessorExpression = class(Exception);

  /// <summary>Wert im Auswerter: Zahl oder unbekannt (#847).</summary>
  TEvalValue = record
    Known: Boolean;
    Number: Double;
    class function Make(ANumber: Double): TEvalValue; static;
    class function Unknown: TEvalValue; static;
    function IsTrue: Boolean;
    function IsFalse: Boolean;
  end;

  /// <summary>Was der Auswerter außer den Symbolen kennt.</summary>
  TExpressionSettings = record
    /// <summary>0 = unbekannt.</summary>
    CompilerVersion: Double;
    /// <summary>0 = unbekannt.</summary>
    RTLVersion: Double;
    /// <summary>Weitere Konstanten als Name=Wert.</summary>
    Constants: TArray<TPair<string, Double>>;
    /// <summary>Beantwortet Declared(X); nil = alles Unbekannte bleibt unbekannt.</summary>
    Declared: TDeclaredFunc;
    /// <summary>Herkunft von CompilerVersion und RTLVersion111 … ("Delphi 13"); '' ohne Version.</summary>
    ProductName: string;
    /// <summary>Zielplattform ("Win64") als Herkunft von SizeOf(Pointer) usw.; '' ohne.</summary>
    Platform: string;
  end;

  /// <summary>Größen und Wertebereiche der Grundtypen auf der Zielplattform.</summary>
  TTargetTypes = record
  private
    FPointerSize: Integer;
    FPlatform: string;
    FWindows: Boolean;
    FArm: Boolean;
    FX64: Boolean;
    /// <summary>Größe eines Typs, die von der Plattform abhängt; AKnown: Der Typ gehört dazu.</summary>
    function PlatformSize(const AName: string; out AKnown: Boolean): Integer;
    function LongSize: Integer;
    function ExtendedSize: Integer;
    function VariantSize: Integer;
  public
    /// <summary>Zeigergröße und Plattform aus den vordefinierten Symbolen (Schlüssel in Großbuchstaben).</summary>
    procedure Init(ADefines: TDictionary<string, Boolean>; const APlatform: string);
    /// <summary>Größe in Byte, 0 = unbekannt. Größen, die von der Plattform abhängen, nennen sie als Herkunft.
    /// </summary>
    function Size(const AType: string; out AOrigin: string): Integer;
    /// <summary>Wertebereich eines Ganzzahl-, Zeichen- oder Wahrheitstyps; False bei anderen Typen.</summary>
    function Range(const AType: string; out ALow, AHigh: Double; out AOrigin: string): Boolean;
  end;

  /// <summary>Rekursiv absteigender Auswerter für $IF-Ausdrücke.</summary>
  TExpressionEvaluator = class
  private
    FTokens: TArray<TPascalToken>;
    FIndex: Integer;
    FSettings: TExpressionSettings;
    FDefines: TDictionary<string, Boolean>;
    FParts: TList<TConditionPart>;
    FTypes: TTargetTypes;
    function Peek: TPascalToken;
    function AtEnd: Boolean;
    function Next: TPascalToken;
    procedure Expect(const ASymbol: string);
    function IsWord(const AWord: string): Boolean;
    function ParseOr: TEvalValue;
    function ParseAnd: TEvalValue;
    function ParseComparison: TEvalValue;
    function ParseAdditive: TEvalValue;
    function ParseMultiplicative: TEvalValue;
    function ParseUnary: TEvalValue;
    function ParsePrimary: TEvalValue;
    /// <summary>Name, Funktion oder Konstante.</summary>
    function ParseNamed: TEvalValue;
    function ParseFunction(const AName: string; out AValue: TEvalValue): Boolean;
    function ParseSizeOf: TEvalValue;
    /// <summary>High(Typ) bzw. Low(Typ).</summary>
    function ParseRange(const AName: string): TEvalValue;
    function ParseOrd: TEvalValue;
    /// <summary>"(Name)" als Argument einer Funktion.</summary>
    function ReadArgument: string;
    function ReadName: string;
    procedure AddPart(const AText, AValue, AOrigin: string);
    /// <summary>CompilerVersion, RTLVersion, RTLVersion111 … und Konstanten aus den Einstellungen; False für
    /// andere Namen.</summary>
    function KnownConstant(const AName: string; out AValue: TEvalValue): Boolean;
    /// <summary>Konstante aus den Einstellungen.</summary>
    function SettingsConstant(const AName: string; out AValue: TEvalValue): Boolean;
    function Declared(const AName: string; out AOrigin: string): TEvalValue;
    function VersionConstant(const AName: string; out AValue: TEvalValue): Boolean;
  public
    constructor Create(const ASettings: TExpressionSettings; ADefines: TDictionary<string, Boolean>);
    destructor Destroy; override;
    /// <summary>Wert von AExpression; löst EPreprocessorExpression bei Syntaxfehlern aus.</summary>
    function Evaluate(const AExpression: string): TConditionValue;
    /// <summary>Teilwerte der letzten Auswertung.</summary>
    function Parts: TArray<TConditionPart>;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer;

const
  BooleanValue: array[Boolean] of Double = (0, 1);

function BoolText(const AValue: TEvalValue): string;
begin
  if not AValue.Known then
  begin
    Result := 'unbekannt';
  end
  else if AValue.Number <> 0 then
  begin
    Result := 'wahr';
  end
  else
  begin
    Result := 'falsch';
  end;
end;

function NumberText(const AValue: TEvalValue): string;
begin
  if AValue.Known then
  begin
    Result := FloatToStr(AValue.Number, TFormatSettings.Invariant);
  end
  else
  begin
    Result := 'unbekannt';
  end;
end;

/// <summary>Vergleich mit dem Operator AOperator (=, &lt;&gt;, &lt;, &gt;, &lt;=, &gt;=).</summary>
function Compare(const AOperator: string; ALeft, ARight: Double): Boolean;
begin
  case IndexStr(AOperator, ['=', '<>', '<', '>', '<=']) of
    0:
      Result := SameValue(ALeft, ARight);
    1:
      Result := not SameValue(ALeft, ARight);
    2:
      Result := ALeft < ARight;
    3:
      Result := ALeft > ARight;
    4:
      Result := ALeft <= ARight;
  else
    Result := ALeft >= ARight;
  end;
end;

/// <summary>Größe eines Typs, die auf allen Plattformen gleich ist; 0 sonst.</summary>
function FixedSize(const AName: string): Integer;
begin
  if MatchStr(AName, ['BYTE', 'SHORTINT', 'ANSICHAR', 'BOOLEAN', 'BYTEBOOL', 'INT8', 'UINT8']) then
  begin
    Result := 1;
  end
  else if MatchStr(AName, ['WORD', 'SMALLINT', 'CHAR', 'WIDECHAR', 'WORDBOOL', 'INT16', 'UINT16']) then
  begin
    Result := 2;
  end
  else if MatchStr(AName, ['INTEGER', 'CARDINAL', 'SINGLE', 'LONGBOOL', 'INT32', 'UINT32', 'FIXEDINT',
    'FIXEDUINT']) then
  begin
    Result := 4;
  end
  else if MatchStr(AName, ['INT64', 'UINT64', 'DOUBLE', 'CURRENCY', 'COMP', 'TDATETIME', 'REAL']) then
  begin
    Result := 8;
  end
  else
  begin
    Result := 0;
  end;
end;

/// <summary>Wertebereich von Wahrheits- und Zeichentypen; False für andere Typen.</summary>
function FixedRange(const AName: string; out ALow, AHigh: Double): Boolean;
begin
  ALow := 0;
  AHigh := 0;
  Result := True;
  if MatchStr(AName, ['BOOLEAN', 'BYTEBOOL', 'WORDBOOL', 'LONGBOOL']) then
  begin
    AHigh := 1;
  end
  else if MatchStr(AName, ['CHAR', 'WIDECHAR']) then
  begin
    AHigh := 65535;
  end
  else if AName = 'ANSICHAR' then
  begin
    AHigh := 255;
  end
  else
  begin
    Result := False;
  end;
end;

function IsSignedInteger(const AName: string): Boolean;
begin
  Result := MatchStr(AName, ['SHORTINT', 'SMALLINT', 'INTEGER', 'INT8', 'INT16', 'INT32', 'INT64', 'FIXEDINT',
    'NATIVEINT', 'INTPTR', 'LONGINT']);
end;

function IsUnsignedInteger(const AName: string): Boolean;
begin
  Result := MatchStr(AName, ['BYTE', 'WORD', 'CARDINAL', 'UINT8', 'UINT16', 'UINT32', 'UINT64', 'FIXEDUINT',
    'NATIVEUINT', 'UINTPTR', 'LONGWORD']);
end;

{ TEvalValue }

class function TEvalValue.Make(ANumber: Double): TEvalValue;
begin
  Result.Known := True;
  Result.Number := ANumber;
end;

class function TEvalValue.Unknown: TEvalValue;
begin
  Result.Known := False;
  Result.Number := 0;
end;

function TEvalValue.IsTrue: Boolean;
begin
  Result := Known and (Number <> 0);
end;

function TEvalValue.IsFalse: Boolean;
begin
  Result := Known and (Number = 0);
end;

{ TTargetTypes }

procedure TTargetTypes.Init(ADefines: TDictionary<string, Boolean>; const APlatform: string);
begin
  FPlatform := APlatform;
  FWindows := ADefines.ContainsKey('MSWINDOWS');
  FArm := ADefines.ContainsKey('CPUARM');
  FX64 := ADefines.ContainsKey('CPUX64');
  if ADefines.ContainsKey('CPU64BITS') or ADefines.ContainsKey('WIN64') then
  begin
    FPointerSize := 8;
  end
  else if ADefines.ContainsKey('CPU32BITS') or ADefines.ContainsKey('WIN32') then
  begin
    FPointerSize := 4;
  end
  else
  begin
    FPointerSize := 0;
  end;
end;

function TTargetTypes.LongSize: Integer;
begin
  // 64-Bit-POSIX: 8, sonst 4.
  if (FPointerSize = 8) and not FWindows then
  begin
    Result := 8;
  end
  else if FPointerSize > 0 then
  begin
    Result := 4;
  end
  else
  begin
    Result := 0;
  end;
end;

function TTargetTypes.ExtendedSize: Integer;
begin
  if FWindows and (FPointerSize = 4) then
  begin
    Result := 10;
  end
  else if FWindows or FArm then
  begin
    Result := 8;
  end
  else if FX64 then
  begin
    Result := 16;
  end
  else
  begin
    Result := 0;
  end;
end;

function TTargetTypes.VariantSize: Integer;
begin
  case FPointerSize of
    8:
      Result := 24;
    4:
      Result := 16;
  else
    Result := 0;
  end;
end;

function TTargetTypes.PlatformSize(const AName: string; out AKnown: Boolean): Integer;
begin
  AKnown := True;
  if MatchStr(AName, ['POINTER', 'NATIVEINT', 'NATIVEUINT', 'INTPTR', 'UINTPTR', 'PCHAR', 'PANSICHAR', 'PWIDECHAR',
    'STRING', 'UNICODESTRING', 'ANSISTRING', 'RAWBYTESTRING', 'UTF8STRING', 'WIDESTRING', 'TOBJECT', 'TCLASS',
    'IINTERFACE', 'IUNKNOWN', 'THANDLE', 'HWND', 'WPARAM', 'LPARAM', 'LRESULT']) then
  begin
    Result := FPointerSize;
  end
  else if MatchStr(AName, ['LONGINT', 'LONGWORD']) then
  begin
    Result := LongSize;
  end
  else if AName = 'EXTENDED' then
  begin
    Result := ExtendedSize;
  end
  else
  begin
    // Variant nur mit bekannter Größe, sonst wie ein unbekannter Typ ohne Herkunft.
    Result := 0;
    if AName = 'VARIANT' then
    begin
      Result := VariantSize;
    end;
    AKnown := Result > 0;
  end;
end;

function TTargetTypes.Size(const AType: string; out AOrigin: string): Integer;
var
  mName: string;
  mKnown: Boolean;
begin
  mName := UpperCase(AType);
  AOrigin := '';
  Result := FixedSize(mName);
  if Result > 0 then
  begin
    Exit;
  end;
  Result := PlatformSize(mName, mKnown);
  if mKnown and (FPlatform <> '') then
  begin
    AOrigin := 'Zielplattform ' + FPlatform;
  end;
end;

function TTargetTypes.Range(const AType: string; out ALow, AHigh: Double; out AOrigin: string): Boolean;
var
  mName: string;
  mSize: Integer;
  mSigned: Boolean;
begin
  mName := UpperCase(AType);
  AOrigin := '';
  if FixedRange(mName, ALow, AHigh) then
  begin
    Exit(True);
  end;
  mSigned := IsSignedInteger(mName);
  mSize := 0;
  if mSigned or IsUnsignedInteger(mName) then
  begin
    mSize := Size(mName, AOrigin);
  end;
  Result := mSize > 0;
  if not Result then
  begin
    Exit;
  end;
  if mSigned then
  begin
    AHigh := Power(2, mSize * 8 - 1) - 1;
    ALow := -AHigh - 1;
  end
  else
  begin
    ALow := 0;
    AHigh := Power(2, mSize * 8) - 1;
  end;
end;

{ TExpressionEvaluator }

constructor TExpressionEvaluator.Create(const ASettings: TExpressionSettings; ADefines: TDictionary<string, Boolean>);
begin
  inherited Create;
  FSettings := ASettings;
  FDefines := ADefines;
  FParts := TList<TConditionPart>.Create;
  FTypes.Init(ADefines, ASettings.Platform);
end;

destructor TExpressionEvaluator.Destroy;
begin
  FParts.Free;
  inherited Destroy;
end;

function TExpressionEvaluator.Parts: TArray<TConditionPart>;
begin
  Result := FParts.ToArray;
end;

procedure TExpressionEvaluator.AddPart(const AText, AValue, AOrigin: string);
var
  Part: TConditionPart;
begin
  Part.Text := AText;
  Part.Value := AValue;
  Part.Origin := AOrigin;
  FParts.Add(Part);
end;

function TExpressionEvaluator.AtEnd: Boolean;
begin
  Result := FIndex >= Length(FTokens);
end;

function TExpressionEvaluator.Peek: TPascalToken;
begin
  if AtEnd then
  begin
    Result := Default(TPascalToken);
    Result.Kind := TPascalTokenKind.Unknown;
  end
  else
  begin
    Result := FTokens[FIndex];
  end;
end;

function TExpressionEvaluator.Next: TPascalToken;
begin
  if AtEnd then
  begin
    raise EPreprocessorExpression.Create('Ausdruck endet unerwartet');
  end;
  Result := FTokens[FIndex];
  Inc(FIndex);
end;

procedure TExpressionEvaluator.Expect(const ASymbol: string);
begin
  if AtEnd or not Peek.IsSymbol(ASymbol) then
  begin
    raise EPreprocessorExpression.CreateFmt('"%s" erwartet', [ASymbol]);
  end;
  Inc(FIndex);
end;

function TExpressionEvaluator.IsWord(const AWord: string): Boolean;
begin
  Result := not AtEnd and (Peek.Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier]) and
    SameText(Peek.Text, AWord);
end;

function TExpressionEvaluator.ReadName: string;
begin
  if AtEnd or not (Peek.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
  begin
    raise EPreprocessorExpression.Create('Name erwartet');
  end;
  Result := Next.Text;
  // Qualifizierte Namen wie System.SysUtils
  while not AtEnd and Peek.IsSymbol('.') do
  begin
    Inc(FIndex);
    if AtEnd or not (Peek.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      raise EPreprocessorExpression.Create('Name erwartet');
    end;
    Result := Result + '.' + Next.Text;
  end;
end;

function TExpressionEvaluator.ReadArgument: string;
begin
  Expect('(');
  Result := ReadName;
  Expect(')');
end;

function TExpressionEvaluator.Evaluate(const AExpression: string): TConditionValue;
var
  Significant: TList<TPascalToken>;
  Token: TPascalToken;
  Value: TEvalValue;
begin
  Significant := TList<TPascalToken>.Create;
  try
    for Token in TPascalLexer.Tokenize(AExpression) do
    begin
      if Token.Kind <> TPascalTokenKind.Comment then
      begin
        Significant.Add(Token);
      end;
    end;
    FTokens := Significant.ToArray;
  finally
    Significant.Free;
  end;
  FIndex := 0;
  FParts.Clear;
  if AtEnd then
  begin
    raise EPreprocessorExpression.Create('Ausdruck fehlt');
  end;
  Value := ParseOr;
  if not AtEnd then
  begin
    raise EPreprocessorExpression.CreateFmt('Unerwartet: "%s"', [Peek.Text]);
  end;
  if not Value.Known then
  begin
    Result := TConditionValue.Unknown;
  end
  else if Value.Number <> 0 then
  begin
    Result := TConditionValue.Yes;
  end
  else
  begin
    Result := TConditionValue.No;
  end;
end;

function TExpressionEvaluator.ParseOr: TEvalValue;
var
  Right: TEvalValue;
  IsXor: Boolean;
begin
  Result := ParseAnd;
  while IsWord('or') or IsWord('xor') do
  begin
    IsXor := IsWord('xor');
    Inc(FIndex);
    Right := ParseAnd;
    if IsXor then
    begin
      if Result.Known and Right.Known then
      begin
        Result := TEvalValue.Make(BooleanValue[(Result.Number <> 0) xor (Right.Number <> 0)]);
      end
      else
      begin
        Result := TEvalValue.Unknown;
      end;
    end
    // Ein sicher wahrer Teil macht or wahr, auch neben einem unbekannten.
    else if Result.IsTrue or Right.IsTrue then
    begin
      Result := TEvalValue.Make(1);
    end
    else if Result.Known and Right.Known then
    begin
      Result := TEvalValue.Make(0);
    end
    else
    begin
      Result := TEvalValue.Unknown;
    end;
  end;
end;

function TExpressionEvaluator.ParseAnd: TEvalValue;
var
  Right: TEvalValue;
begin
  Result := ParseComparison;
  while IsWord('and') do
  begin
    Inc(FIndex);
    Right := ParseComparison;
    if Result.IsFalse or Right.IsFalse then
    begin
      Result := TEvalValue.Make(0);
    end
    else if Result.Known and Right.Known then
    begin
      Result := TEvalValue.Make(1);
    end
    else
    begin
      Result := TEvalValue.Unknown;
    end;
  end;
end;

function TExpressionEvaluator.ParseComparison: TEvalValue;
var
  mOperator: string;
  mRight: TEvalValue;
begin
  Result := ParseAdditive;
  if AtEnd or (Peek.Kind <> TPascalTokenKind.Symbol) then
  begin
    Exit;
  end;
  if not MatchStr(Peek.Text, ['=', '<>', '<', '>', '<=', '>=']) then
  begin
    Exit;
  end;
  mOperator := Next.Text;
  mRight := ParseAdditive;
  if Result.Known and mRight.Known then
  begin
    Result := TEvalValue.Make(BooleanValue[Compare(mOperator, Result.Number, mRight.Number)]);
  end
  else
  begin
    Result := TEvalValue.Unknown;
  end;
end;

function TExpressionEvaluator.ParseAdditive: TEvalValue;
var
  Plus: Boolean;
  Right: TEvalValue;
begin
  Result := ParseMultiplicative;
  while not AtEnd and (Peek.IsSymbol('+') or Peek.IsSymbol('-')) do
  begin
    Plus := Next.Text = '+';
    Right := ParseMultiplicative;
    if not Result.Known or not Right.Known then
    begin
      Result := TEvalValue.Unknown;
    end
    else if Plus then
    begin
      Result := TEvalValue.Make(Result.Number + Right.Number);
    end
    else
    begin
      Result := TEvalValue.Make(Result.Number - Right.Number);
    end;
  end;
end;

function TExpressionEvaluator.ParseMultiplicative: TEvalValue;
var
  Op: string;
  Right: TEvalValue;
begin
  Result := ParseUnary;
  while not AtEnd and (Peek.IsSymbol('*') or IsWord('div') or IsWord('mod')) do
  begin
    Op := LowerCase(Next.Text);
    Right := ParseUnary;
    if (Op <> '*') and Right.IsFalse then
    begin
      raise EPreprocessorExpression.Create('Division durch null');
    end;
    if not Result.Known or not Right.Known then
    begin
      Result := TEvalValue.Unknown;
    end
    else if Op = '*' then
    begin
      Result := TEvalValue.Make(Result.Number * Right.Number);
    end
    else if Op = 'div' then
    begin
      Result := TEvalValue.Make(Trunc(Result.Number) div Trunc(Right.Number));
    end
    else
    begin
      Result := TEvalValue.Make(Trunc(Result.Number) mod Trunc(Right.Number));
    end;
  end;
end;

function TExpressionEvaluator.ParseUnary: TEvalValue;
begin
  if IsWord('not') then
  begin
    Inc(FIndex);
    Result := ParseUnary;
    if Result.Known then
    begin
      Result := TEvalValue.Make(BooleanValue[Result.Number = 0]);
    end;
  end
  else if not AtEnd and Peek.IsSymbol('-') then
  begin
    Inc(FIndex);
    Result := ParseUnary;
    if Result.Known then
    begin
      Result := TEvalValue.Make(-Result.Number);
    end;
  end
  else
  begin
    Result := ParsePrimary;
  end;
end;

function TExpressionEvaluator.SettingsConstant(const AName: string; out AValue: TEvalValue): Boolean;
var
  mPair: TPair<string, Double>;
begin
  for mPair in FSettings.Constants do
  begin
    if SameText(mPair.Key, AName) then
    begin
      AValue := TEvalValue.Make(mPair.Value);
      Exit(True);
    end;
  end;
  AValue := TEvalValue.Unknown;
  Result := False;
end;

function TExpressionEvaluator.Declared(const AName: string; out AOrigin: string): TEvalValue;
var
  mConstant: TEvalValue;
begin
  AOrigin := '';
  Result := TEvalValue.Unknown;
  // Was der Präprozessor selbst kennt: System-Konstanten und die Konstanten aus den Einstellungen.
  if SameText(AName, 'CompilerVersion') or SameText(AName, 'RTLVersion') then
  begin
    AOrigin := 'System';
    Result := TEvalValue.Make(1);
  end
  else if VersionConstant(AName, mConstant) then
  begin
    AOrigin := FSettings.ProductName;
    if mConstant.Known then
    begin
      Result := TEvalValue.Make(BooleanValue[mConstant.Number <> 0]);
    end;
  end
  else if SettingsConstant(AName, mConstant) then
  begin
    Result := TEvalValue.Make(1);
  end
  // Sonst der Index; ohne Treffer bleibt es unbekannt (die Unit kann noch fehlen).
  else if Assigned(FSettings.Declared) and FSettings.Declared(AName) then
  begin
    AOrigin := 'Index';
    Result := TEvalValue.Make(1);
  end;
end;

function TExpressionEvaluator.VersionConstant(const AName: string; out AValue: TEvalValue): Boolean;
var
  Number, Major, Minor: Integer;
begin
  // RTLVersion111 (Delphi 11.1) … RTLVersion123: True ab dieser Version. Für die laufende Hauptversion gilt das
  // jüngste Update als installiert.
  AValue := TEvalValue.Unknown;
  Result := (Length(AName) = Length('RTLVersion') + 3) and
    SameText(Copy(AName, 1, Length('RTLVersion')), 'RTLVersion') and
    TryStrToInt(Copy(AName, Length('RTLVersion') + 1, 3), Number);
  if not Result then
  begin
    Exit;
  end;
  Major := Number div 10;
  Minor := Number mod 10;
  Result := (Major >= 11) and (Minor <> 0);
  if Result and (FSettings.CompilerVersion > 0) then
  begin
    AValue := TEvalValue.Make(BooleanValue[FSettings.CompilerVersion >= Major + 24]);
  end;
end;

function TExpressionEvaluator.ParseSizeOf: TEvalValue;
var
  mArgument, mOrigin: string;
  mSize: Integer;
begin
  mArgument := ReadArgument;
  mSize := FTypes.Size(mArgument, mOrigin);
  Result := TEvalValue.Unknown;
  if mSize > 0 then
  begin
    Result := TEvalValue.Make(mSize);
  end;
  AddPart('SizeOf(' + mArgument + ')', NumberText(Result), mOrigin);
end;

function TExpressionEvaluator.ParseRange(const AName: string): TEvalValue;
var
  mArgument, mOrigin: string;
  mLow, mHigh: Double;
begin
  mArgument := ReadArgument;
  if not FTypes.Range(mArgument, mLow, mHigh, mOrigin) then
  begin
    Result := TEvalValue.Unknown;
  end
  else if SameText(AName, 'High') then
  begin
    Result := TEvalValue.Make(mHigh);
  end
  else
  begin
    Result := TEvalValue.Make(mLow);
  end;
  AddPart(AName + '(' + mArgument + ')', NumberText(Result), mOrigin);
end;

function TExpressionEvaluator.ParseOrd: TEvalValue;
var
  mToken: TPascalToken;
begin
  Expect('(');
  mToken := Peek;
  if (mToken.Kind = TPascalTokenKind.StringLiteral) and (Length(mToken.Text) = 3) then
  begin
    Inc(FIndex);
    Result := TEvalValue.Make(Ord(mToken.Text[2]));
  end
  else
  begin
    Result := ParseOr;
  end;
  Expect(')');
end;

function TExpressionEvaluator.ParseFunction(const AName: string; out AValue: TEvalValue): Boolean;
var
  Argument, Origin: string;
begin
  Result := True;
  if SameText(AName, 'Defined') then
  begin
    AValue := TEvalValue.Make(BooleanValue[FDefines.ContainsKey(UpperCase(ReadArgument))]);
  end
  else if SameText(AName, 'Declared') then
  begin
    Argument := ReadArgument;
    AValue := Declared(Argument, Origin);
    AddPart('Declared(' + Argument + ')', BoolText(AValue), Origin);
  end
  else if SameText(AName, 'SizeOf') then
  begin
    AValue := ParseSizeOf;
  end
  else if SameText(AName, 'High') or SameText(AName, 'Low') then
  begin
    AValue := ParseRange(AName);
  end
  else if SameText(AName, 'Ord') then
  begin
    AValue := ParseOrd;
  end
  else
  begin
    Result := False;
  end;
end;

function TExpressionEvaluator.KnownConstant(const AName: string; out AValue: TEvalValue): Boolean;
begin
  Result := True;
  if SameText(AName, 'CompilerVersion') and (FSettings.CompilerVersion > 0) then
  begin
    AValue := TEvalValue.Make(FSettings.CompilerVersion);
    AddPart(AName, NumberText(AValue), FSettings.ProductName);
  end
  else if SameText(AName, 'RTLVersion') and (FSettings.RTLVersion > 0) then
  begin
    AValue := TEvalValue.Make(FSettings.RTLVersion);
    AddPart(AName, NumberText(AValue), FSettings.ProductName);
  end
  else if SameText(AName, 'CompilerVersion') or SameText(AName, 'RTLVersion') then
  begin
    AValue := TEvalValue.Unknown;
    AddPart(AName, NumberText(AValue), FSettings.ProductName);
  end
  else if VersionConstant(AName, AValue) then
  begin
    AddPart(AName, BoolText(AValue), FSettings.ProductName);
  end
  else
  begin
    Result := SettingsConstant(AName, AValue);
  end;
end;

function TExpressionEvaluator.ParseNamed: TEvalValue;
var
  mName: string;
begin
  mName := ReadName;
  if not AtEnd and Peek.IsSymbol('(') and ParseFunction(mName, Result) then
  begin
    Exit;
  end;
  if KnownConstant(mName, Result) then
  begin
    Exit;
  end;
  // Konstante aus dem Code oder einer anderen Unit: Der Wert ist hier nicht bekannt.
  if not AtEnd and Peek.IsSymbol('(') then
  begin
    raise EPreprocessorExpression.CreateFmt('Unbekannte Funktion "%s"', [mName]);
  end;
  Result := TEvalValue.Unknown;
  AddPart(mName, 'unbekannt', 'Konstante aus dem Code');
end;

function TExpressionEvaluator.ParsePrimary: TEvalValue;
var
  Token: TPascalToken;
  Number: Double;
begin
  Token := Peek;
  if Token.IsSymbol('(') then
  begin
    Inc(FIndex);
    Result := ParseOr;
    Expect(')');
  end
  else if Token.Kind = TPascalTokenKind.Number then
  begin
    Inc(FIndex);
    if not TryStrToFloat(Token.Text, Number, TFormatSettings.Invariant) then
    begin
      Number := StrToIntDef(Token.Text, 0);
    end;
    Result := TEvalValue.Make(Number);
  end
  else if IsWord('True') or IsWord('False') then
  begin
    Result := TEvalValue.Make(BooleanValue[IsWord('True')]);
    Inc(FIndex);
  end
  else
  begin
    Result := ParseNamed;
  end;
end;

end.
