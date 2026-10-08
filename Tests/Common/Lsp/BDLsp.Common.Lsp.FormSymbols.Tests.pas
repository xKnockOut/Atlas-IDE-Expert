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
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
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
