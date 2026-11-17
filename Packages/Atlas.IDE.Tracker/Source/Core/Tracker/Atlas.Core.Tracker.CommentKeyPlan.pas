unit Atlas.Core.Tracker.CommentKeyPlan;

// Tasten im Kommentarfeld von Atlas (#1278), ohne VCL und Open Tools API:
// - Strg+Enter sendet, auch im einfachen Feld (issues.commentEditor aus).
// - Mit offener Vorschlagsliste: Pfeile und Bild auf/ab wählen, Enter oder Tab
//   ohne Umschalter fügen ein, Esc schließt die Liste; Pfeil links/rechts,
//   Pos1 und Ende verlassen das Wort und schließen sie ebenfalls, die Taste
//   bewegt die Schreibmarke trotzdem.
// - Sonst: Esc bricht ab, Strg+Leer öffnet die Textbausteine, Strg+B fett,
//   Strg+I kursiv, Strg+Umschalt+K Code-Block.

interface

uses
  System.Classes;

type
  /// <summary>Was eine Taste im Feld auslöst.</summary>
  {$SCOPEDENUMS ON}
  TAtlasCommentKey = (None, Send, Cancel, Up, Down, PageUp, PageDown, Accept, CloseList, Snippets, Bold, Italic,
    Code, LeaveWord);
  {$SCOPEDENUMS OFF}

  TAtlasCommentKeyPlan = record
  public const
    // Virtuelle Tastencodes wie in Windows (VK_…); System.UITypes von FPC kennt sie nicht.
    cKeyTab = 9;
    cKeyReturn = 13;
    cKeyEscape = 27;
    cKeySpace = 32;
    cKeyPrior = 33;
    cKeyNext = 34;
    cKeyEnd = 35;
    cKeyHome = 36;
    cKeyLeft = 37;
    cKeyUp = 38;
    cKeyRight = 39;
    cKeyDown = 40;
  public
    /// <summary>Wirkung der Taste AKey (virtueller Code) mit AShift; AEnhanced: Ergänzung und Kürzel an,
    /// AListShown: Vorschlagsliste offen.</summary>
    class function Action(AKey: Word; AShift: TShiftState; AEnhanced, AListShown: Boolean): TAtlasCommentKey; static;
    /// <summary>Kommt das Zeichen der Taste nicht ins Feld (Strg+I wäre ein Tab, Strg+Enter ein Zeilenvorschub)?
    /// Das Verlassen des Worts bewegt die Schreibmarke trotzdem.</summary>
    class function Swallows(AAction: TAtlasCommentKey): Boolean; static;
  end;

implementation

/// <summary>Tasten, solange die Vorschlagsliste offen ist.</summary>
function ListKey(AKey: Word; AShift: TShiftState): TAtlasCommentKey;
begin
  Result := TAtlasCommentKey.None;
  case AKey of
    TAtlasCommentKeyPlan.cKeyUp:
      Result := TAtlasCommentKey.Up;
    TAtlasCommentKeyPlan.cKeyDown:
      Result := TAtlasCommentKey.Down;
    TAtlasCommentKeyPlan.cKeyPrior:
      Result := TAtlasCommentKey.PageUp;
    TAtlasCommentKeyPlan.cKeyNext:
      Result := TAtlasCommentKey.PageDown;
    TAtlasCommentKeyPlan.cKeyReturn, TAtlasCommentKeyPlan.cKeyTab:
      if AShift = [] then
      begin
        Result := TAtlasCommentKey.Accept;
      end;
    TAtlasCommentKeyPlan.cKeyEscape:
      Result := TAtlasCommentKey.CloseList;
  end;
end;

/// <summary>Esc, Strg+Leer, Strg+B, Strg+I und Strg+Umschalt+K.</summary>
function ShortcutKey(AKey: Word; AShift: TShiftState): TAtlasCommentKey;
begin
  Result := TAtlasCommentKey.None;
  if AKey = TAtlasCommentKeyPlan.cKeyEscape then
  begin
    Result := TAtlasCommentKey.Cancel;
  end
  else if (AKey = TAtlasCommentKeyPlan.cKeySpace) and (AShift = [ssCtrl]) then
  begin
    Result := TAtlasCommentKey.Snippets;
  end
  else if (AKey = Ord('B')) and (AShift = [ssCtrl]) then
  begin
    Result := TAtlasCommentKey.Bold;
  end
  else if (AKey = Ord('I')) and (AShift = [ssCtrl]) then
  begin
    Result := TAtlasCommentKey.Italic;
  end
  else if (AKey = Ord('K')) and (AShift = [ssCtrl, ssShift]) then
  begin
    Result := TAtlasCommentKey.Code;
  end;
end;

/// <summary>Pfeil links/rechts, Pos1, Ende: Die Schreibmarke verlässt das Wort.</summary>
function LeavesWord(AKey: Word): Boolean;
begin
  Result := (AKey = TAtlasCommentKeyPlan.cKeyLeft) or (AKey = TAtlasCommentKeyPlan.cKeyRight) or
    (AKey = TAtlasCommentKeyPlan.cKeyHome) or (AKey = TAtlasCommentKeyPlan.cKeyEnd);
end;

{ TAtlasCommentKeyPlan }

class function TAtlasCommentKeyPlan.Action(AKey: Word; AShift: TShiftState; AEnhanced,
  AListShown: Boolean): TAtlasCommentKey;
begin
  Result := TAtlasCommentKey.None;
  if (AKey = cKeyReturn) and (ssCtrl in AShift) then
  begin
    Result := TAtlasCommentKey.Send;
  end
  else if AEnhanced then
  begin
    if AListShown then
    begin
      Result := ListKey(AKey, AShift);
    end;
    if Result = TAtlasCommentKey.None then
    begin
      Result := ShortcutKey(AKey, AShift);
    end;
    if (Result = TAtlasCommentKey.None) and AListShown and LeavesWord(AKey) then
    begin
      Result := TAtlasCommentKey.LeaveWord;
    end;
  end;
end;

class function TAtlasCommentKeyPlan.Swallows(AAction: TAtlasCommentKey): Boolean;
begin
  Result := (AAction <> TAtlasCommentKey.None) and (AAction <> TAtlasCommentKey.LeaveWord);
end;

end.
