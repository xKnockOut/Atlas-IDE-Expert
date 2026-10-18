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
  Texte =
    'unit Texte;'#10 +
    'interface'#10 +
    'resourcestring'#10 +
    '  SOk = ''OK'';'#10 +
    'implementation'#10 +
    'end.'#10;

function Added(const AText, AName, AValue: string): string;
var
  Edit: TTextEdit;
begin
  Result := '-';
  if TResourceStringCommands.AddEdit(AText, AName, AValue, Edit) then
    Result := TResourceStringCommands.Applied(AText, Edit);
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
    'end.'#10, Added(Texte, 'SFrage', '''Wirklich?'''));
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
  Assert.AreEqual('-', Added(Texte, 'SOk', '''OK'''));
end;

procedure TResourceStringCommandsTests.RejectsNameWithOtherText;
begin
  Assert.WillRaise(
    procedure
    begin
      Added(Texte, 'sok', '''Okay''');
    end, EJsonRpcError);
end;

procedure TResourceStringCommandsTests.ExecuteReadsAndWrites;
var
  Arguments: TJSONArray;
  Answer: TJSONValue;
  Written, WrittenFile: string;
  WrittenEdit: TTextEdit;
begin
  Written := '';
  Arguments := TJSONArray.Create;
  try
    Arguments.Add('C:\P\Texte.pas');
    Arguments.Add('SFrage');
    Arguments.Add('''Wirklich?''');
    Answer := TResourceStringCommands.ExecuteAdd(
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := Texte;
        Result := AFileName = 'C:\P\Texte.pas';
      end,
      procedure(const AFileName, ANewText: string; const AEdit: TTextEdit)
      begin
        WrittenFile := AFileName;
        Written := ANewText;
        WrittenEdit := AEdit;
      end, Arguments);
    try
      Assert.IsTrue((Answer as TJSONBool).AsBoolean);
    finally
      Answer.Free;
    end;
    Assert.AreEqual('C:\P\Texte.pas', WrittenFile);
    Assert.Contains(Written, '  SFrage = ''Wirklich?'';'#10'implementation');
    Assert.AreEqual(3, WrittenEdit.Range.StartPos.Line);
  finally
    Arguments.Free;
  end;
  WrittenFile := '';
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
            AText := Texte;
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
