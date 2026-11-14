unit Atlas.IDE.Tests.MutationMarks;

// Ergebnisse des Mutationslaufs (#1460) als Schicht der gemeinsamen
// Zeichenschicht der Rinne (TAtlasIdeGutterMarks):
// - je Zeile mit Mutanten ein Punkt: grün, wenn alle erkannt wurden (auch
//   durch Zeitüberschreitung), rot, wenn einer überlebt hat, grau, wenn keiner
//   bewertbar war (nicht übersetzbar, nicht anwendbar);
// - Tooltip: Zahlen der Zeile, je Mutant Original, Ersatz und Ausgang (mit
//   dem erkennenden Test) und die Zeit des Laufs;
// - nur Routinen, deren Text seit dem Lauf gleich geblieben ist
//   (TAtlasMutationResults.MarksOf); wer eine Routine ändert, sieht ihre
//   Punkte nicht mehr, bis sie neu geprüft ist.
// Die Ergebnisse hält TAtlasIdeMutationRun.Current; abschaltbar über
// tests.mutation und am Element (#628); gesichert über TAtlasFeature.Build.
// Nur im Hauptthread.

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Tests.MutationResults,
  Atlas.IDE.Foundation.GutterMarks;

type
  TAtlasIdeMutationMarks = class(TAtlasGutterLayer)
  private const
    /// <summary>Der Punkt nimmt die Hälfte des Symbolplatzes.</summary>
    cDotShare = 2;
    /// <summary>Kleinster Punkt in Pixeln.</summary>
    cDotMinSize = 3;
    /// <summary>Deckkraft der Farbe über dem Grund der Rinne.</summary>
    cDotStrength = 0.85;
  private
    /// <summary>Datei und Zeilen der letzten Verankerung und die Marken dazu.</summary>
    FFileName: string;
    FLines: TArray<string>;
    FMarks: TArray<TAtlasMutationLineMark>;
    /// <summary>Stand der Ergebnisse, zu dem FMarks gehört.</summary>
    FVersion: Integer;
    /// <summary>Marke aus dem letzten MarkAt; TAtlasIdeGutterMarks zeichnet direkt danach.</summary>
    FLast: TAtlasMutationLineMark;
    procedure Refresh;
    function MarkOf(const AFileName: string; ALine: Integer; out AMark: TAtlasMutationLineMark): Boolean;
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
    /// <summary>Die Schicht über den Scope des Moduls bereitstellen.</summary>
    class procedure ProvideIn(const AScope: IAtlasModuleScope); static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Text.Lines,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Mutation,
  Atlas.UI.Tests.Strings;

{ TAtlasIdeMutationMarks }

function TAtlasIdeMutationMarks.Feature: TAtlasFeature;
begin
  Result := TAtlasFeature.Build;
end;

function TAtlasIdeMutationMarks.Element: TAtlasDrawnElement;
begin
  Result := TAtlasDrawnElement.MutationResults;
end;

function TAtlasIdeMutationMarks.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestsMutation and (TAtlasIdeMutationRun.Current <> nil);
end;

procedure TAtlasIdeMutationMarks.Refresh;
begin
  FMarks := nil;
  if TAtlasIdeMutationRun.Current = nil then
  begin
    Exit;
  end;
  FMarks := TAtlasIdeMutationRun.Current.MarksOf(FFileName, FLines);
  FVersion := TAtlasIdeMutationRun.Current.Version;
end;

procedure TAtlasIdeMutationMarks.Track(const AFileName, AText: string; AOpened: Boolean);
begin
  FFileName := AFileName;
  FLines := TTextLines.SplitLines(AText);
  Refresh;
end;

function TAtlasIdeMutationMarks.HasMarks(const AFileName: string): Boolean;
begin
  if not SameText(AFileName, FFileName) or (TAtlasIdeMutationRun.Current = nil) then
  begin
    Exit(False);
  end;
  // Neue Ergebnisse seit der Verankerung: aus den gemerkten Zeilen, ohne die IDE zu fragen.
  if FVersion <> TAtlasIdeMutationRun.Current.Version then
  begin
    Refresh;
  end;
  Result := Length(FMarks) > 0;
end;

function TAtlasIdeMutationMarks.MarkOf(const AFileName: string; ALine: Integer;
  out AMark: TAtlasMutationLineMark): Boolean;
var
  mMark: TAtlasMutationLineMark;
begin
  AMark := Default(TAtlasMutationLineMark);
  if not HasMarks(AFileName) then
  begin
    Exit(False);
  end;
  for mMark in FMarks do
  begin
    if mMark.Line = ALine then
    begin
      AMark := mMark;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasIdeMutationMarks.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): Boolean;
begin
  Result := MarkOf(AFileName, ALine, FLast);
end;

procedure TAtlasIdeMutationMarks.PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  mDot: TRect;
  mSize: Integer;
  mColor: TAtlasColor;
begin
  if FLast.AnySurvived then
  begin
    mColor := AColors.Error;
  end
  else if FLast.AnyKilled then
  begin
    mColor := AColors.Add;
  end
  else
  begin
    mColor := AColors.Muted;
  end;
  mSize := Max(cDotMinSize, Min(AIcon.Width, AIcon.Height) div cDotShare);
  mDot := TRect.Create(0, 0, mSize, mSize);
  mDot.Offset(AIcon.Left + (AIcon.Width - mSize) div 2, AIcon.Top + (AIcon.Height - mSize) div 2);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(TAtlasColorMath.Mix(mColor, ABack, cDotStrength));
  ACanvas.Pen.Color := ACanvas.Brush.Color;
  ACanvas.Ellipse(mDot);
end;

function TAtlasIdeMutationMarks.TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean;
var
  mMark: TAtlasMutationLineMark;
  mTotals: TAtlasMutationTotals;
  mLines: TArray<string>;
  mIndex: Integer;
begin
  ATitle := '';
  AText := '';
  Result := MarkOf(AFileName, ALine, mMark);
  if not Result then
  begin
    Exit;
  end;
  mTotals := Default(TAtlasMutationTotals);
  SetLength(mLines, Length(mMark.Outcomes));
  for mIndex := 0 to High(mMark.Outcomes) do
  begin
    mTotals.Add(mMark.Outcomes[mIndex].Status);
    mLines[mIndex] := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationTipLine, [mMark.Outcomes[mIndex].Original,
      mMark.Outcomes[mIndex].Replacement, TAtlasIdeMutationRun.StatusText(mMark.Outcomes[mIndex].Status,
      mMark.Outcomes[mIndex].By)]);
  end;
  AText := string.Join(#10, mLines);
  ATitle := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationTipTitle, [mTotals.Killed + mTotals.TimedOut,
    mTotals.Survived]);
end;

class procedure TAtlasIdeMutationMarks.ProvideIn(const AScope: IAtlasModuleScope);
begin
  AScope.Provide(IAtlasGutterLayer, TAtlasIdeMutationMarks.Create as IAtlasGutterLayer);
end;

end.
