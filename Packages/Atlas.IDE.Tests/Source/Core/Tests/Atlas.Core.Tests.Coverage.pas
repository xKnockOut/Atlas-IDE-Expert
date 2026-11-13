unit Atlas.Core.Tests.Coverage;

// Testabdeckung in der Rinne (#275), ohne VCL und Open Tools API: Zustand
// des geladenen Berichts von DelphiCodeCoverage (Atlas.Text.Coverage,
// CodeCoverage_Summary.xml mit -xmllines oder jacoco.xml).
// - Load liest den Bericht von der Platte (DelphiCodeCoverage 1.0.15 schreibt
//   ohne Kopf in der Codepage von Windows, also ANSI; UTF-8 nur mit BOM oder
//   encoding="UTF-8" im Kopf); Reload liest ihn neu, sobald sich
//   seine Änderungszeit ändert (neuer Lauf), und vergisst ihn, wenn die Datei
//   verschwunden ist.
// - HitsAt nennt die Durchläufe einer Zeile; die Datei im Editor findet der
//   Zustand über TCoverageReport.IndexOf (voller Pfad, Pfadende oder
//   eindeutiger Dateiname) und merkt sich die letzte Zuordnung, weil die Rinne
//   je gezeichneter Zeile fragt.
// - SourceNewer: Ist die Quelldatei nach dem Bericht gespeichert worden,
//   passen die Zeilen womöglich nicht mehr; der Tooltip sagt es dazu.
// Texte baut die IDE-Schicht (Atlas.IDE.Tests.Coverage).

interface

uses
  System.SysUtils,
  Atlas.Text.Coverage;

type
  /// <summary>Zahlen für die Meldung nach dem Laden.</summary>
  TAtlasCoverageTotals = record
    Files: Integer;
    Lines: Integer;
    Covered: Integer;
    /// <summary>Anteil in Prozent, auf eine ganze Zahl abgerundet; 0 ohne Zeilen.</summary>
    function Percent: Integer;
  end;

  TAtlasCoverageState = class
  private
    FPath: string;
    FStamp: TDateTime;
    FReport: TCoverageReport;
    FLastFile: string;
    FLastIndex: Integer;
    function IndexFor(const AFileName: string): Integer;
  public
    /// <summary>Text aus den Bytes eines Berichts: nach der Kennung (BOM), sonst UTF-8 mit encoding="UTF-8"
    /// im XML-Kopf, sonst ANSI (Codepage von Windows).</summary>
    class function DecodeReport(const ABytes: TBytes): string; static;
    constructor Create;
    /// <summary>Bericht APath lesen. False, wenn die Datei fehlt, nicht lesbar ist oder kein brauchbarer Bericht
    /// ist (AProblem sagt warum; NotAReport auch bei fehlender Datei); der bisherige Bericht bleibt dann.</summary>
    function Load(const APath: string; out AProblem: TCoverageProblem): Boolean;
    /// <summary>Bericht aus dem Text AXml übernehmen (Load ohne Platte; AStamp ist die Änderungszeit).</summary>
    function Accept(const APath, AXml: string; AStamp: TDateTime; out AProblem: TCoverageProblem): Boolean;
    /// <summary>Neu lesen, wenn sich der Bericht auf der Platte geändert hat; ist er weg, ist nichts mehr geladen.
    /// True, wenn sich etwas geändert hat.</summary>
    function Reload: Boolean;
    procedure Clear;
    function Loaded: Boolean;
    /// <summary>Hat AFileName Zeilen im Bericht?</summary>
    function HasFile(const AFileName: string): Boolean;
    /// <summary>Durchläufe in Zeile ALine (0-basiert wie im Editor) von AFileName; -1 ohne Code oder ohne
    /// Datei im Bericht.</summary>
    function HitsAt(const AFileName: string; ALine: Integer): Integer;
    /// <summary>Abgedeckte und alle Zeilen von AFileName; False ohne Datei im Bericht.</summary>
    function FileTotals(const AFileName: string; out ACovered, ALines: Integer): Boolean;
    function Totals: TAtlasCoverageTotals;
    /// <summary>Wurde AFileName nach dem Bericht gespeichert?</summary>
    function SourceNewer(const AFileName: string): Boolean;
    property Path: string read FPath;
    property Report: TCoverageReport read FReport;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.IOUtils;

{ TAtlasCoverageTotals }

function TAtlasCoverageTotals.Percent: Integer;
begin
  Result := 0;
  if Lines > 0 then
  begin
    Result := Int64(Covered) * 100 div Lines;
  end;
end;

{ TAtlasCoverageState }

constructor TAtlasCoverageState.Create;
begin
  inherited Create;
  Clear;
end;

procedure TAtlasCoverageState.Clear;
begin
  FPath := '';
  FStamp := 0;
  FReport := Default(TCoverageReport);
  FLastFile := '';
  FLastIndex := -1;
end;

function TAtlasCoverageState.Loaded: Boolean;
begin
  Result := FPath <> '';
end;

function TAtlasCoverageState.Accept(const APath, AXml: string; AStamp: TDateTime;
  out AProblem: TCoverageProblem): Boolean;
var
  mReport: TCoverageReport;
begin
  mReport := TCoverage.Parse(AXml);
  AProblem := mReport.Problem;
  Result := mReport.Valid;
  if not Result then
  begin
    Exit;
  end;
  FPath := APath;
  FStamp := AStamp;
  FReport := mReport;
  FLastFile := '';
  FLastIndex := -1;
end;

function TAtlasCoverageState.Load(const APath: string; out AProblem: TCoverageProblem): Boolean;
var
  mStamp: TDateTime;
  mXml: string;
begin
  AProblem := TCoverageProblem.NotAReport;
  if not FileAge(APath, mStamp) then
  begin
    Exit(False);
  end;
  try
    mXml := DecodeReport(TFile.ReadAllBytes(APath));
  except
    on EInOutError do
    begin
      Exit(False);
    end;
    on EFileStreamError do
    begin
      Exit(False);
    end;
    on EEncodingError do
    begin
      Exit(False);
    end;
  end;
  Result := Accept(APath, mXml, mStamp, AProblem);
end;

class function TAtlasCoverageState.DecodeReport(const ABytes: TBytes): string;
const
  cHeadLength = 200;
var
  mEncoding: TEncoding;
  mBom: Integer;
  mHead: string;
begin
  // Mit Kennung (BOM) gilt sie; sonst entscheidet die Angabe im XML-Kopf.
  mEncoding := nil;
  mBom := TEncoding.GetBufferEncoding(ABytes, mEncoding, TEncoding.ANSI);
  if mBom > 0 then
  begin
    Exit(mEncoding.GetString(ABytes, mBom, Length(ABytes) - mBom));
  end;
  // Der Kopf ist ASCII: als ANSI gelesen lässt sich die Angabe sicher finden.
  mHead := LowerCase(TEncoding.ANSI.GetString(ABytes, 0, Min(Length(ABytes), cHeadLength)));
  mHead := mHead.Replace('''', '"');
  if mHead.Contains('encoding="utf-8"') then
  begin
    Result := TEncoding.UTF8.GetString(ABytes);
  end
  else
  begin
    Result := TEncoding.ANSI.GetString(ABytes);
  end;
end;

function TAtlasCoverageState.Reload: Boolean;
var
  mStamp: TDateTime;
  mProblem: TCoverageProblem;
begin
  Result := False;
  if not Loaded then
  begin
    Exit;
  end;
  if not FileAge(FPath, mStamp) then
  begin
    Clear;
    Exit(True);
  end;
  if mStamp <> FStamp then
  begin
    // Halb geschriebener Bericht: den alten behalten, beim nächsten Mal wieder versuchen.
    Result := Load(FPath, mProblem);
  end;
end;

function TAtlasCoverageState.IndexFor(const AFileName: string): Integer;
begin
  if not SameText(AFileName, FLastFile) or (FLastFile = '') then
  begin
    FLastFile := AFileName;
    FLastIndex := FReport.IndexOf(AFileName);
  end;
  Result := FLastIndex;
end;

function TAtlasCoverageState.HasFile(const AFileName: string): Boolean;
begin
  Result := Loaded and (AFileName <> '') and (IndexFor(AFileName) >= 0);
end;

function TAtlasCoverageState.HitsAt(const AFileName: string; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if not HasFile(AFileName) then
  begin
    Exit;
  end;
  mIndex := IndexFor(AFileName);
  Result := FReport.Files[mIndex].HitsAt(ALine + 1);
end;

function TAtlasCoverageState.FileTotals(const AFileName: string; out ACovered, ALines: Integer): Boolean;
var
  mIndex: Integer;
begin
  ACovered := 0;
  ALines := 0;
  Result := HasFile(AFileName);
  if Result then
  begin
    mIndex := IndexFor(AFileName);
    ACovered := FReport.Files[mIndex].CoveredCount;
    ALines := FReport.Files[mIndex].LineCount;
  end;
end;

function TAtlasCoverageState.Totals: TAtlasCoverageTotals;
var
  mFile: TCoverageFile;
begin
  Result := Default(TAtlasCoverageTotals);
  for mFile in FReport.Files do
  begin
    Inc(Result.Files);
    Inc(Result.Lines, mFile.LineCount);
    Inc(Result.Covered, mFile.CoveredCount);
  end;
end;

function TAtlasCoverageState.SourceNewer(const AFileName: string): Boolean;
var
  mStamp: TDateTime;
begin
  Result := Loaded and FileAge(AFileName, mStamp) and (mStamp > FStamp);
end;

end.
