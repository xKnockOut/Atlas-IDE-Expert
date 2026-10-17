unit Atlas.Common.Rules.Builtin.DfmProperties.Tests;

// Tests für die Eigenschaftsregeln für Formulardateien (#309), Regel dfm-property:
// Bedingungen, Vererbung, Default-Werte (auch verschachtelt), Schnellkorrektur in
// der Formulardatei, fix-Modi mit source.fixAll und Meldungen für atlas.json.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDfmPropertyRulesTests = class
  public
    /// <summary>Ein Lauf vorab; einmalig angelegte Daten zählen sonst als Leck des ersten Tests.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure DefaultValueCountsWhenNotStored;
    [Test]
    procedure StoredValueIsSilent;
    [Test]
    procedure DescendantsOnlyWhenIncluded;
    [Test]
    procedure ContainsOnSetUsesDefault;
    [Test]
    procedure FormItselfWithOwnMessage;
    [Test]
    procedure InheritedObjectOnlyWhereSet;
    [Test]
    procedure ExcludeAndSeverity;
    [Test]
    procedure WithoutRulesIsSilent;
    [Test]
    procedure Conditions;
    /// <summary>Muster für default einmal je Prüfung kompiliert (Review P-11); Verhalten unverändert.</summary>
    [Test]
    procedure DeclaredDefaultReadsValue;
    [Test]
    procedure DefaultFromDeclarationWithIndexedProperty;
    [Test]
    procedure QuickFixReplacesStoredValue;
    [Test]
    procedure QuickFixInsertsMissingProperty;
    [Test]
    procedure ContainsAddsExactlyTheMissingElement;
    [Test]
    procedure StringValuesAreQuoted;
    [Test]
    procedure FixModesAndFixAll;
    [Test]
    procedure NoFixWithoutTargetValue;
    [Test]
    procedure InheritedFixWhereSet;
    [Test]
    procedure NestedPathDefaults;
    [Test]
    procedure UnknownClassOrPropertyInConfiguration;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.DfmProperties;

const
  VclFile = 'C:\V\Vcl.StdCtrls.pas';
  FormFile = 'C:\P\Haupt.dfm';

  UnitVcl =
    'unit Vcl.StdCtrls;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFont = class'#10 +
    '  published'#10 +
    '    property Name: TFontName read GetName write SetName stored IsNameStored;'#10 +
    '  end;'#10 +
    '  TSizeConstraints = class'#10 +
    '  published'#10 +
    '    property MinWidth: Integer read FMinWidth write SetMinWidth default 0;'#10 +
    '  end;'#10 +
    '  TControl = class'#10 +
    '  published'#10 +
    '    property Visible: Boolean read FVisible write FVisible default True;'#10 +
    '    property Font: TFont read FFont write SetFont stored IsFontStored;'#10 +
    '    property Constraints: TSizeConstraints read FConstraints write SetConstraints;'#10 +
    '  end;'#10 +
    '  TCustomLabel = class(TControl)'#10 +
    '  public'#10 +
    '    property Transparent: Boolean read FTransparent write SetTransparent;'#10 +
    '  end;'#10 +
    '  TLabel = class(TCustomLabel)'#10 +
    '  published'#10 +
    '    property Transparent;'#10 +
    '    property Caption: string read FCaption write FCaption;'#10 +
    '  end;'#10 +
    '  TMyLabel = class(TLabel)'#10 +
    '  end;'#10 +
    '  TDBGrid = class(TControl)'#10 +
    '  published'#10 +
    '    property Options: TDBGridOptions read FOptions write SetOptions default [dgEditing, dgTitles];'#10 +
    '  end;'#10 +
    '  TForm = class(TControl)'#10 +
    '  published'#10 +
    '    property Position: TPosition read FPosition write SetPosition default poDefaultPosOnly;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  FormUnit =
    'unit Haupt;'#10 +                 // 0
    'interface'#10 +                   // 1
    'type'#10 +                        // 2
    '  TForm1 = class(TForm)'#10 +     // 3
    '    Label1: TLabel;'#10 +         // 4
    '    Grid1: TDBGrid;'#10 +         // 5
    '    MyLabel1: TMyLabel;'#10 +     // 6
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  TransparentRule = '{"dfmPropertyRules": [{"class": "TLabel", "property": "Transparent", "value": "True"%s}]}';

function Run(const AConfig, AFormText: string; const ARelativePath: string = ''): TArray<TRuleFinding>;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Index: ISymbolIndex;
begin
  Settings := TConfigurationParser.Parse(AConfig, Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'Konfiguration');
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitVcl, VclFile, nil));
  Tree := TSyntaxTreeCache.Parse(FormUnit);
  try
    Context := Default(TRuleContext);
    Context.RelativePath := ARelativePath;
    Context.Text := FormUnit;
    Context.Tree := Tree;
    Context.FormText := AFormText;
    Context.Index := Index;
    Context.ReadFile :=
      function(const AFileName: string; out AData: TBytes): Boolean
      begin
        Result := SameText(AFileName, VclFile);
        if Result then
          AData := TEncoding.UTF8.GetBytes(UnitVcl);
      end;
    Result := TRuleEngine.Run([TDfmPropertyCheckRule.Create], Settings, Context);
  finally
    Tree.Free;
  end;
end;

function Form(const AObjects: string; const AFormProps: string = ''): string;
begin
  Result := 'object Form1: TForm1'#10 + AFormProps + AObjects + 'end';
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function ApplyEdits(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in AEdits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function RunWithFile(const AConfig, AFormText: string): TArray<TRuleFinding>;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Index: ISymbolIndex;
begin
  Settings := TConfigurationParser.Parse(AConfig, Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'Konfiguration');
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitVcl, VclFile, nil));
  Tree := TSyntaxTreeCache.Parse(FormUnit);
  try
    Context := Default(TRuleContext);
    Context.Text := FormUnit;
    Context.Tree := Tree;
    Context.FormText := AFormText;
    Context.FormFile := FormFile;
    Context.Index := Index;
    Context.ReadFile :=
      function(const AFileName: string; out AData: TBytes): Boolean
      begin
        Result := SameText(AFileName, VclFile);
        if Result then
          AData := TEncoding.UTF8.GetBytes(UnitVcl);
      end;
    Result := TRuleEngine.Run([TDfmPropertyCheckRule.Create], Settings, Context);
  finally
    Tree.Free;
  end;
end;

/// <summary>Formulartext nach der einzigen Korrektur des einzigen Treffers.</summary>
function Fixed(const AConfig, AFormText: string; out AFix: TRuleFix): string;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := RunWithFile(AConfig, AFormText);
  Assert.AreEqual(1, Integer(Length(Findings)), 'ein Treffer');
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)), 'eine Korrektur');
  AFix := Findings[0].Fixes[0];
  Assert.AreEqual(FormFile, AFix.FileName, 'Korrektur in der Formulardatei');
  Result := ApplyEdits(AFormText, AFix.Edits);
end;

procedure TDfmPropertyRulesTests.QuickFixReplacesStoredValue;
var
  Fix: TRuleFix;
begin
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Transparent = True'#10'  end'#10),
    Fixed(Format(TransparentRule, ['']), Form('  object Label1: TLabel'#10'    Transparent = False'#10'  end'#10), Fix));
  Assert.IsFalse(Fix.Safe, 'Vorgabe prompt: nur als Code-Aktion');
end;

procedure TDfmPropertyRulesTests.QuickFixInsertsMissingProperty;
var
  Fix: TRuleFix;
begin
  // Hinter der letzten Property, vor dem Kindobjekt, eingerückt wie die übrigen.
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Caption = ''Name'''#10'    Transparent = True'#10 +
    '    object Inner: TLabel'#10'      Transparent = True'#10'    end'#10'  end'#10),
    Fixed(Format(TransparentRule, ['']), Form('  object Label1: TLabel'#10'    Caption = ''Name'''#10 +
    '    object Inner: TLabel'#10'      Transparent = True'#10'    end'#10'  end'#10), Fix));
  // Ohne Properties direkt hinter der Kopfzeile, mit den Zeilenenden der Datei.
  Assert.AreEqual('object Form1: TForm1'#13#10'  object Label1: TLabel'#13#10'    Transparent = True'#13#10 +
    '  end'#13#10'end', Fixed(Format(TransparentRule, ['']),
    'object Form1: TForm1'#13#10'  object Label1: TLabel'#13#10'  end'#13#10'end', Fix));
end;

procedure TDfmPropertyRulesTests.ContainsAddsExactlyTheMissingElement;
const
  Rule = '{"dfmPropertyRules": [{"class": "TDBGrid", "property": "Options", "condition": "%s", ' +
    '"value": "%s"}]}';
var
  Fix: TRuleFix;
begin
  // Nicht gespeichert: vom Default [dgEditing, dgTitles] aus.
  Assert.AreEqual(Form('  object Grid1: TDBGrid'#10'    Options = [dgEditing, dgTitles, dgRowSelect]'#10'  end'#10),
    Fixed(Format(Rule, ['contains', 'dgRowSelect']), Form('  object Grid1: TDBGrid'#10'  end'#10), Fix));
  Assert.AreEqual(Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles, dgRowSelect]'#10'  end'#10),
    Fixed(Format(Rule, ['contains', 'dgRowSelect']), Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles]'#10 +
    '  end'#10), Fix));
  Assert.AreEqual(Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles]'#10'  end'#10),
    Fixed(Format(Rule, ['notContains', 'dgEditing']), Form('  object Grid1: TDBGrid'#10 +
    '    Options = [dgEditing, dgTitles]'#10'  end'#10), Fix));
  Assert.AreEqual(Form('  object Grid1: TDBGrid'#10'    Options = []'#10'  end'#10),
    Fixed(Format(Rule, ['empty', '']), Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles]'#10'  end'#10), Fix));
end;

procedure TDfmPropertyRulesTests.StringValuesAreQuoted;
const
  Rule = '{"dfmPropertyRules": [{"class": "TLabel", "property": "Caption", "value": "Hallo Welt"}]}';
var
  Fix: TRuleFix;
begin
  // Caption ist ein String: in Hochkommas, Zeichen außerhalb ASCII als #Code.
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Caption = ''Hallo Welt'''#10'  end'#10),
    Fixed(Rule, Form('  object Label1: TLabel'#10'  end'#10), Fix));
  Assert.AreEqual('''Gr''#252#223''e''', TDfmPropertyCheckRule.DfmString('Gr' + Char(252) + Char(223) + 'e'));
  Assert.AreEqual('''It''''s''', TDfmPropertyCheckRule.DfmString('It''s'));
  Assert.AreEqual('''''', TDfmPropertyCheckRule.DfmString(''));
end;

procedure TDfmPropertyRulesTests.FixModesAndFixAll;
var
  Findings: TArray<TRuleFinding>;
  Action: TCodeAction;
  Label1: string;
begin
  Label1 := Form('  object Label1: TLabel'#10'    Transparent = False'#10'  end'#10);
  // auto: sicher, source.fixAll übernimmt es als Edit der Formulardatei.
  Findings := RunWithFile(Format(TransparentRule, [', "fix": "auto"']), Label1);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  Assert.IsTrue(TRuleCodeActions.FixAll(Findings, Action));
  Assert.AreEqual(0, Integer(Length(Action.Edits)), 'die Unit bleibt');
  Assert.AreEqual(1, Integer(Length(Action.FileEdits)));
  Assert.AreEqual(FormFile, Action.FileEdits[0].FileName);
  Assert.AreEqual('True', Action.FileEdits[0].Edits[0].NewText);
  // prompt: als Code-Aktion, aber nicht in fixAll.
  Findings := RunWithFile(Format(TransparentRule, ['']), Label1);
  Assert.IsFalse(TRuleCodeActions.FixAll(Findings, Action));
  // none: keine Korrektur; ohne Formulardatei ebenso.
  Findings := RunWithFile(Format(TransparentRule, [', "fix": "none"']), Label1);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Findings := Run(Format(TransparentRule, [', "fix": "auto"']), Label1);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)), 'ohne FormFile');
end;

procedure TDfmPropertyRulesTests.NoFixWithoutTargetValue;
begin
  // <> und notEmpty nennen keinen Sollwert.
  Assert.AreEqual(0, Integer(Length(RunWithFile('{"dfmPropertyRules": [{"class": "TForm", "property": "Position", ' +
    '"condition": "<>", "value": "poDesigned"}]}', Form('', '  Position = poDesigned'#10))[0].Fixes)));
end;

procedure TDfmPropertyRulesTests.InheritedFixWhereSet;
var
  Fix: TRuleFix;
begin
  Assert.AreEqual('inherited Form1: TForm1'#10'  inherited Label1: TLabel'#10'    Transparent = True'#10'  end'#10'end',
    Fixed(Format(TransparentRule, ['']),
    'inherited Form1: TForm1'#10'  inherited Label1: TLabel'#10'    Transparent = False'#10'  end'#10'end', Fix));
end;

procedure TDfmPropertyRulesTests.NestedPathDefaults;
const
  MinWidth = '{"dfmPropertyRules": [{"class": "TLabel", "property": "Constraints.MinWidth", "value": "100"}]}';
  FontName = '{"dfmPropertyRules": [{"class": "TLabel", "property": "Font.Name", "value": "Segoe UI"}]}';
var
  Findings: TArray<TRuleFinding>;
  Fix: TRuleFix;
begin
  // Constraints: TSizeConstraints.MinWidth default 0.
  Findings := Run(MinWidth, Form('  object Label1: TLabel'#10'  end'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Label1 (TLabel): Constraints.MinWidth soll 100 sein, ist 0', Findings[0].Message);
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Constraints.MinWidth = 100'#10'  end'#10),
    Fixed(MinWidth, Form('  object Label1: TLabel'#10'  end'#10), Fix));
  // Font hat stored IsFontStored (ParentFont): nicht gespeichert ist der Wert unbekannt.
  Assert.AreEqual(0, Integer(Length(Run(FontName, Form('  object Label1: TLabel'#10'  end'#10)))));
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Font.Name = ''Segoe UI'''#10'  end'#10),
    Fixed(FontName, Form('  object Label1: TLabel'#10'    Font.Name = ''Tahoma'''#10'  end'#10), Fix));
end;

function MessagesOf(const AIssues: TArray<TConfigurationIssue>): TArray<string>;
var
  Issue: TConfigurationIssue;
begin
  Result := nil;
  for Issue in AIssues do
    Result := Result + [Issue.Message];
end;

procedure TDfmPropertyRulesTests.UnknownClassOrPropertyInConfiguration;
const
  Config = '{"dfmPropertyRules": [' + #10 +
    '  {"class": "TLabelX", "property": "Transparent", "value": "True"},' + #10 +
    '  {"class": "TLabel", "property": "Transparentx", "value": "True"},' + #10 +
    '  {"class": "TLabel", "property": "Font.Nme", "value": "Arial"},' + #10 +
    '  {"class": "TLabel", "property": "Transparent", "value": "True"}' + #10 +
    ']}';
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Index: ISymbolIndex;
begin
  Settings := TConfigurationParser.Parse(Config, Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitVcl, VclFile, nil));
  Issues := TDfmPropertyCheckRule.ConfigurationIssues(Settings.DfmPropertyRules, Index,
    function(const AFileName: string; out AData: TBytes): Boolean
    begin
      Result := SameText(AFileName, VclFile);
      if Result then
        AData := TEncoding.UTF8.GetBytes(UnitVcl);
    end);
  Assert.AreEqual(3, Integer(Length(Issues)), string.Join(' | ', MessagesOf(Issues)));
  Assert.AreEqual('Klasse "TLabelX" ist im Index unbekannt; die Eigenschaftsregel greift nie', Issues[0].Message);
  Assert.AreEqual(1, Issues[0].Range.StartPos.Line);
  Assert.AreEqual(12, Issues[0].Range.StartPos.Character, 'am Wert von "class"');
  Assert.AreEqual('TLabel hat keine Property "Transparentx"; die Eigenschaftsregel greift nie', Issues[1].Message);
  Assert.AreEqual(2, Issues[1].Range.StartPos.Line);
  Assert.AreEqual(34, Issues[1].Range.StartPos.Character, 'am Wert von "property"');
  Assert.AreEqual('TLabel hat keine Property "Nme"; die Eigenschaftsregel greift nie', Issues[2].Message);
  Assert.IsFalse(Issues[0].IsError, 'Warnung');
  Assert.AreEqual(0, Integer(Length(TDfmPropertyCheckRule.ConfigurationIssues(Settings.DfmPropertyRules, nil, nil))),
    'ohne Index keine Aussage');
end;

{ TDfmPropertyRulesTests }

procedure TDfmPropertyRulesTests.WarmUp;
begin
  Run(Format(TransparentRule, ['']), Form('  object Label1: TLabel'#10'  end'#10));
end;

procedure TDfmPropertyRulesTests.DefaultValueCountsWhenNotStored;
var
  Findings: TArray<TRuleFinding>;
begin
  // Transparent nicht gespeichert: default aus TCustomLabel (ohne Angabe False), also Verstoß.
  Findings := Run(Format(TransparentRule, ['']), Form('  object Label1: TLabel'#10'    Caption = ''Name'''#10'  end'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Label1 (TLabel): Transparent soll True sein, ist False', Findings[0].Message);
  // Gemeldet am Feld Label1 in der Unit.
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TDfmPropertyRulesTests.StoredValueIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Run(Format(TransparentRule, ['']),
    Form('  object Label1: TLabel'#10'    Transparent = True'#10'  end'#10)))));
end;

procedure TDfmPropertyRulesTests.DescendantsOnlyWhenIncluded;
const
  MyLabel = '  object MyLabel1: TMyLabel'#10'  end'#10;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := Run(Format(TransparentRule, ['']), Form(MyLabel));
  Assert.AreEqual(1, Integer(Length(Findings)), 'Nachfahr von TLabel');
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Run(Format(TransparentRule, [', "includeDescendants": false']), Form(MyLabel)))));
end;

procedure TDfmPropertyRulesTests.ContainsOnSetUsesDefault;
const
  Rule = '{"dfmPropertyRules": [{"class": "TDBGrid", "property": "Options", "condition": "contains", ' +
    '"value": "dgRowSelect"}]}';
var
  Findings: TArray<TRuleFinding>;
begin
  // Nicht gespeichert: default [dgEditing, dgTitles] ohne dgRowSelect.
  Findings := Run(Rule, Form('  object Grid1: TDBGrid'#10'  end'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Grid1 (TDBGrid): Options soll dgRowSelect enthalten, ist [dgEditing, dgTitles]', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Run(Rule,
    Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles, dgRowSelect]'#10'  end'#10)))));
end;

procedure TDfmPropertyRulesTests.FormItselfWithOwnMessage;
const
  Rule = '{"dfmPropertyRules": [{"class": "TForm", "property": "Position", "condition": "<>", ' +
    '"value": "poDesigned", "message": "Formulare werden zentriert geöffnet"}]}';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := Run(Rule, Form('', '  Position = poDesigned'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Form1 (TForm1): Formulare werden zentriert geöffnet', Findings[0].Message);
  // Das Formular selbst: an der Formularklasse.
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Run(Rule, Form('', '  Position = poScreenCenter'#10)))));
  // Nicht gespeichert: default poDefaultPosOnly, erfüllt.
  Assert.AreEqual(0, Integer(Length(Run(Rule, Form('')))));
end;

procedure TDfmPropertyRulesTests.InheritedObjectOnlyWhereSet;
begin
  // Aus dem Vorfahrenformular, hier nicht gesetzt: gehört zum Vorfahren.
  Assert.AreEqual(0, Integer(Length(Run(Format(TransparentRule, ['']),
    'inherited Form1: TForm1'#10'  inherited Label1: TLabel'#10'  end'#10'end'))));
  Assert.AreEqual(1, Integer(Length(Run(Format(TransparentRule, ['']),
    'inherited Form1: TForm1'#10'  inherited Label1: TLabel'#10'    Transparent = False'#10'  end'#10'end'))));
end;

procedure TDfmPropertyRulesTests.ExcludeAndSeverity;
const
  Label1 = '  object Label1: TLabel'#10'  end'#10;
var
  Findings: TArray<TRuleFinding>;
begin
  Assert.AreEqual(0, Integer(Length(Run(Format(TransparentRule, [', "exclude": ["Alt/*.dfm"]']), Form(Label1),
    'Alt/Haupt.pas'))));
  Assert.AreEqual(1, Integer(Length(Run(Format(TransparentRule, [', "exclude": ["Alt/*.dfm"]']), Form(Label1),
    'Neu/Haupt.pas'))));
  Findings := Run(Format(TransparentRule, [', "severity": "hint"']), Form(Label1));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(0, Integer(Length(Run(Format(TransparentRule, [', "severity": "off"']), Form(Label1)))));
end;

procedure TDfmPropertyRulesTests.WithoutRulesIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Run('{}', Form('  object Label1: TLabel'#10'  end'#10)))));
end;

procedure TDfmPropertyRulesTests.Conditions;
var
  Value: string;
begin
  Assert.IsTrue(TDfmPropertyCheckRule.Satisfies(TDfmCondition.Equal, 'true', 'True'));
  Assert.IsTrue(TDfmPropertyCheckRule.Satisfies(TDfmCondition.Equal, '''Segoe UI''', 'Segoe UI'));
  Assert.IsTrue(TDfmPropertyCheckRule.Satisfies(TDfmCondition.Equal, '[b, a]', '[a, b]'));
  Assert.IsTrue(TDfmPropertyCheckRule.Satisfies(TDfmCondition.NotContains, '[a, b]', 'c'));
  Assert.IsTrue(TDfmPropertyCheckRule.Satisfies(TDfmCondition.Contains, '''Hallo Welt''', 'welt'));
  Assert.IsTrue(TDfmPropertyCheckRule.Satisfies(TDfmCondition.Empty, '''''', ''));
  Assert.IsTrue(TDfmPropertyCheckRule.Satisfies(TDfmCondition.Empty, '[]', ''));
  Assert.IsTrue(TDfmPropertyCheckRule.Satisfies(TDfmCondition.NotEmpty, '''Hinweis''', ''));
  Assert.IsFalse(TDfmPropertyCheckRule.Satisfies(TDfmCondition.NotEmpty, '', ''));
  Assert.IsTrue(TDfmPropertyCheckRule.DeclaredDefault('property Tag: Integer read FTag write FTag default 7;',
    Value));
  Assert.AreEqual('7', Value);
  Assert.IsFalse(TDfmPropertyCheckRule.DeclaredDefault('property Name: string read FName;', Value));
end;

procedure TDfmPropertyRulesTests.DeclaredDefaultReadsValue;
var
  Value: string;
begin
  Assert.IsTrue(TDfmPropertyCheckRule.DeclaredDefault(
    'property Size: Integer read FSize write FSize default 5;', Value));
  Assert.AreEqual('5', Value);
  Assert.IsTrue(TDfmPropertyCheckRule.DeclaredDefault(
    'property Options: TDBGridOptions read FOptions DEFAULT [dgEditing, dgTitles] ;', Value));
  Assert.AreEqual('[dgEditing, dgTitles]', Value);
  Assert.IsFalse(TDfmPropertyCheckRule.DeclaredDefault('property Caption: string read FCaption;', Value));
  Assert.AreEqual('', Value);
end;

procedure TDfmPropertyRulesTests.DefaultFromDeclarationWithIndexedProperty;
var
  Value: string;
begin
  // "default;" nach einer Array-Property ist keine Vorgabe.
  Assert.IsFalse(TDfmPropertyCheckRule.DeclaredDefault(
    'property Items[Index: Integer]: string read GetItem write SetItem; default;', Value));
  Assert.IsTrue(TDfmPropertyCheckRule.DeclaredDefault(
    'property Flags[Index: Integer]: Integer index 1 read GetFlag default 0;', Value));
  Assert.AreEqual('0', Value);
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmPropertyRulesTests);

end.
