unit Atlas.Common.Diagnostics.ShutdownRest;

// Messung des Speicherrests beim Beenden (#177), ohne eine andere Unit. Die Unit steht als erste im uses der
// .dpr: Ihre initialization läuft direkt nach System und merkt sich den belegten Speicher, ihre finalization
// läuft nach allen anderen Units, auch nach SysUtils, Classes und den Texttabellen. Was dann mehr belegt ist
// als am Anfang, hat niemand freigegeben, auch nicht in einer Finalisierung.
//
// Würde die Unit eine andere einbinden, liefe deren initialization vorher und ihre finalization nachher: Alles,
// was andere Units dort anmelden (Texttabellen, Kodierungen, Klassenregister) und erst diese finalization
// freigibt, zählte als Rest. Deshalb kein uses, und die Zeile wird beim Beenden ohne SysUtils gebildet: Die
// Vorlage (in der Sprache beim Einschalten) liegt in einem Puffer fester Größe, eine Zeichenkette auf dem Heap
// zählte selbst als Rest.
//
// Ohne SetReport (Release) wird nichts gemeldet. Mit SetLimit wird der Rest zum Kriterium: Die Zeile kommt
// immer (auch bei 0, als Nachweis der Messung), über der Grenze setzt die finalization den Exit-Code.

interface

type
  /// <summary>Empfänger der Zeile beim Beenden. Läuft nach der Finalisierung aller anderen Units: nur System
  /// benutzen.</summary>
  TShutdownRestReport = procedure(const ALine: string);

  TShutdownRest = record
  public
    /// <summary>Belegter Speicher des Speichermanagers in Bytes.</summary>
    class function AllocatedBytes: Int64; static;
    /// <summary>ATemplate mit ARest für das erste und AMaxBytes für das zweite %d.</summary>
    class function Render(const ATemplate: string; ARest, AMaxBytes: Int64): string; static;
    /// <summary>True, wenn der Rest ARest über der Grenze AMaxBytes liegt.</summary>
    class function Exceeds(ARest, AMaxBytes: Int64): Boolean; static;
    /// <summary>Meldet beim Beenden einen Rest über 0 mit ATemplate (ein %d) an AReport. Vorlagen über 255
    /// Zeichen werden nicht gemeldet.</summary>
    class procedure SetReport(const ATemplate: string; AReport: TShutdownRestReport); static;
    /// <summary>Ab jetzt meldet das Beenden den Rest immer an den Empfänger aus SetReport, mit ATemplate (zwei
    /// %d: Rest, Grenze); liegt er über AMaxBytes, setzt es, falls noch 0, den Exit-Code AExitCode.</summary>
    class procedure SetLimit(const ATemplate: string; AMaxBytes: Int64; AExitCode: Integer); static;
    /// <summary>Datei, an die das Beenden die gemeldete Zeile anhängt, falls sie dann existiert. Ohne Zeitstempel:
    /// Die Uhrzeit liefert erst SysUtils, und das ist dann schon finalisiert.</summary>
    class procedure SetLogFile(const AFileName: string); static;
  end;

implementation

const
  cMaxTemplateLength = 255;
  cMaxLogFileLength = 1023;

type
  TTemplateBuffer = array[0..cMaxTemplateLength] of Char;
  TLogFileBuffer = array[0..cMaxLogFileLength] of Char;

var
  Baseline: Int64;
  Report: TShutdownRestReport;
  ReportTemplate: TTemplateBuffer;
  Limited: Boolean;
  LimitTemplate: TTemplateBuffer;
  MaxBytes: Int64;
  FailCode: Integer;
  LogFile: TLogFileBuffer;

/// <summary>AText nach ABuffer (ABufferChars Zeichen, eins davon für #0); zu lang: leer.</summary>
procedure Store(const AText: string; var ABuffer; ABufferChars: Integer);
var
  mCount: Integer;
begin
  FillChar(ABuffer, ABufferChars * SizeOf(Char), 0);
  mCount := Length(AText);
  if mCount >= ABufferChars then
  begin
    mCount := 0;
  end;
  if mCount > 0 then
  begin
    Move(AText[1], ABuffer, mCount * SizeOf(Char));
  end;
end;

{ TShutdownRest }

class function TShutdownRest.AllocatedBytes: Int64;
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

class function TShutdownRest.Render(const ATemplate: string; ARest, AMaxBytes: Int64): string;
var
  mIndex: Integer;
  mNumbers: Integer;
  mNumber: ShortString;
begin
  // Ohne SysUtils (kein Format): läuft nach dessen Finalisierung.
  Result := '';
  mNumbers := 0;
  mIndex := 1;
  while mIndex <= Length(ATemplate) do
  begin
    if (ATemplate[mIndex] = '%') and (mIndex < Length(ATemplate)) and (ATemplate[mIndex + 1] = 'd') then
    begin
      if mNumbers = 0 then
      begin
        Str(ARest, mNumber);
      end
      else
      begin
        Str(AMaxBytes, mNumber);
      end;
      Result := Result + string(mNumber);
      Inc(mNumbers);
      Inc(mIndex, 2);
    end
    else
    begin
      Result := Result + ATemplate[mIndex];
      Inc(mIndex);
    end;
  end;
end;

class function TShutdownRest.Exceeds(ARest, AMaxBytes: Int64): Boolean;
begin
  Result := ARest > AMaxBytes;
end;

class procedure TShutdownRest.SetReport(const ATemplate: string; AReport: TShutdownRestReport);
begin
  Store(ATemplate, ReportTemplate, Length(ReportTemplate));
  Report := AReport;
end;

class procedure TShutdownRest.SetLimit(const ATemplate: string; AMaxBytes: Int64; AExitCode: Integer);
begin
  Store(ATemplate, LimitTemplate, Length(LimitTemplate));
  MaxBytes := AMaxBytes;
  FailCode := AExitCode;
  Limited := True;
end;

class procedure TShutdownRest.SetLogFile(const AFileName: string);
begin
  Store(AFileName, LogFile, Length(LogFile));
end;

procedure AppendToLog(const ALine: string);
var
  mLog: TextFile;
begin
  if LogFile[0] = #0 then
  begin
    Exit;
  end;
  AssignFile(mLog, string(PChar(@LogFile[0])));
  // Ohne Datei scheitert Append; dann bleibt es still (FileExists gäbe es erst mit SysUtils).
  {$I-}
  Append(mLog);
  {$I+}
  if IOResult <> 0 then
  begin
    Exit;
  end;
  try
    // Reines ASCII: passt zu jeder Kodierung der Logdatei.
    Writeln(mLog, '[WARN] ' + ALine); // console-ok: Logdatei
  finally
    CloseFile(mLog);
  end;
end;

/// <summary>Zeile zum Rest ARest; leer, wenn nichts zu melden ist.</summary>
function ShutdownLine(ARest: Int64): string;
begin
  Result := '';
  if Limited then
  begin
    Result := TShutdownRest.Render(PChar(@LimitTemplate[0]), ARest, MaxBytes);
  end
  else if (ARest > 0) and (ReportTemplate[0] <> #0) then
  begin
    Result := TShutdownRest.Render(PChar(@ReportTemplate[0]), ARest, 0);
  end;
end;

procedure Finish;
var
  mRest: Int64;
  mLine: string;
begin
  if not Assigned(Report) and not Limited then
  begin
    Exit;
  end;
  mRest := TShutdownRest.AllocatedBytes - Baseline;
  try
    mLine := ShutdownLine(mRest);
    if mLine <> '' then
    begin
      AppendToLog(mLine);
      if Assigned(Report) then
      begin
        Report(mLine);
      end;
    end;
  except
    // Beim Beenden darf nichts mehr scheitern.
  end;
  // System schreibt ExitCode erst nach allen Finalisierungen in ExitProcess bzw. exit(); ein früher gesetzter
  // Fehlercode (fehlgeschlagene Tests) bleibt stehen.
  if Limited and TShutdownRest.Exceeds(mRest, MaxBytes) and (System.ExitCode = 0) then
  begin
    System.ExitCode := FailCode;
  end;
end;

initialization
  Baseline := TShutdownRest.AllocatedBytes;

finalization
  Finish;

end.
