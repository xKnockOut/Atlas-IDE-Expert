unit Atlas.Common.Editing.CreateMethod;

// Methode aus Aufruf anlegen (#472, ARG-073), Teil ohne Namensauflösung:
//   - Site: Aufruf eines Namens am Cursor (auf dem Namen oder direkt hinter
//     seiner "("), mit Qualifizierer, Argumenten und Umgebung: eigene
//     Anweisung (Prozedur), rechte Seite einer Zuweisung, Bedingung (Boolean)
//     oder sonst ein Ausdruck. Fehlt die ")" noch (Auslöser "("), zählen die
//     Argumente bis zum Ende der Zeile bzw. Anweisung.
//   - Parameternamen aus den Argumenten: Variablen ohne F-, A- bzw. L-Präfix,
//     Aufrufe ohne Get, Literale nach ihrem Wert (0.1 → Rate) bzw. Typ (#452).
//   - Literaltypen: Gleitkomma Double, ganze Zahl Integer, String string.
//   - Kopf, Deklaration in der Klasse und Rumpf bzw. freie Routine davor.
// Typen der übrigen Argumente, Rückgabetyp und Zielklasse bringt
// Atlas.Common.Lsp.Refactorings über die Namensauflösung mit.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  /// <summary>Umgebung eines Aufrufs.</summary>
  TCallContext = (
    /// <summary>Eigene Anweisung: Prozedur.</summary>
    Statement,
    /// <summary>Ganze rechte Seite einer Zuweisung: Funktion mit dem Typ des Ziels.</summary>
    Assignment,
    /// <summary>Bedingung nach if, while, until, not, and, or: Funktion mit Boolean.</summary>
    Condition,
    /// <summary>Sonst in einem Ausdruck: Funktion mit dem erwarteten Typ.</summary>
    Expression);
  {$SCOPEDENUMS OFF}

  TCallArgument = record
    /// <summary>Erstes und letztes Token des Arguments.</summary>
    First: Integer;
    Last: Integer;
    Text: string;
  end;

  TCreateCallSite = record
    Name: string;
    NameIndex: Integer;
    NameRange: TTextRange;
    /// <summary>Kette vor dem Punkt ("Kunde", "Self.Liste"); '' ohne.</summary>
    Qualifier: string;
    /// <summary>Erstes Token des Aufrufs (Qualifizierer bzw. Name).</summary>
    CallStart: Integer;
    OpenIndex: Integer;
    /// <summary>Token der schließenden Klammer; -1, wenn sie noch fehlt.</summary>
    CloseIndex: Integer;
    Arguments: TArray<TCallArgument>;
    Context: TCallContext;
    /// <summary>Ziel der Zuweisung bei Context = Assignment, sonst ''.</summary>
    Target: string;
    /// <summary>Erstes Token der Anweisung, in der der Aufruf steht (für Probetexte).</summary>
    StatementStart: Integer;
  end;

  TCreateParameter = record
    Name: string;
    TypeName: string;
    IsConst: Boolean;
  end;

  /// <summary>Was entstehen soll.</summary>
  TCreateMethodPlan = record
    Name: string;
    Parameters: TArray<TCreateParameter>;
    /// <summary>Rückgabetyp; '' = Prozedur.</summary>
    ResultType: string;
    /// <summary>Klasse der Methode (auch TAussen.TInnen); '' = freie Routine vor ARoutine.</summary>
    TypeName: string;
    /// <summary>Abschnitt der Deklaration: private, protected oder public.</summary>
    Section: string;
    /// <summary>Klassenmethode (Aufruf aus einer Klassenmethode heraus).</summary>
    IsClassMethod: Boolean;
    /// <summary>"$0" in die leere Zeile des Rumpfs (Cursor dort nach dem Anlegen).</summary>
    CaretInBody: Boolean;
    Style: TFormatStyle;
  end;

  TCreateMethod = class
  public const
    /// <summary>Rückgabetyp, wenn er sich nicht ableiten lässt; als Kommentar meldet ihn der Compiler.</summary>
    cTypePlaceholder = '{Typ}';
  public
    /// <summary>Aufruf am Cursor: auf seinem Namen oder direkt hinter "Name(". False sonst, auch bei
    /// Deklarationen und Qualifizierern mit Klammern oder Indizes.</summary>
    class function Site(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
      out ASite: TCreateCallSite): Boolean; static;
    /// <summary>Typ eines Arguments, das nur ein Literal ist; '' sonst.</summary>
    class function LiteralType(const ATokens: TArray<TPascalToken>; const AArgument: TCallArgument): string; static;
    /// <summary>Name aus dem Argument; '' wenn es keinen hergibt (dann aus dem Typ).</summary>
    class function ArgumentName(const ATokens: TArray<TPascalToken>; const AArgument: TCallArgument): string; static;
    /// <summary>Name aus dem Typ (#452): ohne T- bzw. I-Präfix und Typargumente; Value, wenn nichts bleibt.</summary>
    class function NameFromType(const ATypeName: string): string; static;
    /// <summary>const für Strings, Records und Interfaces.</summary>
    class function WantsConst(const ATypeName: string; AIsRecord, AIsInterface: Boolean): Boolean; static;
    /// <summary>ANames eindeutig gemacht (Value, Value2 …), ohne Groß-/Kleinschreibung.</summary>
    class function UniqueNames(const ANames: TArray<string>): TArray<string>; static;
    /// <summary>"(Customer: TCustomer; Rate: Double)"; '' ohne Parameter.</summary>
    class function ParameterList(const AParameters: TArray<TCreateParameter>): string; static;
    /// <summary>Kopf ohne ";": "function CalcDiscount(…): Currency", mit AQualified "function TFoo.CalcDiscount…".
    /// </summary>
    class function Header(const APlan: TCreateMethodPlan; AQualified: Boolean): string; static;
    /// <summary>Deklaration und Rumpf für eine Methode von APlan.TypeName in AText; False, wenn die Klasse dort
    /// nicht passend steht.</summary>
    class function MethodEdits(const AText: string; ATree: TSyntaxTree; const APlan: TCreateMethodPlan;
      out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Freie Routine vor ARoutine (samt Kommentaren darüber).</summary>
    class function RoutineEdit(const AText: string; ARoutine: TSyntaxNode; const APlan: TCreateMethodPlan): TTextEdit;
      static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Text.Lines,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ClassCompletion;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

/// <summary>Vor diesem Token beginnt eine Anweisung.</summary>
function StartsStatementAfter(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or IsKeywordIn(AToken, ['begin', 'then', 'do', 'else', 'repeat', 'try',
    'finally', 'except', 'initialization', 'finalization']);
end;

/// <summary>Mit diesem Token endet eine Anweisung.</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or IsKeywordIn(AToken, ['end', 'else', 'until', 'except', 'finally']);
end;

function TokensText(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to ALast do
  begin
    if not (ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      if (Result <> '') and (ATokens[mIndex].Offset > ATokens[mIndex - 1].Offset + Length(ATokens[mIndex -
        1].Text)) then
      begin
        Result := Result + ' ';
      end;
      Result := Result + ATokens[mIndex].Text;
    end;
  end;
end;

function StripPrefix(const AName, APrefix: string): string;
begin
  Result := AName;
  if (Length(AName) > Length(APrefix)) and StartsText(APrefix, AName) and
    CharInSet(AName[Length(APrefix) + 1], ['A'..'Z']) then
  begin
    Result := Copy(AName, Length(APrefix) + 1, MaxInt);
  end;
end;

function IsOpening(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol('(') or AToken.IsSymbol('[');
end;

function IsClosing(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(')') or AToken.IsSymbol(']');
end;

/// <summary>Mit diesem Token auf Klammertiefe 0 endet ein Argument.</summary>
function EndsArgument(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(',') or AToken.IsSymbol(')') or EndsStatement(AToken) or
    IsKeywordIn(AToken, ['then', 'do', 'of', 'begin', 'to', 'downto']);
end;

/// <summary>Letztes Token ohne Kommentare und Direktiven, das vor APosition beginnt; -1 ohne.</summary>
function LastCodeTokenBefore(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mScan: Integer;
begin
  Result := -1;
  mScan := 0;
  while (mScan <= High(ATokens)) and (Compare(ATokens[mScan].StartPos, APosition) < 0) do
  begin
    if not (ATokens[mScan].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result := mScan;
    end;
    Inc(mScan);
  end;
end;

/// <summary>Name am Cursor ausgehend vom Token AIndex: das Token selbst, wenn APosition darauf steht, bzw. das
/// davor bei "Name(|"; -1, wenn dort kein Bezeichner steht.</summary>
function NameIndexAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const APosition: TTextPosition): Integer;
begin
  Result := AIndex;
  if ATokens[AIndex].IsSymbol('(') and (Compare(ATokens[AIndex].EndPos, APosition) = 0) then
  begin
    Result := TRoutineBody.PreviousToken(ATokens, AIndex);
  end
  else if Compare(ATokens[AIndex].EndPos, APosition) < 0 then
  begin
    Result := -1;
  end;
  if (Result >= 0) and (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
  begin
    Result := -1;
  end;
end;

type
  /// <summary>Liest den Aufruf am Cursor für TCreateMethod.Site.</summary>
  TCallSiteScan = record
    Tokens: TArray<TPascalToken>;
    Site: TCreateCallSite;
    /// <summary>Token vor dem Aufruf samt Qualifizierer; -1 ohne.</summary>
    Before: Integer;
    function Read(const APosition: TTextPosition): Boolean;
    /// <summary>Name und öffnende Klammer am Cursor.</summary>
    function FindName(const APosition: TTextPosition): Boolean;
    /// <summary>Qualifizierer: nur Bezeichner mit Punkten.</summary>
    function ReadQualifier: Boolean;
    /// <summary>procedure, function, constructor, destructor, property oder operator davor.</summary>
    function IsDeclaration: Boolean;
    /// <summary>Argumente bis zur passenden ")"; mit AOpenLineOnly nur bis zum Ende der Zeile der "(".
    /// True, wenn die ")" gefunden wurde.</summary>
    function ReadArguments(AOpenLineOnly: Boolean): Boolean;
    /// <summary>Behandelt das Token AScan; True, wenn die Argumente dort enden.</summary>
    function ArgumentStep(AScan: Integer; AOpenLineOnly: Boolean; var ADepth, AStart: Integer): Boolean;
    procedure AddArgument(AStart, AScan: Integer);
    /// <summary>Umgebung aus dem Token vor dem Aufruf und dem nach der Klammer.</summary>
    procedure ReadContext;
    procedure ReadAssignmentTarget;
    /// <summary>Anfang der Anweisung: zurück bis zu ";" oder begin auf Klammertiefe 0.</summary>
    function StatementStart: Integer;
  end;

function TCallSiteScan.FindName(const APosition: TTextPosition): Boolean;
var
  mIndex: Integer;
begin
  mIndex := LastCodeTokenBefore(Tokens, APosition);
  if mIndex >= 0 then
  begin
    mIndex := NameIndexAt(Tokens, mIndex, APosition);
  end;
  Result := mIndex >= 0;
  if Result then
  begin
    Site.NameIndex := mIndex;
    Site.Name := Tokens[mIndex].Text;
    Site.NameRange := TTextRange.Create(Tokens[mIndex].StartPos, Tokens[mIndex].EndPos);
    Site.OpenIndex := TRoutineBody.NextToken(Tokens, mIndex);
    Result := (Site.OpenIndex <= High(Tokens)) and Tokens[Site.OpenIndex].IsSymbol('(');
  end;
end;

function TCallSiteScan.ReadQualifier: Boolean;
var
  mScan: Integer;
begin
  Result := True;
  Site.CallStart := Site.NameIndex;
  Before := TRoutineBody.PreviousToken(Tokens, Site.NameIndex);
  while Result and (Before >= 1) and Tokens[Before].IsSymbol('.') do
  begin
    mScan := TRoutineBody.PreviousToken(Tokens, Before);
    Result := (mScan >= 0) and (Tokens[mScan].Kind = TPascalTokenKind.Identifier);
    if Result then
    begin
      Site.CallStart := mScan;
      Before := TRoutineBody.PreviousToken(Tokens, mScan);
    end;
  end;
  if Site.CallStart < Site.NameIndex then
  begin
    Site.Qualifier := TokensText(Tokens, Site.CallStart, TRoutineBody.PreviousToken(Tokens, Site.NameIndex) - 1);
  end;
end;

function TCallSiteScan.IsDeclaration: Boolean;
begin
  Result := (Before >= 0) and IsKeywordIn(Tokens[Before], ['procedure', 'function', 'constructor', 'destructor',
    'property', 'operator']);
end;

procedure TCallSiteScan.AddArgument(AStart, AScan: Integer);
var
  mArgument: TCallArgument;
begin
  if AStart < AScan then
  begin
    mArgument.First := AStart;
    mArgument.Last := TRoutineBody.PreviousToken(Tokens, AScan);
    mArgument.Text := TokensText(Tokens, mArgument.First, mArgument.Last);
    Site.Arguments := Site.Arguments + [mArgument];
  end;
end;

function TCallSiteScan.ArgumentStep(AScan: Integer; AOpenLineOnly: Boolean; var ADepth, AStart: Integer): Boolean;
begin
  Result := (AScan > High(Tokens)) or
    (AOpenLineOnly and (Tokens[AScan].StartPos.Line > Tokens[Site.OpenIndex].StartPos.Line));
  if Result then
  begin
    AddArgument(AStart, AScan);
  end
  else if IsOpening(Tokens[AScan]) then
  begin
    Inc(ADepth);
  end
  else if IsClosing(Tokens[AScan]) and (ADepth > 0) then
  begin
    Dec(ADepth);
  end
  else if (ADepth = 0) and EndsArgument(Tokens[AScan]) then
  begin
    AddArgument(AStart, AScan);
    if Tokens[AScan].IsSymbol(')') then
    begin
      Site.CloseIndex := AScan;
    end;
    Result := not Tokens[AScan].IsSymbol(',');
    AStart := TRoutineBody.NextToken(Tokens, AScan);
  end;
end;

function TCallSiteScan.ReadArguments(AOpenLineOnly: Boolean): Boolean;
var
  mScan, mDepth, mStart: Integer;
begin
  Site.Arguments := nil;
  mDepth := 0;
  mScan := TRoutineBody.NextToken(Tokens, Site.OpenIndex);
  mStart := mScan;
  while (mScan <= High(Tokens) + 1) and not ArgumentStep(mScan, AOpenLineOnly, mDepth, mStart) do
  begin
    mScan := TRoutineBody.NextToken(Tokens, mScan);
  end;
  Result := Site.CloseIndex >= 0;
end;

procedure TCallSiteScan.ReadAssignmentTarget;
var
  mTarget, mPrior: Integer;
begin
  mTarget := TRoutineBody.PreviousToken(Tokens, Before);
  mPrior := TRoutineBody.PreviousToken(Tokens, mTarget);
  while (mPrior >= 0) and not StartsStatementAfter(Tokens[mPrior]) do
  begin
    mTarget := mPrior;
    mPrior := TRoutineBody.PreviousToken(Tokens, mTarget);
  end;
  if mTarget >= 0 then
  begin
    Site.Target := TokensText(Tokens, mTarget, TRoutineBody.PreviousToken(Tokens, Before));
  end;
end;

procedure TCallSiteScan.ReadContext;
var
  mAfter: Integer;
  mEndsHere: Boolean;
begin
  mAfter := Length(Tokens);
  if Site.CloseIndex >= 0 then
  begin
    mAfter := TRoutineBody.NextToken(Tokens, Site.CloseIndex);
  end;
  mEndsHere := (Site.CloseIndex < 0) or (mAfter > High(Tokens)) or EndsStatement(Tokens[mAfter]);
  Site.Context := TCallContext.Expression;
  if (Before >= 0) and Tokens[Before].IsSymbol(':=') then
  begin
    if mEndsHere then
    begin
      Site.Context := TCallContext.Assignment;
      ReadAssignmentTarget;
    end;
  end
  else if (Before >= 0) and IsKeywordIn(Tokens[Before], ['if', 'while', 'until', 'not', 'and', 'or']) then
  begin
    Site.Context := TCallContext.Condition;
  end
  else if ((Before < 0) or StartsStatementAfter(Tokens[Before])) and mEndsHere then
  begin
    Site.Context := TCallContext.Statement;
  end;
end;

/// <summary>Kopf einer Anweisung, der zu ihr gehört.</summary>
function IsStatementHead(const AToken: TPascalToken): Boolean;
begin
  Result := IsKeywordIn(AToken, ['if', 'while', 'until', 'case', 'for', 'with']);
end;

function TCallSiteScan.StatementStart: Integer;
var
  mBefore, mDepth: Integer;
  mDone: Boolean;
begin
  Result := Site.CallStart;
  mDepth := 0;
  mDone := False;
  while not mDone do
  begin
    mBefore := TRoutineBody.PreviousToken(Tokens, Result);
    if mBefore < 0 then
    begin
      mDone := True;
    end
    else if IsClosing(Tokens[mBefore]) then
    begin
      Inc(mDepth);
    end
    else if IsOpening(Tokens[mBefore]) and (mDepth > 0) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and IsStatementHead(Tokens[mBefore]) then
    begin
      Result := mBefore;
      mDone := True;
    end
    else
    begin
      mDone := (mDepth = 0) and StartsStatementAfter(Tokens[mBefore]);
    end;
    if not mDone then
    begin
      Result := mBefore;
    end;
  end;
end;

function TCallSiteScan.Read(const APosition: TTextPosition): Boolean;
begin
  Result := FindName(APosition) and ReadQualifier and not IsDeclaration;
  if Result then
  begin
    // Fehlt die ")" (gerade getippt), zählt nur der Rest der Zeile: Die nächste Zeile ist dann meist schon die
    // nächste Anweisung.
    if not ReadArguments(False) then
    begin
      ReadArguments(True);
    end;
    ReadContext;
    Site.StatementStart := StatementStart;
  end;
end;

{ TCreateMethod }

class function TCreateMethod.Site(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ASite: TCreateCallSite): Boolean;
var
  mScan: TCallSiteScan;
begin
  mScan := Default(TCallSiteScan);
  mScan.Tokens := ATokens;
  mScan.Site.CloseIndex := -1;
  Result := mScan.Read(APosition);
  ASite := mScan.Site;
end;

class function TCreateMethod.LiteralType(const ATokens: TArray<TPascalToken>; const AArgument: TCallArgument): string;
var
  mToken: TPascalToken;
  mFirst: Integer;
begin
  Result := '';
  mFirst := AArgument.First;
  // Vorzeichen gehört zur Zahl.
  if (mFirst < AArgument.Last) and (ATokens[mFirst].IsSymbol('-') or ATokens[mFirst].IsSymbol('+')) then
  begin
    mFirst := TRoutineBody.NextToken(ATokens, mFirst);
  end;
  if mFirst <> AArgument.Last then
  begin
    Exit;
  end;
  mToken := ATokens[mFirst];
  case mToken.Kind of
    TPascalTokenKind.Number:
      if (mToken.Text[1] <> '$') and (mToken.Text[1] <> '%') and
        ((Pos('.', mToken.Text) > 0) or (Pos('e', LowerCase(mToken.Text)) > 0)) then
      begin
        Result := 'Double';
      end
      else
      begin
        Result := 'Integer';
      end;
    TPascalTokenKind.StringLiteral:
      Result := 'string';
    TPascalTokenKind.CharLiteral:
      Result := 'Char';
    TPascalTokenKind.Identifier:
      if SameText(mToken.Text, 'True') or SameText(mToken.Text, 'False') then
      begin
        Result := 'Boolean';
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Name aus einem Literal: Anteil zwischen 0 und 1 ist ein Satz (0.1 → Rate), sonst aus dem Typ.
/// </summary>
function LiteralName(const ATokens: TArray<TPascalToken>; const AArgument: TCallArgument;
  const ALiteral: string): string;
var
  mValue: Double;
  mSettings: TFormatSettings;
begin
  Result := TCreateMethod.NameFromType(ALiteral);
  mSettings := TFormatSettings.Invariant;
  if (ALiteral = 'Double') and TryStrToFloat(ATokens[AArgument.Last].Text, mValue, mSettings) and (mValue > 0) and
    (mValue < 1) and not ATokens[AArgument.First].IsSymbol('-') then
  begin
    Result := 'Rate';
  end;
end;

/// <summary>"(" zur ")" in ALast; AFirst - 1, wenn sie fehlt.</summary>
function OpeningParen(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Integer;
var
  mDepth: Integer;
  mFound: Boolean;
begin
  Result := ALast;
  mDepth := 0;
  mFound := False;
  while not mFound and (Result >= AFirst) do
  begin
    if ATokens[Result].IsSymbol(')') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol('(') then
    begin
      Dec(mDepth);
      mFound := mDepth = 0;
    end;
    if not mFound then
    begin
      Dec(Result);
    end;
  end;
end;

/// <summary>TKunde: T und ein Großbuchstabe.</summary>
function LooksLikeTypeName(const AName: string): Boolean;
begin
  Result := (Length(AName) > 1) and (AName[1] = 'T') and CharInSet(AName[2], ['A'..'Z']);
end;

/// <summary>Aufruf oder Typumwandlung: Name vor der äußeren Klammer am Ende; '' ohne.</summary>
function CallName(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
var
  mLast: Integer;
begin
  Result := '';
  mLast := TRoutineBody.PreviousToken(ATokens, OpeningParen(ATokens, AFirst, ALast));
  if (mLast < AFirst) or (ATokens[mLast].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit;
  end;
  // Typumwandlung TKunde(X): Name aus dem Typ.
  if (mLast = AFirst) and LooksLikeTypeName(ATokens[mLast].Text) then
  begin
    Result := TCreateMethod.NameFromType(ATokens[mLast].Text);
  end
  else
  begin
    Result := StripPrefix(ATokens[mLast].Text, 'Get');
  end;
end;

function IsChainToken(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) or AToken.IsSymbol('.') or AToken.IsSymbol('^');
end;

/// <summary>Bezeichner, der einen Namen hergibt: nicht Self, nil oder Result.</summary>
function IsNamingIdentifier(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) and not MatchText(AToken.Text, ['Self', 'nil', 'Result']);
end;

/// <summary>Kette A.B.C: letzter Bezeichner; bei einem einzelnen Namen ohne F-, A- bzw. L-Präfix. '' ohne.
/// </summary>
function ChainName(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
var
  mIndex, mLast: Integer;
begin
  Result := '';
  for mIndex := AFirst to ALast do
  begin
    if not IsChainToken(ATokens[mIndex]) then
    begin
      Exit;
    end;
  end;
  mLast := ALast;
  if ATokens[mLast].IsSymbol('^') then
  begin
    mLast := TRoutineBody.PreviousToken(ATokens, mLast);
  end;
  if (mLast < AFirst) or not IsNamingIdentifier(ATokens[mLast]) then
  begin
    Exit;
  end;
  Result := StripPrefix(ATokens[mLast].Text, 'Get');
  if AFirst = mLast then
  begin
    Result := StripPrefix(StripPrefix(StripPrefix(Result, 'F'), 'A'), 'L');
  end;
end;

class function TCreateMethod.ArgumentName(const ATokens: TArray<TPascalToken>;
  const AArgument: TCallArgument): string;
var
  mFirst: Integer;
  mLiteral: string;
begin
  Result := '';
  mLiteral := LiteralType(ATokens, AArgument);
  if mLiteral <> '' then
  begin
    Exit(LiteralName(ATokens, AArgument, mLiteral));
  end;
  mFirst := AArgument.First;
  if ATokens[mFirst].IsSymbol('@') then
  begin
    mFirst := TRoutineBody.NextToken(ATokens, mFirst);
  end;
  if mFirst > AArgument.Last then
  begin
    Exit;
  end;
  if ATokens[AArgument.Last].IsSymbol(')') then
  begin
    Result := CallName(ATokens, mFirst, AArgument.Last);
  end
  else
  begin
    Result := ChainName(ATokens, mFirst, AArgument.Last);
  end;
end;

class function TCreateMethod.NameFromType(const ATypeName: string): string;
begin
  Result := ATypeName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Result.Substring(Result.LastIndexOf('.') + 1);
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 'I']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  if MatchText(Result, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String',
    'ShortString']) then
  begin
    Result := 'Text';
  end
  else if MatchText(Result, ['Char', 'WideChar', 'AnsiChar']) then
  begin
    Result := 'Ch';
  end
  else if SameText(Result, 'Boolean') then
  begin
    Result := 'Flag';
  end
  else if MatchText(Result, ['Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Byte', 'Word',
    'SmallInt', 'ShortInt', 'LongInt', 'LongWord', 'Double', 'Single', 'Extended', 'Real', 'Currency', 'Comp',
    'Variant', 'Pointer', '']) or StartsStr('{', Result) then
  begin
    Result := 'Value';
  end;
end;

class function TCreateMethod.WantsConst(const ATypeName: string; AIsRecord, AIsInterface: Boolean): Boolean;
begin
  Result := AIsRecord or AIsInterface or MatchText(ATypeName, ['string', 'UnicodeString', 'AnsiString',
    'WideString', 'RawByteString', 'UTF8String', 'ShortString']);
end;

class function TCreateMethod.UniqueNames(const ANames: TArray<string>): TArray<string>;
var
  mIndex, mOther, mNumber: Integer;
  mTaken: Boolean;
begin
  SetLength(Result, Length(ANames));
  for mIndex := 0 to High(ANames) do
  begin
    Result[mIndex] := ANames[mIndex];
    mNumber := 1;
    repeat
      mTaken := False;
      for mOther := 0 to mIndex - 1 do
      begin
        if SameText(Result[mOther], Result[mIndex]) then
        begin
          mTaken := True;
        end;
      end;
      if mTaken then
      begin
        Inc(mNumber);
        Result[mIndex] := ANames[mIndex] + IntToStr(mNumber);
      end;
    until not mTaken;
  end;
end;

class function TCreateMethod.ParameterList(const AParameters: TArray<TCreateParameter>): string;
var
  mIndex: Integer;
begin
  Result := '';
  if AParameters = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AParameters) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + '; ';
    end;
    if AParameters[mIndex].IsConst then
    begin
      Result := Result + 'const ';
    end;
    Result := Result + AParameters[mIndex].Name + ': ' + AParameters[mIndex].TypeName;
  end;
  Result := '(' + Result + ')';
end;

class function TCreateMethod.Header(const APlan: TCreateMethodPlan; AQualified: Boolean): string;
begin
  if APlan.ResultType = '' then
  begin
    Result := 'procedure ';
  end
  else
  begin
    Result := 'function ';
  end;
  if APlan.IsClassMethod then
  begin
    Result := 'class ' + Result;
  end;
  if AQualified and (APlan.TypeName <> '') then
  begin
    Result := Result + APlan.TypeName + '.';
  end;
  Result := Result + APlan.Name + ParameterList(APlan.Parameters);
  if APlan.ResultType <> '' then
  begin
    Result := Result + ': ' + APlan.ResultType;
  end;
end;

function BodyText(const APlan: TCreateMethodPlan; const ALineBreak: string): string;
var
  mInner: string;
begin
  mInner := '';
  if APlan.CaretInBody then
  begin
    mInner := TRoutineBody.IndentUnit(APlan.Style) + '$0';
  end;
  Result := TCreateMethod.Header(APlan, True) + ';' + ALineBreak + 'begin' + ALineBreak + mInner + ALineBreak + 'end;';
end;

class function TCreateMethod.MethodEdits(const AText: string; ATree: TSyntaxTree; const APlan: TCreateMethodPlan;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mBody: TSyntaxNode;
  mEdit: TTextEdit;
  mSection: string;
begin
  AEdits := nil;
  Result := False;
  mBody := TRoutineBody.TypeBody(ATree.Root, APlan.TypeName.Substring(APlan.TypeName.LastIndexOf('.') + 1));
  if mBody = nil then
  begin
    Exit;
  end;
  mSection := APlan.Section;
  if mSection = '' then
  begin
    mSection := 'private';
  end;
  if not TRoutineBody.MemberDeclaration(AText, ATree, mBody,
    TMemberEntry.Create(mSection, TCreateMethod.Header(APlan, False) + ';'), APlan.Style, mEdit) then
  begin
    Exit;
  end;
  AEdits := [mEdit];
  if not TClassCompletion.BodyEdit(ATree, AText, APlan.TypeName, BodyText(APlan, TTextLines.LineBreakOf(AText)),
    mEdit) then
  begin
    Exit;
  end;
  AEdits := AEdits + [mEdit];
  Result := True;
end;

class function TCreateMethod.RoutineEdit(const AText: string; ARoutine: TSyntaxNode;
  const APlan: TCreateMethodPlan): TTextEdit;
var
  mLine: Integer;
  mLineBreak: string;
  mPosition: TTextPosition;
begin
  mLineBreak := TTextLines.LineBreakOf(AText);
  mLine := TRoutineBody.RoutineInsertLine(AText, ARoutine);
  mPosition := TTextPosition.Create(mLine, 0);
  Result := TTextEdit.Create(TTextRange.Create(mPosition, mPosition), BodyText(APlan, mLineBreak) + mLineBreak +
    mLineBreak);
end;

end.
