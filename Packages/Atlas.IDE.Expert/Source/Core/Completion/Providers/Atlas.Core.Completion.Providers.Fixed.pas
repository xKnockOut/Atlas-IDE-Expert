unit Atlas.Core.Completion.Providers.Fixed;

// Datenquelle mit festen Einträgen (#408): für Tests der Oberfläche ohne
// Server (#415) und für den Fall eines langsamen Providers (#409, #431). Mit
// ADelayMs > 0 liefert sie erst nach dieser Zeit und lässt sich solange abbrechen.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Internals.Async;

type
  TAtlasFixedCompletionProvider = class(TAtlasAsyncCompletionProvider)
  private
    FItems: TAtlasCompletionItems;
    FDelayMs: Cardinal;
    FIncomplete: Boolean;
  protected
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      out AIncomplete: Boolean): TAtlasCompletionItems; override;
  public
    /// <summary>AIncomplete: meldet die Liste als gekürzt (#431).</summary>
    constructor Create(const AItems: TAtlasCompletionItems; ADelayMs: Cardinal = 0; AIncomplete: Boolean = False);
  end;

implementation

{ TAtlasFixedCompletionProvider }

constructor TAtlasFixedCompletionProvider.Create(const AItems: TAtlasCompletionItems; ADelayMs: Cardinal;
  AIncomplete: Boolean);
begin
  inherited Create;
  FItems := AItems;
  FDelayMs := ADelayMs;
  FIncomplete := AIncomplete;
end;

function TAtlasFixedCompletionProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; out AIncomplete: Boolean): TAtlasCompletionItems;
var
  Start: UInt64;
begin
  AIncomplete := FIncomplete;
  Start := TThread.GetTickCount64;
  while TThread.GetTickCount64 - Start < FDelayMs do
  begin
    if ACancelled() then
      Exit(nil);
    TThread.Sleep(5);
  end;
  Result := FItems;
end;

end.
