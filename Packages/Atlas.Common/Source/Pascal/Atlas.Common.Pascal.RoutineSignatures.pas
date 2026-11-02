unit Atlas.Common.Pascal.RoutineSignatures;

// Gemeinsame Normalisierung von Routinenköpfen für die Zuordnung von Deklaration
// und Rumpf (#1325). Regeln wie declared-not-implemented, implemented-not-declared,
// signature-mismatch und overload-directive-missing vergleichen Köpfe; dabei
// gelten diese Sonderformen als gleich bzw. als zugeordnet:
//   - "()" bedeutet keine Parameter: procedure TW.Execute(); passt zu
//     procedure Execute;
//   - Constraints stehen nur in der Deklaration: Reg<TI: IInterface; TC: class>
//     passt zu TA.Reg<TI, TC>; das ";" zwischen den Constraints beendet den Kopf
//     nicht
//   - Kurzform der Implementierung ohne Parameterliste und Ergebnistyp
//     (function Foo;) gehört zur einzigen Deklaration gleichen Namens
//   - Bei offenen Arrays zählt der Elementtyp (array of PTypeInfo ist nicht
//     array of TValue)
//   - class constructor und class destructor sind keine Überladungen der
//     Instanzmethoden gleichen Namens
//   - Eine Implementierung ist ein Rumpf aus begin…end oder asm…end oder eine
//     external-Angabe im implementation-Teil
//
// Die Textfunktionen (Head, ParameterKey, ResultKey) arbeiten auf dem Kopf als
// Text, die Baumfunktionen auf RoutineHeader- bzw. RoutineDecl-Knoten.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TRoutineSignatures = class
  public
    /// <summary>Kopf bis zum ersten ";" außerhalb von Klammern und Typparameterlisten, ohne doppelte
    /// Leerzeichen; ARest ist der Text dahinter (Direktiven).</summary>
    class function Head(const AText: string; out ARest: string): string; static;
    /// <summary>Parameterliste des Kopfs AHead ohne Leerzeichen und Standardwerte in Kleinbuchstaben, ein
    /// Parameter je Eintrag, z. B. "(consta:integer;b:string)"; '' ohne Klammern und bei "()".</summary>
    class function ParameterKey(const AHead: string): string; static;
    /// <summary>Ergebnistyp hinter der Parameterliste als Schlüsselteil ("|integer"); '' ohne.</summary>
    class function ResultKey(const AHead: string): string; static;
    /// <summary>Generische Teile des Qualifizierers vor dem Methodennamen AName im Kopf AHead, je Teil '1'
    /// (generisch) oder '0': "TDict&lt;K, V&gt;.TEnumerator.MoveNext" ergibt '10', "TProperty.Create" '0'; '' ohne
    /// Qualifizierer; '?' bei bedingten Direktiven im Qualifizierer (TList{$IFDEF X}&lt;T&gt;{$ENDIF}.Add), deren
    /// aktiver Zweig im Text nicht zu sehen ist. Delphi erlaubt neben TProperty einen generischen TProperty&lt;T&gt;;
    /// Rümpfe gehören nur zum Typ mit gleicher Maske.</summary>
    class function QualifierMask(const AHead, AName: string): string; static;
    /// <summary>Text AText ohne Leerraum in Kleinbuchstaben, z. B. für Typen ("arrayofptypeinfo").</summary>
    class function TypeKey(const AText: string): string; static;
    /// <summary>Kurzform eines Routinenkopfs ohne Parameterliste und ohne Ergebnistyp (function Foo;).</summary>
    class function IsShortForm(AHeader: TSyntaxNode): Boolean; static;
    /// <summary>class constructor bzw. class destructor; ATokens sind die Token des Baums.</summary>
    class function IsClassConstructor(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Boolean; static;
    /// <summary>Hat die Routine ARoutine (RoutineDecl) eine Implementierung: begin…end, asm…end oder external?
    /// </summary>
    class function HasImplementation(ARoutine: TSyntaxNode): Boolean; static;
    /// <summary>Typknoten des Parameters AParameter (TypeReference, ArrayType …); nil bei untypisierten
    /// Parametern.</summary>
    class function ParameterType(AParameter: TSyntaxNode): TSyntaxNode; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  cModifiers: array[0..3] of string = ('const', 'var', 'out', 'constref');

/// <summary>Teile von AText an ADelimiter außerhalb von Klammern und Zeichenketten.</summary>
function SplitTopLevel(const AText: string; ADelimiter: Char): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
  mQuoted: Boolean;
begin
  Result := nil;
  mDepth := 0;
  mQuoted := False;
  mStart := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if mQuoted then
    begin
      Continue;
    end
    else if CharInSet(AText[mIndex], ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(AText[mIndex], [')', ']', '>']) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and (AText[mIndex] = ADelimiter) then
    begin
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  Result := Result + [Copy(AText, mStart, MaxInt)];
end;

/// <summary>Ein Parameter je Eintrag, ohne Standardwert: Deklaration und Implementierung dürfen Parameter
/// verschieden gruppieren (const A: string; const B: string = '' gegen const A, B: string) und die
/// Implementierung lässt Standardwerte weg (#647).</summary>
/// <summary>Schneidet einen führenden Modifizierer (const, var, out …) von ANames ab und liefert ihn klein.</summary>
function TakeModifier(var ANames: string): string;
var
  mSpace: Integer;
  mFirst: string;
begin
  Result := '';
  mSpace := Pos(' ', ANames);
  if mSpace = 0 then
  begin
    Exit;
  end;
  mFirst := LowerCase(Copy(ANames, 1, mSpace - 1));
  if MatchText(mFirst, cModifiers) then
  begin
    Result := mFirst;
    ANames := Trim(Copy(ANames, mSpace + 1, MaxInt));
  end;
end;

/// <summary>Typ einer Parametergruppe ohne Standardwert; '' bei untypisierten Parametern.</summary>
function GroupTypeName(const AParts: TArray<string>): string;
begin
  Result := '';
  if Length(AParts) > 1 then
  begin
    Result := Trim(AParts[1]);
  end;
end;

/// <summary>Ein Parameter je Eintrag, ohne Standardwert: Deklaration und Implementierung dürfen Parameter
/// verschieden gruppieren (const A: string; const B: string = '' gegen const A, B: string) und die
/// Implementierung lässt Standardwerte weg (#647).</summary>
function NormalizedParameters(const AParameters: string): string;
var
  mGroup, mNames, mTypeName, mModifier, mName: string;
  mParts: TArray<string>;
begin
  Result := '';
  for mGroup in SplitTopLevel(AParameters, ';') do
  begin
    // Standardwert abschneiden: "AValue: Integer = 0".
    mParts := SplitTopLevel(mGroup, '=');
    mParts := SplitTopLevel(mParts[0], ':');
    mNames := Trim(mParts[0]);
    mTypeName := GroupTypeName(mParts);
    if mNames = '' then
    begin
      Continue;
    end;
    mModifier := TakeModifier(mNames);
    for mName in SplitTopLevel(mNames, ',') do
    begin
      if Result <> '' then
      begin
        Result := Result + ';';
      end;
      Result := Result + mModifier + ' ' + Trim(mName) + ':' + mTypeName;
    end;
  end;
  Result := LowerCase(StringReplace(Result, ' ', '', [rfReplaceAll]));
end;

/// <summary>Position von ANeedle (".name") in ALower, an der der Name endet (vor "(", "&lt;", ":",
/// Leerraum oder am Ende); 0, wenn es keine gibt.</summary>
function QualifiedNamePos(const ALower, ANeedle: string): Integer;
begin
  Result := Pos(ANeedle, ALower);
  while (Result > 0) and (Result + Length(ANeedle) <= Length(ALower)) and
    CharInSet(ALower[Result + Length(ANeedle)], ['a'..'z', '0'..'9', '_']) do
  begin
    Result := PosEx(ANeedle, ALower, Result + 1);
  end;
end;

function GenericDigit(AGeneric: Boolean): string;
begin
  Result := '0';
  if AGeneric then
  begin
    Result := '1';
  end;
end;

/// <summary>Maske der Qualifiziererteile in den ersten ACount Zeichen von AText: je Teil "1" für
/// generisch, sonst "0". "." trennt, Leerraum außerhalb von &lt;&gt; beginnt neu (Schlüsselwörter davor).</summary>
function QualifierPartsMask(const AText: string; ACount: Integer): string;
var
  mDepth, mPos: Integer;
  mGeneric: Boolean;
begin
  Result := '';
  mDepth := 0;
  mGeneric := False;
  for mPos := 1 to ACount do
  begin
    case AText[mPos] of
      '<':
        begin
          Inc(mDepth);
          mGeneric := True;
        end;
      '>':
        Dec(mDepth);
      '.':
        if mDepth = 0 then
        begin
          Result := Result + GenericDigit(mGeneric);
          mGeneric := False;
        end;
      ' ', #9:
        if mDepth = 0 then
        begin
          Result := '';
          mGeneric := False;
        end;
    end;
  end;
  Result := Result + GenericDigit(mGeneric);
end;

{ TRoutineSignatures }

class function TRoutineSignatures.Head(const AText: string; out ARest: string): string;
var
  mIndex, mDepth, mAngles: Integer;
begin
  mDepth := 0;
  mAngles := 0;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    case AText[mIndex] of
      '(', '[':
        Inc(mDepth);
      ')', ']':
        Dec(mDepth);
      // Außerhalb der Parameterliste steht "<" nur in Typparameterlisten (Name, Qualifizierer, Ergebnistyp):
      // Constraints wie <TI: IInterface; TC: class> enthalten ";".
      '<':
        if mDepth = 0 then
        begin
          Inc(mAngles);
        end;
      '>':
        if (mDepth = 0) and (mAngles > 0) then
        begin
          Dec(mAngles);
        end;
      ';':
        if (mDepth = 0) and (mAngles = 0) then
        begin
          Break;
        end;
    end;
    Inc(mIndex);
  end;
  Result := Trim(Copy(AText, 1, mIndex - 1));
  ARest := Copy(AText, mIndex + 1, MaxInt);
  while Pos('  ', Result) > 0 do
  begin
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  end;
end;

class function TRoutineSignatures.ParameterKey(const AHead: string): string;
var
  mOpen, mClose: Integer;
begin
  mOpen := Pos('(', AHead);
  mClose := LastDelimiter(')', AHead);
  if (mOpen = 0) or (mClose < mOpen) then
  begin
    Exit('');
  end;
  Result := NormalizedParameters(Copy(AHead, mOpen + 1, mClose - mOpen - 1));
  // "()" ist dasselbe wie keine Parameterliste.
  if Result <> '' then
  begin
    Result := '(' + Result + ')';
  end;
end;

class function TRoutineSignatures.ResultKey(const AHead: string): string;
var
  mIndex, mDepth: Integer;
begin
  mDepth := 0;
  for mIndex := 1 to Length(AHead) do
    case AHead[mIndex] of
      '(', '[', '<':
        Inc(mDepth);
      ')', ']', '>':
        Dec(mDepth);
      ':':
        if mDepth = 0 then
        begin
          Exit('|' + TypeKey(Copy(AHead, mIndex + 1, MaxInt)));
        end;
    end;
  Result := '';
end;

/// <summary>Kopf ohne Kommentare, ohne "&amp;" vor Namen und ohne Leerraum um ".": "TA.{%H-}&amp;Type",
/// "TA.&lt;Zeilenumbruch&gt;  Run" ergeben "TA.Type" bzw. "TA.Run".</summary>
function QualifierText(const AHead: string): string;
var
  mPos: Integer;
  mComment: Boolean;
begin
  Result := '';
  mComment := False;
  for mPos := 1 to Length(AHead) do
  begin
    if mComment then
    begin
      mComment := AHead[mPos] <> '}';
    end
    else if AHead[mPos] = '{' then
    begin
      mComment := True;
    end
    else if AHead[mPos] <> '&' then
    begin
      Result := Result + AHead[mPos];
    end;
  end;
  while Pos(' .', Result) > 0 do
  begin
    Result := StringReplace(Result, ' .', '.', [rfReplaceAll]);
  end;
  while Pos('. ', Result) > 0 do
  begin
    Result := StringReplace(Result, '. ', '.', [rfReplaceAll]);
  end;
end;

class function TRoutineSignatures.QualifierMask(const AHead, AName: string): string;
var
  mText, mNeedle: string;
  mIndex: Integer;
begin
  Result := '';
  // Bedingte Direktiven: Welcher Zweig aktiv ist, steht nicht im Text.
  if (Pos('{$', AHead) > 0) or (Pos('(*$', AHead) > 0) then
  begin
    Exit('?');
  end;
  mText := QualifierText(AHead);
  mNeedle := '.' + LowerCase(StringReplace(AName, '&', '', [rfReplaceAll]));
  mIndex := QualifiedNamePos(LowerCase(mText), mNeedle);
  if mIndex > 0 then
  begin
    Result := QualifierPartsMask(mText, mIndex - 1);
  end;
end;

class function TRoutineSignatures.TypeKey(const AText: string): string;
var
  mChar: Char;
begin
  Result := '';
  for mChar in AText do
  begin
    if not CharInSet(mChar, [' ', #9, #10, #13]) then
    begin
      Result := Result + mChar;
    end;
  end;
  Result := LowerCase(Result);
end;

class function TRoutineSignatures.IsShortForm(AHeader: TSyntaxNode): Boolean;
begin
  Result := (AHeader <> nil) and (AHeader.FindChild(TSyntaxKind.Parameters) = nil) and
    (AHeader.FindChild(TSyntaxKind.TypeReference) = nil);
end;

class function TRoutineSignatures.IsClassConstructor(const ATokens: TArray<TPascalToken>;
  AHeader: TSyntaxNode): Boolean;
var
  mIndex, mHigh, mMiddle: Integer;
begin
  Result := False;
  if AHeader = nil then
  begin
    Exit;
  end;
  // Erstes Token ab dem Kopf (binäre Suche, die Regeln fragen je Kopf).
  mIndex := 0;
  mHigh := Length(ATokens);
  while mIndex < mHigh do
  begin
    mMiddle := (mIndex + mHigh) div 2;
    if ATokens[mMiddle].Offset < AHeader.StartOffset then
    begin
      mIndex := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  if (mIndex > High(ATokens)) or not ATokens[mIndex].IsKeyword('class') then
  begin
    Exit;
  end;
  Inc(mIndex);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(mIndex);
  end;
  Result := (mIndex <= High(ATokens)) and (ATokens[mIndex].IsKeyword('constructor') or
    ATokens[mIndex].IsKeyword('destructor'));
end;

class function TRoutineSignatures.HasImplementation(ARoutine: TSyntaxNode): Boolean;
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  if (ARoutine = nil) or (ARoutine.Kind <> TSyntaxKind.RoutineDecl) then
  begin
    Exit;
  end;
  if (ARoutine.FindChild(TSyntaxKind.Block) <> nil) or (ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil) then
  begin
    Exit(True);
  end;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mHeader.ChildCount - 1 do
  begin
    if (mHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(mHeader[mIndex].Name, 'external') then
    begin
      Exit(True);
    end;
  end;
end;

class function TRoutineSignatures.ParameterType(AParameter: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  // Attribute stehen vor dem Typ, der Standardwert dahinter.
  for mIndex := 0 to AParameter.ChildCount - 1 do
  begin
    if AParameter[mIndex].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.ProcedureType,
      TSyntaxKind.SetType, TSyntaxKind.FileType, TSyntaxKind.PointerType, TSyntaxKind.SubrangeType] then
    begin
      Exit(AParameter[mIndex]);
    end;
  end;
  Result := nil;
end;

end.
