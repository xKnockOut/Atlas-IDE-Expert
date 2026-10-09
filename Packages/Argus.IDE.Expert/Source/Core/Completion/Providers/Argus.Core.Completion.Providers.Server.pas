unit Argus.Core.Completion.Providers.Server;

// Standardquelle der Vervollständigung (#408): der Argus-Server über die
// LSP-Sitzung des Plugins (ADR 0006). Prepare gleicht im Hauptthread den
// Editortext ab (Sync), Fetch fragt textDocument/completion im Hintergrund an
// und übersetzt die LSP-Einträge. Die Zusatzfelder aus #405 (Sichtbarkeit,
// deklarierende Klasse, Direktiven ...) kommen später über "data" dazu.
//
// Lebensdauer: Die Sitzung gehört dem Aufrufer. Bevor er sie freigibt (Neustart
// des Servers, Entladen), muss er Shutdown aufrufen; das wartet auf laufende Anfragen.

interface

uses
  System.SysUtils,
  System.JSON,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Internals.Async,
  Argus.Core.Lsp.Session;

type
  /// <summary>Aktuelle Sitzung oder nil, wenn kein Server verfügbar ist. Im Hauptthread aufgerufen.</summary>
  TArgusSessionFunc = reference to function: TLspSession;

  TArgusServerCompletionProvider = class(TArgusAsyncCompletionProvider)
  public const
    DefaultTimeoutMs = 2000;
  private
    FSession: TArgusSessionFunc;
    FTimeoutMs: Cardinal;
  protected
    function Prepare(const AContext: TArgusContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TArgusContext; AData: TObject;
      const ACancelled: TArgusCancelledFunc): TArgusCompletionItems; override;
  public
    constructor Create(const ASession: TArgusSessionFunc; ATimeoutMs: Cardinal = DefaultTimeoutMs);
    /// <summary>LSP-CompletionItemKind → Art des Eintrags.</summary>
    class function KindOf(ALspKind: Integer): TArgusItemKind; static;
    /// <summary>Ein CompletionItem des LSP; ARank ist seine Stelle in der Antwort.</summary>
    class function ItemFromLsp(AItem: TJSONObject; ARank: Integer): TArgusCompletionItem; static;
    /// <summary>Antwort auf textDocument/completion: CompletionList, CompletionItem[] oder null.</summary>
    class function ItemsFromLsp(AResponse: TJSONValue): TArgusCompletionItems; static;
  end;

implementation

uses
  System.Generics.Collections;

{ TArgusServerCompletionProvider }

constructor TArgusServerCompletionProvider.Create(const ASession: TArgusSessionFunc; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FSession := ASession;
  FTimeoutMs := ATimeoutMs;
end;

class function TArgusServerCompletionProvider.KindOf(ALspKind: Integer): TArgusItemKind;
begin
  case ALspKind of
    2: Result := TArgusItemKind.Method;
    3: Result := TArgusItemKind.Function_;
    4: Result := TArgusItemKind.Constructor_;
    5: Result := TArgusItemKind.Field;
    6: Result := TArgusItemKind.Variable;
    7: Result := TArgusItemKind.Class_;
    8: Result := TArgusItemKind.Interface_;
    9: Result := TArgusItemKind.Unit_;
    10: Result := TArgusItemKind.Property_;
    13: Result := TArgusItemKind.Enum;
    14: Result := TArgusItemKind.Keyword;
    15: Result := TArgusItemKind.Snippet;
    20: Result := TArgusItemKind.EnumMember;
    21: Result := TArgusItemKind.Constant;
    22: Result := TArgusItemKind.Record_;
    23: Result := TArgusItemKind.Event;
    25: Result := TArgusItemKind.Type_;
  else
    Result := TArgusItemKind.Unknown;
  end;
end;

function EditFromLsp(AEdit: TJSONObject; out AResult: TArgusTextEdit): Boolean;
begin
  AResult := Default(TArgusTextEdit);
  Result := AEdit.TryGetValue<Integer>('range.start.line', AResult.StartLine) and
    AEdit.TryGetValue<Integer>('range.start.character', AResult.StartCharacter) and
    AEdit.TryGetValue<Integer>('range.end.line', AResult.EndLine) and
    AEdit.TryGetValue<Integer>('range.end.character', AResult.EndCharacter) and
    AEdit.TryGetValue<string>('newText', AResult.NewText);
end;

class function TArgusServerCompletionProvider.ItemFromLsp(AItem: TJSONObject; ARank: Integer): TArgusCompletionItem;
var
  Documentation, Edits, Value: TJSONValue;
  Edit: TArgusTextEdit;
begin
  Result := Default(TArgusCompletionItem);
  Result.Name := AItem.GetValue<string>('label', '');
  Result.Kind := KindOf(AItem.GetValue<Integer>('kind', 0));
  Result.Signature := AItem.GetValue<string>('detail', '');
  Result.InsertText := AItem.GetValue<string>('insertText', '');
  Result.FilterText := AItem.GetValue<string>('filterText', '');
  Result.Rank := ARank;
  // documentation: string oder MarkupContent.
  Documentation := AItem.GetValue('documentation');
  if Documentation is TJSONString then
    Result.Documentation := TJSONString(Documentation).Value
  else if Documentation is TJSONObject then
    Result.Documentation := TJSONObject(Documentation).GetValue<string>('value', '');
  Edits := AItem.GetValue('additionalTextEdits');
  if Edits is TJSONArray then
    for Value in TJSONArray(Edits) do
      if (Value is TJSONObject) and EditFromLsp(TJSONObject(Value), Edit) then
        Result.AdditionalEdits := Result.AdditionalEdits + [Edit];
  // Bis #405 "Unit eingebunden" liefert: Ein Eintrag mit uses-Ergänzung (#180) kommt aus
  // einer noch nicht eingebundenen Unit.
  Result.UnitUsed := Length(Result.AdditionalEdits) = 0;
end;

class function TArgusServerCompletionProvider.ItemsFromLsp(AResponse: TJSONValue): TArgusCompletionItems;
var
  Items: TJSONValue;
  Index: Integer;
begin
  Result := nil;
  if AResponse is TJSONObject then
    Items := TJSONObject(AResponse).GetValue('items')
  else
    Items := AResponse;
  if not (Items is TJSONArray) then
    Exit;
  for Index := 0 to TJSONArray(Items).Count - 1 do
    if TJSONArray(Items).Items[Index] is TJSONObject then
      Result := Result + [ItemFromLsp(TJSONObject(TJSONArray(Items).Items[Index]), Index)];
end;

function TArgusServerCompletionProvider.Prepare(const AContext: TArgusContext; out AData: TObject): Boolean;
var
  Session: TLspSession;
begin
  AData := nil;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  Result := (Session <> nil) and (AContext.FileName <> '');
  if not Result then
    Exit;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  Session.Sync(AContext.FileName, AContext.Text);
  AData := Session;
end;

function TArgusServerCompletionProvider.Fetch(const AContext: TArgusContext; AData: TObject;
  const ACancelled: TArgusCancelledFunc): TArgusCompletionItems;
var
  Response: TJSONValue;
begin
  Response := TLspSession(AData).Completion(AContext.FileName, AContext.Line, AContext.Character, FTimeoutMs);
  try
    if ACancelled() then
      Exit(nil);
    Result := ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
end;

end.
