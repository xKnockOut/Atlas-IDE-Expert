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
    Method = 'atlas/expressionCompletion';
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
  Atlas.Text.Chars,
  Atlas.Text.Lines,
  Atlas.Common.Lsp.Positions;

const
  // LSP CompletionItemKind.Keyword und .Snippet; InsertTextFormat.Snippet.
  KindKeyword = 14;
  KindSnippet = 15;
  SnippetFormat = 2;

  // Zeilen, hinter die eine Anweisung gehört: Davor stünde sie außerhalb des Rumpfs oder zerrisse if/else.
  OpenerWords: array[0..5] of string = ('begin', 'else', 'then', 'do', 'repeat', 'try');

/// <summary>True, wenn ALine (ohne Einrückung) mit einem Wort aus OpenerWords beginnt.</summary>
function StartsWithOpener(const ALine: string): Boolean;
var
  Trimmed, Word: string;
  Index: Integer;
begin
  Trimmed := LowerCase(Trim(ALine));
  Index := 1;
  while (Index <= Length(Trimmed)) and TTextChars.IsIdentChar(Trimmed[Index]) do
    Inc(Index);
  Word := Copy(Trimmed, 1, Index - 1);
  for Index := Low(OpenerWords) to High(OpenerWords) do
    if Word = OpenerWords[Index] then
      Exit(True);
  Result := False;
end;

/// <summary>Was insertText ersetzt: textEdit.newText, sonst insertText, sonst label.</summary>
function InsertTextOf(AItem: TJSONObject; out AText: string): Boolean;
var
  Edit: TJSONObject;
begin
  Result := True;
  Edit := nil;
  if AItem.GetValue('textEdit') is TJSONObject then
    Edit := TJSONObject(AItem.GetValue('textEdit'));
  if Edit <> nil then
    Exit(Edit.TryGetValue<string>('newText', AText));
  if AItem.TryGetValue<string>('insertText', AText) then
    Exit;
  Result := AItem.TryGetValue<string>('label', AText);
end;

/// <summary>True, wenn ein textEdit von AItem genau an AStart beginnt oder keins da ist.</summary>
function EditStartsAt(AItem: TJSONObject; const AStart: TTextPosition): Boolean;
var
  Range: TTextRange;
begin
  if not (AItem.GetValue('textEdit') is TJSONObject) then
    Exit(True);
  Range := TLspPositions.ReadRange(TJSONObject(AItem.GetValue('textEdit')).GetValue('range'));
  Result := Range.StartPos = AStart;
end;

/// <summary>True, wenn AItem im Feld etwas bedeutet (siehe Kopf).</summary>
function Usable(AItem: TJSONObject; const AStart: TTextPosition): Boolean;
var
  Kind, Format: Integer;
begin
  Kind := 0;
  AItem.TryGetValue<Integer>('kind', Kind);
  Format := 0;
  AItem.TryGetValue<Integer>('insertTextFormat', Format);
  Result := (Kind <> KindKeyword) and (Kind <> KindSnippet) and (Format <> SnippetFormat) and
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
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspExpressionCompletion.Place(const ADocument: ITextDocument; AScopeLine: Integer;
  const AExpression: string): TExpressionPlacement;
var
  ScopeText, Indent, LineBreak: string;
  Line: Integer;
begin
  Line := AScopeLine;
  if Line >= ADocument.LineCount then
    Line := ADocument.LineCount - 1;
  if Line < 0 then
    Line := 0;
  ScopeText := ADocument.LineText(Line);
  Indent := TTextLines.IndentOf(ScopeText);
  LineBreak := TTextLines.LineBreakOf(ADocument.Text);
  Result := Default(TExpressionPlacement);
  // Mehrzeilige Ausdrücke aus dem Feld bleiben eine Zeile: Die Spalten der Schreibmarke gelten dann weiter.
  Result.Text := Indent + StringReplace(StringReplace(AExpression, #13, ' ', [rfReplaceAll]), #10, ' ',
    [rfReplaceAll]) + ';' + LineBreak;
  Result.Column := Length(Indent);
  if StartsWithOpener(ScopeText) and (Line + 1 < ADocument.LineCount) then
    Result.Line := Line + 1
  else
    Result.Line := Line;
  Result.Change := TTextChange.Ranged(TTextRange.Create(Result.Line, 0, Result.Line, 0), Result.Text);
end;

class function TLspExpressionCompletion.PrefixAt(const AExpression: string; ACharacter: Integer): string;
var
  Start, Stop: Integer;
begin
  Stop := ACharacter;
  if Stop > Length(AExpression) then
    Stop := Length(AExpression);
  if Stop < 0 then
    Stop := 0;
  Start := Stop;
  while (Start > 0) and TTextChars.IsIdentChar(AExpression[Start]) do
    Dec(Start);
  Result := Copy(AExpression, Start + 1, Stop - Start);
end;

class function TLspExpressionCompletion.Filter(const ACompletion: TJSONValue; const APrefix: string;
  const AStart: TTextPosition): TJSONObject;
var
  Source: TJSONArray;
  Items: TJSONArray;
  Value: TJSONValue;
  Item, Entry: TJSONObject;
  Text, Detail: string;
  Kind: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('prefix', APrefix);
  Items := TJSONArray.Create;
  Result.AddPair('items', Items);
  Source := nil;
  if ACompletion is TJSONObject then
    TJSONObject(ACompletion).TryGetValue<TJSONArray>('items', Source)
  else if ACompletion is TJSONArray then
    Source := TJSONArray(ACompletion);
  if Source = nil then
    Exit;
  for Value in Source do
  begin
    if not (Value is TJSONObject) then
      Continue;
    Item := TJSONObject(Value);
    if not (Usable(Item, AStart) and InsertTextOf(Item, Text)) then
      Continue;
    Entry := TJSONObject.Create;
    if not Item.TryGetValue<string>('label', Detail) then
      Detail := Text;
    Entry.AddPair('label', Detail);
    Kind := 0;
    Item.TryGetValue<Integer>('kind', Kind);
    Entry.AddPair('kind', TJSONNumber.Create(Kind));
    Detail := '';
    if Item.TryGetValue<string>('detail', Detail) then
      Entry.AddPair('detail', Detail);
    Entry.AddPair('insertText', Text);
    Items.AddElement(Entry);
  end;
end;

function TLspExpressionCompletion.Complete(const ADocument: ITextDocument; AScopeLine: Integer;
  const AExpression: string; ACharacter: Integer; const ACancellation: IJsonRpcCancellationToken): TJSONObject;
var
  Placement: TExpressionPlacement;
  Snapshot: ITextDocument;
  Prefix: string;
  Caret, Start: TTextPosition;
  Character: Integer;
  Completion: TJSONValue;
begin
  Placement := Place(ADocument, AScopeLine, AExpression);
  // Eigene Momentaufnahme: Der Dokumentspeicher und der Syntaxbaum des Editors bleiben unberührt.
  Snapshot := ADocument.ApplyChanges([Placement.Change], ADocument.Version);
  Character := ACharacter;
  if Character > Length(AExpression) then
    Character := Length(AExpression);
  if Character < 0 then
    Character := 0;
  Prefix := PrefixAt(AExpression, Character);
  Caret := TTextPosition.Create(Placement.Line, Placement.Column + Character);
  Start := TTextPosition.Create(Placement.Line, Caret.Character - Length(Prefix));
  Completion := FCompletion.Complete(Snapshot, ADocument.Uri, Caret, ACancellation);
  try
    Result := Filter(Completion, Prefix, Start);
  finally
    Completion.Free;
  end;
end;

function TLspExpressionCompletion.Handle(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri, Expression: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Character: Integer;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue) and
    TJSONObject(AParams).TryGetValue<string>('expression', Expression)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri", "position" und "expression" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Character := Length(Expression);
  TJSONObject(AParams).TryGetValue<Integer>('character', Character);
  Result := Complete(Document, TLspPositions.ReadPosition(PositionValue).Line, Expression, Character, ACancellation);
end;

end.
