unit Atlas.Common.Mcp.ReportTools;

// Laufzeitberichte für KI-Assistenten (MCP-Werkzeuge resolve_address und analyze_report, #74):
// - resolve_address löst Adressen („0045A1B2“, „$0045A1B2“, „Kunden.exe+$5A1B2“) über die Map-Datei in Unit,
//   Routine und Zeile auf, mit Basisadresse des Moduls und Prüfung, ob Map und EXE zusammenpassen,
// - analyze_report wertet einen eingefügten Leckbericht (Atlas.Text.LeakReport) oder Absturzbericht
//   (Atlas.Text.CrashReport) aus, ergänzt Stapelzeilen ohne Debug-Informationen über die Map und nennt die
//   betroffene Stelle mit Datei im Projekt.
// Dateien liest die Shell (Map, EXE, Bericht); hier nur Auswertung und Ausgabe, damit es ohne Dateisystem
// testbar bleibt.

interface

uses
  System.SysUtils,
  Atlas.Common.Diagnostics.RuntimeReport;

type
  /// <summary>Eine Adresse aus resolve_address.</summary>
  TMcpAddress = record
    Text: string;
    /// <summary>Modul bei „Modul+$Offset“; '' bei absoluter Adresse.</summary>
    Module: string;
    Value: UInt64;
    /// <summary>Value ist ein Offset relativ zur Modulbasis.</summary>
    IsOffset: Boolean;
  end;

  TMcpReportTools = class
  public const
    /// <summary>Höchstzahl gezeigter Stapelzeilen bzw. Leckgruppen.</summary>
    cMaxFrames = 40;
    cMaxGroups = 20;
  public
    /// <summary>Adressen aus einem Text, getrennt durch Leerraum, Komma oder Semikolon; EMcpToolError bei
    /// unlesbaren Einträgen oder ohne Adresse.</summary>
    class function ParseAddresses(const AText: string): TArray<TMcpAddress>; static;
    /// <summary>Antwort von resolve_address.</summary>
    class function ResolveAddresses(const AAddresses: TArray<TMcpAddress>; const ASymbols: TReportSymbols;
      const AFileOf: TReportUnitFileFunc): string; static;
    /// <summary>Antwort von analyze_report; EMcpToolError, wenn der Text weder Leck- noch Absturzbericht ist.
    /// </summary>
    class function AnalyzeReport(const AText: string; const ASymbols: TReportSymbols;
      const AFileOf: TReportUnitFileFunc): string; static;
    /// <summary>Zeile zur Map: Pfad und ob sie zur EXE passt; '' ohne Map.</summary>
    class function MapStatus(const ASymbols: TReportSymbols): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.MapFile,
  Atlas.Text.PeImage,
  Atlas.Text.LeakReport,
  Atlas.Text.CrashReport,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TReportToolsText = (NoAddress, BadAddress, NoReport, MapLine, MapMatches, MapUnchecked, MapEntryDiffers,
    MapSizeDiffers, NoMap, AddressLine, NotFound, OtherModule, LineSuffix, CrashTitle, MessageLine, CrashAddress,
    SiteLine, NoSite, StackTitle, MoreFrames, OtherThreads, LeakTitle, LeakStacks, LeakNoStacks, LeakGroup,
    LeakCreated, LeakNoSite, LeakCount, LargeBlocks, MoreGroups);

const
  cTexts: array[TReportToolsText] of TAtlasText = (
    (De: 'Keine Adresse angegeben'; En: 'No address given'),
    (De: '„%s“ ist keine Adresse (Hexzahl wie 0045A1B2 oder Modul+$Offset)';
     En: '"%s" is not an address (hex number like 0045A1B2 or module+$offset)'),
    (De: 'Der Text ist weder ein Leckbericht (FastMM, ReportMemoryLeaksOnShutdown) noch ein Absturzbericht ' +
      '(madExcept, EurekaLog, JclDebug, Meldung einer Exception).';
     En: 'The text is neither a leak report (FastMM, ReportMemoryLeaksOnShutdown) nor a crash report (madExcept, ' +
      'EurekaLog, JclDebug, exception message).'),
    (De: 'Map: %s (%s)'; En: 'Map: %s (%s)'),
    (De: 'passt zur EXE'; En: 'matches the EXE'),
    (De: 'ohne EXE nicht geprüft'; En: 'not checked without EXE'),
    (De: 'GEHÖRT NICHT ZUR EXE: anderer Einsprungpunkt, Zeilen können falsch sein';
     En: 'DOES NOT BELONG TO THE EXE: different entry point, lines may be wrong'),
    (De: 'GEHÖRT NICHT ZUR EXE: andere Länge des Codes, Zeilen können falsch sein';
     En: 'DOES NOT BELONG TO THE EXE: different code size, lines may be wrong'),
    (De: 'Keine Map-Datei: Adressen ohne Debug-Informationen bleiben offen. map, exe oder project angeben ' +
      '(Linker-Option „Map-Datei: Detailliert“).';
     En: 'No map file: addresses without debug information stay open. Pass map, exe or project (linker ' +
      'option "Map file: Detailed").'),
    (De: '%s → %s'; En: '%s → %s'),
    (De: 'nicht in der Map'; En: 'not in the map'),
    (De: 'anderes Modul (%s), Map gehört zu %s'; En: 'other module (%s), map belongs to %s'),
    (De: ', Zeile %d'; En: ', line %d'),
    (De: 'Absturzbericht (%s): %s'; En: 'Crash report (%s): %s'),
    (De: 'Meldung: %s'; En: 'Message: %s'),
    (De: 'Absturzadresse: %s'; En: 'Crash address: %s'),
    (De: 'Betroffene Stelle: %s'; En: 'Affected location: %s'),
    (De: 'Betroffene Stelle: keine Zeile mit eigenem Code im Stapel (Debug-Informationen oder Map fehlen)';
     En: 'Affected location: no line of own code in the stack (debug information or map missing)'),
    (De: 'Aufrufstapel%s:'; En: 'Call stack%s:'),
    (De: '  … %d weitere Zeilen'; En: '  … %d more lines'),
    (De: 'Weitere Threads: %s'; En: 'Other threads: %s'),
    (De: 'Leckbericht: %d Lecks (%d Arten)'; En: 'Leak report: %d leaks (%d kinds)'),
    (De: 'Gruppen gleicher Aufrufstapel, häufigste zuerst:';
     En: 'Groups with the same call stack, most frequent first:'),
    (De: 'Ohne Aufrufstapel (FastMM im FullDebugMode mit Debug-DLL zeigt die Erzeugungsstellen):';
     En: 'Without call stacks (FastMM in FullDebugMode with the debug DLL shows the creation sites):'),
    (De: '%d. %s × %d (%d Bytes)'; En: '%d. %s × %d (%d bytes)'),
    (De: '   erzeugt in %s'; En: '   created in %s'),
    (De: '   Erzeugungsstelle unbekannt (nur RTL und FastMM im Stapel)';
     En: '   creation site unknown (only RTL and FastMM in the stack)'),
    (De: '- %s × %d'; En: '- %s × %d'),
    (De: 'Mittlere und große Blöcke: %s Bytes'; En: 'Medium and large blocks: %s bytes'),
    (De: '… %d weitere Gruppen'; En: '… %d more groups'));

{$SCOPEDENUMS OFF}

function Hex(AValue: UInt64): string;
begin
  Result := IntToHex(Int64(AValue), 8);
end;

{ Adressen }

/// <summary>„Modul+$Offset“ bzw. „Modul+Offset“; False ohne Pluszeichen.</summary>
function TryModuleOffset(const AText: string; var AAddress: TMcpAddress): Boolean;
var
  mPlus: Integer;
begin
  mPlus := LastDelimiter('+', AText);
  Result := (mPlus > 1) and TCrashReports.TryParseHex(Copy(AText, mPlus + 1, MaxInt), AAddress.Value);
  if Result then
  begin
    AAddress.Module := Copy(AText, 1, mPlus - 1);
    AAddress.IsOffset := True;
  end;
end;

class function TMcpReportTools.ParseAddresses(const AText: string): TArray<TMcpAddress>;
var
  mPart: string;
  mAddress: TMcpAddress;
begin
  Result := nil;
  for mPart in AText.Split([' ', ',', ';', #9, #10, #13], TStringSplitOptions.ExcludeEmpty) do
  begin
    mAddress := Default(TMcpAddress);
    mAddress.Text := mPart;
    if not TryModuleOffset(mPart, mAddress) and not TCrashReports.TryParseHex(mPart, mAddress.Value) then
    begin
      raise EMcpToolError.Create(cTexts[TReportToolsText.BadAddress].Fmt([mPart]));
    end;
    Result := Result + [mAddress];
  end;
  if Result = nil then
  begin
    raise EMcpToolError.Create(cTexts[TReportToolsText.NoAddress].Text);
  end;
end;

/// <summary>„Unit.Routine, Zeile 42 (Pfad)“ zu einer aufgelösten Stelle.</summary>
function LocationText(const ARoutine, AUnitName, AFileName: string; ALine: Integer;
  const AFileOf: TReportUnitFileFunc): string;
var
  mPath: string;
begin
  Result := ARoutine;
  if (AUnitName <> '') and not StartsText(AUnitName + '.', ARoutine) then
  begin
    Result := AUnitName + '.' + ARoutine;
  end;
  if ALine > 0 then
  begin
    Result := Result + cTexts[TReportToolsText.LineSuffix].Fmt([ALine]);
  end;
  mPath := '';
  if Assigned(AFileOf) then
  begin
    mPath := AFileOf(AUnitName, AFileName);
  end;
  if mPath <> '' then
  begin
    Result := Result + ' (' + mPath + ')';
  end;
end;

function FrameText(const AFrame: TCrashFrame; const AFileOf: TReportUnitFileFunc): string;
begin
  Result := LocationText(AFrame.Routine, AFrame.UnitName, AFrame.FileName, AFrame.Line, AFileOf);
end;

function MapLocationText(const ALocation: TMapLocation; const AFileOf: TReportUnitFileFunc): string;
begin
  Result := LocationText(ALocation.Routine, ALocation.UnitName, ALocation.FileName, ALocation.Line, AFileOf);
end;

function ResolveOne(const AAddress: TMcpAddress; const ASymbols: TReportSymbols;
  const AFileOf: TReportUnitFileFunc): string;
var
  mBase: UInt64;
  mLocation: TMapLocation;
begin
  if not ASymbols.TryBaseFor(AAddress.Module, mBase) then
  begin
    Exit(cTexts[TReportToolsText.OtherModule].Fmt([AAddress.Module, ASymbols.Module]));
  end;
  if AAddress.IsOffset then
  begin
    mLocation := ASymbols.Map.Resolve(AAddress.Value);
  end
  else
  begin
    mLocation := ASymbols.Map.ResolveAddress(AAddress.Value, mBase);
  end;
  Result := cTexts[TReportToolsText.NotFound].Text;
  if mLocation.Found then
  begin
    Result := MapLocationText(mLocation, AFileOf);
  end;
end;

class function TMcpReportTools.MapStatus(const ASymbols: TReportSymbols): string;
const
  cMatchTexts: array[TMapImageMatch] of TReportToolsText = (TReportToolsText.MapUnchecked,
    TReportToolsText.MapMatches, TReportToolsText.MapEntryDiffers, TReportToolsText.MapSizeDiffers);
begin
  Result := '';
  if ASymbols.Map <> nil then
  begin
    Result := cTexts[TReportToolsText.MapLine].Fmt([ASymbols.MapName, cTexts[cMatchTexts[ASymbols.Match]].Text]);
  end;
end;

class function TMcpReportTools.ResolveAddresses(const AAddresses: TArray<TMcpAddress>; const ASymbols: TReportSymbols;
  const AFileOf: TReportUnitFileFunc): string;
var
  mAddress: TMcpAddress;
  mBuilder: TStringBuilder;
begin
  if ASymbols.Map = nil then
  begin
    raise EMcpToolError.Create(cTexts[TReportToolsText.NoMap].Text);
  end;
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.AppendLine(MapStatus(ASymbols));
    for mAddress in AAddresses do
    begin
      mBuilder.AppendLine(cTexts[TReportToolsText.AddressLine].Fmt([mAddress.Text,
        ResolveOne(mAddress, ASymbols, AFileOf)]));
    end;
    Result := mBuilder.ToString.TrimRight;
  finally
    mBuilder.Free;
  end;
end;

{ Absturzbericht }

function StackLine(AIndex: Integer; const AFrame: TCrashFrame; const AFileOf: TReportUnitFileFunc): string;
begin
  Result := Format('  %d. %s %s', [AIndex + 1, Hex(AFrame.Address), AFrame.Module]).TrimRight;
  if AFrame.HasLocation then
  begin
    Result := Result + ' ' + FrameText(AFrame, AFileOf);
  end;
end;

procedure AppendStack(ABuilder: TStringBuilder; const AThreadName: string; const AFrames: TArray<TCrashFrame>;
  const AFileOf: TReportUnitFileFunc);
var
  mIndex: Integer;
  mName: string;
begin
  mName := '';
  if AThreadName <> '' then
  begin
    mName := ' (' + AThreadName + ')';
  end;
  ABuilder.AppendLine(cTexts[TReportToolsText.StackTitle].Fmt([mName]));
  for mIndex := 0 to High(AFrames) do
  begin
    if mIndex >= TMcpReportTools.cMaxFrames then
    begin
      ABuilder.AppendLine(cTexts[TReportToolsText.MoreFrames].Fmt([Length(AFrames) - mIndex]));
      Break;
    end;
    ABuilder.AppendLine(StackLine(mIndex, AFrames[mIndex], AFileOf));
  end;
end;

function CrashedThreadName(const AReport: TCrashReport): string;
var
  mThread: TCrashThread;
begin
  Result := '';
  for mThread in AReport.Threads do
  begin
    if mThread.Crashed then
    begin
      Exit(mThread.Name);
    end;
  end;
end;

function OtherThreadNames(const AReport: TCrashReport): string;
var
  mThread: TCrashThread;
begin
  Result := '';
  for mThread in AReport.Threads do
  begin
    if not mThread.Crashed then
    begin
      Result := Result + IfThen(Result <> '', ', ') + mThread.Name;
    end;
  end;
end;

/// <summary>Absturzadresse mit Modul und, falls auflösbar, Stelle.</summary>
function CrashAddressText(const AReport: TCrashReport; const AFrames: TArray<TCrashFrame>): string;
begin
  Result := Hex(AReport.Address);
  if AReport.Module <> '' then
  begin
    Result := Result + ' (' + AReport.Module + ')';
  end;
  if (Length(AFrames) > 0) and (AFrames[0].Address = AReport.Address) and AFrames[0].HasLocation then
  begin
    Result := Result + ' → ' + FrameText(AFrames[0], nil);
  end;
end;

procedure AppendCrashHead(ABuilder: TStringBuilder; const AReport: TCrashReport; const AFrames: TArray<TCrashFrame>);
var
  mTitle: string;
begin
  mTitle := AReport.ExceptionClass;
  if mTitle = '' then
  begin
    mTitle := AReport.ExceptionMessage;
  end;
  ABuilder.AppendLine(cTexts[TReportToolsText.CrashTitle].Fmt([TRuntimeReports.SourceOf(AReport.Kind), mTitle]));
  if (AReport.ExceptionMessage <> '') and (AReport.ExceptionMessage <> mTitle) then
  begin
    ABuilder.AppendLine(cTexts[TReportToolsText.MessageLine].Fmt([AReport.ExceptionMessage]));
  end;
  if AReport.Address <> 0 then
  begin
    ABuilder.AppendLine(cTexts[TReportToolsText.CrashAddress].Fmt([CrashAddressText(AReport, AFrames)]));
  end;
end;

function CrashText(const AReport: TCrashReport; const ASymbols: TReportSymbols; const AFileOf: TReportUnitFileFunc): string;
var
  mFrames: TArray<TCrashFrame>;
  mSite: Integer;
  mBuilder: TStringBuilder;
begin
  mFrames := TRuntimeReports.CrashFramesOf(AReport);
  TRuntimeReports.Symbolize(mFrames, AReport, ASymbols);
  mSite := TRuntimeReports.SiteIndex(mFrames, AFileOf);
  mBuilder := TStringBuilder.Create;
  try
    AppendCrashHead(mBuilder, AReport, mFrames);
    if mSite >= 0 then
    begin
      mBuilder.AppendLine(cTexts[TReportToolsText.SiteLine].Fmt([FrameText(mFrames[mSite], AFileOf)]));
    end
    else
    begin
      mBuilder.AppendLine(cTexts[TReportToolsText.NoSite].Text);
    end;
    if ASymbols.Map <> nil then
    begin
      mBuilder.AppendLine(TMcpReportTools.MapStatus(ASymbols));
    end
    else
    begin
      mBuilder.AppendLine(cTexts[TReportToolsText.NoMap].Text);
    end;
    AppendStack(mBuilder, CrashedThreadName(AReport), mFrames, AFileOf);
    if OtherThreadNames(AReport) <> '' then
    begin
      mBuilder.AppendLine(cTexts[TReportToolsText.OtherThreads].Fmt([OtherThreadNames(AReport)]));
    end;
    Result := mBuilder.ToString.TrimRight;
  finally
    mBuilder.Free;
  end;
end;

{ Leckbericht }

function LeakTotal(const AReport: TLeakReport): Integer;
var
  mCount: TLeakCount;
begin
  Result := Length(AReport.LargeSizes);
  for mCount in AReport.Counts do
  begin
    Inc(Result, mCount.Count);
  end;
end;

function LargeSizesText(const ASizes: TArray<Int64>): string;
var
  mSize: Int64;
begin
  Result := '';
  for mSize in ASizes do
  begin
    Result := Result + IfThen(Result <> '', ', ') + IntToStr(mSize);
  end;
end;

procedure AppendGroup(ABuilder: TStringBuilder; AIndex: Integer; const AGroup: TLeakGroup;
  const AFileOf: TReportUnitFileFunc);
var
  mFrame: TLeakFrame;
begin
  ABuilder.AppendLine(cTexts[TReportToolsText.LeakGroup].Fmt([AIndex + 1, AGroup.Name, AGroup.Count,
    AGroup.TotalSize]));
  if AGroup.Site < 0 then
  begin
    ABuilder.AppendLine(cTexts[TReportToolsText.LeakNoSite].Text);
    Exit;
  end;
  mFrame := AGroup.Frames[AGroup.Site];
  ABuilder.AppendLine(cTexts[TReportToolsText.LeakCreated].Fmt([LocationText(mFrame.Routine, mFrame.UnitName,
    mFrame.FileName, mFrame.Line, AFileOf)]));
end;

procedure AppendGroups(ABuilder: TStringBuilder; const AReport: TLeakReport; const AFileOf: TReportUnitFileFunc);
var
  mGroups: TArray<TLeakGroup>;
  mIndex: Integer;
begin
  ABuilder.AppendLine(cTexts[TReportToolsText.LeakStacks].Text);
  mGroups := AReport.Groups;
  for mIndex := 0 to High(mGroups) do
  begin
    if mIndex >= TMcpReportTools.cMaxGroups then
    begin
      ABuilder.AppendLine(cTexts[TReportToolsText.MoreGroups].Fmt([Length(mGroups) - mIndex]));
      Break;
    end;
    AppendGroup(ABuilder, mIndex, mGroups[mIndex], AFileOf);
  end;
end;

procedure AppendCounts(ABuilder: TStringBuilder; const AReport: TLeakReport);
var
  mCount: TLeakCount;
begin
  ABuilder.AppendLine(cTexts[TReportToolsText.LeakNoStacks].Text);
  for mCount in AReport.Counts do
  begin
    ABuilder.AppendLine(cTexts[TReportToolsText.LeakCount].Fmt([mCount.Name, mCount.Count]));
  end;
end;

function LeakText(const AReport: TLeakReport; const AFileOf: TReportUnitFileFunc): string;
var
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.AppendLine(cTexts[TReportToolsText.LeakTitle].Fmt([LeakTotal(AReport), Length(AReport.Counts)]));
    if AReport.HasStacks then
    begin
      AppendGroups(mBuilder, AReport, AFileOf);
    end
    else
    begin
      AppendCounts(mBuilder, AReport);
    end;
    if AReport.LargeSizes <> nil then
    begin
      mBuilder.AppendLine(cTexts[TReportToolsText.LargeBlocks].Fmt([LargeSizesText(AReport.LargeSizes)]));
    end;
    Result := mBuilder.ToString.TrimRight;
  finally
    mBuilder.Free;
  end;
end;

class function TMcpReportTools.AnalyzeReport(const AText: string; const ASymbols: TReportSymbols;
  const AFileOf: TReportUnitFileFunc): string;
var
  mLeaks: TLeakReport;
  mCrash: TCrashReport;
begin
  mLeaks := TLeakReports.Parse(AText);
  if not mLeaks.IsEmpty then
  begin
    Exit(LeakText(mLeaks, AFileOf));
  end;
  mCrash := TCrashReports.Parse(AText);
  if mCrash.IsEmpty then
  begin
    raise EMcpToolError.Create(cTexts[TReportToolsText.NoReport].Text);
  end;
  Result := CrashText(mCrash, ASymbols, AFileOf);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.ReportTools', cTexts);

end.
