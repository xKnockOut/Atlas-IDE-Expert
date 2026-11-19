unit Shell.Linter.Instructions;

// Internals-Rolle Shell: --write-instructions und --check-instructions (#2615), Anweisungsdateien für KI-Assistenten
// ohne Editor. Ordner aus --check (Standard: aktueller Ordner), atlas.json darin oder darüber wie bei --check. Je
// Datei eine Zeile auf stderr. Exit-Code: --check-instructions 1, wenn ein Abschnitt fehlt oder veraltet ist;
// --write-instructions 3, wenn eine Datei nicht geschrieben werden konnte; sonst 0.

interface

uses
  Shell.CommandLine;

type
  TLinterInstructions = class
  public
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Output,
  Atlas.Common.Rules.Instructions,
  Atlas.Common.Lsp.Instructions,
  Atlas.Common.Localization.Texts,
  Shell.Linter.Output,
  Shell.Linter.Settings,
  Shell.Composition.Instructions;

{$SCOPEDENUMS ON}

type
  TLinterInstructionsText = (Current, Stale, Missing, Written, Failed, NoFiles);

const
  cTexts: array[TLinterInstructionsText] of TAtlasText = (
    (De: '%s: Anweisungen aktuell'; En: '%s: instructions up to date'),
    (De: '%s: Anweisungen veraltet'; En: '%s: instructions out of date'),
    (De: '%s: Abschnitt fehlt'; En: '%s: section missing'),
    (De: '%s: Anweisungen geschrieben'; En: '%s: instructions written'),
    (De: '%s: nicht geschrieben (%s)'; En: '%s: not written (%s)'),
    (De: 'Keine Anweisungsdatei in assistants.instructions.file';
     En: 'No instruction file in assistants.instructions.file'));

{$SCOPEDENUMS OFF}

const
  cStateTexts: array[TInstructionsState] of TLinterInstructionsText = (TLinterInstructionsText.Current,
    TLinterInstructionsText.Stale, TLinterInstructionsText.Missing);

/// <summary>Zeile zu einer Datei auf stderr; False, wenn Schreiben scheiterte.</summary>
function Report(const AFile: TInstructionsFile): Boolean;
begin
  Result := AFile.Error = '';
  if not Result then
  begin
    TLinterOutput.Error(cTexts[TLinterInstructionsText.Failed].Fmt([AFile.FileName, AFile.Error]));
  end
  else if AFile.Written then
  begin
    TLinterOutput.Error(cTexts[TLinterInstructionsText.Written].Fmt([AFile.FileName]));
  end
  else
  begin
    TLinterOutput.Error(cTexts[cStateTexts[AFile.State]].Fmt([AFile.FileName]));
  end;
end;

{ TLinterInstructions }

class function TLinterInstructions.Run(const AOptions: TCommandLineOptions): Integer;
var
  mTarget: TLinterTarget;
  mSettings: TServerSettings;
  mFiles: TArray<TInstructionsFile>;
  mFile: TInstructionsFile;
  mRoot: string;
begin
  if not TLinterTarget.ResolveOrCurrent(AOptions.CheckTarget, mTarget) then
  begin
    Exit(TFindingsOutput.cExitFailure);
  end;
  mSettings := TLinterSettings.Load(mTarget.ConfigRoot);
  if mSettings.AssistantsInstructionFiles = nil then
  begin
    TLinterOutput.Error(cTexts[TLinterInstructionsText.NoFiles].Text);
    Exit(TFindingsOutput.cExitFailure);
  end;
  // Pfade relativ zum Ordner der atlas.json wie im Server, ohne Datei zum Ordner des Ziels.
  mRoot := ExtractFileDir(TLinterSettings.ConfigFileOf(mTarget.ConfigRoot));
  // --check-instructions geht vor: Wer beides angibt, will nur wissen, ob es stimmt.
  mFiles := TShellInstructions.Run(mRoot, mSettings,
    AOptions.WriteInstructions and not AOptions.CheckInstructions);
  Result := TFindingsOutput.cExitClean;
  for mFile in mFiles do
  begin
    if not Report(mFile) then
    begin
      Result := TFindingsOutput.cExitFailure;
    end;
  end;
  if (Result = TFindingsOutput.cExitClean) and (TLspInstructions.StaleCount(mFiles) > 0) then
  begin
    Result := TFindingsOutput.cExitFindings;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Linter.Instructions', cTexts);

end.
