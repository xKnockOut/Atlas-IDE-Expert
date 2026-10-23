unit Atlas.Common.Pascal.PureRoutines.Tests;

// Tests der Liste von Standardroutinen ohne Seiteneffekte (#1109).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPureRoutinesTests = class
  public
    [Test]
    procedure KnowsPureRoutines;
    [Test]
    procedure ListHasNoDuplicates;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.PureRoutines;

procedure TPureRoutinesTests.KnowsPureRoutines;
begin
  Assert.IsTrue(TPureRoutines.IsPure('Format'));
  Assert.IsTrue(TPureRoutines.IsPure('copy'));
  Assert.IsTrue(TPureRoutines.IsPure('String.Join'));
  Assert.IsTrue(TPureRoutines.IsPure('ExtractFileExt'));
  Assert.IsFalse(TPureRoutines.IsPure('Inc'));
  Assert.IsFalse(TPureRoutines.IsPure('Free'));
  Assert.IsFalse(TPureRoutines.IsPure('Join'));
  Assert.IsFalse(TPureRoutines.IsPure(''));
end;

procedure TPureRoutinesTests.ListHasNoDuplicates;
var
  Seen: TDictionary<string, Boolean>;
  Name: string;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Name in TPureRoutines.Names do
    begin
      Assert.IsFalse(Seen.ContainsKey(LowerCase(Name)), Name);
      Seen.Add(LowerCase(Name), True);
    end;
  finally
    Seen.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPureRoutinesTests);

end.
