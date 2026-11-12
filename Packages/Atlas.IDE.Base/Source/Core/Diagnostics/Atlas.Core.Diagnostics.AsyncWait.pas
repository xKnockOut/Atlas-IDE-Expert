unit Atlas.Core.Diagnostics.AsyncWait;

// Warten auf eine asynchrone Anfrage aus einem Hintergrund-Thread, gemeinsam
// für die Versionsabfrage und die CI-Abfragen (vorher je eine Kopie). Das
// Warten endet, sobald die Anfrage fertig ist, das Abbruchsignal des Plugins
// kommt (TAtlasShutdown), der Aufrufer abbricht oder die Frist erreicht ist.
// Ohne Erfolg bricht es die Anfrage ab und wartet noch kurz auf ihr Ende,
// damit der HTTP-Client danach freigegeben werden darf.
// Die Anfrage kommt als zwei Funktionen (fertig? und abbrechen), nicht als
// IAsyncResult: So bleibt die Unit ohne HTTP-Bibliothek und testbar.

interface

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Deadline;

type
{$SCOPEDENUMS ON}
  /// <summary>Warum das Warten endete: Done = Anfrage fertig; Stopped = Abbruchsignal des Plugins;
  /// Cancelled = der Aufrufer bricht ab; Timeout = Frist erreicht.</summary>
  TAtlasAsyncEnd = (Done, Stopped, Cancelled, Timeout);
{$SCOPEDENUMS OFF}

  TAtlasAsyncWait = record
  public const
    /// <summary>Takt, in dem das Warten Abbruch und Frist prüft.</summary>
    cSliceMs = 50;
    /// <summary>So lange wartet es nach dem Abbrechen höchstens noch auf das Ende der Anfrage.</summary>
    cDrainMs = 500;
  public
    /// <summary>Wartet, bis AIsCompleted True liefert oder ein anderer Grund das Warten beendet (siehe
    /// TAtlasAsyncEnd). Ohne Done ruft es ACancel und wartet höchstens cDrainMs auf AIsCompleted.
    /// ACancelled darf nil sein.</summary>
    class function Await(const AIsCompleted: TFunc<Boolean>; const ACancel: TProc;
      const ADeadline: TAtlasDeadline; const ACancelled: TFunc<Boolean>): TAtlasAsyncEnd; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown;

const
  cDrainSliceMs = 10;

class function TAtlasAsyncWait.Await(const AIsCompleted: TFunc<Boolean>; const ACancel: TProc;
  const ADeadline: TAtlasDeadline; const ACancelled: TFunc<Boolean>): TAtlasAsyncEnd;
var
  mDrain: TAtlasDeadline;
begin
  Result := TAtlasAsyncEnd.Done;
  while (Result = TAtlasAsyncEnd.Done) and not AIsCompleted() do
  begin
    if TAtlasShutdown.Wait(cSliceMs) then
    begin
      Result := TAtlasAsyncEnd.Stopped;
    end
    else if Assigned(ACancelled) and ACancelled() then
    begin
      Result := TAtlasAsyncEnd.Cancelled;
    end
    else if ADeadline.Reached then
    begin
      Result := TAtlasAsyncEnd.Timeout;
    end;
  end;
  if Result = TAtlasAsyncEnd.Done then
  begin
    Exit;
  end;
  ACancel();
  mDrain := TAtlasDeadline.After(cDrainMs);
  while not AIsCompleted() and not mDrain.Reached do
  begin
    Sleep(cDrainSliceMs);
  end;
end;

end.
