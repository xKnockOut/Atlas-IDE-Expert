unit Argus.Core.Completion.Providers.Fixed;

// Datenquelle mit festen Einträgen (#408): für Tests der Oberfläche ohne
// Server (#415) und für den Fall eines langsamen Providers (#409, #431). Mit
// ADelayMs > 0 liefert sie erst nach dieser Zeit und lässt sich solange abbrechen.

interface

uses
  System.SysUtils,
  System.Classes,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Internals.Async;

type
  TArgusFixedCompletionProvider = class(TArgusAsyncCompletionProvider)
  private
    FItems: TArgusCompletionItems;
    FDelayMs: Cardinal;
  protected
    function Fetch(const AContext: TArgusContext; AData: TObject;
      const ACancelled: TArgusCancelledFunc): TArgusCompletionItems; override;
  public
    constructor Create(const AItems: TArgusCompletionItems; ADelayMs: Cardinal = 0);
  end;

implementation

{ TArgusFixedCompletionProvider }

constructor TArgusFixedCompletionProvider.Create(const AItems: TArgusCompletionItems; ADelayMs: Cardinal);
begin
  inherited Create;
  FItems := AItems;
  FDelayMs := ADelayMs;
end;

function TArgusFixedCompletionProvider.Fetch(const AContext: TArgusContext; AData: TObject;
  const ACancelled: TArgusCancelledFunc): TArgusCompletionItems;
var
  Start: UInt64;
begin
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
