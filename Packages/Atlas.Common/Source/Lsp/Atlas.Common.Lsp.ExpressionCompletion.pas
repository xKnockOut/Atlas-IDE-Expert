unit Atlas.Common.Lsp.ExpressionCompletion;

// Vervollständigung für Ausdrücke in den Debug-Dialogen (#538): Anfrage
// atlas/expressionCompletion mit textDocument, position (Zeile 0-basiert:
// Ausführungspunkt oder Zeile des Haltepunkts), expression (Text des Felds)
// und character (Schreibmarke im Feld, 0-basiert). Der Server fügt den
// Ausdruck als eigene Anweisung "Ausdruck;" in eine Momentaufnahme des
// Dokuments ein, vor der Zeile oder, wenn sie mit begin, else, then, do,
// repeat oder try beginnt, dahinter. So gelten dieselben Namen wie im Editor:
// lokale Variablen und Parameter der Routine, Felder von Self, Units aus uses,
// nach "." die Elemente. Die Vervollständigung des Editors (TLspCompletion)
// liefert die Einträge; Schlüsselwörter, Vorlagen und Einträge mit weiteren
// Änderungen (uses ergänzen, Befehle) fallen weg, weil sie im Feld nichts
// bedeuten. Antwort:
//   { prefix, items: [{ label, kind, detail, insertText }] }
// prefix ist der Bezeichner vor der Schreibmarke, den insertText ersetzt.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Completion;

type
  /// <summary>Wo der Ausdruck in der Momentaufnahme steht.</summary>
  TExpressionPlacement = record
    /// <summary>Zeile der eingefügten Anweisung.</summary>
    Line: Integer;
    /// <summary>Spalte, an der der Ausdruck beginnt (Einrückung der Bezugszeile).</summary>
    Column: Integer;
    /// <summary>Eingefügter Text samt Zeilenumbruch.</summary>
    Text: string;
    /// <summary>Änderung für ITextDocument.ApplyChanges.</summary>
    Change: TTextChange;
  end;

  TLspExpressionCompletion = class
  public const
    cMethod = 'atlas/expressionCompletion';
  private
    FStore: IDocumentStore;
    FCompletion: TLspCompletion;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    /// <summary>ACompletion gehört dem Aufrufer und muss länger leben.</summary>
    constructor Create(const AStore: IDocumentStore; ACompletion: TLspCompletion);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Wohin AExpression für die Bezugszeile AScopeLine von ADocument kommt.</summary>
    class function Place(const ADocument: ITextDocument; AScopeLine: Integer;
      const AExpression: string): TExpressionPlacement; static;
    /// <summary>Bezeichner vor ACharacter (0-basiert) in AExpression.</summary>
    class function PrefixAt(const AExpression: string; ACharacter: Integer): string; static;
    /// <summary>Antwort wie im Kopf aus der CompletionList ACompletion; AStart ist die Position, an der prefix
    /// in der Momentaufnahme beginnt. Gehört dem Aufrufer.</summary>
    class function Filter(const ACompletion: TJSONValue; const APrefix: string;
      const AStart: TTextPosition): TJSONObject; static;
    /// <summary>Antwort für ADocument; gehört dem Aufrufer.</summary>
    function Complete(const ADocument: ITextDocument; AScopeLine: Integer; const AExpression: string;
      ACharacter: Integer; const ACancellation: IJsonRpcCancellationToken): TJSONObject;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Chars,
  Atlas.Text.Lines,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TExpressionCompletionText = (FieldsTextDocumentUriPositionAnd);

const
  cTexts: array[TExpressionCompletionText] of TAtlasText = (
    (De: 'Felder "textDocument.uri", "position" und "expression" fehlen in ';
     En: 'Fields "textDocument.uri", "position" and "expression" missing in '));

{$SCOPEDENUMS OFF}

const
  // LSP CompletionItemKind.Keyword und .Snippet; InsertTextFormat.Snippet.
  cKindKeyword = 14;
  cKindSnippet = 15;
  cSnippetFormat = 2;

  // Zeilen, hinter die eine Anweisung gehört: Davor stünde sie außerhalb des Rumpfs oder zerrisse if/else.
  cOpenerWords: array[0..5] of string = ('begin', 'else', 'then', 'do', 'repeat', 'try');

/// <summary>True, wenn ALine (ohne Einrückung) mit einem Wort aus OpenerWords beginnt.</summary>
function StartsWithOpener(const ALine: string): Boolean;
var
  mTrimmed, mWord: string;
  mIndex: Integer;
begin
  mTrimmed := LowerCase(Trim(ALine));
  mIndex := 1;
  while (mIndex <= Length(mTrimmed)) and TTextChars.IsIdentChar(mTrimmed[mIndex]) do
  begin
    Inc(mIndex);
  end;
  mWord := Copy(mTrimmed, 1, mIndex - 1);
  for mIndex := Low(cOpenerWords) to High(cOpenerWords) do
  begin
    if mWord = cOpenerWords[mIndex] then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Was insertText ersetzt: textEdit.newText, sonst insertText, sonst label.</summary>
function InsertTextOf(AItem: TJSONObject; out AText: string): Boolean;
var
  mEdit: TJSONObject;
begin
  Result := True;
  mEdit := nil;
  if AItem.GetValue('textEdit') is TJSONObject then
  begin
    mEdit := TJSONObject(AItem.GetValue('textEdit'));
  end;
  if mEdit <> nil then
  begin
    Exit(mEdit.TryGetValue<string>('newText', AText));
  end;
  if AItem.TryGetValue<string>('insertText', AText) then
  begin
    Exit;
  end;
  Result := AItem.TryGetValue<string>('label', AText);
end;

/// <summary>True, wenn ein textEdit von AItem genau an AStart beginnt oder keins da ist.</summary>
function EditStartsAt(AItem: TJSONObject; const AStart: TTextPosition): Boolean;
var
  mRange: TTextRange;
begin
  if not (AItem.GetValue('textEdit') is TJSONObject) then
  begin
    Exit(True);
  end;
  mRange := TLspPositions.ReadRange(TJSONObject(AItem.GetValue('textEdit')).GetValue('range'));
  Result := mRange.StartPos = AStart;
end;

/// <summary>True, wenn AItem im Feld etwas bedeutet (siehe Kopf).</summary>
function Usable(AItem: TJSONObject; const AStart: TTextPosition): Boolean;
var
  mKind, mFormat: Integer;
begin
  mKind := 0;
  AItem.TryGetValue<Integer>('kind', mKind);
  mFormat := 0;
  AItem.TryGetValue<Integer>('insertTextFormat', mFormat);
  Result := (mKind <> cKindKeyword) and (mKind <> cKindSnippet) and (mFormat <> cSnippetFormat) and
    (AItem.GetValue('additionalTextEdits') = nil) and (AItem.GetValue('command') = nil) and
    EditStartsAt(AItem, AStart);
end;

{ TLspExpressionCompletion }

constructor TLspExpressionCompletion.Create(const AStore: IDocumentStore; ACompletion: TLspCompletion);
begin
  inherited Create;
  FStore := AStore;
  FCompletion := ACompletion;
end;

procedure TLspExpressionCompletion.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, Handle);
end;

class function TLspExpressionCompletion.Place(const ADocument: ITextDocument; AScopeLine: Integer;
  const AExpression: string): TExpressionPlacement;
var
  mScopeText, mIndent, mLineBreak: string;
  mLine: Integer;
begin
  mLine := AScopeLine;
  if mLine >= ADocument.LineCount then
  begin
    mLine := ADocument.LineCount - 1;
  end;
  if mLine < 0 then
  begin
    mLine := 0;
  end;
  mScopeText := ADocument.LineText(mLine);
  mIndent := TTextLines.IndentOf(mScopeText);
  mLineBreak := TTextLines.LineBreakOf(ADocument.Text);
  Result := Default(TExpressionPlacement);
  // Mehrzeilige Ausdrücke aus dem Feld bleiben eine Zeile: Die Spalten der Schreibmarke gelten dann weiter.
  Result.Text := mIndent + StringReplace(StringReplace(AExpression, #13, ' ', [rfReplaceAll]), #10, ' ',
    [rfReplaceAll]) + ';' + mLineBreak;
  Result.Column := Length(mIndent);
  if StartsWithOpener(mScopeText) and (mLine + 1 < ADocument.LineCount) then
  begin
    Result.Line := mLine + 1;
  end
  else
  begin
    Result.Line := mLine;
  end;
  Result.Change := TTextChange.Ranged(TTextRange.Create(Result.Line, 0, Result.Line, 0), Result.Text);
end;

class function TLspExpressionCompletion.PrefixAt(const AExpression: string; ACharacter: Integer): string;
var
  mStart, mStop: Integer;
begin
  mStop := ACharacter;
  if mStop > Length(AExpression) then
  begin
    mStop := Length(AExpression);
  end;
  if mStop < 0 then
  begin
    mStop := 0;
  end;
  mStart := mStop;
  while (mStart > 0) and TTextChars.IsIdentChar(AExpression[mStart]) do
  begin
    Dec(mStart);
  end;
  Result := Copy(AExpression, mStart + 1, mStop - mStart);
end;

class function TLspExpressionCompletion.Filter(const ACompletion: TJSONValue; const APrefix: string;
  const AStart: TTextPosition): TJSONObject;
var
  mSource: TJSONArray;
  mItems: TJSONArray;
  mValue: TJSONValue;
  mItem, mEntry: TJSONObject;
  mText, mDetail: string;
  mKind: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('prefix', APrefix);
  mItems := TJSONArray.Create;
  Result.AddPair('items', mItems);
  mSource := nil;
  if ACompletion is TJSONObject then
  begin
    TJSONObject(ACompletion).TryGetValue<TJSONArray>('items', mSource);
  end
  else if ACompletion is TJSONArray then
  begin
    mSource := TJSONArray(ACompletion);
  end;
  if mSource = nil then
  begin
    Exit;
  end;
  for mValue in mSource do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mItem := TJSONObject(mValue);
    if not (Usable(mItem, AStart) and InsertTextOf(mItem, mText)) then
    begin
      Continue;
    end;
    mEntry := TJSONObject.Create;
    if not mItem.TryGetValue<string>('label', mDetail) then
    begin
      mDetail := mText;
    end;
    mEntry.AddPair('label', mDetail);
    mKind := 0;
    mItem.TryGetValue<Integer>('kind', mKind);
    mEntry.AddPair('kind', TJSONNumber.Create(mKind));
    mDetail := '';
    if mItem.TryGetValue<string>('detail', mDetail) then
    begin
      mEntry.AddPair('detail', mDetail);
    end;
    mEntry.AddPair('insertText', mText);
    mItems.AddElement(mEntry);
  end;
end;

function TLspExpressionCompletion.Complete(const ADocument: ITextDocument; AScopeLine: Integer;
  const AExpression: string; ACharacter: Integer; const ACancellation: IJsonRpcCancellationToken): TJSONObject;
var
  mPlacement: TExpressionPlacement;
  mSnapshot: ITextDocument;
  mPrefix: string;
  mCaret, mStart: TTextPosition;
  mCharacter: Integer;
  mCompletion: TJSONValue;
begin
  mPlacement := Place(ADocument, AScopeLine, AExpression);
  // Eigene Momentaufnahme: Der Dokumentspeicher und der Syntaxbaum des Editors bleiben unberührt.
  mSnapshot := ADocument.ApplyChanges([mPlacement.Change], ADocument.Version);
  mCharacter := ACharacter;
  if mCharacter > Length(AExpression) then
  begin
    mCharacter := Length(AExpression);
  end;
  if mCharacter < 0 then
  begin
    mCharacter := 0;
  end;
  mPrefix := PrefixAt(AExpression, mCharacter);
  mCaret := TTextPosition.Create(mPlacement.Line, mPlacement.Column + mCharacter);
  mStart := TTextPosition.Create(mPlacement.Line, mCaret.Character - Length(mPrefix));
  mCompletion := FCompletion.Complete(mSnapshot, ADocument.Uri, mCaret, ACancellation);
  try
    Result := Filter(mCompletion, mPrefix, mStart);
  finally
    mCompletion.Free;
  end;
end;

function TLspExpressionCompletion.Handle(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri, mExpression: string;
  mPositionValue: TJSONValue;
  mDocument: ITextDocument;
  mCharacter: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue) and
    TJSONObject(AParams).TryGetValue<string>('expression', mExpression)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TExpressionCompletionText.FieldsTextDocumentUriPositionAnd].Text + cMethod);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  mCharacter := Length(mExpression);
  TJSONObject(AParams).TryGetValue<Integer>('character', mCharacter);
  Result := Complete(mDocument, TLspPositions.ReadPosition(mPositionValue).Line, mExpression, mCharacter,
    ACancellation);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.ExpressionCompletion', cTexts);

end.
