unit Argus.Common.Dfm.FormFiles.Tests;

// Tests für die Zuordnung von Formulardateien und Units samt FMX-Plattformansichten (#87).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormFilesTests = class
  public
    [Test]
    procedure UnitOfPlainForms;
    [Test]
    procedure UnitOfPlatformViews;
    [Test]
    procedure DottedUnitNamesStay;
    [Test]
    procedure FormFilesFromDirectives;
  end;

implementation

uses
  Argus.Common.Dfm.FormFiles;

procedure TFormFilesTests.UnitOfPlainForms;
begin
  Assert.AreEqual('C:\P\Unit1.pas', TFormFiles.UnitFile('C:\P\Unit1.dfm'));
  Assert.AreEqual('C:\P\Unit1.pas', TFormFiles.UnitFile('C:\P\Unit1.fmx'));
end;

procedure TFormFilesTests.UnitOfPlatformViews;
begin
  Assert.AreEqual('C:\P\Unit1.pas', TFormFiles.UnitFile('C:\P\Unit1.Windows.fmx'));
  Assert.AreEqual('C:\P\Unit1.pas', TFormFiles.UnitFile('C:\P\Unit1.Android.fmx'));
  Assert.AreEqual('C:\P\Unit1.pas', TFormFiles.UnitFile('C:\P\Unit1.iPhone55in.fmx'));
  Assert.AreEqual('C:\P\Unit1.pas', TFormFiles.UnitFile('C:\P\Unit1.LgXhdpiTb.fmx'));
end;

procedure TFormFilesTests.DottedUnitNamesStay;
begin
  // Punkt im Unitnamen ist keine Plattform; bei .dfm gibt es keine Ansichten.
  Assert.AreEqual('C:\P\Main.Form.pas', TFormFiles.UnitFile('C:\P\Main.Form.fmx'));
  Assert.AreEqual('C:\P\Main.Windows.pas', TFormFiles.UnitFile('C:\P\Main.Windows.dfm'));
end;

procedure TFormFilesTests.FormFilesFromDirectives;
var
  Files: TArray<string>;
begin
  Files := TFormFiles.FormFiles('C:\P\Unit1.pas',
    'implementation'#10'{$R *.fmx}'#10'{$R *.Windows.fmx MSWINDOWS}'#10'{$R ''Extra.fmx''}'#10'{$R+}'#10 +
    '{$R *.res}');
  Assert.AreEqual(4, Integer(Length(Files)));
  Assert.AreEqual('C:\P\Unit1.dfm', Files[0]);
  Assert.AreEqual('C:\P\Unit1.fmx', Files[1]);
  Assert.AreEqual('C:\P\Unit1.Windows.fmx', Files[2]);
  Assert.AreEqual('C:\P\Extra.fmx', Files[3]);
  Assert.AreEqual(2, Integer(Length(TFormFiles.FormFiles('C:\P\Unit1.pas', ''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormFilesTests);

end.
