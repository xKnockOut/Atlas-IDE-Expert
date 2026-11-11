unit Atlas.UI.Diagnostics.MainThreadPage;

// Reiter „Hauptthread“ des Diagnose-Fensters, reine VCL: oben je Funktion
// Aufrufe, Summe, Mittel, Maximum (eigene Zeit), Aufrufe ab der Schwelle und
// Anteil; darunter (mit Teiler) die langsamen Aufrufe, neueste zuerst.
// Doppelklick oder „Nur … zeigen“ beschränkt die langsamen Aufrufe auf eine
// Funktion. Das Kontextmenü schaltet eine Funktion bis zum Neustart aus
// (OnDisable) und kopiert eine Zeile (OnCopyText). Die gewählte Funktion
// bleibt gewählt, auch wenn sich die Reihenfolge mit neuen Zeiten ändert.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.PluginTimings,
  Atlas.Core.Diagnostics.PluginReport,
  Atlas.UI.Diagnostics.Grid,
  Atlas.UI.Diagnostics.PluginParts;

type
  TAtlasMainThreadPage = class(TPanel)
  private
    FFeatures: TAtlasDiagnosticGrid;
    FSlowCaption: TLabel;
    FSlow: TAtlasDiagnosticGrid;
    FMenu: TAtlasFeatureMenu;
    FSnapshot: TAtlasPluginSnapshot;
    FRows: TArray<TAtlasFeatureRow>;
    FFilterOn: Boolean;
    FFilter: TAtlasFeature;
    FOnDisable: TProc<TAtlasFeature>;
    FOnCopyText: TProc<string>;
    procedure FillFeatures;
    procedure FillSlow;
    procedure FeatureOpen(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure AllClick(Sender: TObject);
    procedure DisableClick(Sender: TObject);
    procedure CopyRowClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetSnapshot(const ASnapshot: TAtlasPluginSnapshot);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Gewählte Funktion; False ohne Wahl.</summary>
    function SelectedFeature(out AFeature: TAtlasFeature): Boolean;
    /// <summary>Langsame Aufrufe nur von AFeature zeigen bzw. (ShowAllSlow) wieder alle.</summary>
    procedure ShowOnly(AFeature: TAtlasFeature);
    procedure ShowAllSlow;
    property Features: TAtlasDiagnosticGrid read FFeatures;
    property Slow: TAtlasDiagnosticGrid read FSlow;
    property SlowCaption: TLabel read FSlowCaption;
    property Menu: TAtlasFeatureMenu read FMenu;
    property FilterOn: Boolean read FFilterOn;
    property Filter: TAtlasFeature read FFilter;
    /// <summary>„… bis zum Neustart ausschalten“ für die gewählte Funktion.</summary>
    property OnDisable: TProc<TAtlasFeature> read FOnDisable write FOnDisable;
    /// <summary>Text für die Zwischenablage (Zeile kopieren).</summary>
    property OnCopyText: TProc<string> read FOnCopyText write FOnCopyText;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Diagnostics.Strings,
  Atlas.UI.Diagnostics.PluginRows;

{ TAtlasMainThreadPage }

constructor TAtlasMainThreadPage.Create(AOwner: TComponent);
var
  mSplitter: TSplitter;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentBackground := True;
  FFeatures := TAtlasDiagnosticGrid.Create(Self);
  FFeatures.Parent := Self;
  FFeatures.Align := alTop;
  FFeatures.Height := MulDiv(200, CurrentPPI, 96);
  FFeatures.EmptyText := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagEmpty);
  FFeatures.SetColumns(TAtlasPluginGridRows.FeatureColumns);
  FFeatures.OnOpen := FeatureOpen;
  mSplitter := TSplitter.Create(Self);
  mSplitter.Parent := Self;
  mSplitter.Align := alTop;
  mSplitter.Top := FFeatures.Top + FFeatures.Height;
  FSlowCaption := TLabel.Create(Self);
  FSlowCaption.Parent := Self;
  FSlowCaption.Align := alTop;
  FSlowCaption.AlignWithMargins := True;
  FSlowCaption.ShowAccelChar := False;
  FSlowCaption.Top := mSplitter.Top + mSplitter.Height;
  FSlow := TAtlasDiagnosticGrid.Create(Self);
  FSlow.Parent := Self;
  FSlow.Align := alClient;
  FSlow.EmptyText := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagEmpty);
  FSlow.SetColumns(TAtlasPluginGridRows.SlowColumns);
  FMenu := TAtlasFeatureMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FMenu.OnlyItem.OnClick := FeatureOpen;
  FMenu.AllItem.OnClick := AllClick;
  FMenu.DisableItem.OnClick := DisableClick;
  FMenu.CopyRowItem.OnClick := CopyRowClick;
  FFeatures.Box.PopupMenu := FMenu;
  SetSnapshot(Default(TAtlasPluginSnapshot));
end;

procedure TAtlasMainThreadPage.SetSnapshot(const ASnapshot: TAtlasPluginSnapshot);
begin
  FSnapshot := ASnapshot;
  FillFeatures;
  FillSlow;
end;

procedure TAtlasMainThreadPage.SetColors(const AColors: TAtlasColors);
begin
  FFeatures.SetColors(AColors);
  FSlow.SetColors(AColors);
end;

function TAtlasMainThreadPage.SelectedFeature(out AFeature: TAtlasFeature): Boolean;
var
  mIndex: Integer;
begin
  AFeature := Low(TAtlasFeature);
  mIndex := FFeatures.Selected;
  Result := (mIndex >= 0) and (mIndex <= High(FRows));
  if Result then
  begin
    AFeature := FRows[mIndex].Feature;
  end;
end;

procedure TAtlasMainThreadPage.FillFeatures;
var
  mIndex, mSelected: Integer;
  mKeep: TAtlasFeature;
  mHadSelection: Boolean;
begin
  mHadSelection := SelectedFeature(mKeep);
  FRows := TAtlasPluginRows.Features(FSnapshot);
  mSelected := -1;
  for mIndex := 0 to High(FRows) do
  begin
    if mHadSelection and (FRows[mIndex].Feature = mKeep) then
    begin
      mSelected := mIndex;
    end;
  end;
  FFeatures.SetRows(TAtlasPluginGridRows.Features(FRows, FSnapshot.ThresholdMs));
  // Die Wahl folgt der Funktion, nicht der Zeilennummer.
  if mSelected <> FFeatures.Selected then
  begin
    FFeatures.SelectRow(mSelected);
  end;
end;

procedure TAtlasMainThreadPage.FillSlow;
begin
  FSlow.SetRows(TAtlasPluginGridRows.Slow(TAtlasPluginRows.Slow(FSnapshot, FFilterOn, FFilter),
    FSnapshot.ThresholdMs));
  if FFilterOn then
  begin
    FSlowCaption.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagSlowOnly,
      [TAtlasGuard.FeatureName(FFilter)]);
  end
  else
  begin
    FSlowCaption.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagSlowAll,
      [TAtlasPluginRecorder.cSlowCapacity]);
  end;
end;

procedure TAtlasMainThreadPage.ShowOnly(AFeature: TAtlasFeature);
begin
  FFilterOn := True;
  FFilter := AFeature;
  FillSlow;
end;

procedure TAtlasMainThreadPage.ShowAllSlow;
begin
  FFilterOn := False;
  FillSlow;
end;

procedure TAtlasMainThreadPage.FeatureOpen(Sender: TObject);
var
  mFeature: TAtlasFeature;
begin
  if SelectedFeature(mFeature) then
  begin
    ShowOnly(mFeature);
  end;
end;

procedure TAtlasMainThreadPage.MenuPopup(Sender: TObject);
var
  mFeature: TAtlasFeature;
  mName: string;
begin
  mName := '';
  if SelectedFeature(mFeature) then
  begin
    mName := TAtlasGuard.FeatureName(mFeature);
  end;
  FMenu.Prepare(mName, FFilterOn);
end;

procedure TAtlasMainThreadPage.AllClick(Sender: TObject);
begin
  ShowAllSlow;
end;

procedure TAtlasMainThreadPage.DisableClick(Sender: TObject);
var
  mFeature: TAtlasFeature;
begin
  if SelectedFeature(mFeature) and Assigned(FOnDisable) then
  begin
    FOnDisable(mFeature);
  end;
end;

procedure TAtlasMainThreadPage.CopyRowClick(Sender: TObject);
begin
  if (FFeatures.Selected >= 0) and Assigned(FOnCopyText) then
  begin
    FOnCopyText(FFeatures.RowText(FFeatures.Selected));
  end;
end;

end.
