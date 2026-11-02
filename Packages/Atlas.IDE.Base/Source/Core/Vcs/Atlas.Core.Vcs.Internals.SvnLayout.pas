unit Atlas.Core.Vcs.Internals.SvnLayout;

// Ort von SVN-Branches (#1290), ohne Prozesse und ohne VCL. Liegen mehrere
// Projekte in einem Repository (^/Kasse/trunk, ^/Packages/Drucken/trunk),
// gehört der Branch neben den Trunk des Projekts, nicht an die Wurzel:
//   {projektwurzel} = das Stück vor /trunk, /branches/<x> bzw. /tags/<x> im
//   Pfad der Arbeitskopie (svn info: relative-url); ^/Kasse/trunk → ^/Kasse,
//   ^/trunk → ^. Ohne erkennbares Layout gibt es keine Projektwurzel.
// Muster für den Ort (vcs.branch.svn.location) beginnen mit {projektwurzel}
// oder ^/ und kennen {name} und {kennung}. Aufgelöst wird zu einem Pfad im
// Repository ohne "^/" ("Kasse/branches/KASSE-42-bon"), der dieselben Regeln
// erfüllt wie ein Branch-Name (VcsSafeBranchName).
// Dazu die Nachricht der Kopie (vcs.branch.svn.message), der Ordner für
// „frisch auschecken“ (vcs.branch.svn.checkoutFolder) und die höchste
// Revision einer gemischten Arbeitskopie aus der Ausgabe von svnversion.
// Den Provider (BranchExists, SwitchBranch) und den Plan (Anlegen) speist
// dieselbe Auflösung; so suchen und legen beide am selben Ort an.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasSvnLayout = class
  public const
    RootPlaceholder = '{projektwurzel}';
  public
    /// <summary>Projektwurzel aus dem Pfad der Arbeitskopie ARelativeUrl ("^/Kasse/trunk" oder "Kasse/trunk"):
    /// das Stück vor dem ersten "trunk" bzw. "branches/&lt;x&gt;" oder "tags/&lt;x&gt;", ohne "^/" ('' = Wurzel des
    /// Repositorys). False ohne erkennbares Layout.</summary>
    class function ProjectRoot(const ARelativeUrl: string; out ARoot: string): Boolean; static;
    /// <summary>Muster beginnt mit {projektwurzel} oder ^/.</summary>
    class function ValidPattern(const APattern: string): Boolean; static;
    /// <summary>Muster braucht die Projektwurzel.</summary>
    class function NeedsRoot(const APattern: string): Boolean; static;
    /// <summary>Ort aus APattern: {name} = AName, {kennung} = AKey (leer: AName), {projektwurzel} = ^/ARoot bzw.
    /// ^ (nur mit ALayout). APath ohne "^/". False bei ungültigem Muster, fehlender Projektwurzel oder einem
    /// Ergebnis, das kein sicherer Pfad ist.</summary>
    class function Resolve(const APattern: string; ALayout: Boolean; const ARoot, AName, AKey: string;
      out APath: string): Boolean; overload; static;
    /// <summary>Wie oben mit Muster, Kennung aus AOptions und der Projektwurzel aus ARelativeUrl.</summary>
    class function Resolve(const AOptions: TAtlasVcsSvnBranchOptions; const ARelativeUrl, AName: string;
      out APath: string): Boolean; overload; static;
    /// <summary>Hauptbranch im Repository: ein Kandidat wie "trunk" liegt unter der Projektwurzel
    /// ("Kasse/trunk"); ein Kandidat mit "^/" oder mit schon vorhandener Projektwurzel gilt wie angegeben (ohne
    /// "^/").</summary>
    class function MainPath(const ACandidate: string; ALayout: Boolean; const ARoot: string): string; static;
    /// <summary>Nachricht für svn copy: ohne Issue (AKey leer) "Branch &lt;Name&gt;", sonst APattern mit {kennung},
    /// {titel} und {name}; leeres Ergebnis wie ohne Issue.</summary>
    class function MessageText(const APattern, AKey, ATitle, AName: string): string; static;
    /// <summary>Ordner für „frisch auschecken“: APattern mit {projekt} (leer: Ordnername von AWorkingRoot),
    /// {name} (ein "/" wird "-") und {kennung} (leer: wie {name}), relativ zu AWorkingRoot, vollständig. ''
    /// ohne Muster oder Wurzel.</summary>
    class function CheckoutFolder(const APattern, AWorkingRoot, AProject, AName, AKey: string): string; static;
    /// <summary>Höchste Revision aus der Ausgabe von svnversion ("48213", "48190:48213MS", "48213P"); AMixed bei
    /// mehreren Revisionen. False für Ausgaben ohne Revision ("Unversioned directory", "exported").</summary>
    class function WorkingRevision(const ASvnVersion: string; out ARevision: string; out AMixed: Boolean): Boolean;
      static;
  end;

implementation

uses
  Atlas.Core.Vcs.Internals.Text;

function StartsText(const APrefix, AText: string): Boolean;
begin
  Result := SameText(Copy(AText, 1, Length(APrefix)), APrefix);
end;

function Replaced(const AText, APlaceholder, AValue: string): string;
begin
  Result := StringReplace(AText, APlaceholder, AValue, [rfReplaceAll, rfIgnoreCase]);
end;

function WithoutCaret(const AText: string): string;
begin
  Result := Trim(AText);
  if Copy(Result, 1, 2) = '^/' then
    Delete(Result, 1, 2)
  else if Result = '^' then
    Result := '';
end;

{ TAtlasSvnLayout }

class function TAtlasSvnLayout.ProjectRoot(const ARelativeUrl: string; out ARoot: string): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  ARoot := '';
  Result := False;
  mParts := WithoutCaret(ARelativeUrl).Split(['/'], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(mParts) do
    if (mParts[mIndex] = 'trunk') or
      (((mParts[mIndex] = 'branches') or (mParts[mIndex] = 'tags')) and (mIndex < High(mParts))) then
    begin
      // Alles davor; am Anfang ('' = Wurzel des Repositorys).
      ARoot := string.Join('/', mParts, 0, mIndex);
      Exit(True);
    end;
end;

class function TAtlasSvnLayout.ValidPattern(const APattern: string): Boolean;
begin
  Result := StartsText(RootPlaceholder, Trim(APattern)) or (Copy(Trim(APattern), 1, 2) = '^/');
end;

class function TAtlasSvnLayout.NeedsRoot(const APattern: string): Boolean;
begin
  Result := StartsText(RootPlaceholder, Trim(APattern));
end;

class function TAtlasSvnLayout.Resolve(const APattern: string; ALayout: Boolean; const ARoot, AName, AKey: string;
  out APath: string): Boolean;
var
  mText, mKey: string;
begin
  APath := '';
  Result := False;
  mText := Trim(APattern);
  if not ValidPattern(mText) or (AName = '') then
    Exit;
  mKey := AKey;
  if mKey = '' then
    mKey := AName;
  if NeedsRoot(mText) then
  begin
    if not ALayout then
      Exit;
    Delete(mText, 1, Length(RootPlaceholder));
    if WithoutCaret(ARoot) = '' then
      mText := '^' + mText
    else
      mText := '^/' + WithoutCaret(ARoot) + mText;
  end;
  mText := Replaced(Replaced(mText, '{name}', AName), '{kennung}', mKey);
  if Copy(mText, 1, 2) <> '^/' then
    Exit;
  mText := Copy(mText, 3, MaxInt);
  while (mText <> '') and (mText[Length(mText)] = '/') do
    Delete(mText, Length(mText), 1);
  // Übrige Platzhalter, "..", "//", Leer- und Steuerzeichen: kein Ort.
  if (Pos('{', mText) > 0) or not VcsSafeBranchName(mText) then
    Exit;
  APath := mText;
  Result := True;
end;

class function TAtlasSvnLayout.Resolve(const AOptions: TAtlasVcsSvnBranchOptions; const ARelativeUrl,
  AName: string; out APath: string): Boolean;
var
  mRoot: string;
  mLayout: Boolean;
begin
  mLayout := ProjectRoot(ARelativeUrl, mRoot);
  Result := Resolve(AOptions.Location, mLayout, mRoot, AName, AOptions.Key, APath);
end;

class function TAtlasSvnLayout.MainPath(const ACandidate: string; ALayout: Boolean; const ARoot: string): string;
var
  mFirst, mRoot: string;
begin
  Result := Trim(ACandidate);
  if Copy(Result, 1, 2) = '^/' then
    Exit(Copy(Result, 3, MaxInt));
  mRoot := WithoutCaret(ARoot);
  if not ALayout or (mRoot = '') or StartsText(mRoot + '/', Result) then
    Exit;
  mFirst := Result;
  if Pos('/', mFirst) > 0 then
    mFirst := Copy(mFirst, 1, Pos('/', mFirst) - 1);
  // Nur die Teile des Layouts liegen unter der Projektwurzel; "Kasse/trunk" oder "Andere/trunk" gelten wie angegeben.
  if (mFirst = 'trunk') or (mFirst = 'branches') or (mFirst = 'tags') then
    Result := mRoot + '/' + Result;
end;

class function TAtlasSvnLayout.MessageText(const APattern, AKey, ATitle, AName: string): string;
begin
  if Trim(AKey) = '' then
    Exit('Branch ' + AName);
  Result := Trim(Replaced(Replaced(Replaced(APattern, '{kennung}', Trim(AKey)), '{titel}', Trim(ATitle)), '{name}',
    AName));
  if Result = '' then
    Result := 'Branch ' + AName;
end;

class function TAtlasSvnLayout.CheckoutFolder(const APattern, AWorkingRoot, AProject, AName, AKey: string): string;
var
  mRoot, mName, mKey, mProject: string;
begin
  Result := Trim(APattern);
  mRoot := VcsNormalizeDir(AWorkingRoot);
  if (Result = '') or (mRoot = '') then
    Exit('');
  mName := StringReplace(AName, '/', '-', [rfReplaceAll]);
  mKey := Trim(AKey);
  if mKey = '' then
    mKey := mName;
  mProject := Trim(AProject);
  if mProject = '' then
    mProject := ExtractFileName(mRoot);
  Result := Replaced(Replaced(Replaced(Result, '{projekt}', mProject), '{name}', mName), '{kennung}', mKey);
  Result := StringReplace(StringReplace(Result, '/', PathDelim, [rfReplaceAll]), '\', PathDelim, [rfReplaceAll]);
  // Absolut: Laufwerk, UNC bzw. "/" unter Unix; sonst neben bzw. unter der Arbeitskopie.
  if not ((Length(Result) >= 2) and (Result[2] = ':')) and (Copy(Result, 1, 1) <> PathDelim) then
    Result := IncludeTrailingPathDelimiter(mRoot) + Result;
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
end;

class function TAtlasSvnLayout.WorkingRevision(const ASvnVersion: string; out ARevision: string;
  out AMixed: Boolean): Boolean;
var
  mText: string;
begin
  ARevision := '';
  AMixed := False;
  mText := Trim(ASvnVersion);
  // Marken am Ende: M geändert, S umgeschaltet, P teilweise.
  while (mText <> '') and CharInSet(mText[Length(mText)], ['M', 'S', 'P']) do
    Delete(mText, Length(mText), 1);
  if Pos(':', mText) > 0 then
  begin
    AMixed := True;
    mText := Copy(mText, Pos(':', mText) + 1, MaxInt);
  end;
  Result := (mText <> '') and (StrToIntDef(mText, -1) >= 0);
  if Result then
    ARevision := mText
  else
    AMixed := False;
end;

end.
