unit Shell.Linter.Output;

// Internals-Rolle Shell: Ausgabe des Linter-Modus (#95). Das Ergebnis geht nach --output oder auf stdout,
// Meldungen zum Ablauf auf stderr; das Zeitprofil (#1356) in seine Datei oder auf stderr.

interface

uses
  Atlas.Common.Diagnostics.CheckProfile,
  Shell.CommandLine;

type
  TLinterOutput = class
  public
    /// <summary>Eine Zeile auf stderr.</summary>
    class procedure Error(const AText: string); static;
    /// <summary>Ergebnis nach --output (UTF-8 ohne BOM), sonst auf stdout.</summary>
    class procedure Write(const AOptions: TCommandLineOptions; const AText: string); static;
    /// <summary>Hinweise der Befehlszeile (AOptions.Warnings) auf stderr.</summary>
    class procedure Warnings(const AOptions: TCommandLineOptions); static;
    /// <summary>Schreibt AText als UTF-8 ohne BOM nach AFileName.</summary>
    class procedure SaveUtf8(const AFileName, AText: string); static;
    /// <summary>--timings (#1356): Zeitprofil in die Datei (Markdown, mit .json als JSON) oder auf stderr.</summary>
    class procedure Timings(const AOptions: TCommandLineOptions; const ATimings: TCheckTimings); static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Shell.Platform;

procedure WriteText(const AStream: TStream; const AText: string);
var
  mBytes: TBytes;
begin
  mBytes := TEncoding.UTF8.GetBytes(AText);
  if Length(mBytes) > 0 then
  begin
    AStream.WriteBuffer(mBytes[0], Length(mBytes));
  end;
end;

class procedure TLinterOutput.Error(const AText: string);
var
  mStream: TStream;
begin
  mStream := TStdStreams.CreateError;
  try
    WriteText(mStream, AText + sLineBreak);
  finally
    mStream.Free;
  end;
end;

class procedure TLinterOutput.SaveUtf8(const AFileName, AText: string);
var
  mEncoding: TEncoding;
begin
  mEncoding := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(AFileName, AText, mEncoding);
  finally
    mEncoding.Free;
  end;
end;

class procedure TLinterOutput.Write(const AOptions: TCommandLineOptions; const AText: string);
var
  mStream: TStream;
begin
  if AOptions.OutputFile <> '' then
  begin
    SaveUtf8(AOptions.OutputFile, AText);
    Exit;
  end;
  mStream := TStdStreams.CreateOutput;
  try
    WriteText(mStream, AText);
  finally
    mStream.Free;
  end;
end;

class procedure TLinterOutput.Warnings(const AOptions: TCommandLineOptions);
var
  mWarning: string;
begin
  for mWarning in AOptions.Warnings do
  begin
    Error(mWarning);
  end;
end;

/// <summary>Zeitprofil als Text: JSON bei einer .json-Datei, sonst Markdown.</summary>
function TimingsText(const AOptions: TCommandLineOptions; const ATimings: TCheckTimings): string;
var
  mJson: TJSONObject;
begin
  if not TCheckTimings.IsJsonFile(AOptions.TimingsFile) then
  begin
    Exit(ATimings.ToMarkdown);
  end;
  mJson := ATimings.ToJson;
  try
    Result := mJson.Format(2);
  finally
    mJson.Free;
  end;
end;

class procedure TLinterOutput.Timings(const AOptions: TCommandLineOptions; const ATimings: TCheckTimings);
var
  mText: string;
begin
  mText := TimingsText(AOptions, ATimings);
  if AOptions.TimingsFile = '' then
  begin
    Error(mText);
    Exit;
  end;
  ForceDirectories(ExtractFileDir(TPath.GetFullPath(AOptions.TimingsFile)));
  SaveUtf8(AOptions.TimingsFile, mText);
  Error(Format('Zeitprofil geschrieben: %s', [AOptions.TimingsFile]));
end;

end.
