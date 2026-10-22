unit Atlas.Common.Rules.Builtin.Unresolved.Tests;

// Tests für uses-unit-not-found (#1016): Beispiel aus dem Issue mit Vorschlag,
// Namespace-Korrektur, Suchpfad-Korrektur in der .dproj, "in 'Pfad'" (F1026),
// Selbstbezug (F2092), requires (E2202), fehlende Bibliothek (F1027), bedingte
// Einträge, unsichere Suche, Option searchPaths, Abschalten und Ausnahmen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesUnitNotFoundTests = class
  public
    [Test]
    procedure IssueExampleWithSuggestion;
    [Test]
    procedure CorrectedFormIsSilent;
    [Test]
    procedure NamespacePrefixFix;
    [Test]
    procedure SearchPathFixEditsProject;
    [Test]
    procedure InPathFileMissing;
    [Test]
    procedure SelfUseWithoutLookup;
    [Test]
    procedure RequiredPackageMissing;
    [Test]
    procedure MissingSystemGivesOneFinding;
    [Test]
    procedure ConditionalAndUnknownAreSilent;
    [Test]
    procedure SearchPathsOption;
    [Test]
    procedure OffGroupAndExclude;
    [Test]
    procedure EntriesSuggestionsAndDiffEdit;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.UnitLookup,
  Atlas.Common.Rules.Builtin.Unresolved,
  Atlas.Tests.RuleAssert;

const
  Dproj =
    '<Project>'#13#10 +
    '    <PropertyGroup Condition="''$(Base)''!=''''">'#13#10 +
    '        <DCC_UnitSearchPath>Src;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <BuildConfiguration Include="Base">'#13#10 +
    '            <Key>Base</Key>'#13#10 +
    '        </BuildConfiguration>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>'#13#10;
  LibraryNames: array[0..4] of string = ('C:\BDS\lib\System.dcu', 'C:\BDS\lib\SysInit.dcu',
    'C:\BDS\lib\System.SysUtils.dcu', 'C:\BDS\lib\Vcl.Forms.dcu', 'C:\BDS\lib\rtl.dcp');
  MainFile = 'C:\P\Src\Haupt.pas';

function LibraryFiles: TArray<string>;
var
  Name: string;
begin
  Result := nil;
  for Name in LibraryNames do
    Result := Result + [Name];
end;

/// <summary>Unit-Suche über die Dateien AFiles mit Projekt C:\P\App.dproj (Suchpfad C:\P\Src).</summary>
function Lookup(const AFiles: TArray<string>; const ANamespaces: TArray<string>): IRuleUnitLookup;
var
  Setup: TUnitLookupSetup;
begin
  Setup := Default(TUnitLookupSetup);
  Setup.Project.FileName := 'C:\P\App.dproj';
  Setup.Project.SearchPaths := ['C:\P\Src'];
  Setup.Project.Namespaces := ANamespaces;
  Setup.LibraryPaths := ['C:\BDS\lib'];
  Setup.LibraryKnown := True;
  Setup.ListFiles :=
    function(AFolder: string): TArray<string>
    var
      FileName: string;
    begin
      Result := nil;
      for FileName in AFiles do
        if SameText(TProjectPaths.DirectoryOf(FileName), AFolder) then
          Result := Result + [FileName];
    end;
  Setup.ListFolders :=
    function(AFolder: string): TArray<string>
    var
      FileName, Folder: string;
    begin
      Result := nil;
      for FileName in AFiles do
      begin
        Folder := TProjectPaths.DirectoryOf(FileName);
        if SameText(TProjectPaths.DirectoryOf(Folder), AFolder) and (IndexText(Folder, Result) < 0) then
          Result := Result + [Folder];
      end;
    end;
  Setup.FileExists :=
    function(AFileName: string): Boolean
    begin
      Result := IndexText(AFileName, AFiles) >= 0;
    end;
  Setup.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := Dproj;
      Result := SameText(AFileName, 'C:\P\App.dproj');
    end;
  Setup.PackageExists :=
    function(AName: string): Boolean
    begin
      Result := IndexText('C:\BDS\lib\' + AName + '.dcp', AFiles) >= 0;
    end;
  Result := TUnitLookup.Create(Setup);
end;

function Standard: IRuleUnitLookup;
begin
  Result := Lookup(LibraryFiles + ['C:\P\Src\Kunden.Daten.pas', 'C:\P\Src\Rechnung.Druck.pas'], ['System', 'Vcl']);
end;

function Source(const AUses: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'uses'#10'  ' + AUses + ';'#10'implementation'#10'end.';
end;

function Findings(const ASource: string; const AUnits: IRuleUnitLookup): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.UnitFindings(TUsesUnitNotFoundRule.Create, ASource, MainFile, AUnits, '', '');
end;

function Findings(const ASource: string; const AUnits: IRuleUnitLookup; const AConfig: string):
  TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.UnitFindings(TUsesUnitNotFoundRule.Create, ASource, MainFile, AUnits, AConfig,
    'Src/Haupt.pas');
end;

procedure TUsesUnitNotFoundTests.IssueExampleWithSuggestion;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Source('System.SysUtils, Vcl.Forms, Kunden.Daten, Rechnungs.Druck'), Standard);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unit Rechnungs.Druck nicht gefunden; ähnlich: Rechnung.Druck (wie F2613).', Found[0].Message);
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual(44, Found[0].Range.StartPos.Character);
  Assert.AreEqual(59, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Rechnung.Druck verwenden', Found[0].Fixes[0].Title);
  Assert.AreEqual('Rechnung.Druck', Found[0].Fixes[0].Edits[0].NewText);
end;

procedure TUsesUnitNotFoundTests.CorrectedFormIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Findings(Source('System.SysUtils, Vcl.Forms, Kunden.Daten, Rechnung.Druck'),
    Standard))));
  // Ohne Namespace-Präfix, wenn das Projekt den Namespace nennt.
  Assert.AreEqual(0, Integer(Length(Findings(Source('SysUtils, Forms'), Standard))));
end;

procedure TUsesUnitNotFoundTests.NamespacePrefixFix;
var
  Found: TArray<TRuleFinding>;
begin
  // Projekt ohne Namespace Vcl: Forms gibt es nur als Vcl.Forms.
  Found := Findings(Source('SysUtils, Forms'), Lookup(LibraryFiles, ['System']));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unit Forms nicht gefunden; ähnlich: Vcl.Forms (wie F2613).', Found[0].Message);
  Assert.AreEqual('Vcl.Forms verwenden', Found[0].Fixes[0].Title);
end;

procedure TUsesUnitNotFoundTests.SearchPathFixEditsProject;
var
  Found: TArray<TRuleFinding>;
  Edit: TTextEdit;
begin
  Found := Findings(Source('System.SysUtils, Hilfen'), Lookup(LibraryFiles + ['C:\P\Extra\Hilfen.pas'],
    ['System']));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unit Hilfen nicht gefunden; sie liegt in Extra außerhalb der Suchpfade (wie F2613).',
    Found[0].Message);
  Assert.AreEqual('Ordner Extra in den Suchpfad aufnehmen', Found[0].Fixes[0].Title);
  Assert.AreEqual('C:\P\App.dproj', Found[0].Fixes[0].FileName);
  // Nur die Zeile mit DCC_UnitSearchPath ändert sich.
  Edit := Found[0].Fixes[0].Edits[0];
  Assert.AreEqual(2, Edit.Range.StartPos.Line);
  Assert.AreEqual(2, Edit.Range.EndPos.Line);
  Assert.AreEqual('Extra;', Edit.NewText);
end;

procedure TUsesUnitNotFoundTests.InPathFileMissing;
var
  Text: string;
  Found: TArray<TRuleFinding>;
begin
  Text := 'program App;'#10'uses'#10'  System.SysUtils,'#10'  Haupt in ''Src\Haupt.pas'','#10 +
    '  Alt in ''Alt\Alt.pas'';'#10'begin'#10'end.';
  Found := TRuleAssert.UnitFindings(TUsesUnitNotFoundRule.Create, Text, 'C:\P\App.dpr',
    Lookup(LibraryFiles + ['C:\P\Src\Haupt.pas'], ['System']), '', '');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Datei Alt\Alt.pas für Alt nicht gefunden (wie F1026).', Found[0].Message);
end;

procedure TUsesUnitNotFoundTests.SelfUseWithoutLookup;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings('unit Haupt;'#10'interface'#10'implementation'#10'uses'#10'  Haupt;'#10'end.', nil);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Haupt verwendet sich selbst (wie F2092).', Found[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings(Source('Gibt.Es.Nicht'), nil))), 'ohne Suche keine Aussage');
end;

procedure TUsesUnitNotFoundTests.RequiredPackageMissing;
var
  Text: string;
  Found: TArray<TRuleFinding>;
begin
  Text := 'package Komponenten;'#10'requires'#10'  rtl,'#10'  vclfehlt;'#10'contains'#10 +
    '  Komp.Knopf in ''Komp.Knopf.pas'';'#10'end.';
  Found := TRuleAssert.UnitFindings(TUsesUnitNotFoundRule.Create, Text, 'C:\P\Komponenten.dpk',
    Lookup(LibraryFiles + ['C:\P\Komp.Knopf.pas'], ['System']), '', '');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Package vclfehlt nicht gefunden (wie E2202).', Found[0].Message);
end;

procedure TUsesUnitNotFoundTests.MissingSystemGivesOneFinding;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Source('System.SysUtils, Vcl.Forms, Fehlt'), Lookup(['C:\P\Src\X.pas'], ['System']));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unit System nicht gefunden; der Bibliothekspfad der Installation fehlt (wie F1027).',
    Found[0].Message);
end;

procedure TUsesUnitNotFoundTests.ConditionalAndUnknownAreSilent;
var
  Setup: TUnitLookupSetup;
begin
  Assert.AreEqual(0, Integer(Length(Findings(Source('System.SysUtils'#10'  {$IFDEF LINUX}, Posix.Base{$ENDIF}'),
    Standard))));
  // Installation unbekannt: keine Aussage über fehlende Units.
  Setup := Default(TUnitLookupSetup);
  Setup.Project.FileName := 'C:\P\App.dproj';
  Setup.ListFiles :=
    function(AFolder: string): TArray<string>
    begin
      Result := nil;
    end;
  Assert.AreEqual(0, Integer(Length(Findings(Source('Gibt.Es.Nicht'), TUnitLookup.Create(Setup)))));
end;

procedure TUsesUnitNotFoundTests.SearchPathsOption;
var
  Setup: TUnitLookupSetup;
  Units: IRuleUnitLookup;
  Text: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Setup := Default(TUnitLookupSetup);
  Setup.Project.FileName := 'C:\P\App.dproj';
  Setup.LibraryPaths := ['C:\BDS\lib'];
  Setup.LibraryKnown := True;
  Setup.ListFiles :=
    function(AFolder: string): TArray<string>
    begin
      Result := nil;
      if SameText(AFolder, 'C:\BDS\lib') then
        Result := ['C:\BDS\lib\System.dcu'];
    end;
  Setup.IndexKnows :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'Nur.Im.Index');
    end;
  Units := TUnitLookup.Create(Setup);
  Text := Source('Nur.Im.Index');
  Assert.AreEqual(1, Integer(Length(Findings(Text, Units, ''))), 'project');
  Assert.AreEqual(0, Integer(Length(Findings(Text, Units,
    '{"rules": {"uses-unit-not-found": {"searchPaths": "atlas"}}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(Text, Units,
    '{"rules": {"uses-unit-not-found": {"searchPaths": "both"}}}'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source('Gibt.Es.Nicht'), Units,
    '{"rules": {"uses-unit-not-found": {"searchPaths": "both"}}}'))));
  // Der Parser prüft den Wert.
  TConfigurationParser.Parse('{"rules": {"uses-unit-not-found": {"searchPaths": "alles"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"searchPaths" muss "project", "atlas" oder "both" sein', Issues[0].Message);
  TConfigurationParser.Parse('{"rules": {"uses-unit-not-found": {"searchPaths": "both"}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TUsesUnitNotFoundTests.OffGroupAndExclude;
var
  Text: string;
begin
  Text := Source('System.SysUtils, Rechnungs.Druck');
  Assert.AreEqual(1, Integer(Length(Findings(Text, Standard, ''))));
  Assert.AreEqual(0, Integer(Length(Findings(Text, Standard, '{"rules": {"uses-unit-not-found": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(Text, Standard, '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(Text, Standard,
    '{"rules": {"uses-unit-not-found": {"exclude": ["Src/*.pas"]}}}'))));
end;

procedure TUsesUnitNotFoundTests.EntriesSuggestionsAndDiffEdit;
var
  Entries: TArray<TUsesListEntry>;
  Edit: TTextEdit;
  Suggested: TArray<string>;
begin
  Entries := TUsesUnitNotFoundRule.Entries(TPascalLexer.Tokenize('program P;'#10 +
    'uses A, B.C in ''b\c.pas'' {x}, D;'#10'begin'#10'end.'));
  Assert.AreEqual(3, Integer(Length(Entries)));
  Assert.AreEqual('B.C', Entries[1].Name);
  Assert.AreEqual('b\c.pas', Entries[1].InPath);
  Assert.AreEqual('', Entries[2].InPath);
  Edit := TUsesUnitNotFoundRule.DiffEdit('a'#10'xyz'#10'b', 'a'#10'xQyz'#10'b');
  Assert.AreEqual(1, Edit.Range.StartPos.Line);
  Assert.AreEqual(1, Edit.Range.StartPos.Character);
  Assert.AreEqual(1, Edit.Range.EndPos.Character);
  Assert.AreEqual('Q', Edit.NewText);
  // Mit Namespace zuerst, dann nach Abstand; höchstens drei.
  Suggested := TUsesUnitNotFoundRule.Suggestions('Forms', ['Forms3', 'Vcl.Forms', 'Form', 'X', 'Fmx.Forms', 'Formz']);
  Assert.AreEqual(3, Integer(Length(Suggested)));
  Assert.AreEqual('Fmx.Forms', Suggested[0]);
  Assert.AreEqual('Vcl.Forms', Suggested[1]);
  Assert.AreEqual('Form', Suggested[2]);
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesUnitNotFoundTests);

end.
