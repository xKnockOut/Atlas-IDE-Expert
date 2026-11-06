unit Atlas.Common.Lsp.CompletionInherited;

// Vollständiger inherited-Aufruf (#482, ARG-084), mit completion.inheritedCall:
// - Nach "inherited " in einer Methode steht zuerst die gleichnamige Vorfahrmethode mit den Argumenten aus den
//   Parametern der eigenen Methode ("Create(AOwner)", Marke „gleiche Parameter“), dann ihre übrigen
//   Überladungen, in Konstruktoren und Destruktoren danach die übrigen Konstruktoren bzw. Destruktoren der
//   Vorfahren (mit der deklarierenden Klasse als Marke).
// - Argumente: der eigene Parameter mit gleichem Namen, sonst der an derselben Stelle bzw. der erste freie mit
//   gleichem Typ, sonst der Parametername der Vorfahrmethode als Platzhalter.
// - Abstrakte Vorfahrmethoden fehlen; die Fußzeile nennt sie. Überschreibt ein näherer Vorfahr eine
//   abstrakte Methode, gilt seine Fassung.
// - In Funktionen ergänzt die Übernahme "Result := ", wenn vor inherited nichts in der Zeile steht.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  TInheritedParam = record
    Name: string;
    /// <summary>'' bei untypisierten Parametern (var X).</summary>
    TypeName: string;
  end;

  /// <summary>Methodenkopf aus Deklaration oder Implementierung.</summary>
  TInheritedHeader = record
    /// <summary>procedure, function, constructor oder destructor (klein).</summary>
    Kind: string;
    /// <summary>Name ohne Typ davor (Create bei TLogView.Create).</summary>
    Name: string;
    Params: TArray<TInheritedParam>;
    IsAbstract: Boolean;
    /// <summary>Liest "constructor TLogView.Create(AOwner: TComponent)" bzw. "function F(const A: string;
    /// B: Integer = 0): string; virtual; abstract;". False, wenn AText kein Methodenkopf ist.</summary>
    class function Parse(const AText: string; out AHeader: TInheritedHeader): Boolean; static;
    /// <summary>Gleiche Zahl und gleiche Typen der Parameter (Namen zählen nicht).</summary>
    function SameParams(const AOther: TInheritedHeader): Boolean;
  end;

  TInheritedMatch = (Same, Overload, Sibling);

  TInheritedMethod = record
    Header: TInheritedHeader;
    /// <summary>Deklarierende Klasse.</summary>
    Container: string;
    /// <summary>1 = direkter Vorfahr.</summary>
    Depth: Integer;
  end;

  TInheritedCall = record
    Name: string;
    Arguments: TArray<string>;
    Match: TInheritedMatch;
    Container: string;
    Depth: Integer;
    /// <summary>"Create(AOwner)" bzw. "Create" ohne Parameter.</summary>
    function Text: string;
  end;

  TCompletionInherited = class
  public const
    cMatchNames: array[TInheritedMatch] of string = ('same', 'overload', 'other');
  public
    /// <summary>Aufrufe für ACurrent aus den Vorfahrmethoden AMethods (nächster Vorfahr zuerst), sortiert:
    /// gleiche Parameter, Überladungen, übrige Konstruktoren bzw. Destruktoren. AAbstract: ausgelassene
    /// abstrakte Methoden als "TBasis.Name".</summary>
    class function Calls(const ACurrent: TInheritedHeader; const AMethods: TArray<TInheritedMethod>;
      out AAbstract: TArray<string>): TArray<TInheritedCall>; static;
    /// <summary>Argumente für den Aufruf von ATarget aus der Methode ACurrent.</summary>
    class function Arguments(const ACurrent, ATarget: TInheritedHeader): TArray<string>; static;
    /// <summary>"Result := " ergänzen: Funktion und vor inherited steht nichts in der Zeile (ALineBefore endet
    /// am Cursor, z. B. "  inherited Fo").</summary>
    class function NeedsResult(const ACurrent: TInheritedHeader; const ALineBefore: string): Boolean; static;
    /// <summary>Kopf der Routine ab AStart (1-basiert) in AText: bis zum ersten ";" außerhalb von Klammern.
    /// </summary>
    class function HeaderText(const AText: string; AStart: Integer): string; static;
  end;

implementation

uses
  System.StrUtils;

function SplitTopLevel(const AText: string; ADelimiter: Char): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
begin
  Result := nil;
  mDepth := 0;
  mStart := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if CharInSet(AText[mIndex], ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(AText[mIndex], [')', ']', '>']) then
    begin
      Dec(mDepth);
    end
    else if (AText[mIndex] = ADelimiter) and (mDepth <= 0) then
    begin
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  Result := Result + [Copy(AText, mStart, MaxInt)];
end;

/// <summary>Stelle der schließenden Klammer zur öffnenden bei AOpen; 0 ohne.</summary>
function MatchingParen(const AText: string; AOpen: Integer): Integer;
var
  mIndex, mDepth: Integer;
begin
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
        Exit(mIndex);
      end;
    end;
  end;
  Result := 0;
end;

function StripModifier(const AText: string): string;
var
  mModifier: string;
begin
  Result := Trim(AText);
  for mModifier in ['constref ', 'const ', 'var ', 'out '] do
  begin
    if StartsText(mModifier, Result) then
    begin
      Exit(Trim(Copy(Result, Length(mModifier) + 1, MaxInt)));
    end;
  end;
end;

/// <summary>Art des Kopfs AText (ohne "class ") in AKind, der Rest dahinter in ARest; False, wenn er nicht mit
/// procedure, function, constructor oder destructor beginnt.</summary>
function SplitKind(const AText: string; out AKind, ARest: string): Boolean;
var
  mText: string;
  mSpace: Integer;
begin
  AKind := '';
  ARest := '';
  mText := Trim(AText);
  if StartsText('class ', mText) then
  begin
    mText := Trim(Copy(mText, 7, MaxInt));
  end;
  mSpace := Pos(' ', mText);
  if mSpace > 0 then
  begin
    AKind := LowerCase(Copy(mText, 1, mSpace - 1));
    ARest := Trim(Copy(mText, mSpace + 1, MaxInt));
  end;
  Result := (mSpace > 0) and MatchStr(AKind, ['procedure', 'function', 'constructor', 'destructor']);
end;

/// <summary>Stelle hinter dem Namen am Anfang von ARest: das erste "(", ":" oder ";".</summary>
function NameStop(const ARest: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 1 to Length(ARest) do
  begin
    if CharInSet(ARest[mIndex], ['(', ':', ';']) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := Length(ARest) + 1;
end;

/// <summary>TAussen.TInnen.Create: nur der letzte Teil; Typargumente "TFoo&lt;T&gt;.Bar" stören nicht.</summary>
function LastNamePart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := AName;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

/// <summary>Namen und Typ (ohne Vorgabewert) einer Parametergruppe "const A, B: string = ''".</summary>
procedure SplitGroup(const AGroup: string; out ANames, ATypeName: string);
var
  mColon, mEqual: Integer;
begin
  ANames := AGroup;
  ATypeName := '';
  mColon := Pos(':', AGroup);
  if mColon > 0 then
  begin
    ANames := Copy(AGroup, 1, mColon - 1);
    ATypeName := Copy(AGroup, mColon + 1, MaxInt);
    mEqual := Pos('=', ATypeName);
    if mEqual > 0 then
    begin
      ATypeName := Copy(ATypeName, 1, mEqual - 1);
    end;
    ATypeName := Trim(ATypeName);
  end;
end;

/// <summary>Parameter der Gruppe AGroup an AParams anhängen.</summary>
procedure AddGroup(const AGroup: string; var AParams: TArray<TInheritedParam>);
var
  mNames, mTypeName, mName: string;
  mParam: TInheritedParam;
begin
  SplitGroup(AGroup, mNames, mTypeName);
  for mName in StripModifier(mNames).Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      mParam.Name := Trim(mName);
      mParam.TypeName := mTypeName;
      AParams := AParams + [mParam];
    end;
  end;
end;

/// <summary>Parameterliste am Anfang von ARest ("(…)") in AParams; ARest danach ohne sie.</summary>
procedure ParseParamList(var ARest: string; var AParams: TArray<TInheritedParam>);
var
  mClose: Integer;
  mGroup: string;
begin
  if not StartsStr('(', ARest) then
  begin
    Exit;
  end;
  mClose := MatchingParen(ARest, 1);
  if mClose = 0 then
  begin
    mClose := Length(ARest) + 1;
  end;
  for mGroup in SplitTopLevel(Copy(ARest, 2, mClose - 2), ';') do
  begin
    if Trim(mGroup) <> '' then
    begin
      AddGroup(mGroup, AParams);
    end;
  end;
  ARest := Copy(ARest, mClose + 1, MaxInt);
end;

/// <summary>Steht abstract unter den Direktiven hinter dem Kopf?</summary>
function HasAbstract(const ADirectives: string): Boolean;
var
  mGroup: string;
begin
  for mGroup in SplitTopLevel(ADirectives, ';') do
  begin
    if SameText(Trim(mGroup), 'abstract') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TInheritedHeader.Parse(const AText: string; out AHeader: TInheritedHeader): Boolean;
var
  mRest: string;
  mStop: Integer;
begin
  AHeader := Default(TInheritedHeader);
  Result := SplitKind(AText, AHeader.Kind, mRest);
  if not Result then
  begin
    Exit;
  end;
  // Name bis "(", ":" oder ";".
  mStop := NameStop(mRest);
  AHeader.Name := LastNamePart(Trim(Copy(mRest, 1, mStop - 1)));
  Result := AHeader.Name <> '';
  if not Result then
  begin
    Exit;
  end;
  mRest := Copy(mRest, mStop, MaxInt);
  ParseParamList(mRest, AHeader.Params);
  // Direktiven hinter dem Kopf.
  AHeader.IsAbstract := HasAbstract(mRest);
end;

function TInheritedHeader.SameParams(const AOther: TInheritedHeader): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(Params) = Length(AOther.Params);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Params) do
  begin
    if not SameText(Params[mIndex].TypeName, AOther.Params[mIndex].TypeName) then
    begin
      Exit(False);
    end;
  end;
end;

function TInheritedCall.Text: string;
begin
  Result := Name;
  if Length(Arguments) > 0 then
  begin
    Result := Result + '(' + string.Join(', ', Arguments) + ')';
  end;
end;

/// <summary>Erster freier eigener Parameter namens AName; -1 ohne.</summary>
function FreeByName(const ACurrent: TInheritedHeader; const AUsed: TArray<Boolean>; const AName: string): Integer;
var
  mOwn: Integer;
begin
  for mOwn := 0 to High(ACurrent.Params) do
  begin
    if not AUsed[mOwn] and SameText(ACurrent.Params[mOwn].Name, AName) then
    begin
      Exit(mOwn);
    end;
  end;
  Result := -1;
end;

/// <summary>Freier eigener Parameter vom Typ ATypeName: der an Stelle AIndex, sonst der erste; -1 ohne.</summary>
function FreeByType(const ACurrent: TInheritedHeader; const AUsed: TArray<Boolean>; AIndex: Integer;
  const ATypeName: string): Integer;
var
  mOwn: Integer;
begin
  if (AIndex <= High(ACurrent.Params)) and not AUsed[AIndex] and
    SameText(ACurrent.Params[AIndex].TypeName, ATypeName) then
  begin
    Exit(AIndex);
  end;
  for mOwn := 0 to High(ACurrent.Params) do
  begin
    if not AUsed[mOwn] and SameText(ACurrent.Params[mOwn].TypeName, ATypeName) then
    begin
      Exit(mOwn);
    end;
  end;
  Result := -1;
end;

class function TCompletionInherited.Arguments(const ACurrent, ATarget: TInheritedHeader): TArray<string>;
var
  mUsed: TArray<Boolean>;
  mIndex, mFound: Integer;
begin
  SetLength(Result, Length(ATarget.Params));
  SetLength(mUsed, Length(ACurrent.Params));
  // Erst gleiche Namen, dann gleicher Typ an derselben Stelle, dann der erste freie mit gleichem Typ.
  for mIndex := 0 to High(ATarget.Params) do
  begin
    Result[mIndex] := '';
    mFound := FreeByName(ACurrent, mUsed, ATarget.Params[mIndex].Name);
    if mFound >= 0 then
    begin
      mUsed[mFound] := True;
      Result[mIndex] := ACurrent.Params[mFound].Name;
    end;
  end;
  for mIndex := 0 to High(ATarget.Params) do
  begin
    if Result[mIndex] <> '' then
    begin
      Continue;
    end;
    mFound := FreeByType(ACurrent, mUsed, mIndex, ATarget.Params[mIndex].TypeName);
    if mFound >= 0 then
    begin
      mUsed[mFound] := True;
      Result[mIndex] := ACurrent.Params[mFound].Name;
    end
    else
    begin
      Result[mIndex] := ATarget.Params[mIndex].Name;
    end;
  end;
end;

function KeyOf(const AHeader: TInheritedHeader): string;
var
  mParam: TInheritedParam;
begin
  Result := UpperCase(AHeader.Name) + '(';
  for mParam in AHeader.Params do
  begin
    Result := Result + UpperCase(mParam.TypeName) + ';';
  end;
end;

/// <summary>Gehört AMethod zu den Aufrufen für ACurrent: gleicher Name bzw. in Konstruktoren und Destruktoren
/// gleiche Art?</summary>
function Applies(const ACurrent: TInheritedHeader; const AMethod: TInheritedMethod): Boolean;
begin
  Result := SameText(AMethod.Header.Name, ACurrent.Name) or
    (MatchStr(ACurrent.Kind, ['constructor', 'destructor']) and (AMethod.Header.Kind = ACurrent.Kind));
end;

function MatchOf(const ACurrent, AHeader: TInheritedHeader): TInheritedMatch;
begin
  if not SameText(AHeader.Name, ACurrent.Name) then
  begin
    Result := TInheritedMatch.Sibling;
  end
  else if AHeader.SameParams(ACurrent) then
  begin
    Result := TInheritedMatch.Same;
  end
  else
  begin
    Result := TInheritedMatch.Overload;
  end;
end;

/// <summary>Stabil nach Art: gleiche Parameter, Überladungen, übrige.</summary>
procedure SortByMatch(var ACalls: TArray<TInheritedCall>);
var
  mIndex, mInner: Integer;
  mSwap: TInheritedCall;
begin
  for mIndex := 1 to High(ACalls) do
  begin
    mInner := mIndex;
    while (mInner > 0) and (Ord(ACalls[mInner - 1].Match) > Ord(ACalls[mInner].Match)) do
    begin
      mSwap := ACalls[mInner - 1];
      ACalls[mInner - 1] := ACalls[mInner];
      ACalls[mInner] := mSwap;
      Dec(mInner);
    end;
  end;
end;

/// <summary>"TBasis.Name" der abstrakten Methode AMethod an AAbstract anhängen, wenn sie fehlt.</summary>
procedure AddAbstract(const AMethod: TInheritedMethod; var AAbstract: TArray<string>);
var
  mName: string;
begin
  mName := AMethod.Container + '.' + AMethod.Header.Name;
  if not MatchText(mName, AAbstract) then
  begin
    AAbstract := AAbstract + [mName];
  end;
end;

class function TCompletionInherited.Calls(const ACurrent: TInheritedHeader;
  const AMethods: TArray<TInheritedMethod>; out AAbstract: TArray<string>): TArray<TInheritedCall>;
var
  mMethod: TInheritedMethod;
  mCall: TInheritedCall;
  mSeen: TArray<string>;
  mKey: string;
begin
  Result := nil;
  AAbstract := nil;
  mSeen := nil;
  for mMethod in AMethods do
  begin
    // Nächster Vorfahr zuerst: was er überschreibt, gilt nicht mehr.
    mKey := KeyOf(mMethod.Header);
    if not Applies(ACurrent, mMethod) or MatchText(mKey, mSeen) then
    begin
      Continue;
    end;
    mSeen := mSeen + [mKey];
    if mMethod.Header.IsAbstract then
    begin
      AddAbstract(mMethod, AAbstract);
      Continue;
    end;
    mCall := Default(TInheritedCall);
    mCall.Name := mMethod.Header.Name;
    mCall.Arguments := Arguments(ACurrent, mMethod.Header);
    mCall.Container := mMethod.Container;
    mCall.Depth := mMethod.Depth;
    mCall.Match := MatchOf(ACurrent, mMethod.Header);
    Result := Result + [mCall];
  end;
  SortByMatch(Result);
end;

class function TCompletionInherited.NeedsResult(const ACurrent: TInheritedHeader;
  const ALineBefore: string): Boolean;
var
  mLine: string;
  mIndex: Integer;
begin
  Result := False;
  if ACurrent.Kind <> 'function' then
  begin
    Exit;
  end;
  mLine := TrimLeft(ALineBefore);
  if not StartsText('inherited', mLine) then
  begin
    Exit;
  end;
  // Hinter inherited nur Leerzeichen und der angefangene Name.
  mLine := Copy(mLine, Length('inherited') + 1, MaxInt);
  if (mLine = '') or not CharInSet(mLine[1], [' ', #9]) then
  begin
    Exit;
  end;
  mLine := TrimLeft(mLine);
  for mIndex := 1 to Length(mLine) do
  begin
    if not CharInSet(mLine[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

class function TCompletionInherited.HeaderText(const AText: string; AStart: Integer): string;
var
  mIndex, mDepth: Integer;
begin
  mDepth := 0;
  Result := Copy(AText, AStart, MaxInt);
  for mIndex := AStart to Length(AText) do
  begin
    if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
    end
    else if (AText[mIndex] = ';') and (mDepth <= 0) then
    begin
      Result := Copy(AText, AStart, mIndex - AStart);
      Break;
    end;
  end;
  Result := StringReplace(StringReplace(Result, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
end;

end.
