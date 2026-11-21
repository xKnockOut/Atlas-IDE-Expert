unit Atlas.Common.Dfm.EventHandlers.TestSupport;

// Gemeinsame Hilfen der Tests zu Ereignisbehandlern im Formular (Auswertung und Protokoll).

interface

uses
  Atlas.Common.Dfm.EventHandlers;

/// <summary>Behandler von AEvent an AComponent in AHandlers; der Test scheitert, wenn es ihn nicht gibt.</summary>
function FindHandler(const AHandlers: TArray<TEventHandler>; const AComponent, AEvent: string): TEventHandler;

implementation

uses
  System.SysUtils,
  DUnitX.TestFramework;

function FindHandler(const AHandlers: TArray<TEventHandler>; const AComponent, AEvent: string): TEventHandler;
var
  mItem: TEventHandler;
begin
  for mItem in AHandlers do
  begin
    if SameText(mItem.Component, AComponent) and SameText(mItem.Event, AEvent) then
    begin
      Exit(mItem);
    end;
  end;
  Assert.Fail('nicht gefunden: ' + AComponent + '.' + AEvent);
  Result := Default(TEventHandler);
end;

end.
