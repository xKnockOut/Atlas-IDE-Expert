unit Atlas.Core.Completion.Providers.Expression;

// Datenquelle für die Vervollständigung in den Debugger-Dialogen (#538) über
// den Controller (#410). Der Kontext trägt hier den Ausdruck in Text, die
// Bezugszeile (0-basiert) in Line und die Schreibmarke im Feld in Character;
// FileName ist die Datei der Bezugszeile. Die IDE-Schicht gleicht diese Datei
// vorher im Hauptthread ab; Fetch fragt atlas/expressionCompletion im
// Hintergrund. Mit Trigger = TAtlasTriggers.History kommt statt der
// Anfrage der Verlauf (Atlas.Core.Debug.DialogCompletion). Die LSP-Einträge
// übersetzt AItemsOf, das die Komposition mit der Übersetzung der Quelle
// Server belegt (Rollenmatrix: keine Providers untereinander).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Internals.Async,
  Atlas.Core.Lsp.Session;

{$SCOPEDENUMS ON}

type
  /// <summary>Antwort des Servers als Einträge.</summary>
  TAtlasLspItemsFunc = reference to function(AResponse: TJSONValue): TAtlasCompletionItems;

  TAtlasExpressionCompletionProvider = class(TAtlasAsyncCompletionProvider)
  public const
    DefaultTimeoutMs = 2000;
    ProviderTitle = 'Vervollständigung (Debug-Dialoge)';
  private
    FSession: TAtlasSessionFunc;
    FHistory: TFunc<TArray<string>>;
    FItemsOf: TAtlasLspItemsFunc;
    FTimeoutMs: Cardinal;
    FHistoryCaption: string;
  protected
    function IsFailure(E: Exception): Boolean; override;
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems; override;
  public
    /// <summary>AHistory: Verlauf des aktuellen Projekts, im Hintergrund aufgerufen (sperrt selbst).</summary>
    constructor Create(const ASession: TAtlasSessionFunc; const AHistory: TFunc<TArray<string>>;
      const AItemsOf: TAtlasLspItemsFunc; ATimeoutMs: Cardinal);
    /// <summary>Einträge des Verlaufs: der ganze Ausdruck ersetzt das Feld.</summary>
    class function HistoryItems(const AExpressions: TArray<string>; const ACaption: string):
      TAtlasCompletionItems; static;
    /// <summary>Beschriftung der Verlaufseinträge (Signatur-Spalte).</summary>
    property HistoryCaption: string read FHistoryCaption write FHistoryCaption;
  end;

implementation

uses
  Atlas.Core.Lsp.Client;

{ TAtlasExpressionCompletionProvider }

constructor TAtlasExpressionCompletionProvider.Create(const ASession: TAtlasSessionFunc;
  const AHistory: TFunc<TArray<string>>; const AItemsOf: TAtlasLspItemsFunc; ATimeoutMs: Cardinal);
begin
  inherited Create;
  Name := ProviderTitle;
  FSession := ASession;
  FHistory := AHistory;
  FItemsOf := AItemsOf;
  FTimeoutMs := ATimeoutMs;
end;

function TAtlasExpressionCompletionProvider.IsFailure(E: Exception): Boolean;
begin
  // Server weg oder Zeitlimit: wie bei der Vervollständigung im Editor kein Fehler der Quelle.
  Result := inherited IsFailure(E) and not (E is ELspClientError);
end;

function TAtlasExpressionCompletionProvider.Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean;
var
  Session: TLspSession;
begin
  AData := nil;
  if AContext.Trigger = TAtlasTriggers.History then
    Exit(Assigned(FHistory));
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  Result := (Session <> nil) and (AContext.FileName <> '') and (AContext.Line >= 0);
  AData := Session;
end;

function TAtlasExpressionCompletionProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc; out AIncomplete: Boolean):
  TAtlasCompletionItems;
var
  Response: TJSONValue;
begin
  AIncomplete := False;
  if AContext.Trigger = TAtlasTriggers.History then
    Exit(HistoryItems(FHistory(), FHistoryCaption));
  Response := TLspSession(AData).ExpressionCompletion(AContext.FileName, AContext.Line, AContext.Text,
    AContext.Character, FTimeoutMs);
  try
    if ACancelled() then
      Exit(nil);
    // Antwort {prefix, items} in der Form einer CompletionList.
    Result := nil;
    if Assigned(FItemsOf) then
      Result := FItemsOf(Response);
  finally
    Response.Free;
  end;
end;

class function TAtlasExpressionCompletionProvider.HistoryItems(const AExpressions: TArray<string>;
  const ACaption: string): TAtlasCompletionItems;
var
  Index: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AExpressions));
  for Index := 0 to High(AExpressions) do
  begin
    Result[Index] := Default(TAtlasCompletionItem);
    Result[Index].Name := AExpressions[Index];
    Result[Index].Kind := TAtlasItemKind.Unknown;
    Result[Index].Signature := ACaption;
    Result[Index].Rank := Index;
  end;
end;

end.
