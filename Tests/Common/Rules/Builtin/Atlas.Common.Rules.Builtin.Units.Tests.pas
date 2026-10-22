unit Atlas.Common.Rules.Builtin.Units.Tests;

// Tests der Regeln für Unit-Kopf, uses und Dateiende: unit-name-mismatch
// (#990).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnitRulesTests = class
  public
    [Test]
    procedure MismatchIssueExample;
    [Test]
    procedure MismatchSilentCases;
    [Test]
    procedure MismatchWarnDirective;
    [Test]
    procedure MismatchUsesInFile;
    [Test]
    procedure MismatchOptions;
    [Test]
    procedure ModuleHeaderRead;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin.Units,
  Atlas.Tests.RuleAssert;

/// <summary>Prüfung von ASource als Datei APath; AFiles sind Paare aus Name und Text für ReadFile.</summary>
function Run(const ARule: IRule; const ASource, APath: string; const AFiles: TArray<string>;
  const AConfig: string): TArray<TRuleFinding>; overload;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := TServerSettings.Default;
  if AConfig <> '' then
    Settings := TConfigurationParser.Parse(AConfig, Issues);
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.RelativePath := APath;
    Context.UnitName := ChangeFileExt(ExtractFileName(StringReplace(APath, '/', '\', [rfReplaceAll])), '');
    Context.Text := ASource;
    Context.Tree := Tree;
    Context.ReadFile :=
      function(const AName: string; out AData: TBytes): Boolean
      var
        Index: Integer;
      begin
        Result := False;
        Index := 0;
        while Index < High(AFiles) do
        begin
          if SameText(AFiles[Index], AName) then
          begin
            AData := TEncoding.UTF8.GetBytes(AFiles[Index + 1]);
            Exit(True);
          end;
          Inc(Index, 2);
        end;
      end;
    Result := TRuleEngine.Run([ARule], Settings, Context);
  finally
    Tree.Free;
  end;
end;

function Run(const ARule: IRule; const ASource, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := Run(ARule, ASource, APath, nil, '');
end;

/// <summary>Wendet ein Edit innerhalb einer Zeile an (Zeilen aus #10).</summary>
function ApplyEdit(const AText: string; const AEdit: TTextEdit): string;
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

{ TUnitRulesTests }

procedure TUnitRulesTests.MismatchIssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := '// Datei: Kunden.Daten.pas'#10'unit Kunden.Model;'#10#10'interface'#10#10'implementation'#10#10'end.';
  Found := Run(TUnitNameMismatchRule.Create, Source, 'Source/Kunden.Daten.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unit-Name Kunden.Model passt nicht zur Datei Kunden.Daten.pas (wie E1038).', Found[0].Message);
  Assert.AreEqual(1, Found[0].Range.StartPos.Line);
  Assert.AreEqual(5, Found[0].Range.StartPos.Character);
  Assert.AreEqual(17, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Unit-Namen in Kunden.Daten ändern', Found[0].Fixes[0].Title);
  Fixed := ApplyEdit(Source, Found[0].Fixes[0].Edits[0]);
  Assert.AreEqual('// Datei: Kunden.Daten.pas'#10'unit Kunden.Daten;'#10#10'interface'#10#10'implementation'#10#10 +
    'end.', Fixed);
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, Fixed, 'Source/Kunden.Daten.pas'))));
  // Passender Name.
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, 'unit Kunden.Model;'#10'interface'#10 +
    'implementation'#10'end.', 'Kunden.Model.pas'))));
end;

procedure TUnitRulesTests.MismatchSilentCases;
var
  Rule: IRule;
begin
  Rule := TUnitNameMismatchRule.Create;
  // Groß-/Kleinschreibung zählt nicht.
  Assert.AreEqual(0, Integer(Length(Run(Rule, 'unit kunden.daten;'#10'interface'#10'implementation'#10'end.',
    'Kunden.Daten.pas'))));
  // Ohne Pfad, andere Endung, Programme und Packages: keine Aussage.
  Assert.AreEqual(0, Integer(Length(Run(Rule, 'unit Kunden;'#10'interface'#10'implementation'#10'end.', ''))));
  Assert.AreEqual(0, Integer(Length(Run(Rule, 'unit Kunden;'#10'interface'#10'implementation'#10'end.',
    'Kunden.inc'))));
  Assert.AreEqual(0, Integer(Length(Run(Rule, 'program Werkzeug;'#10'begin'#10'end.', 'Projekt1.pas'))));
  Assert.AreEqual(0, Integer(Length(Run(Rule, 'package Werkzeug;'#10'end.', 'Projekt1.pas'))));
  // Halb getippter Kopf.
  Assert.AreEqual(0, Integer(Length(Run(Rule, 'unit ', 'Kunden.pas'))));
end;

procedure TUnitRulesTests.MismatchWarnDirective;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Run(TUnitNameMismatchRule.Create, '{$WARN UNIT_NAME_MISMATCH OFF}'#10'unit Alt;'#10'interface'#10 +
    'implementation'#10'end.', 'Neu.pas');
  Assert.AreEqual(0, Integer(Length(Found)));
  Found := Run(TUnitNameMismatchRule.Create, '{$WARNINGS OFF}'#10'unit Alt;'#10'interface'#10'implementation'#10 +
    'end.', 'Neu.pas');
  Assert.AreEqual(0, Integer(Length(Found)));
  // Wieder eingeschaltet bzw. erst hinter dem Namen ausgeschaltet.
  Found := Run(TUnitNameMismatchRule.Create, '{$WARN UNIT_NAME_MISMATCH OFF}{$WARN UNIT_NAME_MISMATCH ERROR}'#10 +
    'unit Alt;'#10'interface'#10'implementation'#10'end.', 'Neu.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Found := Run(TUnitNameMismatchRule.Create, 'unit Alt;'#10'{$WARN UNIT_NAME_MISMATCH OFF}'#10'interface'#10 +
    'implementation'#10'end.', 'Neu.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  // Kein gültiger Bezeichner als Dateiname: Meldung ohne Korrektur.
  Found := Run(TUnitNameMismatchRule.Create, 'unit Alt;'#10'interface'#10'implementation'#10'end.', 'Kopie von Alt.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TUnitRulesTests.MismatchUsesInFile;
const
  Projekt = 'program Projekt;'#10'uses'#10'  Kunden.Model in ''Quellen\Kunden.Daten.pas'','#10 +
    '  Haupt in ''Haupt.pas'';'#10'begin'#10'end.';
var
  Found: TArray<TRuleFinding>;
  Files: TArray<string>;
begin
  Files := ['Quellen\Kunden.Daten.pas', 'unit Kunden.Daten;'#10'interface'#10'implementation'#10'end.',
    'Haupt.pas', 'unit Haupt;'#10'interface'#10'implementation'#10'end.'];
  Found := Run(TUnitNameMismatchRule.Create, Projekt, 'Projekt.dpr', Files, '');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Kunden.Model in ''Quellen\Kunden.Daten.pas'': die Datei deklariert die Unit Kunden.Daten ' +
    '(wie E2085).', Found[0].Message);
  Assert.AreEqual(2, Found[0].Range.StartPos.Line);
  Assert.AreEqual('In Kunden.Daten ändern', Found[0].Fixes[0].Title);
  Assert.AreEqual('program Projekt;'#10'uses'#10'  Kunden.Daten in ''Quellen\Kunden.Daten.pas'','#10 +
    '  Haupt in ''Haupt.pas'';'#10'begin'#10'end.', ApplyEdit(Projekt, Found[0].Fixes[0].Edits[0]));
  // Datei nicht lesbar, kein unit-Kopf oder Eintrag in einem {$IF…}-Zweig: still.
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, Projekt, 'Projekt.dpr', nil, ''))));
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, Projekt, 'Projekt.dpr',
    ['Quellen\Kunden.Daten.pas', 'program X;'#10'begin'#10'end.'], ''))));
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, 'program Projekt;'#10'uses'#10 +
    '{$IFDEF DEBUG}'#10'  Kunden.Model in ''Quellen\Kunden.Daten.pas'','#10'{$ENDIF}'#10'  Haupt in ''Haupt.pas'';'#10 +
    'begin'#10'end.', 'Projekt.dpr', Files, ''))));
end;

procedure TUnitRulesTests.MismatchOptions;
const
  Source = 'unit Alt;'#10'interface'#10'implementation'#10'end.';
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, Source, '',
    'Source/Neu.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, Source,
    '{"rules": {"unit-name-mismatch": "off"}}', 'Source/Neu.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}', 'Source/Neu.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, Source,
    '{"rules": {"unit-name-mismatch": {"exclude": ["Source/*.pas"]}}}', 'Source/Neu.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, Source,
    '{"rules": {"unit-name-mismatch": {"exclude": ["Alt/*.pas"]}}}', 'Source/Neu.pas'))));
end;

procedure TUnitRulesTests.ModuleHeaderRead;
var
  Header: TModuleHeader;
begin
  Header := TModuleHeader.Read(TPascalLexer.Tokenize('{ Kopf } unit Kunden.{x}Daten platform;'));
  Assert.IsTrue(Header.Kind = TModuleKind.UnitModule);
  Assert.AreEqual('Kunden.Daten', Header.Name);
  Header := TModuleHeader.Read(TPascalLexer.Tokenize('package Atlas.Common;'));
  Assert.IsTrue(Header.Kind = TModuleKind.PackageModule);
  Assert.AreEqual('Atlas.Common', Header.Name);
  Header := TModuleHeader.Read(TPascalLexer.Tokenize('library Werkzeug;'));
  Assert.IsTrue(Header.Kind = TModuleKind.LibraryModule);
  Header := TModuleHeader.Read(TPascalLexer.Tokenize('begin end.'));
  Assert.IsTrue(Header.Kind = TModuleKind.None);
  Assert.AreEqual('', Header.Name);
  Assert.AreEqual('Neu', TUnitNameMismatchRule.ExpectedName('C:\Projekt\Quellen\Neu.pas'));
  Assert.AreEqual('Kunden.Daten', TUnitNameMismatchRule.ExpectedName('Quellen/Kunden.Daten.PAS'));
  Assert.AreEqual('', TUnitNameMismatchRule.ExpectedName('Projekt.dpr'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitRulesTests);

end.
