unit Atlas.Common.Rules.Builtin.Unresolved.Tests;

// Tests für uses-unit-not-found (#1016): Beispiel aus dem Issue mit Vorschlag,
// Namespace-Korrektur, Suchpfad-Korrektur in der .dproj, "in 'Pfad'" (F1026),
// Selbstbezug (F2092), requires (E2202), fehlende Bibliothek (F1027), bedingte
// Einträge, unsichere Suche, Option searchPaths, Abschalten und Ausnahmen,
// "in 'Pfad'" ohne Projekt (#1379);
// unresolved-attribute (#1019): Beispiel mit Korrektur, aufgelöste und
// Compiler-Attribute, andere Bibliothek, unbekanntes Attribut, Fassaden-Unit,
// E1074 nach {$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR} (#1379);
// unresolved-type (#1031): Beispiel mit Korrektur, Deklarationsarten, kein Typ
// (E2005), Zeigerziel (E2564), stille Fälle, Abschalten;
// Typen der IDE (atlas/ideTypes): still, wenn die Unit im uses steht (auch über
// Namespace und Unit-Präfix), sonst Vorschlag der Unit; unresolved-identifier
// still für TFoo.Create.

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
    procedure InPathFileMissingWithoutProject;
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
    [Test]
    procedure ErrorSwitchGivesE1074;
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
    procedure NotATypeCodesLikeDelphi13;
    [Test]
    procedure SilentCases;
    [Test]
    procedure TypeOffGroupAndExclude;
    /// <summary>Die IDE kennt den Typ in einer Unit aus uses, deren Quelltext ihn nicht (mehr) deklariert.
    /// </summary>
    [Test]
    procedure IdeTypeInUsedUnitIsSilent;
    /// <summary>Die IDE kennt den Typ in einer Unit, die nicht im uses steht: Vorschlag samt Korrektur.</summary>
    [Test]
    procedure IdeTypeSuggestsUnit;
    [Test]
    procedure IdeTypeSilencesUnresolvedIdentifier;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.UnitLookup,
  Atlas.Common.Rules.Builtin.Unresolved,
  Atlas.Common.Lsp.IdeTypes,
  Atlas.Tests.RuleAssert;

const
  cDproj =
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
  cLibraryNames: array[0..4] of string = ('C:\BDS\lib\System.dcu', 'C:\BDS\lib\SysInit.dcu',
    'C:\BDS\lib\System.SysUtils.dcu', 'C:\BDS\lib\Vcl.Forms.dcu', 'C:\BDS\lib\rtl.dcp');
  cMainFile = 'C:\P\Src\Haupt.pas';

function LibraryFiles: TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in cLibraryNames do
  begin
    Result := Result + [mName];
  end;
end;

/// <summary>Unit-Suche über die Dateien AFiles mit Projekt C:\P\App.dproj (Suchpfad C:\P\Src).</summary>
function Lookup(const AFiles: TArray<string>; const ANamespaces: TArray<string>): IRuleUnitLookup;
var
  mSetup: TUnitLookupSetup;
begin
  mSetup := Default(TUnitLookupSetup);
  mSetup.Project.FileName := 'C:\P\App.dproj';
  mSetup.Project.SearchPaths := ['C:\P\Src'];
  mSetup.Project.Namespaces := ANamespaces;
  mSetup.LibraryPaths := ['C:\BDS\lib'];
  mSetup.LibraryKnown := True;
  mSetup.ListFiles :=
    function(AFolder: string): TArray<string>
    var
      FileName: string;
    begin
      Result := nil;
      for FileName in AFiles do
      begin
        if SameText(TProjectPaths.DirectoryOf(FileName), AFolder) then
        begin
          Result := Result + [FileName];
        end;
      end;
    end;
  mSetup.ListFolders :=
    function(AFolder: string): TArray<string>
    var
      FileName, Folder: string;
    begin
      Result := nil;
      for FileName in AFiles do
      begin
        Folder := TProjectPaths.DirectoryOf(FileName);
        if SameText(TProjectPaths.DirectoryOf(Folder), AFolder) and (IndexText(Folder, Result) < 0) then
        begin
          Result := Result + [Folder];
        end;
      end;
    end;
  mSetup.FileExists :=
    function(AFileName: string): Boolean
    begin
      Result := IndexText(AFileName, AFiles) >= 0;
    end;
  mSetup.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := cDproj;
      Result := SameText(AFileName, 'C:\P\App.dproj');
    end;
  mSetup.PackageExists :=
    function(AName: string): Boolean
    begin
      Result := IndexText('C:\BDS\lib\' + AName + '.dcp', AFiles) >= 0;
    end;
  Result := TUnitLookup.Create(mSetup);
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
  Result := TRuleAssert.UnitFindings(TUsesUnitNotFoundRule.Create, ASource, cMainFile, AUnits, '', '');
end;

function Findings(const ASource: string; const AUnits: IRuleUnitLookup; const AConfig: string):
  TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.UnitFindings(TUsesUnitNotFoundRule.Create, ASource, cMainFile, AUnits, AConfig,
    'Src/Haupt.pas');
end;

procedure TUsesUnitNotFoundTests.IssueExampleWithSuggestion;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('System.SysUtils, Vcl.Forms, Kunden.Daten, Rechnungs.Druck'), Standard);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Unit Rechnungs.Druck nicht gefunden; ähnlich: Rechnung.Druck (wie F2613).', mFound[0].Message);
  Assert.AreEqual(3, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(44, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(59, mFound[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('Rechnung.Druck verwenden', mFound[0].Fixes[0].Title);
  Assert.AreEqual('Rechnung.Druck', mFound[0].Fixes[0].Edits[0].NewText);
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
  mFound: TArray<TRuleFinding>;
begin
  // Projekt ohne Namespace Vcl: Forms gibt es nur als Vcl.Forms.
  mFound := Findings(Source('SysUtils, Forms'), Lookup(LibraryFiles, ['System']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Unit Forms nicht gefunden; ähnlich: Vcl.Forms (wie F2613).', mFound[0].Message);
  Assert.AreEqual('Vcl.Forms verwenden', mFound[0].Fixes[0].Title);
end;

procedure TUsesUnitNotFoundTests.SearchPathFixEditsProject;
var
  mFound: TArray<TRuleFinding>;
  mEdit: TTextEdit;
begin
  mFound := Findings(Source('System.SysUtils, Hilfen'), Lookup(LibraryFiles + ['C:\P\Extra\Hilfen.pas'],
    ['System']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Unit Hilfen nicht gefunden; sie liegt in Extra außerhalb der Suchpfade (wie F2613).',
    mFound[0].Message);
  Assert.AreEqual('Ordner Extra in den Suchpfad aufnehmen', mFound[0].Fixes[0].Title);
  Assert.AreEqual('C:\P\App.dproj', mFound[0].Fixes[0].FileName);
  // Nur die Zeile mit DCC_UnitSearchPath ändert sich.
  mEdit := mFound[0].Fixes[0].Edits[0];
  Assert.AreEqual(2, mEdit.Range.StartPos.Line);
  Assert.AreEqual(2, mEdit.Range.EndPos.Line);
  Assert.AreEqual('Extra;', mEdit.NewText);
end;

procedure TUsesUnitNotFoundTests.InPathFileMissing;
var
  mText: string;
  mFound: TArray<TRuleFinding>;
begin
  mText := 'program App;'#10'uses'#10'  System.SysUtils,'#10'  Haupt in ''Src\Haupt.pas'','#10 +
    '  Alt in ''Alt\Alt.pas'';'#10'begin'#10'end.';
  mFound := TRuleAssert.UnitFindings(TUsesUnitNotFoundRule.Create, mText, 'C:\P\App.dpr',
    Lookup(LibraryFiles + ['C:\P\Src\Haupt.pas'], ['System']), '', '');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Datei Alt\Alt.pas für Alt nicht gefunden (wie F1026).', mFound[0].Message);
end;

/// <summary>Kontext ohne Unit-Suche, in dem es neben der Datei nur ANames gibt (#1379).</summary>
function ExistingFilesContext(const AText: string; const ANames: TArray<string>): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.Text := AText;
  Result.FileName := 'C:\P\App.dpr';
  Result.FileExists :=
    function(const AName: string): Boolean
    begin
      Result := IndexText(AName, ANames) >= 0;
    end;
end;

procedure TUsesUnitNotFoundTests.InPathFileMissingWithoutProject;
var
  mText: string;
  mFound: TArray<TRuleFinding>;
  mContext: TRuleContext;
begin
  // Fall CmF1026: eine .dpr ohne .dproj, also ohne Unit-Suche; "in '…'" braucht keine Suchpfade.
  mText := 'program App;'#10'uses'#10'  System.SysUtils,'#10'  Haupt in ''Src\Haupt.pas'','#10 +
    '  Alt in ''Alt\Alt.pas'';'#10'begin'#10'end.';
  mFound := TRuleAssert.ContextFindings(TUsesUnitNotFoundRule.Create, ExistingFilesContext(mText,
    ['Src\Haupt.pas']), '');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Datei Alt\Alt.pas für Alt nicht gefunden (wie F1026).', mFound[0].Message);
  Assert.AreEqual(4, mFound[0].Range.StartPos.Line);
  // Ohne Dateizugriff keine Aussage; Einträge in bedingten Blöcken bleiben still.
  mContext := ExistingFilesContext(mText, nil);
  mContext.FileExists := nil;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TUsesUnitNotFoundRule.Create, mContext, ''))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TUsesUnitNotFoundRule.Create, ExistingFilesContext(
    'program App;'#10'uses'#10'{$IFDEF ALT}'#10'  Alt in ''Alt\Alt.pas'','#10'{$ENDIF}'#10 +
    '  System.SysUtils;'#10'begin'#10'end.', nil), ''))));
end;

procedure TUsesUnitNotFoundTests.SelfUseWithoutLookup;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings('unit Haupt;'#10'interface'#10'implementation'#10'uses'#10'  Haupt;'#10'end.', nil);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Haupt verwendet sich selbst (wie F2092).', mFound[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings(Source('Gibt.Es.Nicht'), nil))), 'ohne Suche keine Aussage');
end;

procedure TUsesUnitNotFoundTests.RequiredPackageMissing;
var
  mText: string;
  mFound: TArray<TRuleFinding>;
begin
  mText := 'package Komponenten;'#10'requires'#10'  rtl,'#10'  vclfehlt;'#10'contains'#10 +
    '  Komp.Knopf in ''Komp.Knopf.pas'';'#10'end.';
  mFound := TRuleAssert.UnitFindings(TUsesUnitNotFoundRule.Create, mText, 'C:\P\Komponenten.dpk',
    Lookup(LibraryFiles + ['C:\P\Komp.Knopf.pas'], ['System']), '', '');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Package vclfehlt nicht gefunden (wie E2202).', mFound[0].Message);
end;

procedure TUsesUnitNotFoundTests.MissingSystemGivesOneFinding;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('System.SysUtils, Vcl.Forms, Fehlt'), Lookup(['C:\P\Src\X.pas'], ['System']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Unit System nicht gefunden; der Bibliothekspfad der Installation fehlt (wie F1027).',
    mFound[0].Message);
end;

procedure TUsesUnitNotFoundTests.ConditionalAndUnknownAreSilent;
var
  mSetup: TUnitLookupSetup;
begin
  Assert.AreEqual(0, Integer(Length(Findings(Source('System.SysUtils'#10'  {$IFDEF LINUX}, Posix.Base{$ENDIF}'),
    Standard))));
  // Installation unbekannt: keine Aussage über fehlende Units.
  mSetup := Default(TUnitLookupSetup);
  mSetup.Project.FileName := 'C:\P\App.dproj';
  mSetup.ListFiles :=
    function(AFolder: string): TArray<string>
    begin
      Result := nil;
    end;
  Assert.AreEqual(0, Integer(Length(Findings(Source('Gibt.Es.Nicht'), TUnitLookup.Create(mSetup)))));
end;

procedure TUsesUnitNotFoundTests.SearchPathsOption;
var
  mSetup: TUnitLookupSetup;
  mUnits: IRuleUnitLookup;
  mText: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSetup := Default(TUnitLookupSetup);
  mSetup.Project.FileName := 'C:\P\App.dproj';
  mSetup.LibraryPaths := ['C:\BDS\lib'];
  mSetup.LibraryKnown := True;
  mSetup.ListFiles :=
    function(AFolder: string): TArray<string>
    begin
      Result := nil;
      if SameText(AFolder, 'C:\BDS\lib') then
      begin
        Result := ['C:\BDS\lib\System.dcu'];
      end;
    end;
  mSetup.IndexKnows :=
    function(AName: string): Boolean
    begin
      Result := SameText(AName, 'Nur.Im.Index');
    end;
  mUnits := TUnitLookup.Create(mSetup);
  mText := Source('Nur.Im.Index');
  Assert.AreEqual(1, Integer(Length(Findings(mText, mUnits, ''))), 'project');
  Assert.AreEqual(0, Integer(Length(Findings(mText, mUnits,
    '{"rules": {"uses-unit-not-found": {"searchPaths": "atlas"}}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(mText, mUnits,
    '{"rules": {"uses-unit-not-found": {"searchPaths": "both"}}}'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source('Gibt.Es.Nicht'), mUnits,
    '{"rules": {"uses-unit-not-found": {"searchPaths": "both"}}}'))));
  // Der Parser prüft den Wert.
  TConfigurationParser.Parse('{"rules": {"uses-unit-not-found": {"searchPaths": "alles"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"searchPaths" muss "project", "atlas" oder "both" sein', mIssues[0].Message);
  TConfigurationParser.Parse('{"rules": {"uses-unit-not-found": {"searchPaths": "both"}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

procedure TUsesUnitNotFoundTests.OffGroupAndExclude;
var
  mText: string;
begin
  mText := Source('System.SysUtils, Rechnungs.Druck');
  Assert.AreEqual(1, Integer(Length(Findings(mText, Standard, ''))));
  Assert.AreEqual(0, Integer(Length(Findings(mText, Standard, '{"rules": {"uses-unit-not-found": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(mText, Standard, '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(mText, Standard,
    '{"rules": {"uses-unit-not-found": {"exclude": ["Src/*.pas"]}}}'))));
end;

procedure TUsesUnitNotFoundTests.EntriesSuggestionsAndDiffEdit;
var
  mEntries: TArray<TUsesListEntry>;
  mEdit: TTextEdit;
  mSuggested: TArray<string>;
begin
  mEntries := TUsesUnitNotFoundRule.Entries(TPascalLexer.Tokenize('program P;'#10 +
    'uses A, B.C in ''b\c.pas'' {x}, D;'#10'begin'#10'end.'));
  Assert.AreEqual(3, Integer(Length(mEntries)));
  Assert.AreEqual('B.C', mEntries[1].Name);
  Assert.AreEqual('b\c.pas', mEntries[1].InPath);
  Assert.AreEqual('', mEntries[2].InPath);
  // In einer Unit sind Requires und Contains Bezeichner, keine Package-Listen (Record-Felder nach ";").
  mEntries := TUsesUnitNotFoundRule.Entries(TPascalLexer.Tokenize('unit U;'#10'interface'#10'type'#10 +
    '  TPackageEntry = record end;'#10'  TPackageSource = record'#10'    Name: string;'#10 +
    '    Requires: TArray<TPackageEntry>;'#10'    Contains: TArray<TPackageEntry>;'#10'  end;'#10 +
    'implementation'#10'end.'));
  Assert.AreEqual(0, Integer(Length(mEntries)));
  mEntries := TUsesUnitNotFoundRule.Entries(TPascalLexer.Tokenize('package P;'#10'requires rtl;'#10 +
    'contains A in ''a.pas'';'#10'end.'));
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.AreEqual<TUsesListKind>(TUsesListKind.RequiredPackage, mEntries[0].Kind);
  Assert.AreEqual<TUsesListKind>(TUsesListKind.ContainedUnit, mEntries[1].Kind);
  mEdit := TUsesUnitNotFoundRule.DiffEdit('a'#10'xyz'#10'b', 'a'#10'xQyz'#10'b');
  Assert.AreEqual(1, mEdit.Range.StartPos.Line);
  Assert.AreEqual(1, mEdit.Range.StartPos.Character);
  Assert.AreEqual(1, mEdit.Range.EndPos.Character);
  Assert.AreEqual('Q', mEdit.NewText);
  // Mit Namespace zuerst, dann nach Abstand; höchstens drei.
  mSuggested := TUsesUnitNotFoundRule.Suggestions('Forms', ['Forms3', 'Vcl.Forms', 'Form', 'X', 'Fmx.Forms', 'Formz']);
  Assert.AreEqual(3, Integer(Length(mSuggested)));
  Assert.AreEqual('Fmx.Forms', mSuggested[0]);
  Assert.AreEqual('Vcl.Forms', mSuggested[1]);
  Assert.AreEqual('Form', mSuggested[2]);
end;

{ TUnresolvedAttributeTests }

/// <summary>Index mit System (TCustomAttribute, WeakAttribute), DUnitX.Attributes, der Fassade
/// DUnitX.TestFramework und Rest.Json.Types (JSONNameAttribute).</summary>
function AttributeIndex(AWithSystem: Boolean): ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  if AWithSystem then
  begin
    Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
      '  end;'#10'  TCustomAttribute = class(TObject)'#10'  end;'#10'  WeakAttribute = class(TCustomAttribute)'#10 +
      '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  end;
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
  mLines: TArray<string>;
  mLine: string;
begin
  mLines := AText.Split([#10]);
  mLine := mLines[AEdit.Range.StartPos.Line];
  mLines[AEdit.Range.StartPos.Line] := Copy(mLine, 1, AEdit.Range.StartPos.Character) + AEdit.NewText +
    Copy(mLine, AEdit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, mLines);
end;

procedure TUnresolvedAttributeTests.IssueExampleWithFix;
var
  mFound: TArray<TRuleFinding>;
  mFixed: string;
begin
  mFound := AttributeFindings(TestUnit('System.SysUtils'));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Attribut TestFixture nicht gefunden und wird ignoriert; die Tests laufen nicht (wie W1074). ' +
    'Unit DUnitX.TestFramework fehlt.', mFound[0].Message);
  Assert.AreEqual(5, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(3, mFound[0].Range.StartPos.Character);
  Assert.AreEqual('Attribut Test nicht gefunden und wird ignoriert; die Tests laufen nicht (wie W1074). ' +
    'Unit DUnitX.TestFramework fehlt.', mFound[1].Message);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('uses DUnitX.TestFramework ergänzen', mFound[0].Fixes[0].Title);
  mFixed := Applied(TestUnit('System.SysUtils'), mFound[0].Fixes[0].Edits[0]);
  // Steht die Liste in eigener Zeile, kommt die Unit in eine neue Zeile (wie "uses … ergänzen").
  Assert.AreEqual(TestUnit('System.SysUtils,'#10'  DUnitX.TestFramework'), mFixed);
  Assert.AreEqual(0, Integer(Length(AttributeFindings(mFixed))));
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
  mFound: TArray<TRuleFinding>;
begin
  mFound := AttributeFindings('unit U;'#10'interface'#10'type'#10'  TKunde = class'#10'  public'#10 +
    '    [JSONName(''name'')]'#10'    FName: string;'#10'    [GibtEsNicht]'#10'    FAlter: Integer;'#10'  end;'#10 +
    'implementation'#10'end.');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Attribut JSONName nicht gefunden und wird ignoriert (wie W1074). Unit Rest.Json.Types fehlt.',
    mFound[0].Message);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('Attribut GibtEsNicht nicht gefunden und wird ignoriert (wie W1074).', mFound[1].Message);
  Assert.AreEqual(0, Integer(Length(mFound[1].Fixes)));
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
  mUnits: TArray<string>;
begin
  mUnits := TUnresolvedAttributeRule.DeclaringUnits(AttributeIndex(True), 'TestFixture');
  Assert.AreEqual(1, Integer(Length(mUnits)));
  Assert.AreEqual('DUnitX.TestFramework', mUnits[0]);
  mUnits := TUnresolvedAttributeRule.DeclaringUnits(AttributeIndex(True), 'JSONNameAttribute');
  Assert.AreEqual(1, Integer(Length(mUnits)));
  Assert.AreEqual('Rest.Json.Types', mUnits[0]);
  Assert.AreEqual(0, Integer(Length(TUnresolvedAttributeRule.DeclaringUnits(nil, 'Test'))));
end;

procedure TUnresolvedAttributeTests.AttributeOffGroupAndExclude;
var
  mText: string;
begin
  mText := TestUnit('System.SysUtils');
  Assert.AreEqual(2, Integer(Length(AttributeFindings(mText, ''))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(mText, '{"rules": {"unresolved-attribute": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(mText, '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(mText,
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

procedure TUnresolvedAttributeTests.ErrorSwitchGivesE1074;
var
  mFound: TArray<TRuleFinding>;
begin
  // Fall Cm.E2289: Mit {$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR} meldet Delphi 13 E1074 statt W1074.
  mFound := AttributeFindings('{$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR}'#10'unit U;'#10'interface'#10'type'#10 +
    '  TMitAttribut = class'#10'  public'#10'    [GibtEsNichtAttribute]'#10'    procedure Machen;'#10'  end;'#10 +
    'implementation'#10'procedure TMitAttribut.Machen;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Attribut GibtEsNichtAttribute nicht gefunden und wird ignoriert (wie E1074).', mFound[0].Message);
  // Wieder auf ON gestellt, erst danach oder in einem bedingten Block: W1074.
  mFound := AttributeFindings('unit U;'#10'interface'#10'{$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR}'#10 +
    '{$WARN UNKNOWN_CUSTOM_ATTRIBUTE ON}'#10'type'#10'  TKunde = class'#10'  public'#10'    [GibtEsNicht]'#10 +
    '    FName: string;'#10'  end;'#10'{$IFDEF STRENG}'#10'{$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR}'#10'{$ENDIF}'#10 +
    '  TAuftrag = class'#10'  public'#10'    [GibtEsAuchNicht]'#10'    FNummer: Integer;'#10'  end;'#10 +
    '{$WARN UNKNOWN_CUSTOM_ATTRIBUTE ERROR}'#10'implementation'#10'end.');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Attribut GibtEsNicht nicht gefunden und wird ignoriert (wie W1074).', mFound[0].Message);
  Assert.AreEqual('Attribut GibtEsAuchNicht nicht gefunden und wird ignoriert (wie W1074).', mFound[1].Message);
end;

procedure TUnresolvedTypeTests.IssueExampleWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := KundenUnit('System.SysUtils', '  TKunden = TObjectList<TKunde>;'#10);
  mFound := TypeFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Typ TObjectList ist nicht deklariert; System.Generics.Collections fehlt in uses (wie E2003).',
    mFound[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFound[0].Severity));
  Assert.AreEqual(7, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(12, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(23, mFound[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('uses System.Generics.Collections ergänzen', mFound[0].Fixes[0].Title);
  mFixed := Applied(mSource, mFound[0].Fixes[0].Edits[0]);
  Assert.AreEqual(KundenUnit('System.SysUtils,'#10'  System.Generics.Collections', '  TKunden = TObjectList<TKunde>;'#10),
    mFixed);
  Assert.AreEqual(0, Integer(Length(TypeFindings(mFixed))), mFixed);
end;

procedure TUnresolvedTypeTests.DeclarationKinds;
var
  mFound: TArray<TRuleFinding>;
begin
  // Vorfahr, Feld, Parameter, Ergebnis, globale Variable; ohne Kandidaten im Index ohne Korrektur.
  mFound := TypeFindings(KundenUnit('System.SysUtils', '  TSonder = class(TBasiz)'#10'    FAdresse: TAdresse;'#10 +
    '    function Pruefe(A: TAnschrift): TErgebnis;'#10'  end;'#10'var'#10'  Aktuell: TKundeX;'#10));
  Assert.AreEqual(5, Integer(Length(mFound)));
  Assert.AreEqual('Typ TBasiz ist nicht deklariert (wie E2003).', mFound[0].Message);
  Assert.AreEqual('Typ TAdresse ist nicht deklariert (wie E2003).', mFound[1].Message);
  Assert.AreEqual('Typ TAnschrift ist nicht deklariert (wie E2003).', mFound[2].Message);
  Assert.AreEqual('Typ TErgebnis ist nicht deklariert (wie E2003).', mFound[3].Message);
  Assert.AreEqual('Typ TKundeX ist nicht deklariert (wie E2003).', mFound[4].Message);
  Assert.AreEqual(0, Integer(Length(mFound[4].Fixes)));
end;

procedure TUnresolvedTypeTests.NotATypeAndPointerTarget;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TypeFindings('unit Kunden;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'var'#10 +
    '  Zaehler: Integer;'#10'type'#10'  PKnoten = ^TKnotn;'#10'  TKnoten = record'#10'    Wert: Zaehler;'#10 +
    '  end;'#10'implementation'#10'end.');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Typ TKnotn ist nicht deklariert (wie E2564).', mFound[0].Message);
  Assert.AreEqual('Zaehler ist kein Typ (wie E2005).', mFound[1].Message);
end;

procedure TUnresolvedTypeTests.NotATypeCodesLikeDelphi13;
var
  mFound: TArray<TRuleFinding>;
begin
  // Fälle Cm.E2005b (Routine, E2007), Cm.E2005 (Konstante, E2029) und Cm.E2374 (Mitglied hinter einem Punkt,
  // E2005) mit den Codes von Delphi 13 (#1382).
  mFound := TypeFindings('unit Kunden;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'type'#10 +
    '  TKunde = class'#10'    constructor Erzeuge;'#10'  end;'#10'  TEigen = type TKunde.Erzeuge;'#10 +
    'const'#10'  cZahl = 1;'#10'procedure Nichts;'#10'var'#10'  GWert: Nichts;'#10'  GZahl: cZahl;'#10 +
    'implementation'#10'end.');
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('TKunde.Erzeuge ist kein Typ (wie E2005).', mFound[0].Message);
  Assert.AreEqual('Nichts ist eine Routine, kein Typ (wie E2007).', mFound[1].Message);
  Assert.AreEqual('cZahl ist eine Konstante, kein Typ; der Compiler liest sie als Anfang eines Teilbereichs ' +
    'cZahl..Ende (wie E2029).', mFound[2].Message);
  mFound := nil;
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
  // Typen des Compilers ohne Deklaration in System.pas (Fälle Cm.E2002, Cm.E2071, #1382).
  Assert.AreEqual(0, Integer(Length(TypeFindings(KundenUnit('System.SysUtils',
    '  TProtokoll = class'#10'    FDatei: TextFile;'#10'    FAlt: Text;'#10'    FWert: Real48;'#10 +
    '    procedure Lies(var ADatei: TextFile);'#10'  end;'#10)))));
  // Teilbereich aus Konstanten.
  Assert.AreEqual(0, Integer(Length(TypeFindings('unit Kunden;'#10'interface'#10'uses'#10'  System.SysUtils;'#10 +
    'const'#10'  MinWert = 1;'#10'  MaxWert = 9;'#10'type'#10'  TBereich = MinWert..MaxWert;'#10 +
    'implementation'#10'end.'))));
  // Parameter gleichen Namens wie sein Typ (hWnd: HWND in Watchdog und KeyHook): Der Name gilt dort noch nicht.
  Assert.AreEqual(0, Integer(Length(TypeFindings(KundenUnit('Vcl.Basis',
    '  TX = class'#10'    procedure Zeige(tSteuerung: TSteuerung);'#10'  end;'#10)))));
  // Ohne System im Index bzw. mit einer unbekannten Unit in uses keine Aussage.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TUnresolvedTypeRule.Create,
    KundenUnit('System.SysUtils', '  TX = class(TBasiz)'#10'  end;'#10), AttributeIndex(False), '', ''))));
  Assert.AreEqual(0, Integer(Length(TypeFindings(KundenUnit('System.SysUtils, Unbekannt',
    '  TX = class(TBasiz)'#10'  end;'#10)))));
end;

procedure TUnresolvedTypeTests.TypeOffGroupAndExclude;
var
  mText: string;
begin
  mText := KundenUnit('System.SysUtils', '  TKunden = TObjectList<TKunde>;'#10);
  Assert.AreEqual(1, Integer(Length(TypeFindings(mText, ''))));
  Assert.AreEqual(0, Integer(Length(TypeFindings(mText, '{"rules": {"unresolved-type": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TypeFindings(mText, '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TypeFindings(mText, '{"rules": {"unresolved-type": {"exclude": ["Src/*.pas"]}}}'))));
end;

/// <summary>TypeIndex samt einer Unit Vendor.Grid, deren Quelltext TVendorGrid nicht deklariert (alte Fassung).
/// </summary>
function VendorIndex: ISymbolIndex;
begin
  Result := TypeIndex;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Vendor.Grid;'#10'interface'#10'type'#10 +
    '  TVendorAlt = class'#10'  end;'#10'implementation'#10'end.', 'C:\Vendor\Vendor.Grid.pas', nil));
end;

/// <summary>Katalog der IDE: TVendorGrid in Vendor.Grid.</summary>
function VendorTypes: IRuleIdeTypes;
var
  mCatalog: TIdeTypeCatalog;
  mValue: TJSONValue;
begin
  mCatalog := TIdeTypeCatalog.Create;
  Result := mCatalog;
  mValue := TJSONObject.ParseJSONValue('{"units":[{"unit":"Vendor.Grid","types":[{"name":"TVendorGrid",' +
    '"parent":"Vcl.Controls.TCustomControl"}]}]}');
  try
    mCatalog.Replace(mValue);
  finally
    mValue.Free;
  end;
end;

/// <summary>Die Regel unresolved-identifier aus der Registrierung der Unit.</summary>
function IdentifierRule: IRule;
var
  mRegistry: TRuleRegistry;
begin
  mRegistry := TRuleRegistry.Create;
  try
    RegisterUnresolvedRules(mRegistry);
    mRegistry.Find('unresolved-identifier', Result);
  finally
    mRegistry.Free;
  end;
end;

function IdeFindings(ARule: IRule; const ASource: string; const ATypes: IRuleIdeTypes;
  const ANamespaces: TArray<string>): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.Text := ASource;
  mContext.Index := VendorIndex;
  mContext.IdeTypes := ATypes;
  mContext.Namespaces := ANamespaces;
  Result := TRuleAssert.ContextFindings(ARule, mContext, '');
end;

procedure TUnresolvedTypeTests.IdeTypeInUsedUnitIsSilent;
var
  mSource: string;
begin
  mSource := KundenUnit('System.SysUtils, Vendor.Grid', '  TAnsicht = class'#10'    FGitter: TVendorGrid;'#10 +
    '  end;'#10);
  // Ohne die IDE meldet die Regel den Typ, den der Quelltext von Vendor.Grid nicht kennt.
  Assert.AreEqual(1, Integer(Length(IdeFindings(TUnresolvedTypeRule.Create, mSource, nil, nil))));
  Assert.AreEqual(0, Integer(Length(IdeFindings(TUnresolvedTypeRule.Create, mSource, VendorTypes, nil))));
  // Über den Namespace des Projekts (uses Grid) und mit Unit-Präfix.
  Assert.AreEqual(0, Integer(Length(IdeFindings(TUnresolvedTypeRule.Create, StringReplace(mSource, 'Vendor.Grid',
    'Grid', []), VendorTypes, TArray<string>.Create('Vendor')))));
  Assert.AreEqual(0, Integer(Length(IdeFindings(TUnresolvedTypeRule.Create, StringReplace(mSource, 'TVendorGrid;',
    'Vendor.Grid.TVendorGrid;', []), VendorTypes, nil))));
end;

procedure TUnresolvedTypeTests.IdeTypeSuggestsUnit;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := IdeFindings(TUnresolvedTypeRule.Create, KundenUnit('System.SysUtils', '  TAnsicht = class'#10 +
    '    FGitter: TVendorGrid;'#10'  end;'#10), VendorTypes, nil);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Typ TVendorGrid ist nicht deklariert; Vendor.Grid fehlt in uses (wie E2003).', mFound[0].Message);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('uses Vendor.Grid ergänzen', mFound[0].Fixes[0].Title);
  mFound := nil;
end;

procedure TUnresolvedTypeTests.IdeTypeSilencesUnresolvedIdentifier;
var
  mSource: string;
  mRule: IRule;
begin
  mSource := 'unit Kunden;'#10'interface'#10'uses'#10'  System.SysUtils, Vendor.Grid;'#10'implementation'#10 +
    'procedure Zeige;'#10'begin'#10'  TVendorGrid.Create(nil);'#10'end;'#10'end.';
  mRule := IdentifierRule;
  Assert.AreEqual(1, Integer(Length(IdeFindings(mRule, mSource, nil, nil))));
  Assert.AreEqual(0, Integer(Length(IdeFindings(mRule, mSource, VendorTypes, nil))));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesUnitNotFoundTests);
  TDUnitX.RegisterTestFixture(TUnresolvedAttributeTests);
  TDUnitX.RegisterTestFixture(TUnresolvedTypeTests);

end.
