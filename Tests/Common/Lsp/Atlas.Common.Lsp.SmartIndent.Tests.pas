unit Atlas.Common.Lsp.SmartIndent.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Befehl atlas.server.smartIndent (#1827): Argumente, Antwort, Schalter.</summary>
  [TestFixture]
  TLspSmartIndentTests = class
  private
    /// <summary>Antwort auf AArguments (JSON-Text) als JSON-Text; AEnabled: smartIndent an.</summary>
    function Answer(const AArguments: string; AEnabled: Boolean): string;
  public
    [Test]
    procedure AnswersEditsAndCursor;
    [Test]
    procedure AnswersColumn;
    [Test]
    procedure AnswersNullWhenOffOrUnknown;
    [Test]
    procedure RejectsMissingArguments;
    [Test]
    procedure TakesOptionsFromSettings;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.SmartIndent,
  Atlas.Common.Lsp.SmartIndent;

const
  cUri = 'file:///C:/P/U.pas';
  cText = 'begin'#10'  if A then'#10;

{ TLspSmartIndentTests }

function TLspSmartIndentTests.Answer(const AArguments: string; AEnabled: Boolean): string;
var
  mStore: IDocumentStore;
  mArguments: TJSONArray;
  mValue: TJSONValue;
begin
  mStore := TDocumentStore.Create;
  mStore.Open(cUri, 'delphi', 1, cText);
  mArguments := TJSONObject.ParseJSONValue(AArguments) as TJSONArray;
  try
    mValue := TLspSmartIndent.Execute(mStore,
      function(const AUri: string; const AEditorOptions: TJSONValue; out AOptions: TSmartIndentOptions): Boolean
      begin
        AOptions := TSmartIndentOptions.Default;
        if AEditorOptions is TJSONObject then
        begin
          AOptions.IndentSize := TJSONObject(AEditorOptions).GetValue<Integer>('tabSize');
        end;
        Result := AEnabled;
      end, mArguments);
    try
      Result := mValue.ToJSON;
    finally
      mValue.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

procedure TLspSmartIndentTests.AnswersEditsAndCursor;
begin
  Assert.AreEqual('{"edits":[{"range":{"start":{"line":2,"character":0},"end":{"line":2,"character":0}},' +
    '"newText":"    "}],"cursor":{"line":2,"character":4}}',
    Answer('["' + cUri + '",2,{"tabSize":2,"insertSpaces":true}]', True));
  // Ebene 4 aus den Editor-Optionen.
  Assert.AreEqual('{"edits":[{"range":{"start":{"line":2,"character":0},"end":{"line":2,"character":0}},' +
    '"newText":"      "}],"cursor":{"line":2,"character":6}}',
    Answer('["' + cUri + '",2,{"tabSize":4,"insertSpaces":true}]', True));
end;

procedure TLspSmartIndentTests.AnswersColumn;
begin
  Assert.AreEqual('{"column":4}', Answer('["' + cUri + '",2,{"tabSize":2,"insertSpaces":true},"column"]', True));
end;

procedure TLspSmartIndentTests.AnswersNullWhenOffOrUnknown;
begin
  Assert.AreEqual('null', Answer('["' + cUri + '",2,{"tabSize":2,"insertSpaces":true}]', False));
  Assert.AreEqual('null', Answer('["file:///C:/P/Fremd.pas",2]', True));
  // Zeile 0: keine Zeile darüber.
  Assert.AreEqual('null', Answer('["' + cUri + '",0]', True));
end;

procedure TLspSmartIndentTests.RejectsMissingArguments;
begin
  Assert.WillRaise(
    procedure
    begin
      Answer('["' + cUri + '"]', True);
    end, EArgumentException);
  Assert.WillRaise(
    procedure
    begin
      Answer('["' + cUri + '","zwei"]', True);
    end, EArgumentException);
end;

procedure TLspSmartIndentTests.TakesOptionsFromSettings;
var
  mSettings: TSmartIndentSettings;
  mStyle: TFormatStyle;
  mOptions: TSmartIndentOptions;
begin
  mSettings := TSmartIndentSettings.Default;
  mStyle := TFormatStyle.Default;
  mStyle.IndentSize := 4;
  mStyle.UseTabs := True;
  Assert.IsTrue(TLspSmartIndent.OptionsFrom(mSettings, mStyle, mOptions));
  Assert.AreEqual(4, mOptions.IndentSize);
  Assert.IsTrue(mOptions.UseTabs);
  Assert.IsTrue(mOptions.StringContinuation = TStringContinuation.Indent);
  mSettings.SplitStringsIndent := 'align';
  mSettings.OutdentClosers := False;
  mSettings.Enabled := False;
  Assert.IsFalse(TLspSmartIndent.OptionsFrom(mSettings, mStyle, mOptions));
  Assert.IsTrue(mOptions.StringContinuation = TStringContinuation.Align);
  Assert.IsFalse(mOptions.OutdentClosers);
  Assert.IsTrue(mOptions.AfterEnter);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSmartIndentTests);

end.
