unit Atlas.Core.UnitSearch.Sections;

// Einklappbare Abschnitte im Detail-Panel der Unitsuche (#876), Teil ohne VCL:
//   - Abschnitte in fester Reihenfolge: Pfad, Kopfkommentar, Formular,
//     exportierte Typen, uses, „Verwendet von“;
//   - von Hand auf- oder zugeklappte Abschnitte behalten ihren Zustand;
//   - passt nicht alles, klappen die übrigen von unten nach Wichtigkeit
//     automatisch ein (Typen am wichtigsten, Pfad am wenigsten), bis es passt
//     oder nur noch ein Abschnitt offen ist;
//   - mit genug Platz bleibt alles offen.

interface

type
  TAtlasPreviewSection = (Path, Header, Form, Types, Uses_, UsedBy);

  /// <summary>Wahl von Hand; Auto = Atlas entscheidet.</summary>
  TAtlasSectionChoice = (Auto, HandOpen, HandClosed);

  TAtlasSectionState = (Hidden, Open, Collapsed, AutoCollapsed);

  TAtlasSectionChoices = array[TAtlasPreviewSection] of TAtlasSectionChoice;
  TAtlasSectionStates = array[TAtlasPreviewSection] of TAtlasSectionState;

  TAtlasSectionInput = record
    /// <summary>False: Abschnitt hat keinen Inhalt und wird nicht gezeigt.</summary>
    Present: Boolean;
    /// <summary>Höhe mit Überschrift und Inhalt.</summary>
    OpenHeight: Integer;
    /// <summary>Höhe nur der Überschrift.</summary>
    ClosedHeight: Integer;
  end;

  TAtlasSectionInputs = array[TAtlasPreviewSection] of TAtlasSectionInput;

  TAtlasPreviewSections = class
  public const
    /// <summary>Wichtigster Abschnitt zuerst.</summary>
    Priority: array[0..5] of TAtlasPreviewSection = (TAtlasPreviewSection.Types, TAtlasPreviewSection.Form,
      TAtlasPreviewSection.UsedBy, TAtlasPreviewSection.Uses_, TAtlasPreviewSection.Header,
      TAtlasPreviewSection.Path);
  public
    /// <summary>Zustand je Abschnitt für AAvailable Pixel Höhe; AAutoCollapse = False klappt nichts selbst ein.</summary>
    class function Arrange(const AInputs: TAtlasSectionInputs; const AChoices: TAtlasSectionChoices;
      AAvailable: Integer; AAutoCollapse: Boolean): TAtlasSectionStates; static;
    /// <summary>Gesamthöhe der Abschnitte in diesen Zuständen.</summary>
    class function Height(const AInputs: TAtlasSectionInputs; const AStates: TAtlasSectionStates): Integer; static;
    /// <summary>Wahl nach einem Klick auf die Überschrift: offen wird zu, zu wird offen.</summary>
    class function Toggled(AState: TAtlasSectionState): TAtlasSectionChoice; static;
    /// <summary>True, wenn der Abschnitt offen gezeichnet wird.</summary>
    class function IsOpen(AState: TAtlasSectionState): Boolean; static;
  end;

implementation

{ TAtlasPreviewSections }

class function TAtlasPreviewSections.IsOpen(AState: TAtlasSectionState): Boolean;
begin
  Result := AState = TAtlasSectionState.Open;
end;

class function TAtlasPreviewSections.Height(const AInputs: TAtlasSectionInputs;
  const AStates: TAtlasSectionStates): Integer;
var
  Section: TAtlasPreviewSection;
begin
  Result := 0;
  for Section := Low(TAtlasPreviewSection) to High(TAtlasPreviewSection) do
    case AStates[Section] of
      TAtlasSectionState.Open:
        Inc(Result, AInputs[Section].OpenHeight);
      TAtlasSectionState.Collapsed, TAtlasSectionState.AutoCollapsed:
        Inc(Result, AInputs[Section].ClosedHeight);
    end;
end;

class function TAtlasPreviewSections.Arrange(const AInputs: TAtlasSectionInputs;
  const AChoices: TAtlasSectionChoices; AAvailable: Integer; AAutoCollapse: Boolean): TAtlasSectionStates;
var
  Section: TAtlasPreviewSection;
  Total, OpenCount, Index: Integer;
begin
  OpenCount := 0;
  for Section := Low(TAtlasPreviewSection) to High(TAtlasPreviewSection) do
    if not AInputs[Section].Present then
      Result[Section] := TAtlasSectionState.Hidden
    else if AChoices[Section] = TAtlasSectionChoice.HandClosed then
      Result[Section] := TAtlasSectionState.Collapsed
    else
    begin
      Result[Section] := TAtlasSectionState.Open;
      Inc(OpenCount);
    end;
  if not AAutoCollapse then
    Exit;
  Total := Height(AInputs, Result);
  // Vom unwichtigsten her einklappen; von Hand geöffnete bleiben offen.
  for Index := High(Priority) downto Low(Priority) do
  begin
    if (Total <= AAvailable) or (OpenCount <= 1) then
      Break;
    Section := Priority[Index];
    if (Result[Section] <> TAtlasSectionState.Open) or (AChoices[Section] = TAtlasSectionChoice.HandOpen) then
      Continue;
    Result[Section] := TAtlasSectionState.AutoCollapsed;
    Dec(OpenCount);
    Dec(Total, AInputs[Section].OpenHeight - AInputs[Section].ClosedHeight);
  end;
end;

class function TAtlasPreviewSections.Toggled(AState: TAtlasSectionState): TAtlasSectionChoice;
begin
  if AState = TAtlasSectionState.Open then
    Result := TAtlasSectionChoice.HandClosed
  else
    Result := TAtlasSectionChoice.HandOpen;
end;

end.
