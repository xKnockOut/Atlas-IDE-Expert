unit Atlas.Core.Editor.PlaceholderPlan;

// Entscheidungen des Platzhalter-Modus im Editor (#51, Atlas.IDE.Completion.Placeholders), ohne VCL und Open Tools
// API: welche Taste der Modus nimmt und was sie tut, die Verschiebung des Cursors durch angeglichene Platzhalter,
// der gemeinsame Anfang und das gemeinsame Ende für den einen Undo-Schritt, Art und Spalten der Rahmen in einer Zeile
// und die Stelle der Fußzeile.

{$SCOPEDENUMS ON}

interface

uses
  System.Classes,
  Atlas.Core.Completion.Placeholders;

type
  /// <summary>Taste im Platzhalter-Modus.</summary>
  TAtlasPlaceholderKey = (
    /// <summary>Nicht nehmen.</summary>
    None,
    /// <summary>Tab: zum nächsten Platzhalter, nach dem letzten an die Endposition.</summary>
    Next,
    /// <summary>Umschalt+Tab: zum vorigen Platzhalter.</summary>
    Previous,
    /// <summary>Enter: beenden, an die Endposition.</summary>
    Accept,
    /// <summary>Esc: an Ort und Stelle beenden.</summary>
    Cancel);

  /// <summary>Rahmen eines Platzhalters.</summary>
  TAtlasPlaceholderFrame = (
    /// <summary>Aktueller Platzhalter: durchgezogen, Akzentfarbe.</summary>
    Current,
    /// <summary>Verknüpft mit dem aktuellen (gleiche Nummer): gestrichelt, Akzentfarbe.</summary>
    Linked,
    /// <summary>Übrige: gepunktet, gedämpft.</summary>
    Other);

  /// <summary>Teil eines Platzhalters in einer Zeile: Zeichen (0-basiert) von Start bis Stop.</summary>
  TAtlasPlaceholderSpan = record
    Start: Integer;
    Stop: Integer;
  end;

  /// <summary>Ersetzter Bereich zwischen zwei Texten: gleicher Anfang und gleiches Ende in Zeichen.</summary>
  TAtlasPlaceholderReplacement = record
    Prefix: Integer;
    Suffix: Integer;
  end;

  TAtlasPlaceholderPlan = record
  public const
    /// <summary>Tastencodes wie in Winapi.Windows.</summary>
    cVkTab = $09;
    cVkReturn = $0D;
    cVkEscape = $1B;
    /// <summary>Abstand der Fußzeile hinter dem Zeilenende in Spalten.</summary>
    cFooterGap = 3;
  public
    /// <summary>Taste AKey mit AShift bei laufendem Modus (AActive).</summary>
    class function Key(AKey: Word; AShift: TShiftState; AActive: Boolean): TAtlasPlaceholderKey; static;
    /// <summary>Verschiebung des Cursors ACursor (Zeichen) durch die Angleichungen AEdits davor.</summary>
    class function CursorShift(const AEdits: TAtlasPlaceholderEdits; ACursor: Integer): Integer; static;
    /// <summary>Gemeinsamer Anfang und gemeinsames Ende von ABefore und AAfter; dazwischen ersetzt ein Schreiber.
    /// </summary>
    class function Replacement(const ABefore, AAfter: string): TAtlasPlaceholderReplacement; static;
    /// <summary>Rahmen von AField, wenn ACurrent der aktuelle Platzhalter ist.</summary>
    class function FrameOf(const AField, ACurrent: TAtlasPlaceholderField): TAtlasPlaceholderFrame; static;
    /// <summary>Teil von AField in der Zeile ALine (0-basiert, Text ALineText) des Texts AText; False, wenn er nicht
    /// in dieser Zeile beginnt. Reicht er weiter, endet der Teil am Zeilenende.</summary>
    class function SpanOn(const AText: string; const AField: TAtlasPlaceholderField; ALine: Integer;
      const ALineText: string; out ASpan: TAtlasPlaceholderSpan): Boolean; static;
    /// <summary>Beginnt der aktuelle Platzhalter ACurrent in der Zeile ALine von AText (dort steht die Fußzeile)?
    /// </summary>
    class function FooterOn(const AText: string; const ACurrent: TAtlasPlaceholderField; ALine: Integer): Boolean;
      static;
    /// <summary>Editorspalte (1-basiert) der Fußzeile hinter ALineText.</summary>
    class function FooterColumn(const ALineText: string; ATabWidth: Integer): Integer; static;
  end;

implementation

uses
  Atlas.Core.Editor.Pairs;

{ TAtlasPlaceholderPlan }

class function TAtlasPlaceholderPlan.Key(AKey: Word; AShift: TShiftState; AActive: Boolean): TAtlasPlaceholderKey;
begin
  Result := TAtlasPlaceholderKey.None;
  if not AActive then
  begin
    Exit;
  end;
  if (AKey = cVkTab) and (AShift = []) then
  begin
    Result := TAtlasPlaceholderKey.Next;
  end
  else if (AKey = cVkTab) and (AShift = [ssShift]) then
  begin
    Result := TAtlasPlaceholderKey.Previous;
  end
  else if (AKey = cVkReturn) and (AShift = []) then
  begin
    Result := TAtlasPlaceholderKey.Accept;
  end
  else if (AKey = cVkEscape) and (AShift = []) then
  begin
    Result := TAtlasPlaceholderKey.Cancel;
  end;
end;

class function TAtlasPlaceholderPlan.CursorShift(const AEdits: TAtlasPlaceholderEdits; ACursor: Integer): Integer;
var
  mEdit: TAtlasPlaceholderEdit;
begin
  Result := 0;
  for mEdit in AEdits do
  begin
    if mEdit.Stop <= ACursor then
    begin
      Inc(Result, Length(mEdit.Text) - (mEdit.Stop - mEdit.Start));
    end;
  end;
end;

class function TAtlasPlaceholderPlan.Replacement(const ABefore, AAfter: string): TAtlasPlaceholderReplacement;
begin
  Result.Prefix := 0;
  while (Result.Prefix < Length(ABefore)) and (Result.Prefix < Length(AAfter)) and
    (ABefore[Result.Prefix + 1] = AAfter[Result.Prefix + 1]) do
  begin
    Inc(Result.Prefix);
  end;
  Result.Suffix := 0;
  while (Result.Suffix < Length(ABefore) - Result.Prefix) and (Result.Suffix < Length(AAfter) - Result.Prefix) and
    (ABefore[Length(ABefore) - Result.Suffix] = AAfter[Length(AAfter) - Result.Suffix]) do
  begin
    Inc(Result.Suffix);
  end;
end;

class function TAtlasPlaceholderPlan.FrameOf(const AField, ACurrent: TAtlasPlaceholderField):
  TAtlasPlaceholderFrame;
begin
  if AField.Number <> ACurrent.Number then
  begin
    Result := TAtlasPlaceholderFrame.Other;
  end
  else if AField.Start = ACurrent.Start then
  begin
    Result := TAtlasPlaceholderFrame.Current;
  end
  else
  begin
    Result := TAtlasPlaceholderFrame.Linked;
  end;
end;

class function TAtlasPlaceholderPlan.SpanOn(const AText: string; const AField: TAtlasPlaceholderField;
  ALine: Integer; const ALineText: string; out ASpan: TAtlasPlaceholderSpan): Boolean;
var
  mStartLine, mEndLine: Integer;
begin
  TAtlasPlaceholderSession.Locate(AText, AField.Start, mStartLine, ASpan.Start);
  TAtlasPlaceholderSession.Locate(AText, AField.Stop, mEndLine, ASpan.Stop);
  Result := mStartLine = ALine;
  if Result and (mEndLine <> ALine) then
  begin
    ASpan.Stop := Length(ALineText);
  end;
end;

class function TAtlasPlaceholderPlan.FooterOn(const AText: string; const ACurrent: TAtlasPlaceholderField;
  ALine: Integer): Boolean;
var
  mLine, mCharacter: Integer;
begin
  TAtlasPlaceholderSession.Locate(AText, ACurrent.Start, mLine, mCharacter);
  Result := mLine = ALine;
end;

class function TAtlasPlaceholderPlan.FooterColumn(const ALineText: string; ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(ALineText, ATabWidth)) + 1 + cFooterGap;
end;

end.
