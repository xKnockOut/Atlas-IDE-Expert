unit Atlas.Common.Rules.Builtin.Unresolved.Tests;

// Tests für uses-unit-not-found (#1016): Beispiel aus dem Issue mit Vorschlag,
// Namespace-Korrektur, Suchpfad-Korrektur in der .dproj, "in 'Pfad'" (F1026),
// Selbstbezug (F2092), requires (E2202), fehlende Bibliothek (F1027), bedingte
// Einträge, unsichere Suche, Option searchPaths, Abschalten und Ausnahmen;
// unresolved-attribute (#1019): Beispiel mit Korrektur, aufgelöste und
// Compiler-Attribute, andere Bibliothek, unbekanntes Attribut, Fassaden-Unit;
// unresolved-type (#1031): Beispiel mit Korrektur, Deklarationsarten, kein Typ
// (E2005), Zeigerziel (E2564), stille Fälle, Abschalten.

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

  [TestFixture]
  TUnresolvedAttributeTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure ResolvedAndCompilerAttributesAreSilent;
    [Test]
    procedure OtherLibraryAndUnknownAttribute;
    [Test]
    procedure SilentWithoutSystemOrInConditional;
    [Test]
    procedure FacadeUnitWins;
    [Test]
    procedure AttributeOffGroupAndExclude;
  end;

  [TestFixture]
  TUnresolvedTypeTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure DeclarationKinds;
    [Test]
    procedure NotATypeAndPointerTarget;
    [Test]
    procedure SilentCases;
    [Test]
    procedure TypeOffGroupAndExclude;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
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

{ TUnresolvedAttributeTests }

/// <summary>Index mit System (TCustomAttribute, WeakAttribute), DUnitX.Attributes, der Fassade
/// DUnitX.TestFramework und Rest.Json.Types (JSONNameAttribute).</summary>
function AttributeIndex(AWithSystem: Boolean): ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  if AWithSystem then
    Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
      '  end;'#10'  TCustomAttribute = class(TObject)'#10'  end;'#10'  WeakAttribute = class(TCustomAttribute)'#10 +
      '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.SysUtils;'#10'interface'#10'implementation'#10'end.',
    'C:\BDS\source\System.SysUtils.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit DUnitX.Attributes;'#10'interface'#10'type'#10 +
    '  TestFixtureAttribute = class(TCustomAttribute)'#10'  end;'#10'  TestAttribute = class(TCustomAttribute)'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\DUnitX.Attributes.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit DUnitX.TestFramework;'#10'interface'#10'uses'#10 +
    '  DUnitX.Attributes;'#10'type'#10'  TestFixtureAttribute = DUnitX.Attributes.TestFixtureAttribute;'#10 +
    '  TestAttribute = DUnitX.Attributes.TestAttribute;'#10'implementation'#10'end.',
    'C:\BDS\source\DUnitX.TestFramework.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit Rest.Json.Types;'#10'interface'#10'type'#10 +
    '  JSONNameAttribute = class(TCustomAttribute)'#10'  public'#10'    constructor Create(const AName: string);'#10 +
    '  end;'#10'implementation'#10'constructor JSONNameAttribute.Create(const AName: string);'#10'begin'#10'end;'#10 +
    'end.', 'C:\BDS\source\Rest.Json.Types.pas', nil));
end;

function TestUnit(const AUses: string): string;
begin
  Result := 'unit KundeTests;'#10'interface'#10'uses'#10'  ' + AUses + ';'#10'type'#10'  [TestFixture]'#10 +
    '  TKundeTests = class'#10'  public'#10'    [Test]'#10'    procedure Lauf;'#10'  end;'#10'implementation'#10 +
    'procedure TKundeTests.Lauf;'#10'begin'#10'end;'#10'end.';
end;

function AttributeFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TUnresolvedAttributeRule.Create, ASource, AttributeIndex(True), '', '');
end;

function AttributeFindings(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TUnresolvedAttributeRule.Create, ASource, AttributeIndex(True), AConfig,
    'Tests/KundeTests.pas');
end;

/// <summary>Wendet das Edit an (eine Zeile, Zeilen mit #10).</summary>
function Applied(const AText: string; const AEdit: TTextEdit): string;
var
  Lines: TArray<string>;
  Line: string;
begin
  Lines := AText.Split([#10]);
  Line := Lines[AEdit.Range.StartPos.Line];
  Lines[AEdit.Range.StartPos.Line] := Copy(Line, 1, AEdit.Range.StartPos.Character) + AEdit.NewText +
    Copy(Line, AEdit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, Lines);
end;

procedure TUnresolvedAttributeTests.IssueExampleWithFix;
var
  Found: TArray<TRuleFinding>;
  Fixed: string;
begin
  Found := AttributeFindings(TestUnit('System.SysUtils'));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Attribut TestFixture nicht gefunden und wird ignoriert; die Tests laufen nicht (wie W1074). ' +
    'Unit DUnitX.TestFramework fehlt.', Found[0].Message);
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(3, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Attribut Test nicht gefunden und wird ignoriert; die Tests laufen nicht (wie W1074). ' +
    'Unit DUnitX.TestFramework fehlt.', Found[1].Message);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('uses DUnitX.TestFramework ergänzen', Found[0].Fixes[0].Title);
  Fixed := Applied(TestUnit('System.SysUtils'), Found[0].Fixes[0].Edits[0]);
  // Steht die Liste in eigener Zeile, kommt die Unit in eine neue Zeile (wie "uses … ergänzen").
  Assert.AreEqual(TestUnit('System.SysUtils,'#10'  DUnitX.TestFramework'), Fixed);
  Assert.AreEqual(0, Integer(Length(AttributeFindings(Fixed))));
end;

procedure TUnresolvedAttributeTests.ResolvedAndCompilerAttributesAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(AttributeFindings(TestUnit('DUnitX.TestFramework')))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(TestUnit('DUnitX.Attributes')))));
  // Eigene Attributklasse, Compiler-Attribute, GUID eines Interface.
  Assert.AreEqual(0, Integer(Length(AttributeFindings('unit U;'#10'interface'#10'type'#10 +
    '  MarkeAttribute = class(TCustomAttribute)'#10'  end;'#10'  IFoo = interface'#10 +
    '    [''{6F1C2B9E-4A37-4D2B-9E61-3C5A7B8D9E01}'']'#10'  end;'#10'  [Marke]'#10'  TFoo = class'#10 +
    '    [Weak] FRef: TObject;'#10'    [Unsafe] FRoh: TObject;'#10'    [Volatile] FZahl: Integer;'#10'  end;'#10 +
    'implementation'#10'end.'))));
end;

procedure TUnresolvedAttributeTests.OtherLibraryAndUnknownAttribute;
var
  Found: TArray<TRuleFinding>;
begin
  Found := AttributeFindings('unit U;'#10'interface'#10'type'#10'  TKunde = class'#10'  public'#10 +
    '    [JSONName(''name'')]'#10'    FName: string;'#10'    [GibtEsNicht]'#10'    FAlter: Integer;'#10'  end;'#10 +
    'implementation'#10'end.');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Attribut JSONName nicht gefunden und wird ignoriert (wie W1074). Unit Rest.Json.Types fehlt.',
    Found[0].Message);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Attribut GibtEsNicht nicht gefunden und wird ignoriert (wie W1074).', Found[1].Message);
  Assert.AreEqual(0, Integer(Length(Found[1].Fixes)));
end;

procedure TUnresolvedAttributeTests.SilentWithoutSystemOrInConditional;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TUnresolvedAttributeRule.Create,
    TestUnit('System.SysUtils'), AttributeIndex(False), '', ''))), 'ohne System im Index');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnresolvedAttributeRule.Create,
    TestUnit('System.SysUtils')))), 'ohne Index');
  // Eine Unit aus uses fehlt im Index: Sie könnte TestFixtureAttribute deklarieren.
  Assert.AreEqual(0, Integer(Length(AttributeFindings(TestUnit('System.SysUtils, Fremd.Tests')))),
    'unbekannte Unit in uses');
  Assert.AreEqual(0, Integer(Length(AttributeFindings('unit U;'#10'interface'#10'type'#10'{$IFDEF TESTS}'#10 +
    '  [TestFixture]'#10'{$ENDIF}'#10'  TFoo = class'#10'  end;'#10'implementation'#10'end.'))));
end;

procedure TUnresolvedAttributeTests.FacadeUnitWins;
var
  Units: TArray<string>;
begin
  Units := TUnresolvedAttributeRule.DeclaringUnits(AttributeIndex(True), 'TestFixture');
  Assert.AreEqual(1, Integer(Length(Units)));
  Assert.AreEqual('DUnitX.TestFramework', Units[0]);
  Units := TUnresolvedAttributeRule.DeclaringUnits(AttributeIndex(True), 'JSONNameAttribute');
  Assert.AreEqual(1, Integer(Length(Units)));
  Assert.AreEqual('Rest.Json.Types', Units[0]);
  Assert.AreEqual(0, Integer(Length(TUnresolvedAttributeRule.DeclaringUnits(nil, 'Test'))));
end;

procedure TUnresolvedAttributeTests.AttributeOffGroupAndExclude;
var
  Text: string;
begin
  Text := TestUnit('System.SysUtils');
  Assert.AreEqual(2, Integer(Length(AttributeFindings(Text, ''))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(Text, '{"rules": {"unresolved-attribute": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(Text, '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(Text,
    '{"rules": {"unresolved-attribute": {"exclude": ["Tests/*.pas"]}}}'))));
end;

{ TUnresolvedTypeTests }

function TypeIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'  TArray<T> = array of T;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.SysUtils;'#10'interface'#10'type'#10 +
    '  Exception = class(TObject)'#10'  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.SysUtils.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.Generics.Collections;'#10'interface'#10'type'#10 +
    '  TList<T> = class'#10'  end;'#10'  TObjectList<T: class> = class(TList<T>)'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Generics.Collections.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.Contnrs;'#10'interface'#10'type'#10 +
    '  TObjectList = class'#10'  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.Contnrs.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit Vcl.Basis;'#10'interface'#10'type'#10 +
    '  TSteuerung = class'#10'  public type'#10'    TStil = (stFlach, stRund);'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\Vcl.Basis.pas', nil));
end;

function TypeFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TUnresolvedTypeRule.Create, ASource, TypeIndex, '', '');
end;

function TypeFindings(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TUnresolvedTypeRule.Create, ASource, TypeIndex, AConfig, 'Src/Kunden.pas');
end;

function KundenUnit(const AUses, ATypes: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'uses'#10'  ' + AUses + ';'#10'type'#10'  TKunde = class'#10'  end;'#10 +
    ATypes + 'implementation'#10'end.';
end;

procedure TUnresolvedTypeTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := KundenUnit('System.SysUtils', '  TKunden = TObjectList<TKunde>;'#10);
  Found := TypeFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Typ TObjectList ist nicht deklariert; System.Generics.Collections fehlt in uses (wie E2003).',
    Found[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Found[0].Severity));
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(12, Found[0].Range.StartPos.Character);
  Assert.AreEqual(23, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('uses System.Generics.Collections ergänzen', Found[0].Fixes[0].Title);
  Fixed := Applied(Source, Found[0].Fixes[0].Edits[0]);
  Assert.AreEqual(KundenUnit('System.SysUtils,'#10'  System.Generics.Collections', '  TKunden = TObjectList<TKunde>;'#10),
    Fixed);
  Assert.AreEqual(0, Integer(Length(TypeFindings(Fixed))), Fixed);
end;

procedure TUnresolvedTypeTests.DeclarationKinds;
var
  Found: TArray<TRuleFinding>;
begin
  // Vorfahr, Feld, Parameter, Ergebnis, globale Variable; ohne Kandidaten im Index ohne Korrektur.
  Found := TypeFindings(KundenUnit('System.SysUtils', '  TSonder = class(TBasiz)'#10'    FAdresse: TAdresse;'#10 +
    '    function Pruefe(A: TAnschrift): TErgebnis;'#10'  end;'#10'var'#10'  Aktuell: TKundeX;'#10));
  Assert.AreEqual(5, Integer(Length(Found)));
  Assert.AreEqual('Typ TBasiz ist nicht deklariert (wie E2003).', Found[0].Message);
  Assert.AreEqual('Typ TAdresse ist nicht deklariert (wie E2003).', Found[1].Message);
  Assert.AreEqual('Typ TAnschrift ist nicht deklariert (wie E2003).', Found[2].Message);
  Assert.AreEqual('Typ TErgebnis ist nicht deklariert (wie E2003).', Found[3].Message);
  Assert.AreEqual('Typ TKundeX ist nicht deklariert (wie E2003).', Found[4].Message);
  Assert.AreEqual(0, Integer(Length(Found[4].Fixes)));
end;

procedure TUnresolvedTypeTests.NotATypeAndPointerTarget;
var
  Found: TArray<TRuleFinding>;
begin
  Found := TypeFindings('unit Kunden;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'var'#10 +
    '  Zaehler: Integer;'#10'type'#10'  PKnoten = ^TKnotn;'#10'  TKnoten = record'#10'    Wert: Zaehler;'#10 +
    '  end;'#10'implementation'#10'end.');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Typ TKnotn ist nicht deklariert (wie E2564).', Found[0].Message);
  Assert.AreEqual('Zaehler ist kein Typ (wie E2005).', Found[1].Message);
end;

procedure TUnresolvedTypeTests.SilentCases;
begin
  // Typparameter, verschachtelte Typen (eigene und geerbte), später deklarierte Typen, eingebaute, string,
  // array of const, Unit-Präfix, Typen in bedingten Zweigen.
  Assert.AreEqual(0, Integer(Length(TypeFindings(KundenUnit('System.SysUtils, Vcl.Basis',
    '  TBox<T> = class'#10'    FWert: T;'#10'    FListe: TArray<T>;'#10'  end;'#10 +
    '  TAussen = class'#10'  public type'#10'    TInnen = record'#10'    end;'#10'  public'#10 +
    '    FInnen: TInnen;'#10'    FVor: TSpaeter;'#10'    FStil: TStil;'#10'    FText: string;'#10 +
    '    FZahl: Integer;'#10'    FFehler: System.SysUtils.Exception;'#10 +
    '    procedure Log(const Werte: array of const);'#10'  end;'#10'  TSpaeter = class(TSteuerung)'#10'  end;'#10 +
    '{$IFDEF NEU}'#10'  TNeu = class(TGibtEsNicht)'#10'  end;'#10'{$ENDIF}'#10)))));
  // Teilbereich aus Konstanten.
  Assert.AreEqual(0, Integer(Length(TypeFindings('unit Kunden;'#10'interface'#10'uses'#10'  System.SysUtils;'#10 +
    'const'#10'  MinWert = 1;'#10'  MaxWert = 9;'#10'type'#10'  TBereich = MinWert..MaxWert;'#10 +
    'implementation'#10'end.'))));
  // Ohne System im Index bzw. mit einer unbekannten Unit in uses keine Aussage.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TUnresolvedTypeRule.Create,
    KundenUnit('System.SysUtils', '  TX = class(TBasiz)'#10'  end;'#10), AttributeIndex(False), '', ''))));
  Assert.AreEqual(0, Integer(Length(TypeFindings(KundenUnit('System.SysUtils, Unbekannt',
    '  TX = class(TBasiz)'#10'  end;'#10)))));
end;

procedure TUnresolvedTypeTests.TypeOffGroupAndExclude;
var
  Text: string;
begin
  Text := KundenUnit('System.SysUtils', '  TKunden = TObjectList<TKunde>;'#10);
  Assert.AreEqual(1, Integer(Length(TypeFindings(Text, ''))));
  Assert.AreEqual(0, Integer(Length(TypeFindings(Text, '{"rules": {"unresolved-type": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TypeFindings(Text, '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TypeFindings(Text, '{"rules": {"unresolved-type": {"exclude": ["Src/*.pas"]}}}'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesUnitNotFoundTests);
  TDUnitX.RegisterTestFixture(TUnresolvedAttributeTests);
  TDUnitX.RegisterTestFixture(TUnresolvedTypeTests);

end.
