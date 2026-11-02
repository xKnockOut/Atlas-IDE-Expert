unit Atlas.Core.Editor.SnapshotPolicy;

// Wann der gemeinsame Pufferstand neu gelesen werden muss (P-04), ohne VCL und
// Open Tools API: unbekannt, als veraltet markiert (Änderungsereignis),
// andere Zeilenzahl, anderer Änderungsstatus oder das Sicherheitsnetz für
// Änderungen ohne Ereignis abgelaufen (auch bei Überlauf des Tick-Zählers).

interface

type
  TAtlasSnapshotState = record
    /// <summary>Es gibt schon einen gelesenen Stand.</summary>
    Known: Boolean;
    /// <summary>Durch ein Ereignis als veraltet markiert.</summary>
    Dirty: Boolean;
    Lines: Integer;
    Modified: Boolean;
    /// <summary>GetTickCount beim letzten Lesen.</summary>
    ReadAt: Cardinal;
  end;

  TAtlasSnapshotPolicy = class
  public const
    /// <summary>Spätestens nach dieser Zeit neu lesen, auch ohne Ereignis.</summary>
    SafetyMs = 2000;
  public
    /// <summary>True, wenn der Puffer gelesen werden muss; ALines und AModified sind der jetzige Stand.</summary>
    class function MustRead(const AState: TAtlasSnapshotState; ALines: Integer; AModified: Boolean;
      ANow: Cardinal): Boolean; static;
  end;

implementation

class function TAtlasSnapshotPolicy.MustRead(const AState: TAtlasSnapshotState; ALines: Integer;
  AModified: Boolean; ANow: Cardinal): Boolean;
begin
  if not AState.Known or AState.Dirty or (AState.Lines <> ALines) or (AState.Modified <> AModified) then
    Exit(True);
  // Zähler übergelaufen (ANow vor ReadAt): lieber einmal zu oft lesen.
  if ANow < AState.ReadAt then
    Exit(True);
  Result := ANow - AState.ReadAt >= SafetyMs;
end;

end.
