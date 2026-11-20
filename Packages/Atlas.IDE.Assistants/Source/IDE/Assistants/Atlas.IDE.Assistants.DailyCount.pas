unit Atlas.IDE.Assistants.DailyCount;

// Tageszähler der Anfragen an den eigenen KI-Anbieter (assistants.dailyLimit) in
// %LOCALAPPDATA%\Atlas\ai-requests.json (TAtlasDataFile). Schattentext (#1922) und Anfragen der IDE über den
// Atlas-Eintrag bei Smart CodeInsight (#2745) zählen in dieselbe Datei: Jede Anfrage liest den Stand neu, zählt
// und schreibt sofort. Ist die Datei nicht lesbar, wird sie nicht überschrieben (der Zähler beginnt dann im
// Speicher bei null). Nur im Hauptthread.

interface

type
  TAtlasIdeAiDailyCount = class
  public
    /// <summary>Eine Anfrage zählen, wenn heute noch unter ALimit; sonst False.</summary>
    class function TryTake(ALimit: Integer): Boolean; static;
    /// <summary>Anfragen heute.</summary>
    class function Today: Integer; static;
    class function CountFile: string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Assistants.AiGhost;

const
  cCountFile = 'ai-requests.json';
  cCountKind = 'KI-Anfragen'; // german-ok Protokoll

function DayText: string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd', Date);
end;

/// <summary>Stand aus der Datei; AWritable = False, wenn sie da, aber nicht lesbar ist.</summary>
procedure LoadInto(ACount: TAtlasAiDailyCount; out AWritable: Boolean);
var
  mLoad: TAtlasDataLoad;
begin
  mLoad := TAtlasDataFile.Load(TAtlasIdeAiDailyCount.CountFile, cCountKind,
    function(const AText: string): Boolean
    begin
      Result := ACount.FromJson(AText);
    end);
  AWritable := TAtlasDataFile.Writable(mLoad);
end;

class function TAtlasIdeAiDailyCount.CountFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), cCountFile);
end;

class function TAtlasIdeAiDailyCount.TryTake(ALimit: Integer): Boolean;
var
  mCount: TAtlasAiDailyCount;
  mWritable: Boolean;
begin
  mCount := TAtlasAiDailyCount.Create;
  try
    LoadInto(mCount, mWritable);
    Result := mCount.TryTake(DayText, ALimit);
    if Result and mWritable then
    begin
      try
        TAtlasDataFile.Write(CountFile, mCount.ToJson);
      except
        on E: Exception do
          TAtlasDataFile.ReportNotWritten(cCountKind, E);
      end;
    end;
  finally
    mCount.Free;
  end;
end;

class function TAtlasIdeAiDailyCount.Today: Integer;
var
  mCount: TAtlasAiDailyCount;
  mWritable: Boolean;
begin
  mCount := TAtlasAiDailyCount.Create;
  try
    LoadInto(mCount, mWritable);
    Result := mCount.CountOn(DayText);
  finally
    mCount.Free;
  end;
end;

end.
