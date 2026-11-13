unit Shell.Linter.Mutation;

// Internals-Rolle Shell: --mutate (#1460). Erzeugt die Mutanten einer Unit
// ohne zu bauen (Atlas.Common.Mutation.Generator) und gibt sie als Markdown
// (Standard), JSON oder Patch (--format text, json, diff) auf stdout bzw. in
// --output aus. Dieselben Mutanten liefert das MCP-Werkzeug get_mutants.
//   --routine <Name>        nur diese Routine ("TFoo.Bar" oder "Bar")
//   --operators a,b         nur diese Operatoren (Kennungen wie boundary, not)
//   --check <Projekt.dproj> Symbole des Projekts für die aktiven Zweige der
//                           bedingten Kompilierung; ohne gelten die
//                           Vordefinitionen (Win32, Delphi 13)
// Exit-Code 0; 3 bei Aufruffehlern (Datei fehlt, unbekanntes Format oder
// unbekannter Operator).

interface

uses
  Atlas.Common.Mutation.Contract,
  Shell.CommandLine;

type
  TLinterMutation = class
  public
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
    /// <summary>Auswahl aus --routine und --operators; False mit Fehlertext bei unbekannten Operatoren.</summary>
    class function OptionsOf(const AOptions: TCommandLineOptions; out AMutation: TMutationOptions;
      out AError: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Output,
  Atlas.Common.Mutation.Report,
  Shell.Linter.Output,
  Shell.Linter.Settings,
  Shell.Linter.Files,
  Shell.Linter.Reports,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TLinterMutationText = (Formats, UnknownOperators, NoSource, Unreadable);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TLinterMutationText] of TAtlasText = (
    (De: '--mutate gibt es mit --format text (Standard), json oder diff';
    En: '--mutate exists with --format text (default), json or diff'),
    (De: 'Unbekannte Operatoren in --operators: %s (bekannt: %s)';
    En: 'Unknown operators in --operators: %s (known: %s)'),
    (De: '--mutate erwartet eine .pas-, .dpr- oder .dpk-Datei: %s';
    En: '--mutate expects a .pas, .dpr or .dpk file: %s'),
    (De: '%s ist nicht lesbar'; En: '%s is not readable'));

/// <summary>Alle Kennungen, mit Komma getrennt.</summary>
function KnownOperators: string;
var
  mOperator: TMutationOperator;
begin
  Result := '';
  for mOperator := Low(TMutationOperator) to High(TMutationOperator) do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + TMutation.OperatorId(mOperator);
  end;
end;

class function TLinterMutation.OptionsOf(const AOptions: TCommandLineOptions; out AMutation: TMutationOptions;
  out AError: string): Boolean;
var
  mUnknown: TArray<string>;
begin
  AError := '';
  AMutation := TMutationOptions.Default;
  AMutation.Routine := Trim(AOptions.MutateRoutine);
  if Trim(AOptions.MutateOperators) <> '' then
  begin
    AMutation.Operators := TMutation.ParseOperators(AOptions.MutateOperators.Split([',', ';']), mUnknown);
    if Length(mUnknown) > 0 then
    begin
      AError := cTexts[TLinterMutationText.UnknownOperators].Fmt([string.Join(', ', mUnknown), KnownOperators]);
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Symbole für AFileName aus dem Projekt in --check (nur .dproj); sonst leer.</summary>
function DefinesOf(const AOptions: TCommandLineOptions; const AFileName: string): TArray<string>;
var
  mTarget: TLinterTarget;
  mSettings: TServerSettings;
  mRoot: string;
  mSources: TCheckSourceFunc;
begin
  Result := nil;
  if not SameText(ExtractFileExt(AOptions.CheckTarget), '.dproj') or
    not TLinterTarget.Resolve(AOptions.CheckTarget, mTarget) then
  begin
    Exit;
  end;
  mSettings := TLinterSettings.Load(mTarget.ConfigRoot);
  TLinterFiles.Collect(mTarget.Target, mSettings, mRoot, mSources);
  Result := mSources(AFileName).Defines;
end;

/// <summary>Mutanten von ATarget ausgeben; Exit-Code.</summary>
function Answer(const AOptions: TCommandLineOptions; const ATarget: TLinterTarget;
  AFormat: TMutationOutputFormat): Integer;
var
  mSettings: TServerSettings;
  mMutation: TMutationOptions;
  mFileName, mText, mError: string;
begin
  if not TLinterMutation.OptionsOf(AOptions, mMutation, mError) then
  begin
    TLinterOutput.Error(mError);
    Exit(TFindingsOutput.cExitFailure);
  end;
  mSettings := TLinterSettings.Load(ATarget.ConfigRoot);
  TFileEncodingDefaults.SetFolder(ATarget.ConfigRoot, mSettings.DefaultEncoding);
  mFileName := ExpandFileName(ATarget.Target);
  if not TLinterFiles.ReadText(mFileName, mText) then
  begin
    TLinterOutput.Error(cTexts[TLinterMutationText.Unreadable].Fmt([ATarget.Target]));
    Exit(TFindingsOutput.cExitFailure);
  end;
  mMutation.Defines := DefinesOf(AOptions, mFileName);
  TLinterOutput.Write(AOptions, TMutationReport.Render(TLinterReports.SlashPath(ExtractFileName(mFileName)), mText,
    mMutation, AFormat));
  Result := TFindingsOutput.cExitClean;
end;

class function TLinterMutation.Run(const AOptions: TCommandLineOptions): Integer;
var
  mFormat: TMutationOutputFormat;
  mTarget: TLinterTarget;
begin
  TLinterOutput.Warnings(AOptions);
  if not TMutationReport.TryParseFormat(AOptions.FormatText, mFormat) then
  begin
    TLinterOutput.Error(cTexts[TLinterMutationText.Formats].Text);
    Exit(TFindingsOutput.cExitFailure);
  end;
  if not TLinterTarget.Resolve(AOptions.MutateFile, mTarget) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  if mTarget.IsFolder or not TLinterFiles.IsSourceFile(mTarget.Target) then
  begin
    TLinterOutput.Error(cTexts[TLinterMutationText.NoSource].Fmt([AOptions.MutateFile]));
    Exit(TFindingsOutput.cExitFailure);
  end;
  try
    Result := Answer(AOptions, mTarget, mFormat);
  except
    on E: Exception do
    begin
      TLinterOutput.Error(E.Message);
      Result := TFindingsOutput.cExitFailure;
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Mutation', cTexts);

end.
