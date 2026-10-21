unit Atlas.Core.UnitSearch.Sections;

// Einklappbare Abschnitte im Detail-Panel der Unitsuche (#876), Teil ohne VCL:
//   - welche Abschnitte bei gegebener Höhe offen bleiben;
//   - Rangfolge: Typen vor Kopfkommentar vor Formularskizze vor „Verwendet von“;
//   - Wahl des Benutzers je Abschnitt (offen, zu oder automatisch), die in der
//     Sitzung erhalten bleibt (liegt in TAtlasUnitSearchState, nicht im JSON).
// Passt alles, bleibt alles offen. Sonst klappt Atlas automatische Abschnitte
// vom unwichtigsten an ein, bis es passt; der wichtigste vorhandene bleibt offen.
// Vom Benutzer geöffnete oder geschlossene Abschnitte behalten ihre Wahl.

interface

type
  /// <summary>Abschnitte des Detail-Panels in der Reihenfolge der Anzeige.</summary>
  TAtlasUnitSection = (Header, Form, Types, UsedBy);
  TAtlasUnitSections = set of TAtlasUnitSection;

  /// <summary>Wahl des Benutzers: Auto = Atlas entscheidet nach Platz.</summary>
  TAtlasUnitSectionChoice = (Auto, Open, Closed);
  TAtlasUnitSectionChoices = array[TAtlasUnitSection] of TAtlasUnitSectionChoice;

  TAtlasUnitSectionSize = record
    /// <summary>Abschnitt hat Inhalt (sonst weder Überschrift noch Inhalt).</summary>
    Present: Boolean;
    /// <summary>Höhe der Überschrift; immer sichtbar.</summary>
    Head: Integer;
    /// <summary>Höhe des Inhalts, wenn aufgeklappt.</summary>
    Body: Integer;
  end;
  TAtlasUnitSectionSizes = array[TAtlasUnitSection] of TAtlasUnitSectionSize;

  TAtlasUnitSectionLayout = record
  public
    /// <summary>Rang: 0 = wichtigster.</summary>
    class function Rank(ASection: TAtlasUnitSection): Integer; static;
    /// <summary>Wichtigster vorhandener Abschnitt; False, wenn keiner vorhanden ist.</summary>
    class function MostImportant(const ASizes: TAtlasUnitSectionSizes; out ASection: TAtlasUnitSection): Boolean;
      static;
    /// <summary>Gesamthöhe aller vorhandenen Überschriften plus der Inhalte in AOpen.</summary>
    class function Height(const ASizes: TAtlasUnitSectionSizes; AOpen: TAtlasUnitSections): Integer; static;
    /// <summary>Offene Abschnitte für die verfügbare Höhe AAvailable.</summary>
    class function Resolve(const ASizes: TAtlasUnitSectionSizes; AAvailable: Integer;
      const AChoices: TAtlasUnitSectionChoices): TAtlasUnitSections; static;
    /// <summary>Klick auf die Überschrift: war der Abschnitt offen, wird er zu, sonst offen. Die Wahl bleibt.</summary>
    class procedure Toggle(var AChoices: TAtlasUnitSectionChoices; ASection: TAtlasUnitSection;
      AWasOpen: Boolean); static;
  end;

implementation

const
  // Vom wichtigsten zum unwichtigsten.
  Ranking: array[0..3] of TAtlasUnitSection = (TAtlasUnitSection.Types, TAtlasUnitSection.Header,
    TAtlasUnitSection.Form, TAtlasUnitSection.UsedBy);

{ TAtlasUnitSectionLayout }

class function TAtlasUnitSectionLayout.Rank(ASection: TAtlasUnitSection): Integer;
var
  Index: Integer;
begin
  for Index := Low(Ranking) to High(Ranking) do
    if Ranking[Index] = ASection then
      Exit(Index);
  Result := High(Ranking) + 1;
end;

class function TAtlasUnitSectionLayout.MostImportant(const ASizes: TAtlasUnitSectionSizes;
  out ASection: TAtlasUnitSection): Boolean;
var
  Index: Integer;
begin
  for Index := Low(Ranking) to High(Ranking) do
    if ASizes[Ranking[Index]].Present then
    begin
      ASection := Ranking[Index];
      Exit(True);
    end;
  ASection := Low(TAtlasUnitSection);
  Result := False;
end;

class function TAtlasUnitSectionLayout.Height(const ASizes: TAtlasUnitSectionSizes;
  AOpen: TAtlasUnitSections): Integer;
var
  Section: TAtlasUnitSection;
begin
  Result := 0;
  for Section := Low(TAtlasUnitSection) to High(TAtlasUnitSection) do
    if ASizes[Section].Present then
    begin
      Inc(Result, ASizes[Section].Head);
      if Section in AOpen then
        Inc(Result, ASizes[Section].Body);
    end;
end;

class function TAtlasUnitSectionLayout.Resolve(const ASizes: TAtlasUnitSectionSizes; AAvailable: Integer;
  const AChoices: TAtlasUnitSectionChoices): TAtlasUnitSections;
var
  Section, Keep: TAtlasUnitSection;
  HasKeep: Boolean;
  Index, Total: Integer;
begin
  Result := [];
  for Section := Low(TAtlasUnitSection) to High(TAtlasUnitSection) do
    if ASizes[Section].Present and (AChoices[Section] <> TAtlasUnitSectionChoice.Closed) then
      Include(Result, Section);
  Total := Height(ASizes, Result);
  HasKeep := MostImportant(ASizes, Keep);
  // Vom unwichtigsten an einklappen, bis es passt.
  for Index := High(Ranking) downto Low(Ranking) do
  begin
    if Total <= AAvailable then
      Break;
    Section := Ranking[Index];
    if not (Section in Result) or (AChoices[Section] <> TAtlasUnitSectionChoice.Auto) then
      Continue;
    if HasKeep and (Section = Keep) then
      Continue;
    Exclude(Result, Section);
    Dec(Total, ASizes[Section].Body);
  end;
end;

class procedure TAtlasUnitSectionLayout.Toggle(var AChoices: TAtlasUnitSectionChoices; ASection: TAtlasUnitSection;
  AWasOpen: Boolean);
begin
  if AWasOpen then
    AChoices[ASection] := TAtlasUnitSectionChoice.Closed
  else
    AChoices[ASection] := TAtlasUnitSectionChoice.Open;
end;

end.
