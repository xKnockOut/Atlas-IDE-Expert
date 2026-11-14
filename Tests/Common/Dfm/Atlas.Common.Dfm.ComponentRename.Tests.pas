unit Atlas.Common.Dfm.ComponentRename.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDfmComponentRenameTests = class
  public
    [Test]
    procedure RenamesDerivedHandlers;
    [Test]
    procedure KeepsOwnHandlerNames;
    [Test]
    procedure ListsSharedHandlerOnce;
    [Test]
    procedure NothingForUnknownComponentOrForm;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Dfm.ComponentRename;

const
  cForm =
    'object Maske: TMaske'#10 +
    '  OnCreate = MaskeCreate'#10 +
    '  object Button1: TButton'#10 +
    '    OnClick = Button1Click'#10 +
    '    OnEnter = SpeichernAusfuehren'#10 +
    '    OnExit = Button1'#10 +
    '  end'#10 +
    '  object Menu1: TMenuItem'#10 +
    '    OnClick = Button1Click'#10 +
    '    OnDrawItem = Button1DrawItem'#10 +
    '  end'#10 +
    'end';

{ TDfmComponentRenameTests }

procedure TDfmComponentRenameTests.RenamesDerivedHandlers;
var
  mRenames: TArray<THandlerRename>;
begin
  mRenames := TDfmComponentRename.Handlers(cForm, 'Button1', 'btnSpeichern');
  Assert.AreEqual(2, Integer(Length(mRenames)));
  Assert.AreEqual('Button1Click', mRenames[0].OldName);
  Assert.AreEqual('btnSpeichernClick', mRenames[0].NewName);
  Assert.AreEqual('btnSpeichernDrawItem', mRenames[1].NewName);
end;

procedure TDfmComponentRenameTests.KeepsOwnHandlerNames;
var
  mRename: THandlerRename;
begin
  for mRename in TDfmComponentRename.Handlers(cForm, 'Button1', 'btnSpeichern') do
  begin
    Assert.AreNotEqual('SpeichernAusfuehren', mRename.OldName);
    Assert.AreNotEqual('Button1', mRename.OldName);
  end;
end;

procedure TDfmComponentRenameTests.ListsSharedHandlerOnce;
var
  mRename: THandlerRename;
  mCount: Integer;
begin
  mCount := 0;
  for mRename in TDfmComponentRename.Handlers(cForm, 'button1', 'btnSpeichern') do
  begin
    if mRename.OldName = 'Button1Click' then
    begin
      Inc(mCount);
    end;
  end;
  Assert.AreEqual(1, mCount);
end;

procedure TDfmComponentRenameTests.NothingForUnknownComponentOrForm;
begin
  Assert.AreEqual(0, Integer(Length(TDfmComponentRename.Handlers(cForm, 'Edit1', 'edtName'))));
  Assert.AreEqual(0, Integer(Length(TDfmComponentRename.Handlers(cForm, 'Maske', 'Haupt'))));
  Assert.AreEqual(0, Integer(Length(TDfmComponentRename.Handlers(cForm, 'Button1', 'Button1'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmComponentRenameTests);

end.
