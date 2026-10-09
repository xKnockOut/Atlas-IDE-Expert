unit Argus.Common.Dfm.ComponentRename.Tests;

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
  Argus.Common.Dfm.ComponentRename;

const
  Form =
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
  Renames: TArray<THandlerRename>;
begin
  Renames := TDfmComponentRename.Handlers(Form, 'Button1', 'btnSpeichern');
  Assert.AreEqual(2, Integer(Length(Renames)));
  Assert.AreEqual('Button1Click', Renames[0].OldName);
  Assert.AreEqual('btnSpeichernClick', Renames[0].NewName);
  Assert.AreEqual('btnSpeichernDrawItem', Renames[1].NewName);
end;

procedure TDfmComponentRenameTests.KeepsOwnHandlerNames;
var
  Rename: THandlerRename;
begin
  for Rename in TDfmComponentRename.Handlers(Form, 'Button1', 'btnSpeichern') do
  begin
    Assert.AreNotEqual('SpeichernAusfuehren', Rename.OldName);
    Assert.AreNotEqual('Button1', Rename.OldName);
  end;
end;

procedure TDfmComponentRenameTests.ListsSharedHandlerOnce;
var
  Rename: THandlerRename;
  Count: Integer;
begin
  Count := 0;
  for Rename in TDfmComponentRename.Handlers(Form, 'button1', 'btnSpeichern') do
    if Rename.OldName = 'Button1Click' then
      Inc(Count);
  Assert.AreEqual(1, Count);
end;

procedure TDfmComponentRenameTests.NothingForUnknownComponentOrForm;
begin
  Assert.AreEqual(0, Integer(Length(TDfmComponentRename.Handlers(Form, 'Edit1', 'edtName'))));
  Assert.AreEqual(0, Integer(Length(TDfmComponentRename.Handlers(Form, 'Maske', 'Haupt'))));
  Assert.AreEqual(0, Integer(Length(TDfmComponentRename.Handlers(Form, 'Button1', 'Button1'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmComponentRenameTests);

end.
