unit Atlas.Core.Completion.Providers.Server;

// Standardquelle der Vervollständigung (#408): der Atlas-Server über die
// LSP-Sitzung des Plugins (ADR 0006). Prepare gleicht im aufrufenden Thread
// (Zeitlimit-Arbeiter, #493) den Editortext ab (Sync ist threadsicher), Fetch
// fragt textDocument/completion im Hintergrund an
// und übersetzt die LSP-Einträge. Details für das Detailpanel (#405, #424)
// fragt Resolve über completionItem/resolve nach; der Server liefert sie
// strukturiert in data.atlas.
//
// Gestaffelt (#616): Fetch fragt mit partialResultToken; der Server schickt zuerst den eigenen
// Gültigkeitsbereich, dann die Units aus uses, die Antwort bringt den Rest (Importe). Jedes Teilergebnis
// geht sofort ans Popup. Rank zählt über alle Teile fort.
//
// Lebensdauer: Die Sitzung gehört dem Aufrufer. Bevor er sie freigibt (Neustart
// des Servers, Entladen), muss er Shutdown aufrufen; das wartet auf laufende Anfragen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Internals.Async,
  Atlas.Core.Lsp.Session;

type
  /// <summary>Alias für Bestandsnutzer; die Deklaration steht in Atlas.Core.Lsp.Session.</summary>
  TAtlasSessionFunc = Atlas.Core.Lsp.Session.TAtlasSessionFunc;
  /// <summary>Zeile fürs Diagnoselog des Plugins; ohne Namen aus dem Quelltext. Auch aus Hintergrund-Threads.</summary>
  TAtlasProviderLog = reference to procedure(const AMessage: string);

  TAtlasServerCompletionProvider = class(TAtlasAsyncCompletionProvider, IAtlasCompletionResolver)
  public const
    DefaultTimeoutMs = 2000;
    /// <summary>Name für die Sicherung je Quelle (#493).</summary>
    ProviderTitle = 'Vervollständigung (Server)';
  private
    FSession: TAtlasSessionFunc;
    FTimeoutMs: Cardinal;
    FResolveGeneration: Integer;
    FOnLog: TAtlasProviderLog;
    FSnippets: Boolean;
    procedure Log(const AMessage: string);
  protected
    /// <summary>Server weg oder Zeitlimit des Servers zählt nicht als Fehler der Quelle (#393 startet neu).</summary>
    function IsFailure(E: Exception): Boolean; override;
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems; override;
  public
    constructor Create(const ASession: TAtlasSessionFunc; ATimeoutMs: Cardinal = DefaultTimeoutMs);
    /// <summary>LSP-CompletionItemKind → Art des Eintrags.</summary>
    class function KindOf(ALspKind: Integer): TAtlasItemKind; static;
    /// <summary>Ein CompletionItem des LSP; ARank ist seine Stelle in der Antwort.</summary>
    class function ItemFromLsp(AItem: TJSONObject; ARank: Integer): TAtlasCompletionItem; static;
    /// <summary>Antwort auf textDocument/completion: CompletionList, CompletionItem[] oder null.</summary>
    class function ItemsFromLsp(AResponse: TJSONValue; AFirstRank: Integer = 0): TAtlasCompletionItems; static;
    /// <summary>AItems ohne Code-Vorlagen des Servers (Einträge mit Snippet, #51); Postfix-Vorlagen bleiben.</summary>
    class function WithoutSnippets(const AItems: TAtlasCompletionItems): TAtlasCompletionItems; static;
    /// <summary>Details aus der Antwort auf completionItem/resolve (data.atlas, sonst detail/documentation).</summary>
    class function DetailsFromLsp(AResponse: TJSONValue): TAtlasItemDetails; static;
    { IAtlasCompletionResolver }
    function Resolve(const AItem: TAtlasCompletionItem; const ACallback: TAtlasDetailsCallback): Boolean;
    /// <summary>Warum die Liste leer bleibt (kein Server, keine Antwort) und wie lange der Server brauchte.</summary>
    property OnLog: TAtlasProviderLog read FOnLog write FOnLog;
    /// <summary>Kontextabhängige Code-Vorlagen des Servers anbieten (#51, completion.snippets); Vorgabe an.</summary>
    property Snippets: Boolean read FSnippets write FSnippets;
  end;

implementation

uses
  System.StrUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Client;

{ TAtlasServerCompletionProvider }

constructor TAtlasServerCompletionProvider.Create(const ASession: TAtlasSessionFunc; ATimeoutMs: Cardinal);
begin
  inherited Create;
  Name := ProviderTitle;
  FSession := ASession;
  FTimeoutMs := ATimeoutMs;
  FSnippets := True;
end;

function TAtlasServerCompletionProvider.IsFailure(E: Exception): Boolean;
begin
  Result := inherited IsFailure(E) and not (E is ELspClientError);
end;

class function TAtlasServerCompletionProvider.KindOf(ALspKind: Integer): TAtlasItemKind;
begin
  case ALspKind of
    2: Result := TAtlasItemKind.Method;
    3: Result := TAtlasItemKind.Function_;
    4: Result := TAtlasItemKind.Constructor_;
    5: Result := TAtlasItemKind.Field;
    6: Result := TAtlasItemKind.Variable;
    7: Result := TAtlasItemKind.Class_;
    8: Result := TAtlasItemKind.Interface_;
    9: Result := TAtlasItemKind.Unit_;
    10: Result := TAtlasItemKind.Property_;
    13: Result := TAtlasItemKind.Enum;
    14: Result := TAtlasItemKind.Keyword;
    15: Result := TAtlasItemKind.Snippet;
    20: Result := TAtlasItemKind.EnumMember;
    21: Result := TAtlasItemKind.Constant;
    22: Result := TAtlasItemKind.Record_;
    23: Result := TAtlasItemKind.Event;
    25: Result := TAtlasItemKind.Type_;
  else
    Result := TAtlasItemKind.Unknown;
  end;
end;

function EditFromLsp(AEdit: TJSONObject; out AResult: TAtlasTextEdit): Boolean;
begin
  AResult := Default(TAtlasTextEdit);
  Result := AEdit.TryGetValue<Integer>('range.start.line', AResult.StartLine) and
    AEdit.TryGetValue<Integer>('range.start.character', AResult.StartCharacter) and
    AEdit.TryGetValue<Integer>('range.end.line', AResult.EndLine) and
    AEdit.TryGetValue<Integer>('range.end.character', AResult.EndCharacter) and
    AEdit.TryGetValue<string>('newText', AResult.NewText);
end;

/// <summary>LSP-Range ohne Text (#448).</summary>
function RangeFromLsp(ARange: TJSONObject; out AResult: TAtlasTextEdit): Boolean;
begin
  AResult := Default(TAtlasTextEdit);
  Result := ARange.TryGetValue<Integer>('start.line', AResult.StartLine) and
    ARange.TryGetValue<Integer>('start.character', AResult.StartCharacter) and
    ARange.TryGetValue<Integer>('end.line', AResult.EndLine) and
    ARange.TryGetValue<Integer>('end.character', AResult.EndCharacter);
end;

class function TAtlasServerCompletionProvider.ItemFromLsp(AItem: TJSONObject; ARank: Integer): TAtlasCompletionItem;
var
  Documentation, Edits, Value, Overloads: TJSONValue;
  Edit: TAtlasTextEdit;
  Data, Twin: TJSONObject;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AItem.GetValue<string>('label', '');
  Result.Kind := KindOf(AItem.GetValue<Integer>('kind', 0));
  Result.Signature := AItem.GetValue<string>('detail', '');
  Result.InsertText := AItem.GetValue<string>('insertText', '');
  // filterText nicht übernehmen: Der Server setzt dort bei unscharfen Treffern das getippte
  // Wort, damit VS Code sie nicht verwirft. Atlas filtert selbst gegen den Namen (#409);
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
    Result.Condition := Data.GetValue<string>('condition', '');
    Result.Unavailable := Data.GetValue('unavailable') is TJSONTrue;
    Result.Scope := Data.GetValue<Integer>('scope', 0);
    // Herkunft aus einer anderen Unit und verdeckte Deklarationen (#488).
    Result.DeclaringUnit := Data.GetValue<string>('unit', '');
    Value := Data.GetValue('hides');
    if Value is TJSONArray then
      for Value in TJSONArray(Data.GetValue('hides')) do
        if Value is TJSONString then
          Result.Hides := Result.Hides + [TJSONString(Value).Value];
    Result.HasParameters := Data.GetValue('parameters') is TJSONTrue;
    Result.ExpectedType := Data.GetValue<string>('expected', '');
    Result.Fits := Data.GetValue('fits') is TJSONTrue;
    // Neue Methode (#444) und Deklarationen unbekannter Namen (#471) erzeugen Code und stehen am Ende.
    Result.IsAction := MatchText(Data.GetValue<string>('action', ''), ['create', 'declare']);
    // Postfix-Vorlagen (#188): Der Server filtert über "Ausdruck.Kürzel"; getippt ist hier nur das Wort hinter
    // dem Punkt, also gilt der Teil nach dem letzten Punkt.
    Result.Postfix := Data.GetValue<string>('action', '') = 'postfix';
    if Result.Postfix then
    begin
      Result.FilterText := AItem.GetValue<string>('filterText', Result.Name);
      Result.FilterText := Copy(Result.FilterText, LastDelimiter('.', Result.FilterText) + 1, MaxInt);
    end;
    Result.Unknown := Data.GetValue<string>('unknown', '');
    // Aufzählungen und Mengen (#448).
    Result.Ordinal := Data.GetValue<Integer>('ordinal', 0);
    Result.SetOf := Data.GetValue<string>('setOf', '');
    Result.Checked := Data.GetValue('checked') is TJSONTrue;
    if (Result.SetOf <> '') and not ((Data.GetValue('setRange') is TJSONObject) and
      RangeFromLsp(TJSONObject(Data.GetValue('setRange')), Result.SetRange)) then
      Result.SetOf := '';
    // case vervollständigen (#449).
    Result.Pinned := Data.GetValue('pinned') is TJSONTrue;
    Result.Count := Data.GetValue<Integer>('count', 0);
    // Interface implementieren (#466).
    Result.Batch := Data.GetValue('batch') is TJSONTrue;
    Result.Hint := Data.GetValue('hint') is TJSONTrue;
    // Komponenten aus dem Formular (#455).
    Result.Form := Data.GetValue<string>('form', '');
    Result.ByType := Data.GetValue('byType') is TJSONTrue;
    // Sender mit Typumwandlung (#480).
    Result.Sender := Data.GetValue<string>('sender', '');
    Result.SenderOf := Data.GetValue<string>('senderOf', '');
    // Feld- und Parameternamen (#461).
    Result.DataSet := Data.GetValue<string>('dataSet', '');
    Result.DataSource := Data.GetValue<string>('dataSource', '');
    // Freigabe absichern (#489).
    Result.Guard := Data.GetValue<string>('guard', '') <> '';
    // Typargumente nach den Constraints (#450).
    Result.TypeParam := Data.GetValue<string>('typeParam', '');
    Result.Constraint := Data.GetValue<string>('constraint', '');
    Result.ConstraintHint := Data.GetValue<string>('constraintHint', '');
    Result.HiddenKinds := Data.GetValue<string>('hiddenKinds', '');
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
  // textEdit (#188): ersetzt mehr als das getippte Wort, etwa den Ausdruck vor dem Punkt.
  // Ein textEdit ohne Text ersetzt nichts sinnvoll; ignorieren statt den Bereich zu löschen. Ausnahme: Der Hinweis
  // „Methoden fehlen“ (#466) entfernt das getippte Wort, der Code kommt über die weiteren Änderungen.
  if (AItem.GetValue('textEdit') is TJSONObject) and EditFromLsp(TJSONObject(AItem.GetValue('textEdit')), Edit) and
    ((Edit.NewText <> '') or Result.Hint) then
  begin
    Result.HasTextEdit := True;
    Result.TextEdit := Edit;
  end;
  Edits := AItem.GetValue('additionalTextEdits');
  if Edits is TJSONArray then
    for Value in TJSONArray(Edits) do
      if (Value is TJSONObject) and EditFromLsp(TJSONObject(Value), Edit) then
        Result.AdditionalEdits := Result.AdditionalEdits + [Edit];
  // Bis #405 "Unit eingebunden" liefert: Ein Eintrag mit uses-Ergänzung (#180) kommt aus
  // einer noch nicht eingebundenen Unit. Einträge mit data.action (override, neue Methode;
  // #443, #444) ergänzen Code statt uses.
  Result.UnitUsed := (Length(Result.AdditionalEdits) = 0) or
    ((AItem.GetValue('data') is TJSONObject) and (TJSONObject(AItem.GetValue('data')).GetValue('action') <> nil));
  // Kontextabhängige Code-Vorlage des Servers (#51): Platzhalter-Modus wie bei den eigenen Vorlagen.
  if (AItem.GetValue('insertTextFormat') is TJSONNumber) and
    (TJSONNumber(AItem.GetValue('insertTextFormat')).AsInt = 2) then
  begin
    if Result.HasTextEdit then
      Result.Snippet := TAtlasSnippets.FromLsp(Result.TextEdit.NewText)
    else if Result.InsertText <> '' then
      Result.Snippet := TAtlasSnippets.FromLsp(Result.InsertText)
    else
      Result.Snippet := TAtlasSnippets.FromLsp(Result.Name);
  end;
end;

class function TAtlasServerCompletionProvider.WithoutSnippets(
  const AItems: TAtlasCompletionItems): TAtlasCompletionItems;
var
  Item: TAtlasCompletionItem;
begin
  Result := nil;
  // Postfix-Vorlagen (#188) haben ihren eigenen Schalter completion.postfixTemplates.
  for Item in AItems do
    if (Item.Snippet = '') or Item.Postfix then
      Result := Result + [Item];
end;

class function TAtlasServerCompletionProvider.ItemsFromLsp(AResponse: TJSONValue;
  AFirstRank: Integer): TAtlasCompletionItems;
var
  Items: TJSONValue;
  Index, Count: Integer;
begin
  Result := nil;
  if AResponse is TJSONObject then
    Items := TJSONObject(AResponse).GetValue('items')
  else
    Items := AResponse;
  if not (Items is TJSONArray) then
    Exit;
  // Einmal anlegen statt je Eintrag anzuhängen: Das kopierte bei 1000 Einträgen die ganze Liste jedes Mal (#616).
  SetLength(Result, TJSONArray(Items).Count);
  Count := 0;
  for Index := 0 to TJSONArray(Items).Count - 1 do
    if TJSONArray(Items).Items[Index] is TJSONObject then
    begin
      Result[Count] := ItemFromLsp(TJSONObject(TJSONArray(Items).Items[Index]), AFirstRank + Index);
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

procedure TAtlasServerCompletionProvider.Log(const AMessage: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMessage);
end;

function TAtlasServerCompletionProvider.Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean;
var
  Session: TLspSession;
begin
  AData := nil;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  Result := (Session <> nil) and (AContext.FileName <> '');
  if not Result then
  begin
    if Session = nil then
      Log('Vervollständigung: kein Server verbunden');
    Exit;
  end;
  // Sync ist threadsicher (FDocLock in TLspSession); hier im Zeitlimit-Arbeiter.
  Session.Sync(AContext.FileName, AContext.Text);
  AData := Session;
end;

function TAtlasServerCompletionProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems;
var
  Response: TJSONValue;
  NextRank: Integer;
  Emit: TAtlasEmitProc;
  Watch: TStopwatch;
  Snippets: Boolean;
begin
  AIncomplete := False;
  NextRank := 0;
  Emit := AEmit;
  Snippets := FSnippets;
  Watch := TStopwatch.StartNew;
  // Teilergebnisse kommen im Lese-Thread nacheinander und alle vor der Antwort.
  Response := TLspSession(AData).Completion(AContext.FileName, AContext.Line, AContext.Character, FTimeoutMs,
    AContext.Trigger,
    procedure(const AValue: TJSONValue)
    var
      Items: TAtlasCompletionItems;
    begin
      if not (AValue is TJSONArray) then
        Exit;
      Items := ItemsFromLsp(AValue, NextRank);
      Inc(NextRank, TJSONArray(AValue).Count);
      // completion.snippets aus (#51): wie ohne die Funktion.
      if not Snippets then
        Items := WithoutSnippets(Items);
      Emit(Items);
    end);
  try
    // Ohne Antwort bleibt die Liste leer; das Zeitlimit ist FTimeoutMs.
    if Response = nil then
      Log(Format('Vervollständigung: keine Antwort nach %d ms (%d Teilergebnisse)',
        [Watch.ElapsedMilliseconds, NextRank]))
    else
      Log(Format('Vervollständigung: Antwort nach %d ms', [Watch.ElapsedMilliseconds]));
    if ACancelled() then
      Exit(nil);
    // CompletionList mit isIncomplete: Der Server hat gekürzt und will beim Weitertippen neu gefragt werden.
    // Ohne GetValue<Boolean>: das lässt über TValue Speicher liegen (Leck-Monitor).
    AIncomplete := (Response is TJSONObject) and (TJSONObject(Response).GetValue('isIncomplete') is TJSONBool) and
      TJSONBool(TJSONObject(Response).GetValue('isIncomplete')).AsBoolean;
    Result := ItemsFromLsp(Response, NextRank);
    if not Snippets then
      Result := WithoutSnippets(Result);
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

function EntriesOf(AObject: TJSONObject; const AName: string): TArray<TAtlasDocEntry>;
var
  Value, Item: TJSONValue;
  Entry: TAtlasDocEntry;
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

class function TAtlasServerCompletionProvider.DetailsFromLsp(AResponse: TJSONValue): TAtlasItemDetails;
var
  Data, Atlas, Directives, Item: TJSONValue;
  Documentation: TJSONValue;
begin
  Result := Default(TAtlasItemDetails);
  if not (AResponse is TJSONObject) then
    Exit;
  Data := TJSONObject(AResponse).GetValue('data');
  Atlas := nil;
  if Data is TJSONObject then
    Atlas := TJSONObject(Data).GetValue('atlas');
  if Atlas is TJSONObject then
  begin
    Result.Declaration := StringOf(TJSONObject(Atlas), 'declaration');
    Result.UnitName := StringOf(TJSONObject(Atlas), 'unit');
    Result.Container := StringOf(TJSONObject(Atlas), 'container');
    Result.Visibility := StringOf(TJSONObject(Atlas), 'visibility');
    Result.IsDeprecated := TJSONObject(Atlas).GetValue('deprecated') <> nil;
    Result.DeprecatedText := StringOf(TJSONObject(Atlas), 'deprecated');
    Result.Summary := StringOf(TJSONObject(Atlas), 'summary');
    Result.Returns := StringOf(TJSONObject(Atlas), 'returns');
    Result.Remarks := StringOf(TJSONObject(Atlas), 'remarks');
    Result.Params := EntriesOf(TJSONObject(Atlas), 'params');
    Result.Exceptions := EntriesOf(TJSONObject(Atlas), 'exceptions');
    Result.Doc := TAtlasDoc.FromJson(TJSONObject(Atlas).GetValue('documentation'));
    Result.Display := TAtlasDocDisplay.FromJson(TJSONObject(Atlas).GetValue('xmlDoc'),
      TAtlasDocDisplay.Create(True, 0));
    Directives := TJSONObject(Atlas).GetValue('directives');
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

function TAtlasServerCompletionProvider.Resolve(const AItem: TAtlasCompletionItem;
  const ACallback: TAtlasDetailsCallback): Boolean;
var
  Session: TLspSession;
  Request: string;
  Generation: Integer;
  AliveToken: TAtlasAliveToken;
  AliveRef: IInterface;
  Provider: TAtlasServerCompletionProvider;
  Callback: TAtlasDetailsCallback;
  Item: TJSONObject;
  Hides: TArray<string>;
begin
  Result := False;
  if AItem.ResolveData = '' then
    Exit;
  Hides := AItem.Hides;
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
      Details: TAtlasItemDetails;
    begin
      Response := Session.ResolveCompletion(TJSONObject.ParseJSONValue(Request) as TJSONObject, FTimeoutMs);
      try
        Details := DetailsFromLsp(Response);
      finally
        Response.Free;
      end;
      Details.Hides := Hides;
      // Der Rückruf zeigt das Detailpanel; die Hülle zählt seine Fehler für die Vervollständigung (S-05, A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Completion,
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