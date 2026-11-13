unit Atlas.IDE.Tests.Coverage;

// Testabdeckung im Editor (#275) als Schicht der gemeinsamen Zeichenschicht
// TAtlasIdeGutterMarks:
// - „Testabdeckung laden …“ wählt einen Bericht von DelphiCodeCoverage
//   (CodeCoverage_Summary.xml mit -xmllines oder jacoco.xml, Startordner das
//   aktive Projekt) und liest ihn ohne neuen Build ein; die Meldungsansicht
//   nennt Dateien und abgedeckte Zeilen. „Testabdeckung ausblenden“ vergisst
//   ihn.
// - Rinne: je Zeile mit Code ein schmaler Balken, grün durchlaufen, rot nicht
//   durchlaufen (Farben Add und Error aus dem Grund der Rinne). Der Tooltip
//   nennt Treffer, die Abdeckung der Datei und den Bericht; ist die
//   Datei nach dem Bericht gespeichert worden, warnt er, dass die Zeilen
//   verschoben sein können.
// - Ändert sich der Bericht auf der Platte (neuer Lauf), liest die Schicht
//   ihn beim nächsten Verankern neu und zeichnet den Editor neu.
// Den Zustand hält Atlas.Core.Tests.Coverage. Abschaltbar über tests.coverage
// und am Element (#628); gesichert über TAtlasFeature.Build. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Tests.Coverage,
  Atlas.IDE.Foundation.GutterMarks;

type
  TAtlasIdeTestCoverage = class(TAtlasGutterLayer)
  private const
    /// <summary>Mindestbreite des Balkens in Pixeln.</summary>
    cBarMinWidth = 3;
    /// <summary>Der Balken nimmt ein Drittel des Symbolplatzes.</summary>
    cBarShare = 3;
    /// <summary>Deckkraft der Balkenfarbe über dem Grund der Rinne.</summary>
    cBarStrength = 0.85;
  private class var
    FState: TAtlasCoverageState;
  private
    /// <summary>Durchläufe der Zeile aus dem letzten MarkAt; TAtlasIdeGutterMarks zeichnet direkt danach.</summary>
    FLastHits: Integer;
  public
    function Feature: TAtlasFeature; override;
    function Element: TAtlasDrawnElement; override;
    function Wanted: Boolean; override;
    procedure Track(const AFileName, AText: string; AOpened: Boolean); override;
    function HasMarks(const AFileName: string): Boolean; override;
    function MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
      AHasText: Boolean): Boolean; override;
    procedure PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
      ABack: TAtlasColor); override;
    function TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean; override;
    /// <summary>Zustand anlegen (Start des Teils) bzw. freigeben.</summary>
    class procedure Start; static;
    class procedure Stop; static;
    class function Started: Boolean; static;
    /// <summary>Ist ein Bericht geladen (für „Testabdeckung ausblenden“)?</summary>
    class function Loaded: Boolean; static;
    /// <summary>Bericht wählen und laden; Ergebnis in der Meldungsansicht.</summary>
    class procedure Choose; static;
    /// <summary>Bericht AFileName laden; Ergebnis in der Meldungsansicht.</summary>
    class procedure LoadFile(const AFileName: string); static;
    class procedure Clear; static;
    /// <summary>Die Schicht über den Scope des Moduls bereitstellen.</summary>
    class procedure ProvideIn(const AScope: IAtlasModuleScope); static;
  end;

implementation

uses
  System.Math,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Text.Coverage,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Tests.Strings;

{ TAtlasIdeTestCoverage }

function TAtlasIdeTestCoverage.Feature: TAtlasFeature;
begin
  Result := TAtlasFeature.Build;
end;

function TAtlasIdeTestCoverage.Element: TAtlasDrawnElement;
begin
  Result := TAtlasDrawnElement.TestCoverage;
end;

function TAtlasIdeTestCoverage.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestCoverage and Loaded;
end;

procedure TAtlasIdeTestCoverage.Track(const AFileName, AText: string; AOpened: Boolean);
begin
  if Loaded and FState.Reload then
  begin
    TAtlasIdeGutterMarks.Invalidate;
  end;
end;

function TAtlasIdeTestCoverage.HasMarks(const AFileName: string): Boolean;
begin
  Result := Loaded and FState.HasFile(AFileName);
end;

function TAtlasIdeTestCoverage.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): Boolean;
begin
  FLastHits := -1;
  if Loaded then
  begin
    FLastHits := FState.HitsAt(AFileName, ALine);
  end;
  Result := FLastHits >= 0;
end;

procedure TAtlasIdeTestCoverage.PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  mBar: TRect;
  mColor: TAtlasColor;
begin
  // Schmaler Balken über die ganze Höhe des Symbols, mittig im Platz.
  mBar := AIcon;
  mBar.Left := AIcon.Left + Max(0, (AIcon.Width - Max(cBarMinWidth, AIcon.Width div cBarShare)) div 2);
  mBar.Right := mBar.Left + Max(cBarMinWidth, AIcon.Width div cBarShare);
  if FLastHits > 0 then
  begin
    mColor := AColors.Add;
  end
  else
  begin
    mColor := AColors.Error;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(TAtlasColorMath.Mix(mColor, ABack, cBarStrength));
  ACanvas.FillRect(mBar);
end;

function TAtlasIdeTestCoverage.TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean;
var
  mHits, mCovered, mLines: Integer;
  mTotals: TAtlasCoverageTotals;
begin
  ATitle := '';
  AText := '';
  mHits := -1;
  if Loaded then
  begin
    mHits := FState.HitsAt(AFileName, ALine);
  end;
  Result := mHits >= 0;
  if not Result then
  begin
    Exit;
  end;
  // Ohne -lcl zählt DelphiCodeCoverage keine Durchläufe: 1 heißt durchlaufen, mehr kommt von mehreren
  // Code-Adressen einer Zeile (oder echten Zählungen mit -lcl). JaCoCo kennt nur 0 und 1.
  if mHits = 0 then
  begin
    ATitle := TAtlasTestsStrings.Text(TAtlasTestsTextId.CoverageTipMissed);
  end
  else if mHits = 1 then
  begin
    ATitle := TAtlasTestsStrings.Text(TAtlasTestsTextId.CoverageTipHit);
  end
  else
  begin
    ATitle := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoverageTipHits, [mHits]);
  end;
  FState.FileTotals(AFileName, mCovered, mLines);
  mTotals := Default(TAtlasCoverageTotals);
  mTotals.Lines := mLines;
  mTotals.Covered := mCovered;
  AText := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoverageTipFile, [mCovered, mLines, mTotals.Percent]);
  if FState.SourceNewer(AFileName) then
  begin
    AText := AText + #10 + TAtlasTestsStrings.Text(TAtlasTestsTextId.CoverageTipOutdated);
  end;
  AText := AText + #10 + TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoverageTipReport, [FState.Path]);
end;

class procedure TAtlasIdeTestCoverage.Start;
begin
  if FState = nil then
  begin
    FState := TAtlasCoverageState.Create;
  end;
end;

class procedure TAtlasIdeTestCoverage.Stop;
begin
  FreeAndNil(FState);
  TAtlasIdeGutterMarks.Invalidate;
end;

class function TAtlasIdeTestCoverage.Started: Boolean;
begin
  Result := FState <> nil;
end;

class function TAtlasIdeTestCoverage.Loaded: Boolean;
begin
  Result := (FState <> nil) and FState.Loaded;
end;

/// <summary>Ordner des aktiven Projekts; '' ohne.</summary>
function ProjectFolder: string;
var
  mServices: IOTAModuleServices;
  mProject: IOTAProject;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    mProject := mServices.GetActiveProject;
    if mProject <> nil then
    begin
      Result := ExtractFilePath(mProject.FileName);
    end;
  end;
end;

class procedure TAtlasIdeTestCoverage.Choose;
var
  mDialog: TOpenDialog;
begin
  if FState = nil then
  begin
    Exit;
  end;
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Title := TAtlasTestsStrings.Text(TAtlasTestsTextId.CoverageLoadCommand);
    mDialog.Filter := TAtlasTestsStrings.Text(TAtlasTestsTextId.CoverageFilter);
    mDialog.Options := mDialog.Options + [ofFileMustExist];
    if FState.Loaded then
    begin
      mDialog.InitialDir := ExtractFilePath(FState.Path);
      mDialog.FileName := ExtractFileName(FState.Path);
    end
    else
    begin
      mDialog.InitialDir := ProjectFolder;
      mDialog.FileName := 'CodeCoverage_Summary.xml';
    end;
    if mDialog.Execute then
    begin
      LoadFile(mDialog.FileName);
    end;
  finally
    mDialog.Free;
  end;
end;

class procedure TAtlasIdeTestCoverage.LoadFile(const AFileName: string);
var
  mProblem: TCoverageProblem;
  mTotals: TAtlasCoverageTotals;
begin
  if FState = nil then
  begin
    Exit;
  end;
  if not FState.Load(AFileName, mProblem) then
  begin
    if mProblem = TCoverageProblem.NoLines then
    begin
      TAtlasIdeHost.Message(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoverageNoLines, [AFileName]));
    end
    else
    begin
      TAtlasIdeHost.Message(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoverageNotAReport, [AFileName]));
    end;
    Exit;
  end;
  mTotals := FState.Totals;
  TAtlasIdeHost.Message(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.CoverageLoaded,
    [mTotals.Files, mTotals.Covered, mTotals.Lines, mTotals.Percent, AFileName]));
  TAtlasIdeGutterMarks.Invalidate;
end;

class procedure TAtlasIdeTestCoverage.ProvideIn(const AScope: IAtlasModuleScope);
begin
  AScope.Provide(IAtlasGutterLayer, TAtlasIdeTestCoverage.Create as IAtlasGutterLayer);
end;

class procedure TAtlasIdeTestCoverage.Clear;
begin
  if FState <> nil then
  begin
    FState.Clear;
    TAtlasIdeGutterMarks.Invalidate;
  end;
end;

end.
