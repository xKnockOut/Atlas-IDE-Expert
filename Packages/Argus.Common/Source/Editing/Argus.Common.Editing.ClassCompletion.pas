unit Argus.Common.Editing.ClassCompletion;

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

interface

uses
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Index.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Editing.CodeActions;

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
      out AEdit: TRuleEdit): Boolean; static;
    /// <summary>Aktion für fehlende Rümpfe an APosition; False, wenn nichts fehlt.</summary>
    class function MissingBodies(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      out AAction: TCodeAction): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Argus.Common.Index.Extractor,
  Argus.Common.Pascal.Contract;

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.HelperType];
  MethodKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];

function SplitLines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function LineBreakOf(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

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

/// <summary>Parameterliste ohne Leerzeichen in Kleinbuchstaben; '' ohne Klammern.</summary>
function ParameterKey(const ASignature: string): string;
var
  Open, Close: Integer;
begin
  Open := Pos('(', ASignature);
  Close := LastDelimiter(')', ASignature);
  if (Open = 0) or (Close < Open) then
    Exit('');
  Result := LowerCase(StringReplace(Copy(ASignature, Open, Close - Open + 1), ' ', '', [rfReplaceAll]));
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

function IndentOf(const ALine: string): string;
begin
  Result := Copy(ALine, 1, Length(ALine) - Length(TrimLeft(ALine)));
end;

{ TClassCompletion }

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
  Lines := SplitLines(AText);
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
  const AMethod: TUnmatchedMethod; out AEdit: TRuleEdit): Boolean;
var
  Lines: TArray<string>;
  UnitIndex: TUnitIndex;
  Symbol, TypeSymbol: TIndexSymbol;
  Found, Overloaded: Boolean;
  Declaration, Trimmed, LB: string;
  Index, Line, EndLine: Integer;
begin
  Result := False;
  AEdit := Default(TRuleEdit);
  if AMethod.Declared then
    Exit;
  Lines := SplitLines(AText);
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
  LB := LineBreakOf(AText);
  // Vorhandener private-Abschnitt (nicht strict private) direkt im Typ.
  for Line := TypeSymbol.Range.StartPos.Line + 1 to TypeSymbol.Range.EndPos.Line - 1 do
  begin
    Trimmed := LowerCase(Trim(Lines[Line]));
    if Trimmed = 'private' then
    begin
      AEdit := TRuleEdit.Create(TTextRange.Create(Line, Length(Lines[Line]), Line, Length(Lines[Line])),
        LB + IndentOf(Lines[Line]) + '  ' + Declaration);
      Exit(True);
    end;
  end;
  // Sonst einen anlegen, vor dem "end" des Typs.
  EndLine := TypeSymbol.Range.EndPos.Line;
  if not LowerCase(TrimLeft(Lines[EndLine])).StartsWith('end') then
    Exit;
  AEdit := TRuleEdit.Create(TTextRange.Create(EndLine, 0, EndLine, 0),
    IndentOf(Lines[EndLine]) + 'private' + LB + IndentOf(Lines[EndLine]) + '  ' + Declaration + LB);
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
  Lines := SplitLines(AText);
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
    LB := LineBreakOf(AText);
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
      AAction.Edits := [TRuleEdit.Create(TTextRange.Create(InsertLine, Length(Lines[InsertLine]), InsertLine,
        Length(Lines[InsertLine])), LB + Copy(Bodies, 1, Length(Bodies) - Length(LB)))];
    end
    else
    begin
      InsertLine := ImplementationEndLine(ATree);
      if InsertLine < 0 then
        Exit;
      AAction.Edits := [TRuleEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0),
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
