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

/// <summary>Öffnet eine Klammer zwischen Vorlagenbeginn ATemplateColumn und dem Namen ab AStart den Platzhalter?
/// {{ ist keine.</summary>
function TemplateOpen(const ALine: string; ATemplateColumn, AStart: Integer): Boolean;
var
  mIndex, mOpen: Integer;
begin
  mOpen := -1;
  mIndex := ATemplateColumn + 1;
  while mIndex <= AStart do
  begin
    if (ALine[mIndex] = '{') and (mIndex < AStart) and (ALine[mIndex + 1] = '{') then
    begin
      Inc(mIndex);
    end
    else if ALine[mIndex] = '{' then
    begin
      mOpen := mIndex;
    end
    else if ALine[mIndex] = '}' then
    begin
      mOpen := -1;
    end;
    Inc(mIndex);
  end;
  Result := (mOpen > 0) and (mOpen = AStart);
end;

/// <summary>Steht vor dem Namen ab AStart ein Trenner der Namensliste (Doppelpunkt, Komma, Klammer, Hochkomma)?
/// </summary>
function ChildrenSlot(const ALine: string; AStart: Integer): Boolean;
var
  mIndex: Integer;
  mBefore: Char;
begin
  mIndex := AStart;
  while (mIndex > 0) and (ALine[mIndex] = ' ') do
  begin
    Dec(mIndex);
  end;
  mBefore := #0;
  if mIndex > 0 then
  begin
    mBefore := ALine[mIndex];
  end;
  Result := CharInSet(mBefore, [':', ',', '(', '''']);
end;

class function TCompletionDebugDisplay.PrefixAt(const ALine: string; ACharacter, ATemplateColumn: Integer;
  APlace: TDebugDisplayCompletionPlace; out AStart: Integer; out APrefix: string): Boolean;
begin
  AStart := ACharacter;
  APrefix := '';
  Result := False;
  if (ACharacter < 0) or (ACharacter > Length(ALine)) then
  begin
    Exit;
  end;
  // Angefangener Name links vom Cursor.
  while (AStart > 0) and IsNameChar(ALine[AStart]) do
  begin
    Dec(AStart);
  end;
  APrefix := Copy(ALine, AStart + 1, ACharacter - AStart);
  if APlace = TDebugDisplayCompletionPlace.Template then
  begin
    Result := TemplateOpen(ALine, ATemplateColumn, AStart);
  end
  else if APlace = TDebugDisplayCompletionPlace.Children then
  begin
    Result := ChildrenSlot(ALine, AStart);
  end;
end;

function MemberKind(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.Property_:
      Result := cKindProperty;
    TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_:
      Result := cKindMethod;
    TIndexSymbolKind.Variable:
      Result := cKindVariable;
  else
    Result := cKindField;
  end;
end;

/// <summary>Deklarationen der Datei der Anfrage, aus dem Baum oder dem Text.</summary>
function LocalIndex(ARequest: TCompletionRequest): TUnitIndex;
begin
  if ARequest.Tree <> nil then
  begin
    Result := TIndexExtractor.Extract(ARequest.Tree, ARequest.FileName);
  end
  else
  begin
    Result := TIndexExtractor.ExtractText(ARequest.Text, ARequest.FileName, nil);
  end;
end;

/// <summary>Wo in der Regel ASource die Zeile ALine liegt: in der Vorlage (AColumn ihr Beginn), in der Namensliste
/// oder nicht in der Regel.</summary>
function PlaceIn(const ASource: TDebugDisplaySource; ALine: Integer;
  out AColumn: Integer): TDebugDisplayCompletionPlace;
begin
  AColumn := 0;
  Result := TDebugDisplayCompletionPlace.None;
  if ASource.HasTemplate and (ASource.TemplateLine = ALine) then
  begin
    Result := TDebugDisplayCompletionPlace.Template;
    AColumn := ASource.TemplateColumn;
  end
  else if (ASource.Children <> nil) and (ASource.ChildrenLine = ALine) then
  begin
    Result := TDebugDisplayCompletionPlace.Children;
  end;
end;

/// <summary>Der Typ in ALocal, zu dessen Regel die Zeile ALine gehört, und die Stelle darin; False ohne.</summary>
function RuleTarget(const ALocal: TUnitIndex; const ALines: TArray<string>; ALine: Integer;
  out APlace: TDebugDisplayCompletionPlace; out AColumn: Integer; out ATarget: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
  mSource: TDebugDisplaySource;
begin
  APlace := TDebugDisplayCompletionPlace.None;
  AColumn := 0;
  ATarget := Default(TIndexSymbol);
  for mSymbol in ALocal.Symbols do
  begin
    if not (mSymbol.Kind in TTypeMembers.cRuleKinds) or (mSymbol.FileName <> '') or
      not TDebugDisplayText.RuleAbove(ALines, mSymbol.Range.StartPos.Line, mSource) then
    begin
      Continue;
    end;
    APlace := PlaceIn(mSource, ALine, AColumn);
    if APlace <> TDebugDisplayCompletionPlace.None then
    begin
      ATarget := mSymbol;
      Break;
    end;
  end;
  Result := APlace <> TDebugDisplayCompletionPlace.None;
end;

/// <summary>Eintrag für AMember; ersetzt den Namen ab Spalte AStart bis zum Cursor.</summary>
function MemberItem(ARequest: TCompletionRequest; const AMember: TTypeMember; AStart: Integer): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := AMember.Name;
  Result.Detail := AMember.TypeName;
  Result.Kind := MemberKind(AMember.Kind);
  Result.Container := AMember.Container;
  Result.Depth := AMember.Depth;
  Result.HasTextEdit := True;
  Result.TextEdit := TTextEdit.Create(TTextRange.Create(ARequest.Position.Line, AStart, ARequest.Position.Line,
    ARequest.Position.Character), AMember.Name);
end;

class function TCompletionDebugDisplay.Items(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  mLines: TArray<string>;
  mLine, mPrefix: string;
  mLocal: TUnitIndex;
  mTarget: TIndexSymbol;
  mPlace: TDebugDisplayCompletionPlace;
  mMembers: TArray<TTypeMember>;
  mMember: TTypeMember;
  mStart, mColumn: Integer;
begin
  AItems := Default(TCompletionItems);
  Result := False;
  mLines := ARequest.Lines;
  if (ARequest.Position.Line < 0) or (ARequest.Position.Line > High(mLines)) then
  begin
    Exit;
  end;
  mLine := mLines[ARequest.Position.Line];
  if not (ContainsText(mLine, 'atlas-debug') or ContainsText(mLine, 'AtlasDebug')) then
  begin
    Exit;
  end;
  mLocal := LocalIndex(ARequest);
  if not RuleTarget(mLocal, mLines, ARequest.Position.Line, mPlace, mColumn, mTarget) or
    not PrefixAt(mLine, ARequest.Position.Character, mColumn, mPlace, mStart, mPrefix) then
  begin
    Exit;
  end;
  Result := True;
  TTypeMembers.Collect(mLocal, ARequest.Index, mTarget, mMembers);
  for mMember in mMembers do
  begin
    if (mPrefix = '') or StartsText(mPrefix, mMember.Name) then
    begin
      AItems.Items := AItems.Items + [MemberItem(ARequest, mMember, mStart)];
    end;
  end;
end;

end.
