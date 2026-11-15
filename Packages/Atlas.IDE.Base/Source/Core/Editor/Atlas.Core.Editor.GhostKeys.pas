unit Atlas.Core.Editor.GhostKeys;

// Tasten, solange ein Schattenvorschlag am Cursor steht (#1890), ohne Open Tools API: Tab übernimmt alles,
// Strg+→ das nächste Wort, Esc verwirft. Mit anderen Umschalttasten gehört die Taste dem Editor.

{$SCOPEDENUMS ON}

interface

uses
  System.Classes;

type
  TAtlasGhostKey = (
    /// <summary>Keine Taste des Vorschlags: Sie geht an den Editor.</summary>
    None,
    AcceptAll,
    AcceptWord,
    Reject);

  TAtlasGhostKeys = record
  public const
    cKeyTab = $09;
    cKeyEscape = $1B;
    cKeyRight = $27;
  public
    /// <summary>Was die Taste AKey mit AShift beim sichtbaren Vorschlag tut.</summary>
    class function KeyOf(AKey: Word; AShift: TShiftState): TAtlasGhostKey; static;
  end;

implementation

{ TAtlasGhostKeys }

class function TAtlasGhostKeys.KeyOf(AKey: Word; AShift: TShiftState): TAtlasGhostKey;
begin
  Result := TAtlasGhostKey.None;
  if (AKey = cKeyTab) and (AShift = []) then
  begin
    Result := TAtlasGhostKey.AcceptAll;
  end
  else if (AKey = cKeyEscape) and (AShift = []) then
  begin
    Result := TAtlasGhostKey.Reject;
  end
  else if (AKey = cKeyRight) and (AShift = [ssCtrl]) then
  begin
    Result := TAtlasGhostKey.AcceptWord;
  end;
end;

end.
