unit Atlas.Common.Lsp.Definition.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspDefinitionTests = class
  public
    [Test]
    procedure WritesLocations;
    /// <summary>Ersatz-Units der IDE (atlas-ide:…) gibt es nicht als Datei: kein Sprungziel.</summary>
    [Test]
    procedure SkipsIdeUnits;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Semantics.Definitions,
  Atlas.Common.Lsp.Definition;

{ TLspDefinitionTests }

procedure TLspDefinitionTests.WritesLocations;
var
  mTarget: TDefinitionTarget;
  mJson: TJSONArray;
  mLocation: TJSONValue;
  mUri: string;
  mLine, mCharacter: Integer;
begin
  mTarget.FileName := 'C:\P\Werkzeug.pas';
  mTarget.Range := TTextRange.Create(TTextPosition.Create(4, 0), TTextPosition.Create(6, 4));
  mTarget.SelectionRange := TTextRange.Create(TTextPosition.Create(4, 10), TTextPosition.Create(4, 16));
  mJson := TLspDefinition.ToJson([mTarget]);
  try
    Assert.AreEqual(1, Integer(mJson.Count));
    // Werte erst in typisierte Variablen lesen: GetValue<T> direkt als
    // Argument von Assert.AreEqual übersetzt dcc64 (Delphi 13) nicht.
    mLocation := mJson.Items[0];
    mUri := mLocation.GetValue<string>('uri');
    mLine := mLocation.GetValue<Integer>('range.start.line');
    mCharacter := mLocation.GetValue<Integer>('range.start.character');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Werkzeug.pas'), mUri);
    Assert.AreEqual(4, mLine);
    Assert.AreEqual(10, mCharacter);
  finally
    mJson.Free;
  end;
end;

procedure TLspDefinitionTests.SkipsIdeUnits;
var
  mReal, mIde: TDefinitionTarget;
  mJson: TJSONArray;
  mUri: string;
begin
  mReal.FileName := 'C:\P\Werkzeug.pas';
  mReal.Range := TTextRange.Create(TTextPosition.Create(4, 0), TTextPosition.Create(6, 4));
  mReal.SelectionRange := mReal.Range;
  mIde := mReal;
  mIde.FileName := 'atlas-ide:Vcl.Forms.pas';
  mJson := TLspDefinition.ToJson([mIde]);
  try
    // Ersatz-Unit der IDE allein: kein Sprungziel.
    Assert.AreEqual(0, Integer(mJson.Count));
  finally
    mJson.Free;
  end;
  mJson := TLspDefinition.ToJson([mIde, mReal]);
  try
    Assert.AreEqual(1, Integer(mJson.Count));
    mUri := mJson.Items[0].GetValue<string>('uri');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Werkzeug.pas'), mUri);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDefinitionTests);

end.
