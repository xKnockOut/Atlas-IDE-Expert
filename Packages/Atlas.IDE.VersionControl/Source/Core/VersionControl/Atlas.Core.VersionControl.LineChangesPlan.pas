unit Atlas.Core.VersionControl.LineChangesPlan;

// Entscheidungen der Änderungsmarken und der Zeilenhistorie im Editor (#507),
// ohne VCL und Open Tools API. Atlas.IDE.VersionControl.LineChanges und
// Atlas.IDE.VersionControl.LineChangesData zeichnen, nehmen Maus und
// Zeitgeber und starten die Arbeit im Hintergrund; was sie dabei
// entscheiden, steht hier:
// - Ob die Marken laufen, ob jetzt verglichen wird (Tipp-Pause), ob der
//   Vergleich zum Puffer gehört, ob blame für die ganzen Nachrichten neu muss
//   und welcher Eintrag von blame zu einer Zeile der Platte gehört.
// - Breite des Balkens, Größe des Dreiecks, ob eine Marke noch dort steht,
//   ob ein Klick den alten Stand öffnet und welche Zeile die Historie zeigt.
// - Überfahren: Fenster „alter Stand“ und Hover des Commits.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.VersionControl.Contract;

type
  /// <summary>Was das Fenster „alter Stand“ beim Takt tut.</summary>
  TAtlasChangeTipStep = (
    /// <summary>Offen lassen.</summary>
    Stay,
    /// <summary>Die Maus ist im Fenster: das Betreten merken.</summary>
    Entered,
    /// <summary>Nach dem Betreten wieder verlassen: schließen.</summary>
    Close);

  /// <summary>Was der Hover des Commits beim Takt tut.</summary>
  TAtlasBlameHoverStep = (
    /// <summary>Nichts (Wartezeit läuft oder schon sichtbar).</summary>
    Stay,
    /// <summary>Maus nicht mehr über Anzeige oder Fenster: schließen.</summary>
    Close,
    /// <summary>Lange genug überfahren: zeigen.</summary>
    Show);

  TAtlasLineChangesPlan = record
  public const
    /// <summary>Tipp-Pause vor dem Vergleich.</summary>
    cQuietMs = 300;
    /// <summary>So lange überfahren, bis der Commit erscheint.</summary>
    cHoverMs = 400;
  public
    /// <summary>Laufen Marken bzw. Historie? Eines eingeschaltet und die Funktion nicht abgeschaltet.</summary>
    class function Active(AGutter, ABlame, ADisabled: Boolean): Boolean; static;
    /// <summary>Jetzt vergleichen? Stand im Repository da, kein Vergleich unterwegs, AText weicht vom zuletzt
    /// verglichenen ACompared ab und die Tipp-Pause seit AChangedAt ist um.</summary>
    class function ComparesNow(AHeadOk, ABusy: Boolean; const AText, ACompared: string;
      AChangedAt, ANowMs: UInt64): Boolean; static;
    /// <summary>Gehört der letzte Vergleich (ACompared, mit Zeilen AHasLines) zum Text AText im Puffer?</summary>
    class function Fresh(AHeadOk: Boolean; const ACompared, AText: string; AHasLines: Boolean): Boolean; static;
    /// <summary>blame neu, weil die ganzen Nachrichten jetzt gewollt sind (AWanted), das letzte blame (ABlameOk)
    /// sie aber nicht geladen hat (ALoadedWithMessages)?</summary>
    class function ReloadsForMessages(ABlameOk, ALoadedWithMessages, AWanted: Boolean): Boolean; static;
    /// <summary>Eintrag von blame für Zeile ADiskLine (0-basiert) der Platte; -1 ohne.</summary>
    class function EntryOf(const ALines: TArray<TAtlasVcsBlameLine>; ADiskLine: Integer): Integer; static;
    /// <summary>Breite des Balkens in der Rinne zur Zeilenhöhe ARowHeight (3/16, mindestens 3 Pixel).</summary>
    class function BarWidth(ARowHeight: Integer): Integer; static;
    /// <summary>Größe des Dreiecks einer Löschung zur Zeilenhöhe ARowHeight (ein Drittel, mindestens 4).</summary>
    class function DeletedSize(ARowHeight: Integer): Integer; static;
    /// <summary>Steht die gemerkte Marke noch dort? Gleiche Datei (Groß/klein egal), nicht gescrollt und die
    /// Änderung AChange gibt es noch (bis AHighChange).</summary>
    class function MarkStillThere(const ARowFile, AViewFile: string; ARowTop, AViewTop, AChange,
      AHighChange: Integer): Boolean; static;
    /// <summary>Öffnet der Klick den alten Stand? Linke Taste ohne Umschalt, Strg und Alt, Marken an, Vergleich
    /// aktuell.</summary>
    class function OpensChange(ALeftButton, AModifier, AGutterOn, AFresh: Boolean): Boolean; static;
    /// <summary>Zeigt Zeile ALine die Historie? Nur die Cursorzeile ACursorLine, eingeschaltet und nicht
    /// abgeschaltet (AEnabled), blame da, die Datei vorn und der Vergleich aktuell.</summary>
    class function BlameOnLine(AEnabled, ABlameOk, ASameFile, AFresh: Boolean; ACursorLine, ALine: Integer): Boolean;
      static;
    /// <summary>Hat der Hover einen Commit? Gespeicherte Zeile, Eintrag von blame, übernommen.</summary>
    class function CommitShown(AUnsaved, AHasEntry, AUncommitted: Boolean): Boolean; static;
    /// <summary>Fenster „alter Stand“: Maus darin (AInside), schon einmal betreten (AEntered).</summary>
    class function ChangeTipStep(AInside, AEntered: Boolean): TAtlasChangeTipStep; static;
    /// <summary>Hover des Commits: Maus über Anzeige oder Fenster (AInside), Fenster sichtbar (ATipShown),
    /// überfahren seit ASince.</summary>
    class function BlameHoverStep(AInside, ATipShown: Boolean; ASince, ANowMs: UInt64): TAtlasBlameHoverStep;
      static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasLineChangesPlan }

class function TAtlasLineChangesPlan.Active(AGutter, ABlame, ADisabled: Boolean): Boolean;
begin
  Result := (AGutter or ABlame) and not ADisabled;
end;

class function TAtlasLineChangesPlan.ComparesNow(AHeadOk, ABusy: Boolean; const AText, ACompared: string;
  AChangedAt, ANowMs: UInt64): Boolean;
begin
  Result := AHeadOk and not ABusy and (AText <> ACompared) and (ANowMs - AChangedAt >= cQuietMs);
end;

class function TAtlasLineChangesPlan.Fresh(AHeadOk: Boolean; const ACompared, AText: string;
  AHasLines: Boolean): Boolean;
begin
  Result := AHeadOk and (ACompared = AText) and AHasLines;
end;

class function TAtlasLineChangesPlan.ReloadsForMessages(ABlameOk, ALoadedWithMessages, AWanted: Boolean): Boolean;
begin
  Result := ABlameOk and not ALoadedWithMessages and AWanted;
end;

class function TAtlasLineChangesPlan.EntryOf(const ALines: TArray<TAtlasVcsBlameLine>; ADiskLine: Integer): Integer;
var
  mIndex: Integer;
begin
  // blame liefert die Zeilen der Reihe nach; sonst suchen.
  if (ADiskLine >= 0) and (ADiskLine <= High(ALines)) and (ALines[ADiskLine].Line = ADiskLine + 1) then
  begin
    Exit(ADiskLine);
  end;
  Result := -1;
  mIndex := 0;
  while (Result < 0) and (mIndex <= High(ALines)) do
  begin
    if ALines[mIndex].Line = ADiskLine + 1 then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

class function TAtlasLineChangesPlan.BarWidth(ARowHeight: Integer): Integer;
const
  cMinimum = 3;
  cParts = 16;
begin
  // Kaufmännisch gerundet wie MulDiv(3, ARowHeight, 16).
  Result := (cMinimum * ARowHeight + cParts div 2) div cParts;
  if Result < cMinimum then
  begin
    Result := cMinimum;
  end;
end;

class function TAtlasLineChangesPlan.DeletedSize(ARowHeight: Integer): Integer;
const
  cMinimum = 4;
  cParts = 3;
begin
  Result := ARowHeight div cParts;
  if Result < cMinimum then
  begin
    Result := cMinimum;
  end;
end;

class function TAtlasLineChangesPlan.MarkStillThere(const ARowFile, AViewFile: string; ARowTop, AViewTop,
  AChange, AHighChange: Integer): Boolean;
begin
  Result := SameText(ARowFile, AViewFile) and (ARowTop = AViewTop) and (AChange >= 0) and
    (AChange <= AHighChange);
end;

class function TAtlasLineChangesPlan.OpensChange(ALeftButton, AModifier, AGutterOn, AFresh: Boolean): Boolean;
begin
  Result := ALeftButton and not AModifier and AGutterOn and AFresh;
end;

class function TAtlasLineChangesPlan.BlameOnLine(AEnabled, ABlameOk, ASameFile, AFresh: Boolean; ACursorLine,
  ALine: Integer): Boolean;
begin
  Result := AEnabled and ABlameOk and (ACursorLine = ALine) and ASameFile and AFresh;
end;

class function TAtlasLineChangesPlan.CommitShown(AUnsaved, AHasEntry, AUncommitted: Boolean): Boolean;
begin
  Result := not AUnsaved and AHasEntry and not AUncommitted;
end;

class function TAtlasLineChangesPlan.ChangeTipStep(AInside, AEntered: Boolean): TAtlasChangeTipStep;
begin
  Result := TAtlasChangeTipStep.Stay;
  if AInside then
  begin
    Result := TAtlasChangeTipStep.Entered;
  end
  else if AEntered then
  begin
    Result := TAtlasChangeTipStep.Close;
  end;
end;

class function TAtlasLineChangesPlan.BlameHoverStep(AInside, ATipShown: Boolean; ASince,
  ANowMs: UInt64): TAtlasBlameHoverStep;
begin
  Result := TAtlasBlameHoverStep.Stay;
  if not AInside then
  begin
    Result := TAtlasBlameHoverStep.Close;
  end
  else if not ATipShown and (ANowMs - ASince >= cHoverMs) then
  begin
    Result := TAtlasBlameHoverStep.Show;
  end;
end;

end.
