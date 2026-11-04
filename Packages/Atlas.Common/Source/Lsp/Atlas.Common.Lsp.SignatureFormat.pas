unit Atlas.Common.Lsp.SignatureFormat;

// Platzhalter im Parameter-Hint (#451): Bei Format und den übrigen Formatroutinen (Pascal.FormatRoutines) ordnet
// der Server jedem Platzhalter des Formatstrings sein Argument in der Liste [...] zu. Grundlage sind die Tokens
// des Aufrufs, nicht der Syntaxbaum: Beim Tippen ist der Aufruf noch offen.
// - Der Formatstring muss bekannt sein: Literal, Verkettung aus Literalen oder eine Konstante (Wert aus ihrer
//   Signatur). Nur beim Literal im Aufruf hat jeder Platzhalter seine Lage im Dokument (Range), sonst Line -1.
// - Die Liste wird ab "[" bis zum passenden "]" gelesen, auch hinter dem Cursor; ohne "]" bis zum Ende des
//   Aufrufs bzw. der Anweisung. Leere Einträge (gerade getippt) zählen nicht als Argument.
// - Indexangaben (%0:s) und "*" für Breite bzw. Genauigkeit zerlegt Pascal.FormatStrings wie FormatBuf.
// - Problem: ungültiger Platzhalter, mehr Argumente als der Formatstring braucht, oder ein offensichtlicher
//   Typkonflikt mit einem Literal (%d und 'Text', %s und 5, %d und True); dieselbe Tabelle wie format-args.
// Die Texte baut das Plugin (Deutsch und Englisch); der Server liefert nur Zahlen und Typbuchstaben.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.FormatStrings,
  Atlas.Common.Pascal.FormatRoutines,
  Atlas.Common.Semantics.NameResolver;

type
  TSignatureFormatProblem = (None, Invalid, TooManyArguments, TypeConflict);

  TSignatureFormatSpec = record
    Text: string;
    /// <summary>Typbuchstabe klein; #0 bei ungültigen Platzhaltern.</summary>
    TypeChar: Char;
    Valid: Boolean;
    /// <summary>Argumente ab 0, -1 = keins bzw. unbekannt (Index "*").</summary>
    Argument: Integer;
    WidthArgument: Integer;
    PrecisionArgument: Integer;
    /// <summary>Lage im Dokument; StartPos.Line = -1, wenn der Formatstring nicht als Literal im Aufruf steht.
    /// </summary>
    Range: TTextRange;
  end;

  TSignatureFormat = record
    Found: Boolean;
    /// <summary>Parameter (ab 0) mit dem Formatstring und mit der Liste [...].</summary>
    FormatParameter: Integer;
    ListParameter: Integer;
    Specs: TArray<TSignatureFormatSpec>;
    /// <summary>Einträge der Liste, auch leere (Start = Ende).</summary>
    Arguments: TArray<TTextRange>;
    /// <summary>Einträge mit Inhalt.</summary>
    FilledArguments: Integer;
    /// <summary>Höchstes verwendetes Argument + 1; -1 bei Index "*".</summary>
    ArgumentCount: Integer;
    /// <summary>Eintrag der Liste am Cursor, -1 außerhalb der Liste.</summary>
    ActiveArgument: Integer;
    Problem: TSignatureFormatProblem;
    /// <summary>Betroffener Platzhalter bzw. betroffenes Argument (ab 0), -1 ohne.</summary>
    ProblemSpec: Integer;
    ProblemArgument: Integer;
    /// <summary>Art des Literals beim Typkonflikt: string, char, integer, float, boolean.</summary>
    ProblemKind: string;
  end;

  /// <summary>Der Aufruf, dessen Platzhalter Analyze zuordnet.</summary>
  TSignatureFormatCall = record
    Resolver: TNameResolver;
    Tree: TSyntaxTree;
    FileName: string;
    /// <summary>Erstes und letztes Token je Argument (Token-Indizes wie TCallSite).</summary>
    Firsts: TArray<Integer>;
    Lasts: TArray<Integer>;
    /// <summary>Parameter am Cursor wie TCallSite.</summary>
    ActiveParameter: Integer;
  end;

  TSignatureFormats = record
  public
    /// <summary>Platzhalter des Aufrufs ACall an die Formatroutine ARoutine. Found = False, wenn der
    /// Formatstring unbekannt ist.</summary>
    class function Analyze(const ACall: TSignatureFormatCall; const ARoutine: TFormatRoutine): TSignatureFormat;
      static;
    /// <summary>Objekt "format" der Antwort auf signatureHelp; nil ohne. Der Aufrufer übernimmt es.</summary>
    class function ToJson(const AFormat: TSignatureFormat): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Math,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.Positions;

function Significant(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>Erstes bedeutsames Token in ATokens[AFirst..ALast]; -1 ohne.</summary>
function FirstSignificant(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := AFirst to ALast do
  begin
    if Significant(ATokens[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Wert und Lage der Zeichen eines Formatstrings aus Literalen (mit + verbunden); False für anderes.
/// </summary>
function LiteralFormat(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; out AValue: string;
  out APositions: TArray<TTextPosition>): Boolean;
var
  mIndex, mChar: Integer;
  mToken: TPascalToken;
  mPart: string;
  mOffsets: TArray<Integer>;
  mAny: Boolean;
begin
  AValue := '';
  APositions := nil;
  mAny := False;
  for mIndex := AFirst to ALast do
  begin
    mToken := ATokens[mIndex];
    if not Significant(mToken) or mToken.IsSymbol('+') then
    begin
      Continue;
    end;
    // Mehrzeilige Literale (''') und offene Strings bleiben unbekannt.
    if not (mToken.Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) or not mToken.Terminated or
      (mToken.StartPos.Line <> mToken.EndPos.Line) or
      not TFormatString.LiteralOffsets(mToken.Text, mPart, mOffsets) then
    begin
      Exit(False);
    end;
    AValue := AValue + mPart;
    for mChar := 0 to High(mOffsets) do
    begin
      APositions := APositions + [TTextPosition.Create(mToken.StartPos.Line,
        mToken.StartPos.Character + mOffsets[mChar])];
    end;
    mAny := True;
  end;
  Result := mAny;
end;

/// <summary>Wert einer Konstanten im Argument AParameter (Bezeichner, auch qualifiziert).</summary>
function ConstantFormat(const ACall: TSignatureFormatCall; AParameter: Integer; out AValue: string): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mLast: Integer;
  mSymbol: TResolvedSymbol;
begin
  AValue := '';
  Result := False;
  if ACall.Resolver = nil then
  begin
    Exit;
  end;
  mTokens := ACall.Tree.Tokens;
  mLast := -1;
  for mIndex := ACall.Firsts[AParameter] to ACall.Lasts[AParameter] do
  begin
    if not Significant(mTokens[mIndex]) then
    begin
      Continue;
    end;
    if mTokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      mLast := mIndex;
    end
    else if not mTokens[mIndex].IsSymbol('.') then
    begin
      Exit;
    end;
  end;
  if mLast < 0 then
  begin
    Exit;
  end;
  mSymbol := ACall.Resolver.Resolve(ACall.Tree, ACall.FileName, mTokens[mLast].StartPos);
  if (mSymbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and
    (mSymbol.SymbolKind = TIndexSymbolKind.Constant) then
  begin
    Result := TFormatString.ConstantValue(mSymbol.Signature, AValue);
  end;
end;

/// <summary>Gehört AToken noch zum Literal mText? Literale wie 'a'#13'b' sind mehrere Tokens; ein Vorzeichen
/// nur vorn; alles andere ist ein Ausdruck.</summary>
function ExtendsLiteral(const AToken: TPascalToken; const AText: string): Boolean;
begin
  if AToken.Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral] then
  begin
    Result := True;
  end
  else if AToken.Kind = TPascalTokenKind.Number then
  begin
    Result := (AText = '') or (AText = '-');
  end
  else
  begin
    Result := (AText = '') and (AToken.IsSymbol('-') or (AToken.Kind = TPascalTokenKind.Identifier));
  end;
end;

/// <summary>Art des Literals für die Meldung: string, char, integer, float; '' sonst.</summary>
function ClassKind(AClass: TFormatArgumentClass): string;
begin
  case AClass of
    TFormatArgumentClass.Text:
      Result := 'string';
    TFormatArgumentClass.Character:
      Result := 'char';
    TFormatArgumentClass.Integer_:
      Result := 'integer';
    TFormatArgumentClass.Float:
      Result := 'float';
  else
    Result := '';
  end;
end;

/// <summary>Art eines Listeneintrags aus genau einem Literal (auch negativ) bzw. True/False; Unknown sonst.
/// </summary>
function ElementClass(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  out AKind: string): TFormatArgumentClass;
var
  mIndex: Integer;
  mText, mTypeName: string;
begin
  AKind := '';
  mText := '';
  for mIndex := AFirst to ALast do
  begin
    if not Significant(ATokens[mIndex]) then
    begin
      Continue;
    end;
    if not ExtendsLiteral(ATokens[mIndex], mText) then
    begin
      Exit(TFormatArgumentClass.Unknown);
    end;
    mText := mText + ATokens[mIndex].Text;
  end;
  if SameText(mText, 'True') or SameText(mText, 'False') then
  begin
    AKind := 'boolean';
    Exit(TFormatArgumentClass.Bool);
  end;
  Result := TFormatString.LiteralClass(mText, mTypeName);
  AKind := ClassKind(Result);
end;

/// <summary>Schlüsselwörter, die in einem Ausdruck der Liste stehen dürfen.</summary>
function IsOperatorKeyword(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Keyword) and
    MatchText(AToken.Text, ['nil', 'not', 'and', 'or', 'div', 'mod']);
end;

/// <summary>Liste ohne "]": Ende des Aufrufs bzw. der Anweisung.</summary>
function EndsOpenList(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(')') or AToken.IsSymbol(';') or
    ((AToken.Kind = TPascalTokenKind.Keyword) and not IsOperatorKeyword(AToken));
end;

function Opens(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol('(') or AToken.IsSymbol('[');
end;

function Closes(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(')') or AToken.IsSymbol(']');
end;

/// <summary>Platzhalter mit Lage im Dokument, wenn APositions (Zeichen des Literals) sie kennt.</summary>
function SpecOf(const ASpec: TFormatSpec; const APositions: TArray<TTextPosition>): TSignatureFormatSpec;
var
  mLast: Integer;
begin
  Result := Default(TSignatureFormatSpec);
  Result.Text := ASpec.Text;
  Result.TypeChar := ASpec.TypeChar;
  Result.Valid := ASpec.Kind = TFormatSpecKind.Valid;
  Result.Argument := ASpec.Argument;
  Result.WidthArgument := ASpec.WidthArgument;
  Result.PrecisionArgument := ASpec.PrecisionArgument;
  Result.Range := TTextRange.Create(-1, -1, -1, -1);
  // Index des letzten Zeichens in APositions (ab 0).
  mLast := ASpec.Offset + Length(ASpec.Text) - 2;
  if (APositions <> nil) and (mLast + 1 <= Length(APositions)) then
  begin
    Result.Range := TTextRange.Create(APositions[ASpec.Offset - 1],
      TTextPosition.Create(APositions[mLast].Line, APositions[mLast].Character + 1));
  end;
end;

type
  /// <summary>Ein Lauf von TSignatureFormats.Analyze.</summary>
  TFormatAnalysis = class
  private
    FCall: TSignatureFormatCall;
    FRoutine: TFormatRoutine;
    FTokens: TArray<TPascalToken>;
    FResult: TSignatureFormat;
    // Erstes und letztes bedeutsames Token je Listeneintrag, -1 bei leeren.
    FElementFirst: TArray<Integer>;
    FElementLast: TArray<Integer>;
    function FirstOf(AParameter: Integer): Integer;
    procedure FindListParameter;
    function ChooseFormatParameter: Boolean;
    function ReadFormat(out AValue: string; out APositions: TArray<TTextPosition>): Boolean;
    procedure AddElement(AFrom, ATo: Integer);
    function ListStep(AIndex: Integer; var ADepth, AStart, AClose, ALastToken: Integer): Boolean;
    procedure ReadList(AOpen: Integer);
    function ActiveArgumentAt(AOpen: Integer): Integer;
    procedure Report(AProblem: TSignatureFormatProblem; ASpec, AArgument: Integer; const AKind: string);
    procedure CheckArgument(ASpec: Integer; AType: Char; AArgument: Integer);
    procedure CheckProblems;
  public
    constructor Create(const ACall: TSignatureFormatCall; const ARoutine: TFormatRoutine);
    function Run: TSignatureFormat;
  end;

constructor TFormatAnalysis.Create(const ACall: TSignatureFormatCall; const ARoutine: TFormatRoutine);
begin
  inherited Create;
  FCall := ACall;
  FRoutine := ARoutine;
  FResult := Default(TSignatureFormat);
  FResult.ListParameter := -1;
  FResult.FormatParameter := -1;
  FResult.ActiveArgument := -1;
  FResult.ProblemSpec := -1;
  FResult.ProblemArgument := -1;
end;

function TFormatAnalysis.FirstOf(AParameter: Integer): Integer;
begin
  Result := FirstSignificant(FTokens, FCall.Firsts[AParameter], Min(FCall.Lasts[AParameter], High(FTokens)));
end;

procedure TFormatAnalysis.FindListParameter;
var
  mIndex, mOpen: Integer;
begin
  // Liste: erstes Argument, das mit "[" beginnt (hinter dem Formatstring, wenn dessen Stelle bekannt ist).
  for mIndex := Max(1, FRoutine.FormatIndex + 1) to High(FCall.Firsts) do
  begin
    mOpen := FirstOf(mIndex);
    if (mOpen >= 0) and FTokens[mOpen].IsSymbol('[') then
    begin
      FResult.ListParameter := mIndex;
      Exit;
    end;
  end;
end;

function TFormatAnalysis.ChooseFormatParameter: Boolean;
begin
  if FRoutine.FormatIndex >= 0 then
  begin
    FResult.FormatParameter := FRoutine.FormatIndex;
  end
  else if FResult.ListParameter > 0 then
  begin
    FResult.FormatParameter := FResult.ListParameter - 1;
  end;
  // Ohne Stelle, oder der Formatstring wird gerade getippt bzw. fehlt noch.
  Result := (FResult.FormatParameter >= 0) and (FResult.FormatParameter <= High(FCall.Firsts)) and
    (FCall.ActiveParameter <> FResult.FormatParameter);
  if Result and (FResult.ListParameter < 0) then
  begin
    FResult.ListParameter := FResult.FormatParameter + 1;
  end;
end;

function TFormatAnalysis.ReadFormat(out AValue: string; out APositions: TArray<TTextPosition>): Boolean;
var
  mParameter: Integer;
begin
  mParameter := FResult.FormatParameter;
  Result := LiteralFormat(FTokens, FCall.Firsts[mParameter], FCall.Lasts[mParameter], AValue, APositions);
  if not Result then
  begin
    APositions := nil;
    Result := ConstantFormat(FCall, mParameter, AValue);
  end;
end;

procedure TFormatAnalysis.AddElement(AFrom, ATo: Integer);
var
  mFrom, mTo: Integer;
begin
  mFrom := FirstSignificant(FTokens, AFrom, ATo);
  mTo := ATo;
  while (mTo >= AFrom) and not Significant(FTokens[mTo]) do
  begin
    Dec(mTo);
  end;
  if mFrom < 0 then
  begin
    // Leerer Eintrag: Lage hinter dem Trennzeichen davor.
    FResult.Arguments := FResult.Arguments + [TTextRange.Create(FTokens[AFrom - 1].EndPos,
      FTokens[AFrom - 1].EndPos)];
    FElementFirst := FElementFirst + [-1];
    FElementLast := FElementLast + [-1];
    Exit;
  end;
  FResult.Arguments := FResult.Arguments + [TTextRange.Create(FTokens[mFrom].StartPos, FTokens[mTo].EndPos)];
  FElementFirst := FElementFirst + [mFrom];
  FElementLast := FElementLast + [mTo];
  Inc(FResult.FilledArguments);
end;

function TFormatAnalysis.ListStep(AIndex: Integer; var ADepth, AStart, AClose, ALastToken: Integer): Boolean;
var
  mToken: TPascalToken;
begin
  // True: Ende der Liste erreicht.
  Result := False;
  mToken := FTokens[AIndex];
  if not Significant(mToken) then
  begin
    Exit;
  end;
  if Opens(mToken) then
  begin
    Inc(ADepth);
  end
  else if (ADepth > 0) and Closes(mToken) then
  begin
    Dec(ADepth);
  end
  else if ADepth > 0 then
  begin
    Exit;
  end
  else if mToken.IsSymbol(']') or EndsOpenList(mToken) then
  begin
    if mToken.IsSymbol(']') then
    begin
      AClose := AIndex;
    end;
    ALastToken := AIndex - 1;
    Result := True;
  end
  else if mToken.IsSymbol(',') then
  begin
    AddElement(AStart, AIndex - 1);
    AStart := AIndex + 1;
  end;
end;

procedure TFormatAnalysis.ReadList(AOpen: Integer);
var
  mIndex, mDepth, mStart, mClose, mLastToken: Integer;
begin
  mDepth := 0;
  mStart := AOpen + 1;
  mClose := -1;
  mLastToken := High(FTokens);
  for mIndex := AOpen + 1 to High(FTokens) do
  begin
    if ListStep(mIndex, mDepth, mStart, mClose, mLastToken) then
    begin
      Break;
    end;
  end;
  if (mStart <= mLastToken) or (Length(FResult.Arguments) > 0) or (mClose >= 0) then
  begin
    AddElement(mStart, mLastToken);
  end;
  if (FCall.ActiveParameter = FResult.ListParameter) and
    ((mClose < 0) or (mClose > FCall.Lasts[FResult.ListParameter])) then
  begin
    FResult.ActiveArgument := ActiveArgumentAt(AOpen);
  end;
end;

function TFormatAnalysis.ActiveArgumentAt(AOpen: Integer): Integer;
var
  mIndex, mDepth: Integer;
begin
  // Eintrag am Cursor: Kommas zwischen "[" und dem letzten Token vor dem Cursor.
  Result := 0;
  mDepth := 0;
  for mIndex := AOpen + 1 to Min(FCall.Lasts[FResult.ListParameter], High(FTokens)) do
  begin
    if not Significant(FTokens[mIndex]) then
    begin
      Continue;
    end;
    if Opens(FTokens[mIndex]) then
    begin
      Inc(mDepth);
    end
    else if Closes(FTokens[mIndex]) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and FTokens[mIndex].IsSymbol(',') then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TFormatAnalysis.Report(AProblem: TSignatureFormatProblem; ASpec, AArgument: Integer; const AKind: string);
begin
  if FResult.Problem <> TSignatureFormatProblem.None then
  begin
    Exit;
  end;
  FResult.Problem := AProblem;
  FResult.ProblemSpec := ASpec;
  FResult.ProblemArgument := AArgument;
  FResult.ProblemKind := AKind;
end;

procedure TFormatAnalysis.CheckArgument(ASpec: Integer; AType: Char; AArgument: Integer);
var
  mKind: string;
  mClass: TFormatArgumentClass;
begin
  if (AArgument < 0) or (AArgument > High(FElementFirst)) or (FElementFirst[AArgument] < 0) then
  begin
    Exit;
  end;
  mClass := ElementClass(FTokens, FElementFirst[AArgument], FElementLast[AArgument], mKind);
  if not TFormatString.Fits(AType, mClass) then
  begin
    Report(TSignatureFormatProblem.TypeConflict, ASpec, AArgument, mKind);
  end;
end;

procedure TFormatAnalysis.CheckProblems;
var
  mIndex, mArgument: Integer;
begin
  // Probleme: ungültiger Platzhalter, überzählige Argumente, Typkonflikt mit einem Literal.
  for mIndex := 0 to High(FResult.Specs) do
  begin
    if not FResult.Specs[mIndex].Valid then
    begin
      Report(TSignatureFormatProblem.Invalid, mIndex, -1, '');
    end;
  end;
  if (FResult.ArgumentCount >= 0) and (FResult.FilledArguments > FResult.ArgumentCount) then
  begin
    for mArgument := FResult.ArgumentCount to High(FElementFirst) do
    begin
      if FElementFirst[mArgument] >= 0 then
      begin
        Report(TSignatureFormatProblem.TooManyArguments, -1, mArgument, '');
        Break;
      end;
    end;
  end;
  for mIndex := 0 to High(FResult.Specs) do
  begin
    CheckArgument(mIndex, '*', FResult.Specs[mIndex].WidthArgument);
    CheckArgument(mIndex, '*', FResult.Specs[mIndex].PrecisionArgument);
    if FResult.Specs[mIndex].Valid then
    begin
      CheckArgument(mIndex, FResult.Specs[mIndex].TypeChar, FResult.Specs[mIndex].Argument);
    end;
  end;
end;

function TFormatAnalysis.Run: TSignatureFormat;
var
  mValue: string;
  mPositions: TArray<TTextPosition>;
  mFormat: TFormatString;
  mSpec: TFormatSpec;
  mOpen: Integer;
begin
  Result := FResult;
  if (FCall.Tree = nil) or (Length(FCall.Firsts) = 0) then
  begin
    Exit;
  end;
  FTokens := FCall.Tree.Tokens;
  FindListParameter;
  if not ChooseFormatParameter or not ReadFormat(mValue, mPositions) then
  begin
    Exit(FResult);
  end;
  FResult.Found := True;
  mFormat := TFormatString.Parse(mValue);
  FResult.ArgumentCount := mFormat.ArgumentCount;
  for mSpec in mFormat.Specs do
  begin
    FResult.Specs := FResult.Specs + [SpecOf(mSpec, mPositions)];
  end;
  // Einträge der Liste, auch hinter dem Cursor.
  if FResult.ListParameter <= High(FCall.Firsts) then
  begin
    mOpen := FirstOf(FResult.ListParameter);
    if (mOpen >= 0) and FTokens[mOpen].IsSymbol('[') then
    begin
      ReadList(mOpen);
    end;
  end;
  CheckProblems;
  Result := FResult;
end;

class function TSignatureFormats.Analyze(const ACall: TSignatureFormatCall;
  const ARoutine: TFormatRoutine): TSignatureFormat;
var
  mRun: TFormatAnalysis;
begin
  mRun := TFormatAnalysis.Create(ACall, ARoutine);
  try
    Result := mRun.Run;
  finally
    mRun.Free;
  end;
end;

class function TSignatureFormats.ToJson(const AFormat: TSignatureFormat): TJSONObject;
const
  cProblems: array[TSignatureFormatProblem] of string = ('', 'invalid', 'tooManyArguments', 'typeConflict');
var
  mSpecs, mArguments: TJSONArray;
  mItem, mProblem: TJSONObject;
  mSpec: TSignatureFormatSpec;
  mRange: TTextRange;
begin
  if not AFormat.Found then
  begin
    Exit(nil);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('formatParameter', TJSONNumber.Create(AFormat.FormatParameter));
  Result.AddPair('listParameter', TJSONNumber.Create(AFormat.ListParameter));
  Result.AddPair('argumentCount', TJSONNumber.Create(AFormat.ArgumentCount));
  Result.AddPair('activeArgument', TJSONNumber.Create(AFormat.ActiveArgument));
  mSpecs := TJSONArray.Create;
  Result.AddPair('placeholders', mSpecs);
  for mSpec in AFormat.Specs do
  begin
    mItem := TJSONObject.Create;
    mSpecs.AddElement(mItem);
    mItem.AddPair('text', mSpec.Text);
    if mSpec.Valid then
    begin
      mItem.AddPair('type', string(mSpec.TypeChar));
    end;
    mItem.AddPair('valid', TJSONBool.Create(mSpec.Valid));
    mItem.AddPair('argument', TJSONNumber.Create(mSpec.Argument));
    mItem.AddPair('width', TJSONNumber.Create(mSpec.WidthArgument));
    mItem.AddPair('precision', TJSONNumber.Create(mSpec.PrecisionArgument));
    if mSpec.Range.StartPos.Line >= 0 then
    begin
      mItem.AddPair('range', TLspPositions.RangeToJson(mSpec.Range));
    end;
  end;
  mArguments := TJSONArray.Create;
  Result.AddPair('arguments', mArguments);
  for mRange in AFormat.Arguments do
  begin
    mArguments.AddElement(TLspPositions.RangeToJson(mRange));
  end;
  if AFormat.Problem <> TSignatureFormatProblem.None then
  begin
    mProblem := TJSONObject.Create;
    Result.AddPair('problem', mProblem);
    mProblem.AddPair('kind', cProblems[AFormat.Problem]);
    mProblem.AddPair('placeholder', TJSONNumber.Create(AFormat.ProblemSpec));
    mProblem.AddPair('argument', TJSONNumber.Create(AFormat.ProblemArgument));
    if AFormat.ProblemKind <> '' then
    begin
      mProblem.AddPair('argumentKind', AFormat.ProblemKind);
    end;
  end;
end;

end.
