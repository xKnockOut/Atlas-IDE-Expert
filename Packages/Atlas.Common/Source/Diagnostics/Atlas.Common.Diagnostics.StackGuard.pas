unit Atlas.Common.Diagnostics.StackGuard;

// Schutzseite des Stapels nach einem abgefangenen Überlauf (#1094). Windows
// verbraucht beim Stapelüberlauf die Schutzseite des Threads; ohne neue
// Schutzseite beendet der nächste Überlauf den Prozess hart, statt wieder als
// EStackOverflow zu kommen. Wer einen Überlauf abfängt und weiterarbeitet, ruft
// AfterError; die Plattform trägt in Restore ein, wie die Seite neu entsteht
// (unter Windows Atlas.Windows.Diagnostics.StackGuard). Ohne Restore geschieht
// nichts.
//
// Vorbeugen geht vor: Parser und Regel-Engine begrenzen die Tiefe selbst. Das
// hier ist die letzte Sicherung.

interface

uses
  System.SysUtils;

type
  TStackGuardRestore = reference to procedure;

  TStackGuard = record
  private
    class var FRestore: TStackGuardRestore;
    class var FRestored: Integer;
  public
    /// <summary>Nach einem abgefangenen Fehler aufrufen, wenn der Thread weiterarbeitet. Stellt bei
    /// EStackOverflow die Schutzseite wieder her; andere Fehler und nil lässt es unberührt.</summary>
    class procedure AfterError(const AError: Exception); static;
    /// <summary>True, wenn AError ein Stapelüberlauf ist.</summary>
    class function IsOverflow(const AError: Exception): Boolean; static;
    /// <summary>Stellt die Schutzseite des aktuellen Threads wieder her; von der Plattform gesetzt.</summary>
    class property Restore: TStackGuardRestore read FRestore write FRestore;
    /// <summary>Zahl der Wiederherstellungen seit dem Start.</summary>
    class property Restored: Integer read FRestored;
  end;

implementation

class function TStackGuard.IsOverflow(const AError: Exception): Boolean;
begin
  Result := AError is EStackOverflow;
end;

class procedure TStackGuard.AfterError(const AError: Exception);
var
  Action: TStackGuardRestore;
begin
  if not IsOverflow(AError) then
    Exit;
  Action := FRestore;
  if not Assigned(Action) then
    Exit;
  Action();
  AtomicIncrement(FRestored);
end;

end.
