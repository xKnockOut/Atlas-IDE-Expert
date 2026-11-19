unit Atlas.Common.Mcp.ProtectedFiles.Tests;

// Tests für geschützte Dateien (assistants.protected, #2608): Muster, Ablehnung in den schreibenden Werkzeugen
// (auch über mehrere Dateien und in der Vorschau), Ausgabe von hook_check vor und nach dem Schreiben und der
// Abschnitt in delphi://conventions.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpProtectedFilesTests = class
  public
    /// <summary>Muster wie architecture.exclude: **, *, Ordner, "/" und "\" gleich, ohne Groß-/Kleinschreibung.
    /// </summary>
    [Test]
    procedure MatchesPatternsRelativeToRoot;
    [Test]
    procedure FindsFirstMatchingEntry;
    /// <summary>Ablehnung nennt Datei, Grund und richtigen Weg; mehrere Dateien als Liste.</summary>
    [Test]
    procedure ReportNamesReasonAndUse;
    /// <summary>Ein geschützte Datei im Aufruf: nichts wird geschrieben, auch die anderen Dateien nicht.</summary>
    [Test]
    procedure ApplyRefusesAndWritesNothing;
    /// <summary>dryRun nennt die geschützten Dateien schon in der Vorschau.</summary>
    [Test]
    procedure ApplyPreviewNamesProtectedFiles;
    [Test]
    procedure FixFindingsRefusesProtectedFiles;
    [Test]
    procedure HookOutputRefusesBeforeAndReportsAfter;
    [Test]
    procedure ParsesHookMoment;
    [Test]
    procedure MarkdownListsEntries;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Mcp.ProtectedFiles;

type
  /// <summary>Dateien im Speicher; zählt die Schreibvorgänge.</summary>
  TProtectedTestFiles = class
  public
    Files: TDictionary<string, string>;
    Writes: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

const
  cRoot = 'C:\Projekt';
  cAssignedFree = 'unit U;'#10#10'interface'#10#10'uses'#10'  System.Classes;'#10#10'implementation'#10#10 +
    'procedure Weg(AList: TStringList);'#10'begin'#10'  if Assigned(AList) then'#10'    AList.Free;'#10'end;'#10#10 +
    'end.'#10;

{ TProtectedTestFiles }

constructor TProtectedTestFiles.Create;
begin
  inherited Create;
  Files := TDictionary<string, string>.Create;
end;

destructor TProtectedTestFiles.Destroy;
begin
  Files.Free;
  inherited Destroy;
end;

function Entry(const APath, AReason, AUse: string): TProtectedPath;
begin
  Result.Path := APath;
  Result.Reason := AReason;
  Result.Use := AUse;
end;

/// <summary>ProtectedReport der Werkzeuge über AProtection; eigene Routine, damit die anonyme Methode nur den
/// Parameter einfängt.</summary>
function ReportOf(AProtection: TMcpProtectedFiles): TMcpProtectedReport;
begin
  Result :=
    function(const AFileNames: TArray<string>; ADryRun: Boolean): string
    begin
      Result := AProtection.Report(AFileNames, ADryRun);
    end;
end;

/// <summary>Schutz für CHANGELOG.md (mit Grund und Weg) und erzeugte Schema-Units (nur Grund).</summary>
function NewProtection(const ARoot: string): TMcpProtectedFiles;
var
  mEntries: TArray<TProtectedPath>;
begin
  SetLength(mEntries, 2);
  mEntries[0] := Entry('CHANGELOG.md', 'Wird aus Fragmenten erzeugt', 'Fragment changelog.d/<Issue>.md anlegen');
  mEntries[1] := Entry('**/*SchemaData.pas', 'Erzeugt von Update-ConfigDoc', '');
  Result := TMcpProtectedFiles.Create(ARoot, mEntries);
end;

function NewTools(AFiles: TProtectedTestFiles): TMcpEditTools;
begin
  Result := TMcpEditTools.Create(nil,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AFiles.Files.TryGetValue(AFileName, AText);
    end,
    procedure(const AFileName, AText: string)
    begin
      AFiles.Files[AFileName] := AText;
      Inc(AFiles.Writes);
    end,
    function: TArray<string>
    begin
      Result := nil;
    end,
    nil);
end;

function TwoFileEdits: TArray<TMcpFileEdit>;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := TMcpFileEdit.Create('A.pas', TTextRange.Create(0, 0, 0, 3), 'Neu');
  Result[1] := TMcpFileEdit.Create('CHANGELOG.md', TTextRange.Create(0, 0, 0, 3), 'Neu');
end;

/// <summary>Meldung von EMcpToolError aus AProc; '' ohne Ausnahme.</summary>
function ToolError(const AProc: TProc): string;
begin
  Result := '';
  try
    AProc();
  except
    on E: EMcpToolError do
      Result := E.Message;
  end;
end;

{ TMcpProtectedFilesTests }

procedure TMcpProtectedFilesTests.MatchesPatternsRelativeToRoot;
begin
  Assert.IsTrue(TMcpProtectedFiles.Matches(cRoot, 'CHANGELOG.md', 'C:\Projekt\CHANGELOG.md'));
  Assert.IsTrue(TMcpProtectedFiles.Matches(cRoot, 'CHANGELOG.md', 'c:/projekt/changelog.md'),
    'Trenner und Groß-/Kleinschreibung gleich');
  Assert.IsFalse(TMcpProtectedFiles.Matches(cRoot, 'CHANGELOG.md', 'C:\Projekt\docs\CHANGELOG.md'),
    'ohne Platzhalter nur an der Wurzel');
  Assert.IsTrue(TMcpProtectedFiles.Matches(cRoot, '**/*SchemaData.pas', 'C:\Projekt\A.SchemaData.pas'),
    '**/ auch ohne Ordner');
  Assert.IsTrue(TMcpProtectedFiles.Matches(cRoot, '**/*SchemaData.pas', 'C:\Projekt\Src\Gen\A.SchemaData.pas'));
  Assert.IsTrue(TMcpProtectedFiles.Matches(cRoot, 'Src\Gen', 'C:\Projekt\Src\Gen\B.pas'),
    'Ordner schützt alles darunter');
  Assert.IsFalse(TMcpProtectedFiles.Matches(cRoot, 'Src/*.pas', 'C:\Projekt\Src\Gen\B.pas'),
    '* bleibt in einem Ordner');
  Assert.IsTrue(TMcpProtectedFiles.Matches(cRoot, 'Src/*.pas', 'Src\B.pas'), 'relativ angegeben');
  Assert.IsTrue(TMcpProtectedFiles.Matches('/home/p', 'Src/*.pas', '/home/p/Src/B.pas'), 'Linux-Pfade');
  Assert.IsFalse(TMcpProtectedFiles.Matches(cRoot, '  ', 'C:\Projekt\B.pas'), 'leeres Muster schützt nichts');
  Assert.AreEqual('Src/B.pas', TMcpProtectedFiles.RelativePath('C:\Projekt\', 'C:\Projekt\Src\B.pas'));
  Assert.AreEqual('D:/Fremd/B.pas', TMcpProtectedFiles.RelativePath(cRoot, 'D:\Fremd\B.pas'));
end;

procedure TMcpProtectedFilesTests.FindsFirstMatchingEntry;
var
  mProtection: TMcpProtectedFiles;
  mEntry: TProtectedPath;
begin
  mProtection := NewProtection(cRoot);
  try
    Assert.IsTrue(mProtection.Find('C:\Projekt\Src\X.SchemaData.pas', mEntry));
    Assert.AreEqual('Erzeugt von Update-ConfigDoc', mEntry.Reason);
    Assert.IsFalse(mProtection.Find('C:\Projekt\Src\X.pas', mEntry));
    Assert.AreEqual('', mEntry.Path, 'ohne Treffer leer');
  finally
    mProtection.Free;
  end;
end;

procedure TMcpProtectedFilesTests.ReportNamesReasonAndUse;
var
  mProtection: TMcpProtectedFiles;
  mReport: string;
begin
  mProtection := NewProtection(cRoot);
  try
    Assert.AreEqual('', mProtection.Report(['C:\Projekt\A.pas'], False), 'nichts geschützt');
    mReport := mProtection.Report(['C:\Projekt\A.pas', 'C:\Projekt\CHANGELOG.md'], False);
    Assert.Contains(mReport, 'CHANGELOG.md');
    Assert.Contains(mReport, 'assistants.protected');
    Assert.Contains(mReport, 'Wird aus Fragmenten erzeugt');
    Assert.Contains(mReport, 'Fragment changelog.d/<Issue>.md anlegen');
    Assert.IsFalse(Pos('A.pas', mReport) > 0, mReport);
    mReport := mProtection.Report(['C:\Projekt\CHANGELOG.md', 'C:\Projekt\Src\X.SchemaData.pas'], False);
    Assert.Contains(mReport, '2');
    Assert.Contains(mReport, '- CHANGELOG.md');
    Assert.Contains(mReport, '- Src/X.SchemaData.pas');
    Assert.Contains(mReport, 'Erzeugt von Update-ConfigDoc');
    Assert.AreNotEqual(mProtection.Report(['C:\Projekt\CHANGELOG.md'], False),
      mProtection.Report(['C:\Projekt\CHANGELOG.md'], True), 'Vorschau anders als Ablehnung');
    Assert.WillRaise(
      procedure
      begin
        mProtection.EnsureAllowed(['C:\Projekt\CHANGELOG.md']);
      end, EMcpToolError);
    mProtection.EnsureAllowed(['C:\Projekt\A.pas']);
  finally
    mProtection.Free;
  end;
end;

procedure TMcpProtectedFilesTests.ApplyRefusesAndWritesNothing;
var
  mFiles: TProtectedTestFiles;
  mEdit: TMcpEditTools;
  mProtection: TMcpProtectedFiles;
  mError: string;
begin
  mFiles := TProtectedTestFiles.Create;
  mEdit := NewTools(mFiles);
  mProtection := NewProtection('');
  try
    mFiles.Files.Add('A.pas', 'Alt;');
    mFiles.Files.Add('CHANGELOG.md', 'Alt');
    mEdit.ProtectedReport := ReportOf(mProtection);
    mError := ToolError(
      procedure
      begin
        mEdit.Apply('rename_symbol', TwoFileEdits, False);
      end);
    Assert.Contains(mError, 'CHANGELOG.md');
    Assert.Contains(mError, 'Wird aus Fragmenten erzeugt');
    Assert.AreEqual(0, mFiles.Writes, 'auch A.pas nicht geschrieben');
    Assert.AreEqual('Alt;', mFiles.Files['A.pas']);
    mEdit.ProtectedReport := nil;
    mEdit.Apply('rename_symbol', TwoFileEdits, False);
    Assert.AreEqual(2, mFiles.Writes, 'ohne Schutz geschrieben');
  finally
    mProtection.Free;
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpProtectedFilesTests.ApplyPreviewNamesProtectedFiles;
var
  mFiles: TProtectedTestFiles;
  mEdit: TMcpEditTools;
  mProtection: TMcpProtectedFiles;
  mReport: string;
begin
  mFiles := TProtectedTestFiles.Create;
  mEdit := NewTools(mFiles);
  mProtection := NewProtection('');
  try
    mFiles.Files.Add('A.pas', 'Alt;');
    mFiles.Files.Add('CHANGELOG.md', 'Alt');
    mEdit.ProtectedReport := ReportOf(mProtection);
    mReport := mEdit.Apply('rename_symbol', TwoFileEdits, True);
    Assert.Contains(mReport, 'dryRun=false');
    Assert.Contains(mReport, 'Wird aus Fragmenten erzeugt');
    Assert.Contains(mReport, '--- A.pas', 'Diff bleibt');
    Assert.AreEqual(0, mFiles.Writes);
  finally
    mProtection.Free;
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpProtectedFilesTests.FixFindingsRefusesProtectedFiles;
var
  mFiles: TProtectedTestFiles;
  mEdit: TMcpEditTools;
  mProtection: TMcpProtectedFiles;
  mEntries: TArray<TProtectedPath>;
  mReport, mError: string;
begin
  mFiles := TProtectedTestFiles.Create;
  mEdit := NewTools(mFiles);
  mEntries := [Entry('U.pas', 'Fremdcode', '')];
  mProtection := TMcpProtectedFiles.Create('', mEntries);
  try
    mFiles.Files.Add('U.pas', cAssignedFree);
    mEdit.ProtectedReport := ReportOf(mProtection);
    mReport := mEdit.FixFindings(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, ''), ['U.pas'],
      ['redundant-assigned-free'], '', True);
    Assert.Contains(mReport, 'Fremdcode', 'Vorschau nennt die geschützte Datei');
    mError := ToolError(
      procedure
      begin
        mEdit.FixFindings(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, ''), ['U.pas'],
          ['redundant-assigned-free'], '', False);
      end);
    Assert.Contains(mError, 'U.pas');
    Assert.Contains(mError, 'Fremdcode');
    Assert.AreEqual(0, mFiles.Writes);
    Assert.AreEqual(cAssignedFree, mFiles.Files['U.pas']);
  finally
    mProtection.Free;
    mEdit.Free;
    mFiles.Free;
    mEntries := nil;
  end;
end;

procedure TMcpProtectedFilesTests.HookOutputRefusesBeforeAndReportsAfter;
var
  mProtection: TMcpProtectedFiles;
  mOutput: string;
begin
  mProtection := NewProtection(cRoot);
  try
    mOutput := mProtection.HookOutput('C:\Projekt\CHANGELOG.md', TMcpHookMoment.Before);
    Assert.Contains(mOutput, '"hookEventName":"PreToolUse"');
    Assert.Contains(mOutput, '"permissionDecision":"deny"');
    Assert.Contains(mOutput, 'Wird aus Fragmenten erzeugt');
    mOutput := mProtection.HookOutput('C:\Projekt\CHANGELOG.md', TMcpHookMoment.After);
    Assert.Contains(mOutput, '"decision":"block"');
    Assert.Contains(mOutput, 'Fragment changelog.d/<Issue>.md anlegen');
    Assert.AreEqual('', mProtection.HookOutput('C:\Projekt\A.pas', TMcpHookMoment.Before));
    Assert.AreEqual('', mProtection.HookOutput('C:\Projekt\A.pas', TMcpHookMoment.After));
  finally
    mProtection.Free;
  end;
end;

procedure TMcpProtectedFilesTests.ParsesHookMoment;
begin
  Assert.AreEqual(Integer(Ord(TMcpHookMoment.After)), Integer(Ord(TMcpProtectedFiles.ParseHookMoment(''))),
    'Vorgabe post');
  Assert.AreEqual(Integer(Ord(TMcpHookMoment.After)), Integer(Ord(TMcpProtectedFiles.ParseHookMoment('post'))));
  Assert.AreEqual(Integer(Ord(TMcpHookMoment.Before)), Integer(Ord(TMcpProtectedFiles.ParseHookMoment('PRE'))));
  Assert.WillRaise(
    procedure
    begin
      TMcpProtectedFiles.ParseHookMoment('während');
    end, EMcpToolError);
end;

procedure TMcpProtectedFilesTests.MarkdownListsEntries;
var
  mText: string;
begin
  Assert.AreEqual('', TMcpProtectedFiles.Markdown(nil));
  mText := TMcpProtectedFiles.Markdown([Entry('CHANGELOG.md', 'a|b', 'Fragment')]);
  Assert.Contains(mText, '`CHANGELOG.md`');
  Assert.Contains(mText, 'a\|b', 'Trenner der Tabelle maskiert');
  Assert.Contains(mText, 'Fragment');
  Assert.Contains(mText, 'assistants.protected');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpProtectedFilesTests);

end.
