unit Shell.Composition.LeakCandidates;

// Befehl atlas.server.leakCandidates (#1875) der Komposition: Projekt zur URI
// aus den Arbeitsbereichen wie bei atlas.server.leakSetup, Dateien des
// Projekts, geöffnete Dokumente vor der Platte. Logik in
// Atlas.Common.Leaks.Candidates und Atlas.Common.Lsp.LeakCandidates.

interface

uses
  Atlas.Common.Lsp.Commands,
  Shell.Composition.LeakSetup;

type
  TShellLeakCandidates = class
  public
    /// <summary>Meldet den Befehl an (nebenläufig: liest nur).</summary>
    class procedure Attach(ACommands: TLspCommands; const AServices: TShellLeakSetupServices); static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Lsp.LeakCandidates;

{$SCOPEDENUMS ON}

type
  TShellLeakCandidatesText = (NoProject);

const
  cTexts: array[TShellLeakCandidatesText] of TAtlasText = (
    (De: 'Zu %s ist kein Projekt geladen'; En: 'No project is loaded for %s'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Projekt und Dateien aus den Arbeitsbereichen.</summary>
  TShellLeakCandidateFiles = class(TInterfacedObject, ILeakCandidateFiles)
  private
    FServices: TShellLeakSetupServices;
  public
    constructor Create(const AServices: TShellLeakSetupServices);
    function ProjectOf(const AUri: string; out AMainSource: string; out AFiles: TArray<string>;
      out AReason: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
  end;

constructor TShellLeakCandidateFiles.Create(const AServices: TShellLeakSetupServices);
begin
  inherited Create;
  FServices := AServices;
end;

function TShellLeakCandidateFiles.ProjectOf(const AUri: string; out AMainSource: string;
  out AFiles: TArray<string>; out AReason: string): Boolean;
var
  mFileName: string;
begin
  AReason := '';
  mFileName := TDocumentUris.ToPath(AUri);
  Result := TShellLeakSetup.ProjectFilesOf(FServices, mFileName, AMainSource, AFiles);
  if not Result then
  begin
    AReason := cTexts[TShellLeakCandidatesText.NoProject].Fmt([ExtractFileName(mFileName)]);
  end;
end;

function TShellLeakCandidateFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FServices.ReadText(AFileName, AText);
end;

{ TShellLeakCandidates }

class procedure TShellLeakCandidates.Attach(ACommands: TLspCommands; const AServices: TShellLeakSetupServices);
var
  mServices: TShellLeakSetupServices;
begin
  mServices := AServices;
  ACommands.RegisterConcurrent(TLspLeakCandidates.cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    var
      mFiles: ILeakCandidateFiles;
      mCommand: TLspLeakCandidates;
    begin
      // Erst in eine Interface-Variable: direkt an den const-Parameter übergeben zählt die Referenz nicht.
      mFiles := TShellLeakCandidateFiles.Create(mServices);
      mCommand := TLspLeakCandidates.Create(mFiles);
      try
        Result := mCommand.Execute(AArguments);
      finally
        mCommand.Free;
      end;
    end);
end;

end.
