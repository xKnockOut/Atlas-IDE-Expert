unit Atlas.Common.Leaks.Setup.Tests;

// Tests für „Leckprüfung einrichten“ (#1880): FastMM-Quellen, Version und DLL
// erkennen, Hauptquelltext auswerten (uses, ReportMemoryLeaksOnShutdown,
// Debug-Bedingungen) und die Einfügungen samt Symbolen planen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Leaks.Setup;

type
  [TestFixture]
  TLeakSetupTests = class
  private
    FFiles: ILeakSetupFiles;
    function Input(const AText: string): TLeakSetupInput;
    /// <summary>AText mit allen Einfügungen von APlan (von hinten nach vorn).</summary>
    class function Applied(const AText: string; const APlan: TLeakSetupPlan): string; static;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DllNameFollowsPlatform;
    [Test]
    procedure VersionFromFastMM4Constant;
    [Test]
    procedure VersionFromFastMM5Header;
    [Test]
    procedure FindsSourcesOptionsAndDllTemplate;
    [Test]
    procedure FindsDllInOutputFolder;
    [Test]
    procedure PlainProjectHasNothing;
    [Test]
    procedure ManagerFirstInDebugUses;
    [Test]
    procedure ManagerNotFirst;
    [Test]
    procedure ReportOutsideDebugIsNoted;
    [Test]
    procedure ReportInIfDefinedDebug;
    [Test]
    procedure ElseOfIfndefDebugCountsAsDebug;
    [Test]
    procedure CommentsAndStringsDoNotCount;
    [Test]
    procedure TestProjectWithLeakMonitor;
    [Test]
    procedure DefinesOfDebugConfiguration;
    [Test]
    procedure SimplePlanInsertsGuardedLine;
    [Test]
    procedure SimplePlanEmptyWhenReportExists;
    [Test]
    procedure FastMM4PlanInsertsUnitFirstAndDefine;
    [Test]
    procedure FastMM4PlanUsesOnSameLine;
    [Test]
    procedure FastMM5FileReportPlan;
    [Test]
    procedure FastMM4FileReportIsDefine;
    [Test]
    procedure SetUpProjectPlansNothing;
    [Test]
    procedure PackagePlansNothing;
    [Test]
    procedure CopyDllOnlyWithTemplateAndTarget;
    [Test]
    procedure KeepsLineBreakStyle;
    [Test]
    procedure MainScanFindsBlockAfterRoutines;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Leaks.Internals.MainScan;

type
  TFakeFiles = class(TInterfacedObject, ILeakSetupFiles)
  private
    FTexts: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AFileName, AText: string);
    function FileExists(const AFileName: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
  end;

const
  cBreak = #13#10;
  cProject = 'C:\P\App.dproj';
  cMain = 'C:\P\App.dpr';
  cLib = 'C:\Lib\FastMM4';
  cLib5 = 'C:\Lib\FastMM5';
  cOut = 'C:\P\Win32\Debug';

  cPlain =
    'program App;' + cBreak +
    '' + cBreak +
    'uses' + cBreak +
    '  Vcl.Forms,' + cBreak +
    '  Main in ''Main.pas'' {MainForm};' + cBreak +
    '' + cBreak +
    '{$R *.res}' + cBreak +
    '' + cBreak +
    'begin' + cBreak +
    '  Application.Initialize;' + cBreak +
    '  Application.Run;' + cBreak +
    'end.' + cBreak;

/// <summary>Pfad mit dem Trenner der Plattform (die Tests laufen auch unter Linux).</summary>
function N(const APath: string): string;
begin
  Result := StringReplace(APath, '\', PathDelim, [rfReplaceAll]);
end;

constructor TFakeFiles.Create;
begin
  inherited Create;
  FTexts := TDictionary<string, string>.Create;
end;

destructor TFakeFiles.Destroy;
begin
  FTexts.Free;
  inherited;
end;

procedure TFakeFiles.Add(const AFileName, AText: string);
begin
  FTexts.AddOrSetValue(UpperCase(AFileName), AText);
end;

function TFakeFiles.FileExists(const AFileName: string): Boolean;
begin
  Result := FTexts.ContainsKey(UpperCase(AFileName));
end;

function TFakeFiles.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FTexts.TryGetValue(UpperCase(AFileName), AText);
end;

{ TLeakSetupTests }

procedure TLeakSetupTests.Setup;
var
  mFiles: TFakeFiles;
begin
  mFiles := TFakeFiles.Create;
  FFiles := mFiles;
  mFiles.Add(N(cLib + '\FastMM4.pas'), 'unit FastMM4;' + cBreak + 'const' + cBreak + '  FastMMVersion = ''4.993'';');
  mFiles.Add(N(cLib + '\FastMM4Options.inc'), '{$define EnableMemoryLeakReporting}');
  mFiles.Add(N(cLib + '\FullDebugMode DLL\Precompiled\FastMM_FullDebugMode.dll'), '');
  mFiles.Add(N(cLib + '\FullDebugMode DLL\Precompiled\FastMM_FullDebugMode64.dll'), '');
  mFiles.Add(N(cLib5 + '\FastMM5.pas'), '{' + cBreak + 'FastMM 5.04' + cBreak + '}' + cBreak + 'unit FastMM5;');
end;

procedure TLeakSetupTests.TearDown;
begin
  FFiles := nil;
end;

function TLeakSetupTests.Input(const AText: string): TLeakSetupInput;
begin
  Result := Default(TLeakSetupInput);
  Result.ProjectFile := cProject;
  Result.MainSource := cMain;
  Result.MainText := AText;
  Result.Platform := 'Win32';
  Result.OutputFolder := N(cOut);
  Result.SearchFolders := TArray<string>.Create(N('C:\P'), N(cLib), N(cLib5));
end;

class function TLeakSetupTests.Applied(const AText: string; const APlan: TLeakSetupPlan): string;
var
  mLines: TArray<string>;
  mEdit: TLeakSetupEdit;
  mLine: string;
begin
  mLines := AText.Split([#10]);
  for mEdit in APlan.Edits do
  begin
    mLine := mLines[mEdit.Line];
    mLines[mEdit.Line] := Copy(mLine, 1, mEdit.Character) + mEdit.Text + Copy(mLine, mEdit.Character + 1, MaxInt);
  end;
  Result := string.Join(#10, mLines);
end;

procedure TLeakSetupTests.DllNameFollowsPlatform;
begin
  Assert.AreEqual('FastMM_FullDebugMode.dll', TLeakSetup.DllNameOf('Win32'));
  Assert.AreEqual('FastMM_FullDebugMode64.dll', TLeakSetup.DllNameOf('Win64'));
  Assert.AreEqual('FastMM_FullDebugMode64.dll', TLeakSetup.DllNameOf('win64'));
end;

procedure TLeakSetupTests.VersionFromFastMM4Constant;
begin
  Assert.AreEqual('4.993', TLeakSetup.VersionOf(TLeakManager.FastMM4, 'const' + cBreak +
    '  FastMMVersion = ''4.993'';'));
  Assert.AreEqual('', TLeakSetup.VersionOf(TLeakManager.FastMM4, 'unit FastMM4;'));
end;

procedure TLeakSetupTests.VersionFromFastMM5Header;
begin
  Assert.AreEqual('5.04', TLeakSetup.VersionOf(TLeakManager.FastMM5, 'FastMM 5.04.' + cBreak + 'unit FastMM5;'));
  Assert.AreEqual('', TLeakSetup.VersionOf(TLeakManager.FastMM5, 'unit FastMM5;'));
end;

procedure TLeakSetupTests.FindsSourcesOptionsAndDllTemplate;
var
  mState: TLeakSetupState;
begin
  mState := TLeakSetup.Analyze(Input(cPlain), FFiles);
  Assert.AreEqual(N(cLib + '\FastMM4.pas'), mState.Sources[TLeakManager.FastMM4].FileName);
  Assert.AreEqual('4.993', mState.Sources[TLeakManager.FastMM4].Version);
  Assert.AreEqual(N(cLib + '\FastMM4Options.inc'), mState.Sources[TLeakManager.FastMM4].OptionsFile);
  Assert.AreEqual(N(cLib5 + '\FastMM5.pas'), mState.Sources[TLeakManager.FastMM5].FileName);
  Assert.AreEqual('5.04', mState.Sources[TLeakManager.FastMM5].Version);
  Assert.AreEqual('FastMM_FullDebugMode.dll', mState.DllName);
  Assert.AreEqual('', mState.DllFile);
  Assert.AreEqual(N(cLib + '\FullDebugMode DLL\Precompiled\FastMM_FullDebugMode.dll'), mState.DllSource);
  Assert.AreEqual(N(cOut), mState.DllTarget);
end;

procedure TLeakSetupTests.FindsDllInOutputFolder;
var
  mInput: TLeakSetupInput;
  mState: TLeakSetupState;
begin
  (FFiles as TFakeFiles).Add(N('C:\P\Win64\Debug\FastMM_FullDebugMode64.dll'), '');
  mInput := Input(cPlain);
  mInput.Platform := 'Win64';
  mInput.OutputFolder := N('C:\P\Win64\Debug');
  mState := TLeakSetup.Analyze(mInput, FFiles);
  Assert.AreEqual(N('C:\P\Win64\Debug\FastMM_FullDebugMode64.dll'), mState.DllFile);
end;

procedure TLeakSetupTests.PlainProjectHasNothing;
var
  mState: TLeakSetupState;
begin
  mState := TLeakSetup.Analyze(Input(cPlain), nil);
  Assert.IsFalse(mState.Sources[TLeakManager.FastMM4].Found);
  Assert.AreEqual<TLeakManager>(TLeakManager.None, mState.UsesManager);
  Assert.AreEqual(0, mState.ReportLine);
  Assert.IsTrue(mState.HasUses);
  Assert.IsTrue(mState.HasMainBlock);
  Assert.IsFalse(mState.IsTestProject);
  Assert.IsFalse(mState.IsPackage);
end;

procedure TLeakSetupTests.ManagerFirstInDebugUses;
var
  mState: TLeakSetupState;
begin
  mState := Default(TLeakSetupState);
  TLeakSetup.ScanMain('program App;' + cBreak + 'uses' + cBreak + '  {$IFDEF DEBUG}' + cBreak + '  FastMM4,' +
    cBreak + '  {$ENDIF}' + cBreak + '  System.SysUtils;' + cBreak + 'begin' + cBreak + 'end.', mState);
  Assert.AreEqual<TLeakManager>(TLeakManager.FastMM4, mState.UsesManager);
  Assert.IsTrue(mState.UsesFirst);
  Assert.IsTrue(mState.UsesDebugOnly);
end;

procedure TLeakSetupTests.ManagerNotFirst;
var
  mState: TLeakSetupState;
begin
  mState := Default(TLeakSetupState);
  TLeakSetup.ScanMain('program App; uses System.SysUtils, FastMM5; begin end.', mState);
  Assert.AreEqual<TLeakManager>(TLeakManager.FastMM5, mState.UsesManager);
  Assert.IsFalse(mState.UsesFirst);
  Assert.IsFalse(mState.UsesDebugOnly);
end;

procedure TLeakSetupTests.ReportOutsideDebugIsNoted;
var
  mState: TLeakSetupState;
begin
  mState := Default(TLeakSetupState);
  TLeakSetup.ScanMain('program App;' + cBreak + 'begin' + cBreak + '  ReportMemoryLeaksOnShutdown := True;' + cBreak +
    'end.', mState);
  Assert.AreEqual(3, mState.ReportLine);
  Assert.IsFalse(mState.ReportDebugOnly);
end;

procedure TLeakSetupTests.ReportInIfDefinedDebug;
var
  mState: TLeakSetupState;
begin
  mState := Default(TLeakSetupState);
  TLeakSetup.ScanMain('program App;' + cBreak + 'begin' + cBreak + '{$IF Defined(DEBUG)}' + cBreak +
    '  ReportMemoryLeaksOnShutdown := True;' + cBreak + '{$IFEND}' + cBreak + 'end.', mState);
  Assert.AreEqual(4, mState.ReportLine);
  Assert.IsTrue(mState.ReportDebugOnly);
end;

procedure TLeakSetupTests.ElseOfIfndefDebugCountsAsDebug;
var
  mState: TLeakSetupState;
begin
  mState := Default(TLeakSetupState);
  TLeakSetup.ScanMain('program App;' + cBreak + 'begin' + cBreak + '{$IFNDEF DEBUG}' + cBreak + '  Exit;' + cBreak +
    '{$ELSE}' + cBreak + '  ReportMemoryLeaksOnShutdown := True;' + cBreak + '{$ENDIF}' + cBreak + 'end.', mState);
  Assert.AreEqual(6, mState.ReportLine);
  Assert.IsTrue(mState.ReportDebugOnly);
end;

procedure TLeakSetupTests.CommentsAndStringsDoNotCount;
var
  mState: TLeakSetupState;
begin
  mState := Default(TLeakSetupState);
  TLeakSetup.ScanMain('program App;' + cBreak + '// uses FastMM4;' + cBreak + 'begin' + cBreak +
    '  { ReportMemoryLeaksOnShutdown := True; }' + cBreak + '  Writeln(''ReportMemoryLeaksOnShutdown := True'');' +
    cBreak + 'end.', mState);
  Assert.AreEqual(0, mState.ReportLine);
  Assert.IsFalse(mState.HasUses);
  Assert.IsTrue(mState.HasMainBlock);
end;

procedure TLeakSetupTests.TestProjectWithLeakMonitor;
var
  mState: TLeakSetupState;
begin
  mState := Default(TLeakSetupState);
  TLeakSetup.ScanMain('program Tests;' + cBreak + 'uses' + cBreak + '  FastMM5,' + cBreak +
    '  DUnitX.MemoryLeakMonitor.FastMM5,' + cBreak + '  DUnitX.TestFramework;' + cBreak + 'begin' + cBreak +
    'end.', mState);
  Assert.IsTrue(mState.IsTestProject);
  Assert.AreEqual('DUnitX.MemoryLeakMonitor.FastMM5', mState.LeakMonitor);
  Assert.IsTrue(mState.UsesFirst);
end;

procedure TLeakSetupTests.DefinesOfDebugConfiguration;
var
  mInput: TLeakSetupInput;
  mState: TLeakSetupState;
begin
  mInput := Input('program App; uses FastMM4, SysUtils; begin end.');
  mInput.DebugDefines := TArray<string>.Create('DEBUG', 'FULLDEBUGMODE', 'NOMESSAGEBOXES');
  mState := TLeakSetup.Analyze(mInput, FFiles);
  Assert.IsTrue(mState.DebugDefine);
  Assert.IsTrue(mState.FileReport);
end;

procedure TLeakSetupTests.SimplePlanInsertsGuardedLine;
var
  mState: TLeakSetupState;
  mPlan: TLeakSetupPlan;
begin
  mState := TLeakSetup.Analyze(Input(cPlain), FFiles);
  mPlan := TLeakSetup.Plan(mState, cPlain, TLeakManager.None, False);
  Assert.AreEqual(1, Integer(Length(mPlan.Edits)));
  Assert.AreEqual(0, Integer(Length(mPlan.Defines)));
  Assert.IsFalse(mPlan.CopyDll);
  Assert.IsTrue(Pos(
    'begin' + cBreak +
    '  {$IFDEF DEBUG}' + cBreak +
    '  ReportMemoryLeaksOnShutdown := DebugHook <> 0;' + cBreak +
    '  {$ENDIF}' + cBreak +
    '  Application.Initialize;', Applied(cPlain, mPlan)) > 0, Applied(cPlain, mPlan));
  // Danach gilt die Zeile als vorhanden und nur in Debug.
  mState := TLeakSetup.Analyze(Input(Applied(cPlain, mPlan)), FFiles);
  Assert.AreEqual(11, mState.ReportLine);
  Assert.IsTrue(mState.ReportDebugOnly);
end;

procedure TLeakSetupTests.SimplePlanEmptyWhenReportExists;
var
  mText: string;
  mState: TLeakSetupState;
begin
  mText := 'program App;' + cBreak + 'begin' + cBreak + '  ReportMemoryLeaksOnShutdown := True;' + cBreak + 'end.';
  mState := TLeakSetup.Analyze(Input(mText), FFiles);
  Assert.IsTrue(TLeakSetup.Plan(mState, mText, TLeakManager.None, False).IsEmpty);
end;

procedure TLeakSetupTests.FastMM4PlanInsertsUnitFirstAndDefine;
var
  mState: TLeakSetupState;
  mPlan: TLeakSetupPlan;
  mText: string;
begin
  mState := TLeakSetup.Analyze(Input(cPlain), FFiles);
  mPlan := TLeakSetup.Plan(mState, cPlain, TLeakManager.FastMM4, False);
  Assert.AreEqual(2, Integer(Length(mPlan.Edits)));
  Assert.AreEqual('FullDebugMode', string.Join(',', mPlan.Defines));
  Assert.IsTrue(mPlan.CopyDll);
  mText := Applied(cPlain, mPlan);
  Assert.IsTrue(Pos('uses' + cBreak + '  {$IFDEF DEBUG}' + cBreak + '  FastMM4,' + cBreak + '  {$ENDIF}' + cBreak +
    '  Vcl.Forms,', mText) > 0, mText);
  mState := TLeakSetup.Analyze(Input(mText), FFiles);
  Assert.AreEqual<TLeakManager>(TLeakManager.FastMM4, mState.UsesManager);
  Assert.IsTrue(mState.UsesFirst);
  Assert.IsTrue(mState.UsesDebugOnly);
  Assert.IsTrue(mState.ReportDebugOnly);
end;

procedure TLeakSetupTests.FastMM4PlanUsesOnSameLine;
var
  mText: string;
  mState: TLeakSetupState;
  mPlan: TLeakSetupPlan;
begin
  mText := 'program App;' + cBreak + 'uses SysUtils;' + cBreak + 'begin' + cBreak + 'end.';
  mState := TLeakSetup.Analyze(Input(mText), FFiles);
  mPlan := TLeakSetup.Plan(mState, mText, TLeakManager.FastMM4, False);
  mText := Applied(mText, mPlan);
  Assert.IsTrue(Pos('uses {$IFDEF DEBUG}FastMM4,{$ENDIF} SysUtils;', mText) > 0, mText);
end;

procedure TLeakSetupTests.FastMM5FileReportPlan;
var
  mState: TLeakSetupState;
  mPlan: TLeakSetupPlan;
  mText: string;
begin
  mState := TLeakSetup.Analyze(Input(cPlain), FFiles);
  mPlan := TLeakSetup.Plan(mState, cPlain, TLeakManager.FastMM5, True);
  Assert.AreEqual('FastMM_FullDebugMode', string.Join(',', mPlan.Defines));
  mText := Applied(cPlain, mPlan);
  Assert.IsTrue(Pos('  FastMM_LogToFileEvents := FastMM_LogToFileEvents + [mmetUnexpectedMemoryLeakDetail, ' +
    'mmetUnexpectedMemoryLeakSummary];', mText) > 0, mText);
  mState := TLeakSetup.Analyze(Input(mText), FFiles);
  Assert.IsTrue(mState.FileReport);
  Assert.AreEqual<TLeakManager>(TLeakManager.FastMM5, mState.UsesManager);
end;

procedure TLeakSetupTests.FastMM4FileReportIsDefine;
var
  mState: TLeakSetupState;
  mPlan: TLeakSetupPlan;
begin
  mState := TLeakSetup.Analyze(Input(cPlain), FFiles);
  mPlan := TLeakSetup.Plan(mState, cPlain, TLeakManager.FastMM4, True);
  Assert.AreEqual('FullDebugMode,NoMessageBoxes', string.Join(',', mPlan.Defines));
end;

procedure TLeakSetupTests.SetUpProjectPlansNothing;
var
  mInput: TLeakSetupInput;
  mState: TLeakSetupState;
  mText: string;
begin
  (FFiles as TFakeFiles).Add(N(cOut + '\FastMM_FullDebugMode.dll'), '');
  mText := 'program App;' + cBreak + 'uses' + cBreak + '  {$IFDEF DEBUG}FastMM4,{$ENDIF}' + cBreak + '  SysUtils;' +
    cBreak + 'begin' + cBreak + '  {$IFDEF DEBUG}' + cBreak + '  ReportMemoryLeaksOnShutdown := True;' + cBreak +
    '  {$ENDIF}' + cBreak + 'end.';
  mInput := Input(mText);
  mInput.DebugDefines := TArray<string>.Create('DEBUG', 'FullDebugMode');
  mState := TLeakSetup.Analyze(mInput, FFiles);
  Assert.IsTrue(TLeakSetup.Plan(mState, mText, TLeakManager.FastMM4, False).IsEmpty);
  // Anderer Speichermanager als der vorhandene: keine zweite Unit, kein Symbol.
  Assert.IsTrue(TLeakSetup.Plan(mState, mText, TLeakManager.FastMM5, False).IsEmpty);
end;

procedure TLeakSetupTests.PackagePlansNothing;
var
  mInput: TLeakSetupInput;
  mState: TLeakSetupState;
begin
  mInput := Input('package Pkg; requires rtl; end.');
  mInput.MainSource := 'C:\P\Pkg.dpk';
  mState := TLeakSetup.Analyze(mInput, FFiles);
  Assert.IsTrue(mState.IsPackage);
  Assert.IsTrue(TLeakSetup.Plan(mState, mInput.MainText, TLeakManager.FastMM4, True).IsEmpty);
end;

procedure TLeakSetupTests.CopyDllOnlyWithTemplateAndTarget;
var
  mInput: TLeakSetupInput;
  mState: TLeakSetupState;
begin
  mInput := Input(cPlain);
  mInput.OutputFolder := '';
  mState := TLeakSetup.Analyze(mInput, FFiles);
  Assert.IsFalse(TLeakSetup.Plan(mState, cPlain, TLeakManager.FastMM4, False).CopyDll);
  mState := TLeakSetup.Analyze(Input(cPlain), FFiles);
  Assert.IsFalse(TLeakSetup.Plan(mState, cPlain, TLeakManager.None, False).CopyDll);
end;

procedure TLeakSetupTests.KeepsLineBreakStyle;
var
  mText: string;
  mState: TLeakSetupState;
  mPlan: TLeakSetupPlan;
begin
  mText := 'program App;'#10'begin'#10'end.';
  mState := TLeakSetup.Analyze(Input(mText), FFiles);
  mPlan := TLeakSetup.Plan(mState, mText, TLeakManager.None, False);
  Assert.AreEqual(0, Pos(#13, mPlan.Edits[0].Text));
  Assert.AreEqual('program App;'#10'begin'#10'  {$IFDEF DEBUG}'#10'  ' + TLeakSetup.cReportLine + #10'  {$ENDIF}'#10 +
    'end.', Applied(mText, mPlan));
end;

procedure TLeakSetupTests.MainScanFindsBlockAfterRoutines;
var
  mScan: TLeakMainScan;
begin
  // Routinen mit eigenen Blöcken (try, case) vor dem Hauptblock zählen nicht.
  mScan := TLeakMainScan.Run('program App;' + cBreak + 'uses SysUtils;' + cBreak + 'procedure Run;' + cBreak +
    'begin' + cBreak + '  try' + cBreak + '    case 1 of 1: ; end;' + cBreak + '  finally' + cBreak + '  end;' +
    cBreak + 'end;' + cBreak + 'begin' + cBreak + '  Run;' + cBreak + 'end.');
  Assert.AreEqual(9, mScan.MainBegin);
  Assert.AreEqual(1, mScan.EntryCount);
  Assert.AreEqual(1, mScan.FirstEntry.Line);
  Assert.AreEqual(5, mScan.FirstEntry.Character);
  Assert.IsFalse(mScan.FirstEntryStartsLine);
end;

initialization
  TDUnitX.RegisterTestFixture(TLeakSetupTests);

end.
