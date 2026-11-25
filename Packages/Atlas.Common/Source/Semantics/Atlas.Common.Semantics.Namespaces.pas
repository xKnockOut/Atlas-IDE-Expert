unit Atlas.Common.Semantics.Namespaces;

// Namespaces der LSP-Features: Die Komposition ersetzt sie
// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads. Die Zuweisung
// eines dynamischen Arrays ist nicht atomar (Referenzzähler); deshalb lesen und
// schreiben alle Features unter einer kurzen gemeinsamen Sperre.

interface

type
  TSharedNamespaces = class
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

uses
  Atlas.Text.Locked;

{ TSharedNamespaces }

class constructor TSharedNamespaces.Create;
begin
  FLock := TAtlasSharedLock.New;
end;

class destructor TSharedNamespaces.Destroy;
begin
  FLock.Free;
end;

class function TSharedNamespaces.Read(var AField: TArray<string>): TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := AField;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSharedNamespaces.Write(var AField: TArray<string>; const AValue: TArray<string>);
begin
  TMonitor.Enter(FLock);
  try
    AField := AValue;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
