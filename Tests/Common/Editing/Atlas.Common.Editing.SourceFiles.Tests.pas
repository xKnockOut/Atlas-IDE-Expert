unit Atlas.Common.Editing.SourceFiles.Tests;

// Tests für die Dateien dateiübergreifender Umbauten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingSourceFileTests = class
  public
    [Test]
    procedure CreateKeepsFields;
  end;

implementation

uses
  Atlas.Common.Editing.SourceFiles;

procedure TEditingSourceFileTests.CreateKeepsFields;
var
  mFile: TEditingSourceFile;
begin
  mFile := TEditingSourceFile.Create('A.pas', 'unit A;', nil);
  Assert.AreEqual('A.pas', mFile.FileName);
  Assert.AreEqual('unit A;', mFile.Text);
  Assert.IsNull(mFile.Tree);
  Assert.AreEqual(0, Integer(Length(mFile.Offsets)));
  mFile := TEditingSourceFile.Create('B.pas', 'unit B;', nil, TArray<Integer>.Create(3, 9));
  Assert.AreEqual(2, Integer(Length(mFile.Offsets)));
  Assert.AreEqual(9, mFile.Offsets[1]);
  mFile := Default(TEditingSourceFile);
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingSourceFileTests);

end.
