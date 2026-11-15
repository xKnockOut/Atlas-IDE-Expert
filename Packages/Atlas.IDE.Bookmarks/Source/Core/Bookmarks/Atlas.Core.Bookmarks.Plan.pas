unit Atlas.Core.Bookmarks.Plan;

// Entscheidungen des Lesezeichen-Dienstes und der Anmeldung des Moduls
// (#622, #1104), ohne VCL und Open Tools API. Atlas.IDE.Bookmarks.Service und
// Atlas.IDE.Bookmarks.Composition fragen hier:
// - Schlüssel einer Datei bzw. eines Projekts in den Listen im Speicher.
// - Ob Lesezeichen überhaupt laufen (benannte oder schnelle an), ob die
//   Spalte der schnellen sichtbar ist (eingeschaltet und von der IDE
//   gezeichnet, #1281) und welche Lesezeichen einer Zeile die Rinne der
//   benannten zeigt.
// - Text eines Eintrags im Fenster „Gehe zu Lesezeichen…“, Ablauf des
//   Hinweises im Statusfeld.
// - Tasten der Befehle je nach Einstellung, Kennungen der Zifferntasten und
//   ob die Spalte der schnellen Lesezeichen in einer Startstufe läuft.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Modules.Contract;

type
  TAtlasBookmarksPlan = record
  public const
    cJumpIdPrefix = 'Atlas.QuickBookmarkJump';
    cSetIdPrefix = 'Atlas.QuickBookmarkSet';
  public
    /// <summary>Schlüssel einer Datei oder eines Projekts: klein, ohne Rand, „/“ als „\“.</summary>
    class function Key(const APath: string): string; static;
    /// <summary>Laufen Lesezeichen (benannte oder schnelle an)?</summary>
    class function Available(ANamed, AQuick: Boolean): Boolean; static;
    /// <summary>Spalte der schnellen Lesezeichen sichtbar: von der IDE gezeichnet und eingeschaltet.</summary>
    class function ColumnShown(APainted, AQuick, AGutter: Boolean): Boolean; static;
    /// <summary>Zeigt die Rinne der benannten das Lesezeichen? Nur benannte (ANamed); nummerierte nicht, solange
    /// die Spalte sichtbar ist (sie zeigt sie dort).</summary>
    class function InNamedGutter(ANamed: Boolean; ANumber: Integer; AColumnShown: Boolean): Boolean; static;
    /// <summary>Text im Fenster „Gehe zu Lesezeichen…“: mit Nummer „3 · Name“.</summary>
    class function PaletteCaption(ANumber: Integer; const AName: string): string; static;
    /// <summary>Hinweis im Statusfeld ablaufen lassen? AStatusAt 0 = kein Hinweis.</summary>
    class function StatusExpired(AStatusAt, ANowMs, AShowMs: UInt64): Boolean; static;
    /// <summary>Taste AKey, wenn AOn; sonst 0 (kein Kürzel).</summary>
    class function KeyWhen(AOn: Boolean; AKey: Integer): Integer; static;
    /// <summary>Taste für „Schnelles Lesezeichen“: nur mit schnellen Lesezeichen und Wartezeit für die zweite
    /// Taste.</summary>
    class function ChordKey(AQuick: Boolean; AChordWait, AKey: Integer): Integer; static;
    /// <summary>Kennung der Zifferntaste ANumber: springen bzw. Nummer setzen.</summary>
    class function NumberCommandId(ANumber: Integer; AJump: Boolean): string; static;
    /// <summary>Läuft die Spalte in der Startstufe ALevel? Im normalen Start immer, im abgesicherten nur mit
    /// schnellen Lesezeichen, im minimalen nie.</summary>
    class function QuickColumnRuns(ALevel: TAtlasSafeLevel; AQuick: Boolean): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasBookmarksPlan }

class function TAtlasBookmarksPlan.Key(const APath: string): string;
begin
  Result := LowerCase(Trim(APath)).Replace('/', '\');
end;

class function TAtlasBookmarksPlan.Available(ANamed, AQuick: Boolean): Boolean;
begin
  Result := ANamed or AQuick;
end;

class function TAtlasBookmarksPlan.ColumnShown(APainted, AQuick, AGutter: Boolean): Boolean;
begin
  Result := APainted and AQuick and AGutter;
end;

class function TAtlasBookmarksPlan.InNamedGutter(ANamed: Boolean; ANumber: Integer; AColumnShown: Boolean): Boolean;
begin
  Result := ANamed and not (AColumnShown and (ANumber > 0));
end;

class function TAtlasBookmarksPlan.PaletteCaption(ANumber: Integer; const AName: string): string;
begin
  Result := AName;
  if ANumber > 0 then
  begin
    Result := IntToStr(ANumber) + ' · ' + Result;
  end;
end;

class function TAtlasBookmarksPlan.StatusExpired(AStatusAt, ANowMs, AShowMs: UInt64): Boolean;
begin
  Result := (AStatusAt <> 0) and (ANowMs - AStatusAt >= AShowMs);
end;

class function TAtlasBookmarksPlan.KeyWhen(AOn: Boolean; AKey: Integer): Integer;
begin
  Result := 0;
  if AOn then
  begin
    Result := AKey;
  end;
end;

class function TAtlasBookmarksPlan.ChordKey(AQuick: Boolean; AChordWait, AKey: Integer): Integer;
begin
  Result := KeyWhen(AQuick and (AChordWait > 0), AKey);
end;

class function TAtlasBookmarksPlan.NumberCommandId(ANumber: Integer; AJump: Boolean): string;
begin
  if AJump then
  begin
    Result := cJumpIdPrefix + IntToStr(ANumber);
  end
  else
  begin
    Result := cSetIdPrefix + IntToStr(ANumber);
  end;
end;

class function TAtlasBookmarksPlan.QuickColumnRuns(ALevel: TAtlasSafeLevel; AQuick: Boolean): Boolean;
begin
  Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or AQuick);
end;

end.
