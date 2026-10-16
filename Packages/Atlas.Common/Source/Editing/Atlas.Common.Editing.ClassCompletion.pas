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
// SignatureFixes (#100) gleicht Deklaration und Rumpf an, deren Parameter,
// Modifizierer oder Rückgabetyp voneinander abweichen. Zugeordnet wird über
// Name und Parameteranzahl; ist das nicht eindeutig, gibt es keine Aktion.
// Standardwerte bleiben nur in der Deklaration.

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

  TClassCompletion = class
  public
    /// <summary>Methoden ohne Gegenstück in Typen dieser Datei. Abstrakte, externe und forward-
    /// Methoden sowie generische Typen werden übergangen; Rümpfe zu Typen, die nicht in der
    /// Datei stehen, ebenfalls.</summary>
    class function Unmatched(ATree: TSyntaxTree; const AText: string): TArray<TUnmatchedMethod>; static;
    /// <summary>Fügt die Deklaration zu einem Rumpf ohne Deklaration im private-Abschnitt ein
    /// (legt ihn bei Bedarf an); False, wenn der Typ nicht passend aufgebaut ist.</summary>
    class function AddDeclaration(ATree: TSyntaxTree; const AText: string; const AMethod: TUnmatchedMethod;
      out AEdit: TTextEdit): Boolean; static;
    /// <summary>Aktion für fehlende Rümpfe an APosition; False, wenn nichts fehlt.</summary>
    class function MissingBodies(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      out AAction: TCodeAction): Boolean; static;
    /// <summary>Zu einer Methode ohne Gegenstück mit eindeutigem Partner gleichen Namens und gleicher
    /// Parameteranzahl auf der anderen Seite: "Implementierung an Deklaration angleichen" und
    /// "Deklaration an Implementierung angleichen" (#100). False ohne eindeutigen Partner.
    /// Liefert Code-Aktionen statt TRuleFix, damit Editing ohne Rules auskommt (A-11); die Regeln
    /// in Rules.Builtin.Declarations machen daraus alternative Korrekturen.</summary>
    class function SignatureFixes(ATree: TSyntaxTree; const AText: string; const AMethod: TUnmatchedMethod;
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
  System.Generics.Collections,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.Contract,
  Atlas.Text.Lines;

const
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
  out ARange: TTextRange; out ATail: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Name, Last, Depth, StartOffset: Integer;
begin
  Result := False;
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
  Result := True;
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
  // Attribute wie [ref] stehen vor den Namen.
  if Pos(']', Names) > 0 then
    Names := Trim(Copy(Names, LastDelimiter(']', Names) + 1, MaxInt));
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

{ TClassCompletion }

class function TClassCompletion.SignatureFixes(ATree: TSyntaxTree; const AText: string;
  const AMethod: TUnmatchedMethod; out AFixes: TArray<TCodeAction>): Boolean;
var
  Items: TArray<TUnmatchedMethod>;
  Item, Partner, Decl, Body: TUnmatchedMethod;
  Partners, Same: Integer;
  DeclRange, BodyRange: TTextRange;
  DeclTail, BodyTail: string;
  Fix: TCodeAction;
begin
  AFixes := nil;
  Result := False;
  Items := Unmatched(ATree, AText);
  Partners := 0;
  Same := 0;
  Partner := Default(TUnmatchedMethod);
  for Item in Items do
  begin
    if not SameText(Item.TypeName, AMethod.TypeName) or not SameText(Item.Symbol.Name, AMethod.Symbol.Name) or
      (Item.Symbol.MaxArgs <> AMethod.Symbol.MaxArgs) then
      Continue;
    if Item.Declared = AMethod.Declared then
      Inc(Same)
    else
    begin
      Inc(Partners);
      Partner := Item;
    end;
  end;
  // Mehrdeutig (Überladungen gleicher Länge) oder ohne Gegenstück: nichts anbieten.
  if (Partners <> 1) or (Same <> 1) then
    Exit;
  if AMethod.Declared then
  begin
    Decl := AMethod;
    Body := Partner;
  end
  else
  begin
    Decl := Partner;
    Body := AMethod;
  end;
  if not SignatureTail(ATree, AText, Decl.Symbol, DeclRange, DeclTail) or
    not SignatureTail(ATree, AText, Body.Symbol, BodyRange, BodyTail) then
    Exit;
  Fix := Default(TCodeAction);
  Fix.Kind := QuickFixKind;
  Fix.Title := Format('Implementierung von %s an die Deklaration angleichen', [AMethod.Symbol.Name]);
  Fix.Edits := [TTextEdit.Create(BodyRange, WithoutDefaults(DeclTail))];
  AFixes := AFixes + [Fix];
  Fix.Title := Format('Deklaration von %s an die Implementierung angleichen', [AMethod.Symbol.Name]);
  Fix.Edits := [TTextEdit.Create(DeclRange, WithDefaultsOf(BodyTail, DeclTail))];
  AFixes := AFixes + [Fix];
  Result := True;
end;


class function TClassCompletion.Unmatched(ATree: TSyntaxTree; const AText: string): TArray<TUnmatchedMethod>;
var
  Lines: TArray<string>;
  UnitIndex: TUnitIndex;
  TypeSymbol, Symbol: TIndexSymbol;
  Declarations, Bodies: TList<TIndexSymbol>;
  BodyKeys: TList<string>;
  TypeName, Rest, Header, Key: string;
  Index: Integer;
  Item: TUnmatchedMethod;
begin
  Result := nil;
  Lines := TTextLines.SplitLines(AText);
  UnitIndex := TIndexExtractor.Extract(ATree, '');
  Declarations := TList<TIndexSymbol>.Create;
  Bodies := TList<TIndexSymbol>.Create;
  BodyKeys := TList<string>.Create;
  try
    for TypeSymbol in UnitIndex.Symbols do
    begin
      if not (TypeSymbol.Kind in TypeKinds) then
        Continue;
      // Generische Typen brauchen die Typparameter im Kopf; die kennt der Index nicht.
      Rest := Copy(Lines[TypeSymbol.SelectionRange.EndPos.Line], TypeSymbol.SelectionRange.EndPos.Character + 1,
        MaxInt);
      if (TypeSymbol.TypeParams <> '') or TrimLeft(Rest).StartsWith('<') then
        Continue;
      TypeName := TypeNameOf(TypeSymbol);
      Declarations.Clear;
      Bodies.Clear;
      BodyKeys.Clear;
      for Symbol in UnitIndex.Symbols do
      begin
        if not (Symbol.Kind in MethodKinds) or not SameText(Symbol.Container, TypeName) then
          Continue;
        if ContainsLine(TypeSymbol.Range, Symbol.Range.StartPos.Line) then
          Declarations.Add(Symbol)
        else
        begin
          Bodies.Add(Symbol);
          BodyKeys.Add(LowerCase(Symbol.Name) + ParameterKey(Signature(RangeText(Lines, Symbol.Range), Rest)));
        end;
      end;
      for Symbol in Declarations do
      begin
        Header := Signature(RangeText(Lines, Symbol.Range), Rest);
        if HasWord(Rest, 'abstract') or HasWord(Rest, 'external') or HasWord(Rest, 'forward') then
          Continue;
        Key := LowerCase(Symbol.Name) + ParameterKey(Header);
        Index := BodyKeys.IndexOf(Key);
        // Ohne Parameterliste im Rumpf passt er zur ersten Deklaration gleichen Namens.
        if Index < 0 then
          Index := BodyKeys.IndexOf(LowerCase(Symbol.Name));
        if Index >= 0 then
        begin
          BodyKeys.Delete(Index);
          Bodies.Delete(Index);
          Continue;
        end;
        Item := Default(TUnmatchedMethod);
        Item.TypeName := TypeName;
        Item.Symbol := Symbol;
        Item.Declared := True;
        Item.Header := Header;
        Result := Result + [Item];
      end;
      for Symbol in Bodies do
      begin
        Item := Default(TUnmatchedMethod);
        Item.TypeName := TypeName;
        Item.Symbol := Symbol;
        Item.Header := Signature(RangeText(Lines, Symbol.Range), Rest);
        Result := Result + [Item];
      end;
    end;
  finally
    BodyKeys.Free;
    Bodies.Free;
    Declarations.Free;
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
    Result := True;
  finally
    Implemented.Free;
    Missing.Free;
    Declarations.Free;
  end;
end;

end.
