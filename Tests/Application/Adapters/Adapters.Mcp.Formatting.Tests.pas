unit Adapters.Mcp.Formatting.Tests;

// Tests für den Host-Adapter zwischen Mcp und Editing (format_code): Zeilenbereich, Datei und Ergebnis gehen
// unverändert durch.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpFormattingAdapterTests = class
  public
    [Test]
    procedure PassesLinesAndOutcome;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Mcp.Contract.Formatting,
  Atlas.Common.Editing.Contract.Formatting,
  Adapters.Mcp.Formatting;

type
  /// <summary>Merkt die Anfrage und antwortet fest.</summary>
  TFakeFormatting = class(TInterfacedObject, IEditingFormatting)
  public
    Request: TEditingFormatRequest;
    function Check(const ARequest: TEditingFormatRequest): TEditingFormatResult;
  end;

function TFakeFormatting.Check(const ARequest: TEditingFormatRequest): TEditingFormatResult;
begin
  Request := ARequest;
  Result := Default(TEditingFormatResult);
  Result.Formatted := 'neu';
  Result.Changed := True;
  SetLength(Result.Deviations, 1);
  Result.Deviations[0].Line := 4;
  Result.Deviations[0].Message := 'Einrückung';
  Result.HasSyntaxError := True;
  Result.SyntaxErrorLine := 7;
  Result.SyntaxErrorMessage := 'Fehler';
  Result.Stable := True;
end;

{ TMcpFormattingAdapterTests }

procedure TMcpFormattingAdapterTests.PassesLinesAndOutcome;
var
  mFake: TFakeFormatting;
  mEditing: IEditingFormatting;
  mAdapter: IMcpFormatting;
  mOutcome: TMcpFormatOutcome;
begin
  mFake := TFakeFormatting.Create;
  mEditing := mFake;
  mAdapter := TMcpFormattingAdapter.Create(mEditing);
  mOutcome := mAdapter.Format('alt', TFormatStyle.Default, TMcpFormatLines.Range(2, 5),
    TPascalSource.Create('C:\U.pas', ['DEBUG'], nil));
  Assert.AreEqual('alt', mFake.Request.Text);
  Assert.IsFalse(mFake.Request.WholeFile);
  Assert.AreEqual(2, mFake.Request.FirstLine);
  Assert.AreEqual(5, mFake.Request.LastLine);
  Assert.AreEqual('C:\U.pas', mFake.Request.Source.FileName);
  Assert.AreEqual('neu', mOutcome.Formatted);
  Assert.IsTrue(mOutcome.Changed);
  Assert.AreEqual(1, Integer(Length(mOutcome.Deviations)));
  Assert.AreEqual(4, mOutcome.Deviations[0].Line);
  Assert.AreEqual('Einrückung', mOutcome.Deviations[0].Message);
  Assert.IsTrue(mOutcome.HasSyntaxError);
  Assert.AreEqual(7, mOutcome.SyntaxErrorLine);
  Assert.AreEqual('Fehler', mOutcome.SyntaxErrorMessage);
  Assert.IsTrue(mOutcome.Stable);
  mAdapter.Format('alt', TFormatStyle.Default, TMcpFormatLines.All, TPascalSource.Default);
  Assert.IsTrue(mFake.Request.WholeFile);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpFormattingAdapterTests);

end.
