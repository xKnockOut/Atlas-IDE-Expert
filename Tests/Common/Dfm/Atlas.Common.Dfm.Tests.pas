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
    /// <summary>#1235: Langen String schreibt Delphi ab der Zeile nach "=" ('Bla'#123 + …); kein Fehler.</summary>
    [Test]
    procedure ReadsValueOnNextLine;
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
    /// <summary>#44: Ein Handler, der nur in der Vorfahrklasse steht, ergibt in einer inherited-DFM kein
    /// falsches Ziel (auch nicht eine gleichnamige Methode einer anderen Klasse der Unit).</summary>
    [Test]
    procedure InheritedHandlerHasNoWrongTarget;
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
  cForm =
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

  cFormUnit =
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
  begin
    AText := cFormUnit;
  end;
end;

const
  cInheritedForm =
    'inherited Form2: TForm2'#10 +                  // 0
    '  inherited Button1: TButton'#10 +             // 1
    '    OnClick = Button1Click'#10 +               // 2
    '  end'#10 +                                    // 3
    '  object Button2: TButton'#10 +                // 4
    '    OnClick = Button2Click'#10 +               // 5
    '  end'#10 +                                    // 6
    'end'#10;
  cInheritedUnit =
    'unit Unit2;'#10 +                              // 0
    'interface'#10 +                                // 1
    'uses Unit1;'#10 +                              // 2
    'type'#10 +                                     // 3
    '  TForm2 = class(TForm1)'#10 +                 // 4
    '    Button2: TButton;'#10 +                    // 5
    '    procedure Button2Click(Sender: TObject);'#10 + // 6
    '  end;'#10 +                                   // 7
    '  THelfer = class'#10 +                        // 8
    '    procedure Button1Click(Sender: TObject);'#10 + // 9
    '  end;'#10 +                                   // 10
    'implementation'#10 +                           // 11
    'procedure TForm2.Button2Click(Sender: TObject);'#10 + // 12
    'begin'#10 +                                    // 13
    'end;'#10 +                                     // 14
    'procedure THelfer.Button1Click(Sender: TObject);'#10 + // 15
    'begin'#10 +                                    // 16
    'end;'#10 +                                     // 17
    'end.'#10;

function ReadInheritedUnit(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(ExtractFileName(AFileName), 'Unit2.pas');
  if Result then
  begin
    AText := cInheritedUnit;
  end;
end;

function NoUnit(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

{ TDfmTests }

procedure TDfmTests.ParsesObjectTree;
var
  mDocument: TDfmDocument;
begin
  mDocument := TDfmParser.Parse(cForm);
  try
    Assert.IsNotNull(mDocument.Root);
    Assert.AreEqual('Form1', mDocument.Root.Name);
    Assert.AreEqual('TForm1', mDocument.Root.TypeName);
    Assert.AreEqual(2, Integer(mDocument.Root.Children.Count));
    Assert.AreEqual('Button1', mDocument.Root.Children[0].Name);
    Assert.AreEqual('TStringGrid', mDocument.Root.Children[1].TypeName);
    Assert.AreEqual(6, mDocument.Root.Children[0].Range.StartPos.Line);
    Assert.AreEqual(9, mDocument.Root.Children[0].Range.EndPos.Line);
    Assert.AreEqual(0, Integer(Length(mDocument.Errors)));
  finally
    mDocument.Free;
  end;
end;

procedure TDfmTests.ParsesValuesOfAllKinds;
var
  mDocument: TDfmDocument;
  mItem: TDfmProperty;
  mNames: string;
begin
  mDocument := TDfmParser.Parse(cForm);
  try
    mNames := '';
    for mItem in mDocument.Root.Properties do
    begin
      mNames := mNames + mItem.Name + ';';
    end;
    Assert.AreEqual('Left;Caption;Font.Name;Anchors;OnCreate;', mNames);
    Assert.AreEqual('0', mDocument.Root.Properties[0].Value);
    Assert.AreEqual('[akLeft, akTop]', mDocument.Root.Properties[3].Value);
    mNames := '';
    for mItem in mDocument.Root.Children[1].Properties do
    begin
      mNames := mNames + mItem.Name + ';';
    end;
    Assert.AreEqual('Columns;Data;', mNames);
  finally
    mDocument.Free;
  end;
end;

procedure TDfmTests.ReadsValueOnNextLine;
var
  mDocument: TDfmDocument;
begin
  mDocument := TDfmParser.Parse(
    'object Form1: TForm1'#13#10 +
    '  Hint = '#13#10 +
    '    ''Bla''#123''Bla'' +'#13#10 +
    '    ''weiter'''#13#10 +
    '  Caption = ''Bla''#123''Bla'''#13#10 +
    '  Left = 0'#13#10 +
    'end'#13#10);
  try
    Assert.AreEqual(0, Integer(Length(mDocument.Errors)), 'kein „Property oder end erwartet“');
    Assert.AreEqual(3, Integer(Length(mDocument.Root.Properties)));
    Assert.AreEqual('''Bla''#123''Bla'' +'#13#10'    ''weiter''', mDocument.Root.Properties[0].Value);
    Assert.AreEqual(2, mDocument.Root.Properties[0].ValueRange.StartPos.Line, 'Wert beginnt in der nächsten Zeile');
    Assert.AreEqual('''Bla''#123''Bla''', mDocument.Root.Properties[1].Value);
    Assert.AreEqual('Left', mDocument.Root.Properties[2].Name);
  finally
    mDocument.Free;
  end;
end;

procedure TDfmTests.MarksEvents;
var
  mDocument: TDfmDocument;
begin
  mDocument := TDfmParser.Parse(cForm);
  try
    Assert.IsTrue(mDocument.Root.Properties[4].IsEvent);
    Assert.IsFalse(mDocument.Root.Properties[1].IsEvent);
    // Ereignisse von Datenmengen ohne On (#856); Wörter wie Online oder Afterglow zählen nicht.
    Assert.IsTrue(TDfmProperty.IsEventName('BeforePost'));
    Assert.IsTrue(TDfmProperty.IsEventName('AfterScroll'));
    Assert.IsTrue(TDfmProperty.IsEventName('OnCalcFields'));
    Assert.IsFalse(TDfmProperty.IsEventName('Online'));
    Assert.IsFalse(TDfmProperty.IsEventName('Afterglow'));
    Assert.IsFalse(TDfmProperty.IsEventName('Before'));
    Assert.AreEqual('Button1Click', mDocument.Root.Children[0].Properties[1].Value);
    Assert.AreEqual(8, mDocument.Root.Children[0].Properties[1].ValueRange.StartPos.Line);
  finally
    mDocument.Free;
  end;
end;

procedure TDfmTests.ReportsErrorsAndContinues;
var
  mDocument: TDfmDocument;
begin
  mDocument := TDfmParser.Parse(
    'object Form1: TForm1'#10 +
    '  ??? kaputt'#10 +
    '  object Button1: TButton'#10 +
    '  end'#10 +
    'end');
  try
    Assert.IsTrue(Length(mDocument.Errors) > 0);
    Assert.AreEqual(1, mDocument.Errors[0].Position.Line);
    Assert.AreEqual(1, Integer(mDocument.Root.Children.Count));
  finally
    mDocument.Free;
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
  mDocument: TDfmDocument;
begin
  mDocument := TDfmParser.Parse(cForm);
  try
    Assert.AreEqual('Button1', TDfmNavigation.ObjectAt(mDocument, Position(7, 6)).Name);
    Assert.AreEqual('Form1', TDfmNavigation.ObjectAt(mDocument, Position(2, 4)).Name);
  finally
    mDocument.Free;
  end;
end;

procedure TDfmTests.JumpsFromEventToImplementation;
var
  mTargets: TArray<TDfmTarget>;
begin
  mTargets := TDfmNavigation.Targets(cForm, 'C:\P\Unit1.dfm', Position(8, 16), ReadUnit);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('C:\P\Unit1.pas', mTargets[0].FileName);
  Assert.AreEqual(8, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TDfmTests.JumpsFromPlatformViewToUnit;
var
  mTargets: TArray<TDfmTarget>;
begin
  // Abnahme #87: F12 auf einen Handler in Unit1.Windows.fmx springt in Unit1.pas, nicht Unit1.Windows.pas.
  mTargets := TDfmNavigation.Targets(cForm, 'C:\P\Unit1.Windows.fmx', Position(8, 16), ReadUnit);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('C:\P\Unit1.pas', mTargets[0].FileName);
  Assert.AreEqual(8, mTargets[0].SelectionRange.StartPos.Line);
  mTargets := TDfmNavigation.Targets(cForm, 'C:\P\Unit1.Android.fmx', Position(8, 16), ReadUnit);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('C:\P\Unit1.pas', mTargets[0].FileName);
end;

procedure TDfmTests.JumpsFromComponentToField;
var
  mTargets: TArray<TDfmTarget>;
begin
  mTargets := TDfmNavigation.Targets(cForm, 'C:\P\Unit1.dfm', Position(6, 10), ReadUnit);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual(4, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TDfmTests.JumpsFromFormToClass;
var
  mTargets: TArray<TDfmTarget>;
begin
  mTargets := TDfmNavigation.Targets(cForm, 'C:\P\Unit1.dfm', Position(0, 8), ReadUnit);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual(3, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TDfmTests.NoJumpWithoutUnit;
begin
  Assert.AreEqual(0, Integer(Length(TDfmNavigation.Targets(cForm, 'C:\P\Unit1.dfm', Position(8, 16), NoUnit))));
  // Auf einem gewöhnlichen Wert gibt es kein Ziel.
  Assert.AreEqual(0, Integer(Length(TDfmNavigation.Targets(cForm, 'C:\P\Unit1.dfm', Position(1, 9), ReadUnit))));
end;

procedure TDfmTests.InheritedHandlerHasNoWrongTarget;
var
  mTargets: TArray<TDfmTarget>;
begin
  // Button1Click gehört zu TForm1 (Vorfahr, andere Unit); THelfer.Button1Click ist nicht gemeint.
  mTargets := TDfmNavigation.Targets(cInheritedForm, 'C:\P\Unit2.dfm', Position(2, 16), ReadInheritedUnit);
  Assert.AreEqual(0, Integer(Length(mTargets)));
  // Der eigene Handler der abgeleiteten Klasse wird gefunden, die Implementierung gewinnt.
  mTargets := TDfmNavigation.Targets(cInheritedForm, 'C:\P\Unit2.dfm', Position(5, 16), ReadInheritedUnit);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual('C:\P\Unit2.pas', mTargets[0].FileName);
  Assert.AreEqual(12, mTargets[0].SelectionRange.StartPos.Line);
end;

procedure TDfmTests.BuildsSymbolsAndFolding;
var
  mDocument: TDfmDocument;
  mSymbols, mFolding: TJSONArray;
  mName: string;
begin
  mDocument := TDfmParser.Parse(cForm);
  try
    mSymbols := TLspFormFiles.BuildSymbols(mDocument);
    try
      Assert.AreEqual(1, Integer(mSymbols.Count));
      // Gliederung zeigt Name und Typ, wie der Objektinspektor.
      mName := (mSymbols.Items[0] as TJSONObject).GetValue<string>('name');
      Assert.AreEqual('Form1: TForm1', mName);
      Assert.IsTrue(Pos('Button1', mSymbols.ToJSON) > 0);
      Assert.IsTrue(Pos('Button1Click', mSymbols.ToJSON) > 0);
    finally
      mSymbols.Free;
    end;
    mFolding := TLspFormFiles.BuildFoldingRanges(mDocument);
    try
      Assert.IsTrue(mFolding.Count >= 3);
    finally
      mFolding.Free;
    end;
  finally
    mDocument.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmTests);

end.
