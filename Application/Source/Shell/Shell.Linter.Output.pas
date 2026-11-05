unit Shell.Linter.Output;

// Internals-Rolle Shell: Ausgabe des Linter-Modus (#95). Das Ergebnis geht nach --output oder auf stdout,
// Meldungen zum Ablauf auf stderr; das Zeitprofil (#1356) in seine Datei oder auf stderr, anonym mit name#N
// statt Unit-Namen (#1478), mit --log-names im Klartext; die erste Zeile bzw. "anonymized" sagt, welches.

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
    /// <summary>Text des Zeitprofils: JSON bei einer .json-Datei, sonst Markdown; ohne --log-names anonym.</summary>
    class function TimingsText(const AOptions: TCommandLineOptions; const ATimings: TCheckTimings): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atlas.Text.LogMarks,
  Atlas.Common.Diagnostics.Anonymizer,
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

/// <summary>ATimings mit name#N statt der Unit-Namen.</summary>
function AnonymousTimings(const ATimings: TCheckTimings): TCheckTimings;
var
  mAnonymizer: ILogAnonymizer;
begin
  mAnonymizer := TLogAnonymizer.Create(nil);
  Result := ATimings;
  Result.Profile := ATimings.Profile.Anonymized(
    function(const AName: string): string
    begin
      Result := mAnonymizer.Anonymize(TLogMarks.Name(AName));
    end);
end;

class function TLinterOutput.TimingsText(const AOptions: TCommandLineOptions; const ATimings: TCheckTimings): string;
var
  mJson: TJSONObject;
  mTimings: TCheckTimings;
  mNote: string;
begin
  mTimings := ATimings;
  mNote := '_Unit-Namen im Klartext (--log-names)._';
  if not AOptions.LogNames then
  begin
    mTimings := AnonymousTimings(ATimings);
    mNote := '_Unit-Namen anonymisiert (name#N); im Klartext mit --log-names._';
  end;
  if not TCheckTimings.IsJsonFile(AOptions.TimingsFile) then
  begin
    Exit(mNote + sLineBreak + sLineBreak + mTimings.ToMarkdown);
  end;
  mJson := mTimings.ToJson;
  try
    mJson.AddPair('anonymized', TJSONBool.Create(not AOptions.LogNames));
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
