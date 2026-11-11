unit Atlas.Common.Lsp.Internals.Namespaces;

// Namespaces der LSP-Features: Die Komposition ersetzt sie
// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads. Die Zuweisung
// eines dynamischen Arrays ist nicht atomar (Referenzzähler); deshalb lesen und
// schreiben alle Features unter einer kurzen gemeinsamen Sperre.

interface

type
  TLspNamespaces = class
  strict private
    class var FLock: TObject;
    class constructor Create;
    class destructor Destroy;
  public
    /// <summary>Kopie von AField unter der Sperre. var: Ein const-Parameter könnte schon beim Aufruf
    /// außerhalb der Sperre kopiert werden.</summary>
    class function Read(var AField: TArray<string>): TArray<string>; static;
    /// <summary>Ersetzt AField unter der Sperre durch AValue.</summary>
    class procedure Write(var AField: TArray<string>; const AValue: TArray<string>); static;
  end;

implementation

{ TLspNamespaces }

class constructor TLspNamespaces.Create;
begin
  FLock := TObject.Create;
  // Den Monitor-Datensatz der Sperre gleich anlegen: Sonst entsteht er beim ersten Aufruf und gilt im ersten
  // Test, der Namensräume setzt, als Leck (72 Byte, bis der Klassendestruktor die Sperre freigibt).
  TMonitor.Enter(FLock);
  TMonitor.Exit(FLock);
end;

class destructor TLspNamespaces.Destroy;
begin
  FLock.Free;
end;

class function TLspNamespaces.Read(var AField: TArray<string>): TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := AField;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TLspNamespaces.Write(var AField: TArray<string>; const AValue: TArray<string>);
begin
  TMonitor.Enter(FLock);
  try
    AField := AValue;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
