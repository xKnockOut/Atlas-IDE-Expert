unit Atlas.Common.Editing.ResourceStrings;

// String-Literal als resourcestring auslagern (#473, ARG-074), gemeinsam mit
// dem Schnellbefehl /resstr (#294):
//   - NameFor: Präfix S und die ersten bis zu vier bedeutungstragenden Wörter
//     in CamelCase, Umlaute ersetzt, Format-Platzhalter (%s, %0:d) übergangen:
//     'Eintrag wirklich löschen?' → SEintragWirklichLoeschen.
//   - LiteralAt: das Literal unter dem Cursor samt direkt angehängten
//     Zeichenkonstanten ('Zeile'#13#10'Zwei'); leer und einzelne Zeichen nicht,
//     die könnten Char sein.
//   - Allowed: nicht in Konstanten, Attributen, case-Marken, Parametervorgaben,
//     Typen, Mengen und initialisierten globalen Variablen, wo ein
//     resourcestring nicht erlaubt ist.
//   - Entries und Insertion: vorhandene resourcestring-Einträge lesen und einen
//     neuen anhängen; fehlt der Abschnitt, entsteht er (implementation der
//     eigenen Unit bzw. interface einer festgelegten Unit).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TResourceEntry = record
    Name: string;
    /// <summary>Quelltext des Werts, z. B. 'Fehler'#13#10.</summary>
    Value: string;
    /// <summary>Zeile des abschließenden ";".</summary>
    Line: Integer;
    /// <summary>Zeile des Namens.</summary>
    NameLine: Integer;
    /// <summary>Zeile des Schlüsselworts resourcestring seines Abschnitts.</summary>
    Section: Integer;
    /// <summary>Steht im interface-Teil.</summary>
    InInterface: Boolean;
  end;

  /// <summary>Literal unter dem Cursor: Bereich und Quelltext.</summary>
  TResourceLiteral = record
    Range: TTextRange;
    StartOffset: Integer;
    Source: string;
    /// <summary>Text ohne Hochkommas und Zeichenkonstanten aufgelöst.</summary>
    Text: string;
  end;

  TResourceStrings = class
  public
    /// <summary>Name aus dem Klartext AText: SEintragWirklichLoeschen; ohne Wörter SText.</summary>
    class function NameFor(const AText: string): string; static;
    /// <summary>ABase oder mit Ziffer ab 2, wenn ATaken ihn schon enthält (ohne Groß-/Kleinschreibung).</summary>
    class function UniqueName(const ABase: string; const ATaken: TArray<string>): string; static;
    /// <summary>Literal, in dem APosition liegt (nicht davor oder dahinter); False ohne oder bei leerem bzw.
    /// einzelnem Zeichen.</summary>
    class function LiteralAt(const AText: string; const ATokens: TArray<TPascalToken>;
      const APosition: TTextPosition; out ALiteral: TResourceLiteral): Boolean; static;
    /// <summary>Darf an AOffset ein resourcestring stehen? Nur im Rumpf von Routinen und im initialization-
    /// bzw. finalization-Teil, nicht in Konstanten, Attributen, case-Marken, Parametern und Mengen.</summary>
    class function Allowed(ATree: TSyntaxTree; AOffset: Integer): Boolean; static;
    /// <summary>Alle Einträge der resourcestring-Abschnitte in Quelltextreihenfolge.</summary>
    class function Entries(const AText: string; const ATokens: TArray<TPascalToken>): TArray<TResourceEntry>;
      static;
    /// <summary>Eintrag mit gleichem Text (nach Auflösung von Hochkommas und Zeichenkonstanten) im passenden Teil
    /// (AInterface) und vor Zeile ABefore (-1 = überall); False ohne.</summary>
    class function SameText(const AEntries: TArray<TResourceEntry>; const AText: string; AInterface: Boolean;
      ABefore: Integer; out AEntry: TResourceEntry): Boolean; static;
    /// <summary>Einfügung von "ADeclaration" (ohne Einrückung, z. B. "SName = 'Text';"): hinter den letzten
    /// Eintrag des ersten passenden Abschnitts (im implementation-Teil vor Zeile ABefore bzw. im interface-Teil),
    /// sonst als neuer Abschnitt hinter implementation und deren uses bzw. vor implementation.</summary>
    class function Insertion(const AText: string; const ATokens: TArray<TPascalToken>; AInterface: Boolean;
      ABefore: Integer; const ADeclaration, ALineBreak: string; out AEdit: TTextEdit): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Character,
  Atlas.Common.Editing.StringLiterals;

const
  /// <summary>Wörter ohne eigene Bedeutung; sie zählen nur, wenn sonst keins bleibt.</summary>
  StopWords: array[0..19] of string = ('der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen', 'einem',
    'einer', 'eines', 'und', 'oder', 'the', 'a', 'an', 'and', 'or', 'of');
  MaxWords = 4;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
    Result := A.Character - B.Character;
end;

function TokenEnd(const AToken: TPascalToken): Integer;
begin
  Result := AToken.Offset + Length(AToken.Text);
end;

{ TResourceStrings }

class function TResourceStrings.NameFor(const AText: string): string;
var
  Words, Meaningful: TArray<string>;
  Word, Letter: string;
  Index, Count: Integer;
  C: Char;

  procedure Flush;
  begin
    if Word <> '' then
      Words := Words + [Word];
    Word := '';
  end;

begin
  Words := nil;
  Word := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    C := AText[Index];
    // Format-Platzhalter %s, %d, %0:s, %-10.2f: weder Wort noch Teil eines Worts.
    if (C = '%') and (Index < Length(AText)) then
    begin
      Flush;
      Inc(Index);
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['0'..'9', ':', '-', '.', '*']) do
        Inc(Index);
      if (Index <= Length(AText)) and CharInSet(AText[Index], ['a'..'z', 'A'..'Z', '%']) then
        Inc(Index);
      Continue;
    end;
    case C of
      'ä': Letter := 'ae';
      'ö': Letter := 'oe';
      'ü': Letter := 'ue';
      'Ä': Letter := 'Ae';
      'Ö': Letter := 'Oe';
      'Ü': Letter := 'Ue';
      'ß': Letter := 'ss';
      'A'..'Z', 'a'..'z', '0'..'9': Letter := C;
    else
      Letter := '';
      // Andere Buchstaben (é) fallen weg, ohne das Wort zu trennen.
      if not C.IsLetter then
        Flush;
    end;
    Word := Word + Letter;
    Inc(Index);
  end;
  Flush;
  Meaningful := nil;
  for Word in Words do
    if not MatchText(Word, StopWords) then
      Meaningful := Meaningful + [Word];
  if Length(Meaningful) = 0 then
    Meaningful := Words;
  Result := 'S';
  Count := 0;
  for Word in Meaningful do
  begin
    Result := Result + UpperCase(Copy(Word, 1, 1)) + Copy(Word, 2, MaxInt);
    Inc(Count);
    if Count = MaxWords then
      Break;
  end;
  if Result = 'S' then
    Result := 'SText';
end;

class function TResourceStrings.UniqueName(const ABase: string; const ATaken: TArray<string>): string;
var
  Number: Integer;
begin
  Result := ABase;
  Number := 1;
  while MatchText(Result, ATaken) do
  begin
    Inc(Number);
    Result := ABase + IntToStr(Number);
  end;
end;

class function TResourceStrings.LiteralAt(const AText: string; const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition; out ALiteral: TResourceLiteral): Boolean;
var
  Index, First, Last: Integer;
  Inside: Boolean;
begin
  ALiteral := Default(TResourceLiteral);
  Result := False;
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].Kind <> TPascalTokenKind.StringLiteral then
      Continue;
    // Echt innerhalb: hinter dem öffnenden und vor dem schließenden Hochkomma.
    Inside := (ComparePositions(ATokens[Index].StartPos, APosition) < 0) and
      ((ComparePositions(APosition, ATokens[Index].EndPos) < 0) or not ATokens[Index].Terminated);
    if not Inside then
      Continue;
    if not ATokens[Index].Terminated then
      Exit;
    // Direkt angehängte Literale und Zeichenkonstanten gehören dazu: 'Zeile'#13#10'Zwei'.
    First := Index;
    while (First > 0) and (ATokens[First - 1].Kind in [TPascalTokenKind.StringLiteral,
      TPascalTokenKind.CharLiteral]) and (TokenEnd(ATokens[First - 1]) = ATokens[First].Offset) do
      Dec(First);
    Last := Index;
    while (Last < High(ATokens)) and (ATokens[Last + 1].Kind in [TPascalTokenKind.StringLiteral,
      TPascalTokenKind.CharLiteral]) and (TokenEnd(ATokens[Last]) = ATokens[Last + 1].Offset) do
      Inc(Last);
    ALiteral.Range := TTextRange.Create(ATokens[First].StartPos, ATokens[Last].EndPos);
    ALiteral.StartOffset := ATokens[First].Offset;
    ALiteral.Source := Copy(AText, ATokens[First].Offset + 1, TokenEnd(ATokens[Last]) - ATokens[First].Offset);
    if not TStringLiterals.PlainText(ALiteral.Source, ALiteral.Text) then
      Exit;
    Result := Length(ALiteral.Text) > 1;
    Exit;
  end;
end;

class function TResourceStrings.Allowed(ATree: TSyntaxTree; AOffset: Integer): Boolean;
var
  Node, Child: TSyntaxNode;
  Index: Integer;
  Found, InBody: Boolean;
begin
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Node := ATree.Root;
  repeat
    Found := False;
    for Index := 0 to Node.ChildCount - 1 do
      if (Node[Index].StartOffset <= AOffset) and (AOffset < Node[Index].EndOffset) then
      begin
        Node := Node[Index];
        Found := True;
        Break;
      end;
  until not Found;
  // Von innen nach außen; erst ein Anweisungsblock macht die Stelle zulässig.
  InBody := False;
  Child := nil;
  while Node <> nil do
  begin
    case Node.Kind of
      TSyntaxKind.ConstSection, TSyntaxKind.ConstDecl, TSyntaxKind.InlineConst, TSyntaxKind.Attribute,
      TSyntaxKind.Parameter, TSyntaxKind.Parameters, TSyntaxKind.PropertyDecl, TSyntaxKind.TypeSection,
      TSyntaxKind.TypeDecl, TSyntaxKind.SetConstructor, TSyntaxKind.RangeExpr, TSyntaxKind.ExportsClause,
      TSyntaxKind.AsmBlock, TSyntaxKind.VarDecl, TSyntaxKind.VarSection:
        if not InBody then
          Exit;
      TSyntaxKind.CaseItem:
        // Marken stehen vor der Anweisung, dem letzten Kind.
        if (Child <> nil) and (Node.ChildCount > 0) and (Node[Node.ChildCount - 1] <> Child) then
          Exit;
      TSyntaxKind.Block, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection:
        InBody := True;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    Child := Node;
    Node := Node.Parent;
  end;
  Result := InBody;
end;

class function TResourceStrings.Entries(const AText: string;
  const ATokens: TArray<TPascalToken>): TArray<TResourceEntry>;
var
  Index, Next, Value, Stop, Section: Integer;
  InInterface, InSection: Boolean;
  Entry: TResourceEntry;
begin
  Result := nil;
  InInterface := False;
  InSection := False;
  Section := -1;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if ATokens[Index].IsKeyword('interface') then
      InInterface := True
    else if ATokens[Index].IsKeyword('implementation') then
      InInterface := False;
    if ATokens[Index].IsKeyword('resourcestring') then
    begin
      InSection := True;
      Section := ATokens[Index].StartPos.Line;
      Index := NextIndex(ATokens, Index);
      Continue;
    end;
    if InSection then
    begin
      Next := NextIndex(ATokens, Index);
      if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and (Next <= High(ATokens)) and
        ATokens[Next].IsSymbol('=') then
      begin
        Value := NextIndex(ATokens, Next);
        Stop := Value;
        while (Stop <= High(ATokens)) and not ATokens[Stop].IsSymbol(';') do
          Inc(Stop);
        if Stop > High(ATokens) then
          Break;
        Entry := Default(TResourceEntry);
        Entry.Name := ATokens[Index].Text;
        Entry.InInterface := InInterface;
        Entry.Section := Section;
        Entry.NameLine := ATokens[Index].StartPos.Line;
        Entry.Line := ATokens[Stop].StartPos.Line;
        if Value < Stop then
          Entry.Value := Trim(Copy(AText, ATokens[Value].Offset + 1, ATokens[Stop].Offset - ATokens[Value].Offset));
        Result := Result + [Entry];
        Index := NextIndex(ATokens, Stop);
        Continue;
      end;
      InSection := False;
    end;
    Index := NextIndex(ATokens, Index);
  end;
end;

class function TResourceStrings.SameText(const AEntries: TArray<TResourceEntry>; const AText: string;
  AInterface: Boolean; ABefore: Integer; out AEntry: TResourceEntry): Boolean;
var
  Entry: TResourceEntry;
  Text: string;
begin
  for Entry in AEntries do
    if (Entry.InInterface = AInterface) and ((ABefore < 0) or (Entry.Line < ABefore)) and
      TStringLiterals.PlainText(Entry.Value, Text) and (Text = AText) then
    begin
      AEntry := Entry;
      Exit(True);
    end;
  AEntry := Default(TResourceEntry);
  Result := False;
end;

class function TResourceStrings.Insertion(const AText: string; const ATokens: TArray<TPascalToken>;
  AInterface: Boolean; ABefore: Integer; const ADeclaration, ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  Lines: TArray<string>;
  Index, Next, Implementation_, SectionLine, LastLine, Line: Integer;
  InInterface: Boolean;
  Entry: TResourceEntry;
  Indent: string;

  function LineEnd(ALine: Integer): TTextPosition;
  begin
    Result := TTextPosition.Create(ALine, Length(Lines[ALine]));
  end;

begin
  AEdit := Default(TTextEdit);
  Result := False;
  Lines := AText.Replace(#13, '').Split([#10]);
  Implementation_ := -1;
  for Index := 0 to High(ATokens) do
    if ATokens[Index].IsKeyword('implementation') then
    begin
      Implementation_ := Index;
      Break;
    end;
  if Implementation_ < 0 then
    Exit;
  // Erster passender Abschnitt; der neue Eintrag kommt hinter dessen letzten.
  SectionLine := -1;
  InInterface := False;
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].IsKeyword('interface') then
      InInterface := True
    else if Index = Implementation_ then
      InInterface := False;
    if ATokens[Index].IsKeyword('resourcestring') and (InInterface = AInterface) and
      ((ABefore < 0) or (ATokens[Index].StartPos.Line < ABefore)) then
    begin
      SectionLine := ATokens[Index].StartPos.Line;
      Break;
    end;
  end;
  if SectionLine >= 0 then
  begin
    LastLine := SectionLine;
    Indent := '';
    for Entry in Entries(AText, ATokens) do
      if Entry.Section = SectionLine then
      begin
        if Indent = '' then
          Indent := Copy(Lines[Entry.NameLine], 1, Length(Lines[Entry.NameLine]) -
            Length(TrimLeft(Lines[Entry.NameLine])));
        LastLine := Entry.Line;
      end;
    // Eintrag in der Zeile von resourcestring ("resourcestring SA = 'a';"): mit zwei Leerzeichen darunter.
    if (Indent = '') or (LastLine = SectionLine) then
      Indent := '  ';
    AEdit := TTextEdit.Create(TTextRange.Create(LineEnd(LastLine), LineEnd(LastLine)),
      ALineBreak + Indent + ADeclaration);
    Exit(True);
  end;
  if AInterface then
  begin
    // Neuer Abschnitt vor implementation.
    Line := ATokens[Implementation_].StartPos.Line;
    AEdit := TTextEdit.Create(TTextRange.Create(TTextPosition.Create(Line, 0), TTextPosition.Create(Line, 0)),
      'resourcestring' + ALineBreak + '  ' + ADeclaration + ALineBreak + ALineBreak);
    Exit(True);
  end;
  // Neuer Abschnitt hinter implementation bzw. deren uses.
  Line := ATokens[Implementation_].EndPos.Line;
  Next := NextIndex(ATokens, Implementation_);
  if (Next <= High(ATokens)) and ATokens[Next].IsKeyword('uses') then
  begin
    while (Next <= High(ATokens)) and not ATokens[Next].IsSymbol(';') do
      Inc(Next);
    if Next <= High(ATokens) then
      Line := ATokens[Next].EndPos.Line;
  end;
  AEdit := TTextEdit.Create(TTextRange.Create(LineEnd(Line), LineEnd(Line)),
    ALineBreak + ALineBreak + 'resourcestring' + ALineBreak + '  ' + ADeclaration);
  Result := True;
end;

end.
