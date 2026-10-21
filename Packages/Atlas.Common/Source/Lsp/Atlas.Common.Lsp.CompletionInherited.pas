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
    MatchNames: array[TInheritedMatch] of string = ('same', 'overload', 'other');
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
  Index, Depth, Start: Integer;
begin
  Result := nil;
  Depth := 0;
  Start := 1;
  for Index := 1 to Length(AText) do
    if CharInSet(AText[Index], ['(', '[', '<']) then
      Inc(Depth)
    else if CharInSet(AText[Index], [')', ']', '>']) then
      Dec(Depth)
    else if (AText[Index] = ADelimiter) and (Depth <= 0) then
    begin
      Result := Result + [Copy(AText, Start, Index - Start)];
      Start := Index + 1;
    end;
  Result := Result + [Copy(AText, Start, MaxInt)];
end;

/// <summary>Stelle der schließenden Klammer zur öffnenden bei AOpen; 0 ohne.</summary>
function MatchingParen(const AText: string; AOpen: Integer): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  for Index := AOpen to Length(AText) do
    if AText[Index] = '(' then
      Inc(Depth)
    else if AText[Index] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(Index);
    end;
  Result := 0;
end;

function StripModifier(const AText: string): string;
var
  Modifier: string;
begin
  Result := Trim(AText);
  for Modifier in ['constref ', 'const ', 'var ', 'out '] do
    if StartsText(Modifier, Result) then
      Exit(Trim(Copy(Result, Length(Modifier) + 1, MaxInt)));
end;

class function TInheritedHeader.Parse(const AText: string; out AHeader: TInheritedHeader): Boolean;
var
  Text, Rest, Group, Names, TypeName, Name: string;
  Space, Open, Close, Stop, Colon, Equal, Dot: Integer;
  Param: TInheritedParam;
begin
  AHeader := Default(TInheritedHeader);
  Text := Trim(AText);
  if StartsText('class ', Text) then
    Text := Trim(Copy(Text, 7, MaxInt));
  Space := Pos(' ', Text);
  Result := Space > 0;
  if not Result then
    Exit;
  AHeader.Kind := LowerCase(Copy(Text, 1, Space - 1));
  Result := MatchStr(AHeader.Kind, ['procedure', 'function', 'constructor', 'destructor']);
  if not Result then
    Exit;
  Rest := Trim(Copy(Text, Space + 1, MaxInt));
  // Name bis "(", ":" oder ";".
  Stop := Length(Rest) + 1;
  for Open := 1 to Length(Rest) do
    if CharInSet(Rest[Open], ['(', ':', ';']) then
    begin
      Stop := Open;
      Break;
    end;
  Name := Trim(Copy(Rest, 1, Stop - 1));
  // TAussen.TInnen.Create: nur der letzte Teil; Typargumente "TFoo<T>.Bar" stören nicht.
  Dot := LastDelimiter('.', Name);
  if Dot > 0 then
    Name := Copy(Name, Dot + 1, MaxInt);
  AHeader.Name := Name;
  Result := Name <> '';
  if not Result then
    Exit;
  Rest := Copy(Rest, Stop, MaxInt);
  if StartsStr('(', Rest) then
  begin
    Close := MatchingParen(Rest, 1);
    if Close = 0 then
      Close := Length(Rest) + 1;
    for Group in SplitTopLevel(Copy(Rest, 2, Close - 2), ';') do
    begin
      if Trim(Group) = '' then
        Continue;
      Colon := Pos(':', Group);
      if Colon > 0 then
      begin
        Names := Copy(Group, 1, Colon - 1);
        TypeName := Copy(Group, Colon + 1, MaxInt);
        Equal := Pos('=', TypeName);
        if Equal > 0 then
          TypeName := Copy(TypeName, 1, Equal - 1);
        TypeName := Trim(TypeName);
      end
      else
      begin
        Names := Group;
        TypeName := '';
      end;
      for Name in StripModifier(Names).Split([',']) do
        if Trim(Name) <> '' then
        begin
          Param.Name := Trim(Name);
          Param.TypeName := TypeName;
          AHeader.Params := AHeader.Params + [Param];
        end;
    end;
    Rest := Copy(Rest, Close + 1, MaxInt);
  end;
  // Direktiven hinter dem Kopf.
  for Group in SplitTopLevel(Rest, ';') do
    if SameText(Trim(Group), 'abstract') then
      AHeader.IsAbstract := True;
end;

function TInheritedHeader.SameParams(const AOther: TInheritedHeader): Boolean;
var
  Index: Integer;
begin
  Result := Length(Params) = Length(AOther.Params);
  if not Result then
    Exit;
  for Index := 0 to High(Params) do
    if not SameText(Params[Index].TypeName, AOther.Params[Index].TypeName) then
      Exit(False);
end;

function TInheritedCall.Text: string;
begin
  Result := Name;
  if Length(Arguments) > 0 then
    Result := Result + '(' + string.Join(', ', Arguments) + ')';
end;

class function TCompletionInherited.Arguments(const ACurrent, ATarget: TInheritedHeader): TArray<string>;
var
  Used: TArray<Boolean>;
  Index, Own, Found: Integer;
begin
  SetLength(Result, Length(ATarget.Params));
  SetLength(Used, Length(ACurrent.Params));
  // Erst gleiche Namen, dann gleicher Typ an derselben Stelle, dann der erste freie mit gleichem Typ.
  for Index := 0 to High(ATarget.Params) do
  begin
    Result[Index] := '';
    for Own := 0 to High(ACurrent.Params) do
      if not Used[Own] and SameText(ACurrent.Params[Own].Name, ATarget.Params[Index].Name) then
      begin
        Used[Own] := True;
        Result[Index] := ACurrent.Params[Own].Name;
        Break;
      end;
  end;
  for Index := 0 to High(ATarget.Params) do
  begin
    if Result[Index] <> '' then
      Continue;
    Found := -1;
    if (Index <= High(ACurrent.Params)) and not Used[Index] and
      SameText(ACurrent.Params[Index].TypeName, ATarget.Params[Index].TypeName) then
      Found := Index
    else
      for Own := 0 to High(ACurrent.Params) do
        if not Used[Own] and SameText(ACurrent.Params[Own].TypeName, ATarget.Params[Index].TypeName) then
        begin
          Found := Own;
          Break;
        end;
    if Found >= 0 then
    begin
      Used[Found] := True;
      Result[Index] := ACurrent.Params[Found].Name;
    end
    else
      Result[Index] := ATarget.Params[Index].Name;
  end;
end;

function KeyOf(const AHeader: TInheritedHeader): string;
var
  Param: TInheritedParam;
begin
  Result := UpperCase(AHeader.Name) + '(';
  for Param in AHeader.Params do
    Result := Result + UpperCase(Param.TypeName) + ';';
end;

class function TCompletionInherited.Calls(const ACurrent: TInheritedHeader;
  const AMethods: TArray<TInheritedMethod>; out AAbstract: TArray<string>): TArray<TInheritedCall>;
var
  Method: TInheritedMethod;
  Call, Swap: TInheritedCall;
  Seen: TArray<string>;
  Key, Name: string;
  Special: Boolean;
  Index, Inner: Integer;
begin
  Result := nil;
  AAbstract := nil;
  Seen := nil;
  Special := MatchStr(ACurrent.Kind, ['constructor', 'destructor']);
  for Method in AMethods do
  begin
    if not SameText(Method.Header.Name, ACurrent.Name) and
      (not Special or (Method.Header.Kind <> ACurrent.Kind)) then
      Continue;
    // Nächster Vorfahr zuerst: was er überschreibt, gilt nicht mehr.
    Key := KeyOf(Method.Header);
    if MatchText(Key, Seen) then
      Continue;
    Seen := Seen + [Key];
    if Method.Header.IsAbstract then
    begin
      Name := Method.Container + '.' + Method.Header.Name;
      if not MatchText(Name, AAbstract) then
        AAbstract := AAbstract + [Name];
      Continue;
    end;
    Call := Default(TInheritedCall);
    Call.Name := Method.Header.Name;
    Call.Arguments := Arguments(ACurrent, Method.Header);
    Call.Container := Method.Container;
    Call.Depth := Method.Depth;
    if not SameText(Method.Header.Name, ACurrent.Name) then
      Call.Match := TInheritedMatch.Sibling
    else if Method.Header.SameParams(ACurrent) then
      Call.Match := TInheritedMatch.Same
    else
      Call.Match := TInheritedMatch.Overload;
    Result := Result + [Call];
  end;
  // Stabil nach Art: gleiche Parameter, Überladungen, übrige.
  for Index := 1 to High(Result) do
  begin
    Inner := Index;
    while (Inner > 0) and (Ord(Result[Inner - 1].Match) > Ord(Result[Inner].Match)) do
    begin
      Swap := Result[Inner - 1];
      Result[Inner - 1] := Result[Inner];
      Result[Inner] := Swap;
      Dec(Inner);
    end;
  end;
end;

class function TCompletionInherited.NeedsResult(const ACurrent: TInheritedHeader;
  const ALineBefore: string): Boolean;
var
  Line: string;
  Index: Integer;
begin
  Result := False;
  if ACurrent.Kind <> 'function' then
    Exit;
  Line := TrimLeft(ALineBefore);
  if not StartsText('inherited', Line) then
    Exit;
  // Hinter inherited nur Leerzeichen und der angefangene Name.
  Line := Copy(Line, Length('inherited') + 1, MaxInt);
  if (Line = '') or not CharInSet(Line[1], [' ', #9]) then
    Exit;
  Line := TrimLeft(Line);
  for Index := 1 to Length(Line) do
    if not CharInSet(Line[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit;
  Result := True;
end;

class function TCompletionInherited.HeaderText(const AText: string; AStart: Integer): string;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  Result := Copy(AText, AStart, MaxInt);
  for Index := AStart to Length(AText) do
    if AText[Index] = '(' then
      Inc(Depth)
    else if AText[Index] = ')' then
      Dec(Depth)
    else if (AText[Index] = ';') and (Depth <= 0) then
    begin
      Result := Copy(AText, AStart, Index - AStart);
      Break;
    end;
  Result := StringReplace(StringReplace(Result, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
end;

end.
