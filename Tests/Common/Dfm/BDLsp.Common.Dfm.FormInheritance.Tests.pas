unit BDLsp.Common.Dfm.FormInheritance.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormInheritanceTests = class
  public
    [Test]
    procedure ReadsThreeLevels;
    [Test]
    procedure HoverShowsInheritedValueAndLevels;
    [Test]
    procedure HoverOnFormProperty;
    [Test]
    procedure CollectionReplacesList;
    [Test]
    procedure NewPropertyGivesNoHover;
    [Test]
    procedure UnresolvedAncestorGivesNothing;
    [Test]
    procedure ResetRemovesExactlyTheLine;
    [Test]
    procedure FindsAncestorFromUnit;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Dfm.FormInheritance;

const
  BasisDfm =
    'object Basis: TBasis'#10 +
    '  Caption = ''Basis'''#10 +
    '  Width = 300'#10 +
    '  object Ok: TButton'#10 +
    '    Caption = ''OK'''#10 +
    '    Left = 8'#10 +
    '  end'#10 +
    '  object Spalten: TListView'#10 +
    '    Columns = <'#10 +
    '      item'#10 +
    '        Caption = ''A'''#10 +
    '      end>'#10 +
    '  end'#10 +
    'end'#10;

  MitteDfm =
    'inherited Mitte: TMitte'#10 +
    '  Caption = ''Mitte'''#10 +
    '  inherited Ok: TButton'#10 +
    '    Caption = ''Weiter'''#10 +
    '  end'#10 +
    'end'#10;

  FormDfm =
    'inherited Form2: TForm2'#10 +
    '  Width = 400'#10 +
    '  inherited Ok: TButton'#10 +
    '    Caption = ''Los'''#10 +
    '    Top = 4'#10 +
    '  end'#10 +
    '  inherited Spalten: TListView'#10 +
    '    Columns = <'#10 +
    '      item'#10 +
    '        Caption = ''B'''#10 +
    '      end>'#10 +
    '  end'#10 +
    'end'#10;

function AncestorOf(const AFormFile, AFormClass: string): string;
begin
  if SameText(AFormClass, 'TForm2') then
    Result := 'TMitte'
  else if SameText(AFormClass, 'TMitte') then
    Result := 'TBasis'
  else
    Result := '';
end;

function Resolve(const AClassName: string; out AFormFile, AFormText: string): Boolean;
begin
  Result := True;
  if SameText(AClassName, 'TMitte') then
  begin
    AFormFile := 'C:\P\Mitte.dfm';
    AFormText := MitteDfm;
  end
  else if SameText(AClassName, 'TBasis') then
  begin
    AFormFile := 'C:\P\Basis.dfm';
    AFormText := BasisDfm;
  end
  else
    Result := False;
end;

function ResolveNothing(const AClassName: string; out AFormFile, AFormText: string): Boolean;
begin
  Result := False;
end;

function NewChain: TFormInheritance;
begin
  Result := TFormInheritance.Create('C:\P\Form2.dfm', FormDfm, AncestorOf, Resolve);
end;

{ TFormInheritanceTests }

procedure TFormInheritanceTests.ReadsThreeLevels;
var
  Chain: TFormInheritance;
begin
  Chain := NewChain;
  try
    Assert.AreEqual(3, Length(Chain.Levels));
    Assert.AreEqual('TMitte', Chain.Levels[1].FormClass);
    Assert.AreEqual('TBasis', Chain.Levels[2].FormClass);
  finally
    Chain.Free;
  end;
end;

procedure TFormInheritanceTests.HoverShowsInheritedValueAndLevels;
var
  Chain: TFormInheritance;
  Text: string;
begin
  Chain := NewChain;
  try
    // Caption = 'Los' von Ok: Mitte setzt 'Weiter', Basis 'OK'.
    Text := Chain.HoverAt(TTextPosition.Create(3, 5));
    Assert.IsTrue(Pos('überschreibt den geerbten Wert `''Weiter''` aus TMitte', Text) > 0, Text);
    Assert.IsTrue(Pos('- TForm2: `''Los''` (hier)', Text) > 0, Text);
    Assert.IsTrue(Pos('- TMitte: `''Weiter''` (Mitte.dfm)', Text) > 0, Text);
    Assert.IsTrue(Pos('- TBasis: `''OK''` (Basis.dfm)', Text) > 0, Text);
  finally
    Chain.Free;
  end;
end;

procedure TFormInheritanceTests.HoverOnFormProperty;
var
  Chain: TFormInheritance;
  Text: string;
begin
  Chain := NewChain;
  try
    // Width kommt nur in der Basis vor.
    Text := Chain.HoverAt(TTextPosition.Create(1, 3));
    Assert.IsTrue(Pos('`300` aus TBasis', Text) > 0, Text);
  finally
    Chain.Free;
  end;
end;

procedure TFormInheritanceTests.CollectionReplacesList;
var
  Chain: TFormInheritance;
  Text: string;
begin
  Chain := NewChain;
  try
    Text := Chain.HoverAt(TTextPosition.Create(7, 5));
    Assert.IsTrue(Pos('ersetzt die geerbte Liste aus TBasis', Text) > 0, Text);
  finally
    Chain.Free;
  end;
end;

procedure TFormInheritanceTests.NewPropertyGivesNoHover;
var
  Chain: TFormInheritance;
begin
  Chain := NewChain;
  try
    // Top setzt erst Form2.
    Assert.AreEqual('', Chain.HoverAt(TTextPosition.Create(4, 5)));
  finally
    Chain.Free;
  end;
end;

procedure TFormInheritanceTests.UnresolvedAncestorGivesNothing;
var
  Chain: TFormInheritance;
  Edit: TRuleEdit;
  Title: string;
begin
  Chain := TFormInheritance.Create('C:\P\Form2.dfm', FormDfm, AncestorOf, ResolveNothing);
  try
    Assert.AreEqual(1, Length(Chain.Levels));
    Assert.AreEqual('', Chain.HoverAt(TTextPosition.Create(3, 5)));
    Assert.IsFalse(Chain.ResetAt(TTextPosition.Create(3, 5), Edit, Title));
  finally
    Chain.Free;
  end;
end;

procedure TFormInheritanceTests.ResetRemovesExactlyTheLine;
var
  Chain: TFormInheritance;
  Edit: TRuleEdit;
  Title: string;
begin
  Chain := NewChain;
  try
    Assert.IsTrue(Chain.ResetAt(TTextPosition.Create(3, 5), Edit, Title));
    Assert.AreEqual(3, Edit.Range.StartPos.Line);
    Assert.AreEqual(0, Edit.Range.StartPos.Character);
    Assert.AreEqual(4, Edit.Range.EndPos.Line);
    Assert.AreEqual(0, Edit.Range.EndPos.Character);
    Assert.AreEqual('', Edit.NewText);
    Assert.IsTrue(Pos('Caption auf geerbten Wert zurücksetzen', Title) = 1, Title);
    // Mehrzeilige Collection: alle Zeilen bis zur schließenden Klammer.
    Assert.IsTrue(Chain.ResetAt(TTextPosition.Create(7, 5), Edit, Title));
    Assert.AreEqual(7, Edit.Range.StartPos.Line);
    Assert.AreEqual(11, Edit.Range.EndPos.Line);
  finally
    Chain.Free;
  end;
end;

function ReadFiles(AFileName: string): string;
begin
  if SameText(AFileName, 'C:\P\Form2.pas') then
    Result := 'unit Form2;'#10'interface'#10'type'#10'  TForm2 = class(TMitte)'#10'  end;'#10 +
      'implementation'#10'end.'
  else if SameText(AFileName, 'C:\P\Form2.dfm') then
    Result := FormDfm
  else
    Result := '';
end;

procedure TFormInheritanceTests.FindsAncestorFromUnit;
begin
  Assert.AreEqual('TMitte', TFormInheritance.UnitAncestorOf(ReadFiles)('C:\P\Form2.dfm', 'TForm2'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormInheritanceTests);

end.
