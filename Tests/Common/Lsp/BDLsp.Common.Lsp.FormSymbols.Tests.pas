unit BDLsp.Common.Lsp.FormSymbols.Tests;

// Tests für Hover und Gehe zu Definition in Formulardateien (#308).

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Index.Contract;

type
  [TestFixture]
  TFormSymbolsTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure HoverPropertyShowsDeclaringClass;
    [Test]
    procedure HoverClassName;
    [Test]
    procedure HoverEnumValue;
    [Test]
    procedure HoverNestedPropertyAndSetValue;
    [Test]
    procedure HoverCollectionItemProperty;
    [Test]
    procedure HoverEventHandlerSignature;
    [Test]
    procedure UnknownClassGivesNothing;
    [Test]
    procedure TargetsClassPropertyAndValue;
    [Test]
    procedure RedundantDefaultsFound;
    [Test]
    procedure RuleEqualUsesDefaultAndDescendants;
    [Test]
    procedure RuleContainsAddsSetElement;
    [Test]
    procedure RuleNotContainsRemovesElement;
    [Test]
    procedure RuleNotEqualAndEmptyHaveNoFix;
    [Test]
    procedure RuleExcludeSeverityAndFixMode;
    [Test]
    procedure RuleProblemsForUnknownNames;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Lsp.FormSymbols;

const
  ControlsFile = 'C:\P\Controls.pas';
  MainFile = 'C:\P\Main.pas';

  UnitControls =
    'unit Vcl.Controls;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAlign = (alNone, alTop, alClient);'#10 +
    '  TFontStyle = (fsBold, fsItalic);'#10 +
    '  TFontStyles = set of TFontStyle;'#10 +
    '  TFont = class(TPersistent)'#10 +
    '  published'#10 +
    '    property Style: TFontStyles read FStyle write FStyle;'#10 +
    '  end;'#10 +
    '  TControl = class(TComponent)'#10 +
    '  protected'#10 +
    '    property Align: TAlign read FAlign write FAlign default alNone;'#10 +
    '  published'#10 +
    '    property Font: TFont read FFont write FFont;'#10 +
    '  end;'#10 +
    '  TWinControl = class(TControl)'#10 +
    '  protected'#10 +
    '    property TabStop: Boolean read FTabStop write FTabStop default False;'#10 +
    '  end;'#10 +
    '  TListColumn = class(TCollectionItem)'#10 +
    '  published'#10 +
    '    property Width: Integer read FWidth write FWidth default 50;'#10 +
    '  end;'#10 +
    '  TListColumns = class(TCollection)'#10 +
    '  public'#10 +
    '    property Items[Index: Integer]: TListColumn read GetItem; default;'#10 +
    '  end;'#10 +
    '  TButton = class(TWinControl)'#10 +
    '  published'#10 +
    '    property Align;'#10 +
    '    property TabStop default True;'#10 +
    '    property Columns: TListColumns read FColumns write FColumns;'#10 +
    '    property OnClick: TNotifyEvent read FOnClick write FOnClick;'#10 +
    '  end;'#10 +
    '  TGridOption = (dgEditing, dgRowSelect, dgTitles);'#10 +
    '  TGridOptions = set of TGridOption;'#10 +
    '  TLabel = class(TControl)'#10 +
    '  published'#10 +
    '    property Transparent: Boolean read FTransparent write FTransparent default False;'#10 +
    '    property Caption: string read FCaption write FCaption;'#10 +
    '  end;'#10 +
    '  TMyLabel = class(TLabel)'#10 +
    '  end;'#10 +
    '  TGrid = class(TWinControl)'#10 +
    '  published'#10 +
    '    property Options: TGridOptions read FOptions write FOptions default [dgEditing, dgTitles];'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  UnitMain =
    'unit Main;'#10 +
    'interface'#10 +
    'uses Vcl.Controls;'#10 +
    'type'#10 +
    '  TMainForm = class(TForm)'#10 +
    '    btnOk: TButton;'#10 +
    '    procedure btnOkClick(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TMainForm.btnOkClick(Sender: TObject);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  FormText =
    'object MainForm: TMainForm'#10 +             // 0
    '  object btnOk: TButton'#10 +                // 1
    '    Align = alClient'#10 +                   // 2
    '    TabStop = True'#10 +                     // 3
    '    Font.Style = [fsBold]'#10 +              // 4
    '    Columns = <'#10 +                        // 5
    '      item'#10 +                             // 6
    '        Width = 50'#10 +                     // 7
    '      end>'#10 +                             // 8
    '    OnClick = btnOkClick'#10 +               // 9
    '  end'#10 +                                  // 10
    'end';                                        // 11

function ReadSource(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, ControlsFile) then
    AText := UnitControls
  else if SameText(AFileName, MainFile) then
    AText := UnitMain
  else
    Result := False;
end;

function At(ALine, ACharacter: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(ALine, ACharacter);
end;

procedure TFormSymbolsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitControls, ControlsFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
end;

procedure TFormSymbolsTests.TearDown;
begin
  FIndex := nil;
end;

function Hover(const AIndex: ISymbolIndex; ALine, ACharacter: Integer): string;
begin
  Result := TFormSymbols.Hover(FormText, 'C:\P\Main.dfm', At(ALine, ACharacter), AIndex, ReadSource);
end;

procedure TFormSymbolsTests.HoverPropertyShowsDeclaringClass;
var
  Text: string;
begin
  Text := Hover(FIndex, 2, 6);
  Assert.IsTrue(Pos('property Align: TAlign default alNone', Text) > 0, Text);
  Assert.IsTrue(Pos('Deklariert in `TControl`', Text) > 0, Text);
end;

procedure TFormSymbolsTests.HoverClassName;
var
  Text: string;
begin
  Text := Hover(FIndex, 1, 18);
  Assert.IsTrue(Pos('TButton = class(TWinControl)', Text) > 0, Text);
  Assert.IsTrue(Pos('Vcl.Controls', Text) > 0, Text);
end;

procedure TFormSymbolsTests.HoverEnumValue;
var
  Text: string;
begin
  Text := Hover(FIndex, 2, 14);
  Assert.IsTrue(Pos('alClient: TAlign', Text) > 0, Text);
  Assert.IsTrue(Pos('Werte: alNone, alTop, alClient', Text) > 0, Text);
end;

procedure TFormSymbolsTests.HoverNestedPropertyAndSetValue;
var
  Text: string;
begin
  Text := Hover(FIndex, 4, 10);
  Assert.IsTrue(Pos('property Style: TFontStyles', Text) > 0, Text);
  Text := Hover(FIndex, 4, 19);
  Assert.IsTrue(Pos('fsBold: TFontStyle', Text) > 0, Text);
end;

procedure TFormSymbolsTests.HoverCollectionItemProperty;
var
  Text: string;
begin
  Text := Hover(FIndex, 7, 9);
  Assert.IsTrue(Pos('property Width: Integer default 50', Text) > 0, Text);
  Assert.IsTrue(Pos('`TListColumn`', Text) > 0, Text);
end;

procedure TFormSymbolsTests.HoverEventHandlerSignature;
var
  Text: string;
begin
  Text := Hover(FIndex, 9, 16);
  Assert.IsTrue(Pos('procedure btnOkClick(Sender: TObject);', Text) > 0, Text);
end;

procedure TFormSymbolsTests.UnknownClassGivesNothing;
const
  Text = 'object F: TForm1'#10'  object X: TUnbekannt'#10'    Farbe = clRot'#10'  end'#10'end';
begin
  Assert.AreEqual('', TFormSymbols.Hover(Text, '', At(2, 5), FIndex, ReadSource));
  Assert.AreEqual('', TFormSymbols.Hover(Text, '', At(1, 15), FIndex, ReadSource));
  Assert.AreEqual(0, Integer(Length(TFormSymbols.Targets(Text, At(2, 5), FIndex, ReadSource))));
  Assert.AreEqual('', TFormSymbols.Hover(FormText, '', At(2, 6), nil, ReadSource));
end;

procedure TFormSymbolsTests.TargetsClassPropertyAndValue;
var
  Found: TArray<TSymbolLocation>;
begin
  Found := TFormSymbols.Targets(FormText, At(1, 18), FIndex, ReadSource);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(ControlsFile, Found[0].FileName);
  Assert.AreEqual('TButton', Found[0].Symbol.Name);
  Found := TFormSymbols.Targets(FormText, At(2, 14), FIndex, ReadSource);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('alClient', Found[0].Symbol.Name);
  Found := TFormSymbols.Targets(FormText, At(2, 6), FIndex, ReadSource);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('TControl', Found[0].Symbol.Container);
  Assert.AreEqual(12, Found[0].Symbol.Range.StartPos.Line);
end;

const
  RuleForm =
    'object F: TMainForm'#10 +                   // 0
    '  object L1: TLabel'#10 +                   // 1
    '  end'#10 +                                 // 2
    '  object L2: TLabel'#10 +                   // 3
    '    Transparent = True'#10 +                // 4
    '  end'#10 +                                 // 5
    '  object L3: TMyLabel'#10 +                 // 6
    '  end'#10 +                                 // 7
    '  object G: TGrid'#10 +                     // 8
    '    Options = [dgEditing]'#10 +             // 9
    '  end'#10 +                                 // 10
    '  object G2: TGrid'#10 +                    // 11
    '  end'#10 +                                 // 12
    'end';                                       // 13

function Rule(const AClass, AProperty: string; ACondition: TDfmCondition; const AValue: string): TDfmPropertyRule;
begin
  Result := Default(TDfmPropertyRule);
  Result.ClassName := AClass;
  Result.PropertyPath := AProperty;
  Result.Condition := ACondition;
  Result.Value := AValue;
  Result.Severity := TRuleSeverity.Warning;
  Result.IncludeDescendants := True;
  Result.Fix := TDfmFixMode.Prompt;
end;

procedure TFormSymbolsTests.RuleEqualUsesDefaultAndDescendants;
var
  Rules: TArray<TDfmPropertyRule>;
  Found: TArray<TFormPropertyViolation>;
begin
  Rules := [Rule('TLabel', 'Transparent', TDfmCondition.Equal, 'True')];
  Found := TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm', Rules, FIndex, ReadSource);
  // L1 ohne gespeicherten Wert (default False) und der Nachfahr L3; L2 hat True.
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(1, Found[0].Range.StartPos.Line);
  Assert.AreEqual(6, Found[1].Range.StartPos.Line);
  Assert.AreEqual('TLabel.Transparent = True (ist: False)', Found[0].Message);
  Assert.IsTrue(Found[0].HasFix);
  Assert.IsFalse(Found[0].Safe);
  Assert.AreEqual(#10'    Transparent = True', Found[0].Fix.NewText);
  Assert.AreEqual(1, Found[0].Fix.Range.StartPos.Line);
  Assert.AreEqual(Length('  object L1: TLabel'), Found[0].Fix.Range.StartPos.Character);
  Rules[0].IncludeDescendants := False;
  Found := TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm', Rules, FIndex, ReadSource);
  Assert.AreEqual(1, Integer(Length(Found)));
end;

procedure TFormSymbolsTests.RuleContainsAddsSetElement;
var
  Found: TArray<TFormPropertyViolation>;
begin
  Found := TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm',
    [Rule('TGrid', 'Options', TDfmCondition.Contains, 'dgRowSelect')], FIndex, ReadSource);
  Assert.AreEqual(2, Integer(Length(Found)));
  // Gespeichert: Element ergänzen.
  Assert.AreEqual(9, Found[0].Range.StartPos.Line);
  Assert.AreEqual('[dgEditing, dgRowSelect]', Found[0].Fix.NewText);
  Assert.AreEqual(9, Found[0].Fix.Range.StartPos.Line);
  // Nicht gespeichert: default plus Element als neue Zeile.
  Assert.AreEqual(#10'    Options = [dgEditing, dgTitles, dgRowSelect]', Found[1].Fix.NewText);
end;

procedure TFormSymbolsTests.RuleNotContainsRemovesElement;
var
  Found: TArray<TFormPropertyViolation>;
begin
  Found := TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm',
    [Rule('TGrid', 'Options', TDfmCondition.NotContains, 'dgEditing')], FIndex, ReadSource);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('[]', Found[0].Fix.NewText);
  Assert.AreEqual(#10'    Options = [dgTitles]', Found[1].Fix.NewText);
end;

procedure TFormSymbolsTests.RuleNotEqualAndEmptyHaveNoFix;
var
  Found: TArray<TFormPropertyViolation>;
begin
  Found := TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm',
    [Rule('TLabel', 'Transparent', TDfmCondition.NotEqual, 'True')], FIndex, ReadSource);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(4, Found[0].Range.StartPos.Line);
  Assert.IsFalse(Found[0].HasFix);
  Found := TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm',
    [Rule('TLabel', 'Caption', TDfmCondition.NotEmpty, '')], FIndex, ReadSource);
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.IsFalse(Found[0].HasFix);
  Found := TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm',
    [Rule('TLabel', 'Caption', TDfmCondition.Empty, '')], FIndex, ReadSource);
  Assert.AreEqual(0, Integer(Length(Found)));
end;

procedure TFormSymbolsTests.RuleExcludeSeverityAndFixMode;
var
  Rules: TArray<TDfmPropertyRule>;
  Found: TArray<TFormPropertyViolation>;
begin
  Rules := [Rule('TLabel', 'Transparent', TDfmCondition.Equal, 'True')];
  Rules[0].Fix := TDfmFixMode.Auto;
  Rules[0].Message := 'Labels transparent';
  Found := TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm', Rules, FIndex, ReadSource);
  Assert.IsTrue(Found[0].Safe);
  Assert.AreEqual('Labels transparent', Found[0].Message);
  Rules[0].Fix := TDfmFixMode.None;
  Found := TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm', Rules, FIndex, ReadSource);
  Assert.IsFalse(Found[0].HasFix);
  Rules[0].Exclude := ['*.dfm'];
  Assert.AreEqual(0, Integer(Length(TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm', Rules, FIndex,
    ReadSource))));
  Rules[0].Exclude := nil;
  Rules[0].Severity := TRuleSeverity.Off;
  Assert.AreEqual(0, Integer(Length(TFormSymbols.PropertyViolations(RuleForm, 'Haupt.dfm', Rules, FIndex,
    ReadSource))));
end;

procedure TFormSymbolsTests.RuleProblemsForUnknownNames;
var
  Problems: TArray<TFormPropertyRuleProblem>;
begin
  Problems := TFormSymbols.RuleProblems([Rule('TLabel', 'Transparent', TDfmCondition.Equal, 'True'),
    Rule('TUnbekannt', 'X', TDfmCondition.Equal, '1'), Rule('TLabel', 'Farbe', TDfmCondition.Equal, '1')], FIndex,
    ReadSource);
  Assert.AreEqual(2, Integer(Length(Problems)));
  Assert.AreEqual(1, Problems[0].RuleIndex);
  Assert.AreEqual('Unbekannte Klasse "TUnbekannt"', Problems[0].Message);
  Assert.AreEqual('TLabel hat keine published-Property "Farbe"', Problems[1].Message);
end;

procedure TFormSymbolsTests.RedundantDefaultsFound;
var
  Found: TArray<TRedundantDefault>;
begin
  Found := TFormSymbols.RedundantDefaults(FormText, FIndex, ReadSource);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('TabStop', Found[0].PropertyName);
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual('Width', Found[1].PropertyName);
  Found := TFormSymbols.RedundantDefaults(StringReplace(FormText, 'TabStop = True', 'TabStop = False', []), FIndex,
    ReadSource);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Width', Found[0].PropertyName);
end;

initialization
  TDUnitX.RegisterTestFixture(TFormSymbolsTests);

end.
