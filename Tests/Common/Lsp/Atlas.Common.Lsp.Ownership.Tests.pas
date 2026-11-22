unit Atlas.Common.Lsp.Ownership.Tests;

// Tests für den Befehl atlas.server.ownership (#1877): Antwort vom Host, leere Antwort ohne Host, Fehler ohne URI,
// nebenläufig angemeldet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspOwnershipTests = class
  public
    [Test]
    procedure AnswerComesFromReport;
    [Test]
    procedure WithoutReportGivesNoSites;
    [Test]
    procedure MissingUriRaises;
    [Test]
    procedure AttachRegistersConcurrent;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Ownership,
  Atlas.Text.Json;

const
  cUri = 'file:///C:/P/U.pas';

type
  /// <summary>Antwort mit der URI und einer Stelle der Art "destroy".</summary>
  TFixedReport = class(TInterfacedObject, ILspOwnershipReport)
  public
    function Report(const AUri: string): TJSONObject;
  end;

function TFixedReport.Report(const AUri: string): TJSONObject;
var
  mSites: TJSONArray;
  mSite: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  mSites := TJSONArray.Create;
  Result.AddPair('sites', mSites);
  mSite := TJSONObject.Create;
  mSite.AddPair('kind', 'destroy');
  mSites.AddElement(mSite);
end;

function Run(const AReport: ILspOwnershipReport; out ASites: TJSONArray): TJSONObject;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(cUri);
    Result := TLspOwnership.Execute(mArguments, AReport) as TJSONObject;
  finally
    mArguments.Free;
  end;
  ASites := Result.GetValue('sites') as TJSONArray;
end;

function Text(ASite: TJSONValue; const AName: string): string;
begin
  Result := TJsonRead.Text(TJsonRead.AsObject(ASite), AName);
end;

{ TLspOwnershipTests }

procedure TLspOwnershipTests.AnswerComesFromReport;
var
  mReport: ILspOwnershipReport;
  mAnswer: TJSONObject;
  mSites: TJSONArray;
begin
  mReport := TFixedReport.Create;
  mAnswer := Run(mReport, mSites);
  try
    Assert.AreEqual(cUri, Text(mAnswer, 'uri'));
    Assert.AreEqual(1, Integer(mSites.Count));
    Assert.AreEqual('destroy', Text(mSites.Items[0], 'kind'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspOwnershipTests.WithoutReportGivesNoSites;
var
  mAnswer: TJSONObject;
  mSites: TJSONArray;
begin
  mAnswer := Run(nil, mSites);
  try
    Assert.AreEqual(cUri, Text(mAnswer, 'uri'));
    Assert.AreEqual(0, Integer(mSites.Count));
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
      TLspOwnership.Execute(mArguments, nil).Free;
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
    TLspOwnership.Attach(mCommands, nil);
    Assert.IsTrue(mCommands.IsConcurrentCommand(TLspOwnership.cCommand));
  finally
    mCommands.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspOwnershipTests);

end.
