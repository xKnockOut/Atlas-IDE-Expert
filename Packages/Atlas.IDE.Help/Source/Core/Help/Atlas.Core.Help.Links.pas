unit Atlas.Core.Help.Links;

// Ziele der F1-Hilfe (#1886, Modul Hilfe), ohne VCL und Open Tools API:
// - Regel: docs/Regeln.md bzw. docs/en/Rules.md mit dem Anker der Regel-ID (<a id="regel">).
// - Einstellung: docs/Einstellungen.md bzw. docs/en/Settings.md mit dem Anker setting-<Schlüssel>, den
//   Tools/Update-ConfigDoc.ps1 je Schlüssel schreibt.
// - Atlas-Fenster: Seite unter docs/features/<de|en>/ mit dem Anker window-<Kennung> (Tabelle cWindows, Kennung =
//   Identifier des Dockfensters); die Optionsseite ohne Einstellung unter dem Fokus öffnet die Seite Einstellungen.
// Online: Datei im Repository zum Versionstag (v<Version>, ohne Version main). Lokal: die Seite im Ordner Doku, die
// Tools/Build-Docs.ps1 erzeugt (flach, Funktion-<Name>.html bzw. Feature-<Name>.html). Tools/Check-HelpAnchors.ps1
// prüft, dass jedes Ziel der Tabelle in beiden Sprachen existiert.

interface

uses
  System.SysUtils;

type
  /// <summary>Atlas-Fenster und seine Funktionsseite (Dateiname ohne .md in docs/features/de bzw. en).</summary>
  TAtlasHelpWindow = record
    Id: string;
    German: string;
    English: string;
  end;

  /// <summary>Ziel einer Hilfe: Pfad relativ zum Repository und Anker (ohne #, '' = Seitenanfang).</summary>
  TAtlasHelpTarget = record
    Path: string;
    Anchor: string;
  end;

  TAtlasHelpLinks = class
  public const
    cRepositoryUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert';
    cWindowAnchor = 'window-';
    cSettingAnchor = 'setting-';
    cOptionsWindow = 'AtlasOptions';
  public
    /// <summary>Alle Atlas-Fenster mit Funktionsseite (Tests, Tools/Check-HelpAnchors.ps1).</summary>
    class function Windows: TArray<TAtlasHelpWindow>; static;
    /// <summary>Seite der Regel ARule; False ohne Regel oder für Meldungen des Compilers (E2003, W1000 …).</summary>
    class function Rule(const ARule: string; AEnglish: Boolean; out ATarget: TAtlasHelpTarget): Boolean; static;
    /// <summary>Abschnitt der Einstellung AKey (x-key); False ohne Schlüssel.</summary>
    class function Setting(const AKey: string; AEnglish: Boolean; out ATarget: TAtlasHelpTarget): Boolean; static;
    /// <summary>Funktionsseite des Atlas-Fensters AId; False für ein unbekanntes Fenster.</summary>
    class function Window(const AId: string; AEnglish: Boolean; out ATarget: TAtlasHelpTarget): Boolean; static;
    /// <summary>Adresse auf GitHub zum Versionstag „v“ + AVersion; AVersion '' = main.</summary>
    class function OnlineUrl(const ATarget: TAtlasHelpTarget; const AVersion: string): string; static;
    /// <summary>Datei der Seite im Ordner Doku (Tools/Build-Docs.ps1); '' für eine Seite, die dort fehlt.</summary>
    class function LocalPage(const APath: string): string; static;
    /// <summary>Ordner Doku (mit index.html) in APluginDir oder eine Ebene darüber (BPL in Win32\ bzw. Win64\);
    /// '' ohne. AExists prüft eine Datei.</summary>
    class function LocalFolder(const APluginDir: string; const AExists: TFunc<string, Boolean>): string; static;
    /// <summary>file:///-Adresse der Seite APage in AFolder mit Anker.</summary>
    class function LocalUrl(const AFolder, APage, AAnchor: string): string; static;
    /// <summary>Kleine Seite, die sofort nach AUrl weiterleitet: Windows verliert den Anker, wenn es eine lokale Datei
    /// mit #Anker direkt öffnet.</summary>
    class function RedirectHtml(const AUrl: string): string; static;
  end;

implementation

const
  cFeaturesGerman = 'docs/features/de/';
  cFeaturesEnglish = 'docs/features/en/';
  cWindows: array[0..26] of TAtlasHelpWindow = (
    (Id: 'AtlasProblems'; German: 'Code-Analyse'; English: 'Code-analysis'), // german-ok Dateiname
    (Id: 'AtlasResults'; German: 'Navigieren'; English: 'Navigating'), // german-ok Dateiname
    (Id: 'AtlasOutline'; German: 'Navigieren'; English: 'Navigating'), // german-ok Dateiname
    (Id: 'AtlasSearchReplace'; German: 'Navigieren'; English: 'Navigating'), // german-ok Dateiname
    (Id: 'AtlasBookmarks'; German: 'Navigieren'; English: 'Navigating'), // german-ok Dateiname
    (Id: 'AtlasServerStatus'; German: 'IDE-Komfort'; English: 'IDE-comfort'), // german-ok Dateiname
    (Id: 'AtlasDiagnostics'; German: 'IDE-Komfort'; English: 'IDE-comfort'), // german-ok Dateiname
    (Id: 'AtlasStart'; German: 'IDE-Komfort'; English: 'IDE-comfort'), // german-ok Dateiname
    (Id: 'AtlasIssue'; German: 'IDE-Komfort'; English: 'IDE-comfort'), // german-ok Dateiname
    (Id: 'AtlasBoard'; German: 'IDE-Komfort'; English: 'IDE-comfort'), // german-ok Dateiname
    (Id: 'AtlasFlowMap'; German: 'IDE-Komfort'; English: 'IDE-comfort'), // german-ok Dateiname
    (Id: 'AtlasArchitecture'; German: 'Verstehen'; English: 'Understanding'), // german-ok Dateiname
    (Id: 'AtlasQuery'; German: 'Verstehen'; English: 'Understanding'), // german-ok Dateiname
    (Id: 'AtlasHotspots'; German: 'Verstehen'; English: 'Understanding'), // german-ok Dateiname
    (Id: 'AtlasUnitRelations'; German: 'Verstehen'; English: 'Understanding'), // german-ok Dateiname
    (Id: 'AtlasEvaluate'; German: 'Bauen-Testen-Debuggen'; English: 'Build-test-debug'), // german-ok Dateiname
    (Id: 'AtlasDebugExceptions'; German: 'Bauen-Testen-Debuggen'; English: 'Build-test-debug'), // german-ok Dateiname
    (Id: 'AtlasDebugEventLog'; German: 'Bauen-Testen-Debuggen'; English: 'Build-test-debug'), // german-ok Dateiname
    (Id: 'AtlasDebugParallelStacks'; German: 'Bauen-Testen-Debuggen'; English: 'Build-test-debug'), // german-ok Dateiname
    (Id: 'AtlasDebugLeaks'; German: 'Bauen-Testen-Debuggen'; English: 'Build-test-debug'), // german-ok Dateiname
    (Id: 'AtlasTestsExplorer'; German: 'Bauen-Testen-Debuggen'; English: 'Build-test-debug'), // german-ok Dateiname
    (Id: 'AtlasStepFilter'; German: 'Bauen-Testen-Debuggen'; English: 'Build-test-debug'), // german-ok Dateiname
    (Id: 'AtlasBreakpoints'; German: 'Bauen-Testen-Debuggen'; English: 'Build-test-debug'), // german-ok Dateiname
    (Id: 'AtlasCompilerSwitches'; German: 'Bauen-Testen-Debuggen'; English: 'Build-test-debug'), // german-ok Dateiname
    (Id: 'AtlasStructure'; German: 'Formulare'; English: 'Forms'), // german-ok Dateiname
    (Id: 'AtlasEventMap'; German: 'Formulare'; English: 'Forms'), // german-ok Dateiname
    (Id: TAtlasHelpLinks.cOptionsWindow; German: 'Einstellungen'; English: 'Settings')); // german-ok Dateiname

function Target(const APath, AAnchor: string): TAtlasHelpTarget;
begin
  Result.Path := APath;
  Result.Anchor := AAnchor;
end;

/// <summary>Meldungsnummer des Compilers (Buchstabe und vier Ziffern, etwa E2003, H2443).</summary>
function IsCompilerCode(const ACode: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (Length(ACode) = 5) and CharInSet(UpCase(ACode[1]), ['E', 'F', 'H', 'W', 'X']);
  for mIndex := 2 to Length(ACode) do
  begin
    Result := Result and CharInSet(ACode[mIndex], ['0'..'9']);
  end;
end;

{ TAtlasHelpLinks }

class function TAtlasHelpLinks.Windows: TArray<TAtlasHelpWindow>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cWindows));
  for mIndex := 0 to High(cWindows) do
  begin
    Result[mIndex] := cWindows[mIndex];
  end;
end;

class function TAtlasHelpLinks.Rule(const ARule: string; AEnglish: Boolean; out ATarget: TAtlasHelpTarget): Boolean;
var
  mRule: string;
begin
  mRule := Trim(ARule);
  Result := (mRule <> '') and not IsCompilerCode(mRule);
  ATarget := Target('docs/Regeln.md', mRule); // german-ok Dateiname
  if AEnglish then
  begin
    ATarget.Path := 'docs/en/Rules.md';
  end;
end;

class function TAtlasHelpLinks.Setting(const AKey: string; AEnglish: Boolean; out ATarget: TAtlasHelpTarget): Boolean;
var
  mKey: string;
begin
  mKey := Trim(AKey);
  Result := mKey <> '';
  ATarget := Target('docs/Einstellungen.md', cSettingAnchor + mKey); // german-ok Dateiname
  if AEnglish then
  begin
    ATarget.Path := 'docs/en/Settings.md';
  end;
end;

class function TAtlasHelpLinks.Window(const AId: string; AEnglish: Boolean; out ATarget: TAtlasHelpTarget): Boolean;
var
  mWindow: TAtlasHelpWindow;
begin
  ATarget := Target('', '');
  for mWindow in cWindows do
  begin
    if SameText(mWindow.Id, AId) then
    begin
      ATarget := Target(cFeaturesGerman + mWindow.German + '.md', cWindowAnchor + LowerCase(mWindow.Id));
      if AEnglish then
      begin
        ATarget.Path := cFeaturesEnglish + mWindow.English + '.md';
      end;
      if SameText(mWindow.Id, cOptionsWindow) then
      begin
        ATarget.Anchor := '';
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasHelpLinks.OnlineUrl(const ATarget: TAtlasHelpTarget; const AVersion: string): string;
var
  mRef: string;
begin
  mRef := 'main';
  if Trim(AVersion) <> '' then
  begin
    mRef := 'v' + Trim(AVersion);
  end;
  Result := cRepositoryUrl + '/blob/' + mRef + '/' + ATarget.Path;
  if ATarget.Anchor <> '' then
  begin
    Result := Result + '#' + ATarget.Anchor;
  end;
end;

class function TAtlasHelpLinks.LocalPage(const APath: string): string;
var
  mPath, mName: string;
begin
  mPath := StringReplace(APath, '\', '/', [rfReplaceAll]);
  mName := ChangeFileExt(ExtractFileName(StringReplace(mPath, '/', PathDelim, [rfReplaceAll])), '');
  if SameText(mPath, 'docs/Regeln.md') or SameText(mPath, 'docs/Einstellungen.md') then // german-ok Dateiname
  begin
    Result := mName + '.html';
  end
  else if SameText(mPath, 'docs/en/Rules.md') or SameText(mPath, 'docs/en/Settings.md') then
  begin
    Result := 'en-' + mName + '.html';
  end
  else if SameText(Copy(mPath, 1, Length(cFeaturesGerman)), cFeaturesGerman) then
  begin
    Result := 'Funktion-' + mName + '.html'; // german-ok Dateiname
  end
  else if SameText(Copy(mPath, 1, Length(cFeaturesEnglish)), cFeaturesEnglish) then
  begin
    Result := 'Feature-' + mName + '.html';
  end
  else
  begin
    Result := '';
  end;
end;

class function TAtlasHelpLinks.LocalFolder(const APluginDir: string; const AExists: TFunc<string, Boolean>): string;
const
  cFolder = 'Doku';
  cIndex = 'index.html';
var
  mFolder, mParent: string;
begin
  Result := '';
  if (APluginDir = '') or not Assigned(AExists) then
  begin
    Exit;
  end;
  mFolder := IncludeTrailingPathDelimiter(APluginDir) + cFolder + PathDelim;
  mParent := ExtractFilePath(ExcludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(APluginDir)));
  if AExists(mFolder + cIndex) then
  begin
    Result := mFolder;
  end
  else if (mParent <> '') and AExists(IncludeTrailingPathDelimiter(mParent) + cFolder + PathDelim + cIndex) then
  begin
    Result := IncludeTrailingPathDelimiter(mParent) + cFolder + PathDelim;
  end;
end;

class function TAtlasHelpLinks.LocalUrl(const AFolder, APage, AAnchor: string): string;
var
  mFolder: string;
begin
  mFolder := StringReplace(AFolder, '\', '/', [rfReplaceAll]);
  if (mFolder <> '') and (mFolder[Length(mFolder)] <> '/') then
  begin
    mFolder := mFolder + '/';
  end;
  Result := StringReplace(mFolder + APage, ' ', '%20', [rfReplaceAll]);
  Result := StringReplace(Result, '#', '%23', [rfReplaceAll]);
  if (Result <> '') and (Result[1] = '/') then
  begin
    Result := 'file://' + Result;
  end
  else
  begin
    Result := 'file:///' + Result;
  end;
  if AAnchor <> '' then
  begin
    Result := Result + '#' + AAnchor;
  end;
end;

class function TAtlasHelpLinks.RedirectHtml(const AUrl: string): string;
var
  mUrl: string;
begin
  mUrl := StringReplace(StringReplace(AUrl, '&', '&amp;', [rfReplaceAll]), '"', '&quot;', [rfReplaceAll]);
  Result := '<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=' + mUrl +
    '"></head><body><a href="' + mUrl + '">Atlas</a></body></html>';
end;

end.
