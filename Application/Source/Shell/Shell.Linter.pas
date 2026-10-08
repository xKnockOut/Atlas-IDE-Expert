unit Shell.Linter;

// Host-Rolle Shell: Linter-Modus ohne Editor (#95).
//
//   BetterDelphiLSP.exe --check Projekt.dproj --format sarif --output ergebnis.sarif
//
// Ziel ist eine .dproj (Hauptdatei und Units des Projekts), ein Ordner (alle
// .pas, .dpr, .dpk darunter) oder eine einzelne Datei. delphi-lsp.json im
// Ordner des Ziels gilt wie im Editor. Das Ergebnis geht auf stdout oder in
// die Datei aus --output, Meldungen zum Ablauf auf stderr.
// Mit --suppression-stats erscheint statt der Treffer die Auswertung der
// Unterdrückungskommentare je Regel; Exit-Code dann 0.
// Exit-Code: 0 ohne Warnungen und Fehler, 1 Warnungen, 2 Fehler,
// 3 Aufruf- oder Lesefehler.

interface

uses
  Shell.CommandLine;

type
  TLinterShell = class
  public
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Configuration.Parser,
  BDLsp.Common.Documents.FileEncoding,
  BDLsp.Common.Projects.Contract,
  BDLsp.Common.Projects.DprojReader,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Checker,
  BDLsp.Common.Rules.Filter,
  BDLsp.Common.Rules.Output,
  BDLsp.Common.Rules.Builtin,
  BDLsp.Common.Rules.SuppressionStats,
  BDLsp.Windows.Console.StdStreams;

procedure WriteText(const AStream: TStream; const AText: string);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  if Length(Bytes) > 0 then
    AStream.WriteBuffer(Bytes[0], Length(Bytes));
end;

procedure WriteError(const AText: string);
var
  Stream: TStream;
begin
  Stream := TStdStreams.CreateError;
  try
    WriteText(Stream, AText + sLineBreak);
  finally
    Stream.Free;
  end;
end;

function IsSourceFile(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk');
end;

function LoadSettings(const ARoot: string): TServerSettings;
var
  FileName: string;
  FileFormat: TFileFormat;
  Issues: TArray<TConfigurationIssue>;
  Issue: TConfigurationIssue;
begin
  FileName := TPath.Combine(ARoot, ConfigurationFileName);
  if not TFile.Exists(FileName) then
    Exit(TServerSettings.Default);
  Result := TConfigurationParser.Parse(TFileEncoding.LoadFromFile(FileName, FileFormat), Issues);
  for Issue in Issues do
    WriteError(Format('%s(%d,%d): %s', [FileName, Issue.Range.StartPos.Line + 1,
      Issue.Range.StartPos.Character + 1, Issue.Message]));
end;

function CollectFiles(const ATarget: string; const ASettings: TServerSettings; out ARoot: string): TArray<string>;
var
  Options: TDprojOptions;
  Project: TProjectInfo;
  ProjectUnit: TProjectUnit;
  Files: TList<string>;
  FileName: string;
begin
  Files := TList<string>.Create;
  try
    if TDirectory.Exists(ATarget) then
    begin
      ARoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ATarget));
      for FileName in TDirectory.GetFiles(ARoot, '*.*', TSearchOption.soAllDirectories) do
        if IsSourceFile(FileName) then
          Files.Add(FileName);
    end
    else if SameText(ExtractFileExt(ATarget), '.dproj') then
    begin
      ARoot := ExtractFileDir(TPath.GetFullPath(ATarget));
      Options := Default(TDprojOptions);
      Options.Config := ASettings.Config;
      Options.Platform := ASettings.Platform;
      Options.FileExists :=
        function(APath: string): Boolean
        begin
          Result := TFile.Exists(APath) or TDirectory.Exists(APath);
        end;
      Project := TDprojReader.Load(TPath.GetFullPath(ATarget), Options);
      if (Project.MainSource <> '') and TFile.Exists(Project.MainSource) then
        Files.Add(Project.MainSource);
      for ProjectUnit in Project.Units do
        if IsSourceFile(ProjectUnit.FileName) and TFile.Exists(ProjectUnit.FileName) and
          not Files.Contains(ProjectUnit.FileName) then
          Files.Add(ProjectUnit.FileName);
    end
    else
    begin
      ARoot := ExtractFileDir(TPath.GetFullPath(ATarget));
      Files.Add(TPath.GetFullPath(ATarget));
    end;
    Result := Files.ToArray;
  finally
    Files.Free;
  end;
end;

class function TLinterShell.Run(const AOptions: TCommandLineOptions): Integer;
var
  Root, ConfigRoot, FileName, RelativePath, Text: string;
  Settings: TServerSettings;
  Filter: TFindingFilter;
  Rules: TArray<IRule>;
  Rule: IRule;
  Descriptors: TArray<TRuleDescriptor>;
  Files: TArray<TCheckedFile>;
  Checked: TCheckedFile;
  FileFormat: TFileFormat;
  Encoding: TEncoding;
  Output: string;
  Stream: TStream;
  Warning: string;
  Stats: TSuppressionStats;
  Findings: TArray<TRuleFinding>;
begin
  for Warning in AOptions.Warnings do
    WriteError(Warning);
  if not (TFile.Exists(AOptions.CheckTarget) or TDirectory.Exists(AOptions.CheckTarget)) then
  begin
    WriteError(Format('Ziel "%s" nicht gefunden', [AOptions.CheckTarget]));
    Exit(TFindingsOutput.ExitFailure);
  end;
  try
    if TDirectory.Exists(AOptions.CheckTarget) then
      ConfigRoot := TPath.GetFullPath(AOptions.CheckTarget)
    else
      ConfigRoot := ExtractFileDir(TPath.GetFullPath(AOptions.CheckTarget));
    Settings := LoadSettings(ConfigRoot);

    Filter := Default(TFindingFilter);
    Filter.Rules := AOptions.RuleFilter;
    Filter.Units := AOptions.UnitFilter;
    Filter.MinSeverity := AOptions.MinSeverity;

    Rules := BuiltinRules;
    Descriptors := [TFileChecker.SyntaxDescriptor];
    for Rule in Rules do
      Descriptors := Descriptors + [Rule.Descriptor];

    Files := nil;
    Stats := TSuppressionStats.Create;
    try
      for FileName in CollectFiles(AOptions.CheckTarget, Settings, Root) do
      begin
        RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(Root), FileName);
        if not Filter.AcceptsFile(RelativePath) then
          Continue;
        try
          Text := TFileEncoding.LoadFromFile(FileName, FileFormat);
        except
          on E: Exception do
          begin
            WriteError(Format('%s: %s', [FileName, E.Message]));
            Continue;
          end;
        end;
        Findings := TFileChecker.CheckText(Rules, Settings, RelativePath, Text);
        if AOptions.SuppressionStats then
          Stats.Add(Text, Findings);
        Checked.Path := RelativePath;
        Checked.Findings := Filter.Apply(Findings);
        Files := Files + [Checked];
      end;

      if AOptions.SuppressionStats then
        Output := Stats.Render(AOptions.CheckFormat)
      else
        Output := TFindingsOutput.Render(Files, AOptions.CheckFormat, Descriptors);
    finally
      Stats.Free;
    end;
    if AOptions.OutputFile <> '' then
    begin
      Encoding := TUTF8Encoding.Create(False);
      try
        TFile.WriteAllText(AOptions.OutputFile, Output, Encoding);
      finally
        Encoding.Free;
      end;
    end
    else
    begin
      Stream := TStdStreams.CreateOutput;
      try
        WriteText(Stream, Output);
      finally
        Stream.Free;
      end;
    end;
    if AOptions.SuppressionStats then
      Result := TFindingsOutput.ExitClean
    else
      Result := TFindingsOutput.ExitCode(Files);
  except
    on E: Exception do
    begin
      WriteError(Format('%s: %s', [E.ClassName, E.Message]));
      Result := TFindingsOutput.ExitFailure;
    end;
  end;
end;

end.
