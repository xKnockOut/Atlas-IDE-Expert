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

  /// <summary>Wo ein Eintrag gesucht oder angehängt wird: im interface- oder implementation-Teil und vor Zeile
  /// Before (-1 = überall).</summary>
  TResourcePlace = record
    InInterface: Boolean;
    Before: Integer;
    class function Create(AInInterface: Boolean; ABefore: Integer): TResourcePlace; static;
    /// <summary>Steht ALine vor Before (immer bei Before = -1)?</summary>
    function Precedes(ALine: Integer): Boolean;
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
    /// Eintrag des ersten Abschnitts an APlace, sonst als neuer Abschnitt hinter implementation und deren uses
    /// bzw. vor implementation.</summary>
    class function Insertion(const AText: string; const ATokens: TArray<TPascalToken>; const APlace: TResourcePlace;
      const ADeclaration, ALineBreak: string; out AEdit: TTextEdit): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Character,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Pascal.TokenCursor;

const
  /// <summary>Wörter ohne eigene Bedeutung; sie zählen nur, wenn sonst keins bleibt.</summary>
  cStopWords: array[0..19] of string = ('der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen', 'einem',
    'einer', 'eines', 'und', 'oder', 'the', 'a', 'an', 'and', 'or', 'of');
  cMaxWords = 4;

function NextIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

function TokenEnd(const AToken: TPascalToken): Integer;
begin
  Result := AToken.Offset + Length(AToken.Text);
end;

{ TResourcePlace }

class function TResourcePlace.Create(AInInterface: Boolean; ABefore: Integer): TResourcePlace;
begin
  Result.InInterface := AInInterface;
  Result.Before := ABefore;
end;

function TResourcePlace.Precedes(ALine: Integer): Boolean;
begin
  Result := (Before < 0) or (ALine < Before);
end;

{ Namen }

/// <summary>Hängt AWord an AWords, wenn es nicht leer ist, und leert es.</summary>
procedure AddWord(var AWords: TArray<string>; var AWord: string);
begin
  if AWord <> '' then
  begin
    AWords := AWords + [AWord];
  end;
  AWord := '';
end;

/// <summary>Beginnt an AIndex ein Format-Platzhalter (%s, %d, %0:s, %-10.2f)?</summary>
function IsPlaceholder(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AText[AIndex] = '%') and (AIndex < Length(AText));
end;

/// <summary>Index hinter dem Format-Platzhalter, der an AIndex beginnt.</summary>
function PlaceholderEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= Length(AText)) and CharInSet(AText[Result], ['0'..'9', ':', '-', '.', '*']) do
  begin
    Inc(Result);
  end;
  if (Result <= Length(AText)) and CharInSet(AText[Result], ['a'..'z', 'A'..'Z', '%']) then
  begin
    Inc(Result);
  end;
end;

/// <summary>Buchstaben für den Namen zu AChar (Umlaute ersetzt); ASeparates, wenn AChar Wörter trennt.</summary>
function LetterOf(AChar: Char; out ASeparates: Boolean): string;
begin
  ASeparates := False;
  case AChar of
    'ä': Result := 'ae';
    'ö': Result := 'oe';
    'ü': Result := 'ue';
    'Ä': Result := 'Ae';
    'Ö': Result := 'Oe';
    'Ü': Result := 'Ue';
    'ß': Result := 'ss';
    'A'..'Z', 'a'..'z', '0'..'9': Result := AChar;
  else
    Result := '';
    // Andere Buchstaben (é) fallen weg, ohne das Wort zu trennen.
    ASeparates := not AChar.IsLetter;
  end;
end;

/// <summary>Wörter des Klartexts; Format-Platzhalter sind weder Wort noch Teil eines Worts.</summary>
function SplitWords(const AText: string): TArray<string>;
var
  mWord, mLetter: string;
  mIndex: Integer;
  mSeparates: Boolean;
begin
  Result := nil;
  mWord := '';
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if IsPlaceholder(AText, mIndex) then
    begin
      AddWord(Result, mWord);
      mIndex := PlaceholderEnd(AText, mIndex);
      Continue;
    end;
    mLetter := LetterOf(AText[mIndex], mSeparates);
    if mSeparates then
    begin
      AddWord(Result, mWord);
    end;
    mWord := mWord + mLetter;
    Inc(mIndex);
  end;
  AddWord(Result, mWord);
end;

/// <summary>AWords ohne Füllwörter; bleibt keins übrig, alle.</summary>
function MeaningfulWords(const AWords: TArray<string>): TArray<string>;
var
  mWord: string;
begin
  Result := nil;
  for mWord in AWords do
  begin
    if not MatchText(mWord, cStopWords) then
    begin
      Result := Result + [mWord];
    end;
  end;
  if Length(Result) = 0 then
  begin
    Result := AWords;
  end;
end;

{ Abschnitte }

/// <summary>Ende der Zeile ALine.</summary>
function LineEndOf(const ALines: TArray<string>; ALine: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(ALine, Length(ALines[ALine]));
end;

/// <summary>Einrückung von ALine.</summary>
function LeadingSpace(const ALine: string): string;
begin
  Result := Copy(ALine, 1, Length(ALine) - Length(TrimLeft(ALine)));
end;

/// <summary>Index des Schlüsselworts implementation; -1 ohne.</summary>
function ImplementationIndex(const ATokens: TArray<TPascalToken>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Merkt sich, ob die Tokens ab AToken im interface-Teil stehen.</summary>
procedure TrackPart(const AToken: TPascalToken; var AInInterface: Boolean);
begin
  if AToken.IsKeyword('interface') then
  begin
    AInInterface := True;
  end
  else if AToken.IsKeyword('implementation') then
  begin
    AInInterface := False;
  end;
end;

/// <summary>Zeile des ersten resourcestring-Abschnitts an APlace; -1 ohne.</summary>
function SectionLineAt(const ATokens: TArray<TPascalToken>; const APlace: TResourcePlace): Integer;
var
  mIndex: Integer;
  mInInterface: Boolean;
begin
  mInInterface := False;
  for mIndex := 0 to High(ATokens) do
  begin
    TrackPart(ATokens[mIndex], mInInterface);
    if ATokens[mIndex].IsKeyword('resourcestring') and (mInInterface = APlace.InInterface) and
      APlace.Precedes(ATokens[mIndex].StartPos.Line) then
    begin
      Exit(ATokens[mIndex].StartPos.Line);
    end;
  end;
  Result := -1;
end;

/// <summary>Zeile des letzten Eintrags im Abschnitt ASectionLine und Einrückung für einen neuen.</summary>
function SectionEnd(const AEntries: TArray<TResourceEntry>; const ALines: TArray<string>; ASectionLine: Integer;
  out AIndent: string): Integer;
var
  mEntry: TResourceEntry;
begin
  Result := ASectionLine;
  AIndent := '';
  for mEntry in AEntries do
  begin
    if mEntry.Section <> ASectionLine then
    begin
      Continue;
    end;
    if AIndent = '' then
    begin
      AIndent := LeadingSpace(ALines[mEntry.NameLine]);
    end;
    Result := mEntry.Line;
  end;
  // Eintrag in der Zeile von resourcestring ("resourcestring SA = 'a';"): mit zwei Leerzeichen darunter.
  if (AIndent = '') or (Result = ASectionLine) then
  begin
    AIndent := '  ';
  end;
end;

/// <summary>Zeile, hinter der ein neuer Abschnitt im implementation-Teil beginnt: hinter dessen uses.</summary>
function AfterImplementationUses(const ATokens: TArray<TPascalToken>; AImplementation: Integer): Integer;
var
  mNext: Integer;
begin
  Result := ATokens[AImplementation].EndPos.Line;
  mNext := NextIndex(ATokens, AImplementation);
  if (mNext > High(ATokens)) or not ATokens[mNext].IsKeyword('uses') then
  begin
    Exit;
  end;
  while (mNext <= High(ATokens)) and not ATokens[mNext].IsSymbol(';') do
  begin
    Inc(mNext);
  end;
  if mNext <= High(ATokens) then
  begin
    Result := ATokens[mNext].EndPos.Line;
  end;
end;

/// <summary>Index des ";" hinter dem Eintrag "Name = Wert;" ab AIndex; -1 ohne Eintrag, über High ohne ";".
/// </summary>
function EntryStop(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mNext: Integer;
begin
  mNext := NextIndex(ATokens, AIndex);
  if (ATokens[AIndex].Kind <> TPascalTokenKind.Identifier) or (mNext > High(ATokens)) or
    not ATokens[mNext].IsSymbol('=') then
  begin
    Exit(-1);
  end;
  Result := NextIndex(ATokens, mNext);
  while (Result <= High(ATokens)) and not ATokens[Result].IsSymbol(';') do
  begin
    Inc(Result);
  end;
end;

/// <summary>Eintrag von AIndex bis zum ";" an AStop, ohne Abschnitt und Teil.</summary>
function EntryFrom(const AText: string; const ATokens: TArray<TPascalToken>; AIndex, AStop: Integer):
  TResourceEntry;
var
  mValue: Integer;
begin
  Result := Default(TResourceEntry);
  Result.Name := ATokens[AIndex].Text;
  Result.NameLine := ATokens[AIndex].StartPos.Line;
  Result.Line := ATokens[AStop].StartPos.Line;
  mValue := NextIndex(ATokens, NextIndex(ATokens, AIndex));
  if mValue < AStop then
  begin
    Result.Value := Trim(Copy(AText, ATokens[mValue].Offset + 1, ATokens[AStop].Offset - ATokens[mValue].Offset));
  end;
end;

/// <summary>Tiefster Knoten, der AOffset enthält.</summary>
function DeepestNode(ATree: TSyntaxTree; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := ATree.Root;
  repeat
    mFound := False;
    for mIndex := 0 to Result.ChildCount - 1 do
    begin
      if (Result[mIndex].StartOffset <= AOffset) and (AOffset < Result[mIndex].EndOffset) then
      begin
        Result := Result[mIndex];
        mFound := True;
        Break;
      end;
    end;
  until not mFound;
end;

/// <summary>Liegt AChild in einer Marke des case-Zweigs ACaseItem? Marken stehen vor der Anweisung, dem letzten
/// Kind.</summary>
function InCaseLabel(ACaseItem, AChild: TSyntaxNode): Boolean;
begin
  Result := (AChild <> nil) and (ACaseItem.ChildCount > 0) and (ACaseItem[ACaseItem.ChildCount - 1] <> AChild);
end;

{ TResourceStrings }

class function TResourceStrings.NameFor(const AText: string): string;
var
  mWord: string;
  mCount: Integer;
begin
  Result := 'S';
  mCount := 0;
  for mWord in MeaningfulWords(SplitWords(AText)) do
  begin
    Result := Result + UpperCase(Copy(mWord, 1, 1)) + Copy(mWord, 2, MaxInt);
    Inc(mCount);
    if mCount = cMaxWords then
    begin
      Break;
    end;
  end;
  if Result = 'S' then
  begin
    Result := 'SText';
  end;
end;

class function TResourceStrings.UniqueName(const ABase: string; const ATaken: TArray<string>): string;
var
  mNumber: Integer;
begin
  Result := ABase;
  mNumber := 1;
  while MatchText(Result, ATaken) do
  begin
    Inc(mNumber);
    Result := ABase + IntToStr(mNumber);
  end;
end;

class function TResourceStrings.LiteralAt(const AText: string; const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition; out ALiteral: TResourceLiteral): Boolean;
var
  mIndex, mFirst, mLast: Integer;
  mInside: Boolean;
begin
  ALiteral := Default(TResourceLiteral);
  Result := False;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Kind <> TPascalTokenKind.StringLiteral then
    begin
      Continue;
    end;
    // Echt innerhalb: hinter dem öffnenden und vor dem schließenden Hochkomma.
    mInside := (ComparePositions(ATokens[mIndex].StartPos, APosition) < 0) and
      ((ComparePositions(APosition, ATokens[mIndex].EndPos) < 0) or not ATokens[mIndex].Terminated);
    if not mInside then
    begin
      Continue;
    end;
    if not ATokens[mIndex].Terminated then
    begin
      Exit;
    end;
    // Direkt angehängte Literale und Zeichenkonstanten gehören dazu: 'Zeile'#13#10'Zwei'.
    mFirst := mIndex;
    while (mFirst > 0) and (ATokens[mFirst - 1].Kind in [TPascalTokenKind.StringLiteral,
      TPascalTokenKind.CharLiteral]) and (TokenEnd(ATokens[mFirst - 1]) = ATokens[mFirst].Offset) do
    begin
      Dec(mFirst);
    end;
    mLast := mIndex;
    while (mLast < High(ATokens)) and (ATokens[mLast + 1].Kind in [TPascalTokenKind.StringLiteral,
      TPascalTokenKind.CharLiteral]) and (TokenEnd(ATokens[mLast]) = ATokens[mLast + 1].Offset) do
    begin
      Inc(mLast);
    end;
    ALiteral.Range := TTextRange.Create(ATokens[mFirst].StartPos, ATokens[mLast].EndPos);
    ALiteral.StartOffset := ATokens[mFirst].Offset;
    ALiteral.Source := Copy(AText, ATokens[mFirst].Offset + 1, TokenEnd(ATokens[mLast]) - ATokens[mFirst].Offset);
    if not TStringLiterals.PlainText(ALiteral.Source, ALiteral.Text) then
    begin
      Exit;
    end;
    Result := Length(ALiteral.Text) > 1;
    Exit;
  end;
end;

class function TResourceStrings.Allowed(ATree: TSyntaxTree; AOffset: Integer): Boolean;
var
  mNode, mChild: TSyntaxNode;
  mInBody: Boolean;
begin
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mNode := DeepestNode(ATree, AOffset);
  // Von innen nach außen; erst ein Anweisungsblock macht die Stelle zulässig.
  mInBody := False;
  mChild := nil;
  while mNode <> nil do
  begin
    case mNode.Kind of
      TSyntaxKind.ConstSection, TSyntaxKind.ConstDecl, TSyntaxKind.InlineConst, TSyntaxKind.Attribute,
      TSyntaxKind.Parameter, TSyntaxKind.Parameters, TSyntaxKind.PropertyDecl, TSyntaxKind.TypeSection,
      TSyntaxKind.TypeDecl, TSyntaxKind.SetConstructor, TSyntaxKind.RangeExpr, TSyntaxKind.ExportsClause,
      TSyntaxKind.AsmBlock, TSyntaxKind.VarDecl, TSyntaxKind.VarSection:
        if not mInBody then
        begin
          Exit;
        end;
      TSyntaxKind.CaseItem:
        if InCaseLabel(mNode, mChild) then
        begin
          Exit;
        end;
      TSyntaxKind.Block, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection:
        mInBody := True;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    mChild := mNode;
    mNode := mNode.Parent;
  end;
  Result := mInBody;
end;

class function TResourceStrings.Entries(const AText: string;
  const ATokens: TArray<TPascalToken>): TArray<TResourceEntry>;
var
  mIndex, mStop, mSection: Integer;
  mInInterface, mInSection: Boolean;
  mEntry: TResourceEntry;
begin
  Result := nil;
  mInInterface := False;
  mInSection := False;
  mSection := -1;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    TrackPart(ATokens[mIndex], mInInterface);
    if ATokens[mIndex].IsKeyword('resourcestring') then
    begin
      mInSection := True;
      mSection := ATokens[mIndex].StartPos.Line;
      mIndex := NextIndex(ATokens, mIndex);
      Continue;
    end;
    if mInSection then
    begin
      mStop := EntryStop(ATokens, mIndex);
      if mStop > High(ATokens) then
      begin
        Break;
      end;
      if mStop >= 0 then
      begin
        mEntry := EntryFrom(AText, ATokens, mIndex, mStop);
        mEntry.InInterface := mInInterface;
        mEntry.Section := mSection;
        Result := Result + [mEntry];
        mIndex := NextIndex(ATokens, mStop);
        Continue;
      end;
      mInSection := False;
    end;
    mIndex := NextIndex(ATokens, mIndex);
  end;
end;

class function TResourceStrings.SameText(const AEntries: TArray<TResourceEntry>; const AText: string;
  AInterface: Boolean; ABefore: Integer; out AEntry: TResourceEntry): Boolean;
var
  mEntry: TResourceEntry;
  mText: string;
begin
  for mEntry in AEntries do
  begin
    if (mEntry.InInterface = AInterface) and ((ABefore < 0) or (mEntry.Line < ABefore)) and
      TStringLiterals.PlainText(mEntry.Value, mText) and (mText = AText) then
    begin
      AEntry := mEntry;
      Exit(True);
    end;
  end;
  AEntry := Default(TResourceEntry);
  Result := False;
end;

class function TResourceStrings.Insertion(const AText: string; const ATokens: TArray<TPascalToken>;
  const APlace: TResourcePlace; const ADeclaration, ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  mLines: TArray<string>;
  mImplementation, mSectionLine, mLine: Integer;
  mIndent: string;
begin
  AEdit := Default(TTextEdit);
  mImplementation := ImplementationIndex(ATokens);
  if mImplementation < 0 then
  begin
    Exit(False);
  end;
  mLines := AText.Replace(#13, '').Split([#10]);
  // Erster passender Abschnitt; der neue Eintrag kommt hinter dessen letzten.
  mSectionLine := SectionLineAt(ATokens, APlace);
  if mSectionLine >= 0 then
  begin
    mLine := SectionEnd(Entries(AText, ATokens), mLines, mSectionLine, mIndent);
    AEdit := TTextEdit.Create(TTextRange.Create(LineEndOf(mLines, mLine), LineEndOf(mLines, mLine)),
      ALineBreak + mIndent + ADeclaration);
  end
  else if APlace.InInterface then
  begin
    // Neuer Abschnitt vor implementation.
    mLine := ATokens[mImplementation].StartPos.Line;
    AEdit := TTextEdit.Create(TTextRange.Create(TTextPosition.Create(mLine, 0), TTextPosition.Create(mLine, 0)),
      'resourcestring' + ALineBreak + '  ' + ADeclaration + ALineBreak + ALineBreak);
  end
  else
  begin
    // Neuer Abschnitt hinter implementation bzw. deren uses.
    mLine := AfterImplementationUses(ATokens, mImplementation);
    AEdit := TTextEdit.Create(TTextRange.Create(LineEndOf(mLines, mLine), LineEndOf(mLines, mLine)),
      ALineBreak + ALineBreak + 'resourcestring' + ALineBreak + '  ' + ADeclaration);
  end;
  Result := True;
end;

end.
