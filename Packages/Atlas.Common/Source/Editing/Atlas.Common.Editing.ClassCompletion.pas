unit Atlas.Common.Editing.ClassCompletion;

// Klassenvervollständigung (#42), wie Strg+Umschalt+C in der IDE: Zu Methoden,
// die im Typ deklariert, aber nicht implementiert sind, erzeugt eine
// Code-Aktion leere Rümpfe im implementation-Abschnitt.
//
// Steht der Cursor auf einer solchen Methode, gilt die Aktion nur ihr; sonst
// allen fehlenden Methoden des Typs unter dem Cursor. Abstrakte Methoden,
// Methoden von Interfaces und generische Typen werden übergangen. Die Rümpfe
// kommen hinter die letzte vorhandene Methode des Typs, sonst vor
// initialization, finalization bzw. das abschließende "end.".
//
// Unmatched liefert für die Prüfregeln aus #124 beide Richtungen: deklarierte
// Methoden ohne Rumpf und Rümpfe ohne Deklaration. AddDeclaration ergänzt eine
// fehlende Deklaration im private-Abschnitt des Typs.
//
// DeclaredMethods (#660) liefert dieselbe Zuordnung von der anderen Seite:
// je Typ der Datei die deklarierten Methoden in ihrer Reihenfolge, jede mit
// ihrem Rumpf, falls es ihn gibt; die Reihenfolge der Rümpfe im
// implementation-Teil richtet sich danach.
//
// Pairs (#996) ordnet Deklarationen und Rümpfe ohne Gegenstück einander zu,
// deren Köpfe abweichen: gleicher Typ und Name, bei Überladungen die
// nächstliegende Deklaration (Parameteranzahl, dann Typen, Namen und
// Modifizierer); ist sie nicht eindeutig, bleibt das Paar aus. PairFixes (#100)
// gleicht Rumpf und Deklaration in beide Richtungen an, auch die
// Aufrufkonvention. Standardwerte bleiben nur in der Deklaration.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CodeActions;

type
  /// <summary>Methode ohne Gegenstück (#124).</summary>
  TUnmatchedMethod = record
    /// <summary>Typ, ggf. mit umgebendem Typ (TAussen.TInnen).</summary>
    TypeName: string;
    Symbol: TIndexSymbol;
    /// <summary>True: deklariert, aber ohne Rumpf; False: Rumpf ohne Deklaration.</summary>
    Declared: Boolean;
    /// <summary>Kopf ohne ";", z. B. "procedure TFoo.Bar(A: Integer)" beim Rumpf.</summary>
    Header: string;
  end;

  /// <summary>Ein Parameter eines Methodenkopfs (#996).</summary>
  TShapeParameter = record
    /// <summary>const, var, out, constref oder '' (Kleinbuchstaben).</summary>
    Modifier: string;
    Name: string;
    /// <summary>Typ wie geschrieben; '' bei untypisierten Parametern.</summary>
    TypeName: string;
  end;

  /// <summary>Zerlegter Kopf einer Methode (#996).</summary>
  TSignatureShape = record
    /// <summary>procedure, function, constructor, destructor oder operator.</summary>
    Kind: string;
    Parameters: TArray<TShapeParameter>;
    /// <summary>Ergebnistyp wie geschrieben; '' ohne.</summary>
    ResultType: string;
    /// <summary>Aufrufkonvention in Kleinbuchstaben (stdcall, cdecl …); '' ohne Angabe.</summary>
    Convention: string;
    ConventionRange: TTextRange;
    /// <summary>Im Kopf steht bedingte Übersetzung ({$IFDEF} …); welche Parameter gelten, ist offen (#1324).
    /// </summary>
    Conditional: Boolean;
  end;

  /// <summary>Deklaration und Rumpf gleichen Namens, deren Köpfe voneinander abweichen (#996).</summary>
  TSignaturePair = record
    Declaration: TUnmatchedMethod;
    Body: TUnmatchedMethod;
    DeclarationShape: TSignatureShape;
    BodyShape: TSignatureShape;
  end;

  /// <summary>Deklarierte Methode eines Typs mit ihrem Rumpf (#660).</summary>
  TDeclaredMethod = record
    /// <summary>Typ, ggf. mit umgebendem Typ (TAussen.TInnen).</summary>
    TypeName: string;
    /// <summary>Stelle des Typs in der Datei, ab 0 in der Reihenfolge der Typen.</summary>
    TypeOrder: Integer;
    /// <summary>Stelle der Deklaration im Typ, ab 0.</summary>
    DeclarationOrder: Integer;
    Declaration: TIndexSymbol;
    HasBody: Boolean;
    Body: TIndexSymbol;
  end;

  TClassCompletion = class
  public
    /// <summary>Methoden ohne Gegenstück in Typen dieser Datei. Abstrakte, externe und forward-
    /// Methoden sowie generische Typen werden übergangen; Rümpfe zu Typen, die nicht in der
    /// Datei stehen, ebenfalls.</summary>
    class function Unmatched(ATree: TSyntaxTree; const AText: string): TArray<TUnmatchedMethod>; static;
    /// <summary>Je Typ der Datei (in ihrer Reihenfolge) die deklarierten Methoden in Deklarationsreihenfolge mit
    /// ihrem Rumpf (#660). Abstrakte, externe und forward-Methoden fehlen, generische Typen ebenso.</summary>
    class function DeclaredMethods(ATree: TSyntaxTree; const AText: string): TArray<TDeclaredMethod>; static;
    /// <summary>Fügt die Deklaration zu einem Rumpf ohne Deklaration im private-Abschnitt ein
    /// (legt ihn bei Bedarf an); False, wenn der Typ nicht passend aufgebaut ist.</summary>
    class function AddDeclaration(ATree: TSyntaxTree; const AText: string; const AMethod: TUnmatchedMethod;
      out AEdit: TTextEdit): Boolean; static;
    /// <summary>Aktion für fehlende Rümpfe an APosition; False, wenn nichts fehlt.</summary>
    class function MissingBodies(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      out AAction: TCodeAction): Boolean; static;
    /// <summary>Zerlegt den Kopf der Methode ASymbol; False, wenn er sich nicht lesen lässt.</summary>
    class function Shape(ATree: TSyntaxTree; const AText: string; const ASymbol: TIndexSymbol;
      out AShape: TSignatureShape): Boolean; static;
    /// <summary>Paare aus Unmatched: Deklaration und Rumpf desselben Typs und Namens, bei Überladungen nur
    /// wechselseitig eindeutig nächstliegende (#996).</summary>
    class function Pairs(ATree: TSyntaxTree; const AText: string): TArray<TSignaturePair>; static;
    /// <summary>"Implementierung an die Deklaration angleichen" und "Deklaration an die Implementierung
    /// angleichen" (#100) für APair. Liefert Code-Aktionen statt TRuleFix, damit Editing ohne Rules
    /// auskommt (A-11); die Regel signature-mismatch macht daraus Korrekturen.</summary>
    class function PairFixes(ATree: TSyntaxTree; const AText: string; const APair: TSignaturePair;
      out AFixes: TArray<TCodeAction>): Boolean; static;
    /// <summary>Fügt den Rumpf ABody (ohne Zeilenumbruch am Ende) für einen Typ dieser Datei ein: hinter die
    /// letzte vorhandene Methode des Typs, sonst vor initialization, finalization bzw. "end." (#443).</summary>
    class function BodyEdit(ATree: TSyntaxTree; const AText, ATypeName, ABody: string; out AEdit: TTextEdit): Boolean;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Text.Lines;

const
  // Bedingte Übersetzung im Kopf einer Methode (#1324).
  cConditionalDirectives: array[0..7] of string = ('IF', 'IFDEF', 'IFNDEF', 'IFOPT', 'ELSE', 'ELSEIF', 'ENDIF',
    'IFEND');
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.HelperType];
  MethodKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];

function ContainsLine(const ARange: TTextRange; ALine: Integer): Boolean;
begin
  Result := (ALine >= ARange.StartPos.Line) and (ALine <= ARange.EndPos.Line);
end;

/// <summary>Text von ARange bis zum Ende seiner letzten Zeile, Zeilen mit Leerzeichen verbunden.</summary>
function RangeText(const ALines: TArray<string>; const ARange: TTextRange): string;
var
  Line: Integer;
begin
  Result := '';
  for Line := ARange.StartPos.Line to ARange.EndPos.Line do
  begin
    if (Line < 0) or (Line > High(ALines)) then
      Break;
    if Line = ARange.StartPos.Line then
      Result := Copy(ALines[Line], ARange.StartPos.Character + 1, MaxInt)
    else
      Result := Result + ' ' + Trim(ALines[Line]);
  end;
end;

/// <summary>Kopf bis zum ersten ";" außerhalb von Klammern, ohne doppelte Leerzeichen.</summary>
function Signature(const AText: string; out ARest: string): string;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  Index := 1;
  while Index <= Length(AText) do
  begin
    case AText[Index] of
      '(', '[': Inc(Depth);
      ')', ']': Dec(Depth);
      ';':
        if Depth = 0 then
          Break;
    end;
    Inc(Index);
  end;
  Result := Trim(Copy(AText, 1, Index - 1));
  ARest := Copy(AText, Index + 1, MaxInt);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
end;

/// <summary>Teile von AText an ADelimiter außerhalb von Klammern und Zeichenketten.</summary>
function SplitTopLevel(const AText: string; ADelimiter: Char): TArray<string>;
var
  Index, Depth, Start: Integer;
  Quoted: Boolean;
begin
  Result := nil;
  Depth := 0;
  Quoted := False;
  Start := 1;
  for Index := 1 to Length(AText) do
    if AText[Index] = '''' then
      Quoted := not Quoted
    else if Quoted then
      Continue
    else if CharInSet(AText[Index], ['(', '[', '<']) then
      Inc(Depth)
    else if CharInSet(AText[Index], [')', ']', '>']) then
      Dec(Depth)
    else if (Depth = 0) and (AText[Index] = ADelimiter) then
    begin
      Result := Result + [Copy(AText, Start, Index - Start)];
      Start := Index + 1;
    end;
  Result := Result + [Copy(AText, Start, MaxInt)];
end;

/// <summary>Ein Parameter je Eintrag, ohne Standardwert: Deklaration und Implementierung dürfen
/// Parameter verschieden gruppieren (const A: string; const B: string = '' gegen const A, B: string)
/// und die Implementierung lässt Standardwerte weg (#647).</summary>
function NormalizedParameters(const AParameters: string): string;
var
  Group, Names, TypeName, Modifier, Name, First: string;
  Parts, NameList: TArray<string>;
  Space: Integer;
begin
  Result := '';
  for Group in SplitTopLevel(AParameters, ';') do
  begin
    // Standardwert abschneiden: "AValue: Integer = 0".
    Parts := SplitTopLevel(Group, '=');
    Parts := SplitTopLevel(Parts[0], ':');
    Names := Trim(Parts[0]);
    if Length(Parts) > 1 then
      TypeName := Trim(Parts[1])
    else
      TypeName := '';
    if Names = '' then
      Continue;
    Modifier := '';
    Space := Pos(' ', Names);
    if Space > 0 then
    begin
      First := LowerCase(Copy(Names, 1, Space - 1));
      if MatchText(First, ['const', 'var', 'out', 'constref']) then
      begin
        Modifier := First;
        Names := Trim(Copy(Names, Space + 1, MaxInt));
      end;
    end;
    NameList := SplitTopLevel(Names, ',');
    for Name in NameList do
    begin
      if Result <> '' then
        Result := Result + ';';
      Result := Result + Modifier + ' ' + Trim(Name) + ':' + TypeName;
    end;
  end;
  Result := LowerCase(StringReplace(Result, ' ', '', [rfReplaceAll]));
end;

/// <summary>Parameterliste ohne Leerzeichen und Standardwerte in Kleinbuchstaben, ein Parameter je
/// Eintrag; '' ohne Klammern.</summary>
function ParameterKey(const ASignature: string): string;
var
  Open, Close: Integer;
begin
  Open := Pos('(', ASignature);
  Close := LastDelimiter(')', ASignature);
  if (Open = 0) or (Close < Open) then
    Exit('');
  Result := '(' + NormalizedParameters(Copy(ASignature, Open + 1, Close - Open - 1)) + ')';
end;

/// <summary>Ergebnistyp hinter der Parameterliste als Schlüsselteil ("|integer"); '' ohne. Rümpfe dürfen ihn
/// weglassen, dann passt der Rumpf über den Namen allein.</summary>
function ResultKey(const ASignature: string): string;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  for Index := 1 to Length(ASignature) do
    case ASignature[Index] of
      '(', '[', '<':
        Inc(Depth);
      ')', ']', '>':
        Dec(Depth);
      ':':
        if Depth = 0 then
          Exit('|' + LowerCase(StringReplace(Trim(Copy(ASignature, Index + 1, MaxInt)), ' ', '', [rfReplaceAll])));
    end;
  Result := '';
end;

function HasWord(const AText, AWord: string): Boolean;
var
  Index: Integer;
  Lower: string;
begin
  Lower := LowerCase(AText);
  Index := Pos(AWord, Lower);
  while Index > 0 do
  begin
    if ((Index = 1) or not CharInSet(Lower[Index - 1], ['a'..'z', '0'..'9', '_'])) and
      ((Index + Length(AWord) > Length(Lower)) or
      not CharInSet(Lower[Index + Length(AWord)], ['a'..'z', '0'..'9', '_'])) then
      Exit(True);
    Index := PosEx(AWord, Lower, Index + 1);
  end;
  Result := False;
end;

/// <summary>Kopf der Implementierung: Typname vor den Methodennamen.</summary>
function QualifiedHeader(const ASignature, AMethodName, ATypeName: string): string;
var
  Index: Integer;
begin
  // Der Name folgt auf procedure/function/constructor/destructor/operator.
  Index := Pos(LowerCase(' ' + AMethodName), LowerCase(ASignature));
  if Index = 0 then
    Exit('');
  Result := Copy(ASignature, 1, Index) + ATypeName + '.' + Copy(ASignature, Index + 1, MaxInt) + ';';
end;

/// <summary>Zeile vor initialization, finalization oder dem abschließenden "end."; -1 ohne implementation.</summary>
function ImplementationEndLine(ATree: TSyntaxTree): Integer;
var
  Tokens: TArray<TPascalToken>;
  Index, Next: Integer;
  InImplementation: Boolean;
begin
  Result := -1;
  InImplementation := False;
  Tokens := ATree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind <> TPascalTokenKind.Keyword then
      Continue;
    if Tokens[Index].IsKeyword('implementation') then
      InImplementation := True
    else if InImplementation and (Tokens[Index].IsKeyword('initialization') or
      Tokens[Index].IsKeyword('finalization')) then
      Exit(Tokens[Index].StartPos.Line)
    else if InImplementation and Tokens[Index].IsKeyword('end') then
    begin
      Next := Index + 1;
      while (Next <= High(Tokens)) and (Tokens[Next].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Inc(Next);
      if (Next <= High(Tokens)) and Tokens[Next].IsSymbol('.') then
        Result := Tokens[Index].StartPos.Line;
    end;
  end;
end;

function TypeNameOf(const ASymbol: TIndexSymbol): string;
begin
  if ASymbol.Container <> '' then
    Result := ASymbol.Container + '.' + ASymbol.Name
  else
    Result := ASymbol.Name;
end;

/// <summary>Bereich und Text hinter dem Methodennamen bis vor das erste ";" außerhalb von Klammern,
/// z. B. "(const A: Integer): Boolean".</summary>
function SignatureTail(ATree: TSyntaxTree; const AText: string; const ASymbol: TIndexSymbol;
  out ARange: TTextRange; out ATail: string; out AName, ALast: Integer): Boolean; overload;
var
  Tokens: TArray<TPascalToken>;
  Index, Name, Last, Depth, StartOffset: Integer;
begin
  Result := False;
  AName := -1;
  ALast := -1;
  Tokens := ATree.Tokens;
  Name := -1;
  for Index := 0 to High(Tokens) do
    if Tokens[Index].EndPos = ASymbol.SelectionRange.EndPos then
    begin
      Name := Index;
      Break;
    end;
  if Name < 0 then
    Exit;
  Depth := 0;
  Last := -1;
  for Index := Name + 1 to High(Tokens) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Comment then
      Continue;
    if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if (Depth = 0) and Tokens[Index].IsSymbol(';') then
      Break;
    Last := Index;
  end;
  if Last < 0 then
    Exit;
  StartOffset := Tokens[Name].Offset + Length(Tokens[Name].Text);
  ARange := TTextRange.Create(Tokens[Name].EndPos, Tokens[Last].EndPos);
  ATail := Copy(AText, StartOffset + 1, Tokens[Last].Offset + Length(Tokens[Last].Text) - StartOffset);
  AName := Name;
  ALast := Last;
  Result := True;
end;

function SignatureTail(ATree: TSyntaxTree; const AText: string; const ASymbol: TIndexSymbol;
  out ARange: TTextRange; out ATail: string): Boolean; overload;
var
  mName, mLast: Integer;
begin
  Result := SignatureTail(ATree, AText, ASymbol, ARange, ATail, mName, mLast);
end;

/// <summary>Text der Token AFirst..ALast ohne Kommentare und Direktiven (#1324): {Do not Localize}, {%H-} oder
/// //FI W521 gehören nicht zum Kopf. Leerraum oder ein weggelassenes Token zwischen zwei Token wird ein Leerzeichen.
/// AConditional: Darunter steht {$IF…}, {$ELSE…} oder {$ENDIF}; welche Teile gelten, hängt dann von der
/// Übersetzung ab.</summary>
function CleanTail(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; out AConditional: Boolean): string;
var
  mIndex, mEnd: Integer;
  mGap: Boolean;
begin
  Result := '';
  AConditional := False;
  mGap := False;
  mEnd := -1;
  for mIndex := AFirst to ALast do
  begin
    if ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      if (ATokens[mIndex].Kind = TPascalTokenKind.Directive) and
        MatchText(TPascalLexer.DirectiveName(ATokens[mIndex].Text), cConditionalDirectives) then
        AConditional := True;
      mGap := True;
      Continue;
    end;
    if (Result <> '') and (mGap or (ATokens[mIndex].Offset > mEnd)) then
      Result := Result + ' ';
    Result := Result + ATokens[mIndex].Text;
    mEnd := ATokens[mIndex].Offset + Length(ATokens[mIndex].Text);
    mGap := False;
  end;
end;

/// <summary>AText ohne Attribute in eckigen Klammern: "const [ref] A" → "const A" (#1324).</summary>
function WithoutAttributes(const AText: string): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  for mIndex := 1 to Length(AText) do
    if AText[mIndex] = '[' then
      Inc(mDepth)
    else if AText[mIndex] = ']' then
    begin
      if mDepth > 0 then
        Dec(mDepth);
      Result := Result + ' ';
    end
    else if mDepth = 0 then
      Result := Result + AText[mIndex];
  Result := Trim(Result);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
end;

/// <summary>Zerlegt "(A: Integer = 1; const B: string): Boolean" in Parametergruppen und den Rest.</summary>
function SplitParameters(const ATail: string; out AGroups: TArray<string>; out AAfter: string): Boolean;
var
  Index, Depth, Start: Integer;
  Quoted: Boolean;
  Tail: string;
begin
  AGroups := nil;
  Tail := Trim(ATail);
  AAfter := Tail;
  Result := (Tail <> '') and (Tail[1] = '(');
  if not Result then
    Exit;
  Depth := 0;
  Quoted := False;
  Start := 2;
  for Index := 1 to Length(Tail) do
  begin
    if Tail[Index] = '''' then
      Quoted := not Quoted;
    if Quoted then
      Continue;
    case Tail[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            if Trim(Copy(Tail, Start, Index - Start)) <> '' then
              AGroups := AGroups + [Trim(Copy(Tail, Start, Index - Start))];
            AAfter := Copy(Tail, Index + 1, MaxInt);
            Exit;
          end;
        end;
      ';':
        if Depth = 1 then
        begin
          AGroups := AGroups + [Trim(Copy(Tail, Start, Index - Start))];
          Start := Index + 1;
        end;
    end;
  end;
  Result := False;
end;

/// <summary>Position des "=" eines Standardwerts in AGroup, 0 ohne.</summary>
function DefaultPos(const AGroup: string): Integer;
var
  Index, Depth: Integer;
  Quoted: Boolean;
begin
  Depth := 0;
  Quoted := False;
  for Index := 1 to Length(AGroup) do
  begin
    if AGroup[Index] = '''' then
      Quoted := not Quoted;
    if Quoted then
      Continue;
    case AGroup[Index] of
      '(', '[', '<':
        Inc(Depth);
      ')', ']', '>':
        Dec(Depth);
      '=':
        if Depth = 0 then
          Exit(Index);
    end;
  end;
  Result := 0;
end;

/// <summary>Namen einer Parametergruppe in Kleinbuchstaben ohne const/var/out, z. B. "a,b".</summary>
function GroupNames(const AGroup: string): string;
const
  Modifiers: array[0..3] of string = ('constref', 'const', 'var', 'out');
var
  Colon, Index: Integer;
  Names: string;
begin
  Colon := Pos(':', AGroup);
  if Colon = 0 then
    Names := AGroup
  else
    Names := Copy(AGroup, 1, Colon - 1);
  Names := LowerCase(Trim(Names));
  // Attribute wie [ref] stehen vor den Namen, auch hinter dem Modifizierer: const [ref] A (#1324).
  Names := WithoutAttributes(Names);
  for Index := 0 to High(Modifiers) do
    if Pos(Modifiers[Index] + ' ', Names) = 1 then
    begin
      Names := Trim(Copy(Names, Length(Modifiers[Index]) + 1, MaxInt));
      Break;
    end;
  Result := StringReplace(StringReplace(Names, ' ', '', [rfReplaceAll]), #9, '', [rfReplaceAll]);
end;

function JoinGroups(const AGroups: TArray<string>; const AAfter: string): string;
var
  Index: Integer;
begin
  Result := '(';
  for Index := 0 to High(AGroups) do
  begin
    if Index > 0 then
      Result := Result + '; ';
    Result := Result + AGroups[Index];
  end;
  Result := Result + ')' + AAfter;
end;

/// <summary>Kopf der Deklaration für den Rumpf: Standardwerte entfallen.</summary>
function WithoutDefaults(const ATail: string): string;
var
  Groups: TArray<string>;
  After: string;
  Index, Equals: Integer;
begin
  if not SplitParameters(ATail, Groups, After) then
    Exit(TrimLeft(ATail));
  for Index := 0 to High(Groups) do
  begin
    Equals := DefaultPos(Groups[Index]);
    if Equals > 0 then
      Groups[Index] := TrimRight(Copy(Groups[Index], 1, Equals - 1));
  end;
  Result := JoinGroups(Groups, After);
end;

/// <summary>Kopf des Rumpfs für die Deklaration; Standardwerte der alten Deklaration bleiben
/// bei gleichnamigen Parametern erhalten.</summary>
function WithDefaultsOf(const ABodyTail, ADeclTail: string): string;
var
  Groups, Old: TArray<string>;
  After, OldAfter: string;
  Index, Inner, Equals: Integer;
begin
  if not SplitParameters(ABodyTail, Groups, After) then
    Exit(TrimLeft(ABodyTail));
  if SplitParameters(ADeclTail, Old, OldAfter) then
    for Index := 0 to High(Groups) do
      for Inner := 0 to High(Old) do
      begin
        Equals := DefaultPos(Old[Inner]);
        if (Equals > 0) and (DefaultPos(Groups[Index]) = 0) and
          (GroupNames(Groups[Index]) = GroupNames(Copy(Old[Inner], 1, Equals - 1))) then
          Groups[Index] := Groups[Index] + ' ' + Trim(Copy(Old[Inner], Equals, MaxInt));
      end;
  Result := JoinGroups(Groups, After);
end;

const
  Conventions: array[0..5] of string = ('register', 'pascal', 'cdecl', 'stdcall', 'safecall', 'winapi');
  Directives: array[0..20] of string = ('overload', 'inline', 'static', 'virtual', 'dynamic', 'override',
    'abstract', 'reintroduce', 'final', 'message', 'deprecated', 'platform', 'experimental', 'library', 'assembler',
    'varargs', 'external', 'forward', 'unsafe', 'dispid', 'export');
  Modifiers: array[0..3] of string = ('constref', 'const', 'var', 'out');
  Kinds: array[0..4] of string = ('constructor', 'destructor', 'operator', 'function', 'procedure');

/// <summary>Parameter einer Gruppe "const A, B: string = ''" einzeln.</summary>
function GroupParameters(const AGroup: string): TArray<TShapeParameter>;
var
  Group, Names, TypeName, Modifier, Name: string;
  Equals, Colon, Space: Integer;
  Parameter: TShapeParameter;
begin
  Result := nil;
  Group := AGroup;
  Equals := DefaultPos(Group);
  if Equals > 0 then
    Group := Copy(Group, 1, Equals - 1);
  Colon := Pos(':', Group);
  if Colon > 0 then
  begin
    Names := Trim(Copy(Group, 1, Colon - 1));
    TypeName := Trim(Copy(Group, Colon + 1, MaxInt));
  end
  else
  begin
    Names := Trim(Group);
    TypeName := '';
  end;
  // Attribute wie [ref] stehen vor den Namen, auch hinter dem Modifizierer: const [ref] A (#1324).
  Names := WithoutAttributes(Names);
  Modifier := '';
  Space := Pos(' ', Names);
  if (Space > 0) and MatchText(Copy(Names, 1, Space - 1), Modifiers) then
  begin
    Modifier := LowerCase(Copy(Names, 1, Space - 1));
    Names := Trim(Copy(Names, Space + 1, MaxInt));
  end;
  while Pos('  ', TypeName) > 0 do
    TypeName := StringReplace(TypeName, '  ', ' ', [rfReplaceAll]);
  for Name in SplitTopLevel(Names, ',') do
  begin
    Parameter.Modifier := Modifier;
    Parameter.Name := Trim(Name);
    Parameter.TypeName := TypeName;
    Result := Result + [Parameter];
  end;
end;

function SameTypeName(const A, B: string): Boolean;
begin
  Result := SameText(StringReplace(A, ' ', '', [rfReplaceAll]), StringReplace(B, ' ', '', [rfReplaceAll]));
end;

/// <summary>Nähe zweier Köpfe für die Zuordnung bei Überladungen; höher = ähnlicher.</summary>
function Closeness(const ADeclaration, ABody: TSignatureShape): Integer;
var
  Index: Integer;
begin
  Result := 0;
  if Length(ADeclaration.Parameters) = Length(ABody.Parameters) then
    Inc(Result, 100);
  for Index := 0 to Min(High(ADeclaration.Parameters), High(ABody.Parameters)) do
  begin
    if SameTypeName(ADeclaration.Parameters[Index].TypeName, ABody.Parameters[Index].TypeName) then
      Inc(Result, 10);
    if SameText(ADeclaration.Parameters[Index].Name, ABody.Parameters[Index].Name) then
      Inc(Result, 5);
    if ADeclaration.Parameters[Index].Modifier = ABody.Parameters[Index].Modifier then
      Inc(Result, 1);
  end;
  if SameTypeName(ADeclaration.ResultType, ABody.ResultType) then
    Inc(Result, 3);
  if ADeclaration.Kind = ABody.Kind then
    Inc(Result, 3);
end;

/// <summary>Aufrufkonvention aus den Direktiven hinter dem Kopf ("overload; stdcall; …"); '' ohne.</summary>
function ConventionOfRest(const ARest: string): string;
var
  Part, Word: string;
  Space: Integer;
begin
  Result := '';
  for Part in SplitTopLevel(ARest, ';') do
  begin
    Word := LowerCase(Trim(Part));
    Space := Pos(' ', Word);
    if Space > 0 then
      Word := Copy(Word, 1, Space - 1);
    if MatchText(Word, Conventions) then
      Exit(Word);
    if not MatchText(Word, Directives) then
      Exit;
  end;
end;

/// <summary>Weicht die ausdrücklich angegebene Konvention des Rumpfs von der Deklaration ab?</summary>
function ConventionDiffers(const ABody, ADeclaration: string): Boolean;
var
  Declaration: string;
begin
  Declaration := ADeclaration;
  if Declaration = '' then
    Declaration := 'register';
  Result := (ABody <> '') and (ABody <> Declaration);
end;

{ TClassCompletion }

class function TClassCompletion.Shape(ATree: TSyntaxTree; const AText: string; const ASymbol: TIndexSymbol;
  out AShape: TSignatureShape): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Range: TTextRange;
  Tail, After, Group, Header, Rest, Word: string;
  Groups: TArray<string>;
  Index, Depth: Integer;
  mName, mLast: Integer;
begin
  AShape := Default(TSignatureShape);
  Result := SignatureTail(ATree, AText, ASymbol, Range, Tail, mName, mLast);
  if not Result then
    Exit;
  // Verglichen wird der Kopf ohne Kommentare und Direktiven (#1324).
  Tail := CleanTail(ATree.Tokens, mName + 1, mLast, AShape.Conditional);
  Header := Signature(RangeText(TTextLines.SplitLines(AText), ASymbol.Range), Rest);
  for Word in Kinds do
    if HasWord(Header, Word) then
    begin
      AShape.Kind := Word;
      Break;
    end;
  if SplitParameters(Tail, Groups, After) then
    for Group in Groups do
      AShape.Parameters := AShape.Parameters + GroupParameters(Group);
  After := Trim(After);
  if StartsStr(':', After) then
    AShape.ResultType := Trim(Copy(After, 2, MaxInt));
  // Direktiven hinter dem Kopf: "; overload; stdcall;"
  Tokens := ATree.Tokens;
  Index := 0;
  while (Index <= High(Tokens)) and not (Tokens[Index].EndPos = Range.EndPos) do
    Inc(Index);
  Inc(Index);
  while Index <= High(Tokens) do
  begin
    while (Index <= High(Tokens)) and (Tokens[Index].Kind = TPascalTokenKind.Comment) do
      Inc(Index);
    if (Index > High(Tokens)) or not Tokens[Index].IsSymbol(';') then
      Break;
    Inc(Index);
    while (Index <= High(Tokens)) and (Tokens[Index].Kind = TPascalTokenKind.Comment) do
      Inc(Index);
    if Index > High(Tokens) then
      Break;
    if MatchText(Tokens[Index].Text, Conventions) then
    begin
      AShape.Convention := LowerCase(Tokens[Index].Text);
      AShape.ConventionRange := TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos);
    end
    else if not MatchText(Tokens[Index].Text, Directives) then
      Break;
    // Argumente wie message WM_PAINT oder deprecated 'Grund' überspringen.
    Depth := 0;
    while (Index < High(Tokens)) and not ((Depth = 0) and Tokens[Index + 1].IsSymbol(';')) do
    begin
      if Tokens[Index].IsSymbol('(') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(')') then
        Dec(Depth);
      Inc(Index);
    end;
    Inc(Index);
  end;
end;

class function TClassCompletion.Pairs(ATree: TSyntaxTree; const AText: string): TArray<TSignaturePair>;
var
  Items: TArray<TUnmatchedMethod>;
  Shapes: TArray<TSignatureShape>;
  Valid: TArray<Boolean>;
  Index, Other: Integer;
  Pair: TSignaturePair;

  function Candidate(A, B: Integer): Boolean;
  begin
    Result := (A <> B) and Valid[A] and Valid[B] and (Items[A].Declared <> Items[B].Declared) and
      SameText(Items[A].TypeName, Items[B].TypeName) and SameText(Items[A].Symbol.Name, Items[B].Symbol.Name);
  end;

  function Score(A, B: Integer): Integer;
  begin
    if Items[A].Declared then
      Result := Closeness(Shapes[A], Shapes[B])
    else
      Result := Closeness(Shapes[B], Shapes[A]);
  end;

  /// <summary>Eindeutig nächstliegender Partner von A; -1 ohne oder bei Gleichstand.</summary>
  function Best(A: Integer): Integer;
  var
    B, Top, Count: Integer;
  begin
    Result := -1;
    Top := -1;
    Count := 0;
    for B := 0 to High(Items) do
      if Candidate(A, B) then
        if Score(A, B) > Top then
        begin
          Top := Score(A, B);
          Result := B;
          Count := 1;
        end
        else if Score(A, B) = Top then
          Inc(Count);
    if Count <> 1 then
      Result := -1;
  end;

begin
  Result := nil;
  Items := Unmatched(ATree, AText);
  SetLength(Shapes, Length(Items));
  SetLength(Valid, Length(Items));
  for Index := 0 to High(Items) do
    Valid[Index] := Shape(ATree, AText, Items[Index].Symbol, Shapes[Index]);
  for Index := 0 to High(Items) do
  begin
    if Items[Index].Declared then
      Continue;
    Other := Best(Index);
    if (Other < 0) or (Best(Other) <> Index) then
      Continue;
    Pair.Declaration := Items[Other];
    Pair.Body := Items[Index];
    Pair.DeclarationShape := Shapes[Other];
    Pair.BodyShape := Shapes[Index];
    Result := Result + [Pair];
  end;
end;

class function TClassCompletion.PairFixes(ATree: TSyntaxTree; const AText: string; const APair: TSignaturePair;
  out AFixes: TArray<TCodeAction>): Boolean;
var
  DeclRange, BodyRange: TTextRange;
  DeclTail, BodyTail, DeclTailText, Convention: string;
  Fix: TCodeAction;
  Name: string;
begin
  AFixes := nil;
  Result := SignatureTail(ATree, AText, APair.Declaration.Symbol, DeclRange, DeclTail) and
    SignatureTail(ATree, AText, APair.Body.Symbol, BodyRange, BodyTail);
  if not Result then
    Exit;
  Name := APair.Body.Symbol.Name;
  Fix := Default(TCodeAction);
  Fix.Kind := QuickFixKind;
  Fix.Title := Format('Implementierung von %s an die Deklaration angleichen', [Name]);
  Fix.Edits := [TTextEdit.Create(BodyRange, WithoutDefaults(DeclTail))];
  // Eine abweichende Konvention im Rumpf übernimmt die der Deklaration (ohne Angabe register).
  if (APair.BodyShape.Convention <> '') and (APair.BodyShape.Convention <> APair.DeclarationShape.Convention) then
  begin
    Convention := APair.DeclarationShape.Convention;
    if Convention = '' then
      Convention := 'register';
    Fix.Edits := Fix.Edits + [TTextEdit.Create(APair.BodyShape.ConventionRange, Convention)];
  end;
  AFixes := AFixes + [Fix];
  Fix.Title := Format('Deklaration von %s an die Implementierung angleichen', [Name]);
  DeclTailText := WithDefaultsOf(BodyTail, DeclTail);
  Fix.Edits := nil;
  if (APair.BodyShape.Convention <> '') and (APair.BodyShape.Convention <> APair.DeclarationShape.Convention) then
  begin
    if APair.DeclarationShape.Convention <> '' then
      Fix.Edits := [TTextEdit.Create(APair.DeclarationShape.ConventionRange, APair.BodyShape.Convention)]
    else
      DeclTailText := DeclTailText + '; ' + APair.BodyShape.Convention;
  end;
  Fix.Edits := [TTextEdit.Create(DeclRange, DeclTailText)] + Fix.Edits;
  AFixes := AFixes + [Fix];
end;


type
  /// <summary>Zuordnung von Deklarationen und Rümpfen eines Typs (Unmatched, DeclaredMethods).</summary>
  TTypeMatch = record
    TypeName: string;
    Declarations: TArray<TIndexSymbol>;
    DeclarationHeaders: TArray<string>;
    /// <summary>Rumpf je Deklaration als Index in Bodies; -1 ohne Rumpf, -2 übergangen (abstract, external,
    /// forward).</summary>
    BodyOf: TArray<Integer>;
    Bodies: TArray<TIndexSymbol>;
    BodyHeaders: TArray<string>;
    BodyUsed: TArray<Boolean>;
  end;

/// <summary>Deklarationen und Rümpfe je Typ der Datei, in der Reihenfolge der Typen; generische Typen fehlen.
/// </summary>
function MatchMethods(ATree: TSyntaxTree; const AText: string): TArray<TTypeMatch>;
var
  Lines: TArray<string>;
  UnitIndex: TUnitIndex;
  TypeSymbol, Symbol: TIndexSymbol;
  Match: TTypeMatch;
  BodyKeys, BodyConventions: TArray<string>;
  Rest, Header, Key: string;
  Declaration, Body: Integer;

  function FreeBody(const AKey: string): Integer;
  var
    Candidate: Integer;
  begin
    for Candidate := 0 to High(BodyKeys) do
      if not Match.BodyUsed[Candidate] and (BodyKeys[Candidate] = AKey) then
        Exit(Candidate);
    Result := -1;
  end;

begin
  Result := nil;
  Lines := TTextLines.SplitLines(AText);
  UnitIndex := TIndexExtractor.Extract(ATree, '');
  for TypeSymbol in UnitIndex.Symbols do
  begin
    if not (TypeSymbol.Kind in TypeKinds) then
      Continue;
    // Generische Typen brauchen die Typparameter im Kopf; die kennt der Index nicht.
    Rest := Copy(Lines[TypeSymbol.SelectionRange.EndPos.Line], TypeSymbol.SelectionRange.EndPos.Character + 1,
      MaxInt);
    if (TypeSymbol.TypeParams <> '') or TrimLeft(Rest).StartsWith('<') then
      Continue;
    Match := Default(TTypeMatch);
    Match.TypeName := TypeNameOf(TypeSymbol);
    BodyKeys := nil;
    BodyConventions := nil;
    for Symbol in UnitIndex.Symbols do
    begin
      if not (Symbol.Kind in MethodKinds) or not SameText(Symbol.Container, Match.TypeName) then
        Continue;
      Header := Signature(RangeText(Lines, Symbol.Range), Rest);
      if ContainsLine(TypeSymbol.Range, Symbol.Range.StartPos.Line) then
      begin
        Match.Declarations := Match.Declarations + [Symbol];
        Match.DeclarationHeaders := Match.DeclarationHeaders + [Header];
      end
      else
      begin
        Match.Bodies := Match.Bodies + [Symbol];
        Match.BodyHeaders := Match.BodyHeaders + [Header];
        Match.BodyUsed := Match.BodyUsed + [False];
        BodyKeys := BodyKeys + [LowerCase(Symbol.Name) + ParameterKey(Header) + ResultKey(Header)];
        BodyConventions := BodyConventions + [ConventionOfRest(Rest)];
      end;
    end;
    SetLength(Match.BodyOf, Length(Match.Declarations));
    for Declaration := 0 to High(Match.Declarations) do
    begin
      Symbol := Match.Declarations[Declaration];
      Signature(RangeText(Lines, Symbol.Range), Rest);
      if HasWord(Rest, 'abstract') or HasWord(Rest, 'external') or HasWord(Rest, 'forward') then
      begin
        Match.BodyOf[Declaration] := -2;
        Continue;
      end;
      Header := Match.DeclarationHeaders[Declaration];
      Key := LowerCase(Symbol.Name) + ParameterKey(Header) + ResultKey(Header);
      Body := FreeBody(Key);
      // Ohne Parameterliste im Rumpf passt er zur ersten Deklaration gleichen Namens.
      if Body < 0 then
        Body := FreeBody(LowerCase(Symbol.Name));
      // Eine andere ausdrückliche Aufrufkonvention im Rumpf passt nicht (E2037).
      if (Body >= 0) and ConventionDiffers(BodyConventions[Body], ConventionOfRest(Rest)) then
        Body := -1;
      if Body >= 0 then
        Match.BodyUsed[Body] := True;
      Match.BodyOf[Declaration] := Body;
    end;
    Result := Result + [Match];
  end;
end;

class function TClassCompletion.Unmatched(ATree: TSyntaxTree; const AText: string): TArray<TUnmatchedMethod>;
var
  Match: TTypeMatch;
  Index: Integer;
  Item: TUnmatchedMethod;
begin
  Result := nil;
  for Match in MatchMethods(ATree, AText) do
  begin
    for Index := 0 to High(Match.Declarations) do
      if Match.BodyOf[Index] = -1 then
      begin
        Item := Default(TUnmatchedMethod);
        Item.TypeName := Match.TypeName;
        Item.Symbol := Match.Declarations[Index];
        Item.Declared := True;
        Item.Header := Match.DeclarationHeaders[Index];
        Result := Result + [Item];
      end;
    for Index := 0 to High(Match.Bodies) do
      if not Match.BodyUsed[Index] then
      begin
        Item := Default(TUnmatchedMethod);
        Item.TypeName := Match.TypeName;
        Item.Symbol := Match.Bodies[Index];
        Item.Header := Match.BodyHeaders[Index];
        Result := Result + [Item];
      end;
  end;
end;

class function TClassCompletion.DeclaredMethods(ATree: TSyntaxTree; const AText: string): TArray<TDeclaredMethod>;
var
  Matches: TArray<TTypeMatch>;
  TypeIndex, Index: Integer;
  Item: TDeclaredMethod;
begin
  Result := nil;
  Matches := MatchMethods(ATree, AText);
  for TypeIndex := 0 to High(Matches) do
    for Index := 0 to High(Matches[TypeIndex].Declarations) do
    begin
      if Matches[TypeIndex].BodyOf[Index] = -2 then
        Continue;
      Item := Default(TDeclaredMethod);
      Item.TypeName := Matches[TypeIndex].TypeName;
      Item.TypeOrder := TypeIndex;
      Item.DeclarationOrder := Index;
      Item.Declaration := Matches[TypeIndex].Declarations[Index];
      Item.HasBody := Matches[TypeIndex].BodyOf[Index] >= 0;
      if Item.HasBody then
        Item.Body := Matches[TypeIndex].Bodies[Matches[TypeIndex].BodyOf[Index]];
      Result := Result + [Item];
    end;
end;

class function TClassCompletion.AddDeclaration(ATree: TSyntaxTree; const AText: string;
  const AMethod: TUnmatchedMethod; out AEdit: TTextEdit): Boolean;
var
  Lines: TArray<string>;
  UnitIndex: TUnitIndex;
  Symbol, TypeSymbol: TIndexSymbol;
  Found, Overloaded: Boolean;
  Declaration, Trimmed, LB: string;
  Index, Line, EndLine: Integer;
begin
  Result := False;
  AEdit := Default(TTextEdit);
  if AMethod.Declared then
    Exit;
  Lines := TTextLines.SplitLines(AText);
  UnitIndex := TIndexExtractor.Extract(ATree, '');
  Found := False;
  TypeSymbol := Default(TIndexSymbol);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind in TypeKinds) and SameText(TypeNameOf(Symbol), AMethod.TypeName) then
    begin
      TypeSymbol := Symbol;
      Found := True;
      Break;
    end;
  if not Found or (TypeSymbol.Range.EndPos.Line <= TypeSymbol.Range.StartPos.Line) or
    (TypeSymbol.Range.EndPos.Line > High(Lines)) then
    Exit;
  // "procedure TFoo.Bar(A: Integer)" wird "procedure Bar(A: Integer);".
  Index := Pos(LowerCase(AMethod.TypeName + '.'), LowerCase(AMethod.Header));
  if Index = 0 then
    Exit;
  Declaration := Copy(AMethod.Header, 1, Index - 1) + Copy(AMethod.Header, Index + Length(AMethod.TypeName) + 1,
    MaxInt) + ';';
  Overloaded := False;
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind in MethodKinds) and SameText(Symbol.Container, AMethod.TypeName) and
      SameText(Symbol.Name, AMethod.Symbol.Name) and ContainsLine(TypeSymbol.Range, Symbol.Range.StartPos.Line) then
      Overloaded := True;
  if Overloaded and not HasWord(Declaration, 'overload') then
    Declaration := Declaration + ' overload;';
  LB := TTextLines.LineBreakOf(AText);
  // Vorhandener private-Abschnitt (nicht strict private) direkt im Typ.
  for Line := TypeSymbol.Range.StartPos.Line + 1 to TypeSymbol.Range.EndPos.Line - 1 do
  begin
    Trimmed := LowerCase(Trim(Lines[Line]));
    if Trimmed = 'private' then
    begin
      AEdit := TTextEdit.Create(TTextRange.Create(Line, Length(Lines[Line]), Line, Length(Lines[Line])),
        LB + TTextLines.IndentOf(Lines[Line]) + '  ' + Declaration);
      Exit(True);
    end;
  end;
  // Sonst einen anlegen, vor dem "end" des Typs.
  EndLine := TypeSymbol.Range.EndPos.Line;
  if not LowerCase(TrimLeft(Lines[EndLine])).StartsWith('end') then
    Exit;
  AEdit := TTextEdit.Create(TTextRange.Create(EndLine, 0, EndLine, 0),
    TTextLines.IndentOf(Lines[EndLine]) + 'private' + LB + TTextLines.IndentOf(Lines[EndLine]) + '  ' +
    Declaration + LB);
  Result := True;
end;

class function TClassCompletion.BodyEdit(ATree: TSyntaxTree; const AText, ATypeName, ABody: string;
  out AEdit: TTextEdit): Boolean;
var
  Lines: TArray<string>;
  UnitIndex: TUnitIndex;
  Symbol, TypeSymbol: TIndexSymbol;
  LastLine, InsertLine: Integer;
  Found: Boolean;
  LB: string;
begin
  AEdit := Default(TTextEdit);
  Lines := TTextLines.SplitLines(AText);
  UnitIndex := TIndexExtractor.Extract(ATree, '');
  Found := False;
  TypeSymbol := Default(TIndexSymbol);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind in TypeKinds) and SameText(TypeNameOf(Symbol), ATypeName) then
    begin
      TypeSymbol := Symbol;
      Found := True;
      Break;
    end;
  if not Found then
    Exit(False);
  LastLine := -1;
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind in MethodKinds) and SameText(Symbol.Container, ATypeName) and
      not ContainsLine(TypeSymbol.Range, Symbol.Range.StartPos.Line) and (Symbol.Range.EndPos.Line > LastLine) then
      LastLine := Symbol.Range.EndPos.Line;
  LB := TTextLines.LineBreakOf(AText);
  if LastLine >= 0 then
    AEdit := TTextEdit.Create(TTextRange.Create(LastLine, Length(Lines[LastLine]), LastLine, Length(Lines[LastLine])),
      LB + LB + ABody)
  else
  begin
    InsertLine := ImplementationEndLine(ATree);
    if InsertLine < 0 then
      Exit(False);
    AEdit := TTextEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0), ABody + LB + LB);
  end;
  Result := True;
end;

class function TClassCompletion.MissingBodies(ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; out AAction: TCodeAction): Boolean;
var
  Lines: TArray<string>;
  UnitIndex: TUnitIndex;
  Symbol, TypeSymbol: TIndexSymbol;
  Declarations, Missing: TList<TIndexSymbol>;
  Implemented: TList<string>;
  Rest, Header, Key, LB, Bodies, TypeName: string;
  Index, LastLine, InsertLine: Integer;
  OnMethod: Boolean;
  Found: Boolean;
begin
  AAction := Default(TCodeAction);
  Result := False;
  Lines := TTextLines.SplitLines(AText);
  UnitIndex := TIndexExtractor.Extract(ATree, '');
  // Innerster Typ unter dem Cursor.
  Found := False;
  TypeSymbol := Default(TIndexSymbol);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind in TypeKinds) and ContainsLine(Symbol.Range, APosition.Line) and
      (not Found or (Symbol.Range.StartPos.Line >= TypeSymbol.Range.StartPos.Line)) then
    begin
      TypeSymbol := Symbol;
      Found := True;
    end;
  if not Found then
    Exit;
  if TypeSymbol.Container <> '' then
    TypeName := TypeSymbol.Container + '.' + TypeSymbol.Name
  else
    TypeName := TypeSymbol.Name;
  // Generische Typen brauchen die Typparameter im Kopf; die kennt der Index nicht.
  Rest := Copy(Lines[TypeSymbol.SelectionRange.EndPos.Line], TypeSymbol.SelectionRange.EndPos.Character + 1, MaxInt);
  if TrimLeft(Rest).StartsWith('<') then
    Exit;
  Declarations := TList<TIndexSymbol>.Create;
  Missing := TList<TIndexSymbol>.Create;
  Implemented := TList<string>.Create;
  try
    LastLine := -1;
    for Symbol in UnitIndex.Symbols do
    begin
      if not (Symbol.Kind in MethodKinds) or not SameText(Symbol.Container, TypeName) then
        Continue;
      if ContainsLine(TypeSymbol.Range, Symbol.Range.StartPos.Line) then
        Declarations.Add(Symbol)
      else
      begin
        Implemented.Add(LowerCase(Symbol.Name) + ParameterKey(Signature(RangeText(Lines, Symbol.Range), Rest)));
        if Symbol.Range.EndPos.Line > LastLine then
          LastLine := Symbol.Range.EndPos.Line;
      end;
    end;
    OnMethod := False;
    for Symbol in Declarations do
    begin
      Header := Signature(RangeText(Lines, Symbol.Range), Rest);
      if HasWord(Rest, 'abstract') then
        Continue;
      Key := LowerCase(Symbol.Name) + ParameterKey(Header);
      Index := Implemented.IndexOf(Key);
      // Ohne Parameterliste in der Implementierung passt sie zur ersten Deklaration gleichen Namens.
      if Index < 0 then
        Index := Implemented.IndexOf(LowerCase(Symbol.Name));
      if Index >= 0 then
      begin
        Implemented.Delete(Index);
        Continue;
      end;
      if ContainsLine(Symbol.Range, APosition.Line) then
      begin
        Missing.Clear;
        Missing.Add(Symbol);
        OnMethod := True;
        Break;
      end;
      Missing.Add(Symbol);
    end;
    if Missing.Count = 0 then
      Exit;
    LB := TTextLines.LineBreakOf(AText);
    Bodies := '';
    for Symbol in Missing do
    begin
      Header := QualifiedHeader(Signature(RangeText(Lines, Symbol.Range), Rest), Symbol.Name, TypeName);
      if Header = '' then
        Continue;
      Bodies := Bodies + LB + Header + LB + 'begin' + LB + LB + 'end;' + LB;
    end;
    if Bodies = '' then
      Exit;
    if LastLine >= 0 then
    begin
      InsertLine := LastLine;
      AAction.Edits := [TTextEdit.Create(TTextRange.Create(InsertLine, Length(Lines[InsertLine]), InsertLine,
        Length(Lines[InsertLine])), LB + Copy(Bodies, 1, Length(Bodies) - Length(LB)))];
    end
    else
    begin
      InsertLine := ImplementationEndLine(ATree);
      if InsertLine < 0 then
        Exit;
      AAction.Edits := [TTextEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0),
        Copy(Bodies, Length(LB) + 1, MaxInt) + LB)];
    end;
    if OnMethod then
      AAction.Title := Format('Methodenrumpf für %s.%s erzeugen', [TypeName, Missing[0].Name])
    else if Missing.Count = 1 then
      AAction.Title := Format('Fehlenden Methodenrumpf für %s erzeugen', [TypeName])
    else
      AAction.Title := Format('%d fehlende Methodenrümpfe für %s erzeugen', [Missing.Count, TypeName]);
    AAction.Kind := RewriteKind;
    AAction.Tag := ClassBodiesTag;
    Result := True;
  finally
    Implemented.Free;
    Missing.Free;
    Declarations.Free;
  end;
end;

end.
