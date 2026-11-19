unit Shell.VersionControl.TestSupport;

// Gemeinsame Hilfen der Tests mit echtem git bzw. svn (Shell.Hotspots.Tests, Shell.SymbolHistory.Tests): Befehl
// ausführen und temporären Ordner samt schreibgeschützter Dateien wieder entfernen.

interface

uses
  Atlas.Core.VersionControl.Contract;

/// <summary>Führt AExecutable mit AArguments in AWorkingDir aus und liefert die Ausgabe ohne Leerraum am Rand;
/// Exception bei Fehler oder Exit-Code ungleich 0.</summary>
function Exec(const ARunner: IAtlasVcsRunner; const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string): string;
/// <summary>Löscht AFolder samt Inhalt; Fehler beim Löschen werden übergangen.</summary>
procedure RemoveFolder(const AFolder: string);

implementation

uses
  System.SysUtils,
  System.IOUtils;

function Exec(const ARunner: IAtlasVcsRunner; const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string): string;
var
  mAnswer: TAtlasVcsRunResult;
begin
  mAnswer := ARunner.Run(AExecutable, AArguments, AWorkingDir, 60000);
  if (mAnswer.Outcome <> TAtlasVcsOutcome.Ok) or (mAnswer.ExitCode <> 0) then
  begin
    raise Exception.CreateFmt('%s %s: Exit-Code %d', [ExtractFileName(AExecutable), string.Join(' ', AArguments),
      mAnswer.ExitCode]);
  end;
  Result := Trim(TEncoding.UTF8.GetString(mAnswer.Output));
end;

procedure RemoveFolder(const AFolder: string);
{$IFDEF MSWINDOWS}
var
  mFileName: string;
{$ENDIF}
begin
  if not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  {$IFDEF MSWINDOWS}
  // git und svn legen schreibgeschützte Dateien an.
  for mFileName in TDirectory.GetFiles(AFolder, '*', TSearchOption.soAllDirectories) do
  begin
    {$WARN SYMBOL_PLATFORM OFF}
    TFile.SetAttributes(mFileName, [TFileAttribute.faNormal]);
    {$WARN SYMBOL_PLATFORM ON}
  end;
  {$ENDIF}
  try
    TDirectory.Delete(AFolder, True);
  except
    on EInOutError do
      ;
    on EOSError do
      ;
  end;
end;

end.
