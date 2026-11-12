unit Atlas.Core.Editor.SnapshotPolicy;

// Wann der gemeinsame Pufferstand neu gelesen werden muss, ohne VCL und
// Open Tools API: unbekannt, als veraltet markiert (Änderungsereignis),
// andere Zeilenzahl, anderer Änderungsstatus oder das Sicherheitsnetz für
// Änderungen ohne Ereignis abgelaufen.

interface

type
  TAtlasSnapshotState = record
    /// <summary>Es gibt schon einen gelesenen Stand.</summary>
    Known: Boolean;
    /// <summary>Durch ein Ereignis als veraltet markiert.</summary>
    Dirty: Boolean;
    Lines: Integer;
    Modified: Boolean;
    /// <summary>TAtlasTicks.Now beim letzten Lesen.</summary>
    ReadAt: UInt64;
  end;

  TAtlasSnapshotPolicy = class
  public const
    /// <summary>Spätestens nach dieser Zeit neu lesen, auch ohne Ereignis.</summary>
    cSafetyMs = 2000;
  public
    /// <summary>True, wenn der Puffer gelesen werden muss; ALines und AModified sind der jetzige Stand.</summary>
    class function MustRead(const AState: TAtlasSnapshotState; ALines: Integer; AModified: Boolean;
      ANow: UInt64): Boolean; static;
  end;

implementation

class function TAtlasSnapshotPolicy.MustRead(const AState: TAtlasSnapshotState; ALines: Integer;
  AModified: Boolean; ANow: UInt64): Boolean;
begin
  if not AState.Known or AState.Dirty or (AState.Lines <> ALines) or (AState.Modified <> AModified) then
  begin
    Exit(True);
  end;
  // Uhr zurückgesetzt (ANow vor ReadAt, etwa im Test): lieber einmal zu oft lesen.
  if ANow < AState.ReadAt then
  begin
    Exit(True);
  end;
  Result := ANow - AState.ReadAt >= cSafetyMs;
end;

end.
