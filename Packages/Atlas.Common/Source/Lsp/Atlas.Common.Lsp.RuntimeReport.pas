unit Atlas.Common.Lsp.RuntimeReport;

// Befehle atlas.server.runtimeReport [uri, {text, map?, exe?, base?}] und atlas.server.runtimeReport.clear [uri?]
// (#74): Ein Leckbericht (FastMM, ReportMemoryLeaksOnShutdown) oder Absturzbericht (madExcept, EurekaLog,
// JclDebug, Meldung einer Exception) wird aufgelöst (Atlas.Common.Diagnostics.RuntimeReport) und als Diagnosen an
// die Stellen im Projekt gehängt: je Leckgruppe eine Warnung an der Erzeugungsstelle, beim Absturz eine Warnung an
// der Absturzstelle und Hinweise an den übrigen eigenen Zeilen des Absturz-Threads. Quelle ist das Werkzeug
// (FastMM, madExcept, …). Warnung statt Fehler, damit ein Bericht keinen Build sperrt. Ein neuer Bericht ersetzt
// den alten, clear entfernt ihn. Die Meldungen hält ein eigener TCompilerResults; die Diagnosen lesen ihn wie die
// Compilermeldungen.
//
// map und exe sind Pfade; ohne beide sucht die Komposition die Map neben der EXE des Projekts hinter uri.
// base (hex) ist die Basis, mit der das Modul geladen war (Packages); ohne gilt die Vorzugsbasis der EXE.
//
// Antwort:
//   { kind: "leaks" | "crash" | "none", source, title, mapStatus, map, diagnostics,
//     crash?: {exceptionClass, message, address, module},
//     groups?: [{name, kind, count, size, site, frames}],      bei leaks, nach count absteigend
//     threads?: [{name, crashed, site, frames}] }              bei crash, Thread der Exception zuerst
//   frame = {address, module, unit, routine, line, uri?, file?}
// mapStatus: none, missing, unchecked, matches, entryPointDiffers, codeSizeDiffers. kind einer Gruppe: instance,
// string, unknown. address hex mit $ oder ''; line ab 1, 0 ohne; uri und file nur für Dateien im Projekt; site ist
// der Index in frames, -1 ohne.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.Results,
  Atlas.Common.Diagnostics.RuntimeReport;

type
  /// <summary>Dateien zum Bericht; die Komposition kennt Projekt und Arbeitsbereich.</summary>
  IRuntimeReportFiles = interface
    ['{8B2F6C41-3E7D-4A95-B1C8-5D0E9F27A6C3}']
    /// <summary>Map aus AMapName, sonst neben AExeName, sonst neben der EXE des Projekts hinter AUri. Der Aufrufer
    /// gibt ASymbols.Map frei.</summary>
    procedure LoadSymbols(const AUri, AMapName, AExeName: string; ABase: UInt64; out ASymbols: TReportSymbols);
    /// <summary>Datei im Projekt hinter AUri zu Unit bzw. Dateiname; '' außerhalb.</summary>
    function UnitFileOf(const AUri: string): TReportUnitFileFunc;
  end;

  /// <summary>Meldet geänderte Dateien zum Neuveröffentlichen der Diagnosen.</summary>
  TRuntimeReportPublish = reference to procedure(const AFileNames: TArray<string>);

  TLspRuntimeReport = class
  public const
    cCommand = 'atlas.server.runtimeReport';
    cClearCommand = 'atlas.server.runtimeReport.clear';
    /// <summary>Höchstens so viele Gruppen bzw. Threads und Stapelzeilen je Stapel in der Antwort.</summary>
    cMaxStacks = 200;
    cMaxFrames = 100;
  private
    FFiles: IRuntimeReportFiles;
    FResults: TCompilerResults;
    FPublish: TRuntimeReportPublish;
    function Store(const AMessages: TArray<TCompilerMessage>): Integer;
  public
    /// <summary>AResults gehört dem Aufrufer und hält die Meldungen des letzten Berichts.</summary>
    constructor Create(const AFiles: IRuntimeReportFiles; AResults: TCompilerResults;
      const APublish: TRuntimeReportPublish);
    /// <summary>Diagnosen zu den Stellen im Projekt.</summary>
    class function MessagesOf(const AReport: TRuntimeReport): TArray<TCompilerMessage>; static;
    /// <summary>Überschrift: „EAccessViolation: Meldung“ bzw. „12 Lecks (3 Arten)“; '' ohne Bericht.</summary>
    class function TitleOf(const AReport: TRuntimeReport): string; static;
    /// <summary>Antwort ohne Dateien. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AReport: TRuntimeReport; const ASymbols: TReportSymbols;
      ADiagnostics: Integer): TJSONObject; static;
    /// <summary>atlas.server.runtimeReport; EJsonRpcError ohne uri, ohne text oder bei unlesbarer base.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>atlas.server.runtimeReport.clear: {cleared: Zahl der Dateien}.</summary>
    function Clear(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  Atlas.Text.Json,
  Atlas.Text.LeakReport,
  Atlas.Text.CrashReport,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TLspRuntimeReportText = (NeedsUri, NeedsText, BadBase, LeakSite, CrashSite, CrashFrame, LeakTitle);

const
  cTexts: array[TLspRuntimeReportText] of TAtlasText = (
    (De: '%s braucht die URI einer Datei oder des Projekts'; En: '%s needs the URI of a file or the project'),
    (De: '%s braucht den Text des Berichts (text)'; En: '%s needs the text of the report (text)'),
    (De: '"base" ist keine Hexzahl: %s'; En: '"base" is not a hex number: %s'),
    (De: 'Leck: %s × %d (%d Bytes) wird hier erzeugt'; En: 'Leak: %s × %d (%d bytes) is created here'),
    (De: 'Absturz hier: %s'; En: 'Crash here: %s'),
    (De: 'Im Aufrufstapel des Absturzes: %s'; En: 'In the call stack of the crash: %s'),
    (De: '%d Lecks (%d Arten)'; En: '%d leaks (%d kinds)'));

  cMapStates: array[TReportMapState] of string = ('none', 'missing', 'unchecked', 'matches', 'entryPointDiffers',
    'codeSizeDiffers');
  cReportKinds: array[TRuntimeReportKind] of string = ('none', 'leaks', 'crash');
  cLeakKinds: array[TLeakKind] of string = ('instance', 'string', 'unknown');

{$SCOPEDENUMS OFF}

constructor TLspRuntimeReport.Create(const AFiles: IRuntimeReportFiles; AResults: TCompilerResults;
  const APublish: TRuntimeReportPublish);
begin
  inherited Create;
  FFiles := AFiles;
  FResults := AResults;
  FPublish := APublish;
end;

{ Diagnosen }

function CrashText(const AReport: TRuntimeReport): string;
begin
  Result := AReport.ExceptionClass;
  if (Result <> '') and (AReport.ExceptionMessage <> '') then
  begin
    Result := Result + ': ' + AReport.ExceptionMessage;
  end
  else if Result = '' then
  begin
    Result := AReport.ExceptionMessage;
  end;
end;

function MessageAt(const AFrame: TRuntimeFrame; ASeverity: TCompilerSeverity; const ASource, AText: string):
  TCompilerMessage;
begin
  Result := Default(TCompilerMessage);
  Result.FileName := AFrame.ProjectFile;
  Result.Line := AFrame.Line - 1;
  Result.Column := -1;
  Result.Severity := ASeverity;
  Result.Source := ASource;
  Result.Text := AText;
end;

function IsProjectLine(const AFrame: TRuntimeFrame): Boolean;
begin
  Result := (AFrame.ProjectFile <> '') and (AFrame.Line > 0);
end;

procedure AddCrashMessages(var AMessages: TArray<TCompilerMessage>; const AReport: TRuntimeReport;
  const AStack: TRuntimeStack);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AStack.Frames) do
  begin
    if not IsProjectLine(AStack.Frames[mIndex]) then
    begin
      Continue;
    end;
    if mIndex = AStack.Site then
    begin
      AMessages := AMessages + [MessageAt(AStack.Frames[mIndex], TCompilerSeverity.Warning, AReport.Source,
        cTexts[TLspRuntimeReportText.CrashSite].Fmt([CrashText(AReport)]))];
    end
    else
    begin
      AMessages := AMessages + [MessageAt(AStack.Frames[mIndex], TCompilerSeverity.Hint, AReport.Source,
        cTexts[TLspRuntimeReportText.CrashFrame].Fmt([CrashText(AReport)]))];
    end;
  end;
end;

class function TLspRuntimeReport.MessagesOf(const AReport: TRuntimeReport): TArray<TCompilerMessage>;
var
  mStack: TRuntimeStack;
begin
  Result := nil;
  for mStack in AReport.Stacks do
  begin
    if (AReport.Kind = TRuntimeReportKind.Crash) and mStack.Crashed then
    begin
      AddCrashMessages(Result, AReport, mStack);
    end
    else if (AReport.Kind = TRuntimeReportKind.Leaks) and mStack.HasProjectSite then
    begin
      Result := Result + [MessageAt(mStack.Frames[mStack.Site], TCompilerSeverity.Warning, AReport.Source,
        cTexts[TLspRuntimeReportText.LeakSite].Fmt([mStack.Name, mStack.Count, mStack.Size]))];
    end;
  end;
end;

{ Antwort }

class function TLspRuntimeReport.TitleOf(const AReport: TRuntimeReport): string;
var
  mStack: TRuntimeStack;
  mTotal: Integer;
begin
  Result := '';
  if AReport.Kind = TRuntimeReportKind.Crash then
  begin
    Result := CrashText(AReport);
  end
  else if AReport.Kind = TRuntimeReportKind.Leaks then
  begin
    mTotal := 0;
    for mStack in AReport.Stacks do
    begin
      Inc(mTotal, mStack.Count);
    end;
    Result := cTexts[TLspRuntimeReportText.LeakTitle].Fmt([mTotal, Length(AReport.Stacks)]);
  end;
end;

function AddressText(AAddress: UInt64): string;
begin
  Result := '';
  if AAddress <> 0 then
  begin
    Result := '$' + IntToHex(Int64(AAddress), 8);
  end;
end;

function FrameToJson(const AFrame: TRuntimeFrame): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('address', AddressText(AFrame.Address));
  Result.AddPair('module', AFrame.Module);
  Result.AddPair('unit', AFrame.UnitName);
  Result.AddPair('routine', AFrame.Routine);
  Result.AddPair('line', TJSONNumber.Create(AFrame.Line));
  if AFrame.ProjectFile <> '' then
  begin
    Result.AddPair('uri', TDocumentUris.FromPath(AFrame.ProjectFile));
    Result.AddPair('file', AFrame.ProjectFile);
  end;
end;

function FramesToJson(const AFrames: TArray<TRuntimeFrame>): TJSONArray;
var
  mIndex: Integer;
begin
  Result := TJSONArray.Create;
  for mIndex := 0 to High(AFrames) do
  begin
    if mIndex >= TLspRuntimeReport.cMaxFrames then
    begin
      Break;
    end;
    Result.AddElement(FrameToJson(AFrames[mIndex]));
  end;
end;

function StackToJson(const AStack: TRuntimeStack; AKind: TRuntimeReportKind): TJSONObject;
var
  mSite: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AStack.Name);
  if AKind = TRuntimeReportKind.Leaks then
  begin
    Result.AddPair('kind', cLeakKinds[AStack.LeakKind]);
    Result.AddPair('count', TJSONNumber.Create(AStack.Count));
    Result.AddPair('size', TJSONNumber.Create(AStack.Size));
  end
  else
  begin
    Result.AddPair('crashed', TJSONBool.Create(AStack.Crashed));
  end;
  // Nur Zeilen bis cMaxFrames stehen in frames.
  mSite := AStack.Site;
  if mSite >= TLspRuntimeReport.cMaxFrames then
  begin
    mSite := -1;
  end;
  Result.AddPair('site', TJSONNumber.Create(mSite));
  Result.AddPair('frames', FramesToJson(AStack.Frames));
end;

function CrashToJson(const AReport: TRuntimeReport): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('exceptionClass', AReport.ExceptionClass);
  Result.AddPair('message', AReport.ExceptionMessage);
  Result.AddPair('address', AddressText(AReport.Address));
  Result.AddPair('module', AReport.Module);
end;

function StacksToJson(const AReport: TRuntimeReport): TJSONArray;
var
  mIndex: Integer;
begin
  Result := TJSONArray.Create;
  for mIndex := 0 to High(AReport.Stacks) do
  begin
    if mIndex >= TLspRuntimeReport.cMaxStacks then
    begin
      Break;
    end;
    Result.AddElement(StackToJson(AReport.Stacks[mIndex], AReport.Kind));
  end;
end;

class function TLspRuntimeReport.ToJson(const AReport: TRuntimeReport; const ASymbols: TReportSymbols;
  ADiagnostics: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', cReportKinds[AReport.Kind]);
  Result.AddPair('source', AReport.Source);
  Result.AddPair('title', TitleOf(AReport));
  Result.AddPair('mapStatus', cMapStates[ASymbols.MapState]);
  Result.AddPair('map', ASymbols.MapName);
  Result.AddPair('diagnostics', TJSONNumber.Create(ADiagnostics));
  if AReport.Kind = TRuntimeReportKind.Crash then
  begin
    Result.AddPair('crash', CrashToJson(AReport));
    Result.AddPair('threads', StacksToJson(AReport));
  end
  else if AReport.Kind = TRuntimeReportKind.Leaks then
  begin
    Result.AddPair('groups', StacksToJson(AReport));
  end;
end;

{ Befehle }

function UriOf(const AArguments: TJSONArray; const ACommand: string): string;
begin
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONString) or
    (AArguments.Items[0].Value = '') then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspRuntimeReportText.NeedsUri].Fmt([ACommand]));
  end;
  Result := AArguments.Items[0].Value;
end;

function BaseOf(AOptions: TJSONObject): UInt64;
var
  mText: string;
begin
  Result := 0;
  mText := Trim(TJsonRead.Text(AOptions, 'base'));
  if (mText <> '') and not TCrashReports.TryParseHex(mText, Result) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspRuntimeReportText.BadBase].Fmt([mText]));
  end;
end;

function TLspRuntimeReport.Store(const AMessages: TArray<TCompilerMessage>): Integer;
var
  mFiles: TArray<string>;
begin
  mFiles := FResults.Replace(AMessages);
  Result := Length(mFiles);
  if (mFiles <> nil) and Assigned(FPublish) then
  begin
    FPublish(mFiles);
  end;
end;

function TLspRuntimeReport.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mText: string;
  mOptions: TJSONObject;
  mSymbols: TReportSymbols;
  mReport: TRuntimeReport;
  mMessages: TArray<TCompilerMessage>;
begin
  mUri := UriOf(AArguments, cCommand);
  mOptions := nil;
  if (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
  begin
    mOptions := TJSONObject(AArguments.Items[1]);
  end;
  mText := TJsonRead.Text(mOptions, 'text');
  if Trim(mText) = '' then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspRuntimeReportText.NeedsText].Fmt([cCommand]));
  end;
  FFiles.LoadSymbols(mUri, TJsonRead.Text(mOptions, 'map'), TJsonRead.Text(mOptions, 'exe'), BaseOf(mOptions),
    mSymbols);
  try
    mReport := TRuntimeReports.Build(mText, mSymbols, FFiles.UnitFileOf(mUri));
    mMessages := MessagesOf(mReport);
    Store(mMessages);
    Result := ToJson(mReport, mSymbols, Length(mMessages));
  finally
    mSymbols.Map.Free;
  end;
end;

function TLspRuntimeReport.Clear(const AArguments: TJSONArray): TJSONValue;
var
  mResult: TJSONObject;
begin
  // Der Bericht gilt für alle Projekte; die URI braucht es nicht.
  mResult := TJSONObject.Create;
  mResult.AddPair('cleared', TJSONNumber.Create(Store(nil)));
  Result := mResult;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.RuntimeReport', cTexts);

end.
