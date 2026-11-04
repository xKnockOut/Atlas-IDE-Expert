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
  ForeignSymbols: array[0..15] of string = ('FPC', 'CLR', 'KYLIX', 'LCL', 'DOTNET', 'UNIX', 'DARWIN', 'WINDOWS',
    'BSD', 'FREEBSD', 'HAIKU', 'WASI', 'EMBEDDED', 'IMPLICITBUILDING', 'TESTINSIGHT', 'CI');
  // Präfixe von Symbolen, die Free Pascal bzw. Lazarus je Ziel setzt (CPUX86_64, ENDIAN_BIG, FPC_FULLVERSION, LCLgtk2).
  ForeignPrefixes: array[0..3] of string = ('CPU', 'ENDIAN_', 'FPC_', 'LCL');
  ScriptExtensions: array[0..4] of string = ('.sh', '.cmd', '.bat', '.lpi', '.lpk');
  AlwaysThere: array[0..1] of string = ('SYSTEM', 'SYSINIT');

{ TAtlasPathCheckResult }

function TAtlasPathCheckResult.Clean: Boolean;
begin
  Result := (UncertainIn(MissingUnits) = Length(MissingUnits)) and
    (UncertainIn(UndefinedDefines) = Length(UndefinedDefines));
end;

class function TAtlasPathCheckResult.UncertainIn(const AFindings: TArray<TAtlasPathFinding>): Integer;
var
  Finding: TAtlasPathFinding;
begin
  Result := 0;
  for Finding in AFindings do
  begin
    if Finding.Uncertain then
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
  Index: Integer;
begin
  for Index := 0 to High(FNames) do
  begin
    if SameText(FNames[Index], Trim(AName)) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

procedure TAtlasPathMacros.Add(const AName, AValue: string);
var
  Index: Integer;
begin
  if (Trim(AName) = '') or (Trim(AValue) = '') then
  begin
    Exit;
  end;
  Index := IndexOf(AName);
  if Index >= 0 then
  begin
    FValues[Index] := AValue;
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
  Bds: string;
begin
  Bds := WithoutSlash(ABdsDir);
  if Bds = '' then
  begin
    Exit;
  end;
  AddDefault('BDS', Bds);
  AddDefault('BDSLIB', Bds + '\lib');
  AddDefault('BDSBIN', Bds + '\bin');
  AddDefault('BDSINCLUDE', Bds + '\include');
end;

procedure TAtlasPathMacros.AddProject(const AProject, APlatform, AConfig: string);
var
  Folder, FileName, Name, NoRoot: string;
  Index: Integer;
begin
  Add('Platform', APlatform);
  Add('Config', AConfig);
  if Trim(AProject) = '' then
  begin
    Exit;
  end;
  Folder := '';
  FileName := Trim(AProject);
  for Index := Length(FileName) downto 1 do
  begin
    if CharInSet(FileName[Index], ['\', '/']) then
    begin
      Folder := Copy(FileName, 1, Index - 1);
      FileName := Copy(FileName, Index + 1, MaxInt);
      Break;
    end;
  end;
  Name := FileName;
  for Index := Length(Name) downto 1 do
  begin
    if Name[Index] = '.' then
    begin
      Name := Copy(Name, 1, Index - 1);
      Break;
    end;
  end;
  // ProjectDir wie bei MSBuild ohne abschließenden Trenner; Combine verträgt doppelte „\“.
  Add('ProjectDir', Folder);
  Add('ProjectPath', Folder);
  Add('ProjectName', Name);
  Add('ProjectFilename', FileName);
  Add('MSBuildProjectDirectory', Folder);
  Add('MSBuildProjectName', Name);
  Add('MSBuildProjectFile', FileName);
  Add('MSBuildProjectFullPath', Trim(AProject));
  Add('MSBuildThisFileDirectory', Folder + '\');
  NoRoot := Folder;
  if (Length(NoRoot) >= 2) and (NoRoot[2] = ':') then
  begin
    Delete(NoRoot, 1, 2);
  end;
  while (NoRoot <> '') and CharInSet(NoRoot[1], ['\', '/']) do
  begin
    Delete(NoRoot, 1, 1);
  end;
  Add('MSBuildProjectDirectoryNoRoot', NoRoot);
end;

function TAtlasPathMacros.Value(const AName: string): string;
var
  Index: Integer;
begin
  Index := IndexOf(AName);
  if Index >= 0 then
  begin
    Exit(FValues[Index]);
  end;
  Result := '';
  if Assigned(FEnvironment) and (Trim(AName) <> '') then
  begin
    Result := FEnvironment(Trim(AName));
  end;
end;

function TAtlasPathMacros.Variable: TAtlasPathVariable;
var
  Macros: TAtlasPathMacros;
begin
  Macros := Self;
  Result :=
    function(const AName: string): string
    begin
      Result := Macros.Value(AName);
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
  Part: string;
  Parts: TList<string>;
begin
  Parts := TList<string>.Create;
  try
    for Part in APath.Split(['\']) do
    begin
      if (Part = '..') and (Parts.Count > 0) then
      begin
        Parts.Delete(Parts.Count - 1);
      end
      else if (Part <> '') and (Part <> '.') and (Part <> '..') then
      begin
        Parts.Add(Part);
      end;
    end;
    Result := string.Join('\', Parts.ToArray);
  finally
    Parts.Free;
  end;
end;

class function TAtlasPathCheck.Combine(const AFolder, AName: string): string;
var
  Path, Prefix: string;
begin
  Path := StringReplace(Trim(AName), '/', '\', [rfReplaceAll]);
  if not IsAbsolute(Path) then
  begin
    Prefix := StringReplace(Trim(AFolder), '/', '\', [rfReplaceAll]);
    if (Prefix <> '') and not Prefix.EndsWith('\') then
    begin
      Prefix := Prefix + '\';
    end;
    Path := Prefix + Path;
  end;
  // Laufwerk bzw. \\Server bleibt vorn, der Rest wird aufgelöst.
  Prefix := '';
  if (Length(Path) >= 2) and (Path[2] = ':') then
  begin
    Prefix := Copy(Path, 1, 2);
    Delete(Path, 1, 2);
  end
  else if Path.StartsWith('\\') then
  begin
    Prefix := '\';
    Delete(Path, 1, 1);
  end;
  Result := Prefix + '\' + WithoutDots(Path);
end;

class function TAtlasPathCheck.ExpandPath(const APath, ABaseDir: string; const AVariable: TAtlasPathVariable): string;
var
  Unknown: string;
begin
  Result := ExpandPath(APath, ABaseDir, AVariable, Unknown);
end;

class function TAtlasPathCheck.ExpandPath(const APath, ABaseDir: string; const AVariable: TAtlasPathVariable;
  out AUnknown: string): string;
var
  Text, Name, Value: string;
  Open, Close, Count: Integer;
begin
  Result := '';
  AUnknown := '';
  Text := Trim(APath);
  if Text = '' then
  begin
    Exit;
  end;
  Count := 0;
  Open := Pos('$(', Text);
  while Open > 0 do
  begin
    Close := Pos(')', Text, Open + 2);
    if Close = 0 then
    begin
      AUnknown := Copy(Text, Open + 2, MaxInt);
      Exit;
    end;
    Name := Trim(Copy(Text, Open + 2, Close - Open - 2));
    Value := '';
    Inc(Count);
    if Assigned(AVariable) and (Count <= MaxExpansions) then
    begin
      Value := AVariable(Name);
    end;
    if Value = '' then
    begin
      AUnknown := Name;
      Exit;
    end;
    // Ab derselben Stelle weiter: Der Wert kann selbst $(…) enthalten.
    Text := Copy(Text, 1, Open - 1) + Value + Copy(Text, Close + 1, MaxInt);
    Open := Pos('$(', Text, Open);
  end;
  Result := Combine(ABaseDir, Text);
  if Result.EndsWith('\') and (Length(Result) > 3) then
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TAtlasPathCheck.ExpandPaths(const ARaw: TArray<string>; const ABaseDir: string;
  const AVariable: TAtlasPathVariable; var ASkipped: TArray<string>): TArray<string>;
var
  Raw, Path, Unknown, Known: string;
  Seen: Boolean;
begin
  Result := nil;
  for Raw in ARaw do
  begin
    Path := ExpandPath(Raw, ABaseDir, AVariable, Unknown);
    if Path <> '' then
    begin
      Result := Result + [Path];
      Continue;
    end;
    if Unknown = '' then
    begin
      Continue;
    end;
    Seen := False;
    for Known in ASkipped do
    begin
      if SameText(Known, Unknown) then
      begin
        Seen := True;
      end;
    end;
    if not Seen then
    begin
      ASkipped := ASkipped + [Unknown];
    end;
  end;
end;

class function TAtlasPathCheck.DprojDefines(const ADprojText: string): TArray<string>;
const
  OpenTag = '<DCC_DEFINE>';
  CloseTag = '</DCC_DEFINE>';
var
  Upper, Item: string;
  Start, Stop: Integer;
  Seen: TDictionary<string, Boolean>;
begin
  Result := nil;
  Upper := UpperCase(ADprojText);
  Seen := TDictionary<string, Boolean>.Create;
  try
    Start := Pos(OpenTag, Upper);
    while Start > 0 do
    begin
      Stop := Pos(CloseTag, Upper, Start);
      if Stop = 0 then
      begin
        Break;
      end;
      for Item in Copy(ADprojText, Start + Length(OpenTag), Stop - Start - Length(OpenTag)).Split([';']) do
      begin
        if (Trim(Item) <> '') and (Pos('$(', Item) = 0) and not Seen.ContainsKey(UpperCase(Trim(Item))) then
        begin
          Seen.Add(UpperCase(Trim(Item)), True);
          Result := Result + [Trim(Item)];
        end;
      end;
      Start := Pos(OpenTag, Upper, Stop);
    end;
  finally
    Seen.Free;
  end;
end;

class function TAtlasPathCheck.IsForeignSymbol(const AName: string): Boolean;
var
  Name: string;
begin
  for Name in ForeignSymbols do
  begin
    if SameText(Name, Trim(AName)) then
    begin
      Exit(True);
    end;
  end;
  for Name in ForeignPrefixes do
  begin
    if StartsText(Name, Trim(AName)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasPathCheck.DprojConfigDefines(const ADprojText, AConfig, APlatform: string): TArray<string>;
var
  Keys: TArray<string>;
  Key, Value, Inherited_, Part: string;
  Match: TMatch;

  function DefineOf(const AKey: string; out AValue: string): Boolean;
  var
    Group, Define: TMatch;
  begin
    // <PropertyGroup Condition="'$(Key)'!=''"> … <DCC_Define>…</DCC_Define>
    for Group in TRegEx.Matches(ADprojText, '<PropertyGroup\s+Condition="''\$\(' + AKey +
      '\)''!=''''"\s*>(.*?)</PropertyGroup>', [roIgnoreCase, roSingleLine]) do
    begin
      Define := TRegEx.Match(Group.Groups[1].Value, '<DCC_Define>(.*?)</DCC_Define>', [roIgnoreCase, roSingleLine]);
      if Define.Success then
      begin
        AValue := Define.Groups[1].Value;
        Exit(True);
      end;
    end;
    AValue := '';
    Result := False;
  end;

begin
  Result := nil;
  // Debug → Cfg_1: <BuildConfiguration Include="Debug"><Key>Cfg_1</Key>.
  Key := '';
  Match := TRegEx.Match(ADprojText, '<BuildConfiguration\s+Include="' + TRegEx.Escape(AConfig) +
    '"\s*>\s*<Key>(\w+)</Key>', [roIgnoreCase]);
  if Match.Success then
  begin
    Key := Match.Groups[1].Value;
  end;
  Keys := ['Base'];
  if (Key <> '') and not SameText(Key, 'Base') then
  begin
    Keys := Keys + [Key];
    if APlatform <> '' then
    begin
      Keys := Keys + [Key + '_' + APlatform];
    end;
  end;
  Inherited_ := '';
  for Key in Keys do
  begin
    if DefineOf(Key, Value) then
    begin
      Inherited_ := StringReplace(Value, '$(DCC_Define)', Inherited_, [rfReplaceAll, rfIgnoreCase]);
    end;
  end;
  for Part in Inherited_.Split([';']) do
  begin
    if (Trim(Part) <> '') and (Pos('$(', Part) = 0) and (IndexText(Trim(Part), Result) < 0) then
    begin
      Result := Result + [Trim(Part)];
    end;
  end;
end;

class function TAtlasPathCheck.ScriptDefines(const AFileName, AText: string): TArray<string>;
var
  Match: TMatch;
  Part, Ext: string;

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
  for Match in TRegEx.Matches(AText, '(?<![\w-])-[dD]([A-Za-z_]\w*)') do
  begin
    Add(Match.Groups[1].Value);
  end;
  Ext := LowerCase(ExtractFileExt(AFileName));
  if (Ext = '.lpi') or (Ext = '.lpk') then
  begin
    for Match in TRegEx.Matches(AText, '<ConditionalDefines\s+Value="([^"]*)"', [roIgnoreCase]) do
    begin
      for Part in Match.Groups[1].Value.Split([';', ',', ' ']) do
      begin
        Add(Trim(Part));
      end;
    end;
  end;
end;

class function TAtlasPathCheck.Suggest(const AName: string; const AKnown: TArray<string>): string;

  function Distance(const A, B: string): Integer;
  var
    Row, Prev: TArray<Integer>;
    I, J, Cost: Integer;
  begin
    SetLength(Prev, Length(B) + 1);
    SetLength(Row, Length(B) + 1);
    for J := 0 to Length(B) do
    begin
      Prev[J] := J;
    end;
    for I := 1 to Length(A) do
    begin
      Row[0] := I;
      for J := 1 to Length(B) do
      begin
        Cost := Ord(UpCase(A[I]) <> UpCase(B[J]));
        Row[J] := Min(Min(Row[J - 1] + 1, Prev[J] + 1), Prev[J - 1] + Cost);
      end;
      Prev := Copy(Row);
    end;
    Result := Prev[Length(B)];
  end;

var
  Known: string;
  Best, Value: Integer;
begin
  Result := '';
  // Kurze Namen (X, C) gleichen fast allem; erst ab vier Zeichen.
  if Length(Trim(AName)) < 4 then
  begin
    Exit;
  end;
  Best := 3;
  for Known in AKnown do
  begin
    if (Known <> '') and not SameText(Known, AName) and (Abs(Length(Known) - Length(AName)) <= 2) then
    begin
      Value := Distance(AName, Known);
      if Value < Best then
      begin
        Best := Value;
        Result := Known;
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
  Key, Name: string;
  Names: TDictionary<string, Boolean>;
begin
  Key := UpperCase(TAtlasPathCheck.Combine(AFolder, ''));
  if not FFolders.TryGetValue(Key, Names) then
  begin
    Names := TDictionary<string, Boolean>.Create;
    if Assigned(FList) then
    begin
      for Name in FList(TAtlasPathCheck.Combine(AFolder, '')) do
      begin
        Names.AddOrSetValue(UpperCase(Name), True);
      end;
    end;
    FFolders.Add(Key, Names);
  end;
  Result := Names.ContainsKey(UpperCase(AFileName));
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
  Key: string;
  Index: Integer;
  Finding: TAtlasPathFinding;
begin
  Key := UpperCase(AName);
  if FIndex.TryGetValue(Key, Index) then
  begin
    Finding := FItems[Index];
    Inc(Finding.Count);
    // Sicher, sobald eine Stelle sicher fehlt.
    Finding.Uncertain := Finding.Uncertain and AUncertain;
    FItems[Index] := Finding;
    Exit;
  end;
  Finding := Default(TAtlasPathFinding);
  Finding.Uncertain := AUncertain;
  Finding.Name := AName;
  Finding.FileName := AFileName;
  Finding.Line := ALine;
  Finding.Count := 1;
  FIndex.Add(Key, FItems.Count);
  FItems.Add(Finding);
end;

function TFindingList.ToArray: TArray<TAtlasPathFinding>;
begin
  Result := FItems.ToArray;
end;

/// <summary>ANames groß und ohne Leerraum am Rand als Schlüssel in AKeys.</summary>
procedure AddKeys(AKeys: TDictionary<string, Boolean>; const ANames: TArray<string>);
var
  Name: string;
begin
  for Name in ANames do
  begin
    AKeys.AddOrSetValue(UpperCase(Trim(Name)), True);
  end;
end;

/// <summary>AName und AName mit jedem Namespace davor (SysUtils → System.SysUtils).</summary>
function UnitNames(const AName: string; const ANamespaces: TArray<string>): TArray<string>;
var
  Namespace: string;
begin
  Result := [AName];
  for Namespace in ANamespaces do
  begin
    if Trim(Namespace) <> '' then
    begin
      Result := Result + [Trim(Namespace) + '.' + AName];
    end;
  end;
end;

function InFolders(const AFolder: string; const AFolders: TArray<string>): Boolean;
var
  Each: string;
begin
  for Each in AFolders do
  begin
    if (Trim(Each) <> '') and SameText(ExcludeTrailingPathDelimiter(Each), ExcludeTrailingPathDelimiter(AFolder)) then
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
  All: TArray<string>;
  Dir: string;
begin
  All := [AFrom, FProjectDir] + FInput.SearchPaths + FInput.LibraryPaths;
  Result := nil;
  for Dir in All do
  begin
    if Trim(Dir) <> '' then
    begin
      Result := Result + [Dir];
    end;
  end;
end;

function TPathRun.IsKnownUnit(const AName: string): Boolean;
var
  Text: string;
begin
  Result := FProjectNames.ContainsKey(UpperCase(AName)) or FRequired.ContainsKey(UpperCase(AName)) or
    (IndexText(AName, AlwaysThere) >= 0);
  if Result then
  begin
    Exit;
  end;
  for Text in FDcpTexts do
  begin
    if Pos(UpperCase(AName), Text) > 0 then
    begin
      Exit(True);
    end;
  end;
end;

function TPathRun.Resolves(const AUnit: TAtlasUsedUnit; const AFrom: string): Boolean;
var
  Names: TArray<string>;
  Each, Dir, Path: string;
begin
  if AUnit.InFile <> '' then
  begin
    Path := TAtlasPathCheck.Combine(AFrom, AUnit.InFile);
    Exit(FCache.Has(ExtractFileDir(Path), ExtractFileName(Path)));
  end;
  Names := UnitNames(AUnit.Name, FInput.Namespaces);
  for Each in Names do
  begin
    if IsKnownUnit(Each) then
    begin
      Exit(True);
    end;
  end;
  for Dir in Folders(AFrom) do
  begin
    for Each in Names do
    begin
      if FCache.Has(Dir, Each + '.pas') or FCache.Has(Dir, Each + '.dcu') then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TPathRun.FindInclude(const AName, AFrom: string; out APath: string): Boolean;
var
  Dir, Each: string;
  Names: TArray<string>;
begin
  Names := [AName];
  if ExtractFileExt(AName) = '' then
  begin
    Names := Names + [AName + '.inc', AName + '.pas'];
  end;
  for Dir in Folders(AFrom) do
  begin
    for Each in Names do
    begin
      APath := TAtlasPathCheck.Combine(Dir, Each);
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
  Item: TAtlasPathFinding;
begin
  // Ein Hinweis je Package.
  if FHintedPackages.ContainsKey(UpperCase(APackage)) then
  begin
    Exit;
  end;
  FHintedPackages.Add(UpperCase(APackage), True);
  Item := Default(TAtlasPathFinding);
  Item.Name := APackage;
  Item.Note := AUnit;
  Item.FileName := AFileName;
  Item.Line := ALine;
  Item.Count := 1;
  FHints.Add(Item);
end;

function TPathRun.RequireFromGroup(const APackage: TAtlasUsedUnit; const AFrom: string): Boolean;
var
  Project, Dpk, PackageText: string;
  Contained: TAtlasSourceScan;
  Item: TAtlasUsedUnit;
begin
  for Project in FInput.GroupProjects do
  begin
    Dpk := ChangeFileExt(Project, '.dpk');
    if SameText(ChangeFileExt(ExtractFileName(Project), ''), APackage.Name) and ReadText(Dpk, PackageText) then
    begin
      Contained := TAtlasPathCheck.Scan(PackageText, FInput.ActiveDefines);
      for Item in Contained.Units do
      begin
        FRequired.AddOrSetValue(UpperCase(Item.Name), APackage.Name);
        // Quellordner des Packages zusätzlich im Suchpfad: doppelt gefunden, Hinweis.
        if (Item.InFile <> '') and InFolders(ExtractFileDir(TAtlasPathCheck.Combine(ExtractFileDir(Dpk),
          Item.InFile)), FInput.SearchPaths) then
        begin
          Hint(APackage.Name, Item.Name, AFrom, APackage.Line);
        end;
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TPathRun.RequireFromDcp(const APackage: string; const AFolders: TArray<string>): Boolean;
var
  Dir, PackageText: string;
begin
  for Dir in AFolders do
  begin
    if (Trim(Dir) <> '') and FCache.Has(Dir, APackage + '.dcp') then
    begin
      if ReadText(TAtlasPathCheck.Combine(Dir, APackage + '.dcp'), PackageText) then
      begin
        FDcpTexts.Add(UpperCase(PackageText));
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TPathRun.Require(const APackage: TAtlasUsedUnit; const AFrom: string);
var
  Own: TArray<string>;
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
  Own := [FProjectDir] + FInput.SearchPaths;
  if RequireFromDcp(APackage.Name, Own) then
  begin
    Hint(APackage.Name, '', AFrom, APackage.Line);
  end;
end;

procedure TPathRun.AddProduced;
var
  Source, Text: string;
  Scanned: TAtlasSourceScan;
  Used: TAtlasUsedUnit;
begin
  // Units, die ein anderes Projekt der Gruppe in einen Ordner des Suchpfads übersetzt.
  for Source in FInput.ProducedBy do
  begin
    if ReadText(ChangeFileExt(Source, '.dpk'), Text) or ReadText(ChangeFileExt(Source, '.dpr'), Text) then
    begin
      Scanned := TAtlasPathCheck.Scan(Text, FInput.ActiveDefines);
      for Used in Scanned.Units do
      begin
        FRequired.AddOrSetValue(UpperCase(Used.Name), ChangeFileExt(ExtractFileName(Source), ''));
      end;
    end;
  end;
end;

procedure TPathRun.AddRequires;
var
  Source, Text: string;
  Scanned: TAtlasSourceScan;
  Used: TAtlasUsedUnit;
begin
  // requires der Packages zuerst: Ihre Units sind beim Prüfen der uses schon bekannt.
  for Source in FInput.Sources do
  begin
    if SameText(ExtractFileExt(Source), '.dpk') and ReadText(Source, Text) then
    begin
      Scanned := TAtlasPathCheck.Scan(Text, FInput.ActiveDefines);
      for Used in Scanned.Requires do
      begin
        if Used.State = TAtlasBranchState.Active then
        begin
          Require(Used, Source);
        end;
      end;
    end;
  end;
end;

procedure TPathRun.AddScriptDefines;
var
  Folder, Name, Text: string;
begin
  // Build-Skripte und Lazarus-Projekte: -dX und ConditionalDefines sind Quellen.
  for Folder in FInput.ScriptFolders do
  begin
    if Trim(Folder) = '' then
    begin
      Continue;
    end;
    for Name in FList(Folder) do
    begin
      if (IndexText(ExtractFileExt(Name), ScriptExtensions) >= 0) and
        ReadText(TAtlasPathCheck.Combine(Folder, Name), Text) then
      begin
        AddKeys(FKnown, TAtlasPathCheck.ScriptDefines(Name, Text));
      end;
    end;
  end;
end;

procedure TPathRun.ScanSource(const ASource: string);
var
  Text, Folder, Include: string;
  Scanned: TAtlasSourceScan;
  Used: TAtlasUsedUnit;
  Use: TAtlasSymbolUse;
begin
  if FVisited.ContainsKey(UpperCase(ASource)) then
  begin
    Exit;
  end;
  FVisited.Add(UpperCase(ASource), True);
  if not ReadText(ASource, Text) then
  begin
    Inc(FResult.Unreadable);
    Exit;
  end;
  Inc(FResult.Files);
  Folder := ExtractFileDir(ASource);
  Scanned := TAtlasPathCheck.Scan(Text, FInput.ActiveDefines);
  for Used in Scanned.Units do
  begin
    if (Used.State = TAtlasBranchState.Active) and not Resolves(Used, Folder) then
    begin
      // Mit "in 'Pfad'" zählt kein Suchpfad: dann sicher.
      FMissing.Add(Used.Name, ASource, Used.Line, FSkipped and (Used.InFile = ''));
    end;
  end;
  for Use in Scanned.Referenced do
  begin
    FUses.Add(SymbolAt(ASource, Use));
  end;
  AddKeys(FKnown, Scanned.Defined);
  for Include in Scanned.Includes do
  begin
    FQueue.Add(IncludeRef(Include, Folder));
  end;
end;

procedure TPathRun.ScanIncludes;
var
  Index: Integer;
  Pair: TIncludeRef;
  Candidate, Text, Include: string;
  Scanned: TAtlasSourceScan;
begin
  // Eingebundene Dateien nur nach $DEFINE durchsuchen.
  Index := 0;
  while (Index < FQueue.Count) and (Index < TAtlasPathCheck.MaxIncludes) do
  begin
    Pair := FQueue[Index];
    Inc(Index);
    if not FindInclude(Pair.Name, Pair.Folder, Candidate) then
    begin
      FIncludeMissing := True;
      Continue;
    end;
    if FVisited.ContainsKey(UpperCase(Candidate)) then
    begin
      Continue;
    end;
    FVisited.Add(UpperCase(Candidate), True);
    if not ReadText(Candidate, Text) then
    begin
      Continue;
    end;
    Scanned := TAtlasPathCheck.Scan(Text, FInput.ActiveDefines);
    AddKeys(FKnown, Scanned.Defined);
    for Include in Scanned.Includes do
    begin
      FQueue.Add(IncludeRef(Include, ExtractFileDir(Candidate)));
    end;
  end;
end;

procedure TPathRun.CollectUndefined;
var
  Item: TSymbolAt;
  Known: TArray<string>;
  Index: Integer;
begin
  for Item in FUses do
  begin
    if not FKnown.ContainsKey(UpperCase(Item.Use.Name)) and not TTextDefines.IsCompilerSymbol(Item.Use.Name) and
      not TAtlasPathCheck.IsForeignSymbol(Item.Use.Name) then
    begin
      // Fehlt eine eingebundene Datei und fiel ein Suchpfad weg, kann das $DEFINE dort stehen.
      FUndefined.Add(Item.Use.Name, Item.FileName, Item.Use.Line, FSkipped and FIncludeMissing);
    end;
  end;
  FResult.UndefinedDefines := FUndefined.ToArray;
  // Tippfehler? Ein ähnlich geschriebenes bekanntes Symbol vorschlagen.
  Known := FKnown.Keys.ToArray;
  for Index := 0 to High(FResult.UndefinedDefines) do
  begin
    FResult.UndefinedDefines[Index].Note := TAtlasPathCheck.Suggest(FResult.UndefinedDefines[Index].Name, Known);
  end;
end;

function TPathRun.Execute: TAtlasPathCheckResult;
var
  Source: string;
begin
  FResult := Default(TAtlasPathCheckResult);
  FResult.SkippedMacros := FInput.SkippedMacros;
  for Source in FInput.Sources do
  begin
    FProjectNames.AddOrSetValue(UpperCase(ChangeFileExt(ExtractFileName(Source), '')), True);
  end;
  AddKeys(FKnown, FInput.ActiveDefines + FInput.ProjectDefines);
  AddProduced;
  AddRequires;
  AddScriptDefines;
  for Source in FInput.Sources do
  begin
    ScanSource(Source);
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
  Check: TPathRun;
begin
  Check := TPathRun.Create(AInput, ARead, AList);
  try
    Result := Check.Execute;
  finally
    Check.Free;
  end;
end;

end.
