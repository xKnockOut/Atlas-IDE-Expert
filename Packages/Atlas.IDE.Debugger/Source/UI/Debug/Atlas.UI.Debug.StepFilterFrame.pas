unit Atlas.UI.Debug.StepFilterFrame;

// Inhalt des Fensters „Schrittfilter“ (#850): Schalter debug.stepFilters, die
// Arten mit ihren Treffern im Index, die Muster (bearbeiten mit F2 oder
// Doppelklick, hinzufügen, entfernen) mit Treffern und unten, was Atlas in
// dieser Debug-Sitzung übersprungen hat. Jede Änderung meldet Hooks.Change mit dem
// ganzen Stand; die IDE-Schicht speichert ihn und ruft SetOptions mit dem
// gespeicherten Stand zurück. Treffer zählt die IDE-Schicht im Hintergrund
// (SetCounting, SetCounts, SetNoCounts). Eingabezeile und Liste der Muster
// stehen in Atlas.UI.Debug.StepFilterPatterns.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Text.StepFilter,
  Atlas.Core.Debug.StepFilter,
  Atlas.UI.Debug.StepFilterPatterns;

type
  {$SCOPEDENUMS ON}
  TAtlasStepCountsState = (None, Counting, Ready, Unavailable);
  {$SCOPEDENUMS OFF}

  TAtlasStepFilterChange = reference to procedure(AEnabled: Boolean; AKinds: TStepFilterKinds;
    const APatterns: TArray<string>);

  /// <summary>Texte des Fensters „Schrittfilter“: Gründe, Arten und Muster mit Treffern, Zusammenfassung, Sitzung.
  /// </summary>
  TAtlasStepFilterTexts = class
  public
    /// <summary>Grund eines Urteils: Beschreibung der Art bzw. „Muster X“.</summary>
    class function VerdictText(const AVerdict: TAtlasStepVerdict): string; static;
    /// <summary>Beschriftung einer Art, mit Treffern, sobald sie gezählt sind.</summary>
    class function KindCaption(AKind: TStepFilterKind; AState: TAtlasStepCountsState;
      const ACounts: TAtlasStepCounts): string; static;
    /// <summary>Treffer eines Musters ('' solange nicht gezählt).</summary>
    class function PatternHits(AIndex: Integer; AState: TAtlasStepCountsState;
      const ACounts: TAtlasStepCounts): string; static;
    class function SummaryText(AState: TAtlasStepCountsState; const ACounts: TAtlasStepCounts): string; static;
    class function SessionText(AStarted: Boolean; ASkipped: Integer; const ALastName, ALastReason: string): string;
      static;
  end;

  /// <summary>Was der Frame an die IDE-Schicht meldet; nicht gesetzte Einträge bleiben still. Gehört dem Frame.
  /// </summary>
  TAtlasStepFilterHooks = class
  private
    FChange: TAtlasStepFilterChange;
    FRefresh: TProc;
  public
    /// <summary>Schalter, Arten oder Muster geändert, mit dem ganzen Stand.</summary>
    property Change: TAtlasStepFilterChange read FChange write FChange;
    /// <summary>„Neu zählen“.</summary>
    property Refresh: TProc read FRefresh write FRefresh;
  end;

  TAtlasDebugStepFilterFrame = class(TFrame)
  private
    FEnabledCheck: TCheckBox;
    FKindChecks: array[TStepFilterKind] of TCheckBox;
    FPatterns: TAtlasStepFilterPatterns;
    FSummary: TLabel;
    FSession: TLabel;
    FEnabled: Boolean;
    FKinds: TStepFilterKinds;
    FCountsState: TAtlasStepCountsState;
    FCounts: TAtlasStepCounts;
    FFilling: Boolean;
    FHooks: TAtlasStepFilterHooks;
    function AddLabel(AAlign: TAlign; const ACaption: string): TLabel;
    function BuildTopBar: Integer;
    procedure BuildKinds(var ATop: Integer);
    procedure BuildBottomLabels;
    procedure UpdateCounts;
    procedure NotifyChange;
    procedure EnabledClick(Sender: TObject);
    procedure KindClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure PatternsChange(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Gespeicherter Stand; meldet nichts über Hooks.Change. Die Liste baut sich nur neu, wenn sich die Muster
    /// geändert haben (sonst stört es ein laufendes Bearbeiten).</summary>
    procedure SetOptions(AEnabled: Boolean; AKinds: TStepFilterKinds; const APatterns: TArray<string>);
    procedure SetCounting;
    /// <summary>Treffer für die Muster in der Reihenfolge, die beim Zählen galt.</summary>
    procedure SetCounts(const ACounts: TAtlasStepCounts);
    procedure SetNoCounts;
    procedure SetSession(AStarted: Boolean; ASkipped: Integer; const ALastName, ALastReason: string);
    property EnabledCheck: TCheckBox read FEnabledCheck;
    /// <summary>Eingabezeile und Liste der Muster: anfügen, entfernen, ersetzen.</summary>
    property Patterns: TAtlasStepFilterPatterns read FPatterns;
    property Summary: TLabel read FSummary;
    property Session: TLabel read FSession;
    property CountsState: TAtlasStepCountsState read FCountsState;
    property Hooks: TAtlasStepFilterHooks read FHooks;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Strings,
  Atlas.UI.Debug.Stepping.Strings,
  Atlas.UI.Foundation.WrapLabel;

{$R *.dfm}

const
  cKindTexts: array[TStepFilterKind] of TAtlasSteppingTextId = (TAtlasSteppingTextId.StepFilterKindGetters,
    TAtlasSteppingTextId.StepFilterKindSetters, TAtlasSteppingTextId.StepFilterKindTrivial,
      TAtlasSteppingTextId.StepFilterKindOperators,
    TAtlasSteppingTextId.StepFilterKindEmptyConstructors);
  /// <summary>Höhe der Leiste oben bei 96 dpi.</summary>
  cTopBarHeight = 30;
  /// <summary>Abstand der Lage gleich ausgerichteter Teile vor dem Ausrichten: Sie bestimmt ihre Reihenfolge.
  /// </summary>
  cOrderStep = 100;
  /// <summary>Lage der Beschriftungen unten (mit alBottom liegt das größere Top weiter unten).</summary>
  cHintOrder = 30000;
  cSessionOrder = 20000;
  cSummaryOrder = 10000;

{ TAtlasDebugStepFilterFrame }

constructor TAtlasDebugStepFilterFrame.Create(AOwner: TComponent);
var
  mTop: Integer;
  mHeader: TLabel;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FHooks := TAtlasStepFilterHooks.Create;
  FKinds := TStepFilterNames.cDefaultKinds;
  // Von oben: Kopf der Arten, die Arten, Kopf der Muster, Eingabezeile; die Liste füllt den Rest.
  mTop := BuildTopBar;
  BuildKinds(mTop);
  mHeader := AddLabel(alTop, TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterPatternsHeader));
  mHeader.Font.Style := [fsBold];
  mHeader.Top := mTop + mHeader.ScaleValue(cOrderStep);
  BuildBottomLabels;
  FPatterns := TAtlasStepFilterPatterns.CreateIn(Self, mTop + ScaleValue(2 * cOrderStep), PatternsChange);
  SetOptions(False, TStepFilterNames.cDefaultKinds, nil);
  SetSession(False, 0, '', '');
  UpdateCounts;
end;

destructor TAtlasDebugStepFilterFrame.Destroy;
begin
  FreeAndNil(FHooks);
  inherited Destroy;
end;

function TAtlasDebugStepFilterFrame.AddLabel(AAlign: TAlign; const ACaption: string): TLabel;
begin
  Result := TAtlasWrapLabel.Create(Self);
  Result.Parent := Self;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
end;

function TAtlasDebugStepFilterFrame.BuildTopBar: Integer;
var
  mTop: TPanel;
begin
  // Schalter debug.stepFilters und „Neu zählen“; Ergebnis: Höhe der Leiste.
  mTop := TPanel.Create(Self);
  mTop.Height := MulDiv(cTopBarHeight, CurrentPPI, 96);
  mTop.Align := alTop;
  mTop.Parent := Self;
  mTop.BevelOuter := bvNone;
  mTop.ShowCaption := False;
  mTop.ParentBackground := True;
  TAtlasStepFilterPatterns.AddButton(Self, mTop, CurrentPPI,
    TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterRefresh), RefreshClick);
  FEnabledCheck := TCheckBox.Create(Self);
  FEnabledCheck.Parent := mTop;
  FEnabledCheck.Align := alClient;
  FEnabledCheck.AlignWithMargins := True;
  FEnabledCheck.Caption := TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterEnabled);
  FEnabledCheck.OnClick := EnabledClick;
  Result := mTop.Height;
end;

procedure TAtlasDebugStepFilterFrame.BuildKinds(var ATop: Integer);
var
  mKind: TStepFilterKind;
  mHeader: TLabel;
  mCheck: TCheckBox;
begin
  // Kopf und Schalter der Arten ab ATop; mit alTop ordnet die VCL nach Top, deshalb steigend.
  mHeader := AddLabel(alTop, TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterKindsHeader));
  mHeader.Font.Style := [fsBold];
  mHeader.Top := ATop;
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    mCheck := TCheckBox.Create(Self);
    mCheck.Parent := Self;
    mCheck.Align := alTop;
    mCheck.AlignWithMargins := True;
    Inc(ATop, cOrderStep);
    mCheck.Top := ATop;
    mCheck.Tag := Ord(mKind);
    mCheck.OnClick := KindClick;
    FKindChecks[mKind] := mCheck;
  end;
end;

procedure TAtlasDebugStepFilterFrame.BuildBottomLabels;
var
  mHint: TLabel;
begin
  // Von unten: Hinweis, Sitzung, Zusammenfassung.
  mHint := AddLabel(alBottom, TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterShiftHint));
  mHint.Font.Color := clGrayText;
  mHint.Top := cHintOrder;
  FSession := AddLabel(alBottom, '');
  FSession.Top := cSessionOrder;
  FSummary := AddLabel(alBottom, '');
  FSummary.Top := cSummaryOrder;
end;

procedure TAtlasDebugStepFilterFrame.CreateWnd;
begin
  inherited CreateWnd;
  // TListView.Items braucht ein Fenster.
  FPatterns.Fill;
end;

procedure TAtlasDebugStepFilterFrame.UpdateCounts;
var
  mKind: TStepFilterKind;
  mHits: TArray<string>;
  mIndex: Integer;
begin
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    FKindChecks[mKind].Caption := TAtlasStepFilterTexts.KindCaption(mKind, FCountsState, FCounts);
  end;
  FSummary.Caption := TAtlasStepFilterTexts.SummaryText(FCountsState, FCounts);
  SetLength(mHits, Length(FPatterns.Patterns));
  for mIndex := 0 to High(mHits) do
  begin
    mHits[mIndex] := TAtlasStepFilterTexts.PatternHits(mIndex, FCountsState, FCounts);
  end;
  FPatterns.SetHits(mHits);
end;

procedure TAtlasDebugStepFilterFrame.NotifyChange;
begin
  if Assigned(FHooks.Change) then
  begin
    FHooks.Change(FEnabled, FKinds, Copy(FPatterns.Patterns));
  end;
end;

procedure TAtlasDebugStepFilterFrame.EnabledClick(Sender: TObject);
begin
  if FFilling then
  begin
    Exit;
  end;
  FEnabled := FEnabledCheck.Checked;
  NotifyChange;
end;

procedure TAtlasDebugStepFilterFrame.KindClick(Sender: TObject);
var
  mKind: TStepFilterKind;
begin
  if FFilling then
  begin
    Exit;
  end;
  mKind := TStepFilterKind((Sender as TCheckBox).Tag);
  if FKindChecks[mKind].Checked then
  begin
    Include(FKinds, mKind);
  end
  else
  begin
    Exclude(FKinds, mKind);
  end;
  NotifyChange;
end;

procedure TAtlasDebugStepFilterFrame.RefreshClick(Sender: TObject);
begin
  if Assigned(FHooks.Refresh) then
  begin
    FHooks.Refresh();
  end;
end;

procedure TAtlasDebugStepFilterFrame.PatternsChange(Sender: TObject);
begin
  NotifyChange;
end;

procedure TAtlasDebugStepFilterFrame.SetOptions(AEnabled: Boolean; AKinds: TStepFilterKinds;
  const APatterns: TArray<string>);
var
  mKind: TStepFilterKind;
begin
  FEnabled := AEnabled;
  FKinds := AKinds;
  FFilling := True;
  try
    FEnabledCheck.Checked := AEnabled;
    for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
    begin
      FKindChecks[mKind].Checked := mKind in AKinds;
    end;
  finally
    FFilling := False;
  end;
  FPatterns.SetPatterns(APatterns);
end;

procedure TAtlasDebugStepFilterFrame.SetCounting;
begin
  FCountsState := TAtlasStepCountsState.Counting;
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.SetCounts(const ACounts: TAtlasStepCounts);
begin
  FCounts := ACounts;
  FCounts.Patterns := Copy(ACounts.Patterns);
  FCountsState := TAtlasStepCountsState.Ready;
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.SetNoCounts;
begin
  FCounts := Default(TAtlasStepCounts);
  FCountsState := TAtlasStepCountsState.Unavailable;
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.SetSession(AStarted: Boolean; ASkipped: Integer;
  const ALastName, ALastReason: string);
begin
  FSession.Caption := TAtlasStepFilterTexts.SessionText(AStarted, ASkipped, ALastName, ALastReason);
end;

{ TAtlasStepFilterTexts }

class function TAtlasStepFilterTexts.VerdictText(const AVerdict: TAtlasStepVerdict): string;
begin
  case AVerdict.Kind of
    TAtlasStepVerdictKind.Kind:
      Result := TAtlasSteppingStrings.Text(cKindTexts[AVerdict.FilterKind]);
    TAtlasStepVerdictKind.Pattern:
      Result := TAtlasSteppingStrings.Fmt(TAtlasSteppingTextId.StepFilterByPattern, [AVerdict.Pattern]);
  else
    Result := '';
  end;
end;

class function TAtlasStepFilterTexts.KindCaption(AKind: TStepFilterKind; AState: TAtlasStepCountsState;
  const ACounts: TAtlasStepCounts): string;
begin
  Result := TAtlasSteppingStrings.Text(cKindTexts[AKind]);
  if AState = TAtlasStepCountsState.Ready then
  begin
    Result := Result + ' – ' + IntToStr(ACounts.Kinds[AKind]);
  end;
end;

class function TAtlasStepFilterTexts.PatternHits(AIndex: Integer; AState: TAtlasStepCountsState;
  const ACounts: TAtlasStepCounts): string;
begin
  Result := '';
  if (AState = TAtlasStepCountsState.Ready) and (AIndex >= 0) and (AIndex <= High(ACounts.Patterns)) then
  begin
    Result := IntToStr(ACounts.Patterns[AIndex]);
  end;
end;

class function TAtlasStepFilterTexts.SummaryText(AState: TAtlasStepCountsState;
  const ACounts: TAtlasStepCounts): string;
begin
  case AState of
    TAtlasStepCountsState.Counting:
      Result := TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterCounting);
    TAtlasStepCountsState.Ready:
      begin
        Result := TAtlasSteppingStrings.Fmt(TAtlasSteppingTextId.StepFilterSummary, [ACounts.Routines, ACounts.Files]);
        if ACounts.Truncated then
        begin
          Result := Result + TAtlasSteppingStrings.Fmt(TAtlasSteppingTextId.StepFilterTruncated, [ACounts.Files]);
        end;
      end;
    TAtlasStepCountsState.Unavailable:
      Result := TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterNoCounts);
  else
    Result := '';
  end;
end;

class function TAtlasStepFilterTexts.SessionText(AStarted: Boolean; ASkipped: Integer;
  const ALastName, ALastReason: string): string;
begin
  if not AStarted then
  begin
    Exit(TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterInactive));
  end;
  Result := TAtlasSteppingStrings.Fmt(TAtlasSteppingTextId.StepFilterSession, [ASkipped]);
  if ALastName <> '' then
  begin
    Result := Result + TAtlasSteppingStrings.Fmt(TAtlasSteppingTextId.StepFilterLast, [ALastName, ALastReason]);
  end;
end;

end.
