unit Atlas.Core.Diagnostics.AsyncWait;

// Warten auf eine asynchrone Anfrage aus einem Hintergrund-Thread, gemeinsam
// für die Versionsabfrage und die CI-Abfragen (vorher je eine Kopie). Das
// Warten endet, sobald die Anfrage fertig ist, das Abbruchsignal des Plugins
// kommt (TAtlasShutdown), der Aufrufer abbricht oder die Frist erreicht ist.
// Ohne Erfolg bricht es die Anfrage ab. Await meldet dann, ob sie schon
// beendet ist (Completed); solange nicht, benutzt der Task der RTL Client und
// Streams noch, und der Aufrufer darf sie nicht freigeben (Code-Review W-103:
// früher wurde nach 500 ms freigegeben, ob die Anfrage beendet war oder nicht).
// AwaitSettled wartet deshalb nach dem Abbruch ohne Frist auf das Ende. Bleibt
// eine Anfrage hängen, wird der wartende Arbeiter-Thread überfällig und geht an
// TAtlasOverdueThreads, die sein Package beim Abmelden festhalten. Damit das
// selten und kurz ist, begrenzt cConnectMs den Verbindungsaufbau.
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

  /// <summary>Ergebnis von TAtlasAsyncWait.Await: der Grund und ob die Anfrage beendet ist.</summary>
  TAtlasAsyncResult = record
    Ended: TAtlasAsyncEnd;
    /// <summary>False: Die Anfrage läuft nach dem Abbruch noch; ihre Objekte dürfen nicht freigegeben
    /// werden.</summary>
    Completed: Boolean;
  end;

  TAtlasAsyncWait = record
  public const
    /// <summary>Takt, in dem das Warten Abbruch und Frist prüft.</summary>
    cSliceMs = 50;
    /// <summary>Takt, in dem Finish nach dem Abbruch auf das Ende der Anfrage prüft.</summary>
    cFinishSliceMs = 10;
    /// <summary>Höchstens so lange darf der Verbindungsaufbau einer abbrechbaren Anfrage dauern: Ein blockierender
    /// Verbindungsaufbau endet sonst erst mit der Gesamtfrist, und so lange wartet Finish nach dem
    /// Abbruch.</summary>
    cConnectMs = 5000;
  public
    /// <summary>Wartet, bis AIsCompleted True liefert oder ein anderer Grund das Warten beendet (siehe
    /// TAtlasAsyncEnd). Ohne Done ruft es ACancel und kehrt sofort zurück; Completed sagt, ob die Anfrage
    /// schon beendet ist. ACancelled darf nil sein.</summary>
    class function Await(const AIsCompleted: TFunc<Boolean>; const ACancel: TProc;
      const ADeadline: TAtlasDeadline; const ACancelled: TFunc<Boolean>): TAtlasAsyncResult; static;
    /// <summary>Wartet ohne Frist, bis AIsCompleted True liefert (nach dem Abbruch einer Anfrage).</summary>
    class procedure Finish(const AIsCompleted: TFunc<Boolean>); static;
    /// <summary>Wie Await, wartet aber nach einem Abbruch mit Finish auf das Ende der Anfrage: Danach darf der
    /// Aufrufer Client und Streams immer freigeben.</summary>
    class function AwaitSettled(const AIsCompleted: TFunc<Boolean>; const ACancel: TProc;
      const ADeadline: TAtlasDeadline; const ACancelled: TFunc<Boolean>): TAtlasAsyncEnd; static;
    /// <summary>Verbindungsfrist zur Gesamtfrist ATimeoutMs: höchstens cConnectMs.</summary>
    class function ConnectTimeout(ATimeoutMs: Integer): Integer; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Shutdown;

class function TAtlasAsyncWait.Await(const AIsCompleted: TFunc<Boolean>; const ACancel: TProc;
  const ADeadline: TAtlasDeadline; const ACancelled: TFunc<Boolean>): TAtlasAsyncResult;
begin
  Result.Ended := TAtlasAsyncEnd.Done;
  Result.Completed := AIsCompleted();
  while (Result.Ended = TAtlasAsyncEnd.Done) and not Result.Completed do
  begin
    if TAtlasShutdown.Wait(cSliceMs) then
    begin
      Result.Ended := TAtlasAsyncEnd.Stopped;
    end
    else if Assigned(ACancelled) and ACancelled() then
    begin
      Result.Ended := TAtlasAsyncEnd.Cancelled;
    end
    else if ADeadline.Reached then
    begin
      Result.Ended := TAtlasAsyncEnd.Timeout;
    end
    else
    begin
      Result.Completed := AIsCompleted();
    end;
  end;
  if Result.Ended <> TAtlasAsyncEnd.Done then
  begin
    ACancel();
    Result.Completed := AIsCompleted();
  end;
end;

class procedure TAtlasAsyncWait.Finish(const AIsCompleted: TFunc<Boolean>);
begin
  // Ohne Frist und ohne Abbruchsignal: Solange die Anfrage läuft, gehören Client und Streams ihr.
  while not AIsCompleted() do
  begin
    Sleep(cFinishSliceMs);
  end;
end;

class function TAtlasAsyncWait.AwaitSettled(const AIsCompleted: TFunc<Boolean>; const ACancel: TProc;
  const ADeadline: TAtlasDeadline; const ACancelled: TFunc<Boolean>): TAtlasAsyncEnd;
var
  mResult: TAtlasAsyncResult;
begin
  mResult := Await(AIsCompleted, ACancel, ADeadline, ACancelled);
  if not mResult.Completed then
  begin
    Finish(AIsCompleted);
  end;
  Result := mResult.Ended;
end;

class function TAtlasAsyncWait.ConnectTimeout(ATimeoutMs: Integer): Integer;
begin
  Result := Min(Max(ATimeoutMs, 0), cConnectMs);
end;

end.
