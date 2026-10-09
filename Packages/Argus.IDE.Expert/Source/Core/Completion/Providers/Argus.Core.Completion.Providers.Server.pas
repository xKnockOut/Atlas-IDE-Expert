unit Argus.Core.Completion.Providers.Server;

// Standardquelle der Vervollständigung (#408): der Argus-Server über die
// LSP-Sitzung des Plugins (ADR 0006). Prepare gleicht im Hauptthread den
// Editortext ab (Sync), Fetch fragt textDocument/completion im Hintergrund an
// und übersetzt die LSP-Einträge. Details für das Detailpanel (#405, #424)
// fragt Resolve über completionItem/resolve nach; der Server liefert sie
// strukturiert in data.argus.
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

  TArgusServerCompletionProvider = class(TArgusAsyncCompletionProvider, IArgusCompletionResolver)
  public const
    DefaultTimeoutMs = 2000;
  private
    FSession: TArgusSessionFunc;
    FTimeoutMs: Cardinal;
    FResolveGeneration: Integer;
  protected
    function Prepare(const AContext: TArgusContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TArgusContext; AData: TObject; const ACancelled: TArgusCancelledFunc;
      out AIncomplete: Boolean): TArgusCompletionItems; override;
  public
    constructor Create(const ASession: TArgusSessionFunc; ATimeoutMs: Cardinal = DefaultTimeoutMs);
    /// <summary>LSP-CompletionItemKind → Art des Eintrags.</summary>
    class function KindOf(ALspKind: Integer): TArgusItemKind; static;
    /// <summary>Ein CompletionItem des LSP; ARank ist seine Stelle in der Antwort.</summary>
    class function ItemFromLsp(AItem: TJSONObject; ARank: Integer): TArgusCompletionItem; static;
    /// <summary>Antwort auf textDocument/completion: CompletionList, CompletionItem[] oder null.</summary>
    class function ItemsFromLsp(AResponse: TJSONValue): TArgusCompletionItems; static;
    /// <summary>Details aus der Antwort auf completionItem/resolve (data.argus, sonst detail/documentation).</summary>
    class function DetailsFromLsp(AResponse: TJSONValue): TArgusItemDetails; static;
    { IArgusCompletionResolver }
    function Resolve(const AItem: TArgusCompletionItem; const ACallback: TArgusDetailsCallback): Boolean;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
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
  Documentation, Edits, Value, Overloads: TJSONValue;
  Edit: TArgusTextEdit;
  Data, Twin: TJSONObject;
begin
  Result := Default(TArgusCompletionItem);
  Result.Name := AItem.GetValue<string>('label', '');
  Result.Kind := KindOf(AItem.GetValue<Integer>('kind', 0));
  Result.Signature := AItem.GetValue<string>('detail', '');
  Result.InsertText := AItem.GetValue<string>('insertText', '');
  // filterText nicht übernehmen: Der Server setzt dort bei unscharfen Treffern das getippte
  // Wort, damit VS Code sie nicht verwirft. Argus filtert selbst gegen den Namen (#409);
  // sonst passt jeder Eintrag genau (in der IDE: "mylist" zeigte ERROR_TOO_MANY_LINKS).
  Result.Rank := ARank;
  // documentation: string oder MarkupContent.
  Documentation := AItem.GetValue('documentation');
  if Documentation is TJSONString then
    Result.Documentation := TJSONString(Documentation).Value
  else if Documentation is TJSONObject then
    Result.Documentation := TJSONObject(Documentation).GetValue<string>('value', '');
  // data unverändert für completionItem/resolve aufheben.
  if AItem.GetValue('data') <> nil then
    Result.ResolveData := AItem.GetValue('data').ToJSON;
  // Herkunft, Vererbungstiefe, Helper und Überladungen (#419, #425, #456).
  if AItem.GetValue('data') is TJSONObject then
  begin
    Data := TJSONObject(AItem.GetValue('data'));
    Result.DeclaringClass := Data.GetValue<string>('container', '');
    Result.Depth := Data.GetValue<Integer>('depth', 0);
    Result.IsHelper := Data.GetValue('helper') is TJSONTrue;
    Overloads := Data.GetValue('overloads');
    if Overloads is TJSONArray then
      for Value in TJSONArray(Overloads) do
        if Value is TJSONObject then
        begin
          // Gleiche Datei, andere Position: ein data je Überladung für completionItem/resolve.
          Twin := Data.Clone as TJSONObject;
          try
            Twin.RemovePair('overloads').Free;
            Twin.RemovePair('line').Free;
            Twin.RemovePair('character').Free;
            Twin.AddPair('line', TJSONNumber.Create(TJSONObject(Value).GetValue<Integer>('line', 0)));
            Twin.AddPair('character', TJSONNumber.Create(TJSONObject(Value).GetValue<Integer>('character', 0)));
            Result.OverloadData := Result.OverloadData + [Twin.ToJSON];
          finally
            Twin.Free;
          end;
        end;
  end;
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
  const ACancelled: TArgusCancelledFunc; out AIncomplete: Boolean): TArgusCompletionItems;
var
  Response: TJSONValue;
begin
  AIncomplete := False;
  Response := TLspSession(AData).Completion(AContext.FileName, AContext.Line, AContext.Character, FTimeoutMs);
  try
    if ACancelled() then
      Exit(nil);
    // CompletionList mit isIncomplete: Der Server hat gekürzt und will beim Weitertippen neu gefragt werden.
    // Ohne GetValue<Boolean>: das lässt über TValue Speicher liegen (Leck-Monitor).
    AIncomplete := (Response is TJSONObject) and (TJSONObject(Response).GetValue('isIncomplete') is TJSONBool) and
      TJSONBool(TJSONObject(Response).GetValue('isIncomplete')).AsBoolean;
    Result := ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value
  else
    Result := '';
end;

function EntriesOf(AObject: TJSONObject; const AName: string): TArray<TArgusDocEntry>;
var
  Value, Item: TJSONValue;
  Entry: TArgusDocEntry;
begin
  Result := nil;
  Value := AObject.GetValue(AName);
  if not (Value is TJSONArray) then
    Exit;
  for Item in TJSONArray(Value) do
    if Item is TJSONObject then
    begin
      Entry.Name := StringOf(TJSONObject(Item), 'name');
      Entry.Text := StringOf(TJSONObject(Item), 'text');
      Result := Result + [Entry];
    end;
end;

class function TArgusServerCompletionProvider.DetailsFromLsp(AResponse: TJSONValue): TArgusItemDetails;
var
  Data, Argus, Directives, Item: TJSONValue;
  Documentation: TJSONValue;
begin
  Result := Default(TArgusItemDetails);
  if not (AResponse is TJSONObject) then
    Exit;
  Data := TJSONObject(AResponse).GetValue('data');
  Argus := nil;
  if Data is TJSONObject then
    Argus := TJSONObject(Data).GetValue('argus');
  if Argus is TJSONObject then
  begin
    Result.Declaration := StringOf(TJSONObject(Argus), 'declaration');
    Result.UnitName := StringOf(TJSONObject(Argus), 'unit');
    Result.Container := StringOf(TJSONObject(Argus), 'container');
    Result.Visibility := StringOf(TJSONObject(Argus), 'visibility');
    Result.IsDeprecated := TJSONObject(Argus).GetValue('deprecated') <> nil;
    Result.DeprecatedText := StringOf(TJSONObject(Argus), 'deprecated');
    Result.Summary := StringOf(TJSONObject(Argus), 'summary');
    Result.Returns := StringOf(TJSONObject(Argus), 'returns');
    Result.Remarks := StringOf(TJSONObject(Argus), 'remarks');
    Result.Params := EntriesOf(TJSONObject(Argus), 'params');
    Result.Exceptions := EntriesOf(TJSONObject(Argus), 'exceptions');
    Directives := TJSONObject(Argus).GetValue('directives');
    if Directives is TJSONArray then
      for Item in TJSONArray(Directives) do
        if Item is TJSONString then
          Result.Directives := Result.Directives + [TJSONString(Item).Value];
    Exit;
  end;
  // Andere Server: detail als Deklaration, documentation als Beschreibung.
  Result.Declaration := StringOf(TJSONObject(AResponse), 'detail');
  Documentation := TJSONObject(AResponse).GetValue('documentation');
  if Documentation is TJSONString then
    Result.Summary := TJSONString(Documentation).Value
  else if Documentation is TJSONObject then
    Result.Summary := StringOf(TJSONObject(Documentation), 'value');
end;

function TArgusServerCompletionProvider.Resolve(const AItem: TArgusCompletionItem;
  const ACallback: TArgusDetailsCallback): Boolean;
var
  Session: TLspSession;
  Request: string;
  Generation: Integer;
  AliveToken: TArgusAliveToken;
  AliveRef: IInterface;
  Provider: TArgusServerCompletionProvider;
  Callback: TArgusDetailsCallback;
  Item: TJSONObject;
begin
  Result := False;
  if AItem.ResolveData = '' then
    Exit;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  if Session = nil then
    Exit;
  // Nur label und data: mehr braucht der Server nicht.
  Item := TJSONObject.Create;
  try
    Item.AddPair('label', AItem.Name);
    Item.AddPair('data', TJSONObject.ParseJSONValue(AItem.ResolveData));
    Request := Item.ToJSON;
  finally
    Item.Free;
  end;
  Generation := TInterlocked.Increment(FResolveGeneration);
  AliveToken := Token;
  AliveRef := TokenRef;
  Provider := Self;
  Callback := ACallback;
  RunInBackground(
    procedure
    var
      Response: TJSONValue;
      Details: TArgusItemDetails;
    begin
      Response := Session.ResolveCompletion(TJSONObject.ParseJSONValue(Request) as TJSONObject, FTimeoutMs);
      try
        Details := DetailsFromLsp(Response);
      finally
        Response.Free;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if AliveToken.Alive and (AliveRef <> nil) and
            (TInterlocked.CompareExchange(Provider.FResolveGeneration, 0, 0) = Generation) then
            Callback(Details);
        end);
    end);
  Result := True;
end;

end.