unit Atlas.Text.Locked;

// Sperren für Server und Plugin: Felder unter der Sperre ihres Besitzers lesen (Getter, die nur ein Feld unter
// einer TCriticalSection kopieren, schreiben das mit einer Zeile statt Enter/try/finally/Leave) und Sperrobjekte
// für Daten anlegen, die ein ganzer Prozess teilt.

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

  /// <summary>Sperrobjekte für TMonitor, die Daten des ganzen Prozesses schützen (Unit- und Klassenvariablen,
  /// gemeinsame Dienste) und bis zum Programmende leben.</summary>
  TAtlasSharedLock = record
  public
    /// <summary>Neues Sperrobjekt, dessen Monitor-Datensatz schon besteht. TMonitor legt ihn sonst beim ersten
    /// Sperren an, in dem Thread, der zufällig zuerst sperrt, und hält ihn bis zur Freigabe des Objekts. So belegt
    /// keine Sperrung im Betrieb Speicher, und Speicher- wie Zeitmessungen eines ersten Aufrufs zeigen nur dessen
    /// eigene Arbeit. Gemeinsame Sperren entstehen deshalb nur hier; freigegeben wird mit Free.</summary>
    class function New: TObject; static;
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

{ TAtlasSharedLock }

class function TAtlasSharedLock.New: TObject;
begin
  Result := TObject.Create;
  TMonitor.Enter(Result);
  TMonitor.Exit(Result);
end;

end.
