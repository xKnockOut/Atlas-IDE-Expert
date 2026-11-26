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
    [Test]
    procedure PassesStyleRequest;
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
    StyleFile: string;
    StyleConfigured: TFormatStyle;
    function Check(const ARequest: TEditingFormatRequest): TEditingFormatResult;
    function StyleOf(const AFileName: string; const AConfigured: TFormatStyle): TFormatStyle;
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

function TFakeFormatting.StyleOf(const AFileName: string; const AConfigured: TFormatStyle): TFormatStyle;
begin
  StyleFile := AFileName;
  StyleConfigured := AConfigured;
  Result := TFormatStyle.Default;
  Result.IndentSize := 5;
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

procedure TMcpFormattingAdapterTests.PassesStyleRequest;
var
  mFake: TFakeFormatting;
  mEditing: IEditingFormatting;
  mAdapter: IMcpFormatting;
  mConfigured: TFormatStyle;
begin
  mFake := TFakeFormatting.Create;
  mEditing := mFake;
  mAdapter := TMcpFormattingAdapter.Create(mEditing);
  mConfigured := TFormatStyle.Default;
  mConfigured.IndentSize := 7;
  mConfigured.Given := [TFormatKey.IndentSize];
  Assert.AreEqual(5, mAdapter.StyleOf('C:\U.pas', mConfigured).IndentSize);
  Assert.AreEqual('C:\U.pas', mFake.StyleFile);
  Assert.AreEqual(7, mFake.StyleConfigured.IndentSize);
  Assert.IsTrue(TFormatKey.IndentSize in mFake.StyleConfigured.Given);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpFormattingAdapterTests);

end.
