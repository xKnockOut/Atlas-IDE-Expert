unit Atlas.Common.Lsp.Impact.Forms.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.Impact.Forms;

type
  [TestFixture]
  TImpactFormCacheTests = class
  private
    FCache: TImpactFormCache;
    FReads: Integer;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure HandlerBindingWithLineText;
    [Test]
    procedure ComponentNameBinding;
    [Test]
    procedure UnknownNameHasNoBinding;
    [Test]
    procedure UnitWithoutFormHasNoBinding;
    [Test]
    procedure FormFileItselfHasNoBinding;
    [Test]
    procedure FormReadOnceForSeveralNames;
    [Test]
    procedure FormFileExtensions;
  end;

implementation

uses
  System.SysUtils;

const
  UnitFile = 'C:\P\Haupt.pas';
  FormFile = 'C:\P\Haupt.dfm';
  PlainFile = 'C:\P\Ohne.pas';

  UnitText =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TForm1 = class'#10 +
    '    procedure Button1Click(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    '{$R *.dfm}'#10 +
    'end.';

  FormText =
    'object Form1: TForm1'#10 +
    '  object Button1: TButton'#10 +
    '    OnClick = Button1Click'#10 +
    '  end'#10 +
    'end';

  PlainText =
    'unit Ohne;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'end.';

function TImpactFormCacheTests.ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, UnitFile) then
  begin
    AText := UnitText;
  end
  else if SameText(AFileName, FormFile) then
  begin
    Inc(FReads);
    AText := FormText;
  end
  else if SameText(AFileName, PlainFile) then
  begin
    AText := PlainText;
  end
  else
  begin
    AText := '';
    Result := False;
  end;
end;

procedure TImpactFormCacheTests.Setup;
begin
  FReads := 0;
  FCache := TImpactFormCache.Create(ReadFile);
end;

procedure TImpactFormCacheTests.TearDown;
begin
  FreeAndNil(FCache);
end;

procedure TImpactFormCacheTests.HandlerBindingWithLineText;
var
  mFound: TArray<TImpactFormBinding>;
begin
  mFound := FCache.Bindings('Button1Click', UnitFile);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(FormFile, mFound[0].FileName);
  Assert.AreEqual('OnClick = Button1Click', mFound[0].Text);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Line);
end;

procedure TImpactFormCacheTests.ComponentNameBinding;
var
  mFound: TArray<TImpactFormBinding>;
begin
  mFound := FCache.Bindings('Button1', UnitFile);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('object Button1: TButton', mFound[0].Text);
end;

procedure TImpactFormCacheTests.UnknownNameHasNoBinding;
begin
  Assert.AreEqual(0, Integer(Length(FCache.Bindings('Fehlt', UnitFile))));
  Assert.AreEqual(0, Integer(Length(FCache.Bindings('', UnitFile))));
end;

procedure TImpactFormCacheTests.UnitWithoutFormHasNoBinding;
begin
  Assert.AreEqual(0, Integer(Length(FCache.Bindings('Button1Click', PlainFile))));
  Assert.AreEqual(0, Integer(Length(FCache.Bindings('Button1Click', 'C:\P\Fehlt.pas'))));
end;

procedure TImpactFormCacheTests.FormFileItselfHasNoBinding;
begin
  Assert.AreEqual(0, Integer(Length(FCache.Bindings('Button1Click', FormFile))));
end;

procedure TImpactFormCacheTests.FormReadOnceForSeveralNames;
begin
  FCache.Bindings('Button1Click', UnitFile);
  FCache.Bindings('Fehlt', UnitFile);
  // Das Modell wird einmal gelesen; den Zeilentext liest nur die Bindung mit Fundstelle nach.
  Assert.AreEqual(2, FReads);
end;

procedure TImpactFormCacheTests.FormFileExtensions;
begin
  Assert.IsTrue(TImpactFormCache.IsFormFile('C:\P\A.DFM'));
  Assert.IsTrue(TImpactFormCache.IsFormFile('C:\P\A.fmx'));
  Assert.IsFalse(TImpactFormCache.IsFormFile('C:\P\A.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TImpactFormCacheTests);

end.
