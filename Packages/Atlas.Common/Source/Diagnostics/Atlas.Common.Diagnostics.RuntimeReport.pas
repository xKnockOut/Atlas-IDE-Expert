unit Atlas.Common.Diagnostics.RuntimeReport;

// Laufzeitberichte eines Programms (#74): Leckbericht (Atlas.Text.LeakReport) oder Absturzbericht
// (Atlas.Text.CrashReport) als eine Folge von Stapeln mit Stelle im Projekt. Stapelzeilen ohne
// Debug-Informationen ergänzt die Map-Datei des Moduls (TReportSymbols), die Datei im Projekt liefert der
// Aufrufer (TReportUnitFileFunc). Gemeinsame Grundlage der MCP-Werkzeuge (Atlas.Common.Mcp.ReportTools) und des
// Befehls atlas.server.runtimeReport (Atlas.Common.Lsp.RuntimeReport).

interface

uses
  System.SysUtils,
  Atlas.Text.MapFile,
  Atlas.Text.PeImage,
  Atlas.Text.LeakReport,
  Atlas.Text.CrashReport;

type
  /// <summary>Datei im Projekt zu Unit bzw. Dateiname aus einem Bericht; '' unbekannt.</summary>
  TReportUnitFileFunc = reference to function(const AUnitName, AFileName: string): string;

{$SCOPEDENUMS ON}
  /// <summary>Stand der Map: keine angegeben, angegeben und fehlt, sonst Ergebnis des Vergleichs mit der EXE.
  /// </summary>
  TReportMapState = (None, Missing, Unchecked, Matches, EntryPointDiffers, CodeSizeDiffers);

  TRuntimeReportKind = (None, Leaks, Crash);
{$SCOPEDENUMS OFF}

  /// <summary>Map eines Moduls für die Auflösung; Map = nil ohne Map-Datei. Der Besitzer gibt Map frei.</summary>
  TReportSymbols = record
    Map: TMapFile;
    /// <summary>Pfad der Map-Datei; auch gesetzt, wenn sie fehlt.</summary>
    MapName: string;
    /// <summary>Dateiname des Moduls (EXE, DLL, BPL) ohne Ordner; '' unbekannt.</summary>
    Module: string;
    /// <summary>Basisadresse für absolute Adressen; 0 = Vorzugsbasis aus der Map.</summary>
    Base: UInt64;
    /// <summary>Ergebnis des Vergleichs mit der EXE; Unknown ohne EXE.</summary>
    Match: TMapImageMatch;
    /// <summary>Basis, mit der Adressen von AModule aufgelöst werden; False für fremde Module und ohne Map.
    /// </summary>
    function TryBaseFor(const AModule: string; out ABase: UInt64): Boolean;
    function MapState: TReportMapState;
  end;

  /// <summary>Eine Stapelzeile, aufgelöst; ProjectFile '' außerhalb des Projekts.</summary>
  TRuntimeFrame = record
    Address: UInt64;
    Module: string;
    UnitName: string;
    Routine: string;
    /// <summary>Datei, wie der Bericht bzw. die Map sie nennt.</summary>
    FileName: string;
    /// <summary>Zeile ab 1; 0 ohne.</summary>
    Line: Integer;
    ProjectFile: string;
  end;

  /// <summary>Gruppe gleicher Lecks bzw. Thread eines Absturzes.</summary>
  TRuntimeStack = record
    /// <summary>Klasse bzw. Name des Lecks; Name des Threads.</summary>
    Name: string;
    LeakKind: TLeakKind;
    Count: Integer;
    Size: Int64;
    /// <summary>Thread der Exception.</summary>
    Crashed: Boolean;
    /// <summary>Index der Erzeugungs- bzw. Absturzstelle in Frames; -1 ohne.</summary>
    Site: Integer;
    Frames: TArray<TRuntimeFrame>;
    function HasProjectSite: Boolean;
  end;

  TRuntimeReport = record
    Kind: TRuntimeReportKind;
    /// <summary>FastMM, madExcept, EurekaLog, JclDebug oder Exception; '' ohne Bericht.</summary>
    Source: string;
    ExceptionClass: string;
    ExceptionMessage: string;
    Address: UInt64;
    Module: string;
    /// <summary>Leckgruppen nach Anzahl absteigend; Threads mit dem Thread der Exception zuerst.</summary>
    Stacks: TArray<TRuntimeStack>;
  end;

  TRuntimeReports = class
  public const
    cLeakSource = 'FastMM';
  public
    /// <summary>Name des Werkzeugs zu einem Absturzbericht: madExcept, EurekaLog, JclDebug, Exception.</summary>
    class function SourceOf(AKind: TCrashReportKind): string; static;
    /// <summary>Map aus AMapName ('' = neben AExeName) und Kopf der EXE; ASymbols.Map = nil, wenn keine Map da
    /// ist (MapState sagt, ob sie fehlt). ABase 0 = Vorzugsbasis der EXE. Der Aufrufer gibt ASymbols.Map frei.
    /// </summary>
    class procedure LoadSymbols(const AMapName, AExeName: string; ABase: UInt64; out ASymbols: TReportSymbols);
      static;
    /// <summary>Stapelzeilen ohne Ort über die Map ergänzen (nur Zeilen des Moduls der Map).</summary>
    class procedure Symbolize(var AFrames: TArray<TCrashFrame>; const AReport: TCrashReport;
      const ASymbols: TReportSymbols); static;
    /// <summary>Erste Zeile mit Zeilennummer, deren Datei im Projekt liegt; sonst die erste außerhalb der
    /// Bibliotheken; -1 ohne.</summary>
    class function SiteIndex(const AFrames: TArray<TCrashFrame>; const AFileOf: TReportUnitFileFunc): Integer;
      static;
    /// <summary>Stapel des Absturz-Threads; nur eine Meldung ohne Stapel ergibt eine Zeile mit der Absturzadresse.
    /// </summary>
    class function CrashFramesOf(const AReport: TCrashReport): TArray<TCrashFrame>; static;
    /// <summary>Leck- oder Absturzbericht aus AText, aufgelöst; Kind None, wenn keiner darin steht.</summary>
    class function Build(const AText: string; const ASymbols: TReportSymbols;
      const AFileOf: TReportUnitFileFunc): TRuntimeReport; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils;

const
  // Der PE-Kopf samt Abschnittstabelle steht in den ersten Kilobytes der Datei.
  cImageHeadBytes = 64 * 1024;

  cKindNames: array[TCrashReportKind] of string = ('', 'madExcept', 'EurekaLog', 'JclDebug', 'Exception');

{ TReportSymbols }

function TReportSymbols.TryBaseFor(const AModule: string; out ABase: UInt64): Boolean;
begin
  ABase := Base;
  if (ABase = 0) and (Map <> nil) then
  begin
    ABase := Map.ImageBase;
  end;
  Result := (Map <> nil) and ((AModule = '') or (Module = '') or
    SameText(ExtractFileName(AModule), ExtractFileName(Module)));
end;

function TReportSymbols.MapState: TReportMapState;
const
  cStates: array[TMapImageMatch] of TReportMapState = (TReportMapState.Unchecked, TReportMapState.Matches,
    TReportMapState.EntryPointDiffers, TReportMapState.CodeSizeDiffers);
begin
  if Map <> nil then
  begin
    Result := cStates[Match];
  end
  else if MapName <> '' then
  begin
    Result := TReportMapState.Missing;
  end
  else
  begin
    Result := TReportMapState.None;
  end;
end;

{ TRuntimeStack }

function TRuntimeStack.HasProjectSite: Boolean;
begin
  Result := (Site >= 0) and (Frames[Site].ProjectFile <> '') and (Frames[Site].Line > 0);
end;

{ Symbole }

/// <summary>Erste Bytes einer Datei; nil, wenn sie fehlt oder nicht lesbar ist.</summary>
function ReadHead(const AFileName: string): TBytes;
var
  mStream: TFileStream;
begin
  Result := nil;
  if (AFileName = '') or not FileExists(AFileName) then
  begin
    Exit;
  end;
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, mStream.Size);
      if mStream.Size > cImageHeadBytes then
      begin
        SetLength(Result, cImageHeadBytes);
      end;
      if Length(Result) > 0 then
      begin
        mStream.ReadBuffer(Result[0], Length(Result));
      end;
    finally
      mStream.Free;
    end;
  except
    on EStreamError do
    begin
      Result := nil;
    end;
  end;
end;

class procedure TRuntimeReports.LoadSymbols(const AMapName, AExeName: string; ABase: UInt64;
  out ASymbols: TReportSymbols);
var
  mImage: TPeImage;
begin
  ASymbols := Default(TReportSymbols);
  ASymbols.Base := ABase;
  ASymbols.MapName := AMapName;
  if (ASymbols.MapName = '') and (AExeName <> '') then
  begin
    ASymbols.MapName := ChangeFileExt(AExeName, '.map');
  end;
  if (ASymbols.MapName = '') or not FileExists(ASymbols.MapName) then
  begin
    Exit;
  end;
  ASymbols.Map := TMapFile.Create(TFile.ReadAllText(ASymbols.MapName, TEncoding.UTF8));
  mImage := TPeImage.Read(ReadHead(AExeName));
  ASymbols.Match := TMapImageCheck.Compare(ASymbols.Map, mImage);
  if mImage.Valid then
  begin
    ASymbols.Module := ExtractFileName(AExeName);
  end;
  if (ASymbols.Base = 0) and mImage.Valid then
  begin
    ASymbols.Base := mImage.ImageBase;
  end;
end;

class procedure TRuntimeReports.Symbolize(var AFrames: TArray<TCrashFrame>; const AReport: TCrashReport;
  const ASymbols: TReportSymbols);
var
  mIndex: Integer;
  mBase, mLoaded: UInt64;
  mLocation: TMapLocation;
begin
  for mIndex := 0 to High(AFrames) do
  begin
    if (AFrames[mIndex].Line > 0) or not ASymbols.TryBaseFor(AFrames[mIndex].Module, mBase) then
    begin
      Continue;
    end;
    // Die Modulliste des Berichts kennt die Basis, mit der das Modul tatsächlich geladen war.
    if (ASymbols.Base = 0) and AReport.TryBaseOf(AFrames[mIndex].Module, mLoaded) then
    begin
      mBase := mLoaded;
    end;
    mLocation := ASymbols.Map.ResolveAddress(AFrames[mIndex].Address, mBase);
    if mLocation.Found then
    begin
      AFrames[mIndex].UnitName := mLocation.UnitName;
      AFrames[mIndex].Routine := mLocation.Routine;
      AFrames[mIndex].FileName := mLocation.FileName;
      AFrames[mIndex].Line := mLocation.Line;
    end;
  end;
end;

class function TRuntimeReports.SiteIndex(const AFrames: TArray<TCrashFrame>;
  const AFileOf: TReportUnitFileFunc): Integer;
var
  mIndex: Integer;
begin
  if Assigned(AFileOf) then
  begin
    for mIndex := 0 to High(AFrames) do
    begin
      if (AFrames[mIndex].Line > 0) and (AFileOf(AFrames[mIndex].UnitName, AFrames[mIndex].FileName) <> '') then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := TCrashReports.SiteOf(AFrames);
end;

class function TRuntimeReports.CrashFramesOf(const AReport: TCrashReport): TArray<TCrashFrame>;
var
  mFrame: TCrashFrame;
begin
  Result := Copy(AReport.CrashFrames);
  if (Result = nil) and (AReport.Address <> 0) then
  begin
    mFrame := Default(TCrashFrame);
    mFrame.Address := AReport.Address;
    mFrame.Module := AReport.Module;
    Result := Result + [mFrame];
  end;
end;

class function TRuntimeReports.SourceOf(AKind: TCrashReportKind): string;
begin
  Result := cKindNames[AKind];
end;

{ Aufbau }

function ProjectFileOf(const AFileOf: TReportUnitFileFunc; const AUnitName, AFileName: string): string;
begin
  Result := '';
  if Assigned(AFileOf) and ((AUnitName <> '') or (AFileName <> '')) then
  begin
    Result := AFileOf(AUnitName, AFileName);
  end;
end;

function LeakStackOf(const AGroup: TLeakGroup; const AFileOf: TReportUnitFileFunc): TRuntimeStack;
var
  mIndex: Integer;
  mFrame: TRuntimeFrame;
begin
  Result := Default(TRuntimeStack);
  Result.Name := AGroup.Name;
  Result.LeakKind := AGroup.Kind;
  Result.Count := AGroup.Count;
  Result.Size := AGroup.TotalSize;
  Result.Site := AGroup.Site;
  SetLength(Result.Frames, Length(AGroup.Frames));
  for mIndex := 0 to High(AGroup.Frames) do
  begin
    mFrame := Default(TRuntimeFrame);
    mFrame.Address := AGroup.Frames[mIndex].Address;
    mFrame.UnitName := AGroup.Frames[mIndex].UnitName;
    mFrame.Routine := AGroup.Frames[mIndex].Routine;
    mFrame.FileName := AGroup.Frames[mIndex].FileName;
    mFrame.Line := AGroup.Frames[mIndex].Line;
    mFrame.ProjectFile := ProjectFileOf(AFileOf, mFrame.UnitName, mFrame.FileName);
    Result.Frames[mIndex] := mFrame;
  end;
  // Wie bei Abstürzen: Die erste eigene Zeile mit Nummer ist die Erzeugungsstelle.
  for mIndex := 0 to High(Result.Frames) do
  begin
    if (Result.Frames[mIndex].Line > 0) and (Result.Frames[mIndex].ProjectFile <> '') then
    begin
      Result.Site := mIndex;
      Break;
    end;
  end;
end;

function LeaksOf(const AReport: TLeakReport; const AFileOf: TReportUnitFileFunc): TRuntimeReport;
var
  mGroup: TLeakGroup;
  mCount: TLeakCount;
  mStack: TRuntimeStack;
begin
  Result := Default(TRuntimeReport);
  Result.Kind := TRuntimeReportKind.Leaks;
  Result.Source := TRuntimeReports.cLeakSource;
  if AReport.HasStacks then
  begin
    for mGroup in AReport.Groups do
    begin
      Result.Stacks := Result.Stacks + [LeakStackOf(mGroup, AFileOf)];
    end;
    Exit;
  end;
  // Ohne FullDebugMode nur Name und Anzahl.
  for mCount in AReport.Counts do
  begin
    mStack := Default(TRuntimeStack);
    mStack.Name := mCount.Name;
    mStack.LeakKind := mCount.Kind;
    mStack.Count := mCount.Count;
    // Die Meldung nennt nur Größenklassen, keine genaue Summe.
    mStack.Size := 0;
    mStack.Site := -1;
    Result.Stacks := Result.Stacks + [mStack];
  end;
end;

function CrashStackOf(const AName: string; ACrashed: Boolean; const AFrames: TArray<TCrashFrame>;
  const AReport: TCrashReport; const ASymbols: TReportSymbols; const AFileOf: TReportUnitFileFunc): TRuntimeStack;
var
  mFrames: TArray<TCrashFrame>;
  mIndex: Integer;
  mFrame: TRuntimeFrame;
begin
  mFrames := Copy(AFrames);
  TRuntimeReports.Symbolize(mFrames, AReport, ASymbols);
  Result := Default(TRuntimeStack);
  Result.Name := AName;
  Result.Crashed := ACrashed;
  Result.Site := TRuntimeReports.SiteIndex(mFrames, AFileOf);
  SetLength(Result.Frames, Length(mFrames));
  for mIndex := 0 to High(mFrames) do
  begin
    mFrame := Default(TRuntimeFrame);
    mFrame.Address := mFrames[mIndex].Address;
    mFrame.Module := mFrames[mIndex].Module;
    mFrame.UnitName := mFrames[mIndex].UnitName;
    mFrame.Routine := mFrames[mIndex].Routine;
    mFrame.FileName := mFrames[mIndex].FileName;
    mFrame.Line := mFrames[mIndex].Line;
    if mFrame.Line > 0 then
    begin
      mFrame.ProjectFile := ProjectFileOf(AFileOf, mFrame.UnitName, mFrame.FileName);
    end;
    Result.Frames[mIndex] := mFrame;
  end;
end;

function CrashOf(const AReport: TCrashReport; const ASymbols: TReportSymbols;
  const AFileOf: TReportUnitFileFunc): TRuntimeReport;
var
  mThread: TCrashThread;
  mCrashedName: string;
begin
  Result := Default(TRuntimeReport);
  Result.Kind := TRuntimeReportKind.Crash;
  Result.Source := TRuntimeReports.SourceOf(AReport.Kind);
  Result.ExceptionClass := AReport.ExceptionClass;
  Result.ExceptionMessage := AReport.ExceptionMessage;
  Result.Address := AReport.Address;
  Result.Module := AReport.Module;
  mCrashedName := '';
  for mThread in AReport.Threads do
  begin
    if mThread.Crashed then
    begin
      mCrashedName := mThread.Name;
    end;
  end;
  Result.Stacks := nil;
  Result.Stacks := Result.Stacks + [CrashStackOf(mCrashedName, True, TRuntimeReports.CrashFramesOf(AReport),
    AReport, ASymbols, AFileOf)];
  for mThread in AReport.Threads do
  begin
    if not mThread.Crashed then
    begin
      Result.Stacks := Result.Stacks + [CrashStackOf(mThread.Name, False, mThread.Frames, AReport, ASymbols,
        AFileOf)];
    end;
  end;
end;

class function TRuntimeReports.Build(const AText: string; const ASymbols: TReportSymbols;
  const AFileOf: TReportUnitFileFunc): TRuntimeReport;
var
  mLeaks: TLeakReport;
  mCrash: TCrashReport;
begin
  mLeaks := TLeakReports.Parse(AText);
  if not mLeaks.IsEmpty then
  begin
    Exit(LeaksOf(mLeaks, AFileOf));
  end;
  mCrash := TCrashReports.Parse(AText);
  if mCrash.IsEmpty then
  begin
    Exit(Default(TRuntimeReport));
  end;
  Result := CrashOf(mCrash, ASymbols, AFileOf);
end;

end.
