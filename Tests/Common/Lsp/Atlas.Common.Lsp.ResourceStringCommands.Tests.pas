unit Atlas.Common.Lsp.ResourceStringCommands.Tests;

// Tests für atlas.server.addResourceString (#473): Eintrag im interface-Teil
// einer festgelegten Unit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TResourceStringCommandsTests = class
  public
    [Test]
    procedure AddsToInterfaceSection;
    [Test]
    procedure CreatesSectionWithCrLf;
    [Test]
    procedure KeepsSameEntry;
    [Test]
    procedure RejectsNameWithOtherText;
    [Test]
    procedure ExecuteReadsAndWrites;
    [Test]
    procedure ExecuteRejectsBadArguments;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.ResourceStringCommands;

const
  cTexte =
    'unit Texte;'#10 +
    'interface'#10 +
    'resourcestring'#10 +
    '  SOk = ''OK'';'#10 +
    'implementation'#10 +
    'end.'#10;

function Added(const AText, AName, AValue: string): string;
var
  mEdit: TTextEdit;
begin
  Result := '-';
  if TResourceStringCommands.AddEdit(AText, AName, AValue, mEdit) then
  begin
    Result := TResourceStringCommands.Applied(AText, mEdit);
  end;
end;

{ TResourceStringCommandsTests }

procedure TResourceStringCommandsTests.AddsToInterfaceSection;
begin
  Assert.AreEqual(
    'unit Texte;'#10 +
    'interface'#10 +
    'resourcestring'#10 +
    '  SOk = ''OK'';'#10 +
    '  SFrage = ''Wirklich?'';'#10 +
    'implementation'#10 +
    'end.'#10, Added(cTexte, 'SFrage', '''Wirklich?'''));
end;

procedure TResourceStringCommandsTests.CreatesSectionWithCrLf;
begin
  Assert.AreEqual(
    'unit Texte;'#13#10 +
    'interface'#13#10 +
    'resourcestring'#13#10 +
    '  SFrage = ''Wirklich?'';'#13#10 +
    #13#10 +
    'implementation'#13#10 +
    'end.'#13#10, Added('unit Texte;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10, 'SFrage',
    '''Wirklich?'''));
end;

procedure TResourceStringCommandsTests.KeepsSameEntry;
begin
  Assert.AreEqual('-', Added(cTexte, 'SOk', '''OK'''));
end;

procedure TResourceStringCommandsTests.RejectsNameWithOtherText;
begin
  Assert.WillRaise(
    procedure
    begin
      Added(cTexte, 'sok', '''Okay''');
    end, EJsonRpcError);
end;

procedure TResourceStringCommandsTests.ExecuteReadsAndWrites;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
  mWritten, mWrittenFile: string;
  mWrittenEdit: TTextEdit;
begin
  mWritten := '';
  mArguments := TJSONArray.Create;
  try
    mArguments.Add('C:\P\Texte.pas');
    mArguments.Add('SFrage');
    mArguments.Add('''Wirklich?''');
    mAnswer := TResourceStringCommands.ExecuteAdd(
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cTexte;
        Result := AFileName = 'C:\P\Texte.pas';
      end,
      procedure(const AFileName, ANewText: string; const AEdit: TTextEdit)
      begin
        mWrittenFile := AFileName;
        mWritten := ANewText;
        mWrittenEdit := AEdit;
      end, mArguments);
    try
      Assert.IsTrue((mAnswer as TJSONBool).AsBoolean);
    finally
      mAnswer.Free;
    end;
    Assert.AreEqual('C:\P\Texte.pas', mWrittenFile);
    Assert.Contains(mWritten, '  SFrage = ''Wirklich?'';'#10'implementation');
    Assert.AreEqual(3, mWrittenEdit.Range.StartPos.Line);
  finally
    mArguments.Free;
  end;
  mWrittenFile := '';
end;

procedure TResourceStringCommandsTests.ExecuteRejectsBadArguments;
begin
  Assert.WillRaise(
    procedure
    var
      Arguments: TJSONArray;
    begin
      Arguments := TJSONArray.Create;
      try
        Arguments.Add('C:\P\Texte.pas');
        Arguments.Add('S Frage');
        Arguments.Add('''x''');
        TResourceStringCommands.ExecuteAdd(
          function(const AFileName: string; out AText: string): Boolean
          begin
            AText := cTexte;
            Result := True;
          end,
          procedure(const AFileName, ANewText: string; const AEdit: TTextEdit)
          begin
          end, Arguments).Free;
      finally
        Arguments.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TResourceStringCommandsTests);

end.
