unit Atlas.Core.Diagnostics.ServerPackage;

// Diagnosepaket des Fensters „Atlas-Server“ (#1356), ohne VCL und Open Tools
// API: eine ZIP-Datei mit dem Fehlerbericht von #108 (fehlerbericht.md) und
// den Dateien, die der Server mit atlas.server.diagnosticPackage liefert
// (server/status.json, server/protokoll.txt mit dem Protokoll der Sitzung,
// server/trace.txt nur mit --trace). Anonymisiert wird wie im Fehlerbericht
// (diagnostics.bugReport.anonymize): Den Bericht anonymisiert
// TAtlasBugReport, die Serverdateien der Server selbst; Zugangsdaten
// entfernt er immer. Hier werden nur Namen geprüft (nur unter server/, ohne
// „..“, Laufwerk oder „\“), die Vorschau gebaut und der Name der ZIP-Datei
// bestimmt; geschrieben wird mit TAtlasDiagnosticPackage.WriteZip.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Package;

type
  TAtlasServerDiagnostics = record
  public const
    Command = 'atlas.server.diagnosticPackage';
    ReportName = 'fehlerbericht.md';
    ServerFolder = 'server/';
    ZipPrefix = 'Atlas-Server-Diagnose-';
    /// <summary>Trace der letzten Minuten (#1356).</summary>
    TraceMinutes = 5;
    /// <summary>So viele Zeichen je Datei zeigt die Vorschau; die ZIP enthält alles.</summary>
    PreviewChars = 65536;
  public
    /// <summary>Argumente für Command: [{"anonymize": …, "traceMinutes": 5}].</summary>
    class function ServerArguments(AAnonymize: Boolean): string; static;
    /// <summary>Dateien aus der Antwort {"files":[{"name","content"}]}; Namen außerhalb von server/ oder mit
    /// „..“, Laufwerk oder „\“ fallen weg. Leer ohne Antwort.</summary>
    class function ServerFiles(const AAnswer: TJSONValue): TAtlasPackageFiles; static;
    /// <summary>Gültiger Name einer Serverdatei?</summary>
    class function IsServerName(const AName: string): Boolean; static;
    /// <summary>Bericht zuerst, dann die Dateien des Servers.</summary>
    class function Build(const AReport: string; const AServerFiles: TAtlasPackageFiles): TAtlasPackageFiles; static;
    /// <summary>Vorschau: je Datei „== Name (Größe) ==“ und Inhalt, gekürzt auf PreviewChars mit ACutNote.</summary>
    class function Preview(const AFiles: TAtlasPackageFiles; const ACutNote: string): string; static;
    /// <summary>Atlas-Server-Diagnose-2026-10-29-1430.zip.</summary>
    class function ZipName(ANow: TDateTime): string; static;
  end;

implementation

class function TAtlasServerDiagnostics.ServerArguments(AAnonymize: Boolean): string;
var
  mArguments: TJSONArray;
  mOptions: TJSONObject;
begin
  mArguments := TJSONArray.Create;
  try
    mOptions := TJSONObject.Create;
    mOptions.AddPair('anonymize', TJSONBool.Create(AAnonymize));
    mOptions.AddPair('traceMinutes', TJSONNumber.Create(TraceMinutes));
    mArguments.AddElement(mOptions);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

class function TAtlasServerDiagnostics.IsServerName(const AName: string): Boolean;
begin
  Result := AName.StartsWith(ServerFolder) and (Length(AName) > Length(ServerFolder)) and
    (Pos('..', AName) = 0) and (Pos('\', AName) = 0) and (Pos(':', AName) = 0) and not AName.EndsWith('/');
end;

class function TAtlasServerDiagnostics.ServerFiles(const AAnswer: TJSONValue): TAtlasPackageFiles;
var
  mFiles: TJSONValue;
  mItem: TJSONValue;
  mName, mContent: TJSONValue;
begin
  Result := nil;
  if not (AAnswer is TJSONObject) then
    Exit;
  mFiles := TJSONObject(AAnswer).GetValue('files');
  if not (mFiles is TJSONArray) then
    Exit;
  for mItem in TJSONArray(mFiles) do
  begin
    if not (mItem is TJSONObject) then
      Continue;
    mName := TJSONObject(mItem).GetValue('name');
    mContent := TJSONObject(mItem).GetValue('content');
    // TJSONNumber leitet von TJSONString ab; Zahlen sind weder Name noch Inhalt.
    if not (mName is TJSONString) or not (mContent is TJSONString) or (mName is TJSONNumber) or
      (mContent is TJSONNumber) then
      Continue;
    if not IsServerName(mName.Value) then
      Continue;
    Result := Result + [TAtlasPackageFile.Create(mName.Value, TAtlasPackagePart.Logs, mContent.Value)];
  end;
end;

class function TAtlasServerDiagnostics.Build(const AReport: string;
  const AServerFiles: TAtlasPackageFiles): TAtlasPackageFiles;
begin
  SetLength(Result, 1);
  Result[0] := TAtlasPackageFile.Create(ReportName, TAtlasPackagePart.Versions, AReport);
  Result := Result + AServerFiles;
end;

class function TAtlasServerDiagnostics.Preview(const AFiles: TAtlasPackageFiles; const ACutNote: string): string;
var
  mBuilder: TStringBuilder;
  mFile: TAtlasPackageFile;
  mText: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mFile in AFiles do
    begin
      if mBuilder.Length > 0 then
        mBuilder.Append(sLineBreak);
      mBuilder.Append('== ').Append(mFile.Name).Append(' (').Append(mFile.Size).Append(' Bytes) ==');
      mBuilder.Append(sLineBreak);
      mText := mFile.Text;
      if Length(mText) > PreviewChars then
        mBuilder.Append(Copy(mText, 1, PreviewChars)).Append(sLineBreak).Append(ACutNote)
      else
        mBuilder.Append(mText);
      mBuilder.Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TAtlasServerDiagnostics.ZipName(ANow: TDateTime): string;
begin
  Result := ZipPrefix + FormatDateTime('yyyy"-"mm"-"dd"-"hhnn', ANow) + '.zip';
end;

end.
