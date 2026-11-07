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
    cPriority: array[0..5] of TAtlasPreviewSection = (TAtlasPreviewSection.Types, TAtlasPreviewSection.Form,
      TAtlasPreviewSection.UsedBy, TAtlasPreviewSection.Uses_, TAtlasPreviewSection.Header,
      TAtlasPreviewSection.Path);
  public
    /// <summary>Zustand je Abschnitt für AAvailable Pixel Höhe; AAutoCollapse = False klappt nichts selbst
    /// ein.</summary>
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
  mSection: TAtlasPreviewSection;
begin
  Result := 0;
  for mSection := Low(TAtlasPreviewSection) to High(TAtlasPreviewSection) do
    case AStates[mSection] of
      TAtlasSectionState.Open:
        Inc(Result, AInputs[mSection].OpenHeight);
      TAtlasSectionState.Collapsed, TAtlasSectionState.AutoCollapsed:
        Inc(Result, AInputs[mSection].ClosedHeight);
    end;
end;

class function TAtlasPreviewSections.Arrange(const AInputs: TAtlasSectionInputs;
  const AChoices: TAtlasSectionChoices; AAvailable: Integer; AAutoCollapse: Boolean): TAtlasSectionStates;
var
  mSection: TAtlasPreviewSection;
  mTotal, mOpenCount, mIndex: Integer;
begin
  mOpenCount := 0;
  for mSection := Low(TAtlasPreviewSection) to High(TAtlasPreviewSection) do
  begin
    if not AInputs[mSection].Present then
    begin
      Result[mSection] := TAtlasSectionState.Hidden;
    end
    else if AChoices[mSection] = TAtlasSectionChoice.HandClosed then
    begin
      Result[mSection] := TAtlasSectionState.Collapsed;
    end
    else
    begin
      Result[mSection] := TAtlasSectionState.Open;
      Inc(mOpenCount);
    end;
  end;
  if not AAutoCollapse then
  begin
    Exit;
  end;
  mTotal := Height(AInputs, Result);
  // Vom unwichtigsten her einklappen; von Hand geöffnete bleiben offen.
  for mIndex := High(cPriority) downto Low(cPriority) do
  begin
    if (mTotal <= AAvailable) or (mOpenCount <= 1) then
    begin
      Break;
    end;
    mSection := cPriority[mIndex];
    if (Result[mSection] <> TAtlasSectionState.Open) or (AChoices[mSection] = TAtlasSectionChoice.HandOpen) then
    begin
      Continue;
    end;
    Result[mSection] := TAtlasSectionState.AutoCollapsed;
    Dec(mOpenCount);
    Dec(mTotal, AInputs[mSection].OpenHeight - AInputs[mSection].ClosedHeight);
  end;
end;

class function TAtlasPreviewSections.Toggled(AState: TAtlasSectionState): TAtlasSectionChoice;
begin
  if AState = TAtlasSectionState.Open then
  begin
    Result := TAtlasSectionChoice.HandClosed;
  end
  else
  begin
    Result := TAtlasSectionChoice.HandOpen;
  end;
end;

end.
