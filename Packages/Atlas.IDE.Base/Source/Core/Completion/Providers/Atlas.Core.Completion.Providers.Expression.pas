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
  public
    /// <summary>Name der Quelle für die Sicherung (#493) und ihre Meldungen, in der Sprache der Oberfläche.
    /// </summary>
    class function ProviderTitle: string; static;
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
      const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems; override;
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
  Atlas.Core.Lsp.Client,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TExpressionText = (CompletionDebugDialogs);

const
  cTexts: array[TAtlasLanguage, TExpressionText] of string = (
    ('Vervollständigung (Debug-Dialoge)'),
    ('Completion (debug dialogs)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TExpressionText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasExpressionCompletionProvider }

class function TAtlasExpressionCompletionProvider.ProviderTitle: string;
begin
  Result := UiText(TExpressionText.CompletionDebugDialogs);
end;

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
  mSession: TLspSession;
begin
  AData := nil;
  if AContext.Trigger = TAtlasTriggers.History then
  begin
    Exit(Assigned(FHistory));
  end;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  Result := (mSession <> nil) and (AContext.FileName <> '') and (AContext.Line >= 0);
  AData := mSession;
end;

function TAtlasExpressionCompletionProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState):
  TAtlasCompletionItems;
var
  mResponse: TJSONValue;
begin
  AState := Default(TAtlasFetchState);
  if AContext.Trigger = TAtlasTriggers.History then
  begin
    Exit(HistoryItems(FHistory(), FHistoryCaption));
  end;
  mResponse := TLspSession(AData).ExpressionCompletion(AContext.FileName, AContext.Line, AContext.Text,
    AContext.Character, FTimeoutMs);
  try
    if ACancelled() then
    begin
      Exit(nil);
    end;
    // Antwort {prefix, items} in der Form einer CompletionList.
    Result := nil;
    if Assigned(FItemsOf) then
    begin
      Result := FItemsOf(mResponse);
    end;
  finally
    mResponse.Free;
  end;
end;

class function TAtlasExpressionCompletionProvider.HistoryItems(const AExpressions: TArray<string>;
  const ACaption: string): TAtlasCompletionItems;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AExpressions));
  for mIndex := 0 to High(AExpressions) do
  begin
    Result[mIndex] := Default(TAtlasCompletionItem);
    Result[mIndex].Name := AExpressions[mIndex];
    Result[mIndex].Kind := TAtlasItemKind.Unknown;
    Result[mIndex].Signature := ACaption;
    Result[mIndex].Rank := mIndex;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Completion.Providers.Expression', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
