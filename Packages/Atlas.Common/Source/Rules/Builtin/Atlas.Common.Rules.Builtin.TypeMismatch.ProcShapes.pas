unit Atlas.Common.Rules.Builtin.TypeMismatch.ProcShapes;

// Kopf prozeduraler Typen für type-mismatch (#1369): Text eines Prozedurtyps bzw. einer Routine in eine Gestalt
// (function/procedure, of object, reference to, Parameter, Ergebnis) lesen und mit Kandidaten einer Zuweisung
// vergleichen. Die Regel selbst steht in Atlas.Common.Rules.Builtin.TypeMismatch.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Semantics.NameResolver;

type
{$SCOPEDENUMS ON}
  /// <summary>Wie eine Routine zu einem prozeduralen Typ passt.</summary>
  TProcMatch = (Yes, Unsure, MethodKind, Parameters, ParameterType);
{$SCOPEDENUMS OFF}

  /// <summary>Kopf eines prozeduralen Typs bzw. einer Routine.</summary>
  TProcShape = record
    IsFunction: Boolean;
    OfObject: Boolean;
    Reference: Boolean;
    Params: TArray<TSignatureParameter>;
    ResultType: string;
  end;

  /// <summary>Urteil über alle Kandidaten einer Zuweisung an einen prozeduralen Typ.</summary>
  TProcVerdict = record
    First: TProcMatch;
    HasType: Boolean;
    Formal: string;
    Actual: string;
  end;

  /// <summary>Kopf prozeduraler Typen und Routinen lesen und vergleichen.</summary>
  TProcShapes = class
  public
    /// <summary>Kopf "procedure(A: Integer) of object", "reference to function: Boolean" bzw. einer Routine
    /// "class procedure TKlasse.Machen; static;" (mit Namen, AWithName) zerlegen. False, wenn er nicht lesbar ist.
    /// </summary>
    class function ParseShape(const AText: string; AWithName: Boolean; out AShape: TProcShape): Boolean; static;
    class function NormalizedModifier(const AModifier: string): string; static;
    /// <summary>Rumpf hinter "=" der Alias-Deklaration ASymbol ohne Semikolon; False bei bedingter, fehlender oder
    /// kommentierter.</summary>
    class function AliasBody(const ASymbol: TResolvedSymbol; out ABody: string): Boolean; static;
    /// <summary>Passen Art (function/procedure, Methode/Routine), Anzahl und Modifizierer der Parameter von AShape zu
    /// ATarget? Yes, wenn ja, sonst die erste Abweichung.</summary>
    class function ShapeKindMatch(const ATarget: TProcShape; const ACandidate: TResolvedSymbol;
      const AShape: TProcShape): TProcMatch; static;
    /// <summary>Vergleicht die Parametertypen gleich langer Listen; AFormal/AActual nennen das erste abweichende Paar.
    /// </summary>
    class function ParamTypesMatch(const ATarget, AShape: TProcShape; out AFormal, AActual: string): TProcMatch;
      static;
    /// <summary>Wie die Routine ACandidate mit dem Kopf AShape zum prozeduralen Typ ATarget passt.</summary>
    class function CompareShape(const ATarget: TProcShape; const ACandidate: TResolvedSymbol; const AShape: TProcShape;
      out AFormal, AActual: string): TProcMatch; static;
    /// <summary>Kopf des Kandidaten, wenn er nur als Routine (nicht als Aufruf) zugewiesen sein kann.</summary>
    class function AssignableShape(const ACandidate: TResolvedSymbol; out AShape: TProcShape): Boolean; static;
    /// <summary>True, wenn alle Kandidaten lesbar sind und keiner zu ATarget passt; AVerdict nennt die Abweichungen.
    /// </summary>
    class function AllCandidatesFail(const ATarget: TProcShape; const ACandidates: TArray<TResolvedSymbol>;
      out AVerdict: TProcVerdict): Boolean; static;
    /// <summary>Kandidat ohne Generik, Bindungen und Überladungen, dessen Parameter fest stehen.</summary>
    class function IsFixedRoutine(const ACandidate: TResolvedSymbol): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Semantics.TypeCompatibility,
  Atlas.Common.Semantics.TypeIdentity;

const
  // Aufrufkonventionen, die in einem Prozedurtyp direkt hinter procedure bzw. function stehen dürfen.
  cConventions: array[0..4] of string = ('stdcall', 'cdecl', 'register', 'pascal', 'safecall');

/// <summary>Teil von AText innerhalb der Klammer ab AOpen (1-basiert) bis zur passenden schließenden; AClose die
/// Stelle der schließenden Klammer, 0 ohne.</summary>
function InParens(const AText: string; AOpen: Integer; out AClose: Integer): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  AClose := 0;
  mDepth := 0;
  for mIndex := AOpen to Length(AText) do
  begin
    if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        AClose := mIndex;
        Exit(Copy(AText, AOpen + 1, mIndex - AOpen - 1));
      end;
    end;
  end;
end;

/// <summary>reference to, class und das Schlüsselwort procedure bzw. function von AText abtrennen; False ohne
/// Schlüsselwort.</summary>
function StripKind(var AText: string; var AShape: TProcShape): Boolean;
begin
  Result := True;
  if StartsText('reference to ', AText) then
  begin
    AShape.Reference := True;
    AText := Trim(Copy(AText, 14, MaxInt));
  end;
  if StartsText('class ', AText) then
  begin
    AText := Trim(Copy(AText, 7, MaxInt));
  end;
  if StartsText('procedure', AText) then
  begin
    AText := TrimLeft(Copy(AText, 10, MaxInt));
  end
  else if StartsText('function', AText) then
  begin
    AShape.IsFunction := True;
    AText := TrimLeft(Copy(AText, 9, MaxInt));
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Beginnt AText mit einer Aufrufkonvention?</summary>
function StartsWithConvention(const AText: string): Boolean;
var
  mConvention: string;
begin
  for mConvention in cConventions do
  begin
    if StartsText(mConvention, AText) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Index des ersten Zeichens aus AStops in AText ab 1; Length + 1 ohne.</summary>
function StopAt(const AText: string; const AStops: TSysCharSet): Integer;
begin
  Result := 1;
  while (Result <= Length(AText)) and not CharInSet(AText[Result], AStops) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Name überspringen (AWithName) bzw. prüfen, dass kein Name folgt; False bei einem Namen im Typ.
/// </summary>
function SkipName(var AText: string; AWithName: Boolean): Boolean;
begin
  Result := True;
  if AWithName then
  begin
    // Name bis zur Klammer, zum Doppelpunkt oder zum Semikolon (TKlasse.Machen, Foo<T>).
    AText := TrimLeft(Copy(AText, StopAt(AText, ['(', ':', ';', ' ']), MaxInt));
  end
  else if AText <> '' then
  begin
    Result := CharInSet(AText[1], ['(', ':', ';', 'o', 'O']) or StartsWithConvention(AText);
  end;
end;

/// <summary>Parameterliste in Klammern lesen, wenn AText damit beginnt; False ohne schließende Klammer.</summary>
function ReadParams(var AText: string; var AShape: TProcShape): Boolean;
var
  mRest: string;
  mClose: Integer;
begin
  Result := True;
  if not StartsStr('(', AText) then
  begin
    Exit;
  end;
  mRest := InParens(AText, 1, mClose);
  Result := mClose > 0;
  if Result then
  begin
    AShape.Params := TChangeSignature.ParseParameters(mRest);
    AText := TrimLeft(Copy(AText, mClose + 1, MaxInt));
  end;
end;

/// <summary>Ergebnistyp hinter dem Doppelpunkt lesen, wenn AText damit beginnt; Leerraum in und vor spitzen
/// Klammern gehört dazu ("TProc &lt;string&gt;" aus dem Index, "TFunc&lt;string, Integer&gt;").</summary>
procedure ReadResult(var AText: string; var AShape: TProcShape);
var
  mPosition, mDepth: Integer;
begin
  if not StartsStr(':', AText) then
  begin
    Exit;
  end;
  AText := TrimLeft(Copy(AText, 2, MaxInt));
  mPosition := 1;
  mDepth := 0;
  while (mPosition <= Length(AText)) and (AText[mPosition] <> ';') and ((AText[mPosition] <> ' ') or (mDepth > 0) or
    StartsStr('<', TrimLeft(Copy(AText, mPosition, MaxInt)))) do
  begin
    if AText[mPosition] = '<' then
    begin
      Inc(mDepth);
    end
    else if AText[mPosition] = '>' then
    begin
      Dec(mDepth);
    end;
    Inc(mPosition);
  end;
  AShape.ResultType := Copy(AText, 1, mPosition - 1);
  AText := TrimLeft(Copy(AText, mPosition, MaxInt));
end;

/// <summary>Kopf "procedure(A: Integer) of object", "reference to function: Boolean" bzw. einer Routine
/// "class procedure TKlasse.Machen; static;" (mit Namen, AWithName) zerlegen. False, wenn er nicht lesbar ist.
/// </summary>
class function TProcShapes.ParseShape(const AText: string; AWithName: Boolean; out AShape: TProcShape): Boolean;
var
  mText, mWord: string;
begin
  AShape := Default(TProcShape);
  mText := Trim(AText);
  Result := StripKind(mText, AShape) and SkipName(mText, AWithName) and ReadParams(mText, AShape);
  if not Result then
  begin
    Exit;
  end;
  ReadResult(mText, AShape);
  // of object und Direktiven.
  for mWord in mText.Replace(';', ' ').Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if SameText(mWord, 'object') then
    begin
      AShape.OfObject := True;
    end;
  end;
end;

class function TProcShapes.NormalizedModifier(const AModifier: string): string;
var
  mWords: TArray<string>;
begin
  // "[ref] const" → const.
  mWords := LowerCase(Trim(AModifier)).Split([' '], TStringSplitOptions.ExcludeEmpty);
  Result := '';
  if Length(mWords) > 0 then
  begin
    Result := mWords[High(mWords)];
  end;
end;

/// <summary>Rumpf hinter "=" der Alias-Deklaration ASymbol ohne Semikolon; False bei bedingter, fehlender oder
/// kommentierter.</summary>
class function TProcShapes.AliasBody(const ASymbol: TResolvedSymbol; out ABody: string): Boolean;
begin
  ABody := '';
  Result := (ASymbol.Condition = '') and (Pos('=', ASymbol.Signature) > 0);
  if not Result then
  begin
    Exit;
  end;
  ABody := Trim(Copy(ASymbol.Signature, Pos('=', ASymbol.Signature) + 1, MaxInt));
  if EndsStr(';', ABody) then
  begin
    ABody := Trim(Copy(ABody, 1, Length(ABody) - 1));
  end;
  Result := Pos('{', ABody) = 0;
end;

/// <summary>Passen Art (function/procedure, Methode/Routine), Anzahl und Modifizierer der Parameter von AShape zu
/// ATarget? Yes, wenn ja, sonst die erste Abweichung.</summary>
class function TProcShapes.ShapeKindMatch(const ATarget: TProcShape; const ACandidate: TResolvedSymbol;
  const AShape: TProcShape): TProcMatch;
var
  mParam: Integer;
  mIsMethod: Boolean;
begin
  if AShape.IsFunction <> ATarget.IsFunction then
  begin
    Exit(TProcMatch.Unsure);
  end;
  mIsMethod := (ACandidate.SymbolKind = TIndexSymbolKind.Method) and not MatchText('static', ACandidate.Directives);
  // Eine Methodenreferenz nimmt Methoden und freie Routinen.
  if (mIsMethod <> ATarget.OfObject) and not ATarget.Reference then
  begin
    Exit(TProcMatch.MethodKind);
  end;
  Result := TProcMatch.Parameters;
  if Length(AShape.Params) <> Length(ATarget.Params) then
  begin
    Exit;
  end;
  for mParam := 0 to High(ATarget.Params) do
  begin
    if NormalizedModifier(ATarget.Params[mParam].Modifier) <> NormalizedModifier(AShape.Params[mParam].Modifier) then
    begin
      Exit;
    end;
  end;
  Result := TProcMatch.Yes;
end;

/// <summary>Vergleicht die Parametertypen gleich langer Listen; AFormal/AActual nennen das erste abweichende Paar.
/// </summary>
class function TProcShapes.ParamTypesMatch(const ATarget, AShape: TProcShape; out AFormal, AActual: string): TProcMatch;
var
  mParam: Integer;
  mLeft, mRight: TValueType;
begin
  AFormal := '';
  AActual := '';
  Result := TProcMatch.Yes;
  for mParam := 0 to High(ATarget.Params) do
  begin
    if TTypeIdentity.Same(ATarget.Params[mParam].TypeName, AShape.Params[mParam].TypeName) then
    begin
      Continue;
    end;
    mLeft := TValueType.FromBuiltin(TTypeIdentity.Clean(ATarget.Params[mParam].TypeName));
    mRight := TValueType.FromBuiltin(TTypeIdentity.Clean(AShape.Params[mParam].TypeName));
    if (mLeft.Kind <> TValueKind.Builtin) or (mRight.Kind <> TValueKind.Builtin) or
      TTypeCompatibility.PlatformDependent(mLeft.Name) or TTypeCompatibility.PlatformDependent(mRight.Name) then
    begin
      Exit(TProcMatch.Unsure);
    end;
    if AFormal = '' then
    begin
      AFormal := mLeft.Name;
      AActual := mRight.Name;
    end;
    Result := TProcMatch.ParameterType;
  end;
end;

/// <summary>Wie die Routine ACandidate mit dem Kopf AShape zum prozeduralen Typ ATarget passt.</summary>
class function TProcShapes.CompareShape(const ATarget: TProcShape; const ACandidate: TResolvedSymbol;
  const AShape: TProcShape; out AFormal, AActual: string): TProcMatch;
begin
  AFormal := '';
  AActual := '';
  Result := TProcShapes.ShapeKindMatch(ATarget, ACandidate, AShape);
  if Result = TProcMatch.Yes then
  begin
    Result := TProcShapes.ParamTypesMatch(ATarget, AShape, AFormal, AActual);
  end;
  if (Result = TProcMatch.Yes) and AShape.IsFunction and
    not TTypeIdentity.Same(AShape.ResultType, ATarget.ResultType) then
  begin
    Result := TProcMatch.Unsure;
  end;
end;

/// <summary>Kopf des Kandidaten, wenn er nur als Routine (nicht als Aufruf) zugewiesen sein kann.</summary>
class function TProcShapes.AssignableShape(const ACandidate: TResolvedSymbol; out AShape: TProcShape): Boolean;
begin
  Result := TProcShapes.ParseShape(ACandidate.Signature, True, AShape);
  // Eine Funktion ohne Pflichtparameter kann hier auch aufgerufen werden.
  if Result and AShape.IsFunction then
  begin
    Result := (Length(AShape.Params) > 0) and (AShape.Params[0].DefaultValue = '');
  end;
end;

/// <summary>True, wenn alle Kandidaten lesbar sind und keiner zu ATarget passt; AVerdict nennt die Abweichungen.
/// </summary>
class function TProcShapes.AllCandidatesFail(const ATarget: TProcShape; const ACandidates: TArray<TResolvedSymbol>;
  out AVerdict: TProcVerdict): Boolean;
var
  mIndex: Integer;
  mShape: TProcShape;
  mMatch: TProcMatch;
  mFormal, mActual: string;
begin
  AVerdict := Default(TProcVerdict);
  AVerdict.First := TProcMatch.Yes;
  Result := True;
  for mIndex := 0 to High(ACandidates) do
  begin
    if not TProcShapes.AssignableShape(ACandidates[mIndex], mShape) then
    begin
      Exit(False);
    end;
    mMatch := TProcShapes.CompareShape(ATarget, ACandidates[mIndex], mShape, mFormal, mActual);
    if mIndex = 0 then
    begin
      AVerdict.First := mMatch;
    end;
    Result := Result and not (mMatch in [TProcMatch.Yes, TProcMatch.Unsure]);
    if (mMatch = TProcMatch.ParameterType) and not AVerdict.HasType then
    begin
      AVerdict.HasType := True;
      AVerdict.Formal := mFormal;
      AVerdict.Actual := mActual;
    end;
  end;
end;

/// <summary>Kandidat ohne Generik, Bindungen und Überladungen, dessen Parameter fest stehen.</summary>
class function TProcShapes.IsFixedRoutine(const ACandidate: TResolvedSymbol): Boolean;
begin
  Result := (ACandidate.SymbolKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Routine,
    TIndexSymbolKind.Constructor_]) and not ACandidate.Builtin and (ACandidate.TypeParams = '');
  Result := Result and (Length(ACandidate.Bindings) = 0) and (Length(ACandidate.Overloads) = 0);
  Result := Result and (Length(ACandidate.VariantParams) <= 1) and not MatchText('overload', ACandidate.Directives);
  Result := Result and not ContainsText(ACandidate.Signature, 'overload');
end;

end.
