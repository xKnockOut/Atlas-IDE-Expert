unit Atlas.Core.Debug.LeakCapture;

// Leckbericht am Ende einer Debug-Sitzung (#1875), ohne VCL und Open Tools API:
//   - Welche Fenstertexte des Programms sind ein Leckbericht (Meldungsfenster
//     von ReportMemoryLeaksOnShutdown)?
//   - Welche Logdatei schreibt FastMM4/FastMM5 neben die EXE, und zählt sie
//     (jünger als der Start)?
//   - Welcher Bericht gilt: die Logdatei mit Aufrufstapeln vor dem
//     Meldungsfenster, sonst das Meldungsfenster, sonst die Logdatei.
//   - Vergleich mit dem letzten Lauf je Projekt und Konfiguration: neue
//     Klassen und gestiegene Zahlen markiert, „bekannt“ zum Ausblenden.
// Der Stand des letzten Laufs ist eine kleine Textdatei (Zeilen „count:Name=n“
// und „known:Name“), damit der Kern ohne JSON auskommt. Lesen und Schreiben
// der Dateien übernimmt die IDE-Schicht.

interface

uses
  Atlas.Text.LeakReport;

type
{$SCOPEDENUMS ON}
  TAtlasLeakSource = (None, MessageBox, LogFile);
{$SCOPEDENUMS OFF}

  TAtlasLeakCapture = record
    Source: TAtlasLeakSource;
    Text: string;
    /// <summary>Logdatei; '' beim Meldungsfenster.</summary>
    FileName: string;
    Report: TLeakReport;
    function IsEmpty: Boolean;
  end;

  /// <summary>Stand des letzten Laufs: Zahl je Name und als bekannt markierte Namen.</summary>
  TAtlasLeakHistory = record
    Names: TArray<string>;
    Counts: TArray<Integer>;
    Known: TArray<string>;
    function CountOf(const AName: string): Integer;
    function IsKnown(const AName: string): Boolean;
  end;

  /// <summary>Eine Zeile des Fensters: Name aus dem Bericht mit Vergleich zum letzten Lauf.</summary>
  TAtlasLeakEntry = record
    Name: string;
    Kind: TLeakKind;
    Count: Integer;
    /// <summary>Zahl im letzten Lauf; 0 ohne.</summary>
    PreviousCount: Integer;
    /// <summary>Im letzten Lauf nicht dabei oder seitdem mehr geworden.</summary>
    IsNew: Boolean;
    Known: Boolean;
  end;

  TAtlasLeakCaptures = class
  public const
    cLogSuffix = '_MemoryManager_EventLog.txt';
    cCountPrefix = 'count:';
    cKnownPrefix = 'known:';
  public
    /// <summary>Logdatei von FastMM4/FastMM5 zur EXE (Vorgabename beider).</summary>
    class function LogFileOf(const AExeFile: string): string; static;
    /// <summary>Erster Text mit einem Leckbericht; False ohne.</summary>
    class function FromWindowTexts(const ATexts: TArray<string>; out ACapture: TAtlasLeakCapture): Boolean; static;
    /// <summary>Logdatei, wenn sie nach AStarted geschrieben wurde und einen Bericht enthält.</summary>
    class function FromLogFile(const AFileName, AText: string; AWritten, AStarted: TDateTime;
      out ACapture: TAtlasLeakCapture): Boolean; static;
    /// <summary>Logdatei mit Stapeln vor dem Meldungsfenster, sonst das Meldungsfenster, sonst die Logdatei.</summary>
    class function Choose(const ABox, ALog: TAtlasLeakCapture): TAtlasLeakCapture; static;
    /// <summary>Zeilen zu AReport mit Vergleich zu AHistory, in der Reihenfolge des Berichts.</summary>
    class function Compare(const AReport: TLeakReport; const AHistory: TAtlasLeakHistory): TArray<TAtlasLeakEntry>;
      static;
    /// <summary>Neuer Stand nach einem Lauf: Zahlen aus AReport, bekannte Namen bleiben.</summary>
    class function NextHistory(const AReport: TLeakReport; const AHistory: TAtlasLeakHistory): TAtlasLeakHistory;
      static;
    /// <summary>AName als bekannt markieren oder die Markierung aufheben.</summary>
    class function MarkKnown(const AHistory: TAtlasLeakHistory; const AName: string; AKnown: Boolean):
      TAtlasLeakHistory; static;
    class function HistoryToText(const AHistory: TAtlasLeakHistory): string; static;
    /// <summary>Stand aus dem Text; unbekannte Zeilen zählen nicht.</summary>
    class function HistoryFromText(const AText: string): TAtlasLeakHistory; static;
    /// <summary>Dateiname des Stands je Konfiguration und Plattform (ohne Ordner).</summary>
    class function HistoryFileName(const AConfig, APlatform: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines;

function TAtlasLeakCapture.IsEmpty: Boolean;
begin
  Result := (Source = TAtlasLeakSource.None) or Report.IsEmpty;
end;

function IndexOfName(const ANames: TArray<string>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANames) do
  begin
    if SameText(ANames[mIndex], AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasLeakHistory.CountOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  mIndex := IndexOfName(Names, AName);
  Result := 0;
  if mIndex >= 0 then
  begin
    Result := Counts[mIndex];
  end;
end;

function TAtlasLeakHistory.IsKnown(const AName: string): Boolean;
begin
  Result := IndexOfName(Known, AName) >= 0;
end;

class function TAtlasLeakCaptures.LogFileOf(const AExeFile: string): string;
begin
  Result := ChangeFileExt(AExeFile, '') + cLogSuffix;
end;

class function TAtlasLeakCaptures.FromWindowTexts(const ATexts: TArray<string>;
  out ACapture: TAtlasLeakCapture): Boolean;
var
  mText: string;
begin
  ACapture := Default(TAtlasLeakCapture);
  for mText in ATexts do
  begin
    ACapture.Report := TLeakReports.Parse(mText);
    if not ACapture.Report.IsEmpty then
    begin
      ACapture.Source := TAtlasLeakSource.MessageBox;
      ACapture.Text := mText;
      Exit(True);
    end;
  end;
  ACapture := Default(TAtlasLeakCapture);
  Result := False;
end;

class function TAtlasLeakCaptures.FromLogFile(const AFileName, AText: string; AWritten, AStarted: TDateTime;
  out ACapture: TAtlasLeakCapture): Boolean;
begin
  ACapture := Default(TAtlasLeakCapture);
  Result := AWritten >= AStarted;
  if not Result then
  begin
    Exit;
  end;
  ACapture.Report := TLeakReports.Parse(AText);
  Result := not ACapture.Report.IsEmpty;
  if Result then
  begin
    ACapture.Source := TAtlasLeakSource.LogFile;
    ACapture.Text := AText;
    ACapture.FileName := AFileName;
  end
  else
  begin
    ACapture := Default(TAtlasLeakCapture);
  end;
end;

class function TAtlasLeakCaptures.Choose(const ABox, ALog: TAtlasLeakCapture): TAtlasLeakCapture;
begin
  if not ALog.IsEmpty and (ALog.Report.HasStacks or ABox.IsEmpty) then
  begin
    Result := ALog;
  end
  else
  begin
    Result := ABox;
  end;
end;

class function TAtlasLeakCaptures.Compare(const AReport: TLeakReport;
  const AHistory: TAtlasLeakHistory): TArray<TAtlasLeakEntry>;
var
  mIndex: Integer;
  mEntry: TAtlasLeakEntry;
begin
  SetLength(Result, Length(AReport.Counts));
  for mIndex := 0 to High(AReport.Counts) do
  begin
    mEntry := Default(TAtlasLeakEntry);
    mEntry.Name := AReport.Counts[mIndex].Name;
    mEntry.Kind := AReport.Counts[mIndex].Kind;
    mEntry.Count := AReport.Counts[mIndex].Count;
    mEntry.PreviousCount := AHistory.CountOf(mEntry.Name);
    mEntry.IsNew := mEntry.Count > mEntry.PreviousCount;
    mEntry.Known := AHistory.IsKnown(mEntry.Name);
    Result[mIndex] := mEntry;
  end;
end;

class function TAtlasLeakCaptures.NextHistory(const AReport: TLeakReport;
  const AHistory: TAtlasLeakHistory): TAtlasLeakHistory;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasLeakHistory);
  SetLength(Result.Names, Length(AReport.Counts));
  SetLength(Result.Counts, Length(AReport.Counts));
  for mIndex := 0 to High(AReport.Counts) do
  begin
    Result.Names[mIndex] := AReport.Counts[mIndex].Name;
    Result.Counts[mIndex] := AReport.Counts[mIndex].Count;
  end;
  Result.Known := Copy(AHistory.Known);
end;

class function TAtlasLeakCaptures.MarkKnown(const AHistory: TAtlasLeakHistory; const AName: string;
  AKnown: Boolean): TAtlasLeakHistory;
var
  mIndex: Integer;
begin
  Result := AHistory;
  Result.Known := Copy(AHistory.Known);
  mIndex := IndexOfName(Result.Known, AName);
  if AKnown and (mIndex < 0) then
  begin
    Result.Known := Result.Known + [AName];
  end
  else if not AKnown and (mIndex >= 0) then
  begin
    Delete(Result.Known, mIndex, 1);
  end;
end;

class function TAtlasLeakCaptures.HistoryToText(const AHistory: TAtlasLeakHistory): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mLines, Length(AHistory.Names) + Length(AHistory.Known));
  for mIndex := 0 to High(AHistory.Names) do
  begin
    mLines[mIndex] := cCountPrefix + AHistory.Names[mIndex] + '=' + IntToStr(AHistory.Counts[mIndex]);
  end;
  for mIndex := 0 to High(AHistory.Known) do
  begin
    mLines[Length(AHistory.Names) + mIndex] := cKnownPrefix + AHistory.Known[mIndex];
  end;
  Result := TTextLines.JoinLines(mLines, sLineBreak);
end;

/// <summary>Zeile „count:Name=n“ in AHistory übernehmen; andere Zeilen zählen nicht.</summary>
procedure ReadCountLine(const ALine: string; var AHistory: TAtlasLeakHistory);
var
  mRest: string;
  mAt, mCount: Integer;
begin
  mRest := Copy(ALine, Length(TAtlasLeakCaptures.cCountPrefix) + 1, MaxInt);
  mAt := LastDelimiter('=', mRest);
  if (mAt > 1) and TryStrToInt(Copy(mRest, mAt + 1, MaxInt), mCount) then
  begin
    AHistory.Names := AHistory.Names + [Copy(mRest, 1, mAt - 1)];
    AHistory.Counts := AHistory.Counts + [mCount];
  end;
end;

class function TAtlasLeakCaptures.HistoryFromText(const AText: string): TAtlasLeakHistory;
var
  mLine: string;
begin
  Result := Default(TAtlasLeakHistory);
  for mLine in TTextLines.SplitLines(AText) do
  begin
    if StartsStr(cCountPrefix, mLine) then
    begin
      ReadCountLine(Trim(mLine), Result);
    end
    else if StartsStr(cKnownPrefix, mLine) and (Trim(Copy(mLine, Length(cKnownPrefix) + 1, MaxInt)) <> '') then
    begin
      Result.Known := Result.Known + [Trim(Copy(mLine, Length(cKnownPrefix) + 1, MaxInt))];
    end;
  end;
end;

class function TAtlasLeakCaptures.HistoryFileName(const AConfig, APlatform: string): string;
begin
  Result := 'leaks-' + LowerCase(AConfig) + '-' + LowerCase(APlatform) + '.txt';
end;

end.
