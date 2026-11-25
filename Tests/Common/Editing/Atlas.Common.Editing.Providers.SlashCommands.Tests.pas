unit Atlas.Common.Editing.Providers.SlashCommands.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingSlashChecksProviderTests = class
  public
    /// <summary>Unbekannte Befehle meldet der Anbieter, bekannte mit passenden Argumenten nicht.</summary>
    [Test]
    procedure ReportsUnknownCommandsOnly;
  end;

implementation

uses
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.Contract.SlashCommands,
  Atlas.Common.Editing.Composition;

{ TEditingSlashChecksProviderTests }

procedure TEditingSlashChecksProviderTests.ReportsUnknownCommandsOnly;
const
  cHead = 'unit U;'#10'interface'#10'implementation'#10;
var
  mChecks: IEditingSlashChecks;
  mProblems: TArray<TSlashProblem>;
begin
  mChecks := TEditingComposition.SlashChecks;
  mProblems := mChecks.Problems(cHead + '/gibtsnicht'#10'end.', nil, '');
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual(3, mProblems[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(mChecks.Problems(cHead + 'end.', nil, ''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingSlashChecksProviderTests);

end.
