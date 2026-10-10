unit Argus.Common.Rules.Builtin.DfmProperties.Tests;

// Tests für die Eigenschaftsregeln für Formulardateien (#309), Regel dfm-property.

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
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Configuration.Parser,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Engine,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.TreeCache,
  Argus.Common.Index.Contract,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor,
  Argus.Common.Rules.Builtin.DfmProperties;

const
  VclFile = 'C:\V\Vcl.StdCtrls.pas';

  UnitVcl =
    'unit Vcl.StdCtrls;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TControl = class'#10 +
    '  published'#10 +
    '    property Visible: Boolean read FVisible write FVisible default True;'#10 +
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

initialization
  TDUnitX.RegisterTestFixture(TDfmPropertyRulesTests);

end.
