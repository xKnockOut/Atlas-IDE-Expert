unit Atlas.Common.Dfm.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDfmTests = class
  public
    [Test]
    procedure ParsesObjectTree;
    [Test]
    procedure ParsesValuesOfAllKinds;
    [Test]
    procedure MarksEvents;
    [Test]
    procedure ReportsErrorsAndContinues;
    [Test]
    procedure RecognizesFormFiles;
    [Test]
    procedure FindsInnermostObject;
    [Test]
    procedure JumpsFromEventToImplementation;
    [Test]
    procedure JumpsFromPlatformViewToUnit;
    [Test]
    procedure JumpsFromComponentToField;
    [Test]
    procedure JumpsFromFormToClass;
    [Test]
    procedure NoJumpWithoutUnit;
    [Test]
    procedure BuildsSymbolsAndFolding;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.Navigation,
  Atlas.Common.Lsp.FormFiles;

const
  Form =
    'object Form1: TForm1'#10 +                     // 0
    '  Left = 0'#10 +                               // 1
    '  Caption = ''Hallo'''#10 +                    // 2
    '  Font.Name = ''Segoe'' + #39'' UI'''#10 +       // 3
    '  Anchors = [akLeft, akTop]'#10 +              // 4
    '  OnCreate = FormCreate'#10 +                  // 5
    '  object Button1: TButton'#10 +                // 6
    '    Caption = ''OK'''#10 +                     // 7
    '    OnClick = Button1Click'#10 +               // 8
    '  end'#10 +                                    // 9
    '  object Grid: TStringGrid'#10 +               // 10
    '    Columns = <'#10 +                          // 11
    '      item'#10 +                               // 12
    '        Width = 20'#10 +                       // 13
    '      end>'#10 +                               // 14
    '    Data = {'#10 +                             // 15
    '      0102}'#10 +                              // 16
    '  end'#10 +                                    // 17
    'end';                                          // 18

  FormUnit =
    'unit Unit1;'#10 +                              // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TForm1 = class(TForm)'#10 +                  // 3
    '    Button1: TButton;'#10 +                    // 4
    '    procedure Button1Click(Sender: TObject);'#10 + // 5
    '  end;'#10 +                                   // 6
    'implementation'#10 +                           // 7
    'procedure TForm1.Button1Click(Sender: TObject);'#10 + // 8
    'begin'#10 +                                    // 9
    'end;'#10 +                                     // 10
    'end.';                                         // 11

function Position(ALine, ACharacter: Integer): TTextPosition;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

function ReadUnit(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(ExtractFileName(AFileName), 'Unit1.pas');
  if Result then
    AText := FormUnit;
end;

function NoUnit(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

{ TDfmTests }

procedure TDfmTests.ParsesObjectTree;
var
  Document: TDfmDocument;
begin
  Document := TDfmParser.Parse(Form);
  try
    Assert.IsNotNull(Document.Root);
    Assert.AreEqual('Form1', Document.Root.Name);
    Assert.AreEqual('TForm1', Document.Root.TypeName);
    Assert.AreEqual(2, Integer(Document.Root.Children.Count));
    Assert.AreEqual('Button1', Document.Root.Children[0].Name);
    Assert.AreEqual('TStringGrid', Document.Root.Children[1].TypeName);
    Assert.AreEqual(6, Document.Root.Children[0].Range.StartPos.Line);
    Assert.AreEqual(9, Document.Root.Children[0].Range.EndPos.Line);
    Assert.AreEqual(0, Integer(Length(Document.Errors)));
  finally
    Document.Free;
  end;
end;

procedure TDfmTests.ParsesValuesOfAllKinds;
var
  Document: TDfmDocument;
  Item: TDfmProperty;
  Names: string;
begin
  Document := TDfmParser.Parse(Form);
  try
    Names := '';
    for Item in Document.Root.Properties do
      Names := Names + Item.Name + ';';
    Assert.AreEqual('Left;Caption;Font.Name;Anchors;OnCreate;', Names);
    Assert.AreEqual('0', Document.Root.Properties[0].Value);
    Assert.AreEqual('[akLeft, akTop]', Document.Root.Properties[3].Value);
    Names := '';
    for Item in Document.Root.Children[1].Properties do
      Names := Names + Item.Name + ';';
    Assert.AreEqual('Columns;Data;', Names);
  finally
    Document.Free;
  end;
end;

procedure TDfmTests.MarksEvents;
var
  Document: TDfmDocument;
begin
  Document := TDfmParser.Parse(Form);
  try
    Assert.IsTrue(Document.Root.Properties[4].IsEvent);
    Assert.IsFalse(Document.Root.Properties[1].IsEvent);
    Assert.AreEqual('Button1Click', Document.Root.Children[0].Properties[1].Value);
    Assert.AreEqual(8, Document.Root.Children[0].Properties[1].ValueRange.StartPos.Line);
  finally
    Document.Free;
  end;
end;

procedure TDfmTests.ReportsErrorsAndContinues;
var
  Document: TDfmDocument;
begin
  Document := TDfmParser.Parse(
    'object Form1: TForm1'#10 +
    '  ??? kaputt'#10 +
    '  object Button1: TButton'#10 +
    '  end'#10 +
    'end');
  try
    Assert.IsTrue(Length(Document.Errors) > 0);
    Assert.AreEqual(1, Document.Errors[0].Position.Line);
    Assert.AreEqual(1, Integer(Document.Root.Children.Count));
  finally
    Document.Free;
  end;
end;

procedure TDfmTests.RecognizesFormFiles;
begin
  Assert.IsTrue(TDfmParser.IsFormFile('C:\P\Unit1.dfm'));
  Assert.IsTrue(TDfmParser.IsFormFile('file:///c%3A/P/Main.FMX'));
  Assert.IsFalse(TDfmParser.IsFormFile('C:\P\Unit1.pas'));
end;

procedure TDfmTests.FindsInnermostObject;
var
  Document: TDfmDocument;
begin
  Document := TDfmParser.Parse(Form);
  try
    Assert.AreEqual('Button1', TDfmNavigation.ObjectAt(Document, Position(7, 6)).Name);
    Assert.AreEqual('Form1', TDfmNavigation.ObjectAt(Document, Position(2, 4)).Name);
  finally
    Document.Free;
  end;
end;

procedure TDfmTests.JumpsFromEventToImplementation;
var
  Targets: TArray<TDfmTarget>;
begin
  Targets := TDfmNavigation.Targets(Form, 'C:\P\Unit1.dfm', Position(8, 16), ReadUnit);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual('C:\P\Unit1.pas', Targets[0].FileName);
  Assert.AreEqual(8, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TDfmTests.JumpsFromPlatformViewToUnit;
var
  Targets: TArray<TDfmTarget>;
begin
  // Abnahme #87: F12 auf einen Handler in Unit1.Windows.fmx springt in Unit1.pas, nicht Unit1.Windows.pas.
  Targets := TDfmNavigation.Targets(Form, 'C:\P\Unit1.Windows.fmx', Position(8, 16), ReadUnit);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual('C:\P\Unit1.pas', Targets[0].FileName);
  Assert.AreEqual(8, Targets[0].SelectionRange.StartPos.Line);
  Targets := TDfmNavigation.Targets(Form, 'C:\P\Unit1.Android.fmx', Position(8, 16), ReadUnit);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual('C:\P\Unit1.pas', Targets[0].FileName);
end;

procedure TDfmTests.JumpsFromComponentToField;
var
  Targets: TArray<TDfmTarget>;
begin
  Targets := TDfmNavigation.Targets(Form, 'C:\P\Unit1.dfm', Position(6, 10), ReadUnit);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual(4, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TDfmTests.JumpsFromFormToClass;
var
  Targets: TArray<TDfmTarget>;
begin
  Targets := TDfmNavigation.Targets(Form, 'C:\P\Unit1.dfm', Position(0, 8), ReadUnit);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TDfmTests.NoJumpWithoutUnit;
begin
  Assert.AreEqual(0, Integer(Length(TDfmNavigation.Targets(Form, 'C:\P\Unit1.dfm', Position(8, 16), NoUnit))));
  // Auf einem gewöhnlichen Wert gibt es kein Ziel.
  Assert.AreEqual(0, Integer(Length(TDfmNavigation.Targets(Form, 'C:\P\Unit1.dfm', Position(1, 9), ReadUnit))));
end;

procedure TDfmTests.BuildsSymbolsAndFolding;
var
  Document: TDfmDocument;
  Symbols, Folding: TJSONArray;
  Name: string;
begin
  Document := TDfmParser.Parse(Form);
  try
    Symbols := TLspFormFiles.BuildSymbols(Document);
    try
      Assert.AreEqual(1, Symbols.Count);
      // Gliederung zeigt Name und Typ, wie der Objektinspektor.
      Name := (Symbols.Items[0] as TJSONObject).GetValue<string>('name');
      Assert.AreEqual('Form1: TForm1', Name);
      Assert.IsTrue(Pos('Button1', Symbols.ToJSON) > 0);
      Assert.IsTrue(Pos('Button1Click', Symbols.ToJSON) > 0);
    finally
      Symbols.Free;
    end;
    Folding := TLspFormFiles.BuildFoldingRanges(Document);
    try
      Assert.IsTrue(Folding.Count >= 3);
    finally
      Folding.Free;
    end;
  finally
    Document.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmTests);

end.
