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
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Stand eines Zweigs: gilt, gilt nicht, oder die Bedingung ließ sich nicht auswerten.</summary>
  TAtlasBranchState = (Active, Inactive, Unknown);
{$SCOPEDENUMS OFF}

  TAtlasUsedUnit = record
    /// <summary>Name wie geschrieben, z. B. "System.SysUtils".</summary>
    Name: string;
    /// <summary>Pfad aus "in 'Pfad'"; '' ohne.</summary>
    InFile: string;
    /// <summary>Zeile ab 1.</summary>
    Line: Integer;
    State: TAtlasBranchState;
  end;

  TAtlasSymbolUse = record
    Name: string;
    Line: Integer;
  end;

  TAtlasSourceScan = record
    /// <summary>Paket (.dpk): contains zählt wie uses.</summary>
    IsPackage: Boolean;
    Units: TArray<TAtlasUsedUnit>;
    /// <summary>Symbole aus $IFDEF, $IFNDEF und DEFINED(…), auch in inaktiven Zweigen.</summary>
    Referenced: TArray<TAtlasSymbolUse>;
    /// <summary>Symbole aus $DEFINE, auch in inaktiven Zweigen (gesetzt in irgendeiner Konfiguration).</summary>
    Defined: TArray<string>;
    /// <summary>Dateinamen aus $I und $INCLUDE, wie geschrieben.</summary>
    Includes: TArray<string>;
  end;

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
  end;

  TAtlasPathCheckResult = record
    /// <summary>Gelesene Dateien des Projekts.</summary>
    Files: Integer;
    /// <summary>Nicht lesbare Dateien des Projekts.</summary>
    Unreadable: Integer;
    MissingUnits: TArray<TAtlasPathFinding>;
    UndefinedDefines: TArray<TAtlasPathFinding>;
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
    /// <summary>Symbole anderer Compiler, die Delphi-Code oft abfragt (FPC …).</summary>
    class function IsForeignSymbol(const AName: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Chars,
  Atlas.Text.Defines;

const
  ForeignSymbols: array[0..4] of string = ('FPC', 'CLR', 'KYLIX', 'LCL', 'DOTNET');
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
    if Finding.Uncertain then
      Inc(Result);
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
    if SameText(FNames[Index], Trim(AName)) then
      Exit(Index);
  Result := -1;
end;

procedure TAtlasPathMacros.Add(const AName, AValue: string);
var
  Index: Integer;
begin
  if (Trim(AName) = '') or (Trim(AValue) = '') then
    Exit;
  Index := IndexOf(AName);
  if Index >= 0 then
    FValues[Index] := AValue
  else
  begin
    FNames := FNames + [Trim(AName)];
    FValues := FValues + [AValue];
  end;
end;

procedure TAtlasPathMacros.AddDefault(const AName, AValue: string);
begin
  if IndexOf(AName) < 0 then
    Add(AName, AValue);
end;

function WithoutSlash(const AFolder: string): string;
begin
  Result := Trim(AFolder);
  while (Length(Result) > 3) and CharInSet(Result[Length(Result)], ['\', '/']) do
    Delete(Result, Length(Result), 1);
end;

procedure TAtlasPathMacros.AddBds(const ABdsDir: string);
var
  Bds: string;
begin
  Bds := WithoutSlash(ABdsDir);
  if Bds = '' then
    Exit;
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
    Exit;
  Folder := '';
  FileName := Trim(AProject);
  for Index := Length(FileName) downto 1 do
    if CharInSet(FileName[Index], ['\', '/']) then
    begin
      Folder := Copy(FileName, 1, Index - 1);
      FileName := Copy(FileName, Index + 1, MaxInt);
      Break;
    end;
  Name := FileName;
  for Index := Length(Name) downto 1 do
    if Name[Index] = '.' then
    begin
      Name := Copy(Name, 1, Index - 1);
      Break;
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
    Delete(NoRoot, 1, 2);
  while (NoRoot <> '') and CharInSet(NoRoot[1], ['\', '/']) do
    Delete(NoRoot, 1, 1);
  Add('MSBuildProjectDirectoryNoRoot', NoRoot);
end;

function TAtlasPathMacros.Value(const AName: string): string;
var
  Index: Integer;
begin
  Index := IndexOf(AName);
  if Index >= 0 then
    Exit(FValues[Index]);
  Result := '';
  if Assigned(FEnvironment) and (Trim(AName) <> '') then
    Result := FEnvironment(Trim(AName));
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

{ Bedingungen }

type
  TBranch = record
    State: TAtlasBranchState;
    /// <summary>Ein Zweig galt sicher.</summary>
    Taken: Boolean;
    /// <summary>Ein Zweig war unbekannt: Spätere können nicht mehr sicher gelten.</summary>
    Unsure: Boolean;
    Parent: TAtlasBranchState;
  end;

  TExpressionParser = class
  private
    FTokens: TArray<string>;
    FPos: Integer;
    FDefines: TDictionary<string, Boolean>;
    FFailed: Boolean;
    function Peek: string;
    function Next: string;
    function ParseOr: TAtlasBranchState;
    function ParseAnd: TAtlasBranchState;
    function ParseUnary: TAtlasBranchState;
  public
    constructor Create(const AExpression: string; ADefines: TDictionary<string, Boolean>);
    function Parse: TAtlasBranchState;
  end;

function Tokenize(const AText: string): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Index := 1;
  while Index <= Length(AText) do
  begin
    if CharInSet(AText[Index], [' ', #9, #10, #13]) then
      Inc(Index)
    else if TTextChars.IsIdentStart(AText[Index]) then
    begin
      Start := Index;
      while (Index <= Length(AText)) and TTextChars.IsIdentChar(AText[Index]) do
        Inc(Index);
      Result := Result + [Copy(AText, Start, Index - Start)];
    end
    else
    begin
      Result := Result + [AText[Index]];
      Inc(Index);
    end;
  end;
end;

function StateOf(AValue: Boolean): TAtlasBranchState;
begin
  if AValue then
    Result := TAtlasBranchState.Active
  else
    Result := TAtlasBranchState.Inactive;
end;

constructor TExpressionParser.Create(const AExpression: string; ADefines: TDictionary<string, Boolean>);
begin
  inherited Create;
  FTokens := Tokenize(AExpression);
  FDefines := ADefines;
end;

function TExpressionParser.Peek: string;
begin
  Result := '';
  if FPos <= High(FTokens) then
    Result := FTokens[FPos];
end;

function TExpressionParser.Next: string;
begin
  Result := Peek;
  Inc(FPos);
end;

function TExpressionParser.Parse: TAtlasBranchState;
begin
  FPos := 0;
  FFailed := False;
  Result := ParseOr;
  if FFailed or (FPos <= High(FTokens)) then
    Result := TAtlasBranchState.Unknown;
end;

function TExpressionParser.ParseOr: TAtlasBranchState;
var
  Right: TAtlasBranchState;
begin
  Result := ParseAnd;
  while SameText(Peek, 'or') do
  begin
    Next;
    Right := ParseAnd;
    if (Result = TAtlasBranchState.Active) or (Right = TAtlasBranchState.Active) then
      Result := TAtlasBranchState.Active
    else if (Result = TAtlasBranchState.Unknown) or (Right = TAtlasBranchState.Unknown) then
      Result := TAtlasBranchState.Unknown
    else
      Result := TAtlasBranchState.Inactive;
  end;
end;

function TExpressionParser.ParseAnd: TAtlasBranchState;
var
  Right: TAtlasBranchState;
begin
  Result := ParseUnary;
  while SameText(Peek, 'and') do
  begin
    Next;
    Right := ParseUnary;
    if (Result = TAtlasBranchState.Inactive) or (Right = TAtlasBranchState.Inactive) then
      Result := TAtlasBranchState.Inactive
    else if (Result = TAtlasBranchState.Unknown) or (Right = TAtlasBranchState.Unknown) then
      Result := TAtlasBranchState.Unknown
    else
      Result := TAtlasBranchState.Active;
  end;
end;

function TExpressionParser.ParseUnary: TAtlasBranchState;
var
  Token, Name: string;
begin
  Token := Next;
  if SameText(Token, 'not') then
  begin
    Result := ParseUnary;
    if Result = TAtlasBranchState.Active then
      Result := TAtlasBranchState.Inactive
    else if Result = TAtlasBranchState.Inactive then
      Result := TAtlasBranchState.Active;
    Exit;
  end;
  if Token = '(' then
  begin
    Result := ParseOr;
    if Next <> ')' then
      FFailed := True;
    Exit;
  end;
  if SameText(Token, 'defined') and (Peek = '(') then
  begin
    Next;
    Name := Next;
    if (Name = '') or not TTextChars.IsIdentStart(Name[1]) or (Next <> ')') then
    begin
      FFailed := True;
      Exit(TAtlasBranchState.Unknown);
    end;
    Exit(StateOf(FDefines.ContainsKey(UpperCase(Name))));
  end;
  // CompilerVersion, Declared(…), SizeOf, Zahlen, Vergleiche: nicht auswertbar.
  FFailed := True;
  Result := TAtlasBranchState.Unknown;
end;

{ Scanner }

type
{$SCOPEDENUMS ON}
  TUsesState = (None, ExpectName, NamePart, AfterName, ExpectPath);
{$SCOPEDENUMS OFF}

  TScanner = class
  private
    FText: string;
    FPos: Integer;
    FLine: Integer;
    FDefines: TDictionary<string, Boolean>;
    FStack: TList<TBranch>;
    FResult: TAtlasSourceScan;
    FUses: TUsesState;
    FPending: TAtlasUsedUnit;
    FFirstWord: Boolean;
    function Current: TAtlasBranchState;
    procedure Push(ACondition: TAtlasBranchState);
    procedure ElseIf(ACondition: TAtlasBranchState);
    procedure Pop;
    procedure Directive(const AText: string; ALine: Integer);
    procedure Reference(const AName: string; ALine: Integer);
    procedure ReferenceAll(const AExpression: string; ALine: Integer);
    procedure Word(const AWord: string; ALine: Integer);
    procedure Symbol(AChar: Char);
    procedure StringLiteral(const AValue: string);
    procedure Commit;
    procedure CountLines(AFrom, ATo: Integer);
  public
    constructor Create(const AText: string; const ADefines: TArray<string>);
    destructor Destroy; override;
    function Run: TAtlasSourceScan;
  end;

constructor TScanner.Create(const AText: string; const ADefines: TArray<string>);
var
  Name: string;
begin
  inherited Create;
  FText := AText;
  FDefines := TDictionary<string, Boolean>.Create;
  for Name in ADefines do
    if Trim(Name) <> '' then
      FDefines.AddOrSetValue(UpperCase(Trim(Name)), True);
  FStack := TList<TBranch>.Create;
  FFirstWord := True;
end;

destructor TScanner.Destroy;
begin
  FStack.Free;
  FDefines.Free;
  inherited;
end;

function TScanner.Current: TAtlasBranchState;
begin
  if FStack.Count = 0 then
    Result := TAtlasBranchState.Active
  else
    Result := FStack.Last.State;
end;

procedure TScanner.Push(ACondition: TAtlasBranchState);
var
  Branch: TBranch;
begin
  Branch := Default(TBranch);
  Branch.Parent := Current;
  case Branch.Parent of
    TAtlasBranchState.Inactive:
      begin
        Branch.State := TAtlasBranchState.Inactive;
        // Kein Zweig darunter kann gelten.
        Branch.Taken := True;
      end;
    TAtlasBranchState.Unknown:
      begin
        if ACondition = TAtlasBranchState.Inactive then
          Branch.State := TAtlasBranchState.Inactive
        else
          Branch.State := TAtlasBranchState.Unknown;
        Branch.Taken := ACondition = TAtlasBranchState.Active;
        Branch.Unsure := ACondition = TAtlasBranchState.Unknown;
      end;
  else
    Branch.State := ACondition;
    Branch.Taken := ACondition = TAtlasBranchState.Active;
    Branch.Unsure := ACondition = TAtlasBranchState.Unknown;
  end;
  FStack.Add(Branch);
end;

procedure TScanner.ElseIf(ACondition: TAtlasBranchState);
var
  Branch: TBranch;
begin
  if FStack.Count = 0 then
    Exit;
  Branch := FStack.Last;
  if Branch.Taken or (Branch.Parent = TAtlasBranchState.Inactive) then
    Branch.State := TAtlasBranchState.Inactive
  else if ACondition = TAtlasBranchState.Inactive then
    Branch.State := TAtlasBranchState.Inactive
  else
  begin
    if Branch.Unsure or (Branch.Parent = TAtlasBranchState.Unknown) or
      (ACondition = TAtlasBranchState.Unknown) then
      Branch.State := TAtlasBranchState.Unknown
    else
      Branch.State := TAtlasBranchState.Active;
    // Gilt die Bedingung sicher, kann kein späterer Zweig mehr gelten: Entweder galt ein früherer oder dieser.
    Branch.Taken := ACondition = TAtlasBranchState.Active;
    Branch.Unsure := Branch.Unsure or (ACondition = TAtlasBranchState.Unknown);
  end;
  FStack[FStack.Count - 1] := Branch;
end;

procedure TScanner.Pop;
begin
  if FStack.Count > 0 then
    FStack.Delete(FStack.Count - 1);
end;

procedure TScanner.Reference(const AName: string; ALine: Integer);
var
  Use: TAtlasSymbolUse;
begin
  if (AName = '') or not TTextChars.IsIdentStart(AName[1]) then
    Exit;
  Use.Name := AName;
  Use.Line := ALine;
  FResult.Referenced := FResult.Referenced + [Use];
end;

procedure TScanner.ReferenceAll(const AExpression: string; ALine: Integer);
var
  Tokens: TArray<string>;
  Index: Integer;
begin
  Tokens := Tokenize(AExpression);
  for Index := 0 to High(Tokens) - 3 do
    if SameText(Tokens[Index], 'defined') and (Tokens[Index + 1] = '(') and (Tokens[Index + 3] = ')') then
      Reference(Tokens[Index + 2], ALine);
end;

function FirstWord(const AText: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(AText)) and TTextChars.IsIdentChar(AText[Index]) do
    Inc(Index);
  Result := Copy(AText, 1, Index - 1);
end;

function Unquote(const AText: string): string;
begin
  Result := Trim(AText);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

procedure TScanner.Directive(const AText: string; ALine: Integer);
var
  Name, Argument, Symbol: string;
  Parser: TExpressionParser;
  Condition: TAtlasBranchState;
begin
  Name := UpperCase(FirstWord(AText));
  Argument := Trim(Copy(AText, Length(Name) + 1, MaxInt));
  Symbol := FirstWord(Argument);
  if (Name = 'IFDEF') or (Name = 'IFNDEF') then
  begin
    Reference(Symbol, ALine);
    Condition := StateOf(FDefines.ContainsKey(UpperCase(Symbol)) = (Name = 'IFDEF'));
    if Symbol = '' then
      Condition := TAtlasBranchState.Unknown;
    Push(Condition);
  end
  else if (Name = 'IF') or (Name = 'ELSEIF') then
  begin
    ReferenceAll(Argument, ALine);
    Parser := TExpressionParser.Create(Argument, FDefines);
    try
      Condition := Parser.Parse;
    finally
      Parser.Free;
    end;
    if Name = 'IF' then
      Push(Condition)
    else
      ElseIf(Condition);
  end
  else if Name = 'IFOPT' then
    Push(TAtlasBranchState.Unknown)
  else if Name = 'ELSE' then
    ElseIf(TAtlasBranchState.Active)
  else if (Name = 'ENDIF') or (Name = 'IFEND') then
    Pop
  else if (Name = 'DEFINE') and (Symbol <> '') then
  begin
    FResult.Defined := FResult.Defined + [Symbol];
    if Current = TAtlasBranchState.Active then
      FDefines.AddOrSetValue(UpperCase(Symbol), True);
  end
  else if (Name = 'UNDEF') and (Symbol <> '') then
  begin
    if Current = TAtlasBranchState.Active then
      FDefines.Remove(UpperCase(Symbol));
  end
  else if ((Name = 'I') or (Name = 'INCLUDE')) and (Argument <> '') and not CharInSet(Argument[1], ['+', '-']) then
    FResult.Includes := FResult.Includes + [Unquote(Argument)];
end;

procedure TScanner.Commit;
begin
  if FPending.Name <> '' then
    FResult.Units := FResult.Units + [FPending];
  FPending := Default(TAtlasUsedUnit);
end;

procedure TScanner.Word(const AWord: string; ALine: Integer);
begin
  if FFirstWord then
  begin
    FFirstWord := False;
    FResult.IsPackage := SameText(AWord, 'package');
  end;
  case FUses of
    TUsesState.None:
      if SameText(AWord, 'uses') or (FResult.IsPackage and SameText(AWord, 'contains')) then
      begin
        FUses := TUsesState.ExpectName;
        FPending := Default(TAtlasUsedUnit);
      end;
    TUsesState.ExpectName:
      begin
        FPending := Default(TAtlasUsedUnit);
        FPending.Name := AWord;
        FPending.Line := ALine;
        FPending.State := Current;
        FUses := TUsesState.AfterName;
      end;
    TUsesState.NamePart:
      begin
        FPending.Name := FPending.Name + '.' + AWord;
        FUses := TUsesState.AfterName;
      end;
    TUsesState.AfterName:
      if SameText(AWord, 'in') then
        FUses := TUsesState.ExpectPath
      else
        FUses := TUsesState.None;
  else
    FUses := TUsesState.None;
  end;
end;

procedure TScanner.Symbol(AChar: Char);
begin
  case FUses of
    TUsesState.None:
      Exit;
    TUsesState.AfterName:
      if AChar = '.' then
      begin
        FUses := TUsesState.NamePart;
        Exit;
      end;
  end;
  if AChar = ',' then
  begin
    Commit;
    FUses := TUsesState.ExpectName;
  end
  else if AChar = ';' then
  begin
    Commit;
    FUses := TUsesState.None;
  end
  else
  begin
    FPending := Default(TAtlasUsedUnit);
    FUses := TUsesState.None;
  end;
end;

procedure TScanner.StringLiteral(const AValue: string);
begin
  if FUses = TUsesState.ExpectPath then
  begin
    FPending.InFile := AValue;
    FUses := TUsesState.AfterName;
  end
  else if FUses <> TUsesState.None then
  begin
    FPending := Default(TAtlasUsedUnit);
    FUses := TUsesState.None;
  end;
end;

procedure TScanner.CountLines(AFrom, ATo: Integer);
var
  Index: Integer;
begin
  for Index := AFrom to ATo do
    if (Index >= 1) and (Index <= Length(FText)) and (FText[Index] = #10) then
      Inc(FLine);
end;

function TScanner.Run: TAtlasSourceScan;
var
  Len, Start, Close, StartLine: Integer;
  C: Char;
  Value: string;
begin
  FResult := Default(TAtlasSourceScan);
  FPos := 1;
  FLine := 1;
  Len := Length(FText);
  while FPos <= Len do
  begin
    C := FText[FPos];
    if C = #10 then
    begin
      Inc(FLine);
      Inc(FPos);
    end
    else if CharInSet(C, [' ', #9, #13]) then
      Inc(FPos)
    else if (C = '/') and (FPos < Len) and (FText[FPos + 1] = '/') then
    begin
      while (FPos <= Len) and (FText[FPos] <> #10) do
        Inc(FPos);
    end
    else if C = '{' then
    begin
      Close := Pos('}', FText, FPos + 1);
      if Close = 0 then
        Close := Len + 1;
      StartLine := FLine;
      if (FPos < Len) and (FText[FPos + 1] = '$') then
        Directive(Copy(FText, FPos + 2, Close - FPos - 2), StartLine);
      CountLines(FPos, Close);
      FPos := Close + 1;
    end
    else if (C = '(') and (FPos < Len) and (FText[FPos + 1] = '*') then
    begin
      Close := Pos('*)', FText, FPos + 2);
      if Close = 0 then
        Close := Len + 1;
      StartLine := FLine;
      if (FPos + 2 <= Len) and (FText[FPos + 2] = '$') then
        Directive(Copy(FText, FPos + 3, Close - FPos - 3), StartLine);
      CountLines(FPos, Close);
      FPos := Close + 2;
    end
    else if C = '''' then
    begin
      // Mehrzeiliger String (Delphi 12): ''' am Zeilenende bis zum nächsten '''.
      if (Copy(FText, FPos, 3) = '''''''') and (FPos + 3 <= Len) and CharInSet(FText[FPos + 3], [#10, #13]) then
      begin
        Close := Pos('''''''', FText, FPos + 3);
        if Close = 0 then
          Close := Len + 1;
        CountLines(FPos, Close);
        FPos := Close + 3;
        StringLiteral('');
        Continue;
      end;
      Value := '';
      Inc(FPos);
      while FPos <= Len do
      begin
        if FText[FPos] = '''' then
        begin
          if (FPos < Len) and (FText[FPos + 1] = '''') then
          begin
            Value := Value + '''';
            Inc(FPos, 2);
            Continue;
          end;
          Break;
        end;
        if FText[FPos] = #10 then
          Break;
        Value := Value + FText[FPos];
        Inc(FPos);
      end;
      // Schließendes Hochkomma überspringen; ein Zeilenende bleibt für die Zeilenzählung stehen.
      if (FPos <= Len) and (FText[FPos] = '''') then
        Inc(FPos);
      StringLiteral(Value);
    end
    else if TTextChars.IsIdentStart(C) or (C = '&') then
    begin
      if C = '&' then
        Inc(FPos);
      Start := FPos;
      while (FPos <= Len) and TTextChars.IsIdentChar(FText[FPos]) do
        Inc(FPos);
      if FPos > Start then
        Word(Copy(FText, Start, FPos - Start), FLine);
    end
    else
    begin
      Symbol(C);
      Inc(FPos);
    end;
  end;
  Result := FResult;
end;

{ TAtlasPathCheck }

class function TAtlasPathCheck.Scan(const AText: string; const ADefines: TArray<string>): TAtlasSourceScan;
var
  Scanner: TScanner;
begin
  Scanner := TScanner.Create(AText, ADefines);
  try
    Result := Scanner.Run;
  finally
    Scanner.Free;
  end;
end;

class function TAtlasPathCheck.Evaluate(const AExpression: string;
  const ADefines: TArray<string>): TAtlasBranchState;
var
  Defines: TDictionary<string, Boolean>;
  Name: string;
  Parser: TExpressionParser;
begin
  Defines := TDictionary<string, Boolean>.Create;
  try
    for Name in ADefines do
      Defines.AddOrSetValue(UpperCase(Trim(Name)), True);
    Parser := TExpressionParser.Create(AExpression, Defines);
    try
      Result := Parser.Parse;
    finally
      Parser.Free;
    end;
  finally
    Defines.Free;
  end;
end;

function IsAbsolute(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or APath.StartsWith('\') or APath.StartsWith('/');
end;

class function TAtlasPathCheck.Combine(const AFolder, AName: string): string;
var
  Path, Prefix, Part: string;
  Parts: TList<string>;
begin
  Path := StringReplace(Trim(AName), '/', '\', [rfReplaceAll]);
  if not IsAbsolute(Path) then
  begin
    Prefix := StringReplace(Trim(AFolder), '/', '\', [rfReplaceAll]);
    if (Prefix <> '') and not Prefix.EndsWith('\') then
      Prefix := Prefix + '\';
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
  Parts := TList<string>.Create;
  try
    for Part in Path.Split(['\']) do
      if (Part = '') or (Part = '.') then
        Continue
      else if Part = '..' then
      begin
        if Parts.Count > 0 then
          Parts.Delete(Parts.Count - 1);
      end
      else
        Parts.Add(Part);
    Result := Prefix + '\' + string.Join('\', Parts.ToArray);
  finally
    Parts.Free;
  end;
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
    Exit;
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
      Value := AVariable(Name);
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
    Delete(Result, Length(Result), 1);
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
      Continue;
    Seen := False;
    for Known in ASkipped do
      if SameText(Known, Unknown) then
        Seen := True;
    if not Seen then
      ASkipped := ASkipped + [Unknown];
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
        Break;
      for Item in Copy(ADprojText, Start + Length(OpenTag), Stop - Start - Length(OpenTag)).Split([';']) do
        if (Trim(Item) <> '') and (Pos('$(', Item) = 0) and not Seen.ContainsKey(UpperCase(Trim(Item))) then
        begin
          Seen.Add(UpperCase(Trim(Item)), True);
          Result := Result + [Trim(Item)];
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
    if SameText(Name, Trim(AName)) then
      Exit(True);
  Result := False;
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
      for Name in FList(TAtlasPathCheck.Combine(AFolder, '')) do
        Names.AddOrSetValue(UpperCase(Name), True);
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

procedure AddFinding(AList: TList<TAtlasPathFinding>; AIndex: TDictionary<string, Integer>; const AName,
  AFileName: string; ALine: Integer; AUncertain: Boolean);
var
  Key: string;
  Index: Integer;
  Finding: TAtlasPathFinding;
begin
  Key := UpperCase(AName);
  if AIndex.TryGetValue(Key, Index) then
  begin
    Finding := AList[Index];
    Inc(Finding.Count);
    // Sicher, sobald eine Stelle sicher fehlt.
    Finding.Uncertain := Finding.Uncertain and AUncertain;
    AList[Index] := Finding;
    Exit;
  end;
  Finding.Uncertain := AUncertain;
  Finding.Name := AName;
  Finding.FileName := AFileName;
  Finding.Line := ALine;
  Finding.Count := 1;
  AIndex.Add(Key, AList.Count);
  AList.Add(Finding);
end;

class function TAtlasPathCheck.Run(const AInput: TAtlasPathCheckInput; const ARead: TAtlasPathReadText;
  const AList: TAtlasPathListFolder): TAtlasPathCheckResult;
var
  Cache: TFolderCache;
  ProjectDir, Source, Text, Folder, Name, Include, Candidate: string;
  ProjectNames, Known, Visited: TDictionary<string, Boolean>;
  Missing, Undefined: TList<TAtlasPathFinding>;
  MissingIndex, UndefinedIndex: TDictionary<string, Integer>;
  Scanned: TAtlasSourceScan;
  Used: TAtlasUsedUnit;
  Use: TAtlasSymbolUse;
  Queue: TList<TIncludeRef>;
  Uses_: TList<TSymbolAt>;
  Pair: TIncludeRef;
  Item: TSymbolAt;
  Index: Integer;
  Skipped, IncludeMissing: Boolean;

  function Folders(const AFrom: string): TArray<string>;
  begin
    Result := [AFrom, ProjectDir] + AInput.SearchPaths + AInput.LibraryPaths;
  end;

  function Resolves(const AUnit: TAtlasUsedUnit; const AFrom: string): Boolean;
  var
    Names: TArray<string>;
    Namespace, Each, Dir, Path: string;
  begin
    if AUnit.InFile <> '' then
    begin
      Path := Combine(AFrom, AUnit.InFile);
      Exit(Cache.Has(ExtractFileDir(Path), ExtractFileName(Path)));
    end;
    Names := [AUnit.Name];
    for Namespace in AInput.Namespaces do
      if Trim(Namespace) <> '' then
        Names := Names + [Trim(Namespace) + '.' + AUnit.Name];
    for Each in Names do
    begin
      if ProjectNames.ContainsKey(UpperCase(Each)) then
        Exit(True);
      for Dir in AlwaysThere do
        if SameText(Dir, Each) then
          Exit(True);
    end;
    for Dir in Folders(AFrom) do
      if Trim(Dir) <> '' then
        for Each in Names do
          if Cache.Has(Dir, Each + '.pas') or Cache.Has(Dir, Each + '.dcu') then
            Exit(True);
    Result := False;
  end;

  function FindInclude(const AName, AFrom: string; out APath: string): Boolean;
  var
    Dir, Each: string;
    Names: TArray<string>;
  begin
    Names := [AName];
    if ExtractFileExt(AName) = '' then
      Names := Names + [AName + '.inc', AName + '.pas'];
    for Dir in Folders(AFrom) do
      if Trim(Dir) <> '' then
        for Each in Names do
        begin
          APath := Combine(Dir, Each);
          if Cache.Has(ExtractFileDir(APath), ExtractFileName(APath)) then
            Exit(True);
        end;
    APath := '';
    Result := False;
  end;

begin
  Result := Default(TAtlasPathCheckResult);
  Result.SkippedMacros := AInput.SkippedMacros;
  Skipped := Length(AInput.SkippedMacros) > 0;
  IncludeMissing := False;
  ProjectDir := ExtractFileDir(Combine('', AInput.Project));
  Cache := TFolderCache.Create(AList);
  ProjectNames := TDictionary<string, Boolean>.Create;
  Known := TDictionary<string, Boolean>.Create;
  Visited := TDictionary<string, Boolean>.Create;
  Missing := TList<TAtlasPathFinding>.Create;
  Undefined := TList<TAtlasPathFinding>.Create;
  MissingIndex := TDictionary<string, Integer>.Create;
  UndefinedIndex := TDictionary<string, Integer>.Create;
  Queue := TList<TIncludeRef>.Create;
  Uses_ := TList<TSymbolAt>.Create;
  try
    for Source in AInput.Sources do
      ProjectNames.AddOrSetValue(UpperCase(ChangeFileExt(ExtractFileName(Source), '')), True);
    for Name in AInput.ActiveDefines + AInput.ProjectDefines do
      Known.AddOrSetValue(UpperCase(Trim(Name)), True);
    for Source in AInput.Sources do
    begin
      if Visited.ContainsKey(UpperCase(Source)) then
        Continue;
      Visited.Add(UpperCase(Source), True);
      if not (Assigned(ARead) and ARead(Source, Text)) then
      begin
        Inc(Result.Unreadable);
        Continue;
      end;
      Inc(Result.Files);
      Folder := ExtractFileDir(Source);
      Scanned := Scan(Text, AInput.ActiveDefines);
      for Used in Scanned.Units do
        if (Used.State = TAtlasBranchState.Active) and not Resolves(Used, Folder) then
          // Mit "in 'Pfad'" zählt kein Suchpfad: dann sicher.
          AddFinding(Missing, MissingIndex, Used.Name, Source, Used.Line, Skipped and (Used.InFile = ''));
      for Use in Scanned.Referenced do
        Uses_.Add(SymbolAt(Source, Use));
      for Name in Scanned.Defined do
        Known.AddOrSetValue(UpperCase(Name), True);
      for Include in Scanned.Includes do
        Queue.Add(IncludeRef(Include, Folder));
    end;
    // Eingebundene Dateien nur nach $DEFINE durchsuchen.
    Index := 0;
    while (Index < Queue.Count) and (Index < MaxIncludes) do
    begin
      Pair := Queue[Index];
      Inc(Index);
      if not FindInclude(Pair.Name, Pair.Folder, Candidate) then
      begin
        IncludeMissing := True;
        Continue;
      end;
      if Visited.ContainsKey(UpperCase(Candidate)) then
        Continue;
      Visited.Add(UpperCase(Candidate), True);
      if not (Assigned(ARead) and ARead(Candidate, Text)) then
        Continue;
      Scanned := Scan(Text, AInput.ActiveDefines);
      for Name in Scanned.Defined do
        Known.AddOrSetValue(UpperCase(Name), True);
      for Include in Scanned.Includes do
        Queue.Add(IncludeRef(Include, ExtractFileDir(Candidate)));
    end;
    for Item in Uses_ do
      if not Known.ContainsKey(UpperCase(Item.Use.Name)) and not TTextDefines.IsCompilerSymbol(Item.Use.Name) and
        not IsForeignSymbol(Item.Use.Name) then
        // Fehlt eine eingebundene Datei und fiel ein Suchpfad weg, kann das $DEFINE dort stehen.
        AddFinding(Undefined, UndefinedIndex, Item.Use.Name, Item.FileName, Item.Use.Line,
          Skipped and IncludeMissing);
    Result.MissingUnits := Missing.ToArray;
    Result.UndefinedDefines := Undefined.ToArray;
  finally
    Uses_.Free;
    Queue.Free;
    UndefinedIndex.Free;
    MissingIndex.Free;
    Undefined.Free;
    Missing.Free;
    Visited.Free;
    Known.Free;
    ProjectNames.Free;
    Cache.Free;
  end;
end;

end.
