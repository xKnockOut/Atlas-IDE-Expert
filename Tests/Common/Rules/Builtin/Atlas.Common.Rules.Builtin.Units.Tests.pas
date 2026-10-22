unit Atlas.Common.Rules.Builtin.Units.Tests;

// Tests der Regeln für Unit-Kopf, uses und Dateiende: unit-name-mismatch
// (#990), text-after-final-end (#991), exports-invalid (#1077),
// unit-name-conflict (#1079), implicit-variants-unit (#1082).

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
    [Test]
    procedure TextAfterIssueExample;
    [Test]
    procedure TextAfterSilentCases;
    [Test]
    procedure TextAfterAllowComments;
    [Test]
    procedure TextAfterOptions;
    [Test]
    procedure ExportsIssueExample;
    [Test]
    procedure ExportsDuplicateVariants;
    [Test]
    procedure ExportsNotExportable;
    [Test]
    procedure ExportsLocalScope;
    [Test]
    procedure ExportsSilentCases;
    [Test]
    procedure ExportsEntries;
    [Test]
    procedure ExportsOptions;
    [Test]
    procedure ConflictReservedName;
    [Test]
    procedure ConflictNoInclude;
    [Test]
    procedure ConflictOptions;
    [Test]
    procedure VariantsIssueExample;
    [Test]
    procedure VariantsSilentCases;
    [Test]
    procedure VariantsSpelling;
    [Test]
    procedure VariantsOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Contract,
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

/// <summary>Offset von APosition in AText mit Zeilen aus #10.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line, Index: Integer;
begin
  Line := 0;
  Index := 1;
  while (Line < APosition.Line) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  Result := Index + APosition.Character;
end;

/// <summary>Wendet ein Edit an, auch über Zeilen.</summary>
function ApplyAny(const AText: string; const AEdit: TTextEdit): string;
var
  Start, Stop: Integer;
begin
  Start := OffsetOf(AText, AEdit.Range.StartPos);
  Stop := OffsetOf(AText, AEdit.Range.EndPos);
  Result := Copy(AText, 1, Start - 1) + AEdit.NewText + Copy(AText, Stop, MaxInt);
end;

function Kunde(const ATail: string): string;
begin
  Result := 'unit Kunde;'#10'interface'#10'implementation'#10'procedure TKunde.Laden;'#10'begin'#10'end;'#10 +
    'end.' + ATail;
end;

type
  /// <summary>Unit-Suche, die genau die Units aus FKnown findet; mit FUnknown ohne Aussage.</summary>
  TFakeUnits = class(TInterfacedObject, IRuleUnitLookup)
  private
    FKnown: TArray<string>;
    FUnknown: Boolean;
  public
    constructor Create(const AKnown: TArray<string>; AUnknown: Boolean);
    function Find(const AUnitName, AInPath, AFromFile: string; ASources: TRuleUnitSources): TRuleUnitAnswer;
    function FindPackage(const APackage: string): TRuleUnitAnswer;
    function KnownUnits(ASources: TRuleUnitSources): TArray<string>;
    function FolderOutsidePaths(const AUnitName: string): string;
    function ReadProject(out AFileName, AText: string): Boolean;
  end;

constructor TFakeUnits.Create(const AKnown: TArray<string>; AUnknown: Boolean);
begin
  inherited Create;
  FKnown := AKnown;
  FUnknown := AUnknown;
end;

function TFakeUnits.Find(const AUnitName, AInPath, AFromFile: string; ASources: TRuleUnitSources): TRuleUnitAnswer;
var
  Known: string;
begin
  Result := TRuleUnitAnswer.Missing;
  if FUnknown then
    Result := TRuleUnitAnswer.Unknown;
  for Known in FKnown do
    if SameText(Known, AUnitName) then
      Result := TRuleUnitAnswer.Found;
end;

function TFakeUnits.FindPackage(const APackage: string): TRuleUnitAnswer;
begin
  Result := TRuleUnitAnswer.Unknown;
end;

function TFakeUnits.KnownUnits(ASources: TRuleUnitSources): TArray<string>;
begin
  Result := FKnown;
end;

function TFakeUnits.FolderOutsidePaths(const AUnitName: string): string;
begin
  Result := '';
end;

function TFakeUnits.ReadProject(out AFileName, AText: string): Boolean;
begin
  AFileName := '';
  AText := '';
  Result := False;
end;

const
  /// <summary>implicit-variants-unit ist experimentell und muss eingeschaltet werden.</summary>
  VariantsOn = '{"rules": {"implicit-variants-unit": "hint"}}';

function Speicher(const AUses, ADeclaration: string): string;
begin
  Result := 'unit Speicher;'#10'interface'#10'uses'#10'  ' + AUses + ';'#10 + ADeclaration + 'implementation'#10 +
    'end.';
end;

function VariantFindings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, ASource, VariantsOn, 'Speicher.pas');
end;

function Werkzeug(const ADeclarations, AExports: string): string;
begin
  Result := 'library Werkzeug;'#10'procedure Initialisieren; stdcall;'#10'begin'#10'end;'#10 +
    'procedure Berechnen; stdcall;'#10'begin'#10'end;'#10 + ADeclarations + 'exports'#10 + AExports + ';'#10 +
    'begin'#10'end.';
end;

function ExportFindings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TExportsInvalidRule.Create, ASource);
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

procedure TUnitRulesTests.TextAfterIssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Kunde(#10#10'procedure TKunde.Speichern;'#10'begin'#10);
  Found := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Code nach end. wird nicht übersetzt (wie W1011).', Found[0].Message);
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Assert.AreEqual(0, Found[0].Range.StartPos.Character);
  Assert.AreEqual(9, Found[0].Range.EndPos.Line);
  Assert.AreEqual('Text nach end. entfernen', Found[0].Fixes[0].Title);
  Fixed := ApplyAny(Source, Found[0].Fixes[0].Edits[0]);
  Assert.AreEqual(Kunde(#10), Fixed);
  TRuleAssert.Silent(TTextAfterFinalEndRule.Create, Fixed);
  // Programm: end gehört zum Block.
  Found := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, 'program P;'#10'begin'#10'end.'#10'Rest;');
  Assert.AreEqual(1, Integer(Length(Found)));
  // Unit mit initialization und Package.
  TRuleAssert.Reports(TTextAfterFinalEndRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'initialization'#10'  X := 1;'#10'end.'#10'Y := 2;');
  TRuleAssert.Reports(TTextAfterFinalEndRule.Create, 'package P;'#10'requires'#10'  rtl;'#10'end.'#10'contains X;');
end;

procedure TUnitRulesTests.TextAfterSilentCases;
begin
  // Nichts dahinter, nur Leerraum, Kommentare und Direktiven.
  TRuleAssert.Silent(TTextAfterFinalEndRule.Create, Kunde(''));
  TRuleAssert.Silent(TTextAfterFinalEndRule.Create, Kunde(#10#10#10));
  TRuleAssert.Silent(TTextAfterFinalEndRule.Create, Kunde(#10'// Ende'#10'{ Notiz }'#10'(* alt *)'#10'{$ENDIF}'));
  // Halb getippter Code: Der Parser meldet Fehler, die Lage von end. ist unsicher.
  TRuleAssert.Silent(TTextAfterFinalEndRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure A;'#10'begin'#10'  if X then'#10'end.'#10'procedure B;');
  // end. in einem {$IF…}-Zweig.
  TRuleAssert.Silent(TTextAfterFinalEndRule.Create, 'program P;'#10'begin'#10'{$IFDEF A}'#10'end.'#10'{$ELSE}'#10 +
    '  X;'#10'end.'#10'{$ENDIF}');
  // {$WARNINGS OFF} davor.
  TRuleAssert.Silent(TTextAfterFinalEndRule.Create, '{$WARNINGS OFF}'#10 + Kunde(#10'Rest;'));
end;

procedure TUnitRulesTests.TextAfterAllowComments;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Kunde(#10'// Ende'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source, '', 'Kunde.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source,
    '{"rules": {"text-after-final-end": {"allowComments": true}}}', 'Kunde.pas'))));
  Found := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source,
    '{"rules": {"text-after-final-end": {"allowComments": false}}}', 'Kunde.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Kommentar nach end. wird nicht übersetzt (wie W1011).', Found[0].Message);
  Assert.AreEqual(Kunde(#10), ApplyAny(Source, Found[0].Fixes[0].Edits[0]));
  // Mit Kommentar vor dem Code beginnt die Meldung beim Code bzw. mit allowComments = false beim Kommentar.
  Source := Kunde(#10'// Rest'#10'X;'#10);
  Found := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source, '', 'Kunde.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Found := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source,
    '{"rules": {"text-after-final-end": {"allowComments": false}}}', 'Kunde.pas');
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual('Code nach end. wird nicht übersetzt (wie W1011).', Found[0].Message);
end;

procedure TUnitRulesTests.TextAfterOptions;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  // Der Parser prüft den Typ von allowComments.
  TConfigurationParser.Parse('{"rules": {"text-after-final-end": {"allowComments": "ja"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"allowComments" muss true oder false sein', Issues[0].Message);
  Source := Kunde(#10'Rest;');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source, '',
    'Source/Kunde.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source,
    '{"rules": {"text-after-final-end": "off"}}', 'Source/Kunde.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}', 'Source/Kunde.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, Source,
    '{"rules": {"text-after-final-end": {"exclude": ["Source/*.pas"]}}}', 'Source/Kunde.pas'))));
end;

procedure TUnitRulesTests.ExportsIssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Werkzeug('', '  Initialisieren,'#10'  Berechnen,'#10'  Initialisieren');
  Found := ExportFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Initialisieren wird zweimal exportiert (wie E2287).', Found[0].Message);
  Assert.AreEqual(10, Found[0].Range.StartPos.Line);
  Assert.AreEqual(2, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Doppelten Eintrag entfernen', Found[0].Fixes[0].Title);
  Fixed := ApplyAny(Source, Found[0].Fixes[0].Edits[0]);
  Assert.AreEqual(Werkzeug('', '  Initialisieren,'#10'  Berechnen'), Fixed);
  Assert.AreEqual(0, Integer(Length(ExportFindings(Fixed))));
end;

procedure TUnitRulesTests.ExportsDuplicateVariants;
var
  Found: TArray<TRuleFinding>;
  Source: string;
begin
  // Gleicher Exportname über name '…', auch in zwei Klauseln.
  Found := ExportFindings(Werkzeug('exports Initialisieren name ''Start'';'#10, '  Berechnen name ''Start'''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der Name ''Start'' wird zweimal exportiert (wie E2287).', Found[0].Message);
  // Einziger Eintrag seiner Klausel: Die Korrektur entfernt die Klausel.
  Source := Werkzeug('exports Berechnen;'#10, '  Berechnen');
  Found := ExportFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(StringReplace(Source, 'exports'#10'  Berechnen;', '', []),
    ApplyAny(Source, Found[0].Fixes[0].Edits[0]));
  // Doppelter erster Eintrag einer späteren Klausel: entfernt bis zum nächsten Eintrag.
  Source := Werkzeug('exports Berechnen;'#10, 'Berechnen, Initialisieren');
  Found := ExportFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Werkzeug('exports Berechnen;'#10, 'Initialisieren'), ApplyAny(Source, Found[0].Fixes[0].Edits[0]));
  // Groß-/Kleinschreibung zählt bei Bezeichnern nicht, bei Exportnamen schon.
  Assert.AreEqual(1, Integer(Length(ExportFindings(Werkzeug('', 'Berechnen, berechnen')))));
  Assert.AreEqual(0, Integer(Length(ExportFindings(Werkzeug('', 'Berechnen name ''A'', Initialisieren name ''a''')))));
end;

procedure TUnitRulesTests.ExportsNotExportable;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ExportFindings(Werkzeug('threadvar'#10'  Zaehler: Integer;'#10, 'Zaehler'));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die threadvar Zaehler kann nicht exportiert werden (wie E2276).', Found[0].Message);
  Found := ExportFindings(Werkzeug('procedure Intern; local;'#10'begin'#10'end;'#10, 'Intern'));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Intern ist mit local deklariert und kann nicht exportiert werden (wie E2276).', Found[0].Message);
  Found := ExportFindings(Werkzeug('var'#10'  Zaehler: Integer;'#10'const'#10'  Version = 3;'#10'type'#10 +
    '  TRueckruf = procedure;'#10, 'Zaehler, Version, TRueckruf'));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('Zaehler ist keine Prozedur oder Funktion und kann nicht exportiert werden (wie E2121).',
    Found[0].Message);
  Assert.AreEqual('TRueckruf ist keine Prozedur oder Funktion und kann nicht exportiert werden (wie E2121).',
    Found[2].Message);
  // Variable eines Prozedurtyps bleibt eine Variable.
  Assert.AreEqual(1, Integer(Length(ExportFindings(Werkzeug('var'#10'  Rueckruf: procedure;'#10, 'Rueckruf')))));
end;

procedure TUnitRulesTests.ExportsLocalScope;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ExportFindings('library Werkzeug;'#10'procedure Starten;'#10'exports Starten;'#10'begin'#10'end;'#10 +
    'begin'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('exports ist nur auf globaler Ebene erlaubt (wie E2191).', Found[0].Message);
  Assert.AreEqual(2, Found[0].Range.StartPos.Line);
  Assert.AreEqual(0, Found[0].Range.StartPos.Character);
  Assert.AreEqual(7, Found[0].Range.EndPos.Character);
end;

procedure TUnitRulesTests.ExportsSilentCases;
begin
  // Überladene Routinen mit Parametern, unterschiedliche Exportnamen, Namen aus anderen Units und mit Punkt.
  TRuleAssert.Silent(TExportsInvalidRule.Create, Werkzeug('',
    'Initialisieren, Berechnen name ''Rechnen'', Berechnen name ''Rechnen2'' index 2, Fremd, Fremd.Start, ' +
    'Teilen(A: Integer), Teilen(A: Double) name ''TeilenD'''));
  // Exportname als Ausdruck: kein Vergleich.
  TRuleAssert.Silent(TExportsInvalidRule.Create, Werkzeug('', 'Initialisieren name Praefix + ''A'', ' +
    'Berechnen name Praefix + ''A'''));
  // Zwei Einträge in sich ausschließenden Zweigen.
  TRuleAssert.Silent(TExportsInvalidRule.Create, Werkzeug('', '{$IFDEF WIN64}'#10'  Berechnen name ''B'''#10 +
    '{$ELSE}'#10'  Initialisieren name ''B'''#10'{$ENDIF}'));
  // exports im interface einer Unit mit der Routine aus dem implementation-Teil.
  TRuleAssert.Silent(TExportsInvalidRule.Create, 'unit Dienst;'#10'interface'#10'procedure Start; stdcall;'#10 +
    'exports Start;'#10'implementation'#10'procedure Start;'#10'begin'#10'end;'#10'end.');
end;

procedure TUnitRulesTests.ExportsEntries;
var
  Tokens: TArray<TPascalToken>;
  Entries: TArray<TExportEntry>;
begin
  Tokens := TPascalLexer.Tokenize('exports A.B(X: Integer) name ''Ab'' index 3, C resident, D name P + ''x'';');
  Entries := TExportsInvalidRule.Entries(Tokens, 0, High(Tokens));
  Assert.AreEqual(3, Integer(Length(Entries)));
  Assert.AreEqual('A.B', Entries[0].Name);
  Assert.AreEqual('(X:INTEGER)', Entries[0].Parameters);
  Assert.AreEqual('Ab', Entries[0].ExportName);
  Assert.IsTrue(Entries[0].HasNameClause);
  Assert.AreEqual('C', Entries[1].Name);
  Assert.IsFalse(Entries[1].HasNameClause);
  Assert.AreEqual('D', Entries[2].Name);
  Assert.IsTrue(Entries[2].HasNameClause);
  Assert.AreEqual('', Entries[2].ExportName);
end;

procedure TUnitRulesTests.ExportsOptions;
var
  Source: string;
begin
  Source := Werkzeug('', 'Berechnen, Berechnen');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TExportsInvalidRule.Create, Source, '', 'Werkzeug.dpr'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExportsInvalidRule.Create, Source,
    '{"rules": {"exports-invalid": "off"}}', 'Werkzeug.dpr'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExportsInvalidRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}', 'Werkzeug.dpr'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExportsInvalidRule.Create, Source,
    '{"rules": {"exports-invalid": {"exclude": ["Werkzeug.dpr"]}}}', 'Werkzeug.dpr'))));
end;

procedure TUnitRulesTests.ConflictReservedName;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Run(TUnitNameConflictRule.Create, 'unit System;'#10'interface'#10'implementation'#10'end.', 'System.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der Unit-Name System ist für den Compiler reserviert (wie E2272).', Found[0].Message);
  Assert.AreEqual(0, Found[0].Range.StartPos.Line);
  Assert.AreEqual(5, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Run(TUnitNameConflictRule.Create, 'unit sysinit;'#10'interface'#10 +
    'implementation'#10'end.', 'sysinit.pas'))));
  // Namensraum System, andere Units und die RTL selbst bleiben still.
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameConflictRule.Create, 'unit System.Kunden;'#10'interface'#10 +
    'implementation'#10'end.', 'System.Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameConflictRule.Create, 'unit Kunden;'#10'interface'#10 +
    'implementation'#10'end.', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameConflictRule.Create, 'unit System;'#10'interface'#10 +
    'implementation'#10'end.', 'C:\BDS\source\rtl\sys\System.pas'))));
  // Das Beispiel aus #1079 übersetzt Delphi: keine Meldung.
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameConflictRule.Create, 'unit Kunden;'#10'interface'#10'uses'#10 +
    '  Kunden.Daten;'#10'implementation'#10'end.', 'Kunden.pas'))));
end;

procedure TUnitRulesTests.ConflictNoInclude;
const
  Source = 'unit Haupt;'#10'{$NOINCLUDE Kunden.Datn}'#10'{$NOINCLUDE Kunden.Daten}'#10'interface'#10 +
    'implementation'#10'end.';
var
  Found: TArray<TRuleFinding>;
begin
  Found := TRuleAssert.UnitFindings(TUnitNameConflictRule.Create, Source, 'C:\P\Haupt.pas',
    TFakeUnits.Create(['Kunden.Daten', 'System'], False), '', '');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('{$NOINCLUDE Kunden.Datn}: Kunden.Datn ist keine bekannte Unit (wie E2242).', Found[0].Message);
  Assert.AreEqual(1, Found[0].Range.StartPos.Line);
  Assert.AreEqual(12, Found[0].Range.StartPos.Character);
  Assert.AreEqual(23, Found[0].Range.EndPos.Character);
  Assert.AreEqual('Kunden.Daten verwenden', Found[0].Fixes[0].Title);
  // Ohne Unit-Suche bzw. ohne sichere Aussage: still.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.UnitFindings(TUnitNameConflictRule.Create, Source, 'C:\P\Haupt.pas',
    nil, '', ''))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.UnitFindings(TUnitNameConflictRule.Create, Source, 'C:\P\Haupt.pas',
    TFakeUnits.Create(['Kunden.Daten'], True), '', ''))));
end;

procedure TUnitRulesTests.ConflictOptions;
const
  Source = 'unit System;'#10'interface'#10'implementation'#10'end.';
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUnitNameConflictRule.Create, Source, '', 'Src/System.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameConflictRule.Create, Source,
    '{"rules": {"unit-name-conflict": "off"}}', 'Src/System.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameConflictRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}', 'Src/System.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameConflictRule.Create, Source,
    '{"rules": {"unit-name-conflict": {"exclude": ["Src/*.pas"]}}}', 'Src/System.pas'))));
end;

procedure TUnitRulesTests.VariantsIssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Speicher('System.SysUtils', 'var Wert: Variant;'#10);
  Found := VariantFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Variant wird ohne System.Variants in uses verwendet (wie W1040).', Found[0].Message);
  Assert.AreEqual(4, Found[0].Range.StartPos.Line);
  Assert.AreEqual(10, Found[0].Range.StartPos.Character);
  Assert.AreEqual('System.Variants in uses aufnehmen', Found[0].Fixes[0].Title);
  Fixed := ApplyAny(Source, Found[0].Fixes[0].Edits[0]);
  Assert.AreEqual(Speicher('System.SysUtils,'#10'  System.Variants', 'var Wert: Variant;'#10), Fixed);
  Assert.AreEqual(0, Integer(Length(VariantFindings(Fixed))));
  // OleVariant als Parameter im interface, Typargument.
  Found := VariantFindings('unit Speicher;'#10'interface'#10'procedure Setzen(const AWert: OleVariant);'#10 +
    'implementation'#10'procedure Setzen(const AWert: OleVariant);'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('OleVariant wird ohne System.Variants in uses verwendet (wie W1040).', Found[0].Message);
  Assert.AreEqual(2, Found[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(VariantFindings(Speicher('System.Generics.Collections',
    'var Liste: TList<Variant>;'#10)))));
end;

procedure TUnitRulesTests.VariantsSilentCases;
begin
  // Variants eingebunden (auch ohne Namespace, im implementation-uses, in einem Zweig).
  Assert.AreEqual(0, Integer(Length(VariantFindings(Speicher('SysUtils, Variants', 'var Wert: Variant;'#10)))));
  Assert.AreEqual(0, Integer(Length(VariantFindings('unit Speicher;'#10'interface'#10'implementation'#10 +
    'uses'#10'  {$IFDEF MSWINDOWS}System.Variants{$ENDIF};'#10'var Wert: Variant;'#10'end.'))));
  // Kein Variant, eigener Typ Variant, die Unit Variants selbst, abgeschaltete Warnung.
  Assert.AreEqual(0, Integer(Length(VariantFindings(Speicher('System.SysUtils', 'var Wert: Integer;'#10)))));
  Assert.AreEqual(0, Integer(Length(VariantFindings(Speicher('System.SysUtils',
    'type Variant = Integer;'#10'var Wert: Variant;'#10)))));
  Assert.AreEqual(0, Integer(Length(VariantFindings('unit System.Variants;'#10'interface'#10 +
    'function VarIsNull(const V: Variant): Boolean;'#10'implementation'#10'end.'))));
  Assert.AreEqual(0, Integer(Length(VariantFindings('{$WARN IMPLICIT_VARIANTS OFF}'#10 +
    Speicher('System.SysUtils', 'var Wert: Variant;'#10)))));
  // Ohne Einschalten (experimentell) still.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TImplicitVariantsUnitRule.Create,
    Speicher('System.SysUtils', 'var Wert: Variant;'#10), '', 'Speicher.pas'))));
end;

procedure TUnitRulesTests.VariantsSpelling;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  // Ohne Namespace wie die übrigen Einträge.
  Source := Speicher('SysUtils, Classes', 'var Wert: Variant;'#10);
  Found := VariantFindings(Source);
  Assert.AreEqual('Variants in uses aufnehmen', Found[0].Fixes[0].Title);
  Assert.AreEqual(Speicher('SysUtils, Classes,'#10'  Variants', 'var Wert: Variant;'#10),
    ApplyAny(Source, Found[0].Fixes[0].Edits[0]));
  // Ohne uses im Abschnitt: neues uses hinter implementation.
  Source := 'unit Speicher;'#10'interface'#10'implementation'#10'var Wert: Variant;'#10'end.';
  Found := VariantFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.Contains(ApplyAny(Source, Found[0].Fixes[0].Edits[0]), 'uses');
  Assert.Contains(ApplyAny(Source, Found[0].Fixes[0].Edits[0]), 'System.Variants;');
end;

procedure TUnitRulesTests.VariantsOptions;
var
  Source: string;
begin
  Source := Speicher('System.SysUtils', 'var Wert: Variant;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, Source, VariantsOn,
    'Src/Speicher.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, Source,
    '{"rules": {"implicit-variants-unit": "off"}}', 'Src/Speicher.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, Source,
    '{"rules": {"implicit-variants-unit": "hint", "group:compiler": "off"}}', 'Src/Speicher.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, Source,
    '{"rules": {"implicit-variants-unit": {"severity": "hint", "exclude": ["Src/*.pas"]}}}', 'Src/Speicher.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitRulesTests);

end.
