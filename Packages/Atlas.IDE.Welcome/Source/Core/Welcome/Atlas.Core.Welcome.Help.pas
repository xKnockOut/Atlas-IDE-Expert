unit Atlas.Core.Welcome.Help;

// Bereich „Hilfe und Rückmeldung“ der Willkommensseite (#766), ohne VCL und
// Open Tools API:
// - „Atlas-Doku“: die mit Atlas installierte Doku (Doku\index.html im
//   Installationsordner, erzeugt von Tools/Build-Docs.ps1); ohne Installation
//   die Doku-Seite des Repositorys.
// - Knöpfe des Bereichs und ob sie gerade gehen (Tastenkürzel nur mit der
//   Übersicht aus #520).

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TAtlasHelpButton = (Docs, Keys, Report, Donate);
{$SCOPEDENUMS OFF}

  TAtlasHelp = class
  public const
    DocsFolder = 'Doku';
    DocsIndex = 'index.html';
    /// <summary>Doku-Seite des Repositorys, wenn keine installierte Doku da ist.</summary>
    DocsUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert/tree/main/docs';
    /// <summary>„Atlas unterstützen“: Spendenseite (PayPal), fest; nichts wird gesendet.</summary>
    DonateUrl = 'https://www.paypal.com/paypalme/xKnockOut288';
  public
    /// <summary>Doku\index.html im Ordner APluginDir oder eine Ebene darüber (BPL in Win32\ bzw. Win64\);
    /// '' ohne. AExists prüft eine Datei.</summary>
    class function LocalDocs(const APluginDir: string; const AExists: TFunc<string, Boolean>): string; static;
    /// <summary>Lokale Doku oder DocsUrl.</summary>
    class function DocsTarget(const APluginDir: string; const AExists: TFunc<string, Boolean>): string; static;
    /// <summary>Geht der Knopf AButton? Tastenkürzel nur mit der Übersicht (keys.overview, #520).</summary>
    class function Enabled(AButton: TAtlasHelpButton; AKeysAvailable: Boolean): Boolean; static;
  end;

implementation

{ TAtlasHelp }

class function TAtlasHelp.LocalDocs(const APluginDir: string; const AExists: TFunc<string, Boolean>): string;
var
  Folder, Parent, Candidate: string;
begin
  Result := '';
  if (APluginDir = '') or not Assigned(AExists) then
    Exit;
  Folder := IncludeTrailingPathDelimiter(APluginDir);
  Candidate := Folder + DocsFolder + PathDelim + DocsIndex;
  if AExists(Candidate) then
    Exit(Candidate);
  Parent := ExtractFilePath(ExcludeTrailingPathDelimiter(Folder));
  if Parent = '' then
    Exit;
  Candidate := IncludeTrailingPathDelimiter(Parent) + DocsFolder + PathDelim + DocsIndex;
  if AExists(Candidate) then
    Result := Candidate;
end;

class function TAtlasHelp.DocsTarget(const APluginDir: string; const AExists: TFunc<string, Boolean>): string;
begin
  Result := LocalDocs(APluginDir, AExists);
  if Result = '' then
    Result := DocsUrl;
end;

class function TAtlasHelp.Enabled(AButton: TAtlasHelpButton; AKeysAvailable: Boolean): Boolean;
begin
  Result := True;
  if AButton = TAtlasHelpButton.Keys then
    Result := AKeysAvailable;
end;

end.
