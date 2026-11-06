unit Atlas.UI.Diagnostics.PluginFrame;

// Inhalt des Fensters „Atlas-Diagnose“ (Variante A), reine VCL: oben die
// Reiter Hauptthread, Server, Hintergrund, Hänger und Vervollständigung,
// darunter für die vier Reiter des Plugins die Leiste mit Belegung, Schwelle
// und Knöpfen (TAtlasDiagnosticBar) und unten die Fußzeile „Messung seit …“.
// - Hauptthread: TAtlasMainThreadPage.
// - Server, Hintergrund, Hänger: je eine Tabelle (TAtlasTablePage).
// - Vervollständigung: der bisherige Inhalt (TAtlasTimingFrame, #479) mit
//   eigenen Knöpfen.
// Ist die Messung des Plugins aus, zeigen die vier Reiter nur einen Hinweis.
// Die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine
// Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.PluginTimings,
  Atlas.UI.Diagnostics.PluginParts,
  Atlas.UI.Diagnostics.MainThreadPage,
  Atlas.UI.Diagnostics.TimingFrame;

type
  TAtlasDiagnosticsFrame = class(TFrame)
  private
    FTabs: TAtlasDiagnosticTabs;
    FBar: TAtlasDiagnosticBar;
    FFooter: TLabel;
    FOffNote: TLabel;
    FMain: TAtlasMainThreadPage;
    FServer: TAtlasTablePage;
    FBackground: TAtlasTablePage;
    FHangs: TAtlasTablePage;
    FCompletionPage: TPanel;
    FCompletion: TAtlasTimingFrame;
    FPluginOn: Boolean;
    function Page(APage: TAtlasDiagnosticPage): TPanel;
    function NewLabel(AAlign: TAlign): TLabel;
    procedure Place(APage: TPanel);
    procedure TabsChange(Sender: TObject);
    procedure ShowPages;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Neuer Stand; AWorkers = belegte Arbeiter der Datenquellen.</summary>
    procedure SetSnapshot(const ASnapshot: TAtlasPluginSnapshot; AWorkers: Integer);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Messung des Plugins an (Reiter mit Tabellen) oder aus (nur Hinweis).</summary>
    procedure SetPluginTimings(AOn: Boolean);
    procedure SelectPage(APage: TAtlasDiagnosticPage);
    /// <summary>Hinweis nach „… ausschalten“: die Funktion und wie sie wieder angeht.</summary>
    procedure FeatureDisabled(AFeature: TAtlasFeature);
    function ActivePage: TAtlasDiagnosticPage;
    property Tabs: TAtlasDiagnosticTabs read FTabs;
    property Bar: TAtlasDiagnosticBar read FBar;
    property MainThread: TAtlasMainThreadPage read FMain;
    property Server: TAtlasTablePage read FServer;
    property Background: TAtlasTablePage read FBackground;
    property Hangs: TAtlasTablePage read FHangs;
    property Completion: TAtlasTimingFrame read FCompletion;
    property Footer: TLabel read FFooter;
    property OffNote: TLabel read FOffNote;
    property PluginTimings: Boolean read FPluginOn;
  end;

implementation

uses
  Atlas.Core.Diagnostics.PluginReport,
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.PluginRows;

{$R *.dfm}

{ TAtlasDiagnosticsFrame }

constructor TAtlasDiagnosticsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FPluginOn := True;
  FTabs := TAtlasDiagnosticTabs.Create(Self);
  FTabs.Parent := Self;
  FTabs.OnChange := TabsChange;
  FBar := TAtlasDiagnosticBar.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Top := FTabs.Height;
  FFooter := NewLabel(alBottom);
  FFooter.Font.Color := clGrayText;
  FOffNote := NewLabel(alTop);
  FOffNote.WordWrap := True;
  FOffNote.Caption := TAtlasStrings.Text(TAtlasTextId.DiagPluginOff);
  FMain := TAtlasMainThreadPage.Create(Self);
  Place(FMain);
  FServer := TAtlasTablePage.CreatePage(Self, False);
  FServer.Grid.SetColumns(TAtlasPluginGridRows.RequestColumns);
  Place(FServer);
  FBackground := TAtlasTablePage.CreatePage(Self, True);
  FBackground.Grid.SetColumns(TAtlasPluginGridRows.SourceColumns);
  Place(FBackground);
  FHangs := TAtlasTablePage.CreatePage(Self, True);
  FHangs.Grid.SetColumns(TAtlasPluginGridRows.HangColumns);
  Place(FHangs);
  FCompletionPage := TPanel.Create(Self);
  FCompletionPage.BevelOuter := bvNone;
  FCompletionPage.ParentBackground := True;
  Place(FCompletionPage);
  FCompletion := TAtlasTimingFrame.Create(Self);
  FCompletion.Parent := FCompletionPage;
  FCompletion.Align := alClient;
  SetSnapshot(Default(TAtlasPluginSnapshot), 0);
  ShowPages;
end;

function TAtlasDiagnosticsFrame.NewLabel(AAlign: TAlign): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
end;

procedure TAtlasDiagnosticsFrame.Place(APage: TPanel);
begin
  APage.Parent := Self;
  APage.Align := alClient;
  APage.Visible := False;
end;

function TAtlasDiagnosticsFrame.Page(APage: TAtlasDiagnosticPage): TPanel;
begin
  case APage of
    TAtlasDiagnosticPage.MainThread:
      Result := FMain;
    TAtlasDiagnosticPage.Server:
      Result := FServer;
    TAtlasDiagnosticPage.Background:
      Result := FBackground;
    TAtlasDiagnosticPage.Hangs:
      Result := FHangs;
  else
    Result := FCompletionPage;
  end;
end;

function TAtlasDiagnosticsFrame.ActivePage: TAtlasDiagnosticPage;
begin
  Result := FTabs.Active;
end;

procedure TAtlasDiagnosticsFrame.SelectPage(APage: TAtlasDiagnosticPage);
begin
  FTabs.Active := APage;
  ShowPages;
end;

procedure TAtlasDiagnosticsFrame.TabsChange(Sender: TObject);
begin
  ShowPages;
end;

procedure TAtlasDiagnosticsFrame.ShowPages;
var
  mPage: TAtlasDiagnosticPage;
  mPluginPage: Boolean;
begin
  mPluginPage := FTabs.Active <> TAtlasDiagnosticPage.Completion;
  // Leiste und Fußzeile gehören den Reitern des Plugins; die Vervollständigung hat eigene Knöpfe.
  FBar.Visible := mPluginPage and FPluginOn;
  FFooter.Visible := mPluginPage and FPluginOn;
  FOffNote.Visible := mPluginPage and not FPluginOn;
  for mPage := Low(TAtlasDiagnosticPage) to High(TAtlasDiagnosticPage) do
  begin
    Page(mPage).Visible := (mPage = FTabs.Active) and (FPluginOn or not mPluginPage);
  end;
end;

procedure TAtlasDiagnosticsFrame.SetPluginTimings(AOn: Boolean);
begin
  FPluginOn := AOn;
  ShowPages;
end;

procedure TAtlasDiagnosticsFrame.SetSnapshot(const ASnapshot: TAtlasPluginSnapshot; AWorkers: Integer);
var
  mHangs: TArray<TAtlasHangEntry>;
  mHang: TAtlasHangEntry;
  mWithAtlas: Integer;
  mFooter: string;
begin
  FBar.SetSnapshot(ASnapshot);
  FMain.SetSnapshot(ASnapshot);
  FServer.Grid.SetRows(TAtlasPluginGridRows.Requests(TAtlasPluginRows.Requests(ASnapshot), ASnapshot.ThresholdMs));
  FBackground.Grid.SetRows(TAtlasPluginGridRows.Sources(TAtlasPluginRows.Sources(ASnapshot)));
  FBackground.Header.Caption := TAtlasStrings.Fmt(TAtlasTextId.DiagWorkers, [AWorkers]);
  mHangs := TAtlasPluginRows.Hangs(ASnapshot);
  FHangs.Grid.SetRows(TAtlasPluginGridRows.Hangs(mHangs));
  mWithAtlas := 0;
  for mHang in mHangs do
  begin
    if mHang.WithAtlas then
    begin
      Inc(mWithAtlas);
    end;
  end;
  FHangs.Header.Caption := TAtlasStrings.Fmt(TAtlasTextId.DiagHangSummary, [Length(mHangs), mWithAtlas]);
  mFooter := TAtlasStrings.Fmt(TAtlasTextId.DiagSince, [FormatDateTime('hh":"nn":"ss', ASnapshot.Since),
    Length(ASnapshot.Features)]);
  if ASnapshot.Paused then
  begin
    mFooter := mFooter + ' · ' + TAtlasStrings.Text(TAtlasTextId.DiagPaused);
  end;
  FFooter.Caption := mFooter + ' · ' + TAtlasStrings.Text(TAtlasTextId.DiagHint);
end;

procedure TAtlasDiagnosticsFrame.SetColors(const AColors: TAtlasColors);
begin
  FTabs.Colors := AColors;
  FBar.SetColors(AColors);
  FMain.SetColors(AColors);
  FServer.Grid.SetColors(AColors);
  FBackground.Grid.SetColors(AColors);
  FHangs.Grid.SetColors(AColors);
  FCompletion.SetColors(AColors);
end;

procedure TAtlasDiagnosticsFrame.FeatureDisabled(AFeature: TAtlasFeature);
begin
  FBar.ShowNote(TAtlasStrings.Fmt(TAtlasTextId.DiagDisabled, [TAtlasGuard.FeatureName(AFeature)]));
end;

end.
