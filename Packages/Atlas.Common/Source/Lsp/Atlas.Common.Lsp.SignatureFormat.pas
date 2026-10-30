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

  TSignatureFormats = record
  public
    /// <summary>Platzhalter des Aufrufs, dessen Argumente AFirsts/ALasts (Token-Indizes wie TCallSite) sind;
    /// AActiveParameter wie TCallSite. Found = False, wenn der Formatstring unbekannt ist.</summary>
    class function Analyze(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const AFirsts, ALasts: TArray<Integer>; AActiveParameter: Integer;
      const ARoutine: TFormatRoutine): TSignatureFormat; static;
    /// <summary>Objekt "format" der Antwort auf signatureHelp; nil ohne. Der Aufrufer übernimmt es.</summary>
    class function ToJson(const AFormat: TSignatureFormat): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Math,
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
    if Significant(ATokens[mIndex]) then
      Exit(mIndex);
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
      Continue;
    // Mehrzeilige Literale (''') und offene Strings bleiben unbekannt.
    if not (mToken.Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) or not mToken.Terminated or
      (mToken.StartPos.Line <> mToken.EndPos.Line) or
      not TFormatString.LiteralOffsets(mToken.Text, mPart, mOffsets) then
      Exit(False);
    AValue := AValue + mPart;
    for mChar := 0 to High(mOffsets) do
      APositions := APositions + [TTextPosition.Create(mToken.StartPos.Line,
        mToken.StartPos.Character + mOffsets[mChar])];
    mAny := True;
  end;
  Result := mAny;
end;

/// <summary>Wert einer Konstanten ATokens[AFirst..ALast] (Bezeichner, auch qualifiziert).</summary>
function ConstantFormat(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; out AValue: string): Boolean;
var
  mIndex, mLast: Integer;
  mSymbol: TResolvedSymbol;
begin
  AValue := '';
  Result := False;
  if AResolver = nil then
    Exit;
  mLast := -1;
  for mIndex := AFirst to ALast do
    if Significant(ATokens[mIndex]) then
    begin
      if ATokens[mIndex].Kind = TPascalTokenKind.Identifier then
        mLast := mIndex
      else if not ATokens[mIndex].IsSymbol('.') then
        Exit;
    end;
  if mLast < 0 then
    Exit;
  mSymbol := AResolver.Resolve(ATree, AFileName, ATokens[mLast].StartPos);
  if (mSymbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and
    (mSymbol.SymbolKind = TIndexSymbolKind.Constant) then
    Result := TFormatString.ConstantValue(mSymbol.Signature, AValue);
end;

/// <summary>Art eines Listeneintrags aus genau einem Literal (auch negativ) bzw. True/False; Unknown sonst.
/// </summary>
function ElementClass(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  out AKind: string): TFormatArgumentClass;
var
  mIndex: Integer;
  mText, mTypeName: string;
  mToken: TPascalToken;
begin
  AKind := '';
  Result := TFormatArgumentClass.Unknown;
  mText := '';
  for mIndex := AFirst to ALast do
  begin
    mToken := ATokens[mIndex];
    if not Significant(mToken) then
      Continue;
    // Literale wie 'a'#13'b' sind mehrere Tokens; ein Vorzeichen nur vorn; alles andere ist ein Ausdruck.
    if (mToken.Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) or
      (mToken.Kind = TPascalTokenKind.Number) and ((mText = '') or (mText = '-')) or
      (mText = '') and mToken.IsSymbol('-') or
      (mText = '') and (mToken.Kind = TPascalTokenKind.Identifier) then
      mText := mText + mToken.Text
    else
      Exit;
  end;
  if SameText(mText, 'True') or SameText(mText, 'False') then
  begin
    AKind := 'boolean';
    Exit(TFormatArgumentClass.Bool);
  end;
  Result := TFormatString.LiteralClass(mText, mTypeName);
  case Result of
    TFormatArgumentClass.Text:
      AKind := 'string';
    TFormatArgumentClass.Character:
      AKind := 'char';
    TFormatArgumentClass.Integer_:
      AKind := 'integer';
    TFormatArgumentClass.Float:
      AKind := 'float';
    TFormatArgumentClass.Unknown, TFormatArgumentClass.Bool, TFormatArgumentClass.Variant_, TFormatArgumentClass.Enum,
    TFormatArgumentClass.Object_, TFormatArgumentClass.Pointer_: ;
  end;
end;

class function TSignatureFormats.Analyze(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AFirsts, ALasts: TArray<Integer>; AActiveParameter: Integer;
  const ARoutine: TFormatRoutine): TSignatureFormat;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mFirst, mOpen, mDepth, mStart, mLastToken, mClose, mCommas, mArgument: Integer;
  mValue, mKind: string;
  mPositions: TArray<TTextPosition>;
  mFormat: TFormatString;
  mSpec: TFormatSpec;
  mItem: TSignatureFormatSpec;
  mToken: TPascalToken;
  mElementFirst, mElementLast: TArray<Integer>;
  mClass: TFormatArgumentClass;

  procedure AddElement(AFrom, ATo: Integer);
  var
    mFrom, mTo: Integer;
  begin
    mFrom := FirstSignificant(mTokens, AFrom, ATo);
    mTo := ATo;
    while (mTo >= AFrom) and not Significant(mTokens[mTo]) do
      Dec(mTo);
    if mFrom < 0 then
    begin
      // Leerer Eintrag: Lage hinter dem Trennzeichen davor.
      Result.Arguments := Result.Arguments + [TTextRange.Create(mTokens[AFrom - 1].EndPos,
        mTokens[AFrom - 1].EndPos)];
      mElementFirst := mElementFirst + [-1];
      mElementLast := mElementLast + [-1];
      Exit;
    end;
    Result.Arguments := Result.Arguments + [TTextRange.Create(mTokens[mFrom].StartPos, mTokens[mTo].EndPos)];
    mElementFirst := mElementFirst + [mFrom];
    mElementLast := mElementLast + [mTo];
    Inc(Result.FilledArguments);
  end;

  procedure Report(AProblem: TSignatureFormatProblem; ASpec, AArgument: Integer; const AKind: string);
  begin
    if Result.Problem <> TSignatureFormatProblem.None then
      Exit;
    Result.Problem := AProblem;
    Result.ProblemSpec := ASpec;
    Result.ProblemArgument := AArgument;
    Result.ProblemKind := AKind;
  end;

  procedure CheckArgument(ASpec: Integer; AType: Char; AArgument: Integer);
  begin
    if (AArgument < 0) or (AArgument > High(mElementFirst)) or (mElementFirst[AArgument] < 0) then
      Exit;
    mClass := ElementClass(mTokens, mElementFirst[AArgument], mElementLast[AArgument], mKind);
    if not TFormatString.Fits(AType, mClass) then
      Report(TSignatureFormatProblem.TypeConflict, ASpec, AArgument, mKind);
  end;

begin
  Result := Default(TSignatureFormat);
  Result.ListParameter := -1;
  Result.FormatParameter := -1;
  Result.ActiveArgument := -1;
  Result.ProblemSpec := -1;
  Result.ProblemArgument := -1;
  if (ATree = nil) or (Length(AFirsts) = 0) then
    Exit;
  mTokens := ATree.Tokens;
  // Liste: erstes Argument, das mit "[" beginnt (hinter dem Formatstring, wenn dessen Stelle bekannt ist).
  mFirst := 1;
  if ARoutine.FormatIndex >= 0 then
    mFirst := ARoutine.FormatIndex + 1;
  for mIndex := mFirst to High(AFirsts) do
  begin
    mOpen := FirstSignificant(mTokens, AFirsts[mIndex], Min(ALasts[mIndex], High(mTokens)));
    if (mOpen >= 0) and mTokens[mOpen].IsSymbol('[') then
    begin
      Result.ListParameter := mIndex;
      Break;
    end;
  end;
  if ARoutine.FormatIndex >= 0 then
    Result.FormatParameter := ARoutine.FormatIndex
  else if Result.ListParameter > 0 then
    Result.FormatParameter := Result.ListParameter - 1
  else
    Exit;
  // Der Formatstring wird gerade getippt bzw. fehlt noch.
  if (Result.FormatParameter > High(AFirsts)) or (AActiveParameter = Result.FormatParameter) then
    Exit;
  if Result.ListParameter < 0 then
    Result.ListParameter := Result.FormatParameter + 1;
  if not LiteralFormat(mTokens, AFirsts[Result.FormatParameter], ALasts[Result.FormatParameter], mValue,
    mPositions) then
  begin
    mPositions := nil;
    if not ConstantFormat(AResolver, ATree, AFileName, mTokens, AFirsts[Result.FormatParameter],
      ALasts[Result.FormatParameter], mValue) then
      Exit;
  end;
  Result.Found := True;
  mFormat := TFormatString.Parse(mValue);
  Result.ArgumentCount := mFormat.ArgumentCount;
  for mSpec in mFormat.Specs do
  begin
    mItem := Default(TSignatureFormatSpec);
    mItem.Text := mSpec.Text;
    mItem.TypeChar := mSpec.TypeChar;
    mItem.Valid := mSpec.Kind = TFormatSpecKind.Valid;
    mItem.Argument := mSpec.Argument;
    mItem.WidthArgument := mSpec.WidthArgument;
    mItem.PrecisionArgument := mSpec.PrecisionArgument;
    mItem.Range := TTextRange.Create(-1, -1, -1, -1);
    if (mPositions <> nil) and (mSpec.Offset + Length(mSpec.Text) - 1 <= Length(mPositions)) then
      mItem.Range := TTextRange.Create(mPositions[mSpec.Offset - 1],
        TTextPosition.Create(mPositions[mSpec.Offset + Length(mSpec.Text) - 2].Line,
        mPositions[mSpec.Offset + Length(mSpec.Text) - 2].Character + 1));
    Result.Specs := Result.Specs + [mItem];
  end;
  // Einträge der Liste, auch hinter dem Cursor.
  mElementFirst := nil;
  mElementLast := nil;
  if Result.ListParameter <= High(AFirsts) then
  begin
    mOpen := FirstSignificant(mTokens, AFirsts[Result.ListParameter],
      Min(ALasts[Result.ListParameter], High(mTokens)));
    if (mOpen >= 0) and mTokens[mOpen].IsSymbol('[') then
    begin
      mDepth := 0;
      mStart := mOpen + 1;
      mClose := -1;
      mLastToken := High(mTokens);
      mIndex := mOpen + 1;
      while mIndex <= High(mTokens) do
      begin
        mToken := mTokens[mIndex];
        if Significant(mToken) then
        begin
          if mToken.IsSymbol('(') or mToken.IsSymbol('[') then
            Inc(mDepth)
          else if (mDepth > 0) and (mToken.IsSymbol(')') or mToken.IsSymbol(']')) then
            Dec(mDepth)
          else if mDepth = 0 then
          begin
            if mToken.IsSymbol(']') then
            begin
              mClose := mIndex;
              mLastToken := mIndex - 1;
              Break;
            end;
            // Liste ohne "]": Ende des Aufrufs bzw. der Anweisung.
            if mToken.IsSymbol(')') or mToken.IsSymbol(';') or (mToken.Kind = TPascalTokenKind.Keyword) and
              not (mToken.IsKeyword('nil') or mToken.IsKeyword('not') or mToken.IsKeyword('and') or
              mToken.IsKeyword('or') or mToken.IsKeyword('div') or mToken.IsKeyword('mod')) then
            begin
              mLastToken := mIndex - 1;
              Break;
            end;
            if mToken.IsSymbol(',') then
            begin
              AddElement(mStart, mIndex - 1);
              mStart := mIndex + 1;
            end;
          end;
        end;
        Inc(mIndex);
      end;
      if (mStart <= mLastToken) or (Length(Result.Arguments) > 0) or (mClose >= 0) then
        AddElement(mStart, mLastToken);
      // Eintrag am Cursor: Kommas zwischen "[" und dem letzten Token vor dem Cursor.
      if (AActiveParameter = Result.ListParameter) and ((mClose < 0) or (mClose > ALasts[Result.ListParameter])) then
      begin
        mCommas := 0;
        mDepth := 0;
        for mIndex := mOpen + 1 to Min(ALasts[Result.ListParameter], High(mTokens)) do
          if Significant(mTokens[mIndex]) then
          begin
            if mTokens[mIndex].IsSymbol('(') or mTokens[mIndex].IsSymbol('[') then
              Inc(mDepth)
            else if mTokens[mIndex].IsSymbol(')') or mTokens[mIndex].IsSymbol(']') then
              Dec(mDepth)
            else if (mDepth = 0) and mTokens[mIndex].IsSymbol(',') then
              Inc(mCommas);
          end;
        Result.ActiveArgument := mCommas;
      end;
    end;
  end;
  // Probleme: ungültiger Platzhalter, überzählige Argumente, Typkonflikt mit einem Literal.
  for mIndex := 0 to High(Result.Specs) do
    if not Result.Specs[mIndex].Valid then
      Report(TSignatureFormatProblem.Invalid, mIndex, -1, '');
  if (Result.ArgumentCount >= 0) and (Result.FilledArguments > Result.ArgumentCount) then
    for mArgument := Result.ArgumentCount to High(mElementFirst) do
      if mElementFirst[mArgument] >= 0 then
      begin
        Report(TSignatureFormatProblem.TooManyArguments, -1, mArgument, '');
        Break;
      end;
  for mIndex := 0 to High(Result.Specs) do
  begin
    CheckArgument(mIndex, '*', Result.Specs[mIndex].WidthArgument);
    CheckArgument(mIndex, '*', Result.Specs[mIndex].PrecisionArgument);
    if Result.Specs[mIndex].Valid then
      CheckArgument(mIndex, Result.Specs[mIndex].TypeChar, Result.Specs[mIndex].Argument);
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
    Exit(nil);
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
      mItem.AddPair('type', string(mSpec.TypeChar));
    mItem.AddPair('valid', TJSONBool.Create(mSpec.Valid));
    mItem.AddPair('argument', TJSONNumber.Create(mSpec.Argument));
    mItem.AddPair('width', TJSONNumber.Create(mSpec.WidthArgument));
    mItem.AddPair('precision', TJSONNumber.Create(mSpec.PrecisionArgument));
    if mSpec.Range.StartPos.Line >= 0 then
      mItem.AddPair('range', TLspPositions.RangeToJson(mSpec.Range));
  end;
  mArguments := TJSONArray.Create;
  Result.AddPair('arguments', mArguments);
  for mRange in AFormat.Arguments do
    mArguments.AddElement(TLspPositions.RangeToJson(mRange));
  if AFormat.Problem <> TSignatureFormatProblem.None then
  begin
    mProblem := TJSONObject.Create;
    Result.AddPair('problem', mProblem);
    mProblem.AddPair('kind', cProblems[AFormat.Problem]);
    mProblem.AddPair('placeholder', TJSONNumber.Create(AFormat.ProblemSpec));
    mProblem.AddPair('argument', TJSONNumber.Create(AFormat.ProblemArgument));
    if AFormat.ProblemKind <> '' then
      mProblem.AddPair('argumentKind', AFormat.ProblemKind);
  end;
end;

end.
