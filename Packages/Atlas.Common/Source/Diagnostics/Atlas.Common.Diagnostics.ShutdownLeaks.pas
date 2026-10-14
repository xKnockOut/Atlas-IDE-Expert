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

interface

type
  TShutdownLeakReport = procedure(ABytes: Int64);

  TShutdownLeaks = record
  public
    /// <summary>Belegter Speicher des Speichermanagers in Bytes.</summary>
    class function AllocatedBytes: Int64; static;
    /// <summary>Meldetext, z. B. "Speicherrest beim Beenden: 128 Bytes".</summary>
    class function Describe(ABytes: Int64): string; static;
    /// <summary>Datei, an die beim Beenden eine Zeile angehängt wird; nur wenn sie dann existiert.</summary>
    class procedure SetLogFile(const AFileName: string); static;
    /// <summary>Melden einschalten (Debug-Build).</summary>
    class procedure Enable(AReport: TShutdownLeakReport); static;
  end;

implementation

uses
  System.SysUtils;

const
  MaxLogFileLength = 1023;

var
  Baseline: Int64;
  Enabled: Boolean;
  Report: TShutdownLeakReport;
  // Feste Größe statt string: Eine Zeichenkette auf dem Heap zählte selbst als Rest.
  LogFileBuffer: array[0..MaxLogFileLength] of Char;

{ TShutdownLeaks }

class function TShutdownLeaks.AllocatedBytes: Int64;
var
  State: TMemoryManagerState;
  Index: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(State);
  {$WARN SYMBOL_PLATFORM ON}
  Result := Int64(State.TotalAllocatedMediumBlockSize) + Int64(State.TotalAllocatedLargeBlockSize);
  for Index := Low(State.SmallBlockTypeStates) to High(State.SmallBlockTypeStates) do
    Inc(Result, Int64(State.SmallBlockTypeStates[Index].AllocatedBlockCount) *
      State.SmallBlockTypeStates[Index].UseableBlockSize);
end;

class function TShutdownLeaks.Describe(ABytes: Int64): string;
begin
  Result := Format('Speicherrest beim Beenden: %d Bytes', [ABytes]);
end;

class procedure TShutdownLeaks.SetLogFile(const AFileName: string);
var
  Count: Integer;
begin
  FillChar(LogFileBuffer, SizeOf(LogFileBuffer), 0);
  Count := Length(AFileName);
  if Count > MaxLogFileLength then
    Count := 0;
  if Count > 0 then
    Move(AFileName[1], LogFileBuffer[0], Count * SizeOf(Char));
end;

class procedure TShutdownLeaks.Enable(AReport: TShutdownLeakReport);
begin
  Enabled := True;
  Report := AReport;
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
  FileName: string;
  Log: TextFile;
begin
  FileName := PChar(@LogFileBuffer[0]);
  if (FileName = '') or not FileExists(FileName) then
    Exit;
  AssignFile(Log, FileName);
  {$I-}
  Append(Log);
  {$I+}
  if IOResult <> 0 then
    Exit;
  try
    // Reines ASCII: passt zu jeder Kodierung der Logdatei.
    Writeln(Log, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [WARN] ' + AText);
  finally
    CloseFile(Log);
  end;
end;

procedure Finish;
var
  Rest: Int64;
begin
  if not Enabled then
    Exit;
  Rest := TShutdownLeaks.AllocatedBytes - Baseline;
  if Rest <= 0 then
    Exit;
  try
    AppendToLog(TShutdownLeaks.Describe(Rest));
    if Assigned(Report) then
      Report(Rest);
  except
    // Beim Beenden darf nichts mehr scheitern.
  end;
end;

initialization
  Prewarm;
  Baseline := TShutdownLeaks.AllocatedBytes;

finalization
  Finish;

end.
