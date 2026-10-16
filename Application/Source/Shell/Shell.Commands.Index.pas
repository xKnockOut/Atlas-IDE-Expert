unit Shell.Commands.Index;

// Host-Rolle Shell: Fachlogik des Befehls "Index löschen" (#492) ohne Bezug auf
// TServerComposition (S-02). Löscht alle Index-Caches unter einem Ordner (auch
// anderer Projekte und IDE-Versionen; gesperrte Caches anderer Serverinstanzen
// bleiben) und baut die Antwort. Arbeitsbereiche gibt die Komposition vorher
// frei und indiziert sie danach neu.

interface

uses
  System.JSON;

type
  TIndexCommands = class
  public
    /// <summary>Löscht die Caches unter ARoot; liefert ihre Zahl, AFreed die freigewordenen Bytes.</summary>
    class function ClearCaches(const ARoot: string; out AFreed: Int64): Integer; static;
    /// <summary>Antwort {"removed": n, "freedBytes": n}.</summary>
    class function Answer(ARemoved: Integer; AFreed: Int64): TJSONObject; static;
  end;

implementation

uses
  Atlas.Common.Index.Adapters.CacheDirectory;

class function TIndexCommands.ClearCaches(const ARoot: string; out AFreed: Int64): Integer;
var
  Before: Int64;
begin
  Before := TIndexCacheDirectory.TotalSize(ARoot);
  Result := TIndexCacheDirectory.Clear(ARoot);
  AFreed := Before - TIndexCacheDirectory.TotalSize(ARoot);
end;

class function TIndexCommands.Answer(ARemoved: Integer; AFreed: Int64): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('removed', TJSONNumber.Create(ARemoved));
  Result.AddPair('freedBytes', TJSONNumber.Create(AFreed));
end;

end.
