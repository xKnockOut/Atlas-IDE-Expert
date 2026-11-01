unit Atlas.Core.Tracker.Adapters.Shell;

// Shell des Trackers unter Windows (#1455 Paket 2d), ohne VCL und Open Tools
// API: IAtlasTrackerShell über ShellExecute (Verb "open"). Adressen und Dateien
// prüfen die Aufrufer vorher (nur https bzw. derselbe Server, ausführbare
// Dateien nur im Explorer zeigen). Erzeugt nur Atlas.IDE.Tracker.Composition.

interface

uses
  Atlas.Core.Tracker.Contract.Files;

type
  TAtlasTrackerShellExecute = class(TInterfacedObject, IAtlasTrackerShell)
  public
    function Open(const ATarget: string): Boolean;
    function OpenFile(const AFileName: string): Boolean;
    function Reveal(const AFileName: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.ShellAPI;

const
  cOpenVerb = 'open';
  cExplorer = 'explorer.exe';
  /// <summary>ShellExecute meldet Erfolg mit einem Wert über 32.</summary>
  cShellSuccess = 32;

function Run(const AFile, AParameters, AFolder: string): Boolean;
var
  mParameters, mFolder: PChar;
begin
  mParameters := nil;
  if AParameters <> '' then
  begin
    mParameters := PChar(AParameters);
  end;
  mFolder := nil;
  if AFolder <> '' then
  begin
    mFolder := PChar(AFolder);
  end;
  Result := ShellExecute(0, cOpenVerb, PChar(AFile), mParameters, mFolder, SW_SHOWNORMAL) > cShellSuccess;
end;

{ TAtlasTrackerShellExecute }

function TAtlasTrackerShellExecute.Open(const ATarget: string): Boolean;
begin
  Result := (ATarget <> '') and Run(ATarget, '', '');
end;

function TAtlasTrackerShellExecute.OpenFile(const AFileName: string): Boolean;
begin
  Result := (AFileName <> '') and Run(AFileName, '', ExtractFilePath(AFileName));
end;

function TAtlasTrackerShellExecute.Reveal(const AFileName: string): Boolean;
begin
  Result := (AFileName <> '') and Run(cExplorer, '/select,"' + AFileName + '"', '');
end;

end.
