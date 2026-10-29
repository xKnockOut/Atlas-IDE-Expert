unit Atlas.Common.Lsp.CompletionDebugDisplay;

// Vervollständigung in Wertdarstellungen (#854): Steht der Cursor in einer
// Regel über einer Typdeklaration (// atlas-debug: '…', [AtlasDebugDisplay('…')])
// hinter einer offenen geschweiften Klammer, bzw. in der Namensliste von
// // atlas-debug-children: oder [AtlasDebugChildren('…')], bietet Atlas die
// Felder, Eigenschaften und Methoden des Typs und seiner Vorfahren an (der
// eigene Typ zuerst). Die Antwort ist dann ausschließlich, auch ohne Einträge.

interface

uses
  Atlas.Common.Lsp.CompletionRequest;

type
  {$SCOPEDENUMS ON}
  TDebugDisplayCompletionPlace = (None, Template, Children);
  {$SCOPEDENUMS OFF}

  TCompletionDebugDisplay = class
  public
    /// <summary>Was vor ACharacter (0-basiert) in ALine steht: offener Platzhalter ab ATemplateColumn bzw. Name in
    /// der Liste der Unterelemente. APrefix ist der angefangene Name, AStart seine Spalte.</summary>
    class function PrefixAt(const ALine: string; ACharacter, ATemplateColumn: Integer;
      APlace: TDebugDisplayCompletionPlace; out AStart: Integer; out APrefix: string): Boolean; static;
    /// <summary>Einträge für die Regel in der Zeile des Cursors; False außerhalb einer Regel.</summary>
    class function Items(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Character,
  Atlas.Text.DebugDisplay,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.TypeMembers,
  Atlas.Common.Lsp.CompletionCollector;

function IsNameChar(AChar: Char): Boolean;
begin
  Result := (AChar = '_') or AChar.IsLetterOrDigit;
end;

class function TCompletionDebugDisplay.PrefixAt(const ALine: string; ACharacter, ATemplateColumn: Integer;
  APlace: TDebugDisplayCompletionPlace; out AStart: Integer; out APrefix: string): Boolean;
var
  Index, Open: Integer;
  Before: Char;
begin
  AStart := ACharacter;
  APrefix := '';
  Result := False;
  if (ACharacter < 0) or (ACharacter > Length(ALine)) then
    Exit;
  // Angefangener Name links vom Cursor.
  while (AStart > 0) and IsNameChar(ALine[AStart]) do
    Dec(AStart);
  APrefix := Copy(ALine, AStart + 1, ACharacter - AStart);
  if APlace = TDebugDisplayCompletionPlace.Template then
  begin
    // Offene Klammer zwischen Vorlagenbeginn und Name; {{ ist keine.
    Open := -1;
    Index := ATemplateColumn + 1;
    while Index <= AStart do
    begin
      if (ALine[Index] = '{') and (Index < AStart) and (ALine[Index + 1] = '{') then
        Inc(Index)
      else if ALine[Index] = '{' then
        Open := Index
      else if ALine[Index] = '}' then
        Open := -1;
      Inc(Index);
    end;
    Result := (Open > 0) and (Open = AStart);
  end
  else if APlace = TDebugDisplayCompletionPlace.Children then
  begin
    Index := AStart;
    while (Index > 0) and (ALine[Index] = ' ') do
      Dec(Index);
    Before := #0;
    if Index > 0 then
      Before := ALine[Index];
    Result := CharInSet(Before, [':', ',', '(', '''']);
  end;
end;

function MemberKind(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.Property_:
      Result := KindProperty;
    TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_:
      Result := KindMethod;
    TIndexSymbolKind.Variable:
      Result := KindVariable;
  else
    Result := KindField;
  end;
end;

class function TCompletionDebugDisplay.Items(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  Lines: TArray<string>;
  Line, Prefix: string;
  Local: TUnitIndex;
  Symbol, Target: TIndexSymbol;
  Source: TDebugDisplaySource;
  Place: TDebugDisplayCompletionPlace;
  Members: TArray<TTypeMember>;
  Member: TTypeMember;
  Item: TCompletionItem;
  Start, Column: Integer;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  Lines := ARequest.Lines;
  if (ARequest.Position.Line < 0) or (ARequest.Position.Line > High(Lines)) then
    Exit;
  Line := Lines[ARequest.Position.Line];
  if not (ContainsText(Line, 'atlas-debug') or ContainsText(Line, 'AtlasDebug')) then
    Exit;
  if ARequest.Tree <> nil then
    Local := TIndexExtractor.Extract(ARequest.Tree, ARequest.FileName)
  else
    Local := TIndexExtractor.ExtractText(ARequest.Text, ARequest.FileName, nil);
  // Der Typ, zu dessen Regel die Zeile gehört.
  Place := TDebugDisplayCompletionPlace.None;
  Column := 0;
  Target := Default(TIndexSymbol);
  for Symbol in Local.Symbols do
  begin
    if not (Symbol.Kind in TTypeMembers.RuleKinds) or (Symbol.FileName <> '') or
      not TDebugDisplayText.RuleAbove(Lines, Symbol.Range.StartPos.Line, Source) then
      Continue;
    if Source.HasTemplate and (Source.TemplateLine = ARequest.Position.Line) then
    begin
      Place := TDebugDisplayCompletionPlace.Template;
      Column := Source.TemplateColumn;
    end
    else if (Source.Children <> nil) and (Source.ChildrenLine = ARequest.Position.Line) then
      Place := TDebugDisplayCompletionPlace.Children
    else
      Continue;
    Target := Symbol;
    Break;
  end;
  if (Place = TDebugDisplayCompletionPlace.None) or
    not PrefixAt(Line, ARequest.Position.Character, Column, Place, Start, Prefix) then
    Exit;
  Result := True;
  TTypeMembers.Collect(Local, ARequest.Index, Target, Members);
  for Member in Members do
  begin
    if (Prefix <> '') and not StartsText(Prefix, Member.Name) then
      Continue;
    Item := Default(TCompletionItem);
    Item.Name := Member.Name;
    Item.Detail := Member.TypeName;
    Item.Kind := MemberKind(Member.Kind);
    Item.Container := Member.Container;
    Item.Depth := Member.Depth;
    Item.HasTextEdit := True;
    Item.TextEdit := TTextEdit.Create(TTextRange.Create(ARequest.Position.Line, Start, ARequest.Position.Line,
      ARequest.Position.Character), Member.Name);
    AItems.Items := AItems.Items + [Item];
  end;
end;

end.
