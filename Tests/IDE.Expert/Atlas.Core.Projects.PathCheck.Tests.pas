unit Atlas.Core.Projects.PathCheck.Tests;

// Tests für „Suchpfade und Defines prüfen“ der Einrichtung (#759): uses und
// contains mit bedingten Abschnitten, $IF-Ausdrücke, fehlende Units mit Name
// und Zeile, Defines ohne Quelle samt eingebundener Dateien, Pfade und die
// Symbole aus der .dproj.

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
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Projects.PathCheck;

function UnitNames(const AScan: TAtlasSourceScan): string;
var
  Used: TAtlasUsedUnit;
begin
  Result := '';
  for Used in AScan.Units do
  begin
    if Result <> '' then
      Result := Result + '|';
    Result := Result + Used.Name;
  end;
end;

function StateNames(const AScan: TAtlasSourceScan): string;
const
  Names: array[TAtlasBranchState] of string = ('a', 'i', 'u');
var
  Used: TAtlasUsedUnit;
begin
  Result := '';
  for Used in AScan.Units do
    Result := Result + Names[Used.State];
end;

function FindingNames(const AFindings: TArray<TAtlasPathFinding>): string;
var
  Finding: TAtlasPathFinding;
begin
  Result := '';
  for Finding in AFindings do
  begin
    if Result <> '' then
      Result := Result + '|';
    Result := Result + Finding.Name;
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
  Path, Folder: string;
begin
  Result := nil;
  Folder := UpperCase(AFolder);
  if not Folder.EndsWith('\') then
    Folder := Folder + '\';
  for Path in FFiles.Keys do
    if Path.StartsWith(Folder) and (Pos('\', Copy(Path, Length(Folder) + 1, MaxInt)) = 0) then
      Result := Result + [Copy(Path, Length(Folder) + 1, MaxInt)];
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
  Scan: TAtlasSourceScan;
begin
  Scan := TAtlasPathCheck.Scan('program App;' + sLineBreak +
    'uses' + sLineBreak +
    '  System.SysUtils,' + sLineBreak +
    '  Main in ''Src\Main.pas'' {Form1},' + sLineBreak +
    '  &Type;' + sLineBreak +
    'begin' + sLineBreak +
    'end.', nil);
  Assert.IsFalse(Scan.IsPackage);
  Assert.AreEqual('System.SysUtils|Main|Type', UnitNames(Scan));
  Assert.AreEqual(3, Scan.Units[0].Line);
  Assert.AreEqual(4, Scan.Units[1].Line);
  Assert.AreEqual('Src\Main.pas', Scan.Units[1].InFile);
  Assert.AreEqual('', Scan.Units[0].InFile);
  Assert.AreEqual('aaa', StateNames(Scan));
end;

procedure TAtlasPathCheckTests.ScansContainsOnlyInPackages;
var
  Scan: TAtlasSourceScan;
begin
  Scan := TAtlasPathCheck.Scan('package Pkg;' + sLineBreak +
    'requires rtl, vcl;' + sLineBreak +
    'contains A in ''A.pas'', B.C;' + sLineBreak +
    'end.', nil);
  Assert.IsTrue(Scan.IsPackage);
  Assert.AreEqual('A|B.C', UnitNames(Scan));
  // In einer Unit ist contains kein Schlüsselwort.
  Scan := TAtlasPathCheck.Scan('unit U; interface var contains: Integer; implementation uses X; end.', nil);
  Assert.AreEqual('X', UnitNames(Scan));
end;

procedure TAtlasPathCheckTests.IgnoresCommentsAndStrings;
var
  Scan: TAtlasSourceScan;
begin
  Scan := TAtlasPathCheck.Scan('unit U;' + sLineBreak +
    '// uses Comment1;' + sLineBreak +
    '{ uses Comment2; }' + sLineBreak +
    '(* uses Comment3; *)' + sLineBreak +
    'interface' + sLineBreak +
    'const S = ''uses Text;'';' + sLineBreak +
    'implementation' + sLineBreak +
    'uses Real { , Hidden };' + sLineBreak +
    'end.', nil);
  Assert.AreEqual('Real', UnitNames(Scan));
  Assert.AreEqual(8, Scan.Units[0].Line);
end;

procedure TAtlasPathCheckTests.EvaluatesBranches;
var
  Scan: TAtlasSourceScan;
begin
  Scan := TAtlasPathCheck.Scan('unit U; interface uses' + sLineBreak +
    '  A' + sLineBreak +
    '  {$IFDEF DEBUG}, B {$ELSE}, C {$ENDIF}' + sLineBreak +
    '  {$IFNDEF DEBUG}, D {$ENDIF}' + sLineBreak +
    '  {$IF DEFINED(MSWINDOWS) and not DEFINED(DEBUG)}, E' + sLineBreak +
    '  {$ELSEIF DEFINED(DEBUG)}, F' + sLineBreak +
    '  {$ELSE}, G {$IFEND}' + sLineBreak +
    '  {$IFDEF MISSING} {$IFDEF DEBUG}, H {$ENDIF} {$ENDIF};' + sLineBreak +
    'implementation end.', ['debug', 'MSWINDOWS']);
  Assert.AreEqual('A|B|C|D|E|F|G|H', UnitNames(Scan));
  Assert.AreEqual('aaiiiaii', StateNames(Scan));
  Assert.AreEqual(3, Scan.Units[1].Line);
end;

procedure TAtlasPathCheckTests.UnknownConditionsStayUnknown;
var
  Scan: TAtlasSourceScan;
begin
  Scan := TAtlasPathCheck.Scan('unit U; interface uses A' +
    '{$IF CompilerVersion >= 36}, B {$ELSEIF DEFINED(X)}, C {$ELSE}, D {$IFEND}' +
    '{$IFOPT R+}, E {$ELSE}, F {$ENDIF}' +
    '{$IF CompilerVersion >= 36}{$IFDEF X}, G{$ENDIF}{$IFNDEF X}, H{$ENDIF}{$IFEND}' +
    '{$IF Declared(Foo)}, I {$ELSEIF DEFINED(X)}, J {$ELSEIF DEFINED(Y)}, K {$IFEND};' +
    'implementation end.', ['X']);
  Assert.AreEqual('A|B|C|D|E|F|G|H|I|J|K', UnitNames(Scan));
  // C gilt, wenn B nicht gilt: unbekannt; D kann nicht mehr gelten, weil sonst C sicher gilt.
  // Unter einem unbekannten Zweig bleibt ein sicherer Zweig unbekannt (G), ein falscher fällt weg (H).
  // K kann nicht gelten, weil sonst J sicher gilt.
  Assert.AreEqual('auuiuuuiuui', StateNames(Scan));
end;

procedure TAtlasPathCheckTests.TracksDefinesAndIncludes;
var
  Scan: TAtlasSourceScan;
begin
  Scan := TAtlasPathCheck.Scan('unit U;' + sLineBreak +
    '{$I Common.inc}' + sLineBreak +
    '{$INCLUDE ''Sub\More.inc''}' + sLineBreak +
    '{$I+}' + sLineBreak +
    '{$DEFINE USE_X}' + sLineBreak +
    '{$IFDEF NEVER}{$DEFINE LATER}{$ENDIF}' + sLineBreak +
    'interface uses A {$IFDEF USE_X}, B {$ENDIF} {$IFDEF LATER}, C {$ENDIF};' + sLineBreak +
    '{$UNDEF USE_X}' + sLineBreak +
    'implementation uses D {$IFDEF USE_X}, E {$ENDIF}; end.', nil);
  Assert.AreEqual('Common.inc|Sub\More.inc', string.Join('|', Scan.Includes));
  Assert.AreEqual('USE_X|LATER', string.Join('|', Scan.Defined));
  Assert.AreEqual('A|B|C|D|E', UnitNames(Scan));
  Assert.AreEqual('aaiai', StateNames(Scan));
  Assert.AreEqual(4, Integer(Length(Scan.Referenced)));
  Assert.AreEqual('NEVER', Scan.Referenced[0].Name);
  Assert.AreEqual(6, Scan.Referenced[0].Line);
end;

procedure TAtlasPathCheckTests.EvaluatesExpressions;
begin
  Assert.IsTrue(TAtlasPathCheck.Evaluate('DEFINED(A)', ['a']) = TAtlasBranchState.Active);
  Assert.IsTrue(TAtlasPathCheck.Evaluate('defined(A) and not Defined(B)', ['A']) = TAtlasBranchState.Active);
  Assert.IsTrue(TAtlasPathCheck.Evaluate('DEFINED(A) AND DEFINED(B)', ['A']) = TAtlasBranchState.Inactive);
  Assert.IsTrue(TAtlasPathCheck.Evaluate('(DEFINED(A) or DEFINED(B)) and not (DEFINED(C))', ['B']) =
    TAtlasBranchState.Active);
  Assert.IsTrue(TAtlasPathCheck.Evaluate('CompilerVersion >= 36', ['A']) = TAtlasBranchState.Unknown);
  Assert.IsTrue(TAtlasPathCheck.Evaluate('DEFINED(A) or (RTLVersion > 1)', ['A']) = TAtlasBranchState.Unknown);
  Assert.IsTrue(TAtlasPathCheck.Evaluate('DEFINED(A', ['A']) = TAtlasBranchState.Unknown);
  Assert.IsTrue(TAtlasPathCheck.Evaluate('', nil) = TAtlasBranchState.Unknown);
end;

procedure TAtlasPathCheckTests.ReportsMissingUnitWithName;
var
  Disk: TFakeDisk;
  Input: TAtlasPathCheckInput;
  Check: TAtlasPathCheckResult;
begin
  Disk := TFakeDisk.Create;
  try
    Disk.Add('C:\P\App.dpr', 'program App;' + sLineBreak + 'uses' + sLineBreak + '  Main in ''Src\Main.pas'',' +
      sLineBreak + '  Helpers;' + sLineBreak + 'begin end.');
    Disk.Add('C:\P\Src\Main.pas', 'unit Main; interface uses System.SysUtils; implementation uses Helpers; end.');
    Disk.Add('C:\RTL\System.SysUtils.dcu', '');
    Input := Default(TAtlasPathCheckInput);
    Input.Project := 'C:\P\App.dproj';
    Input.Sources := ['C:\P\App.dpr', 'C:\P\Src\Main.pas'];
    Input.LibraryPaths := ['C:\RTL'];
    Check := RunOn(Disk, Input);
    Assert.AreEqual(2, Check.Files);
    Assert.IsFalse(Check.Clean);
    Assert.AreEqual('Helpers', FindingNames(Check.MissingUnits));
    Assert.AreEqual('C:\P\App.dpr', Check.MissingUnits[0].FileName);
    Assert.AreEqual(4, Check.MissingUnits[0].Line);
    Assert.AreEqual(2, Check.MissingUnits[0].Count);
    // Mit dem Suchpfad ist die Unit da, alles ist sauber.
    Disk.Add('C:\Shared\Helpers.pas', 'unit Helpers; interface implementation end.');
    Input.SearchPaths := ['C:\Shared'];
    Check := RunOn(Disk, Input);
    Assert.AreEqual('', FindingNames(Check.MissingUnits));
    Assert.IsTrue(Check.Clean);
  finally
    Disk.Free;
  end;
end;

procedure TAtlasPathCheckTests.ResolvesNamespacesPathsAndDcu;
var
  Disk: TFakeDisk;
  Input: TAtlasPathCheckInput;
  Check: TAtlasPathCheckResult;
begin
  Disk := TFakeDisk.Create;
  try
    Disk.Add('C:\P\App.dpr', 'program App; uses System, SysUtils, Vcl.Forms, Forms, Local, Beside, Compiled, ' +
      'Gone in ''..\Gone.pas'', There in ''..\There.pas'', Main' +
      '{$IFDEF LINUX}, LinuxOnly{$ENDIF}{$IF CompilerVersion > 35}, Maybe{$IFEND}; begin end.');
    Disk.Add('C:\P\Main.pas', 'unit Main; interface implementation end.');
    Disk.Add('C:\P\Local.pas', '');
    Disk.Add('C:\There.pas', '');
    Disk.Add('C:\Lib\Compiled.DCU', '');
    Disk.Add('C:\RTL\System.SysUtils.dcu', '');
    Disk.Add('C:\RTL\Vcl.Forms.dcu', '');
    Disk.Add('C:\Src\App\Beside.pas', '');
    Input := Default(TAtlasPathCheckInput);
    Input.Project := 'C:\P\App.dproj';
    Input.Sources := ['C:\P\App.dpr', 'C:\P\Main.pas'];
    Input.SearchPaths := ['C:\Lib', '', 'C:\Src\App'];
    Input.LibraryPaths := ['C:\RTL'];
    Input.Namespaces := ['System', 'Vcl', ' '];
    Input.ActiveDefines := ['MSWINDOWS'];
    Check := RunOn(Disk, Input);
    Assert.AreEqual('Gone', FindingNames(Check.MissingUnits));
  finally
    Disk.Free;
  end;
end;

procedure TAtlasPathCheckTests.ReportsDefinesWithoutSource;
var
  Disk: TFakeDisk;
  Input: TAtlasPathCheckInput;
  Check: TAtlasPathCheckResult;
begin
  Disk := TFakeDisk.Create;
  try
    Disk.Add('C:\P\App.dpr', 'program App;' + sLineBreak +
      '{$I Common.inc}' + sLineBreak +
      '{$IFDEF USE_LOG}{$ENDIF}' + sLineBreak +
      '{$IFDEF DEBUG}{$ENDIF}{$IFDEF RELEASE}{$ENDIF}' + sLineBreak +
      '{$IFDEF MSWINDOWS}{$ENDIF}{$IFDEF VER360}{$ENDIF}{$IFDEF FPC}{$ENDIF}' + sLineBreak +
      '{$IF DEFINED(FROM_INC) or DEFINED(FROM_SUB)}{$IFEND}' + sLineBreak +
      '{$IFNDEF LOCAL}{$DEFINE LOCAL}{$ENDIF}' + sLineBreak +
      'uses Main; begin end.');
    Disk.Add('C:\P\Main.pas', 'unit Main; interface {$IFDEF USE_LOG}{$ENDIF}{$IFDEF OTHER}{$ENDIF} implementation end.');
    Disk.Add('C:\P\Common.inc', '{$DEFINE FROM_INC}{$IFDEF FROM_LIBRARY}{$ENDIF}{$I Inc\Sub}');
    Disk.Add('C:\P\Inc\Sub.inc', '{$DEFINE FROM_SUB}{$I ..\Common.inc}');
    Input := Default(TAtlasPathCheckInput);
    Input.Project := 'C:\P\App.dproj';
    Input.Sources := ['C:\P\App.dpr', 'C:\P\Main.pas'];
    Input.ActiveDefines := ['DEBUG', 'MSWINDOWS'];
    Input.ProjectDefines := ['DEBUG', 'RELEASE'];
    Check := RunOn(Disk, Input);
    Assert.AreEqual('', FindingNames(Check.MissingUnits));
    // FROM_LIBRARY wird nur in der eingebundenen Datei abgefragt und zählt nicht.
    Assert.AreEqual('USE_LOG|OTHER', FindingNames(Check.UndefinedDefines));
    Assert.AreEqual('C:\P\App.dpr', Check.UndefinedDefines[0].FileName);
    Assert.AreEqual(3, Check.UndefinedDefines[0].Line);
    Assert.AreEqual(2, Check.UndefinedDefines[0].Count);
    Assert.AreEqual('C:\P\Main.pas', Check.UndefinedDefines[1].FileName);
  finally
    Disk.Free;
  end;
end;

procedure TAtlasPathCheckTests.CountsUnreadableFiles;
var
  Disk: TFakeDisk;
  Input: TAtlasPathCheckInput;
  Check: TAtlasPathCheckResult;
begin
  Disk := TFakeDisk.Create;
  try
    Disk.Add('C:\P\App.dpr', 'program App; uses Gone; begin end.');
    Input := Default(TAtlasPathCheckInput);
    Input.Project := 'C:\P\App.dproj';
    Input.Sources := ['C:\P\App.dpr', 'C:\P\Gone.pas', 'C:\P\App.dpr'];
    Check := RunOn(Disk, Input);
    Assert.AreEqual(1, Check.Files);
    Assert.AreEqual(1, Check.Unreadable);
    // Gone ist eine Datei des Projekts: Der Compiler kennt sie, auch wenn sie nicht lesbar ist.
    Assert.IsTrue(Check.Clean);
  finally
    Disk.Free;
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
  Variable: TAtlasPathVariable;
begin
  Variable :=
    function(const AName: string): string
    begin
      Result := '';
      if SameText(AName, 'BDS') then
        Result := 'C:\Delphi'
      else if SameText(AName, 'Platform') then
        Result := 'Win64';
    end;
  Assert.AreEqual('C:\Delphi\lib\Win64\release', TAtlasPathCheck.ExpandPath('$(BDS)\lib\$(Platform)\release\',
    'C:\P', Variable));
  Assert.AreEqual('C:\Lib', TAtlasPathCheck.ExpandPath(' ..\Lib ', 'C:\P', Variable));
  Assert.AreEqual('', TAtlasPathCheck.ExpandPath('$(Unknown)\x', 'C:\P', Variable));
  Assert.AreEqual('', TAtlasPathCheck.ExpandPath('$(BDS', 'C:\P', Variable));
  Assert.AreEqual('', TAtlasPathCheck.ExpandPath('  ', 'C:\P', Variable));
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasPathCheckTests);

end.
