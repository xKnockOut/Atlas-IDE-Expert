unit Atlas.Common.Diagnostics.Adapters.LogFolder;

// Ziel des Diagnoselogs (#647): Tagesdateien in einem Ordner, je Prozess eine
// eigene ("diag-JJJJMMTT-<Kennung>.log"), damit mehrere Server (jede IDE
// startet einen) sich nicht in die Quere kommen.
// - Aufbewahrung: Dateien, die älter als RetentionDays sind, werden gelöscht.
// - Laufmarke "run-<Kennung>.open": beim Start angelegt und offen gehalten,
//   beim sauberen Ende gelöscht. Findet ein neuer Lauf eine Marke, die sich
//   löschen lässt, endete ein früherer Lauf ohne Endzeile (Prozess beendet
//   oder abgestürzt).
// - Die Zuordnung Kurz-ID → Name ("diag-map-…txt") schreibt nur WriteMap; der
//   Export lässt sie aus.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Diagnostics.Contract;

type
  TDiagnosticLogFolder = class(TInterfacedObject, IDiagnosticWriter)
  public const
    FilePattern = 'diag-*.log';
    MapPattern = 'diag-map-*.txt';
    MarkerPattern = 'run-*.open';
  private
    FFolder: string;
    FTag: string;
    FDay: string;
    FStream: TStream;
    FMarker: TStream;
    FRetentionDays: Integer;
    FLock: TObject;
    procedure OpenFor(const ADay: string);
  public
    /// <summary>ATag unterscheidet die Prozesse, z. B. die Prozessnummer.</summary>
    constructor Create(const AFolder, ATag: string);
    destructor Destroy; override;
    procedure WriteLine(const ALine: string);
    /// <summary>Legt die eigene Laufmarke an; liefert die Zahl früherer Läufe ohne Ende.</summary>
    function BeginRun: Integer;
    /// <summary>Löscht die eigene Laufmarke (sauberes Ende).</summary>
    procedure EndRun;
    /// <summary>Löscht Diagnoselogs und Map-Dateien, die älter als ADays Tage sind.</summary>
    procedure Cleanup(ADays: Integer);
    /// <summary>Schreibt die Zuordnung Kurz-ID → Name (nur für die eigene Analyse).</summary>
    procedure WriteMap(const ALines: TArray<string>);
    property Folder: string read FFolder;
    property RetentionDays: Integer read FRetentionDays write FRetentionDays;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils;

{ TDiagnosticLogFolder }

constructor TDiagnosticLogFolder.Create(const AFolder, ATag: string);
begin
  inherited Create;
  FFolder := AFolder;
  FTag := ATag;
  FRetentionDays := 7;
  FLock := TObject.Create;
end;

destructor TDiagnosticLogFolder.Destroy;
begin
  FStream.Free;
  FMarker.Free;
  FLock.Free;
  inherited;
end;

procedure TDiagnosticLogFolder.OpenFor(const ADay: string);
var
  FileName: string;
begin
  FreeAndNil(FStream);
  FDay := ADay;
  ForceDirectories(FFolder);
  FileName := TPath.Combine(FFolder, Format('diag-%s-%s.log', [ADay, FTag]));
  if FileExists(FileName) then
  begin
    FStream := TFileStream.Create(FileName, fmOpenWrite or fmShareDenyWrite);
    FStream.Seek(0, soEnd);
  end
  else
    FStream := TFileStream.Create(FileName, fmCreate or fmShareDenyWrite);
end;

procedure TDiagnosticLogFolder.WriteLine(const ALine: string);
var
  Day: string;
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(ALine + #13#10);
  TMonitor.Enter(FLock);
  try
    try
      Day := FormatDateTime('yyyymmdd', Now);
      if (FStream = nil) or (Day <> FDay) then
        OpenFor(Day);
      FStream.WriteBuffer(Bytes, Length(Bytes));
    except
      // Das Diagnoselog darf den Server nie stören (Platte voll, Ordner gesperrt).
      on EStreamError do
        FreeAndNil(FStream);
      on EInOutError do
        FreeAndNil(FStream);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TDiagnosticLogFolder.BeginRun: Integer;
var
  FileName, Own: string;
begin
  Result := 0;
  try
    ForceDirectories(FFolder);
    Own := TPath.Combine(FFolder, Format('run-%s.open', [FTag]));
    // Marken anderer, noch laufender Server sind offen und lassen sich nicht löschen.
    for FileName in TDirectory.GetFiles(FFolder, MarkerPattern) do
      if not SameText(FileName, Own) and System.SysUtils.DeleteFile(FileName) then
        Inc(Result);
    if FMarker = nil then
      FMarker := TFileStream.Create(Own, fmCreate or fmShareExclusive);
  except
    on EStreamError do
      Result := 0;
    on EInOutError do
      Result := 0;
  end;
end;

procedure TDiagnosticLogFolder.EndRun;
var
  FileName: string;
begin
  if FMarker = nil then
    Exit;
  FileName := TFileStream(FMarker).FileName;
  FreeAndNil(FMarker);
  System.SysUtils.DeleteFile(FileName);
end;

procedure TDiagnosticLogFolder.Cleanup(ADays: Integer);
var
  FileName: string;
  Limit: TDateTime;
begin
  if (ADays <= 0) or not TDirectory.Exists(FFolder) then
    Exit;
  Limit := IncDay(Now, -ADays);
  try
    for FileName in TDirectory.GetFiles(FFolder, FilePattern) + TDirectory.GetFiles(FFolder, MapPattern) do
      if TFile.GetLastWriteTime(FileName) < Limit then
        System.SysUtils.DeleteFile(FileName);
  except
    on EInOutError do
      ;
  end;
end;

procedure TDiagnosticLogFolder.WriteMap(const ALines: TArray<string>);
begin
  if Length(ALines) = 0 then
    Exit;
  try
    ForceDirectories(FFolder);
    TFile.WriteAllLines(TPath.Combine(FFolder, Format('diag-map-%s-%s.txt', [FormatDateTime('yyyymmdd', Now),
      FTag])), ALines, TEncoding.UTF8);
  except
    on EInOutError do
      ;
    on EStreamError do
      ;
  end;
end;

end.
