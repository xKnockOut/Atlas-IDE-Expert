unit Atlas.Core.Projects.PathCheck;

// „Suchpfade und Defines prüfen“ der Einrichtung (#759), ohne VCL und Open
// Tools API: Welche Units aus uses findet der Compiler nicht, und welche
// bedingten Symbole fragt der Code ab, ohne dass sie irgendwo gesetzt werden?
//
// Units: Jede Datei des Projekts (.dpr/.dpk und die eingetragenen Units) wird
// nach uses (bei Packages auch contains) durchsucht; bedingte Abschnitte
// ($IFDEF, $IFNDEF, $IF DEFINED(…), $ELSEIF, $ELSE, $DEFINE, $UNDEF) werden mit
// den Symbolen der aktiven Konfiguration und Plattform ausgewertet. Units in
// inaktiven Zweigen zählen nicht; lässt sich eine Bedingung nicht auswerten
// (CompilerVersion, Declared, $IFOPT), zählen die Units darin ebenfalls nicht.
// Gefunden ist eine Unit wie beim Compiler: mit "in 'Pfad'" an diesem Pfad,
// sonst als Datei des Projekts oder als Name.pas bzw. Name.dcu im Ordner der
// verwendenden Datei, im Projektordner, in den Suchpfaden des Projekts und in
// den Bibliothekspfaden der IDE, jeweils auch mit jedem Unit-Namespace davor
// (SysUtils → System.SysUtils). System und SysInit gibt es immer.
//
// Defines ohne Quelle: Symbole aus $IFDEF, $IFNDEF und DEFINED(…) der
// Projektdateien, die weder in einer Konfiguration der .dproj (DCC_Define,
// alle Konfigurationen und Plattformen) noch per $DEFINE in einer
// Projektdatei oder einer eingebundenen Datei ($I, $INCLUDE) gesetzt werden
// und die der Compiler nicht selbst setzt (Atlas.Text.Defines). Abfragen aus
// eingebundenen Dateien zählen nicht (Bibliotheken wie jedi.inc fragen viele
// fremde Symbole ab); Symbole anderer Compiler (FPC …) auch nicht.
//
// Packages (#759): Units eines per requires eingebundenen Packages der
// Projektgruppe gelten als gefunden. Steht ihr Ordner zusätzlich im Suchpfad,
// oder hat ein requires-Package keine Quelle in der Gruppe und liegt nur als
// .dcp außerhalb der Bibliothekspfade, gibt es einen Hinweis (kein Fehler).
// Ebenso Units eines Projekts der Gruppe, dessen DCU-Ausgabeordner im
// Suchpfad steht (ProducedBy): Sie entstehen beim Bauen der Gruppe.
// Quellen eines Symbols außerdem: -dX in Build-Skripten (*.sh, *.cmd, *.bat)
// und ConditionalDefines in .lpi/.lpk der Skriptordner.
// Symbole anderer Compiler und Widgetsets (FPC, UNIX, CPU*, ENDIAN_*, FPC_*,
// LCL*) gelten als bekannt. Ein Symbol ohne Quelle bekommt einen Vorschlag,
// wenn ein bekanntes Symbol ähnlich geschrieben ist (Tippfehler).
//
// Pfade: unter Windows mit „\“; ExpandPath setzt $(Name) über eine Funktion
// des Aufrufers ein (auch verschachtelt, etwa BDSLIB = $(BDS)\lib) und macht
// relative Pfade absolut. TAtlasPathMacros sammelt die Werte: zuerst die der
// IDE (Umgebungsvariablen aus den IDE-Optionen, BDS-Ordner, Projekt, Plattform,
// Konfiguration), danach die Umgebung des Prozesses.
// Unsichere Funde: Bleibt in einem Such- oder Bibliothekspfad ein Makro
// unbekannt, fällt der Pfad weg und das Makro steht in SkippedMacros. Eine
// fehlende Unit (ohne "in 'Pfad'") könnte dann in diesem Ordner liegen: Sie
// zählt als unsicher (Uncertain), nicht als sicherer Fund. Ebenso ein Define
// ohne Quelle, wenn eine eingebundene Datei nicht gefunden wurde.
// Dateizugriffe kommen von außen (Lesen, Auflisten eines Ordners), damit die
// Tests ohne Platte laufen und die IDE die Arbeit in einen Hintergrundthread
// legen kann.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.PathCheck.Scan;

type
  TAtlasBranchState = Atlas.Core.Projects.PathCheck.Scan.TAtlasBranchState;
  TAtlasUsedUnit = Atlas.Core.Projects.PathCheck.Scan.TAtlasUsedUnit;
  TAtlasSymbolUse = Atlas.Core.Projects.PathCheck.Scan.TAtlasSymbolUse;
  TAtlasSourceScan = Atlas.Core.Projects.PathCheck.Scan.TAtlasSourceScan;

  /// <summary>Fehlende Unit oder Symbol ohne Quelle: erste Stelle und Zahl der Stellen.</summary>
  TAtlasPathFinding = record
    Name: string;
    /// <summary>Voller Pfad der Datei mit der ersten Stelle.</summary>
    FileName: string;
    /// <summary>Zeile ab 1.</summary>
    Line: Integer;
    Count: Integer;
    /// <summary>Kein sicherer Fund: Ein Suchpfad mit unbekanntem Makro wurde übersprungen.</summary>
    Uncertain: Boolean;
    /// <summary>Define: ähnlich geschriebenes bekanntes Symbol (Tippfehler?). Hinweis: Unit im Suchpfad, die zu
    /// dem requires-Package Name gehört; '' = Package ohne Quelle.</summary>
    Note: string;
  end;

  TAtlasPathCheckInput = record
    /// <summary>.dproj; ihr Ordner ist der Projektordner.</summary>
    Project: string;
    /// <summary>Volle Pfade: Hauptdatei (.dpr/.dpk) zuerst, dann die Units des Projekts.</summary>
    Sources: TArray<string>;
    /// <summary>Absolute Suchpfade des Projekts (ExpandPath).</summary>
    SearchPaths: TArray<string>;
    /// <summary>Absolute Bibliothekspfade der IDE.</summary>
    LibraryPaths: TArray<string>;
    Namespaces: TArray<string>;
    /// <summary>Symbole der aktiven Konfiguration samt vordefinierten der Plattform; werten die Zweige aus.</summary>
    ActiveDefines: TArray<string>;
    /// <summary>Alle Symbole aus der .dproj (alle Konfigurationen, DprojDefines); gelten als Quelle.</summary>
    ProjectDefines: TArray<string>;
    /// <summary>Unbekannte Makros übersprungener Such- und Bibliothekspfade (ohne „$(“ und „)“).</summary>
    SkippedMacros: TArray<string>;
    /// <summary>.dproj aller Projekte der Projektgruppe; ihre Packages erfüllen requires.</summary>
    GroupProjects: TArray<string>;
    /// <summary>Ordner mit Build-Skripten (-dX) und .lpi/.lpk.</summary>
    ScriptFolders: TArray<string>;
    /// <summary>.dproj von Projekten der Gruppe, deren DCU-Ausgabeordner im Suchpfad steht: Ihre Units entstehen
    /// beim Bauen der Gruppe und gelten als gefunden.</summary>
    ProducedBy: TArray<string>;
  end;

  TAtlasPathCheckResult = record
    /// <summary>Gelesene Dateien des Projekts.</summary>
    Files: Integer;
    /// <summary>Nicht lesbare Dateien des Projekts.</summary>
    Unreadable: Integer;
    MissingUnits: TArray<TAtlasPathFinding>;
    UndefinedDefines: TArray<TAtlasPathFinding>;
    /// <summary>Hinweise zu requires-Packages (Name = Package, Note = Unit im Suchpfad bzw. ''); kein Fehler.</summary>
    Hints: TArray<TAtlasPathFinding>;
    /// <summary>Wie TAtlasPathCheckInput.SkippedMacros.</summary>
    SkippedMacros: TArray<string>;
    /// <summary>Keine sicheren Funde (unsichere zählen nicht).</summary>
    function Clean: Boolean;
    /// <summary>Unsichere Funde in AFindings.</summary>
    class function UncertainIn(const AFindings: TArray<TAtlasPathFinding>): Integer; static;
  end;

  /// <summary>Liest AFileName als Text; False, wenn die Datei fehlt oder nicht lesbar ist.</summary>
  TAtlasPathReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Dateinamen (mit Endung, ohne Ordner) in AFolder; leer, wenn der Ordner fehlt.</summary>
  TAtlasPathListFolder = reference to function(const AFolder: string): TArray<string>;
  /// <summary>Wert der Variablen AName ($(AName)); '' = unbekannt.</summary>
  TAtlasPathVariable = reference to function(const AName: string): string;

  /// <summary>Werte für $(Name) in Such- und Bibliothekspfaden: zuerst die gesetzten (IDE), dann die Umgebung
  /// des Prozesses. Namen ohne Unterschied der Groß-/Kleinschreibung.</summary>
  TAtlasPathMacros = record
  private
    FNames: TArray<string>;
    FValues: TArray<string>;
    FEnvironment: TAtlasPathVariable;
    function IndexOf(const AName: string): Integer;
  public
    /// <summary>AEnvironment (darf nil sein): Umgebung des Prozesses, gilt nach allen gesetzten Werten.</summary>
    class function Create(const AEnvironment: TAtlasPathVariable): TAtlasPathMacros; static;
    /// <summary>Setzt AName; ein späterer Aufruf überschreibt. Leere Werte zählen nicht.</summary>
    procedure Add(const AName, AValue: string);
    /// <summary>Wie Add, aber nur, wenn AName noch keinen Wert hat.</summary>
    procedure AddDefault(const AName, AValue: string);
    /// <summary>BDS und, wo noch kein Wert steht, BDSLIB, BDSBIN und BDSINCLUDE darunter.</summary>
    procedure AddBds(const ABdsDir: string);
    /// <summary>Platform, Config, ProjectDir, ProjectName, ProjectFilename, ProjectPath und die
    /// MSBuild-Namen (MSBuildProjectDirectory, MSBuildProjectName, MSBuildProjectFullPath,
    /// MSBuildThisFileDirectory, MSBuildProjectDirectoryNoRoot) für die Projektdatei AProject.</summary>
    procedure AddProject(const AProject, APlatform, AConfig: string);
    /// <summary>Gesetzter Wert, sonst der der Umgebung; '' = unbekannt.</summary>
    function Value(const AName: string): string;
    /// <summary>Value als Funktion für ExpandPath (mit einer Kopie der Werte).</summary>
    function Variable: TAtlasPathVariable;
  end;

  TAtlasPathCheck = class
  public const
    /// <summary>Höchstens so viele eingebundene Dateien werden für $DEFINE gelesen.</summary>
    MaxIncludes = 200;
    /// <summary>Höchstens so viele Ersetzungen von $(…) je Pfad.</summary>
    MaxExpansions = 32;
  public
    /// <summary>uses, bedingte Symbole und eingebundene Dateien von AText; ADefines gelten zu Beginn.</summary>
    class function Scan(const AText: string; const ADefines: TArray<string>): TAtlasSourceScan; static;
    /// <summary>Wertet einen $IF-Ausdruck aus DEFINED(…), NOT, AND, OR und Klammern aus; alles andere ergibt
    /// Unknown.</summary>
    class function Evaluate(const AExpression: string; const ADefines: TArray<string>): TAtlasBranchState; static;
    /// <summary>Prüft alle Dateien aus AInput.</summary>
    class function Run(const AInput: TAtlasPathCheckInput; const ARead: TAtlasPathReadText;
      const AList: TAtlasPathListFolder): TAtlasPathCheckResult; static;
    /// <summary>Setzt $(Name) über AVariable ein und macht APath relativ zu ABaseDir absolut ("\" als Trenner,
    /// "." und ".." aufgelöst). '' bei leerem Pfad oder unbekannter Variable.</summary>
    class function ExpandPath(const APath, ABaseDir: string; const AVariable: TAtlasPathVariable): string;
      overload; static;
    /// <summary>Wie oben; AUnknown = Name des ersten unbekannten Makros ('' sonst). Werte dürfen selbst $(…)
    /// enthalten; nach MaxExpansions Ersetzungen gilt das Makro als unbekannt (Schleife).</summary>
    class function ExpandPath(const APath, ABaseDir: string; const AVariable: TAtlasPathVariable;
      out AUnknown: string): string; overload; static;
    /// <summary>Alle Pfade aus ARaw über ExpandPath; Pfade mit unbekanntem Makro fallen weg, ihre Makros kommen
    /// (ohne Doppelte) nach ASkipped.</summary>
    class function ExpandPaths(const ARaw: TArray<string>; const ABaseDir: string;
      const AVariable: TAtlasPathVariable; var ASkipped: TArray<string>): TArray<string>; static;
    /// <summary>Ordner und Name verbunden, "." und ".." aufgelöst; absolute ANames bleiben.</summary>
    class function Combine(const AFolder, AName: string): string; static;
    /// <summary>Alle Symbole aus DCC_Define der .dproj (alle Konfigurationen), ohne $(…), ohne Doppelte.</summary>
    class function DprojDefines(const ADprojText: string): TArray<string>; static;
    /// <summary>Symbole anderer Compiler und Widgetsets, die Delphi-Code oft abfragt (FPC, UNIX, CPU*, ENDIAN_*,
    /// FPC_*, LCL* …).</summary>
    class function IsForeignSymbol(const AName: string): Boolean; static;
    /// <summary>DCC_Define der Konfiguration AConfig (Debug, Release …) und Plattform APlatform mit Vererbung
    /// Base → Cfg_n → Cfg_n_Plattform; $(DCC_Define) setzt den Wert der Ebene darüber ein.</summary>
    class function DprojConfigDefines(const ADprojText, AConfig, APlatform: string): TArray<string>; static;
    /// <summary>Gesetzte Symbole einer Skriptdatei: -dX (*.sh, *.cmd, *.bat …), in .lpi/.lpk auch
    /// ConditionalDefines.</summary>
    class function ScriptDefines(const AFileName, AText: string): TArray<string>; static;
    /// <summary>Ähnlich geschriebenes Symbol aus AKnown (höchstens zwei Zeichen anders); '' ohne.</summary>
    class function Suggest(const AName: string; const AKnown: TArray<string>): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Defines;

const
  // IMPLICITBUILDING setzt die IDE beim impliziten Bauen eines Packages (steht in jeder .dpk-Vorlage);
  // TESTINSIGHT und CI fragt die Projektvorlage von DUnitX ab, gesetzt werden sie vom jeweiligen Werkzeug.
  cForeignSymbols: array[0..15] of string = ('FPC', 'CLR', 'KYLIX', 'LCL', 'DOTNET', 'UNIX', 'DARWIN', 'WINDOWS',
    'BSD', 'FREEBSD', 'HAIKU', 'WASI', 'EMBEDDED', 'IMPLICITBUILDING', 'TESTINSIGHT', 'CI');
  // Präfixe von Symbolen, die Free Pascal bzw. Lazarus je Ziel setzt (CPUX86_64, ENDIAN_BIG, FPC_FULLVERSION, LCLgtk2).
  cForeignPrefixes: array[0..3] of string = ('CPU', 'ENDIAN_', 'FPC_', 'LCL');
  cScriptExtensions: array[0..4] of string = ('.sh', '.cmd', '.bat', '.lpi', '.lpk');
  cAlwaysThere: array[0..1] of string = ('SYSTEM', 'SYSINIT');

{ TAtlasPathCheckResult }

function TAtlasPathCheckResult.Clean: Boolean;
begin
  Result := (UncertainIn(MissingUnits) = Length(MissingUnits)) and
    (UncertainIn(UndefinedDefines) = Length(UndefinedDefines));
end;

class function TAtlasPathCheckResult.UncertainIn(const AFindings: TArray<TAtlasPathFinding>): Integer;
var
  mFinding: TAtlasPathFinding;
begin
  Result := 0;
  for mFinding in AFindings do
  begin
    if mFinding.Uncertain then
    begin
      Inc(Result);
    end;
  end;
end;

{ TAtlasPathMacros }

class function TAtlasPathMacros.Create(const AEnvironment: TAtlasPathVariable): TAtlasPathMacros;
begin
  Result := Default(TAtlasPathMacros);
  Result.FEnvironment := AEnvironment;
end;

function TAtlasPathMacros.IndexOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FNames) do
  begin
    if SameText(FNames[mIndex], Trim(AName)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasPathMacros.Add(const AName, AValue: string);
var
  mIndex: Integer;
begin
  if (Trim(AName) = '') or (Trim(AValue) = '') then
  begin
    Exit;
  end;
  mIndex := IndexOf(AName);
  if mIndex >= 0 then
  begin
    FValues[mIndex] := AValue;
  end
  else
  begin
    FNames := FNames + [Trim(AName)];
    FValues := FValues + [AValue];
  end;
end;

procedure TAtlasPathMacros.AddDefault(const AName, AValue: string);
begin
  if IndexOf(AName) < 0 then
  begin
    Add(AName, AValue);
  end;
end;

function WithoutSlash(const AFolder: string): string;
begin
  Result := Trim(AFolder);
  while (Length(Result) > 3) and CharInSet(Result[Length(Result)], ['\', '/']) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

procedure TAtlasPathMacros.AddBds(const ABdsDir: string);
var
  mBds: string;
begin
  mBds := WithoutSlash(ABdsDir);
  if mBds = '' then
  begin
    Exit;
  end;
  AddDefault('BDS', mBds);
  AddDefault('BDSLIB', mBds + '\lib');
  AddDefault('BDSBIN', mBds + '\bin');
  AddDefault('BDSINCLUDE', mBds + '\include');
end;

procedure TAtlasPathMacros.AddProject(const AProject, APlatform, AConfig: string);
var
  mFolder, mFileName, mName, mNoRoot: string;
  mIndex: Integer;
begin
  Add('Platform', APlatform);
  Add('Config', AConfig);
  if Trim(AProject) = '' then
  begin
    Exit;
  end;
  mFolder := '';
  mFileName := Trim(AProject);
  for mIndex := Length(mFileName) downto 1 do
  begin
    if CharInSet(mFileName[mIndex], ['\', '/']) then
    begin
      mFolder := Copy(mFileName, 1, mIndex - 1);
      mFileName := Copy(mFileName, mIndex + 1, MaxInt);
      Break;
    end;
  end;
  mName := mFileName;
  for mIndex := Length(mName) downto 1 do
  begin
    if mName[mIndex] = '.' then
    begin
      mName := Copy(mName, 1, mIndex - 1);
      Break;
    end;
  end;
  // ProjectDir wie bei MSBuild ohne abschließenden Trenner; Combine verträgt doppelte „\“.
  Add('ProjectDir', mFolder);
  Add('ProjectPath', mFolder);
  Add('ProjectName', mName);
  Add('ProjectFilename', mFileName);
  Add('MSBuildProjectDirectory', mFolder);
  Add('MSBuildProjectName', mName);
  Add('MSBuildProjectFile', mFileName);
  Add('MSBuildProjectFullPath', Trim(AProject));
  Add('MSBuildThisFileDirectory', mFolder + '\');
  mNoRoot := mFolder;
  if (Length(mNoRoot) >= 2) and (mNoRoot[2] = ':') then
  begin
    Delete(mNoRoot, 1, 2);
  end;
  while (mNoRoot <> '') and CharInSet(mNoRoot[1], ['\', '/']) do
  begin
    Delete(mNoRoot, 1, 1);
  end;
  Add('MSBuildProjectDirectoryNoRoot', mNoRoot);
end;

function TAtlasPathMacros.Value(const AName: string): string;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AName);
  if mIndex >= 0 then
  begin
    Exit(FValues[mIndex]);
  end;
  Result := '';
  if Assigned(FEnvironment) and (Trim(AName) <> '') then
  begin
    Result := FEnvironment(Trim(AName));
  end;
end;

function TAtlasPathMacros.Variable: TAtlasPathVariable;
var
  mMacros: TAtlasPathMacros;
begin
  mMacros := Self;
  Result :=
    function(const AName: string): string
    begin
      Result := mMacros.Value(AName);
    end;
end;

{ TAtlasPathCheck }

class function TAtlasPathCheck.Scan(const AText: string; const ADefines: TArray<string>): TAtlasSourceScan;
begin
  Result := TAtlasPathScan.Scan(AText, ADefines);
end;

class function TAtlasPathCheck.Evaluate(const AExpression: string;
  const ADefines: TArray<string>): TAtlasBranchState;
begin
  Result := TAtlasPathScan.Evaluate(AExpression, ADefines);
end;

function IsAbsolute(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or APath.StartsWith('\') or APath.StartsWith('/');
end;

/// <summary>APath ohne „.“ und leere Teile, „..“ nimmt den Teil davor weg; Trenner „\“, ohne Rand.</summary>
function WithoutDots(const APath: string): string;
var
  mPart: string;
  mParts: TList<string>;
begin
  mParts := TList<string>.Create;
  try
    for mPart in APath.Split(['\']) do
    begin
      if (mPart = '..') and (mParts.Count > 0) then
      begin
        mParts.Delete(mParts.Count - 1);
      end
      else if (mPart <> '') and (mPart <> '.') and (mPart <> '..') then
      begin
        mParts.Add(mPart);
      end;
    end;
    Result := string.Join('\', mParts.ToArray);
  finally
    mParts.Free;
  end;
end;

class function TAtlasPathCheck.Combine(const AFolder, AName: string): string;
var
  mPath, mPrefix: string;
begin
  mPath := StringReplace(Trim(AName), '/', '\', [rfReplaceAll]);
  if not IsAbsolute(mPath) then
  begin
    mPrefix := StringReplace(Trim(AFolder), '/', '\', [rfReplaceAll]);
    if (mPrefix <> '') and not mPrefix.EndsWith('\') then
    begin
      mPrefix := mPrefix + '\';
    end;
    mPath := mPrefix + mPath;
  end;
  // Laufwerk bzw. \\Server bleibt vorn, der Rest wird aufgelöst.
  mPrefix := '';
  if (Length(mPath) >= 2) and (mPath[2] = ':') then
  begin
    mPrefix := Copy(mPath, 1, 2);
    Delete(mPath, 1, 2);
  end
  else if mPath.StartsWith('\\') then
  begin
    mPrefix := '\';
    Delete(mPath, 1, 1);
  end;
  Result := mPrefix + '\' + WithoutDots(mPath);
end;

class function TAtlasPathCheck.ExpandPath(const APath, ABaseDir: string; const AVariable: TAtlasPathVariable): string;
var
  mUnknown: string;
begin
  Result := ExpandPath(APath, ABaseDir, AVariable, mUnknown);
end;

class function TAtlasPathCheck.ExpandPath(const APath, ABaseDir: string; const AVariable: TAtlasPathVariable;
  out AUnknown: string): string;
var
  mText, mName, mValue: string;
  mOpen, mClose, mCount: Integer;
begin
  Result := '';
  AUnknown := '';
  mText := Trim(APath);
  if mText = '' then
  begin
    Exit;
  end;
  mCount := 0;
  mOpen := Pos('$(', mText);
  while mOpen > 0 do
  begin
    mClose := Pos(')', mText, mOpen + 2);
    if mClose = 0 then
    begin
      AUnknown := Copy(mText, mOpen + 2, MaxInt);
      Exit;
    end;
    mName := Trim(Copy(mText, mOpen + 2, mClose - mOpen - 2));
    mValue := '';
    Inc(mCount);
    if Assigned(AVariable) and (mCount <= MaxExpansions) then
    begin
      mValue := AVariable(mName);
    end;
    if mValue = '' then
    begin
      AUnknown := mName;
      Exit;
    end;
    // Ab derselben Stelle weiter: Der Wert kann selbst $(…) enthalten.
    mText := Copy(mText, 1, mOpen - 1) + mValue + Copy(mText, mClose + 1, MaxInt);
    mOpen := Pos('$(', mText, mOpen);
  end;
  Result := Combine(ABaseDir, mText);
  if Result.EndsWith('\') and (Length(Result) > 3) then
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TAtlasPathCheck.ExpandPaths(const ARaw: TArray<string>; const ABaseDir: string;
  const AVariable: TAtlasPathVariable; var ASkipped: TArray<string>): TArray<string>;
var
  mRaw, mPath, mUnknown, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mRaw in ARaw do
  begin
    mPath := ExpandPath(mRaw, ABaseDir, AVariable, mUnknown);
    if mPath <> '' then
    begin
      Result := Result + [mPath];
      Continue;
    end;
    if mUnknown = '' then
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in ASkipped do
    begin
      if SameText(mKnown, mUnknown) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      ASkipped := ASkipped + [mUnknown];
    end;
  end;
end;

class function TAtlasPathCheck.DprojDefines(const ADprojText: string): TArray<string>;
const
  cOpenTag = '<DCC_DEFINE>';
  cCloseTag = '</DCC_DEFINE>';
var
  mUpper, mItem: string;
  mStart, mStop: Integer;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  mUpper := UpperCase(ADprojText);
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mStart := Pos(cOpenTag, mUpper);
    while mStart > 0 do
    begin
      mStop := Pos(cCloseTag, mUpper, mStart);
      if mStop = 0 then
      begin
        Break;
      end;
      for mItem in Copy(ADprojText, mStart + Length(cOpenTag), mStop - mStart - Length(cOpenTag)).Split([';']) do
      begin
        if (Trim(mItem) <> '') and (Pos('$(', mItem) = 0) and not mSeen.ContainsKey(UpperCase(Trim(mItem))) then
        begin
          mSeen.Add(UpperCase(Trim(mItem)), True);
          Result := Result + [Trim(mItem)];
        end;
      end;
      mStart := Pos(cOpenTag, mUpper, mStop);
    end;
  finally
    mSeen.Free;
  end;
end;

class function TAtlasPathCheck.IsForeignSymbol(const AName: string): Boolean;
var
  mName: string;
begin
  for mName in cForeignSymbols do
  begin
    if SameText(mName, Trim(AName)) then
    begin
      Exit(True);
    end;
  end;
  for mName in cForeignPrefixes do
  begin
    if StartsText(mName, Trim(AName)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasPathCheck.DprojConfigDefines(const ADprojText, AConfig, APlatform: string): TArray<string>;
var
  mKeys: TArray<string>;
  mKey, mValue, mInherited_, mPart: string;
  mMatch: TMatch;

  function DefineOf(const AKey: string; out AValue: string): Boolean;
  var
    mGroup, mDefine: TMatch;
  begin
    // <PropertyGroup Condition="'$(Key)'!=''"> … <DCC_Define>…</DCC_Define>
    for mGroup in TRegEx.Matches(ADprojText, '<PropertyGroup\s+Condition="''\$\(' + AKey +
      '\)''!=''''"\s*>(.*?)</PropertyGroup>', [roIgnoreCase, roSingleLine]) do
    begin
      mDefine := TRegEx.Match(mGroup.Groups[1].Value, '<DCC_Define>(.*?)</DCC_Define>', [roIgnoreCase, roSingleLine]);
      if mDefine.Success then
      begin
        AValue := mDefine.Groups[1].Value;
        Exit(True);
      end;
    end;
    AValue := '';
    Result := False;
  end;

begin
  Result := nil;
  // Debug → Cfg_1: <BuildConfiguration Include="Debug"><Key>Cfg_1</Key>.
  mKey := '';
  mMatch := TRegEx.Match(ADprojText, '<BuildConfiguration\s+Include="' + TRegEx.Escape(AConfig) +
    '"\s*>\s*<Key>(\w+)</Key>', [roIgnoreCase]);
  if mMatch.Success then
  begin
    mKey := mMatch.Groups[1].Value;
  end;
  mKeys := ['Base'];
  if (mKey <> '') and not SameText(mKey, 'Base') then
  begin
    mKeys := mKeys + [mKey];
    if APlatform <> '' then
    begin
      mKeys := mKeys + [mKey + '_' + APlatform];
    end;
  end;
  mInherited_ := '';
  for mKey in mKeys do
  begin
    if DefineOf(mKey, mValue) then
    begin
      mInherited_ := StringReplace(mValue, '$(DCC_Define)', mInherited_, [rfReplaceAll, rfIgnoreCase]);
    end;
  end;
  for mPart in mInherited_.Split([';']) do
  begin
    if (Trim(mPart) <> '') and (Pos('$(', mPart) = 0) and (IndexText(Trim(mPart), Result) < 0) then
    begin
      Result := Result + [Trim(mPart)];
    end;
  end;
end;

class function TAtlasPathCheck.ScriptDefines(const AFileName, AText: string): TArray<string>;
var
  mMatch: TMatch;
  mPart, mExt: string;

  procedure Add(const AName: string);
  begin
    if (AName <> '') and (IndexText(AName, Result) < 0) then
    begin
      Result := Result + [AName];
    end;
  end;

begin
  Result := nil;
  // -dX auf der Kommandozeile (fpc -dX, dcc32 -DX); X beginnt mit Buchstabe oder _.
  for mMatch in TRegEx.Matches(AText, '(?<![\w-])-[dD]([A-Za-z_]\w*)') do
  begin
    Add(mMatch.Groups[1].Value);
  end;
  mExt := LowerCase(ExtractFileExt(AFileName));
  if (mExt = '.lpi') or (mExt = '.lpk') then
  begin
    for mMatch in TRegEx.Matches(AText, '<ConditionalDefines\s+Value="([^"]*)"', [roIgnoreCase]) do
    begin
      for mPart in mMatch.Groups[1].Value.Split([';', ',', ' ']) do
      begin
        Add(Trim(mPart));
      end;
    end;
  end;
end;

class function TAtlasPathCheck.Suggest(const AName: string; const AKnown: TArray<string>): string;

  function Distance(const A, B: string): Integer;
  var
    mRow, mPrev: TArray<Integer>;
    I, J, mCost: Integer;
  begin
    SetLength(mPrev, Length(B) + 1);
    SetLength(mRow, Length(B) + 1);
    for J := 0 to Length(B) do
    begin
      mPrev[J] := J;
    end;
    for I := 1 to Length(A) do
    begin
      mRow[0] := I;
      for J := 1 to Length(B) do
      begin
        mCost := Ord(UpCase(A[I]) <> UpCase(B[J]));
        mRow[J] := Min(Min(mRow[J - 1] + 1, mPrev[J] + 1), mPrev[J - 1] + mCost);
      end;
      mPrev := Copy(mRow);
    end;
    Result := mPrev[Length(B)];
  end;

var
  mKnown: string;
  mBest, mValue: Integer;
begin
  Result := '';
  // Kurze Namen (X, C) gleichen fast allem; erst ab vier Zeichen.
  if Length(Trim(AName)) < 4 then
  begin
    Exit;
  end;
  mBest := 3;
  for mKnown in AKnown do
  begin
    if (mKnown <> '') and not SameText(mKnown, AName) and (Abs(Length(mKnown) - Length(AName)) <= 2) then
    begin
      mValue := Distance(AName, mKnown);
      if mValue < mBest then
      begin
        mBest := mValue;
        Result := mKnown;
      end;
    end;
  end;
end;

{ Ablauf }

type
  TFolderCache = class
  private
    FList: TAtlasPathListFolder;
    FFolders: TObjectDictionary<string, TDictionary<string, Boolean>>;
  public
    constructor Create(const AList: TAtlasPathListFolder);
    destructor Destroy; override;
    function Has(const AFolder, AFileName: string): Boolean;
  end;

constructor TFolderCache.Create(const AList: TAtlasPathListFolder);
begin
  inherited Create;
  FList := AList;
  FFolders := TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
end;

destructor TFolderCache.Destroy;
begin
  FFolders.Free;
  inherited;
end;

function TFolderCache.Has(const AFolder, AFileName: string): Boolean;
var
  mKey, mName: string;
  mNames: TDictionary<string, Boolean>;
begin
  mKey := UpperCase(TAtlasPathCheck.Combine(AFolder, ''));
  if not FFolders.TryGetValue(mKey, mNames) then
  begin
    mNames := TDictionary<string, Boolean>.Create;
    if Assigned(FList) then
    begin
      for mName in FList(TAtlasPathCheck.Combine(AFolder, '')) do
      begin
        mNames.AddOrSetValue(UpperCase(mName), True);
      end;
    end;
    FFolders.Add(mKey, mNames);
  end;
  Result := mNames.ContainsKey(UpperCase(AFileName));
end;

type
  /// <summary>Eingebundene Datei, wie geschrieben, und der Ordner der einbindenden Datei.</summary>
  TIncludeRef = record
    Name: string;
    Folder: string;
  end;

  /// <summary>Abfrage eines Symbols und die Datei, in der sie steht.</summary>
  TSymbolAt = record
    FileName: string;
    Use: TAtlasSymbolUse;
  end;

function IncludeRef(const AName, AFolder: string): TIncludeRef;
begin
  Result.Name := AName;
  Result.Folder := AFolder;
end;

function SymbolAt(const AFileName: string; const AUse: TAtlasSymbolUse): TSymbolAt;
begin
  Result.FileName := AFileName;
  Result.Use := AUse;
end;

type
  /// <summary>Funde mit Index nach Name (groß): je Name ein Fund mit der ersten Stelle und der Zahl der
  /// Stellen.</summary>
  TFindingList = class
  private
    FItems: TList<TAtlasPathFinding>;
    FIndex: TDictionary<string, Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AName, AFileName: string; ALine: Integer; AUncertain: Boolean);
    function ToArray: TArray<TAtlasPathFinding>;
  end;

constructor TFindingList.Create;
begin
  inherited Create;
  FItems := TList<TAtlasPathFinding>.Create;
  FIndex := TDictionary<string, Integer>.Create;
end;

destructor TFindingList.Destroy;
begin
  FIndex.Free;
  FItems.Free;
  inherited;
end;

procedure TFindingList.Add(const AName, AFileName: string; ALine: Integer; AUncertain: Boolean);
var
  mKey: string;
  mIndex: Integer;
  mFinding: TAtlasPathFinding;
begin
  mKey := UpperCase(AName);
  if FIndex.TryGetValue(mKey, mIndex) then
  begin
    mFinding := FItems[mIndex];
    Inc(mFinding.Count);
    // Sicher, sobald eine Stelle sicher fehlt.
    mFinding.Uncertain := mFinding.Uncertain and AUncertain;
    FItems[mIndex] := mFinding;
    Exit;
  end;
  mFinding := Default(TAtlasPathFinding);
  mFinding.Uncertain := AUncertain;
  mFinding.Name := AName;
  mFinding.FileName := AFileName;
  mFinding.Line := ALine;
  mFinding.Count := 1;
  FIndex.Add(mKey, FItems.Count);
  FItems.Add(mFinding);
end;

function TFindingList.ToArray: TArray<TAtlasPathFinding>;
begin
  Result := FItems.ToArray;
end;

/// <summary>ANames groß und ohne Leerraum am Rand als Schlüssel in AKeys.</summary>
procedure AddKeys(AKeys: TDictionary<string, Boolean>; const ANames: TArray<string>);
var
  mName: string;
begin
  for mName in ANames do
  begin
    AKeys.AddOrSetValue(UpperCase(Trim(mName)), True);
  end;
end;

/// <summary>AName und AName mit jedem Namespace davor (SysUtils → System.SysUtils).</summary>
function UnitNames(const AName: string; const ANamespaces: TArray<string>): TArray<string>;
var
  mNamespace: string;
begin
  Result := [AName];
  for mNamespace in ANamespaces do
  begin
    if Trim(mNamespace) <> '' then
    begin
      Result := Result + [Trim(mNamespace) + '.' + AName];
    end;
  end;
end;

function InFolders(const AFolder: string; const AFolders: TArray<string>): Boolean;
var
  mEach: string;
begin
  for mEach in AFolders do
  begin
    if (Trim(mEach) <> '') and SameText(ExcludeTrailingPathDelimiter(mEach), ExcludeTrailingPathDelimiter(AFolder)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Ein Lauf von TAtlasPathCheck.Run mit seinem Zustand.</summary>
  TPathRun = class
  private
    FInput: TAtlasPathCheckInput;
    FRead: TAtlasPathReadText;
    FList: TAtlasPathListFolder;
    FCache: TFolderCache;
    FProjectDir: string;
    FProjectNames: TDictionary<string, Boolean>;
    FKnown: TDictionary<string, Boolean>;
    FVisited: TDictionary<string, Boolean>;
    FHintedPackages: TDictionary<string, Boolean>;
    /// <summary>Unit (groß) → requires-Package, aus dem sie kommt.</summary>
    FRequired: TDictionary<string, string>;
    FMissing: TFindingList;
    FUndefined: TFindingList;
    FHints: TList<TAtlasPathFinding>;
    /// <summary>Inhalt (groß) der .dcp von requires-Packages ohne Quelle (rtl, vcl, designide …): Unit-Namen stehen
    /// lesbar darin.</summary>
    FDcpTexts: TList<string>;
    FQueue: TList<TIncludeRef>;
    FUses: TList<TSymbolAt>;
    FSkipped: Boolean;
    FIncludeMissing: Boolean;
    FResult: TAtlasPathCheckResult;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Ordner der verwendenden Datei, Projektordner, Such- und Bibliothekspfade; ohne leere.</summary>
    function Folders(const AFrom: string): TArray<string>;
    /// <summary>Unit des Projekts, eines requires-Packages, einer .dcp oder System/SysInit.</summary>
    function IsKnownUnit(const AName: string): Boolean;
    function Resolves(const AUnit: TAtlasUsedUnit; const AFrom: string): Boolean;
    function FindInclude(const AName, AFrom: string; out APath: string): Boolean;
    procedure Hint(const APackage, AUnit, AFileName: string; ALine: Integer);
    /// <summary>Units eines requires-Packages der Projektgruppe als gefunden merken; ohne Quelle in der Gruppe ein
    /// Hinweis, wenn es nur als .dcp außerhalb der Bibliothekspfade liegt.</summary>
    procedure Require(const APackage: TAtlasUsedUnit; const AFrom: string);
    function RequireFromGroup(const APackage: TAtlasUsedUnit; const AFrom: string): Boolean;
    function RequireFromDcp(const APackage: string; const AFolders: TArray<string>): Boolean;
    procedure AddProduced;
    procedure AddRequires;
    procedure AddScriptDefines;
    procedure ScanSource(const ASource: string);
    procedure ScanIncludes;
    procedure CollectUndefined;
  public
    constructor Create(const AInput: TAtlasPathCheckInput; const ARead: TAtlasPathReadText;
      const AList: TAtlasPathListFolder);
    destructor Destroy; override;
    function Execute: TAtlasPathCheckResult;
  end;

constructor TPathRun.Create(const AInput: TAtlasPathCheckInput; const ARead: TAtlasPathReadText;
  const AList: TAtlasPathListFolder);
begin
  inherited Create;
  FInput := AInput;
  FRead := ARead;
  FList := AList;
  FSkipped := Length(AInput.SkippedMacros) > 0;
  FProjectDir := ExtractFileDir(TAtlasPathCheck.Combine('', AInput.Project));
  FCache := TFolderCache.Create(AList);
  FProjectNames := TDictionary<string, Boolean>.Create;
  FKnown := TDictionary<string, Boolean>.Create;
  FVisited := TDictionary<string, Boolean>.Create;
  FHintedPackages := TDictionary<string, Boolean>.Create;
  FRequired := TDictionary<string, string>.Create;
  FMissing := TFindingList.Create;
  FUndefined := TFindingList.Create;
  FHints := TList<TAtlasPathFinding>.Create;
  FDcpTexts := TList<string>.Create;
  FQueue := TList<TIncludeRef>.Create;
  FUses := TList<TSymbolAt>.Create;
end;

destructor TPathRun.Destroy;
begin
  FUses.Free;
  FQueue.Free;
  FDcpTexts.Free;
  FHints.Free;
  FUndefined.Free;
  FMissing.Free;
  FRequired.Free;
  FHintedPackages.Free;
  FVisited.Free;
  FKnown.Free;
  FProjectNames.Free;
  FCache.Free;
  inherited;
end;

function TPathRun.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(FRead) and FRead(AFileName, AText);
end;

function TPathRun.Folders(const AFrom: string): TArray<string>;
var
  mAll: TArray<string>;
  mDir: string;
begin
  mAll := [AFrom, FProjectDir] + FInput.SearchPaths + FInput.LibraryPaths;
  Result := nil;
  for mDir in mAll do
  begin
    if Trim(mDir) <> '' then
    begin
      Result := Result + [mDir];
    end;
  end;
end;

function TPathRun.IsKnownUnit(const AName: string): Boolean;
var
  mText: string;
begin
  Result := FProjectNames.ContainsKey(UpperCase(AName)) or FRequired.ContainsKey(UpperCase(AName)) or
    (IndexText(AName, cAlwaysThere) >= 0);
  if Result then
  begin
    Exit;
  end;
  for mText in FDcpTexts do
  begin
    if Pos(UpperCase(AName), mText) > 0 then
    begin
      Exit(True);
    end;
  end;
end;

function TPathRun.Resolves(const AUnit: TAtlasUsedUnit; const AFrom: string): Boolean;
var
  mNames: TArray<string>;
  mEach, mDir, mPath: string;
begin
  if AUnit.InFile <> '' then
  begin
    mPath := TAtlasPathCheck.Combine(AFrom, AUnit.InFile);
    Exit(FCache.Has(ExtractFileDir(mPath), ExtractFileName(mPath)));
  end;
  mNames := UnitNames(AUnit.Name, FInput.Namespaces);
  for mEach in mNames do
  begin
    if IsKnownUnit(mEach) then
    begin
      Exit(True);
    end;
  end;
  for mDir in Folders(AFrom) do
  begin
    for mEach in mNames do
    begin
      if FCache.Has(mDir, mEach + '.pas') or FCache.Has(mDir, mEach + '.dcu') then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TPathRun.FindInclude(const AName, AFrom: string; out APath: string): Boolean;
var
  mDir, mEach: string;
  mNames: TArray<string>;
begin
  mNames := [AName];
  if ExtractFileExt(AName) = '' then
  begin
    mNames := mNames + [AName + '.inc', AName + '.pas'];
  end;
  for mDir in Folders(AFrom) do
  begin
    for mEach in mNames do
    begin
      APath := TAtlasPathCheck.Combine(mDir, mEach);
      if FCache.Has(ExtractFileDir(APath), ExtractFileName(APath)) then
      begin
        Exit(True);
      end;
    end;
  end;
  APath := '';
  Result := False;
end;

procedure TPathRun.Hint(const APackage, AUnit, AFileName: string; ALine: Integer);
var
  mItem: TAtlasPathFinding;
begin
  // Ein Hinweis je Package.
  if FHintedPackages.ContainsKey(UpperCase(APackage)) then
  begin
    Exit;
  end;
  FHintedPackages.Add(UpperCase(APackage), True);
  mItem := Default(TAtlasPathFinding);
  mItem.Name := APackage;
  mItem.Note := AUnit;
  mItem.FileName := AFileName;
  mItem.Line := ALine;
  mItem.Count := 1;
  FHints.Add(mItem);
end;

function TPathRun.RequireFromGroup(const APackage: TAtlasUsedUnit; const AFrom: string): Boolean;
var
  mProject, mDpk, mPackageText: string;
  mContained: TAtlasSourceScan;
  mItem: TAtlasUsedUnit;
begin
  for mProject in FInput.GroupProjects do
  begin
    mDpk := ChangeFileExt(mProject, '.dpk');
    if SameText(ChangeFileExt(ExtractFileName(mProject), ''), APackage.Name) and ReadText(mDpk, mPackageText) then
    begin
      mContained := TAtlasPathCheck.Scan(mPackageText, FInput.ActiveDefines);
      for mItem in mContained.Units do
      begin
        FRequired.AddOrSetValue(UpperCase(mItem.Name), APackage.Name);
        // Quellordner des Packages zusätzlich im Suchpfad: doppelt gefunden, Hinweis.
        if (mItem.InFile <> '') and InFolders(ExtractFileDir(TAtlasPathCheck.Combine(ExtractFileDir(mDpk),
          mItem.InFile)), FInput.SearchPaths) then
        begin
          Hint(APackage.Name, mItem.Name, AFrom, APackage.Line);
        end;
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TPathRun.RequireFromDcp(const APackage: string; const AFolders: TArray<string>): Boolean;
var
  mDir, mPackageText: string;
begin
  for mDir in AFolders do
  begin
    if (Trim(mDir) <> '') and FCache.Has(mDir, APackage + '.dcp') then
    begin
      if ReadText(TAtlasPathCheck.Combine(mDir, APackage + '.dcp'), mPackageText) then
      begin
        FDcpTexts.Add(UpperCase(mPackageText));
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TPathRun.Require(const APackage: TAtlasUsedUnit; const AFrom: string);
var
  mOwn: TArray<string>;
begin
  if RequireFromGroup(APackage, AFrom) then
  begin
    Exit;
  end;
  // Nicht in der Gruppe: rtl, vcl … liegen als .dcp in den Bibliothekspfaden, das ist normal. Die .dcp nennt
  // ihre Units lesbar; sie gelten damit als gefunden (ToolsAPI aus designide).
  if RequireFromDcp(APackage.Name, FInput.LibraryPaths) then
  begin
    Exit;
  end;
  mOwn := [FProjectDir] + FInput.SearchPaths;
  if RequireFromDcp(APackage.Name, mOwn) then
  begin
    Hint(APackage.Name, '', AFrom, APackage.Line);
  end;
end;

procedure TPathRun.AddProduced;
var
  mSource, mText: string;
  mScanned: TAtlasSourceScan;
  mUsed: TAtlasUsedUnit;
begin
  // Units, die ein anderes Projekt der Gruppe in einen Ordner des Suchpfads übersetzt.
  for mSource in FInput.ProducedBy do
  begin
    if ReadText(ChangeFileExt(mSource, '.dpk'), mText) or ReadText(ChangeFileExt(mSource, '.dpr'), mText) then
    begin
      mScanned := TAtlasPathCheck.Scan(mText, FInput.ActiveDefines);
      for mUsed in mScanned.Units do
      begin
        FRequired.AddOrSetValue(UpperCase(mUsed.Name), ChangeFileExt(ExtractFileName(mSource), ''));
      end;
    end;
  end;
end;

procedure TPathRun.AddRequires;
var
  mSource, mText: string;
  mScanned: TAtlasSourceScan;
  mUsed: TAtlasUsedUnit;
begin
  // requires der Packages zuerst: Ihre Units sind beim Prüfen der uses schon bekannt.
  for mSource in FInput.Sources do
  begin
    if SameText(ExtractFileExt(mSource), '.dpk') and ReadText(mSource, mText) then
    begin
      mScanned := TAtlasPathCheck.Scan(mText, FInput.ActiveDefines);
      for mUsed in mScanned.Requires do
      begin
        if mUsed.State = TAtlasBranchState.Active then
        begin
          Require(mUsed, mSource);
        end;
      end;
    end;
  end;
end;

procedure TPathRun.AddScriptDefines;
var
  mFolder, mName, mText: string;
begin
  // Build-Skripte und Lazarus-Projekte: -dX und ConditionalDefines sind Quellen.
  for mFolder in FInput.ScriptFolders do
  begin
    if Trim(mFolder) = '' then
    begin
      Continue;
    end;
    for mName in FList(mFolder) do
    begin
      if (IndexText(ExtractFileExt(mName), cScriptExtensions) >= 0) and
        ReadText(TAtlasPathCheck.Combine(mFolder, mName), mText) then
      begin
        AddKeys(FKnown, TAtlasPathCheck.ScriptDefines(mName, mText));
      end;
    end;
  end;
end;

procedure TPathRun.ScanSource(const ASource: string);
var
  mText, mFolder, mInclude: string;
  mScanned: TAtlasSourceScan;
  mUsed: TAtlasUsedUnit;
  mUse: TAtlasSymbolUse;
begin
  if FVisited.ContainsKey(UpperCase(ASource)) then
  begin
    Exit;
  end;
  FVisited.Add(UpperCase(ASource), True);
  if not ReadText(ASource, mText) then
  begin
    Inc(FResult.Unreadable);
    Exit;
  end;
  Inc(FResult.Files);
  mFolder := ExtractFileDir(ASource);
  mScanned := TAtlasPathCheck.Scan(mText, FInput.ActiveDefines);
  for mUsed in mScanned.Units do
  begin
    if (mUsed.State = TAtlasBranchState.Active) and not Resolves(mUsed, mFolder) then
    begin
      // Mit "in 'Pfad'" zählt kein Suchpfad: dann sicher.
      FMissing.Add(mUsed.Name, ASource, mUsed.Line, FSkipped and (mUsed.InFile = ''));
    end;
  end;
  for mUse in mScanned.Referenced do
  begin
    FUses.Add(SymbolAt(ASource, mUse));
  end;
  AddKeys(FKnown, mScanned.Defined);
  for mInclude in mScanned.Includes do
  begin
    FQueue.Add(IncludeRef(mInclude, mFolder));
  end;
end;

procedure TPathRun.ScanIncludes;
var
  mIndex: Integer;
  mPair: TIncludeRef;
  mCandidate, mText, mInclude: string;
  mScanned: TAtlasSourceScan;
begin
  // Eingebundene Dateien nur nach $DEFINE durchsuchen.
  mIndex := 0;
  while (mIndex < FQueue.Count) and (mIndex < TAtlasPathCheck.MaxIncludes) do
  begin
    mPair := FQueue[mIndex];
    Inc(mIndex);
    if not FindInclude(mPair.Name, mPair.Folder, mCandidate) then
    begin
      FIncludeMissing := True;
      Continue;
    end;
    if FVisited.ContainsKey(UpperCase(mCandidate)) then
    begin
      Continue;
    end;
    FVisited.Add(UpperCase(mCandidate), True);
    if not ReadText(mCandidate, mText) then
    begin
      Continue;
    end;
    mScanned := TAtlasPathCheck.Scan(mText, FInput.ActiveDefines);
    AddKeys(FKnown, mScanned.Defined);
    for mInclude in mScanned.Includes do
    begin
      FQueue.Add(IncludeRef(mInclude, ExtractFileDir(mCandidate)));
    end;
  end;
end;

procedure TPathRun.CollectUndefined;
var
  mItem: TSymbolAt;
  mKnown: TArray<string>;
  mIndex: Integer;
begin
  for mItem in FUses do
  begin
    if not FKnown.ContainsKey(UpperCase(mItem.Use.Name)) and not TTextDefines.IsCompilerSymbol(mItem.Use.Name) and
      not TAtlasPathCheck.IsForeignSymbol(mItem.Use.Name) then
    begin
      // Fehlt eine eingebundene Datei und fiel ein Suchpfad weg, kann das $DEFINE dort stehen.
      FUndefined.Add(mItem.Use.Name, mItem.FileName, mItem.Use.Line, FSkipped and FIncludeMissing);
    end;
  end;
  FResult.UndefinedDefines := FUndefined.ToArray;
  // Tippfehler? Ein ähnlich geschriebenes bekanntes Symbol vorschlagen.
  mKnown := FKnown.Keys.ToArray;
  for mIndex := 0 to High(FResult.UndefinedDefines) do
  begin
    FResult.UndefinedDefines[mIndex].Note := TAtlasPathCheck.Suggest(FResult.UndefinedDefines[mIndex].Name, mKnown);
  end;
end;

function TPathRun.Execute: TAtlasPathCheckResult;
var
  mSource: string;
begin
  FResult := Default(TAtlasPathCheckResult);
  FResult.SkippedMacros := FInput.SkippedMacros;
  for mSource in FInput.Sources do
  begin
    FProjectNames.AddOrSetValue(UpperCase(ChangeFileExt(ExtractFileName(mSource), '')), True);
  end;
  AddKeys(FKnown, FInput.ActiveDefines + FInput.ProjectDefines);
  AddProduced;
  AddRequires;
  AddScriptDefines;
  for mSource in FInput.Sources do
  begin
    ScanSource(mSource);
  end;
  ScanIncludes;
  CollectUndefined;
  FResult.MissingUnits := FMissing.ToArray;
  FResult.Hints := FHints.ToArray;
  Result := FResult;
end;

class function TAtlasPathCheck.Run(const AInput: TAtlasPathCheckInput; const ARead: TAtlasPathReadText;
  const AList: TAtlasPathListFolder): TAtlasPathCheckResult;
var
  mCheck: TPathRun;
begin
  mCheck := TPathRun.Create(AInput, ARead, AList);
  try
    Result := mCheck.Execute;
  finally
    mCheck.Free;
  end;
end;

end.
