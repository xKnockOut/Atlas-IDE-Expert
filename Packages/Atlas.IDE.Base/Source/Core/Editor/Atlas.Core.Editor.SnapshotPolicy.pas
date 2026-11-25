unit Atlas.Core.Editor.SnapshotPolicy;

// Wann der gemeinsame Pufferstand neu gelesen werden muss, ohne VCL und
// Open Tools API: unbekannt, als veraltet markiert (Änderungsereignis),
// andere Zeilenzahl, anderer Änderungsstatus oder das Sicherheitsnetz für
// Änderungen ohne Ereignis abgelaufen.
//
// Der Abstand des Sicherheitsnetzes passt sich je Puffer an: Findet ein Lesen
// des Netzes nichts Neues, verdoppelt er sich bis cSafetyMaxMs. Hat sich der
// Text geändert, mit oder ohne Ereignis, springt er auf cSafetyMs zurück. Ein
// Lesen, das ein Ereignis ausgelöst hat und nichts findet, lässt ihn stehen.
// So liest das Netz einen ruhenden Puffer nicht dauerhaft alle zwei Sekunden.

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
    /// <summary>Jetziger Abstand des Sicherheitsnetzes in ms; 0 steht für cSafetyMs.</summary>
    SafetyMs: Cardinal;
  end;

  TAtlasSnapshotPolicy = class
  public const
    /// <summary>Kürzester Abstand des Sicherheitsnetzes, gilt nach jeder Textänderung.</summary>
    cSafetyMs = 2000;
    /// <summary>Längster Abstand des Sicherheitsnetzes bei ruhendem Puffer.</summary>
    cSafetyMaxMs = 32000;
  public
    /// <summary>True, wenn der Puffer gelesen werden muss; ALines und AModified sind der jetzige Stand.</summary>
    class function MustRead(const AState: TAtlasSnapshotState; ALines: Integer; AModified: Boolean;
      ANow: UInt64): Boolean; static;
    /// <summary>Jetziger Abstand des Sicherheitsnetzes von AState in ms.</summary>
    class function SafetyMs(const AState: TAtlasSnapshotState): Cardinal; static;
    /// <summary>Trägt ein Lesen zum Zeitpunkt ANow in AState ein (ALines, AModified wie bei MustRead);
    /// ATextChanged: Der gelesene Text weicht vom gemerkten ab.</summary>
    class procedure Read(var AState: TAtlasSnapshotState; ALines: Integer; AModified: Boolean; ANow: UInt64;
      ATextChanged: Boolean); static;
  end;

implementation

function EventPending(const AState: TAtlasSnapshotState; ALines: Integer; AModified: Boolean): Boolean;
begin
  Result := not AState.Known or AState.Dirty or (AState.Lines <> ALines) or (AState.Modified <> AModified);
end;

function NextSafetyMs(ACurrent: Cardinal): Cardinal;
begin
  Result := TAtlasSnapshotPolicy.cSafetyMaxMs;
  if ACurrent < TAtlasSnapshotPolicy.cSafetyMaxMs div 2 then
  begin
    Result := 2 * ACurrent;
  end;
end;

{ TAtlasSnapshotPolicy }

class function TAtlasSnapshotPolicy.MustRead(const AState: TAtlasSnapshotState; ALines: Integer;
  AModified: Boolean; ANow: UInt64): Boolean;
begin
  if EventPending(AState, ALines, AModified) then
  begin
    Exit(True);
  end;
  // Uhr zurückgesetzt (ANow vor ReadAt, etwa im Test): lieber einmal zu oft lesen.
  if ANow < AState.ReadAt then
  begin
    Exit(True);
  end;
  Result := ANow - AState.ReadAt >= SafetyMs(AState);
end;

class function TAtlasSnapshotPolicy.SafetyMs(const AState: TAtlasSnapshotState): Cardinal;
begin
  Result := AState.SafetyMs;
  if Result < cSafetyMs then
  begin
    Result := cSafetyMs;
  end;
  if Result > cSafetyMaxMs then
  begin
    Result := cSafetyMaxMs;
  end;
end;

class procedure TAtlasSnapshotPolicy.Read(var AState: TAtlasSnapshotState; ALines: Integer; AModified: Boolean;
  ANow: UInt64; ATextChanged: Boolean);
var
  mSafety: Cardinal;
begin
  mSafety := SafetyMs(AState);
  if ATextChanged or not AState.Known then
  begin
    mSafety := cSafetyMs;
  end
  else if not EventPending(AState, ALines, AModified) and (ANow >= AState.ReadAt) then
  begin
    // Nur das Netz hat gelesen und nichts gefunden: länger warten.
    mSafety := NextSafetyMs(mSafety);
  end;
  AState.Known := True;
  AState.Dirty := False;
  AState.Lines := ALines;
  AState.Modified := AModified;
  AState.ReadAt := ANow;
  AState.SafetyMs := mSafety;
end;

end.
