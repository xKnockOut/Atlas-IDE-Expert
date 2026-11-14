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
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := TServerSettings.Default;
  if AConfig <> '' then
  begin
    mSettings := TConfigurationParser.Parse(AConfig, mIssues);
  end;
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := APath;
    mContext.UnitName := ChangeFileExt(ExtractFileName(StringReplace(APath, '/', '\', [rfReplaceAll])), '');
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.ReadFile :=
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
    Result := TRuleEngine.Run([ARule], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

function Run(const ARule: IRule; const ASource, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := Run(ARule, ASource, APath, nil, '');
end;

/// <summary>Offset von APosition in AText mit Zeilen aus #10.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  mLine, mIndex: Integer;
begin
  mLine := 0;
  mIndex := 1;
  while (mLine < APosition.Line) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  Result := mIndex + APosition.Character;
end;

/// <summary>Wendet ein Edit an, auch über Zeilen.</summary>
function ApplyAny(const AText: string; const AEdit: TTextEdit): string;
var
  mStart, mStop: Integer;
begin
  mStart := OffsetOf(AText, AEdit.Range.StartPos);
  mStop := OffsetOf(AText, AEdit.Range.EndPos);
  Result := Copy(AText, 1, mStart - 1) + AEdit.NewText + Copy(AText, mStop, MaxInt);
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
    function FindFile(const AFileName, AFromFile: string): TRuleUnitAnswer;
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
  mKnown: string;
begin
  Result := TRuleUnitAnswer.Missing;
  if FUnknown then
  begin
    Result := TRuleUnitAnswer.Unknown;
  end;
  for mKnown in FKnown do
  begin
    if SameText(mKnown, AUnitName) then
    begin
      Result := TRuleUnitAnswer.Found;
    end;
  end;
end;

function TFakeUnits.FindPackage(const APackage: string): TRuleUnitAnswer;
begin
  Result := TRuleUnitAnswer.Unknown;
end;

function TFakeUnits.FindFile(const AFileName, AFromFile: string): TRuleUnitAnswer;
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
  cVariantsOn = '{"rules": {"implicit-variants-unit": "hint"}}';

function Speicher(const AUses, ADeclaration: string): string;
begin
  Result := 'unit Speicher;'#10'interface'#10'uses'#10'  ' + AUses + ';'#10 + ADeclaration + 'implementation'#10 +
    'end.';
end;

function VariantFindings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, ASource, cVariantsOn, 'Speicher.pas');
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
  mLines: TArray<string>;
  mLine: string;
begin
  mLines := AText.Split([#10]);
  mLine := mLines[AEdit.Range.StartPos.Line];
  mLines[AEdit.Range.StartPos.Line] := Copy(mLine, 1, AEdit.Range.StartPos.Character) + AEdit.NewText +
    Copy(mLine, AEdit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, mLines);
end;

{ TUnitRulesTests }

procedure TUnitRulesTests.MismatchIssueExample;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := '// Datei: Kunden.Daten.pas'#10'unit Kunden.Model;'#10#10'interface'#10#10'implementation'#10#10'end.';
  mFound := Run(TUnitNameMismatchRule.Create, mSource, 'Source/Kunden.Daten.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Unit-Name Kunden.Model passt nicht zur Datei Kunden.Daten.pas (wie E1038).', mFound[0].Message);
  Assert.AreEqual(1, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(5, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(17, mFound[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('Unit-Namen in Kunden.Daten ändern', mFound[0].Fixes[0].Title);
  mFixed := ApplyEdit(mSource, mFound[0].Fixes[0].Edits[0]);
  Assert.AreEqual('// Datei: Kunden.Daten.pas'#10'unit Kunden.Daten;'#10#10'interface'#10#10'implementation'#10#10 +
    'end.', mFixed);
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, mFixed, 'Source/Kunden.Daten.pas'))));
  // Passender Name.
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, 'unit Kunden.Model;'#10'interface'#10 +
    'implementation'#10'end.', 'Kunden.Model.pas'))));
end;

procedure TUnitRulesTests.MismatchSilentCases;
var
  mRule: IRule;
begin
  mRule := TUnitNameMismatchRule.Create;
  // Groß-/Kleinschreibung zählt nicht.
  Assert.AreEqual(0, Integer(Length(Run(mRule, 'unit kunden.daten;'#10'interface'#10'implementation'#10'end.',
    'Kunden.Daten.pas'))));
  // Ohne Pfad, andere Endung, Programme und Packages: keine Aussage.
  Assert.AreEqual(0, Integer(Length(Run(mRule, 'unit Kunden;'#10'interface'#10'implementation'#10'end.', ''))));
  Assert.AreEqual(0, Integer(Length(Run(mRule, 'unit Kunden;'#10'interface'#10'implementation'#10'end.',
    'Kunden.inc'))));
  Assert.AreEqual(0, Integer(Length(Run(mRule, 'program Werkzeug;'#10'begin'#10'end.', 'Projekt1.pas'))));
  Assert.AreEqual(0, Integer(Length(Run(mRule, 'package Werkzeug;'#10'end.', 'Projekt1.pas'))));
  // Halb getippter Kopf.
  Assert.AreEqual(0, Integer(Length(Run(mRule, 'unit ', 'Kunden.pas'))));
end;

procedure TUnitRulesTests.MismatchWarnDirective;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Run(TUnitNameMismatchRule.Create, '{$WARN UNIT_NAME_MISMATCH OFF}'#10'unit Alt;'#10'interface'#10 +
    'implementation'#10'end.', 'Neu.pas');
  Assert.AreEqual(0, Integer(Length(mFound)));
  mFound := Run(TUnitNameMismatchRule.Create, '{$WARNINGS OFF}'#10'unit Alt;'#10'interface'#10'implementation'#10 +
    'end.', 'Neu.pas');
  Assert.AreEqual(0, Integer(Length(mFound)));
  // Wieder eingeschaltet bzw. erst hinter dem Namen ausgeschaltet.
  mFound := Run(TUnitNameMismatchRule.Create, '{$WARN UNIT_NAME_MISMATCH OFF}{$WARN UNIT_NAME_MISMATCH ERROR}'#10 +
    'unit Alt;'#10'interface'#10'implementation'#10'end.', 'Neu.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  mFound := Run(TUnitNameMismatchRule.Create, 'unit Alt;'#10'{$WARN UNIT_NAME_MISMATCH OFF}'#10'interface'#10 +
    'implementation'#10'end.', 'Neu.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  // Kein gültiger Bezeichner als Dateiname: Meldung ohne Korrektur.
  mFound := Run(TUnitNameMismatchRule.Create, 'unit Alt;'#10'interface'#10'implementation'#10'end.', 'Kopie von Alt.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TUnitRulesTests.MismatchUsesInFile;
const
  cProjekt = 'program Projekt;'#10'uses'#10'  Kunden.Model in ''Quellen\Kunden.Daten.pas'','#10 +
    '  Haupt in ''Haupt.pas'';'#10'begin'#10'end.';
var
  mFound: TArray<TRuleFinding>;
  mFiles: TArray<string>;
begin
  mFiles := ['Quellen\Kunden.Daten.pas', 'unit Kunden.Daten;'#10'interface'#10'implementation'#10'end.',
    'Haupt.pas', 'unit Haupt;'#10'interface'#10'implementation'#10'end.'];
  mFound := Run(TUnitNameMismatchRule.Create, cProjekt, 'Projekt.dpr', mFiles, '');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Kunden.Model in ''Quellen\Kunden.Daten.pas'': die Datei deklariert die Unit Kunden.Daten ' +
    '(wie E2085).', mFound[0].Message);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('In Kunden.Daten ändern', mFound[0].Fixes[0].Title);
  Assert.AreEqual('program Projekt;'#10'uses'#10'  Kunden.Daten in ''Quellen\Kunden.Daten.pas'','#10 +
    '  Haupt in ''Haupt.pas'';'#10'begin'#10'end.', ApplyEdit(cProjekt, mFound[0].Fixes[0].Edits[0]));
  // Passt der Name der Unit auch nicht zu ihrer Datei, meldet Delphi 13 nur E1038 in der Unit (Fall CmE2085,
  // #1382).
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, cProjekt, 'Projekt.dpr',
    ['Quellen\Kunden.Daten.pas', 'unit Kunden.Anders;'#10'interface'#10'implementation'#10'end.', 'Haupt.pas',
    'unit Haupt;'#10'interface'#10'implementation'#10'end.'], ''))));
  // Datei nicht lesbar, kein unit-Kopf oder Eintrag in einem {$IF…}-Zweig: still.
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, cProjekt, 'Projekt.dpr', nil, ''))));
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, cProjekt, 'Projekt.dpr',
    ['Quellen\Kunden.Daten.pas', 'program X;'#10'begin'#10'end.'], ''))));
  Assert.AreEqual(0, Integer(Length(Run(TUnitNameMismatchRule.Create, 'program Projekt;'#10'uses'#10 +
    '{$IFDEF DEBUG}'#10'  Kunden.Model in ''Quellen\Kunden.Daten.pas'','#10'{$ENDIF}'#10'  Haupt in ''Haupt.pas'';'#10 +
    'begin'#10'end.', 'Projekt.dpr', mFiles, ''))));
end;

procedure TUnitRulesTests.MismatchOptions;
const
  cSource = 'unit Alt;'#10'interface'#10'implementation'#10'end.';
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, cSource, '',
    'Source/Neu.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, cSource,
    '{"rules": {"unit-name-mismatch": "off"}}', 'Source/Neu.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, cSource,
    '{"rules": {"group:compiler": "off"}}', 'Source/Neu.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, cSource,
    '{"rules": {"unit-name-mismatch": {"exclude": ["Source/*.pas"]}}}', 'Source/Neu.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create, cSource,
    '{"rules": {"unit-name-mismatch": {"exclude": ["Alt/*.pas"]}}}', 'Source/Neu.pas'))));
end;

procedure TUnitRulesTests.ModuleHeaderRead;
var
  mHeader: TModuleHeader;
begin
  mHeader := TModuleHeader.Read(TPascalLexer.Tokenize('{ Kopf } unit Kunden.{x}Daten platform;'));
  Assert.AreEqual<TModuleKind>(TModuleKind.UnitModule, mHeader.Kind);
  Assert.AreEqual('Kunden.Daten', mHeader.Name);
  mHeader := TModuleHeader.Read(TPascalLexer.Tokenize('package Atlas.Common;'));
  Assert.AreEqual<TModuleKind>(TModuleKind.PackageModule, mHeader.Kind);
  Assert.AreEqual('Atlas.Common', mHeader.Name);
  mHeader := TModuleHeader.Read(TPascalLexer.Tokenize('library Werkzeug;'));
  Assert.AreEqual<TModuleKind>(TModuleKind.LibraryModule, mHeader.Kind);
  mHeader := TModuleHeader.Read(TPascalLexer.Tokenize('begin end.'));
  Assert.AreEqual<TModuleKind>(TModuleKind.None, mHeader.Kind);
  Assert.AreEqual('', mHeader.Name);
  Assert.AreEqual('Neu', TUnitNameMismatchRule.ExpectedName('C:\Projekt\Quellen\Neu.pas'));
  Assert.AreEqual('Kunden.Daten', TUnitNameMismatchRule.ExpectedName('Quellen/Kunden.Daten.PAS'));
  Assert.AreEqual('', TUnitNameMismatchRule.ExpectedName('Projekt.dpr'));
end;

procedure TUnitRulesTests.TextAfterIssueExample;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Kunde(#10#10'procedure TKunde.Speichern;'#10'begin'#10);
  mFound := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Code nach end. wird nicht übersetzt (wie W1011).', mFound[0].Message);
  Assert.AreEqual(8, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(0, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(9, mFound[0].Range.EndPos.Line);
  Assert.AreEqual('Text nach end. entfernen', mFound[0].Fixes[0].Title);
  mFixed := ApplyAny(mSource, mFound[0].Fixes[0].Edits[0]);
  Assert.AreEqual(Kunde(#10), mFixed);
  TRuleAssert.Silent(TTextAfterFinalEndRule.Create, mFixed);
  // Programm: end gehört zum Block.
  mFound := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, 'program P;'#10'begin'#10'end.'#10'Rest;');
  Assert.AreEqual(1, Integer(Length(mFound)));
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
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Kunde(#10'// Ende'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource, '', 'Kunde.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource,
    '{"rules": {"text-after-final-end": {"allowComments": true}}}', 'Kunde.pas'))));
  mFound := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource,
    '{"rules": {"text-after-final-end": {"allowComments": false}}}', 'Kunde.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Kommentar nach end. wird nicht übersetzt (wie W1011).', mFound[0].Message);
  Assert.AreEqual(Kunde(#10), ApplyAny(mSource, mFound[0].Fixes[0].Edits[0]));
  // Mit Kommentar vor dem Code beginnt die Meldung beim Code bzw. mit allowComments = false beim Kommentar.
  mSource := Kunde(#10'// Rest'#10'X;'#10);
  mFound := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource, '', 'Kunde.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(8, mFound[0].Range.StartPos.Line);
  mFound := TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource,
    '{"rules": {"text-after-final-end": {"allowComments": false}}}', 'Kunde.pas');
  Assert.AreEqual(7, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('Code nach end. wird nicht übersetzt (wie W1011).', mFound[0].Message);
end;

procedure TUnitRulesTests.TextAfterOptions;
var
  mSource: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Der Parser prüft den Typ von allowComments.
  TConfigurationParser.Parse('{"rules": {"text-after-final-end": {"allowComments": "ja"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"allowComments" muss true oder false sein', mIssues[0].Message);
  mSource := Kunde(#10'Rest;');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource, '',
    'Source/Kunde.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource,
    '{"rules": {"text-after-final-end": "off"}}', 'Source/Kunde.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource,
    '{"rules": {"group:compiler": "off"}}', 'Source/Kunde.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTextAfterFinalEndRule.Create, mSource,
    '{"rules": {"text-after-final-end": {"exclude": ["Source/*.pas"]}}}', 'Source/Kunde.pas'))));
end;

procedure TUnitRulesTests.ExportsIssueExample;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Werkzeug('', '  Initialisieren name ''Start'','#10'  Berechnen,'#10'  Berechnen name ''Start''');
  mFound := ExportFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Der Name ''Start'' wird zweimal exportiert (wie E2287).', mFound[0].Message);
  Assert.AreEqual(10, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Character);
  Assert.AreEqual('Doppelten Eintrag entfernen', mFound[0].Fixes[0].Title);
  mFixed := ApplyAny(mSource, mFound[0].Fixes[0].Edits[0]);
  Assert.AreEqual(Werkzeug('', '  Initialisieren name ''Start'','#10'  Berechnen'), mFixed);
  Assert.AreEqual(0, Integer(Length(ExportFindings(mFixed))));
end;

procedure TUnitRulesTests.ExportsDuplicateVariants;
var
  mFound: TArray<TRuleFinding>;
  mSource: string;
begin
  // Gleicher Exportname über name '…', auch in zwei Klauseln.
  mFound := ExportFindings(Werkzeug('exports Initialisieren name ''Start'';'#10, '  Berechnen name ''Start'''));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Der Name ''Start'' wird zweimal exportiert (wie E2287).', mFound[0].Message);
  // Einziger Eintrag seiner Klausel: Die Korrektur entfernt die Klausel.
  mSource := Werkzeug('exports Berechnen name ''B'';'#10, '  Initialisieren name ''B''');
  mFound := ExportFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(StringReplace(mSource, 'exports'#10'  Initialisieren name ''B'';', '', []),
    ApplyAny(mSource, mFound[0].Fixes[0].Edits[0]));
  // Doppelter erster Eintrag einer späteren Klausel: entfernt bis zum nächsten Eintrag.
  mSource := Werkzeug('exports Berechnen name ''B'';'#10, 'Initialisieren name ''B'', Initialisieren');
  mFound := ExportFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(Werkzeug('exports Berechnen name ''B'';'#10, 'Initialisieren'),
    ApplyAny(mSource, mFound[0].Fixes[0].Edits[0]));
  // Bei Exportnamen zählt die Groß-/Kleinschreibung.
  Assert.AreEqual(0, Integer(Length(ExportFindings(Werkzeug('', 'Berechnen name ''A'', Initialisieren name ''a''')))));
  // Denselben Eintrag zweimal ohne name übersetzt Delphi 13 (#1383, CmE2287).
  Assert.AreEqual(0, Integer(Length(ExportFindings(Werkzeug('', 'Berechnen, berechnen, Berechnen')))));
end;

procedure TUnitRulesTests.ExportsNotExportable;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := ExportFindings(Werkzeug('threadvar'#10'  Zaehler: Integer;'#10, 'Zaehler'));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Die threadvar Zaehler kann nicht exportiert werden (wie E2276).', mFound[0].Message);
  mFound := ExportFindings(Werkzeug('procedure Intern; local;'#10'begin'#10'end;'#10, 'Intern'));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Intern ist mit local deklariert und kann nicht exportiert werden (wie E2276).', mFound[0].Message);
  mFound := ExportFindings(Werkzeug('var'#10'  Zaehler: Integer;'#10'const'#10'  Version = 3;'#10'type'#10 +
    '  TRueckruf = procedure;'#10, 'Zaehler, Version, TRueckruf'));
  // Variablen exportiert dcc (#1383, CmE2121c); für Konstanten und Typen meldet Delphi 13 E2276 (Cm.E2121b).
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Version ist keine Prozedur oder Funktion und kann nicht exportiert werden (wie E2276).',
    mFound[0].Message);
  Assert.AreEqual('TRueckruf ist keine Prozedur oder Funktion und kann nicht exportiert werden (wie E2276).',
    mFound[1].Message);
  // Variable eines Prozedurtyps bleibt eine Variable.
  Assert.AreEqual(0, Integer(Length(ExportFindings(Werkzeug('var'#10'  Rueckruf: procedure;'#10, 'Rueckruf')))));
end;

procedure TUnitRulesTests.ExportsLocalScope;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := ExportFindings('library Werkzeug;'#10'procedure Starten;'#10'exports Starten;'#10'begin'#10'end;'#10 +
    'begin'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('exports ist nur auf globaler Ebene erlaubt (wie E2191).', mFound[0].Message);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(0, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(7, mFound[0].Range.EndPos.Character);
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
  mTokens: TArray<TPascalToken>;
  mEntries: TArray<TExportEntry>;
begin
  mTokens := TPascalLexer.Tokenize('exports A.B(X: Integer) name ''Ab'' index 3, C resident, D name P + ''x'';');
  mEntries := TExportsInvalidRule.Entries(mTokens, 0, High(mTokens));
  Assert.AreEqual(3, Integer(Length(mEntries)));
  Assert.AreEqual('A.B', mEntries[0].Name);
  Assert.AreEqual('(X:INTEGER)', mEntries[0].Parameters);
  Assert.AreEqual('Ab', mEntries[0].ExportName);
  Assert.IsTrue(mEntries[0].HasNameClause);
  Assert.AreEqual('C', mEntries[1].Name);
  Assert.IsFalse(mEntries[1].HasNameClause);
  Assert.AreEqual('D', mEntries[2].Name);
  Assert.IsTrue(mEntries[2].HasNameClause);
  Assert.AreEqual('', mEntries[2].ExportName);
end;

procedure TUnitRulesTests.ExportsOptions;
var
  mSource: string;
begin
  mSource := Werkzeug('', 'Berechnen name ''B'', Initialisieren name ''B''');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TExportsInvalidRule.Create, mSource, '', 'Werkzeug.dpr'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExportsInvalidRule.Create, mSource,
    '{"rules": {"exports-invalid": "off"}}', 'Werkzeug.dpr'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExportsInvalidRule.Create, mSource,
    '{"rules": {"group:compiler": "off"}}', 'Werkzeug.dpr'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExportsInvalidRule.Create, mSource,
    '{"rules": {"exports-invalid": {"exclude": ["Werkzeug.dpr"]}}}', 'Werkzeug.dpr'))));
end;

procedure TUnitRulesTests.ConflictReservedName;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Run(TUnitNameConflictRule.Create, 'unit System;'#10'interface'#10'implementation'#10'end.', 'System.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Der Unit-Name System ist für den Compiler reserviert (wie E2272).', mFound[0].Message);
  Assert.AreEqual(0, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(5, mFound[0].Range.StartPos.Character);
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
  cSource = 'unit Haupt;'#10'{$NOINCLUDE Kunden.Datn}'#10'{$NOINCLUDE Kunden.Daten}'#10'interface'#10 +
    'implementation'#10'end.';
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.UnitFindings(TUnitNameConflictRule.Create, cSource, 'C:\P\Haupt.pas',
    TFakeUnits.Create(['Kunden.Daten', 'System'], False), '', '');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('{$NOINCLUDE Kunden.Datn}: Kunden.Datn ist keine bekannte Unit (wie E2242).', mFound[0].Message);
  Assert.AreEqual(1, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(12, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(23, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('Kunden.Daten verwenden', mFound[0].Fixes[0].Title);
  // Ohne Unit-Suche bzw. ohne sichere Aussage: still.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.UnitFindings(TUnitNameConflictRule.Create, cSource, 'C:\P\Haupt.pas',
    nil, '', ''))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.UnitFindings(TUnitNameConflictRule.Create, cSource, 'C:\P\Haupt.pas',
    TFakeUnits.Create(['Kunden.Daten'], True), '', ''))));
end;

procedure TUnitRulesTests.ConflictOptions;
const
  cSource = 'unit System;'#10'interface'#10'implementation'#10'end.';
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUnitNameConflictRule.Create, cSource, '', 'Src/System.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameConflictRule.Create, cSource,
    '{"rules": {"unit-name-conflict": "off"}}', 'Src/System.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameConflictRule.Create, cSource,
    '{"rules": {"group:compiler": "off"}}', 'Src/System.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameConflictRule.Create, cSource,
    '{"rules": {"unit-name-conflict": {"exclude": ["Src/*.pas"]}}}', 'Src/System.pas'))));
end;

procedure TUnitRulesTests.VariantsIssueExample;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Speicher('System.SysUtils', 'var Wert: Variant;'#10);
  mFound := VariantFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Variant wird ohne System.Variants in uses verwendet (wie W1040).', mFound[0].Message);
  Assert.AreEqual(4, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFound[0].Range.StartPos.Character);
  Assert.AreEqual('System.Variants in uses aufnehmen', mFound[0].Fixes[0].Title);
  mFixed := ApplyAny(mSource, mFound[0].Fixes[0].Edits[0]);
  Assert.AreEqual(Speicher('System.SysUtils,'#10'  System.Variants', 'var Wert: Variant;'#10), mFixed);
  Assert.AreEqual(0, Integer(Length(VariantFindings(mFixed))));
  // OleVariant als Parameter im interface, Typargument.
  mFound := VariantFindings('unit Speicher;'#10'interface'#10'procedure Setzen(const AWert: OleVariant);'#10 +
    'implementation'#10'procedure Setzen(const AWert: OleVariant);'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('OleVariant wird ohne System.Variants in uses verwendet (wie W1040).', mFound[0].Message);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Line);
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
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  // Ohne Namespace wie die übrigen Einträge.
  mSource := Speicher('SysUtils, Classes', 'var Wert: Variant;'#10);
  mFound := VariantFindings(mSource);
  Assert.AreEqual('Variants in uses aufnehmen', mFound[0].Fixes[0].Title);
  Assert.AreEqual(Speicher('SysUtils, Classes,'#10'  Variants', 'var Wert: Variant;'#10),
    ApplyAny(mSource, mFound[0].Fixes[0].Edits[0]));
  // Ohne uses im Abschnitt: neues uses hinter implementation.
  mSource := 'unit Speicher;'#10'interface'#10'implementation'#10'var Wert: Variant;'#10'end.';
  mFound := VariantFindings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.Contains(ApplyAny(mSource, mFound[0].Fixes[0].Edits[0]), 'uses');
  Assert.Contains(ApplyAny(mSource, mFound[0].Fixes[0].Edits[0]), 'System.Variants;');
end;

procedure TUnitRulesTests.VariantsOptions;
var
  mSource: string;
begin
  mSource := Speicher('System.SysUtils', 'var Wert: Variant;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, mSource, cVariantsOn,
    'Src/Speicher.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, mSource,
    '{"rules": {"implicit-variants-unit": "off"}}', 'Src/Speicher.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, mSource,
    '{"rules": {"implicit-variants-unit": "hint", "group:compiler": "off"}}', 'Src/Speicher.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TImplicitVariantsUnitRule.Create, mSource,
    '{"rules": {"implicit-variants-unit": {"severity": "hint", "exclude": ["Src/*.pas"]}}}', 'Src/Speicher.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitRulesTests);

end.
