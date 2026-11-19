unit Atlas.Text.Locked;

// Felder unter der Sperre ihres Besitzers lesen (gemeinsam für Server und Plugin): Getter, die nur ein Feld
// unter einer TCriticalSection kopieren, schreiben das mit einer Zeile statt Enter/try/finally/Leave.

interface

uses
  System.SyncObjs;

type
  TTextLocked = class
  public
    /// <summary>Kopie von AField, gelesen unter ALock. AField als var, damit die Kopie erst unter der Sperre
    /// entsteht.</summary>
    class function Read<T>(ALock: TCriticalSection; var AField: T): T; static;
  end;

implementation

{ TTextLocked }

class function TTextLocked.Read<T>(ALock: TCriticalSection; var AField: T): T;
begin
  ALock.Enter;
  try
    Result := AField;
  finally
    ALock.Leave;
  end;
end;

end.
