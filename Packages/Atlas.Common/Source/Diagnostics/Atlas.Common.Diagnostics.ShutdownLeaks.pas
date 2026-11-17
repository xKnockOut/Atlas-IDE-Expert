unit Atlas.Common.Diagnostics.ShutdownLeaks;

// Speicherrest beim Beenden zählen, ohne Dialog (#177). ReportMemoryLeaksOnShutdown
// zeigt beim Speichermanager der RTL ein modales Fenster; im unsichtbar
// gestarteten Server blockiert das das Beenden, im Testlauf hängt der Job.
//
// Die Unit steht als erste im uses der .dpr: Ihre initialization läuft vor
// allen anderen Units (außer System und SysUtils) und merkt sich den belegten
// Speicher, ihre finalization läuft nach allen anderen. Was dann mehr belegt
// ist als am Anfang, ist nicht freigegeben worden. Gemeldet wird nur die Zahl
// der Bytes, ohne Namen (#647): an Report und, falls gesetzt, als Zeile ans
// Ende von LogFile.
//
// Bei Enabled = False (Release) wird nichts gemeldet.
//
// Mit Expect wird der Rest zum Kriterium (Testlauf): Die Messung je Test kann eine Belegung, die beim ersten
// Gebrauch entsteht und nie freigegeben wird, nicht von einem Zwischenspeicher unterscheiden, der bis zum
// Programmende lebt und dort freigegeben wird. Das kann nur diese Messung. Finish meldet den Rest dann immer
// (auch 0, als Nachweis, dass gemessen wurde) samt Grenze und setzt über der Grenze den Exit-Code. Skripte, die
// den Lauf auswerten, lesen dieselbe Zeile, falls der Exit-Code den Prozess nicht erreicht.

interface

type
  TShutdownLeakReport = procedure(ABytes: Int64);

  TShutdownLeaks = record
  public
    /// <summary>Belegter Speicher des Speichermanagers in Bytes.</summary>
    class function AllocatedBytes: Int64; static;
    /// <summary>Meldetext, z. B. "Speicherrest beim Beenden: 128 Bytes".</summary>
    class function Describe(ABytes: Int64): string; static;
    /// <summary>Meldetext mit Grenze, z. B. "Speicherrest beim Beenden: 128 Bytes (erlaubt: 0)".</summary>
    class function DescribeLimit(ABytes, AMaxBytes: Int64): string; static;
    /// <summary>Meldetext für ABytes: mit Grenze, sobald Expect gerufen wurde, sonst wie Describe.</summary>
    class function Summary(ABytes: Int64): string; static;
    /// <summary>True, wenn der Rest ARest über der Grenze AMaxBytes liegt.</summary>
    class function Exceeds(ARest, AMaxBytes: Int64): Boolean; static;
    /// <summary>Datei, an die beim Beenden eine Zeile angehängt wird; nur wenn sie dann existiert.</summary>
    class procedure SetLogFile(const AFileName: string); static;
    /// <summary>Melden einschalten (Debug-Build).</summary>
    class procedure Enable(AReport: TShutdownLeakReport); static;
    /// <summary>Beim Beenden darf höchstens AMaxBytes mehr belegt sein als beim Start (bekannter Rest der RTL).
    /// Ab jetzt meldet Finish den Rest immer, mit Grenze; darüber setzt es, falls noch 0, den Exit-Code
    /// AExitCode.</summary>
    class procedure Expect(AMaxBytes: Int64; AExitCode: Integer); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TShutdownLeaksText = (MemoryLeftAtShutdownBytes, MemoryLeftAtShutdownLimit);

const
  cTexts: array[TShutdownLeaksText] of TAtlasText = (
    (De: 'Speicherrest beim Beenden: %d Bytes'; En: 'Memory left at shutdown: %d bytes'),
    (De: 'Speicherrest beim Beenden: %d Bytes (erlaubt: %d)'; En: 'Memory left at shutdown: %d bytes (allowed: %d)'));

{$SCOPEDENUMS OFF}

const
  cMaxLogFileLength = 1023;

var
  Baseline: Int64;
  Enabled: Boolean;
  Report: TShutdownLeakReport;
  Expecting: Boolean;
  MaxBytes: Int64;
  FailCode: Integer;
  // Feste Größe statt string: Eine Zeichenkette auf dem Heap zählte selbst als Rest.
  LogFileBuffer: array[0..cMaxLogFileLength] of Char;

{ TShutdownLeaks }

class function TShutdownLeaks.AllocatedBytes: Int64;
{$IFDEF FPC}
begin
  // Linux-Bau mit Free Pascal (#1109): der Heap von FPC statt FastMM.
  Result := GetFPCHeapStatus.CurrHeapUsed;
end;
{$ELSE}
var
  mState: TMemoryManagerState;
  mIndex: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(mState);
  {$WARN SYMBOL_PLATFORM DEFAULT}
  Result := Int64(mState.TotalAllocatedMediumBlockSize) + Int64(mState.TotalAllocatedLargeBlockSize);
  for mIndex := Low(mState.SmallBlockTypeStates) to High(mState.SmallBlockTypeStates) do
  begin
    Inc(Result, Int64(mState.SmallBlockTypeStates[mIndex].AllocatedBlockCount) *
      mState.SmallBlockTypeStates[mIndex].UseableBlockSize);
  end;
end;
{$ENDIF}

class function TShutdownLeaks.Describe(ABytes: Int64): string;
begin
  Result := cTexts[TShutdownLeaksText.MemoryLeftAtShutdownBytes].Fmt([ABytes]);
end;

class function TShutdownLeaks.DescribeLimit(ABytes, AMaxBytes: Int64): string;
begin
  Result := cTexts[TShutdownLeaksText.MemoryLeftAtShutdownLimit].Fmt([ABytes, AMaxBytes]);
end;

class function TShutdownLeaks.Summary(ABytes: Int64): string;
begin
  if Expecting then
  begin
    Result := DescribeLimit(ABytes, MaxBytes);
  end
  else
  begin
    Result := Describe(ABytes);
  end;
end;

class function TShutdownLeaks.Exceeds(ARest, AMaxBytes: Int64): Boolean;
begin
  Result := ARest > AMaxBytes;
end;

class procedure TShutdownLeaks.SetLogFile(const AFileName: string);
var
  mCount: Integer;
begin
  FillChar(LogFileBuffer, SizeOf(LogFileBuffer), 0);
  mCount := Length(AFileName);
  if mCount > cMaxLogFileLength then
  begin
    mCount := 0;
  end;
  if mCount > 0 then
  begin
    Move(AFileName[1], LogFileBuffer[0], mCount * SizeOf(Char));
  end;
end;

class procedure TShutdownLeaks.Enable(AReport: TShutdownLeakReport);
begin
  Enabled := True;
  Report := AReport;
end;

class procedure TShutdownLeaks.Expect(AMaxBytes: Int64; AExitCode: Integer);
begin
  Expecting := True;
  MaxBytes := AMaxBytes;
  FailCode := AExitCode;
end;

// Legt Objekte an, die SysUtils erst bei Bedarf erzeugt und in seiner
// finalization freigibt; sie dürfen nicht als Rest zählen.
procedure Prewarm;
begin
  TEncoding.ASCII.GetByteCount('a');
  TEncoding.ANSI.GetByteCount('a');
  TEncoding.Default.GetByteCount('a');
  TEncoding.UTF8.GetByteCount('a');
  TEncoding.Unicode.GetByteCount('a');
  TEncoding.BigEndianUnicode.GetByteCount('a');
  TEncoding.UTF7.GetByteCount('a');
end;

procedure AppendToLog(const AText: string);
var
  mFileName: string;
  mLog: TextFile;
begin
  mFileName := PChar(@LogFileBuffer[0]);
  if (mFileName = '') or not FileExists(mFileName) then
  begin
    Exit;
  end;
  AssignFile(mLog, mFileName);
  {$I-}
  Append(mLog);
  {$I+}
  if IOResult <> 0 then
  begin
    Exit;
  end;
  try
    // Reines ASCII: passt zu jeder Kodierung der Logdatei.
    Writeln(mLog, FormatDateTime('yyyy-mm-dd hh":"nn":"ss.zzz', Now) + ' [WARN] ' + AText); // console-ok: Logdatei
  finally
    CloseFile(mLog);
  end;
end;

procedure Finish;
var
  mRest: Int64;
begin
  if not Enabled then
  begin
    Exit;
  end;
  mRest := TShutdownLeaks.AllocatedBytes - Baseline;
  if (mRest <= 0) and not Expecting then
  begin
    Exit;
  end;
  try
    AppendToLog(TShutdownLeaks.Summary(mRest));
    if Assigned(Report) then
    begin
      Report(mRest);
    end;
  except
    // Beim Beenden darf nichts mehr scheitern.
  end;
  // System schreibt ExitCode erst nach allen Finalisierungen in ExitProcess bzw. exit(); ein früher gesetzter
  // Fehlercode (fehlgeschlagene Tests) bleibt stehen.
  if Expecting and TShutdownLeaks.Exceeds(mRest, MaxBytes) and (System.ExitCode = 0) then
  begin
    System.ExitCode := FailCode;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Diagnostics.ShutdownLeaks', cTexts);
  Prewarm;
  Baseline := TShutdownLeaks.AllocatedBytes;

finalization
  Finish;

end.
