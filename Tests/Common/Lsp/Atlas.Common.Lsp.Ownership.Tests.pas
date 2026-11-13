unit Atlas.Common.Lsp.Ownership.Tests;

// Tests für den Befehl atlas.server.ownership (#1877): Antwort mit Zeile, Art, Freigabezeile und Zeilentext,
// „nie freigegeben“ nur mit eingeschalteter Regel, leere Antwort ohne Text, Fehler ohne URI, nebenläufig angemeldet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspOwnershipTests = class
  public
    [Test]
    procedure AnswerListsSites;
    [Test]
    procedure NeverOnlyWithTheRule;
    [Test]
    procedure UnreadableFileGivesNoSites;
    [Test]
    procedure MissingUriRaises;
    [Test]
    procedure AttachRegistersConcurrent;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.FreeFields,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.Ownership;

const
  cNl = #10;
  cUri = 'file:///C:/P/U.pas';
  cSource = 'unit U;' + cNl + 'interface' + cNl + 'uses' + cNl + '  System.Classes;' + cNl + 'type' + cNl +
    '  TKunde = class' + cNl + '  private' + cNl + '    FNamen: TStringList;' + cNl + '    FAlt: TStringList;' + cNl +
    '  public' + cNl + '    constructor Create;' + cNl + '    destructor Destroy; override;' + cNl + '  end;' + cNl +
    'implementation' + cNl + 'constructor TKunde.Create;' + cNl + 'begin' + cNl +
    '  FNamen := TStringList.Create;  ' + cNl + '  FAlt := TStringList.Create;' + cNl + 'end;' + cNl +
    'destructor TKunde.Destroy;' + cNl + 'begin' + cNl + '  FNamen.Free;' + cNl + 'end;' + cNl + 'end.';

/// <summary>Eingabe mit cSource; AWithRule schaltet field-not-freed zu.</summary>
function Input(AWithRule: Boolean): TLspOwnershipInput;
begin
  Result :=
    function(const AUri: string; out AText: string; out ARules: TRuleCheckContext): Boolean
    var
      mRule: IRule;
    begin
      AText := cSource;
      ARules := Default(TRuleCheckContext);
      ARules.Settings := TServerSettings.Default;
      if AWithRule then
      begin
        mRule := TOwnedFieldNotFreedRule.Create;
        ARules.Rules := [mRule];
      end;
      Result := True;
    end;
end;

function NoFile: TLspOwnershipInput;
begin
  Result :=
    function(const AUri: string; out AText: string; out ARules: TRuleCheckContext): Boolean
    begin
      AText := '';
      ARules := Default(TRuleCheckContext);
      Result := False;
    end;
end;

function Run(const AInput: TLspOwnershipInput; out ASites: TJSONArray): TJSONObject;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(cUri);
    Result := TLspOwnership.Execute(mArguments, AInput) as TJSONObject;
  finally
    mArguments.Free;
  end;
  ASites := Result.GetValue('sites') as TJSONArray;
end;

function Text(ASite: TJSONValue; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject(ASite).GetValue(AName);
  if mValue <> nil then
  begin
    Result := mValue.Value;
  end;
end;

procedure TLspOwnershipTests.AnswerListsSites;
var
  mAnswer: TJSONObject;
  mSites: TJSONArray;
begin
  mAnswer := Run(Input(True), mSites);
  try
    Assert.AreEqual(cUri, Text(mAnswer, 'uri'));
    Assert.AreEqual(2, mSites.Count);
    Assert.AreEqual('16', Text(mSites.Items[0], 'line'));
    Assert.AreEqual('12', Text(mSites.Items[0], 'character'));
    Assert.AreEqual('  FNamen := TStringList.Create;', Text(mSites.Items[0], 'lineText'));
    Assert.AreEqual('TStringList', Text(mSites.Items[0], 'className'));
    Assert.AreEqual('FNamen', Text(mSites.Items[0], 'target'));
    Assert.AreEqual('destroy', Text(mSites.Items[0], 'kind'));
    Assert.AreEqual('21', Text(mSites.Items[0], 'freeLine'));
    Assert.AreEqual('Destroy', Text(mSites.Items[0], 'detail'));
    Assert.AreEqual('', Text(mSites.Items[0], 'rule'));
    Assert.AreEqual('never', Text(mSites.Items[1], 'kind'));
    Assert.AreEqual('field-not-freed', Text(mSites.Items[1], 'rule'));
    Assert.AreEqual('', Text(mSites.Items[1], 'freeLine'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspOwnershipTests.NeverOnlyWithTheRule;
var
  mAnswer: TJSONObject;
  mSites: TJSONArray;
begin
  mAnswer := Run(Input(False), mSites);
  try
    Assert.AreEqual(2, mSites.Count);
    Assert.AreEqual('unknown', Text(mSites.Items[1], 'kind'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspOwnershipTests.UnreadableFileGivesNoSites;
var
  mAnswer: TJSONObject;
  mSites: TJSONArray;
begin
  mAnswer := Run(NoFile, mSites);
  try
    Assert.AreEqual(0, mSites.Count);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspOwnershipTests.MissingUriRaises;
var
  mArguments: TJSONArray;
  mRaised: Boolean;
begin
  mRaised := False;
  mArguments := TJSONArray.Create;
  try
    try
      TLspOwnership.Execute(mArguments, NoFile).Free;
    except
      on E: EJsonRpcError do
      begin
        mRaised := Pos(TLspOwnership.cCommand, E.Message) > 0;
      end;
    end;
  finally
    mArguments.Free;
  end;
  Assert.IsTrue(mRaised);
end;

procedure TLspOwnershipTests.AttachRegistersConcurrent;
var
  mCommands: TLspCommands;
begin
  mCommands := TLspCommands.Create;
  try
    TLspOwnership.Attach(mCommands, NoFile);
    Assert.IsTrue(mCommands.IsConcurrentCommand(TLspOwnership.cCommand));
  finally
    mCommands.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspOwnershipTests);

end.
