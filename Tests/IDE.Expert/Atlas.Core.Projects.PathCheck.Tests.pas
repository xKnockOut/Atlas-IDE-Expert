unit Atlas.Core.Projects.PathCheck.Tests;

// Tests für „Suchpfade und Defines prüfen“ der Einrichtung (#759): uses und
// contains mit bedingten Abschnitten, $IF-Ausdrücke, fehlende Units mit Name
// und Zeile, Defines ohne Quelle samt eingebundener Dateien, Pfade und die
// Symbole aus der .dproj, Makros (IDE vor Umgebung, verschachtelt) und
// unsichere Funde nach übersprungenen Suchpfaden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPathCheckTests = class
  public
    [Test]
    procedure ScansUsesWithLinesAndPaths;
    [Test]
    procedure ScansContainsOnlyInPackages;
    [Test]
    procedure IgnoresCommentsAndStrings;
    [Test]
    procedure EvaluatesBranches;
    [Test]
    procedure UnknownConditionsStayUnknown;
    [Test]
    procedure TracksDefinesAndIncludes;
    [Test]
    procedure EvaluatesExpressions;
    [Test]
    procedure ReportsMissingUnitWithName;
    [Test]
    procedure ResolvesNamespacesPathsAndDcu;
    [Test]
    procedure ReportsDefinesWithoutSource;
    [Test]
    procedure CountsUnreadableFiles;
    [Test]
    procedure CombinesPaths;
    [Test]
    procedure ExpandsVariables;
    [Test]
    procedure ReadsDefinesFromDproj;
    [Test]
    procedure ExpandsNestedMacrosAndNamesUnknown;
    [Test]
    procedure MacrosPreferIdeOverEnvironment;
    [Test]
    procedure CollectsSkippedMacros;
    [Test]
    procedure SkippedPathMakesUnitsUncertain;
    [Test]
    procedure SkippedPathAndMissingIncludeMakeDefinesUncertain;
    /// <summary>1: Units eines requires-Packages der Projektgruppe gelten als gefunden.</summary>
    [Test]
    procedure RequiresPackageInGroupResolvesUnits;
    /// <summary>2: Quellordner des requires-Packages zusätzlich im Suchpfad: Hinweis, kein Fehler.</summary>
    [Test]
    procedure RequiresPackageFolderInSearchPathIsHint;
    /// <summary>3: requires auf ein Package nur als .dcp: Hinweis „ohne Quelle“; rtl in den Bibliothekspfaden
    /// nicht.</summary>
    [Test]
    procedure RequiresDcpOnlyIsHint;
    /// <summary>4: {$IFDEF FPC} uses LCLIntf {$ENDIF} unter Delphi: weder Unit- noch Define-Befund.</summary>
    [Test]
    procedure FreePascalBranchIsQuiet;
    /// <summary>5: DCC_Define mit Vererbung Base → Cfg_1 → Cfg_1_Win32.</summary>
    [Test]
    procedure DprojDefinesInherit;
    /// <summary>6: -dX in Build-Skripten und ConditionalDefines in .lpk sind Quellen.</summary>
    [Test]
    procedure ScriptDefinesAreSources;
    /// <summary>7: Tippfehler bekommt einen Vorschlag.</summary>
    [Test]
    procedure TypoGetsSuggestion;
    /// <summary>Units aus einer .dcp ohne Quelle (ToolsAPI aus designide) gelten als gefunden.</summary>
    [Test]
    procedure UnitsInRequiredDcpAreFound;
    /// <summary>Der Scanner allein: mehrzeilige Strings und (*$…*) wie im Projekt.</summary>
    [Test]
    procedure ScanUnitReadsMultilineStringsAndParenDirectives;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Projects.PathCheck,
  Atlas.Core.Projects.PathCheck.Scan;

function UnitNames(const AScan: TAtlasSourceScan): string;
var
  mUsed: TAtlasUsedUnit;
begin
  Result := '';
  for mUsed in AScan.Units do
  begin
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    Result := Result + mUsed.Name;
  end;
end;

function StateNames(const AScan: TAtlasSourceScan): string;
const
  cNames: array[TAtlasBranchState] of string = ('a', 'i', 'u');
var
  mUsed: TAtlasUsedUnit;
begin
  Result := '';
  for mUsed in AScan.Units do
  begin
    Result := Result + cNames[mUsed.State];
  end;
end;

function FindingNames(const AFindings: TArray<TAtlasPathFinding>): string;
var
  mFinding: TAtlasPathFinding;
begin
  Result := '';
  for mFinding in AFindings do
  begin
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    Result := Result + mFinding.Name;
  end;
end;

{ Kleines Dateisystem im Speicher: voller Pfad -> Text. }

type
  TFakeDisk = class
  private
    FFiles: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const APath, AText: string);
    function Read(const AFileName: string; out AText: string): Boolean;
    function List(const AFolder: string): TArray<string>;
  end;

constructor TFakeDisk.Create;
begin
  inherited Create;
  FFiles := TDictionary<string, string>.Create;
end;

destructor TFakeDisk.Destroy;
begin
  FFiles.Free;
  inherited;
end;

procedure TFakeDisk.Add(const APath, AText: string);
begin
  FFiles.AddOrSetValue(UpperCase(APath), AText);
end;

function TFakeDisk.Read(const AFileName: string; out AText: string): Boolean;
begin
  Result := FFiles.TryGetValue(UpperCase(AFileName), AText);
end;

function TFakeDisk.List(const AFolder: string): TArray<string>;
var
  mPath, mFolder: string;
begin
  Result := nil;
  mFolder := UpperCase(AFolder);
  if not mFolder.EndsWith('\') then
  begin
    mFolder := mFolder + '\';
  end;
  for mPath in FFiles.Keys do
  begin
    if mPath.StartsWith(mFolder) and (Pos('\', Copy(mPath, Length(mFolder) + 1, MaxInt)) = 0) then
    begin
      Result := Result + [Copy(mPath, Length(mFolder) + 1, MaxInt)];
    end;
  end;
end;

function RunOn(ADisk: TFakeDisk; const AInput: TAtlasPathCheckInput): TAtlasPathCheckResult;
begin
  Result := TAtlasPathCheck.Run(AInput,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ADisk.Read(AFileName, AText);
    end,
    function(const AFolder: string): TArray<string>
    begin
      Result := ADisk.List(AFolder);
    end);
end;

{ TAtlasPathCheckTests }

procedure TAtlasPathCheckTests.ScansUsesWithLinesAndPaths;
var
  mScan: TAtlasSourceScan;
begin
  mScan := TAtlasPathCheck.Scan('program App;' + sLineBreak +
    'uses' + sLineBreak +
    '  System.SysUtils,' + sLineBreak +
    '  Main in ''Src\Main.pas'' {Form1},' + sLineBreak +
    '  &Type;' + sLineBreak +
    'begin' + sLineBreak +
    'end.', nil);
  Assert.IsFalse(mScan.IsPackage);
  Assert.AreEqual('System.SysUtils|Main|Type', UnitNames(mScan));
  Assert.AreEqual(3, mScan.Units[0].Line);
  Assert.AreEqual(4, mScan.Units[1].Line);
  Assert.AreEqual('Src\Main.pas', mScan.Units[1].InFile);
  Assert.AreEqual('', mScan.Units[0].InFile);
  Assert.AreEqual('aaa', StateNames(mScan));
end;

procedure TAtlasPathCheckTests.ScansContainsOnlyInPackages;
var
  mScan: TAtlasSourceScan;
begin
  mScan := TAtlasPathCheck.Scan('package Pkg;' + sLineBreak +
    'requires rtl, vcl;' + sLineBreak +
    'contains A in ''A.pas'', B.C;' + sLineBreak +
    'end.', nil);
  Assert.IsTrue(mScan.IsPackage);
  Assert.AreEqual('A|B.C', UnitNames(mScan));
  // In einer Unit ist contains kein Schlüsselwort.
  mScan := TAtlasPathCheck.Scan('unit U; interface var contains: Integer; implementation uses X; end.', nil);
  Assert.AreEqual('X', UnitNames(mScan));
end;

procedure TAtlasPathCheckTests.IgnoresCommentsAndStrings;
var
  mScan: TAtlasSourceScan;
begin
  mScan := TAtlasPathCheck.Scan('unit U;' + sLineBreak +
    '// uses Comment1;' + sLineBreak +
    '{ uses Comment2; }' + sLineBreak +
    '(* uses Comment3; *)' + sLineBreak +
    'interface' + sLineBreak +
    'const S = ''uses Text;'';' + sLineBreak +
    'implementation' + sLineBreak +
    'uses Real { , Hidden };' + sLineBreak +
    'end.', nil);
  Assert.AreEqual('Real', UnitNames(mScan));
  Assert.AreEqual(8, mScan.Units[0].Line);
end;

procedure TAtlasPathCheckTests.EvaluatesBranches;
var
  mScan: TAtlasSourceScan;
begin
  mScan := TAtlasPathCheck.Scan('unit U; interface uses' + sLineBreak +
    '  A' + sLineBreak +
    '  {$IFDEF DEBUG}, B {$ELSE}, C {$ENDIF}' + sLineBreak +
    '  {$IFNDEF DEBUG}, D {$ENDIF}' + sLineBreak +
    '  {$IF DEFINED(MSWINDOWS) and not DEFINED(DEBUG)}, E' + sLineBreak +
    '  {$ELSEIF DEFINED(DEBUG)}, F' + sLineBreak +
    '  {$ELSE}, G {$IFEND}' + sLineBreak +
    '  {$IFDEF MISSING} {$IFDEF DEBUG}, H {$ENDIF} {$ENDIF};' + sLineBreak +
    'implementation end.', ['debug', 'MSWINDOWS']);
  Assert.AreEqual('A|B|C|D|E|F|G|H', UnitNames(mScan));
  Assert.AreEqual('aaiiiaii', StateNames(mScan));
  Assert.AreEqual(3, mScan.Units[1].Line);
end;

procedure TAtlasPathCheckTests.UnknownConditionsStayUnknown;
var
  mScan: TAtlasSourceScan;
begin
  mScan := TAtlasPathCheck.Scan('unit U; interface uses A' +
    '{$IF CompilerVersion >= 36}, B {$ELSEIF DEFINED(X)}, C {$ELSE}, D {$IFEND}' +
    '{$IFOPT R+}, E {$ELSE}, F {$ENDIF}' +
    '{$IF CompilerVersion >= 36}{$IFDEF X}, G{$ENDIF}{$IFNDEF X}, H{$ENDIF}{$IFEND}' +
    '{$IF Declared(Foo)}, I {$ELSEIF DEFINED(X)}, J {$ELSEIF DEFINED(Y)}, K {$IFEND};' +
    'implementation end.', ['X']);
  Assert.AreEqual('A|B|C|D|E|F|G|H|I|J|K', UnitNames(mScan));
  // C gilt, wenn B nicht gilt: unbekannt; D kann nicht mehr gelten, weil sonst C sicher gilt.
  // Unter einem unbekannten Zweig bleibt ein sicherer Zweig unbekannt (G), ein falscher fällt weg (H).
  // K kann nicht gelten, weil sonst J sicher gilt.
  Assert.AreEqual('auuiuuuiuui', StateNames(mScan));
end;

procedure TAtlasPathCheckTests.TracksDefinesAndIncludes;
var
  mScan: TAtlasSourceScan;
begin
  mScan := TAtlasPathCheck.Scan('unit U;' + sLineBreak +
    '{$I Common.inc}' + sLineBreak +
    '{$INCLUDE ''Sub\More.inc''}' + sLineBreak +
    '{$I+}' + sLineBreak +
    '{$DEFINE USE_X}' + sLineBreak +
    '{$IFDEF NEVER}{$DEFINE LATER}{$ENDIF}' + sLineBreak +
    'interface uses A {$IFDEF USE_X}, B {$ENDIF} {$IFDEF LATER}, C {$ENDIF};' + sLineBreak +
    '{$UNDEF USE_X}' + sLineBreak +
    'implementation uses D {$IFDEF USE_X}, E {$ENDIF}; end.', nil);
  Assert.AreEqual('Common.inc|Sub\More.inc', string.Join('|', mScan.Includes));
  Assert.AreEqual('USE_X|LATER', string.Join('|', mScan.Defined));
  Assert.AreEqual('A|B|C|D|E', UnitNames(mScan));
  Assert.AreEqual('aaiai', StateNames(mScan));
  Assert.AreEqual(4, Integer(Length(mScan.Referenced)));
  Assert.AreEqual('NEVER', mScan.Referenced[0].Name);
  Assert.AreEqual(6, mScan.Referenced[0].Line);
end;

procedure TAtlasPathCheckTests.EvaluatesExpressions;
begin
  Assert.AreEqual<TAtlasBranchState>(TAtlasBranchState.Active, TAtlasPathCheck.Evaluate('DEFINED(A)', ['a']));
  Assert.AreEqual<TAtlasBranchState>(TAtlasBranchState.Active,
    TAtlasPathCheck.Evaluate('defined(A) and not Defined(B)', ['A']));
  Assert.AreEqual<TAtlasBranchState>(TAtlasBranchState.Inactive,
    TAtlasPathCheck.Evaluate('DEFINED(A) AND DEFINED(B)', ['A']));
  Assert.AreEqual<TAtlasBranchState>(TAtlasBranchState.Active,
    TAtlasPathCheck.Evaluate('(DEFINED(A) or DEFINED(B)) and not (DEFINED(C))', ['B']));
  Assert.AreEqual<TAtlasBranchState>(TAtlasBranchState.Unknown,
    TAtlasPathCheck.Evaluate('CompilerVersion >= 36', ['A']));
  Assert.AreEqual<TAtlasBranchState>(TAtlasBranchState.Unknown,
    TAtlasPathCheck.Evaluate('DEFINED(A) or (RTLVersion > 1)', ['A']));
  Assert.AreEqual<TAtlasBranchState>(TAtlasBranchState.Unknown, TAtlasPathCheck.Evaluate('DEFINED(A', ['A']));
  Assert.AreEqual<TAtlasBranchState>(TAtlasBranchState.Unknown, TAtlasPathCheck.Evaluate('', nil));
end;

procedure TAtlasPathCheckTests.ReportsMissingUnitWithName;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\P\App.dpr', 'program App;' + sLineBreak + 'uses' + sLineBreak + '  Main in ''Src\Main.pas'',' +
      sLineBreak + '  Helpers;' + sLineBreak + 'begin end.');
    mDisk.Add('C:\P\Src\Main.pas', 'unit Main; interface uses System.SysUtils; implementation uses Helpers; end.');
    mDisk.Add('C:\RTL\System.SysUtils.dcu', '');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\P\App.dproj';
    mInput.Sources := ['C:\P\App.dpr', 'C:\P\Src\Main.pas'];
    mInput.LibraryPaths := ['C:\RTL'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual(2, mCheck.Files);
    Assert.IsFalse(mCheck.Clean);
    Assert.AreEqual('Helpers', FindingNames(mCheck.MissingUnits));
    Assert.AreEqual('C:\P\App.dpr', mCheck.MissingUnits[0].FileName);
    Assert.AreEqual(4, mCheck.MissingUnits[0].Line);
    Assert.AreEqual(2, Integer(mCheck.MissingUnits[0].Count));
    // Mit dem Suchpfad ist die Unit da, alles ist sauber.
    mDisk.Add('C:\Shared\Helpers.pas', 'unit Helpers; interface implementation end.');
    mInput.SearchPaths := ['C:\Shared'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('', FindingNames(mCheck.MissingUnits));
    Assert.IsTrue(mCheck.Clean);
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.ResolvesNamespacesPathsAndDcu;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\P\App.dpr', 'program App; uses System, SysUtils, Vcl.Forms, Forms, Local, Beside, Compiled, ' +
      'Gone in ''..\Gone.pas'', There in ''..\There.pas'', Main' +
      '{$IFDEF LINUX}, LinuxOnly{$ENDIF}{$IF CompilerVersion > 35}, Maybe{$IFEND}; begin end.');
    mDisk.Add('C:\P\Main.pas', 'unit Main; interface implementation end.');
    mDisk.Add('C:\P\Local.pas', '');
    mDisk.Add('C:\There.pas', '');
    mDisk.Add('C:\Lib\Compiled.DCU', '');
    mDisk.Add('C:\RTL\System.SysUtils.dcu', '');
    mDisk.Add('C:\RTL\Vcl.Forms.dcu', '');
    mDisk.Add('C:\Src\App\Beside.pas', '');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\P\App.dproj';
    mInput.Sources := ['C:\P\App.dpr', 'C:\P\Main.pas'];
    mInput.SearchPaths := ['C:\Lib', '', 'C:\Src\App'];
    mInput.LibraryPaths := ['C:\RTL'];
    mInput.Namespaces := ['System', 'Vcl', ' '];
    mInput.ActiveDefines := ['MSWINDOWS'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('Gone', FindingNames(mCheck.MissingUnits));
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.ReportsDefinesWithoutSource;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\P\App.dpr', 'program App;' + sLineBreak +
      '{$I Common.inc}' + sLineBreak +
      '{$IFDEF USE_LOG}{$ENDIF}' + sLineBreak +
      '{$IFDEF DEBUG}{$ENDIF}{$IFDEF RELEASE}{$ENDIF}' + sLineBreak +
      '{$IFDEF MSWINDOWS}{$ENDIF}{$IFDEF VER360}{$ENDIF}{$IFDEF FPC}{$ENDIF}' + sLineBreak +
      '{$IF DEFINED(FROM_INC) or DEFINED(FROM_SUB)}{$IFEND}' + sLineBreak +
      '{$IFNDEF LOCAL}{$DEFINE LOCAL}{$ENDIF}' + sLineBreak +
      'uses Main; begin end.');
    mDisk.Add('C:\P\Main.pas', 'unit Main; interface {$IFDEF USE_LOG}{$ENDIF}{$IFDEF OTHER}{$ENDIF} implementation end.');
    mDisk.Add('C:\P\Common.inc', '{$DEFINE FROM_INC}{$IFDEF FROM_LIBRARY}{$ENDIF}{$I Inc\Sub}');
    mDisk.Add('C:\P\Inc\Sub.inc', '{$DEFINE FROM_SUB}{$I ..\Common.inc}');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\P\App.dproj';
    mInput.Sources := ['C:\P\App.dpr', 'C:\P\Main.pas'];
    mInput.ActiveDefines := ['DEBUG', 'MSWINDOWS'];
    mInput.ProjectDefines := ['DEBUG', 'RELEASE'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('', FindingNames(mCheck.MissingUnits));
    // FROM_LIBRARY wird nur in der eingebundenen Datei abgefragt und zählt nicht.
    Assert.AreEqual('USE_LOG|OTHER', FindingNames(mCheck.UndefinedDefines));
    Assert.AreEqual('C:\P\App.dpr', mCheck.UndefinedDefines[0].FileName);
    Assert.AreEqual(3, mCheck.UndefinedDefines[0].Line);
    Assert.AreEqual(2, Integer(mCheck.UndefinedDefines[0].Count));
    Assert.AreEqual('C:\P\Main.pas', mCheck.UndefinedDefines[1].FileName);
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.CountsUnreadableFiles;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\P\App.dpr', 'program App; uses Gone; begin end.');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\P\App.dproj';
    mInput.Sources := ['C:\P\App.dpr', 'C:\P\Gone.pas', 'C:\P\App.dpr'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual(1, mCheck.Files);
    Assert.AreEqual(1, mCheck.Unreadable);
    // Gone ist eine Datei des Projekts: Der Compiler kennt sie, auch wenn sie nicht lesbar ist.
    Assert.IsTrue(mCheck.Clean);
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.CombinesPaths;
begin
  Assert.AreEqual('C:\P\Lib\X', TAtlasPathCheck.Combine('C:\P\Src', '..\Lib\.\X'));
  Assert.AreEqual('C:\P\Src', TAtlasPathCheck.Combine('C:\P\Src\', ''));
  Assert.AreEqual('D:\Abs\Y.pas', TAtlasPathCheck.Combine('C:\P', 'D:/Abs/Y.pas'));
  Assert.AreEqual('\\srv\share\a', TAtlasPathCheck.Combine('\\srv\share', 'a'));
  Assert.AreEqual('C:\', TAtlasPathCheck.Combine('C:\P', '..\..\..'));
end;

procedure TAtlasPathCheckTests.ExpandsVariables;
var
  mVariable: TAtlasPathVariable;
begin
  mVariable :=
    function(const AName: string): string
    begin
      Result := '';
      if SameText(AName, 'BDS') then
      begin
        Result := 'C:\Delphi';
      end
      else if SameText(AName, 'Platform') then
      begin
        Result := 'Win64';
      end;
    end;
  Assert.AreEqual('C:\Delphi\lib\Win64\release', TAtlasPathCheck.ExpandPath('$(BDS)\lib\$(Platform)\release\',
    'C:\P', mVariable));
  Assert.AreEqual('C:\Lib', TAtlasPathCheck.ExpandPath(' ..\Lib ', 'C:\P', mVariable));
  Assert.AreEqual('', TAtlasPathCheck.ExpandPath('$(Unknown)\x', 'C:\P', mVariable));
  Assert.AreEqual('', TAtlasPathCheck.ExpandPath('$(BDS', 'C:\P', mVariable));
  Assert.AreEqual('', TAtlasPathCheck.ExpandPath('  ', 'C:\P', mVariable));
  Assert.AreEqual('C:\P\x', TAtlasPathCheck.ExpandPath('x', 'C:\P', nil));
end;

procedure TAtlasPathCheckTests.ReadsDefinesFromDproj;
begin
  Assert.AreEqual('DEBUG|RELEASE|USE_X', string.Join('|', TAtlasPathCheck.DprojDefines(
    '<Project><PropertyGroup><DCC_Define>DEBUG;$(DCC_Define)</DCC_Define></PropertyGroup>' +
    '<PropertyGroup><dcc_define> RELEASE ;debug;USE_X;</dcc_define></PropertyGroup></Project>')));
  Assert.AreEqual(0, Integer(Length(TAtlasPathCheck.DprojDefines('<Project/>'))));
  Assert.IsTrue(TAtlasPathCheck.IsForeignSymbol('fpc'));
  Assert.IsFalse(TAtlasPathCheck.IsForeignSymbol('DEBUG'));
end;

procedure TAtlasPathCheckTests.ExpandsNestedMacrosAndNamesUnknown;
var
  mVariable: TAtlasPathVariable;
  mUnknown: string;
begin
  mVariable :=
    function(const AName: string): string
    begin
      Result := '';
      if SameText(AName, 'BDS') then
      begin
        Result := 'C:\Delphi';
      end
      else if SameText(AName, 'BDSLIB') then
      begin
        Result := '$(BDS)\lib';
      end
      else if SameText(AName, 'Loop') then
      begin
        Result := '$(Loop)';
      end;
    end;
  Assert.AreEqual('C:\Delphi\lib\x', TAtlasPathCheck.ExpandPath('$(BDSLIB)\x', 'C:\P', mVariable, mUnknown));
  Assert.AreEqual('', mUnknown);
  Assert.AreEqual('', TAtlasPathCheck.ExpandPath('$(BDS)\$( MyLib )\src', 'C:\P', mVariable, mUnknown));
  Assert.AreEqual('MyLib', mUnknown);
  // Ein Wert, der sich selbst enthält, endet nach MaxExpansions als unbekannt.
  Assert.AreEqual('', TAtlasPathCheck.ExpandPath('$(Loop)', 'C:\P', mVariable, mUnknown));
  Assert.AreEqual('Loop', mUnknown);
  Assert.AreEqual('', TAtlasPathCheck.ExpandPath('$(Open', 'C:\P', mVariable, mUnknown));
  Assert.AreEqual('Open', mUnknown);
end;

procedure TAtlasPathCheckTests.MacrosPreferIdeOverEnvironment;
var
  mMacros: TAtlasPathMacros;
  mVariable: TAtlasPathVariable;
begin
  mMacros := TAtlasPathMacros.Create(
    function(const AName: string): string
    begin
      Result := '';
      if SameText(AName, 'BDSLIB') then
      begin
        Result := 'E:\Env\lib';
      end
      else if SameText(AName, 'MYLIB') then
      begin
        Result := 'E:\MyLib';
      end
      else if SameText(AName, 'BDSCOMMONDIR') then
      begin
        Result := 'E:\Public';
      end;
    end);
  // Umgebungsvariable aus den IDE-Optionen überschreibt die des Prozesses.
  mMacros.Add('MyLib', 'D:\Override');
  mMacros.Add('Empty', '');
  mMacros.AddBds('C:\Delphi\');
  mMacros.AddProject('C:\Work\App\App.dproj', 'Win64', 'Debug');
  Assert.AreEqual('D:\Override', mMacros.Value('MYLIB'));
  Assert.AreEqual('C:\Delphi', mMacros.Value('bds'));
  // BDS-Werte der IDE gehen der Umgebung vor.
  Assert.AreEqual('C:\Delphi\lib', mMacros.Value('BDSLIB'));
  Assert.AreEqual('C:\Delphi\bin', mMacros.Value('BDSBIN'));
  Assert.AreEqual('E:\Public', mMacros.Value('BDSCOMMONDIR'));
  Assert.AreEqual('', mMacros.Value('Empty'));
  Assert.AreEqual('Win64', mMacros.Value('Platform'));
  Assert.AreEqual('Debug', mMacros.Value('Config'));
  Assert.AreEqual('C:\Work\App', mMacros.Value('ProjectDir'));
  Assert.AreEqual('App', mMacros.Value('ProjectName'));
  Assert.AreEqual('App.dproj', mMacros.Value('ProjectFilename'));
  Assert.AreEqual('C:\Work\App\', mMacros.Value('MSBuildThisFileDirectory'));
  Assert.AreEqual('Work\App', mMacros.Value('MSBuildProjectDirectoryNoRoot'));
  // AddDefault ändert nichts Gesetztes.
  mMacros.AddDefault('Platform', 'Win32');
  Assert.AreEqual('Win64', mMacros.Value('Platform'));
  mVariable := mMacros.Variable();
  Assert.AreEqual('C:\Delphi\lib\Win64\release', TAtlasPathCheck.ExpandPath('$(BDSLIB)\$(Platform)\release',
    'C:\P', mVariable));
  Assert.AreEqual('C:\Work\App\Lib', TAtlasPathCheck.ExpandPath('$(ProjectDir)\Lib', 'C:\P', mVariable));
  Assert.AreEqual('C:\Work\App\Lib', TAtlasPathCheck.ExpandPath('$(MSBuildThisFileDirectory)Lib', 'C:\P',
    mVariable));
end;

procedure TAtlasPathCheckTests.CollectsSkippedMacros;
var
  mSkipped: TArray<string>;
  mPaths: TArray<string>;
  mVariable: TAtlasPathVariable;
begin
  mVariable :=
    function(const AName: string): string
    begin
      Result := '';
      if SameText(AName, 'BDS') then
      begin
        Result := 'C:\Delphi';
      end;
    end;
  mSkipped := ['OLD'];
  mPaths := TAtlasPathCheck.ExpandPaths(['$(BDS)\lib', '$(MyLib)\src', '$(MYLIB)\inc', '$(Other)', '', 'Rel',
    '$(old)'], 'C:\P', mVariable, mSkipped);
  Assert.AreEqual('C:\Delphi\lib|C:\P\Rel', string.Join('|', mPaths));
  Assert.AreEqual('OLD|MyLib|Other', string.Join('|', mSkipped));
end;

procedure TAtlasPathCheckTests.SkippedPathMakesUnitsUncertain;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\P\App.dpr', 'program App; uses Helpers, Gone in ''..\Gone.pas''; begin end.');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\P\App.dproj';
    mInput.Sources := ['C:\P\App.dpr'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('Helpers|Gone', FindingNames(mCheck.MissingUnits));
    Assert.IsFalse(mCheck.MissingUnits[0].Uncertain);
    Assert.AreEqual(0, TAtlasPathCheckResult.UncertainIn(mCheck.MissingUnits));
    Assert.IsFalse(mCheck.Clean);
    // Ein Suchpfad mit unbekanntem Makro fiel weg: Helpers könnte dort liegen, Gone (mit Pfad) nicht.
    mInput.SkippedMacros := ['MyLib'];
    mInput.Sources := ['C:\P\App.dpr'];
    mDisk.Add('C:\P\App.dpr', 'program App; uses Helpers; begin end.');
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('Helpers', FindingNames(mCheck.MissingUnits));
    Assert.IsTrue(mCheck.MissingUnits[0].Uncertain);
    Assert.AreEqual('MyLib', string.Join('|', mCheck.SkippedMacros));
    Assert.AreEqual(1, TAtlasPathCheckResult.UncertainIn(mCheck.MissingUnits));
    // Nur unsichere Funde: kein sicherer Fund.
    Assert.IsTrue(mCheck.Clean);
    mDisk.Add('C:\P\App.dpr', 'program App; uses Helpers, Gone in ''..\Gone.pas''; begin end.');
    mCheck := RunOn(mDisk, mInput);
    Assert.IsTrue(mCheck.MissingUnits[0].Uncertain);
    Assert.IsFalse(mCheck.MissingUnits[1].Uncertain);
    Assert.IsFalse(mCheck.Clean);
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.SkippedPathAndMissingIncludeMakeDefinesUncertain;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\P\App.dpr', 'program App; {$I Lib.inc} {$IFDEF USE_LIB} {$ENDIF} begin end.');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\P\App.dproj';
    mInput.Sources := ['C:\P\App.dpr'];
    // Ohne übersprungenen Pfad: sicherer Fund, auch wenn Lib.inc fehlt.
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('USE_LIB', FindingNames(mCheck.UndefinedDefines));
    Assert.IsFalse(mCheck.UndefinedDefines[0].Uncertain);
    // Lib.inc könnte im übersprungenen Pfad liegen und USE_LIB setzen.
    mInput.SkippedMacros := ['MyLib'];
    mCheck := RunOn(mDisk, mInput);
    Assert.IsTrue(mCheck.UndefinedDefines[0].Uncertain);
    // Ist die eingebundene Datei da, bleibt der Fund sicher.
    mDisk.Add('C:\P\Lib.inc', '{$DEFINE OTHER}');
    mCheck := RunOn(mDisk, mInput);
    Assert.IsFalse(mCheck.UndefinedDefines[0].Uncertain);
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.RequiresPackageInGroupResolvesUnits;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\G\B\B.dpk', 'package B; contains B.Plan in ''Source\B.Plan.pas''; end.');
    mDisk.Add('C:\G\B\Source\B.Plan.pas', 'unit B.Plan; interface implementation end.');
    mDisk.Add('C:\G\A\A.dpk', 'package A; requires rtl, B; contains A.Main in ''A.Main.pas''; end.');
    mDisk.Add('C:\G\A\A.Main.pas', 'unit A.Main; interface uses B.Plan; implementation end.');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\G\A\A.dproj';
    mInput.Sources := ['C:\G\A\A.dpk', 'C:\G\A\A.Main.pas'];
    mInput.GroupProjects := ['C:\G\A\A.dproj', 'C:\G\B\B.dproj'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('', FindingNames(mCheck.MissingUnits), 'B.Plan kommt aus dem requires-Package B');
    Assert.AreEqual('', FindingNames(mCheck.Hints));
    // Ohne B in der Gruppe fehlt die Unit.
    mInput.GroupProjects := ['C:\G\A\A.dproj'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('B.Plan', FindingNames(mCheck.MissingUnits));
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.RequiresPackageFolderInSearchPathIsHint;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\G\B\B.dpk', 'package B; contains B.Plan in ''Source\B.Plan.pas''; end.');
    mDisk.Add('C:\G\B\Source\B.Plan.pas', 'unit B.Plan; interface implementation end.');
    mDisk.Add('C:\G\A\A.dpk', 'package A;' + sLineBreak + 'requires B;' + sLineBreak +
      'contains A.Main in ''A.Main.pas''; end.');
    mDisk.Add('C:\G\A\A.Main.pas', 'unit A.Main; interface uses B.Plan; implementation end.');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\G\A\A.dproj';
    mInput.Sources := ['C:\G\A\A.dpk', 'C:\G\A\A.Main.pas'];
    mInput.GroupProjects := ['C:\G\B\B.dproj'];
    mInput.SearchPaths := ['C:\G\B\Source'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('', FindingNames(mCheck.MissingUnits));
    Assert.AreEqual('B', FindingNames(mCheck.Hints));
    Assert.AreEqual('B.Plan', mCheck.Hints[0].Note);
    Assert.AreEqual('C:\G\A\A.dpk', mCheck.Hints[0].FileName);
    Assert.AreEqual(2, mCheck.Hints[0].Line);
    Assert.IsTrue(mCheck.Clean, 'ein Hinweis ist kein Fehler');
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.RequiresDcpOnlyIsHint;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\G\A\A.dpk', 'package A; requires rtl, Fremd; end.');
    mDisk.Add('C:\Lib\rtl.dcp', '');
    mDisk.Add('C:\G\Dcp\Fremd.dcp', '');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\G\A\A.dproj';
    mInput.Sources := ['C:\G\A\A.dpk'];
    mInput.SearchPaths := ['C:\G\Dcp'];
    mInput.LibraryPaths := ['C:\Lib'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('Fremd', FindingNames(mCheck.Hints), 'rtl in den Bibliothekspfaden ist normal');
    Assert.AreEqual('', mCheck.Hints[0].Note, 'ohne Quelle');
    Assert.AreEqual('', FindingNames(mCheck.MissingUnits));
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.FreePascalBranchIsQuiet;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\P\App.dpr', 'program App;' + sLineBreak + '{$IFDEF FPC} uses LCLIntf, Interfaces; {$ENDIF}' +
      sLineBreak + '{$IFDEF UNIX}{$ENDIF}{$IFDEF CPUX86_64}{$ENDIF}{$IFDEF ENDIAN_BIG}{$ENDIF}' +
      '{$IFDEF LCLgtk2}{$ENDIF}{$IFDEF FPC_FULLVERSION}{$ENDIF}{$IFDEF WINDOWS}{$ENDIF}{$IFDEF IMPLICITBUILDING}{$ENDIF}{$IFNDEF TESTINSIGHT}{$ENDIF}{$IFDEF CI}{$ENDIF}' + sLineBreak +
      'begin end.');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\P\App.dproj';
    mInput.Sources := ['C:\P\App.dpr'];
    mInput.ActiveDefines := ['MSWINDOWS', 'WIN64'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('', FindingNames(mCheck.MissingUnits), 'Units im inaktiven FPC-Zweig');
    Assert.AreEqual('', FindingNames(mCheck.UndefinedDefines), 'Symbole von Free Pascal und Lazarus');
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.DprojDefinesInherit;
const
  cDproj =
    '<Project>' + sLineBreak +
    '  <ItemGroup><BuildConfiguration Include="Debug"><Key>Cfg_1</Key></BuildConfiguration>' +
    '<BuildConfiguration Include="Release"><Key>Cfg_2</Key></BuildConfiguration></ItemGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''"><DCC_Define>FOO;$(DCC_Define)</DCC_Define></PropertyGroup>' +
    sLineBreak +
    '  <PropertyGroup Condition="''$(Cfg_1)''!=''''"><DCC_Define>DEBUG;$(DCC_Define)</DCC_Define></PropertyGroup>' +
    sLineBreak +
    '  <PropertyGroup Condition="''$(Cfg_1_Win32)''!=''''"><DCC_Define>W32;$(DCC_Define)</DCC_Define>' +
    '</PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Cfg_2)''!=''''"><DCC_Define>RELEASE</DCC_Define></PropertyGroup>' + sLineBreak +
    '</Project>';
begin
  Assert.AreEqual('DEBUG|FOO', string.Join('|', TAtlasPathCheck.DprojConfigDefines(cDproj, 'Debug', 'Win64')));
  Assert.AreEqual('W32|DEBUG|FOO', string.Join('|', TAtlasPathCheck.DprojConfigDefines(cDproj, 'Debug', 'Win32')));
  // Ohne $(DCC_Define) ersetzt die Konfiguration den geerbten Wert.
  Assert.AreEqual('RELEASE', string.Join('|', TAtlasPathCheck.DprojConfigDefines(cDproj, 'Release', 'Win64')));
end;

procedure TAtlasPathCheckTests.ScriptDefinesAreSources;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  Assert.AreEqual('LCLnogui|MY_FEATURE', string.Join('|', TAtlasPathCheck.ScriptDefines('build-app.sh',
    'fpc -dLCLnogui -Sa -dMY_FEATURE --dark -Fu"x" app.dpr')));
  Assert.AreEqual('FROM_LPK|OTHER', string.Join('|', TAtlasPathCheck.ScriptDefines('Pkg.lpk',
    '<ConditionalDefines Value="FROM_LPK;OTHER"/>')));
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\G\App\App.dpr', 'program App; {$IFDEF MY_FEATURE}{$ENDIF}{$IFDEF FROM_LPK}{$ENDIF}' +
      '{$IFDEF NOWHERE}{$ENDIF} begin end.');
    mDisk.Add('C:\G\build-app.sh', 'fpc -dLCLnogui -dMY_FEATURE app/App.dpr');
    mDisk.Add('C:\G\tools\Pkg.lpk', '<ConditionalDefines Value="FROM_LPK"/>');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\G\App\App.dproj';
    mInput.Sources := ['C:\G\App\App.dpr'];
    mInput.ScriptFolders := ['C:\G\App', 'C:\G', 'C:\G\tools'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('NOWHERE', FindingNames(mCheck.UndefinedDefines));
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.TypoGetsSuggestion;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  Assert.AreEqual('XMLI_TEST_FEATURES', TAtlasPathCheck.Suggest('XMLI_TEST_FEATRUES', ['DEBUG',
    'XMLI_TEST_FEATURES']));
  Assert.AreEqual('', TAtlasPathCheck.Suggest('X', ['Y']), 'kurze Namen nicht');
  Assert.AreEqual('', TAtlasPathCheck.Suggest('NOWHERE', ['DEBUG']));
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\P\App.dpr', 'program App; {$IFDEF XMLI_TEST_FEATRUES}{$ENDIF} begin end.');
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\P\App.dproj';
    mInput.Sources := ['C:\P\App.dpr'];
    mInput.ProjectDefines := ['XMLI_TEST_FEATURES'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('XMLI_TEST_FEATRUES', FindingNames(mCheck.UndefinedDefines));
    Assert.AreEqual('XMLI_TEST_FEATURES', mCheck.UndefinedDefines[0].Note);
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.UnitsInRequiredDcpAreFound;
var
  mDisk: TFakeDisk;
  mInput: TAtlasPathCheckInput;
  mCheck: TAtlasPathCheckResult;
begin
  mDisk := TFakeDisk.Create;
  try
    mDisk.Add('C:\G\A\A.dpk', 'package A; requires designide; contains A.Main in ''A.Main.pas''; end.');
    mDisk.Add('C:\G\A\A.Main.pas', 'unit A.Main; interface uses ToolsAPI, ToolsAPI.Editor, Fehlt; implementation end.');
    // Binärinhalt einer .dcp: Unit-Namen als kurze Zeichenketten.
    mDisk.Add('C:\Lib\designide.dcp', #8'ToolsAPI'#0#15'ToolsAPI.Editor'#0#1);
    mInput := Default(TAtlasPathCheckInput);
    mInput.Project := 'C:\G\A\A.dproj';
    mInput.Sources := ['C:\G\A\A.dpk', 'C:\G\A\A.Main.pas'];
    mInput.LibraryPaths := ['C:\Lib'];
    mCheck := RunOn(mDisk, mInput);
    Assert.AreEqual('Fehlt', FindingNames(mCheck.MissingUnits));
    Assert.AreEqual('', FindingNames(mCheck.Hints), 'designide in den Bibliothekspfaden ist normal');
  finally
    mDisk.Free;
  end;
end;

procedure TAtlasPathCheckTests.ScanUnitReadsMultilineStringsAndParenDirectives;
var
  mScan: TAtlasSourceScan;
begin
  mScan := TAtlasPathScan.Scan('unit A;'#13#10'uses B, {$IFDEF X} C, {$ENDIF} D;'#13#10'(*$DEFINE Y*)'#13#10 +
    'const S = '''''''#13#10'  uses Z;'#13#10'  '''''';'#13#10, ['X']);
  Assert.AreEqual('B|C|D', UnitNames(mScan));
  Assert.AreEqual(1, Integer(Length(mScan.Defined)));
  Assert.AreEqual('Y', mScan.Defined[0]);
  Assert.AreEqual<TAtlasBranchState>(TAtlasBranchState.Active,
    TAtlasPathScan.Evaluate('defined(X) and not defined(Y)', ['x']));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPathCheckTests);

end.
