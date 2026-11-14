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
    /// <summary>Muster für default einmal je Prüfung kompiliert; Verhalten unverändert.</summary>
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
  cVclFile = 'C:\V\Vcl.StdCtrls.pas';
  cFormFile = 'C:\P\Haupt.dfm';

  cUnitVcl =
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

  cFormUnit =
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

  cTransparentRule = '{"dfmPropertyRules": [{"class": "TLabel", "property": "Transparent", "value": "True"%s}]}';

function Run(const AConfig, AFormText: string; const ARelativePath: string): TArray<TRuleFinding>; overload;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mIndex: ISymbolIndex;
begin
  mSettings := TConfigurationParser.Parse(AConfig, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Konfiguration');
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitVcl, cVclFile, nil));
  mTree := TSyntaxTreeCache.Parse(cFormUnit);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := ARelativePath;
    mContext.Text := cFormUnit;
    mContext.Tree := mTree;
    mContext.FormText := AFormText;
    mContext.Index := mIndex;
    mContext.ReadFile :=
      function(const AFileName: string; out AData: TBytes): Boolean
      begin
        Result := SameText(AFileName, cVclFile);
        if Result then
        begin
          AData := TEncoding.UTF8.GetBytes(cUnitVcl);
        end;
      end;
    Result := TRuleEngine.Run([TDfmPropertyCheckRule.Create], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

function Run(const AConfig, AFormText: string): TArray<TRuleFinding>; overload;
begin
  Result := Run(AConfig, AFormText, '');
end;

function Form(const AObjects: string; const AFormProps: string): string; overload;
begin
  Result := 'object Form1: TForm1'#10 + AFormProps + AObjects + 'end';
end;

function Form(const AObjects: string): string; overload;
begin
  Result := Form(AObjects, '');
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function ApplyEdits(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mOffsets: TArray<Integer>;
  mIndex, mStart, mStop: Integer;
begin
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for mEdit in AEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function RunWithFile(const AConfig, AFormText: string): TArray<TRuleFinding>;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mIndex: ISymbolIndex;
begin
  mSettings := TConfigurationParser.Parse(AConfig, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Konfiguration');
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitVcl, cVclFile, nil));
  mTree := TSyntaxTreeCache.Parse(cFormUnit);
  try
    mContext := Default(TRuleContext);
    mContext.Text := cFormUnit;
    mContext.Tree := mTree;
    mContext.FormText := AFormText;
    mContext.FormFile := cFormFile;
    mContext.Index := mIndex;
    mContext.ReadFile :=
      function(const AFileName: string; out AData: TBytes): Boolean
      begin
        Result := SameText(AFileName, cVclFile);
        if Result then
        begin
          AData := TEncoding.UTF8.GetBytes(cUnitVcl);
        end;
      end;
    Result := TRuleEngine.Run([TDfmPropertyCheckRule.Create], mSettings, mContext);
  finally
    mTree.Free;
  end;
end;

/// <summary>Formulartext nach der einzigen Korrektur des einzigen Treffers.</summary>
function Fixed(const AConfig, AFormText: string; out AFix: TRuleFix): string;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := RunWithFile(AConfig, AFormText);
  Assert.AreEqual(1, Integer(Length(mFindings)), 'ein Treffer');
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)), 'eine Korrektur');
  AFix := mFindings[0].Fixes[0];
  Assert.AreEqual(cFormFile, AFix.FileName, 'Korrektur in der Formulardatei');
  Result := ApplyEdits(AFormText, AFix.Edits);
end;

procedure TDfmPropertyRulesTests.QuickFixReplacesStoredValue;
var
  mFix: TRuleFix;
begin
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Transparent = True'#10'  end'#10),
    Fixed(Format(cTransparentRule, ['']), Form('  object Label1: TLabel'#10'    Transparent = False'#10'  end'#10), mFix));
  Assert.IsFalse(mFix.Safe, 'Vorgabe prompt: nur als Code-Aktion');
end;

procedure TDfmPropertyRulesTests.QuickFixInsertsMissingProperty;
var
  mFix: TRuleFix;
begin
  // Hinter der letzten Property, vor dem Kindobjekt, eingerückt wie die übrigen.
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Caption = ''Name'''#10'    Transparent = True'#10 +
    '    object Inner: TLabel'#10'      Transparent = True'#10'    end'#10'  end'#10),
    Fixed(Format(cTransparentRule, ['']), Form('  object Label1: TLabel'#10'    Caption = ''Name'''#10 +
    '    object Inner: TLabel'#10'      Transparent = True'#10'    end'#10'  end'#10), mFix));
  // Ohne Properties direkt hinter der Kopfzeile, mit den Zeilenenden der Datei.
  Assert.AreEqual('object Form1: TForm1'#13#10'  object Label1: TLabel'#13#10'    Transparent = True'#13#10 +
    '  end'#13#10'end', Fixed(Format(cTransparentRule, ['']),
    'object Form1: TForm1'#13#10'  object Label1: TLabel'#13#10'  end'#13#10'end', mFix));
end;

procedure TDfmPropertyRulesTests.ContainsAddsExactlyTheMissingElement;
const
  cRule = '{"dfmPropertyRules": [{"class": "TDBGrid", "property": "Options", "condition": "%s", ' +
    '"value": "%s"}]}';
var
  mFix: TRuleFix;
begin
  // Nicht gespeichert: vom Default [dgEditing, dgTitles] aus.
  Assert.AreEqual(Form('  object Grid1: TDBGrid'#10'    Options = [dgEditing, dgTitles, dgRowSelect]'#10'  end'#10),
    Fixed(Format(cRule, ['contains', 'dgRowSelect']), Form('  object Grid1: TDBGrid'#10'  end'#10), mFix));
  Assert.AreEqual(Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles, dgRowSelect]'#10'  end'#10),
    Fixed(Format(cRule, ['contains', 'dgRowSelect']), Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles]'#10 +
    '  end'#10), mFix));
  Assert.AreEqual(Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles]'#10'  end'#10),
    Fixed(Format(cRule, ['notContains', 'dgEditing']), Form('  object Grid1: TDBGrid'#10 +
    '    Options = [dgEditing, dgTitles]'#10'  end'#10), mFix));
  Assert.AreEqual(Form('  object Grid1: TDBGrid'#10'    Options = []'#10'  end'#10),
    Fixed(Format(cRule, ['empty', '']), Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles]'#10'  end'#10), mFix));
end;

procedure TDfmPropertyRulesTests.StringValuesAreQuoted;
const
  cRule = '{"dfmPropertyRules": [{"class": "TLabel", "property": "Caption", "value": "Hallo Welt"}]}';
var
  mFix: TRuleFix;
begin
  // Caption ist ein String: in Hochkommas, Zeichen außerhalb ASCII als #Code.
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Caption = ''Hallo Welt'''#10'  end'#10),
    Fixed(cRule, Form('  object Label1: TLabel'#10'  end'#10), mFix));
  Assert.AreEqual('''Gr''#252#223''e''', TDfmPropertyCheckRule.DfmString('Gr' + Char(252) + Char(223) + 'e'));
  Assert.AreEqual('''It''''s''', TDfmPropertyCheckRule.DfmString('It''s'));
  Assert.AreEqual('''''', TDfmPropertyCheckRule.DfmString(''));
end;

procedure TDfmPropertyRulesTests.FixModesAndFixAll;
var
  mFindings: TArray<TRuleFinding>;
  mAction: TCodeAction;
  mLabel1: string;
begin
  mLabel1 := Form('  object Label1: TLabel'#10'    Transparent = False'#10'  end'#10);
  // auto: sicher, source.fixAll übernimmt es als Edit der Formulardatei.
  mFindings := RunWithFile(Format(cTransparentRule, [', "fix": "auto"']), mLabel1);
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
  Assert.IsTrue(TRuleCodeActions.FixAll(mFindings, mAction));
  Assert.AreEqual(0, Integer(Length(mAction.Edits)), 'die Unit bleibt');
  Assert.AreEqual(1, Integer(Length(mAction.FileEdits)));
  Assert.AreEqual(cFormFile, mAction.FileEdits[0].FileName);
  Assert.AreEqual('True', mAction.FileEdits[0].Edits[0].NewText);
  // prompt: als Code-Aktion, aber nicht in fixAll.
  mFindings := RunWithFile(Format(cTransparentRule, ['']), mLabel1);
  Assert.IsFalse(TRuleCodeActions.FixAll(mFindings, mAction));
  // none: keine Korrektur; ohne Formulardatei ebenso.
  mFindings := RunWithFile(Format(cTransparentRule, [', "fix": "none"']), mLabel1);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  mFindings := Run(Format(cTransparentRule, [', "fix": "auto"']), mLabel1);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)), 'ohne FormFile');
end;

procedure TDfmPropertyRulesTests.NoFixWithoutTargetValue;
begin
  // <> und notEmpty nennen keinen Sollwert.
  Assert.AreEqual(0, Integer(Length(RunWithFile('{"dfmPropertyRules": [{"class": "TForm", "property": "Position", ' +
    '"condition": "<>", "value": "poDesigned"}]}', Form('', '  Position = poDesigned'#10))[0].Fixes)));
end;

procedure TDfmPropertyRulesTests.InheritedFixWhereSet;
var
  mFix: TRuleFix;
begin
  Assert.AreEqual('inherited Form1: TForm1'#10'  inherited Label1: TLabel'#10'    Transparent = True'#10'  end'#10'end',
    Fixed(Format(cTransparentRule, ['']),
    'inherited Form1: TForm1'#10'  inherited Label1: TLabel'#10'    Transparent = False'#10'  end'#10'end', mFix));
end;

procedure TDfmPropertyRulesTests.NestedPathDefaults;
const
  cMinWidth = '{"dfmPropertyRules": [{"class": "TLabel", "property": "Constraints.MinWidth", "value": "100"}]}';
  cFontName = '{"dfmPropertyRules": [{"class": "TLabel", "property": "Font.Name", "value": "Segoe UI"}]}';
var
  mFindings: TArray<TRuleFinding>;
  mFix: TRuleFix;
begin
  // Constraints: TSizeConstraints.MinWidth default 0.
  mFindings := Run(cMinWidth, Form('  object Label1: TLabel'#10'  end'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Label1 (TLabel): Constraints.MinWidth soll 100 sein, ist 0', mFindings[0].Message);
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Constraints.MinWidth = 100'#10'  end'#10),
    Fixed(cMinWidth, Form('  object Label1: TLabel'#10'  end'#10), mFix));
  // Font hat stored IsFontStored (ParentFont): nicht gespeichert ist der Wert unbekannt.
  Assert.AreEqual(0, Integer(Length(Run(cFontName, Form('  object Label1: TLabel'#10'  end'#10)))));
  Assert.AreEqual(Form('  object Label1: TLabel'#10'    Font.Name = ''Segoe UI'''#10'  end'#10),
    Fixed(cFontName, Form('  object Label1: TLabel'#10'    Font.Name = ''Tahoma'''#10'  end'#10), mFix));
end;

function MessagesOf(const AIssues: TArray<TConfigurationIssue>): TArray<string>;
var
  mIssue: TConfigurationIssue;
begin
  Result := nil;
  for mIssue in AIssues do
  begin
    Result := Result + [mIssue.Message];
  end;
end;

procedure TDfmPropertyRulesTests.UnknownClassOrPropertyInConfiguration;
const
  cConfig = '{"dfmPropertyRules": [' + #10 +
    '  {"class": "TLabelX", "property": "Transparent", "value": "True"},' + #10 +
    '  {"class": "TLabel", "property": "Transparentx", "value": "True"},' + #10 +
    '  {"class": "TLabel", "property": "Font.Nme", "value": "Arial"},' + #10 +
    '  {"class": "TLabel", "property": "Transparent", "value": "True"}' + #10 +
    ']}';
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mIndex: ISymbolIndex;
begin
  mSettings := TConfigurationParser.Parse(cConfig, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitVcl, cVclFile, nil));
  mIssues := TDfmPropertyCheckRule.ConfigurationIssues(mSettings.DfmPropertyRules, mIndex,
    function(const AFileName: string; out AData: TBytes): Boolean
    begin
      Result := SameText(AFileName, cVclFile);
      if Result then
      begin
        AData := TEncoding.UTF8.GetBytes(cUnitVcl);
      end;
    end);
  Assert.AreEqual(3, Integer(Length(mIssues)), string.Join(' | ', MessagesOf(mIssues)));
  Assert.AreEqual('Klasse "TLabelX" ist im Index unbekannt; die Eigenschaftsregel greift nie', mIssues[0].Message);
  Assert.AreEqual(1, mIssues[0].Range.StartPos.Line);
  Assert.AreEqual(12, mIssues[0].Range.StartPos.Character, 'am Wert von "class"');
  Assert.AreEqual('TLabel hat keine Property "Transparentx"; die Eigenschaftsregel greift nie', mIssues[1].Message);
  Assert.AreEqual(2, mIssues[1].Range.StartPos.Line);
  Assert.AreEqual(34, mIssues[1].Range.StartPos.Character, 'am Wert von "property"');
  Assert.AreEqual('TLabel hat keine Property "Nme"; die Eigenschaftsregel greift nie', mIssues[2].Message);
  Assert.IsFalse(mIssues[0].IsError, 'Warnung');
  Assert.AreEqual(0, Integer(Length(TDfmPropertyCheckRule.ConfigurationIssues(mSettings.DfmPropertyRules, nil, nil))),
    'ohne Index keine Aussage');
end;

{ TDfmPropertyRulesTests }

procedure TDfmPropertyRulesTests.WarmUp;
begin
  Run(Format(cTransparentRule, ['']), Form('  object Label1: TLabel'#10'  end'#10));
end;

procedure TDfmPropertyRulesTests.DefaultValueCountsWhenNotStored;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Transparent nicht gespeichert: default aus TCustomLabel (ohne Angabe False), also Verstoß.
  mFindings := Run(Format(cTransparentRule, ['']), Form('  object Label1: TLabel'#10'    Caption = ''Name'''#10'  end'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Label1 (TLabel): Transparent soll True sein, ist False', mFindings[0].Message);
  // Gemeldet am Feld Label1 in der Unit.
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
end;

procedure TDfmPropertyRulesTests.StoredValueIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Run(Format(cTransparentRule, ['']),
    Form('  object Label1: TLabel'#10'    Transparent = True'#10'  end'#10)))));
end;

procedure TDfmPropertyRulesTests.DescendantsOnlyWhenIncluded;
const
  cMyLabel = '  object MyLabel1: TMyLabel'#10'  end'#10;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := Run(Format(cTransparentRule, ['']), Form(cMyLabel));
  Assert.AreEqual(1, Integer(Length(mFindings)), 'Nachfahr von TLabel');
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Run(Format(cTransparentRule, [', "includeDescendants": false']), Form(cMyLabel)))));
end;

procedure TDfmPropertyRulesTests.ContainsOnSetUsesDefault;
const
  cRule = '{"dfmPropertyRules": [{"class": "TDBGrid", "property": "Options", "condition": "contains", ' +
    '"value": "dgRowSelect"}]}';
var
  mFindings: TArray<TRuleFinding>;
begin
  // Nicht gespeichert: default [dgEditing, dgTitles] ohne dgRowSelect.
  mFindings := Run(cRule, Form('  object Grid1: TDBGrid'#10'  end'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Grid1 (TDBGrid): Options soll dgRowSelect enthalten, ist [dgEditing, dgTitles]', mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(Run(cRule,
    Form('  object Grid1: TDBGrid'#10'    Options = [dgTitles, dgRowSelect]'#10'  end'#10)))));
end;

procedure TDfmPropertyRulesTests.FormItselfWithOwnMessage;
const
  cRule = '{"dfmPropertyRules": [{"class": "TForm", "property": "Position", "condition": "<>", ' +
    '"value": "poDesigned", "message": "Formulare werden zentriert geöffnet"}]}';
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := Run(cRule, Form('', '  Position = poDesigned'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Form1 (TForm1): Formulare werden zentriert geöffnet', mFindings[0].Message);
  // Das Formular selbst: an der Formularklasse.
  Assert.AreEqual(3, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Run(cRule, Form('', '  Position = poScreenCenter'#10)))));
  // Nicht gespeichert: default poDefaultPosOnly, erfüllt.
  Assert.AreEqual(0, Integer(Length(Run(cRule, Form('')))));
end;

procedure TDfmPropertyRulesTests.InheritedObjectOnlyWhereSet;
begin
  // Aus dem Vorfahrenformular, hier nicht gesetzt: gehört zum Vorfahren.
  Assert.AreEqual(0, Integer(Length(Run(Format(cTransparentRule, ['']),
    'inherited Form1: TForm1'#10'  inherited Label1: TLabel'#10'  end'#10'end'))));
  Assert.AreEqual(1, Integer(Length(Run(Format(cTransparentRule, ['']),
    'inherited Form1: TForm1'#10'  inherited Label1: TLabel'#10'    Transparent = False'#10'  end'#10'end'))));
end;

procedure TDfmPropertyRulesTests.ExcludeAndSeverity;
const
  cLabel1 = '  object Label1: TLabel'#10'  end'#10;
var
  mFindings: TArray<TRuleFinding>;
begin
  Assert.AreEqual(0, Integer(Length(Run(Format(cTransparentRule, [', "exclude": ["Alt/*.dfm"]']), Form(cLabel1),
    'Alt/Haupt.pas'))));
  Assert.AreEqual(1, Integer(Length(Run(Format(cTransparentRule, [', "exclude": ["Alt/*.dfm"]']), Form(cLabel1),
    'Neu/Haupt.pas'))));
  mFindings := Run(Format(cTransparentRule, [', "severity": "hint"']), Form(cLabel1));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(0, Integer(Length(Run(Format(cTransparentRule, [', "severity": "off"']), Form(cLabel1)))));
end;

procedure TDfmPropertyRulesTests.WithoutRulesIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Run('{}', Form('  object Label1: TLabel'#10'  end'#10)))));
end;

procedure TDfmPropertyRulesTests.Conditions;
var
  mValue: string;
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
    mValue));
  Assert.AreEqual('7', mValue);
  Assert.IsFalse(TDfmPropertyCheckRule.DeclaredDefault('property Name: string read FName;', mValue));
end;

procedure TDfmPropertyRulesTests.DeclaredDefaultReadsValue;
var
  mValue: string;
begin
  Assert.IsTrue(TDfmPropertyCheckRule.DeclaredDefault(
    'property Size: Integer read FSize write FSize default 5;', mValue));
  Assert.AreEqual('5', mValue);
  Assert.IsTrue(TDfmPropertyCheckRule.DeclaredDefault(
    'property Options: TDBGridOptions read FOptions DEFAULT [dgEditing, dgTitles] ;', mValue));
  Assert.AreEqual('[dgEditing, dgTitles]', mValue);
  Assert.IsFalse(TDfmPropertyCheckRule.DeclaredDefault('property Caption: string read FCaption;', mValue));
  Assert.AreEqual('', mValue);
end;

procedure TDfmPropertyRulesTests.DefaultFromDeclarationWithIndexedProperty;
var
  mValue: string;
begin
  // "default;" nach einer Array-Property ist keine Vorgabe.
  Assert.IsFalse(TDfmPropertyCheckRule.DeclaredDefault(
    'property Items[Index: Integer]: string read GetItem write SetItem; default;', mValue));
  Assert.IsTrue(TDfmPropertyCheckRule.DeclaredDefault(
    'property Flags[Index: Integer]: Integer index 1 read GetFlag default 0;', mValue));
  Assert.AreEqual('0', mValue);
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmPropertyRulesTests);

end.
