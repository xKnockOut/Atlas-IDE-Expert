unit Atlas.Common.Lsp.CompletionAnonymous;

// Anonyme Methoden (#468, ARG-069): Erwartet ein Argument oder eine Zuweisung einen Methodenreferenztyp
// ("reference to procedure/function"), bietet die Vervollständigung ganz oben ein Gerüst mit passender
// Signatur an. Hier die Teile ohne Namensauflösung; TCompletionMethods.AnonymousItem verbindet sie mit dem
// erwarteten Typ.
// - Parse liest die Deklaration aus der Signatur des Index ("TPredicate<T> = reference to function(Arg1: T):
//   Boolean;"); ein Alias ("TKundenFilter = TPredicate<TKunde>;") liefert sein Ziel.
// - Typparameter werden durch die Typargumente des erwarteten Typs ersetzt (TPredicate<TKunde> → Arg1: TKunde).
// - Fehlt die Deklaration im Index, gelten die von System.SysUtils (TProc, TProc<…>, TFunc<…>, TPredicate<T>).
// - Parameter Arg1, Arg2 … der generischen RTL-Typen heißen um (#452): allein Value, sonst nach dem Typ
//   (Kunde) bzw. Value1, Value2; dazu const und das Präfix der Parameter im Projekt. Eigene Namen bleiben.
// - Gerüst: begin/end eine Ebene tiefer als die Zeile, Caret im Rumpf, bei Funktionen "Result := ".

interface

uses
  System.SysUtils;

type
  TMethodRefParam = record
    /// <summary>const, var, out, constref oder ''.</summary>
    Modifier: string;
    Name: string;
    /// <summary>Typ wie geschrieben; '' bei untypisierten Parametern.</summary>
    TypeText: string;
  end;

  TMethodRef = record
    IsFunction: Boolean;
    Params: TArray<TMethodRefParam>;
    ResultType: string;
  end;

  TCompletionAnonymous = class
  public const
    /// <summary>Einrückung je Ebene.</summary>
    IndentUnit = '  ';
    /// <summary>Höchstzahl verfolgter Aliase.</summary>
    MaxAliasDepth = 8;
  public
    /// <summary>Deklaration "Name&lt;T&gt; = reference to …" in AMethodRef, ATypeParams die Typparameter (T). Ist
    /// sie ein Alias, steht sein Ziel in ATarget (ohne ";") und das Ergebnis ist False; ebenso bei anderen
    /// Typen (dann ATarget '').</summary>
    class function Parse(const ASignature: string; out ATypeParams: TArray<string>; out AMethodRef: TMethodRef;
      out ATarget: string): Boolean; static;
    /// <summary>"TFunc&lt;TKunde, Boolean&gt;" → ABase "TFunc", Ergebnis [TKunde, Boolean]; ohne spitze Klammern leer.
    /// </summary>
    class function TypeArgs(const ATypeText: string; out ABase: string): TArray<string>; static;
    /// <summary>Ersetzt ganze Wörter ANames[i] durch AValues[i] (ohne Groß-/Kleinschreibung).</summary>
    class function Substitute(const AText: string; const ANames, AValues: TArray<string>): string; static;
    /// <summary>Deklaration aus System.SysUtils für ABase (ohne oder mit Unit) und AArgCount Typargumente; ''
    /// ohne.</summary>
    class function RtlDeclaration(const ABase: string; AArgCount: Integer): string; static;
    /// <summary>Parameter Arg1, Arg2 … umbenennen (siehe oben); APrefix ist das Parameterpräfix des Projekts.
    /// </summary>
    class function Named(const AMethodRef: TMethodRef; const APrefix: string): TMethodRef; static;
    /// <summary>"procedure", "procedure(const Value: TKunde)", "function(const Value: TKunde): Boolean".</summary>
    class function Header(const AMethodRef: TMethodRef): string; static;
    /// <summary>LSP-Snippet mit #10, eingerückt relativ zur Zeile, $0 im Rumpf.</summary>
    class function Snippet(const AMethodRef: TMethodRef): string; static;
    /// <summary>Klartext mit AIndent (Einrückung der Zeile) und ALineBreak; ohne Platzhalter steht der Cursor
    /// danach hinter end.</summary>
    class function Plain(const AMethodRef: TMethodRef; const AIndent, ALineBreak: string): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.NameSuggestions;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Tokens ohne Kommentare und Direktiven.</summary>
function Significant(const AText: string): TArray<TPascalToken>;
var
  Token: TPascalToken;
begin
  Result := nil;
  for Token in TPascalLexer.Tokenize(AText) do
  begin
    if not IsTrivia(Token) then
    begin
      Result := Result + [Token];
    end;
  end;
end;

/// <summary>Text von ATokens[AFirst] bis vor ATokens[AStop] aus AText (AStop = Length: bis zum Ende).</summary>
function Slice(const AText: string; const ATokens: TArray<TPascalToken>; AFirst, AStop: Integer): string;
var
  StopOffset: Integer;
begin
  if (AFirst < 0) or (AFirst >= AStop) or (AFirst > High(ATokens)) then
  begin
    Exit('');
  end;
  if AStop > High(ATokens) then
  begin
    StopOffset := ATokens[High(ATokens)].Offset + Length(ATokens[High(ATokens)].Text);
  end
  else
  begin
    StopOffset := ATokens[AStop].Offset;
  end;
  Result := Trim(Copy(AText, ATokens[AFirst].Offset + 1, StopOffset - ATokens[AFirst].Offset));
end;

function Opens(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol('(') or AToken.IsSymbol('[') or AToken.IsSymbol('<');
end;

function Closes(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(')') or AToken.IsSymbol(']') or AToken.IsSymbol('>');
end;

/// <summary>Index der schließenden Klammer zu ATokens[AOpen]; Length(ATokens) ohne.</summary>
function Matching(const ATokens: TArray<TPascalToken>; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AOpen;
  while Result <= High(ATokens) do
  begin
    if Opens(ATokens[Result]) then
    begin
      Inc(Depth);
    end
    else if Closes(ATokens[Result]) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit;
      end;
    end;
    Inc(Result);
  end;
end;

function IsModifier(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('const') or AToken.IsKeyword('var') or
    ((AToken.Kind = TPascalTokenKind.Identifier) and (SameText(AToken.Text, 'out') or
    SameText(AToken.Text, 'constref')));
end;

/// <summary>Erster Name einer Parametergruppe ab AStart vor AStop: Attribute wie [Ref] übersprungen, der
/// Modifizierer (const, var …) in AModifier.</summary>
function GroupNamesStart(const ATokens: TArray<TPascalToken>; AStart, AStop: Integer; out AModifier: string): Integer;
begin
  Result := AStart;
  while (Result < AStop) and ATokens[Result].IsSymbol('[') do
  begin
    Result := Matching(ATokens, Result) + 1;
  end;
  AModifier := '';
  if (Result < AStop) and IsModifier(ATokens[Result]) then
  begin
    AModifier := LowerCase(ATokens[Result].Text);
    Inc(Result);
  end;
end;

/// <summary>Typ hinter dem ":" bei AColon bis "=" oder AStop; '' ohne ":" (AColon = AStop).</summary>
function GroupType(const AText: string; const ATokens: TArray<TPascalToken>; AColon, AStop: Integer): string;
var
  mTypeStop: Integer;
begin
  Result := '';
  if AColon >= AStop then
  begin
    Exit;
  end;
  mTypeStop := AColon + 1;
  while (mTypeStop < AStop) and not ATokens[mTypeStop].IsSymbol('=') do
  begin
    Inc(mTypeStop);
  end;
  Result := Slice(AText, ATokens, AColon + 1, mTypeStop);
end;

/// <summary>Eine Gruppe "const A, B: T = Wert" zwischen AStart und AStop an AParams anhängen.</summary>
procedure AddParamGroup(const AText: string; const ATokens: TArray<TPascalToken>; AStart, AStop: Integer;
  var AParams: TArray<TMethodRefParam>);
var
  mIndex, mColon: Integer;
  mModifier, mTypeText: string;
  mParam: TMethodRefParam;
begin
  mIndex := GroupNamesStart(ATokens, AStart, AStop, mModifier);
  mColon := mIndex;
  while (mColon < AStop) and not ATokens[mColon].IsSymbol(':') do
  begin
    Inc(mColon);
  end;
  mTypeText := GroupType(AText, ATokens, mColon, AStop);
  while mIndex < mColon do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      mParam.Modifier := mModifier;
      mParam.Name := ATokens[mIndex].Text;
      mParam.TypeText := mTypeText;
      AParams := AParams + [mParam];
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Parameter zwischen ATokens[AOpen] = "(" und ATokens[AClose] = ")".</summary>
function ParseParams(const AText: string; const ATokens: TArray<TPascalToken>; AOpen, AClose: Integer): TArray<TMethodRefParam>;
var
  mIndex, mGroupStart, mDepth: Integer;
begin
  Result := nil;
  mGroupStart := AOpen + 1;
  mIndex := mGroupStart;
  mDepth := 0;
  while mIndex <= AClose do
  begin
    if (mIndex < AClose) and Opens(ATokens[mIndex]) then
    begin
      Inc(mDepth);
    end
    else if (mIndex < AClose) and Closes(ATokens[mIndex]) then
    begin
      Dec(mDepth);
    end
    else if (mIndex = AClose) or ((mDepth = 0) and ATokens[mIndex].IsSymbol(';')) then
    begin
      AddParamGroup(AText, ATokens, mGroupStart, mIndex, Result);
      mGroupStart := mIndex + 1;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Typparameter zwischen "&lt;" bei AOpen und "&gt;" bei AClose, ohne Constraints.</summary>
function TypeParamsIn(const ATokens: TArray<TPascalToken>; AOpen, AClose: Integer): TArray<string>;
var
  mIndex: Integer;
  mInConstraint: Boolean;
begin
  Result := nil;
  mInConstraint := False;
  for mIndex := AOpen + 1 to Min(AClose, High(ATokens)) do
  begin
    if ATokens[mIndex].IsSymbol(':') then
    begin
      mInConstraint := True;
    end
    // "T: class; U": nach ";" beginnt ein neuer Parameter, nach "," nur ohne Constraint.
    else if ATokens[mIndex].IsSymbol(';') then
    begin
      mInConstraint := False;
    end
    else if not mInConstraint and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) then
    begin
      Result := Result + [ATokens[mIndex].Text];
    end;
  end;
end;

/// <summary>Typparameter im Namen vor dem "="; AEqual dessen Stelle, -1 ohne.</summary>
function TypeParamsBefore(const ATokens: TArray<TPascalToken>; out AEqual: Integer): TArray<string>;
var
  mIndex, mClose: Integer;
begin
  Result := nil;
  AEqual := -1;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsSymbol('=') then
    begin
      AEqual := mIndex;
      Break;
    end;
    if ATokens[mIndex].IsSymbol('<') then
    begin
      mClose := Matching(ATokens, mIndex);
      Result := Result + TypeParamsIn(ATokens, mIndex, mClose);
      mIndex := Max(mIndex, mClose);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Ende der Deklaration ab AStart: ";" oder Textende.</summary>
function DeclarationEnd(const ATokens: TArray<TPascalToken>; AStart: Integer): Integer;
begin
  Result := AStart;
  while (Result <= High(ATokens)) and not ATokens[Result].IsSymbol(';') do
  begin
    Inc(Result);
  end;
end;

/// <summary>Steht bei AIndex "reference to"?</summary>
function IsReferenceTo(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (AIndex + 1 <= High(ATokens)) and (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    SameText(ATokens[AIndex].Text, 'reference') and ATokens[AIndex + 1].IsKeyword('to');
end;

/// <summary>Alias auf einen benannten Typ ab AIndex bis AStop; "procedure of object" und andere Typen zählen
/// nicht ('').</summary>
function AliasTarget(const ASignature: string; const ATokens: TArray<TPascalToken>; AIndex, AStop: Integer): string;
begin
  Result := '';
  if (AIndex <= High(ATokens)) and (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) then
  begin
    Result := Slice(ASignature, ATokens, AIndex, AStop);
  end;
end;

/// <summary>Ergebnistyp ": T" ab AIndex bis AStop in AResultType; False ohne.</summary>
function ParseResultType(const ASignature: string; const ATokens: TArray<TPascalToken>; AIndex, AStop: Integer;
  out AResultType: string): Boolean;
begin
  AResultType := '';
  Result := (AIndex < AStop) and ATokens[AIndex].IsSymbol(':');
  if Result then
  begin
    AResultType := Slice(ASignature, ATokens, AIndex + 1, AStop);
    Result := AResultType <> '';
  end;
end;

/// <summary>"procedure(…)" bzw. "function(…): T" ab AIndex (hinter "reference to") bis AStop in AMethodRef.
/// </summary>
function ParseMethodRef(const ASignature: string; const ATokens: TArray<TPascalToken>; AIndex, AStop: Integer;
  var AMethodRef: TMethodRef): Boolean;
var
  mClose: Integer;
begin
  Result := False;
  if AIndex > High(ATokens) then
  begin
    Exit;
  end;
  AMethodRef.IsFunction := ATokens[AIndex].IsKeyword('function');
  if not AMethodRef.IsFunction and not ATokens[AIndex].IsKeyword('procedure') then
  begin
    Exit;
  end;
  Inc(AIndex);
  if (AIndex < AStop) and ATokens[AIndex].IsSymbol('(') then
  begin
    mClose := Matching(ATokens, AIndex);
    if mClose > High(ATokens) then
    begin
      Exit;
    end;
    AMethodRef.Params := ParseParams(ASignature, ATokens, AIndex, mClose);
    AIndex := mClose + 1;
  end;
  Result := not AMethodRef.IsFunction or
    ParseResultType(ASignature, ATokens, AIndex, AStop, AMethodRef.ResultType);
end;

{ TCompletionAnonymous }

class function TCompletionAnonymous.Parse(const ASignature: string; out ATypeParams: TArray<string>;
  out AMethodRef: TMethodRef; out ATarget: string): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mEqual, mStop: Integer;
begin
  Result := False;
  AMethodRef := Default(TMethodRef);
  ATarget := '';
  mTokens := Significant(ASignature);
  // Name und Typparameter bis "=".
  ATypeParams := TypeParamsBefore(mTokens, mEqual);
  if mEqual < 0 then
  begin
    Exit;
  end;
  mStop := DeclarationEnd(mTokens, mEqual + 1);
  if IsReferenceTo(mTokens, mEqual + 1) then
  begin
    Result := ParseMethodRef(ASignature, mTokens, mEqual + 3, mStop, AMethodRef);
  end
  else
  begin
    ATarget := AliasTarget(ASignature, mTokens, mEqual + 1, mStop);
  end;
end;

class function TCompletionAnonymous.TypeArgs(const ATypeText: string; out ABase: string): TArray<string>;
var
  Open, Index, Depth, Start: Integer;
  Text: string;
begin
  Result := nil;
  Text := Trim(ATypeText);
  Open := Pos('<', Text);
  if (Open = 0) or not EndsStr('>', Text) then
  begin
    ABase := Text;
    Exit;
  end;
  ABase := Trim(Copy(Text, 1, Open - 1));
  Depth := 0;
  Start := Open + 1;
  for Index := Open + 1 to Length(Text) - 1 do
    case Text[Index] of
      '<', '(', '[':
        Inc(Depth);
      '>', ')', ']':
        Dec(Depth);
      ',':
        if Depth = 0 then
        begin
          Result := Result + [Trim(Copy(Text, Start, Index - Start))];
          Start := Index + 1;
        end;
    end;
  Result := Result + [Trim(Copy(Text, Start, Length(Text) - Start))];
end;

/// <summary>Wert des Typparameters AWord aus ANames/AValues in AValue; False, wenn AWord keiner ist.</summary>
function TypeParamValue(const AWord: string; const ANames, AValues: TArray<string>; out AValue: string): Boolean;
var
  mName: Integer;
begin
  for mName := 0 to Min(High(ANames), High(AValues)) do
  begin
    if SameText(AWord, ANames[mName]) then
    begin
      AValue := AValues[mName];
      Exit(True);
    end;
  end;
  AValue := AWord;
  Result := False;
end;

class function TCompletionAnonymous.Substitute(const AText: string; const ANames, AValues: TArray<string>): string;
var
  mIndex, mStart: Integer;
  mWord, mValue: string;
begin
  Result := '';
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if not CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_']) then
    begin
      Result := Result + AText[mIndex];
      Inc(mIndex);
      Continue;
    end;
    mStart := mIndex;
    while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    begin
      Inc(mIndex);
    end;
    mWord := Copy(AText, mStart, mIndex - mStart);
    // Nach einem Punkt ist es ein Teil eines qualifizierten Namens, kein Typparameter.
    if ((mStart = 1) or (AText[mStart - 1] <> '.')) and TypeParamValue(mWord, ANames, AValues, mValue) then
    begin
      Result := Result + mValue;
    end
    else
    begin
      Result := Result + mWord;
    end;
  end;
end;

/// <summary>ABase ohne System.SysUtils. bzw. SysUtils. davor.</summary>
function RtlName(const ABase: string): string;
begin
  Result := ABase;
  if StartsText('System.SysUtils.', Result) then
  begin
    Result := Copy(Result, Length('System.SysUtils.') + 1, MaxInt);
  end
  else if StartsText('SysUtils.', Result) then
  begin
    Result := Copy(Result, Length('SysUtils.') + 1, MaxInt);
  end;
end;

/// <summary>Zahl der Parameter von TProc bzw. TFunc mit AArgCount Typargumenten; -1 bei anderen Typen.</summary>
function RtlParamCount(const AName: string; AArgCount: Integer): Integer;
begin
  Result := -1;
  if SameText(AName, 'TProc') then
  begin
    Result := AArgCount;
  end
  else if SameText(AName, 'TFunc') then
  begin
    Result := AArgCount - 1;
  end;
end;

/// <summary>Parameterliste "(Arg1: T1; Arg2: T2)" und Typparameter "T1, T2" für ACount Parameter.</summary>
procedure RtlLists(ACount: Integer; out AParams, AGeneric: string);
var
  mIndex: Integer;
begin
  AParams := '';
  AGeneric := '';
  for mIndex := 1 to ACount do
  begin
    if mIndex > 1 then
    begin
      AParams := AParams + '; ';
      AGeneric := AGeneric + ', ';
    end;
    if ACount = 1 then
    begin
      AParams := AParams + 'Arg1: T';
      AGeneric := AGeneric + 'T';
    end
    else
    begin
      AParams := AParams + Format('Arg%d: T%d', [mIndex, mIndex]);
      AGeneric := AGeneric + Format('T%d', [mIndex]);
    end;
  end;
  if AParams <> '' then
  begin
    AParams := '(' + AParams + ')';
  end;
end;

class function TCompletionAnonymous.RtlDeclaration(const ABase: string; AArgCount: Integer): string;
var
  mName, mParams, mGeneric: string;
  mCount: Integer;
begin
  Result := '';
  mName := RtlName(ABase);
  if SameText(mName, 'TPredicate') then
  begin
    if AArgCount = 1 then
    begin
      Result := 'TPredicate<T> = reference to function(Arg1: T): Boolean;';
    end;
    Exit;
  end;
  mCount := RtlParamCount(mName, AArgCount);
  if (mCount < 0) or (mCount > 4) then
  begin
    Exit;
  end;
  RtlLists(mCount, mParams, mGeneric);
  if SameText(mName, 'TProc') then
  begin
    if mGeneric <> '' then
    begin
      mGeneric := '<' + mGeneric + '>';
    end;
    Result := 'TProc' + mGeneric + ' = reference to procedure' + mParams + ';';
  end
  else
  begin
    if mGeneric <> '' then
    begin
      mGeneric := mGeneric + ', ';
    end;
    Result := 'TFunc<' + mGeneric + 'TResult> = reference to function' + mParams + ': TResult;';
  end;
end;

/// <summary>Arg1, Arg2 … (Namen der generischen RTL-Typen).</summary>
function IsArgName(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := (Length(AName) > 3) and StartsStr('Arg', AName);
  if Result then
  begin
    for Index := 4 to Length(AName) do
    begin
      if not CharInSet(AName[Index], ['0'..'9']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Benannter Typ mit Präfix T oder I (TKunde, IFoo): daraus ein Name; sonst ''.</summary>
function TypeBase(const ATypeText: string): string;
var
  Bases: TArray<string>;
  Plain: string;
begin
  Result := '';
  Plain := Copy(ATypeText, LastDelimiter('.', ATypeText) + 1, MaxInt);
  if (Length(Plain) < 2) or not CharInSet(Plain[1], ['T', 'I']) or not CharInSet(Plain[2], ['A'..'Z']) then
  begin
    Exit;
  end;
  Bases := TNameSuggestions.Bases(ATypeText);
  if Length(Bases) > 0 then
  begin
    Result := Bases[0];
  end;
end;

/// <summary>Zahl der Parameter mit Namen Arg1, Arg2 … in AParams.</summary>
function ArgNameCount(const AParams: TArray<TMethodRefParam>): Integer;
var
  mParam: TMethodRefParam;
begin
  Result := 0;
  for mParam in AParams do
  begin
    if IsArgName(mParam.Name) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Die übrigen Parameternamen, die vergeben bleiben.</summary>
function OwnNames(const AParams: TArray<TMethodRefParam>): TArray<string>;
var
  mParam: TMethodRefParam;
begin
  Result := nil;
  for mParam in AParams do
  begin
    if not IsArgName(mParam.Name) then
    begin
      Result := Result + [mParam.Name];
    end;
  end;
end;

/// <summary>Name für den ANumber-ten von ACount Arg-Parametern: Value bei einem, sonst aus dem Typ bzw.
/// Value1, Value2 ….</summary>
function ArgBaseName(const AParam: TMethodRefParam; ACount, ANumber: Integer): string;
begin
  Result := 'Value';
  if ACount > 1 then
  begin
    Result := TypeBase(AParam.TypeText);
    if Result = '' then
    begin
      Result := 'Value' + IntToStr(ANumber);
    end;
  end;
end;

class function TCompletionAnonymous.Named(const AMethodRef: TMethodRef; const APrefix: string): TMethodRef;
var
  mIndex, mCount, mNumber: Integer;
  mTaken: TArray<string>;
  mName: string;
begin
  Result := AMethodRef;
  mCount := ArgNameCount(Result.Params);
  if mCount = 0 then
  begin
    Exit;
  end;
  mTaken := OwnNames(Result.Params);
  mNumber := 0;
  for mIndex := 0 to High(Result.Params) do
  begin
    if not IsArgName(Result.Params[mIndex].Name) then
    begin
      Continue;
    end;
    Inc(mNumber);
    mName := ArgBaseName(Result.Params[mIndex], mCount, mNumber);
    mName := TNameSuggestions.Unique(TNameSuggestions.Prefixed(mName, APrefix), mTaken);
    mTaken := mTaken + [mName];
    Result.Params[mIndex].Name := mName;
    if Result.Params[mIndex].Modifier = '' then
    begin
      Result.Params[mIndex].Modifier := 'const';
    end;
  end;
end;

class function TCompletionAnonymous.Header(const AMethodRef: TMethodRef): string;
var
  Param: TMethodRefParam;
  Parts: TArray<string>;
  Part: string;
begin
  if AMethodRef.IsFunction then
  begin
    Result := 'function';
  end
  else
  begin
    Result := 'procedure';
  end;
  Parts := nil;
  for Param in AMethodRef.Params do
  begin
    Part := Param.Name;
    if Param.Modifier <> '' then
    begin
      Part := Param.Modifier + ' ' + Part;
    end;
    if Param.TypeText <> '' then
    begin
      Part := Part + ': ' + Param.TypeText;
    end;
    Parts := Parts + [Part];
  end;
  if Length(Parts) > 0 then
  begin
    Result := Result + '(' + string.Join('; ', Parts) + ')';
  end;
  if AMethodRef.IsFunction then
  begin
    Result := Result + ': ' + AMethodRef.ResultType;
  end;
end;

/// <summary>Zeichen, die in einem LSP-Snippet eine Bedeutung haben, maskieren.</summary>
function EscapeSnippet(const AText: string): string;
begin
  Result := StringReplace(AText, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '$', '\$', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '\}', [rfReplaceAll]);
end;

class function TCompletionAnonymous.Snippet(const AMethodRef: TMethodRef): string;
var
  Body: string;
begin
  Body := '$0';
  if AMethodRef.IsFunction then
  begin
    Body := 'Result := $0';
  end;
  Result := EscapeSnippet(Header(AMethodRef)) + #10 + IndentUnit + 'begin' + #10 + IndentUnit + IndentUnit + Body +
    #10 + IndentUnit + 'end';
end;

class function TCompletionAnonymous.Plain(const AMethodRef: TMethodRef; const AIndent, ALineBreak: string): string;
var
  Body: string;
begin
  // Leere Rumpfzeile ohne Einrückung: sonst bliebe Leerraum am Zeilenende stehen.
  Body := '';
  if AMethodRef.IsFunction then
  begin
    Body := AIndent + IndentUnit + IndentUnit + 'Result := ';
  end;
  Result := Header(AMethodRef) + ALineBreak + AIndent + IndentUnit + 'begin' + ALineBreak + Body + ALineBreak +
    AIndent + IndentUnit + 'end';
end;

end.
