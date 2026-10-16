unit Atlas.Text.Entities.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextEntitiesTests = class
  public
    [Test]
    procedure DecodesNamed;
    [Test]
    procedure DecodesNumeric;
    [Test]
    procedure DecodesHex;
    [Test]
    procedure DecodesSurrogatePair;
    [Test]
    procedure KeepsUnknown;
  end;

implementation

uses
  Atlas.Text.Entities;

procedure TTextEntitiesTests.DecodesNamed;
begin
  Assert.AreEqual('<a> & "b" ''c''', TTextEntities.Decode('&lt;a&gt; &amp; &quot;b&quot; &apos;c&apos;'));
  // Nur eine Stufe: &amp;lt; wird zu &lt;, nicht zu <.
  Assert.AreEqual('&lt;', TTextEntities.Decode('&amp;lt;'));
end;

procedure TTextEntitiesTests.DecodesNumeric;
begin
  Assert.AreEqual('A'#$00E4, TTextEntities.Decode('&#65;&#228;'));
end;

procedure TTextEntitiesTests.DecodesHex;
begin
  Assert.AreEqual(#$20AC'x', TTextEntities.Decode('&#x20AC;&#X78;'));
end;

procedure TTextEntitiesTests.DecodesSurrogatePair;
begin
  Assert.AreEqual(#$D83D#$DE00, TTextEntities.Decode('&#x1F600;'));
  Assert.AreEqual('', TTextEntities.CodePointText($D800));
  Assert.AreEqual('', TTextEntities.CodePointText($110000));
end;

procedure TTextEntitiesTests.KeepsUnknown;
begin
  Assert.AreEqual('&nbsp; & x; &#xZZ; &#0;', TTextEntities.Decode('&nbsp; & x; &#xZZ; &#0;'));
  Assert.AreEqual('ohne', TTextEntities.Decode('ohne'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextEntitiesTests);

end.
