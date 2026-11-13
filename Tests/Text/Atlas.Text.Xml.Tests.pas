unit Atlas.Text.Xml.Tests;

// Tests des kleinen XML-Lesers (#275): Start-, End- und Textknoten mit
// Attributen, Entitäten, CDATA, übersprungene Kommentare und Deklarationen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TXmlCursorTests = class
  public
    [Test]
    procedure WalksNodesWithAttributes;
    [Test]
    procedure DecodesEntitiesAndKeepsCData;
    [Test]
    procedure SkipsCommentsAndDeclarations;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Xml;

{ TXmlCursorTests }

procedure TXmlCursorTests.WalksNodesWithAttributes;
var
  mCursor: TXmlCursor;
begin
  mCursor.Init('<a x="1" Y=''zwei''><b/>Text</a>');
  Assert.IsTrue(mCursor.Next);
  Assert.IsTrue(mCursor.Kind = TXmlNodeKind.StartTag);
  Assert.AreEqual('a', mCursor.Name);
  Assert.AreEqual('1', mCursor.Attribute('X'));
  Assert.AreEqual('zwei', mCursor.Attribute('y'));
  Assert.AreEqual('', mCursor.Attribute('z'));
  Assert.IsFalse(mCursor.SelfClosing);
  Assert.IsTrue(mCursor.Next);
  Assert.AreEqual('b', mCursor.Name);
  Assert.IsTrue(mCursor.SelfClosing);
  Assert.IsTrue(mCursor.Next);
  Assert.IsTrue(mCursor.Kind = TXmlNodeKind.Text);
  Assert.AreEqual('Text', mCursor.Value);
  Assert.IsTrue(mCursor.Next);
  Assert.IsTrue(mCursor.Kind = TXmlNodeKind.EndTag);
  Assert.AreEqual('a', mCursor.Name);
  Assert.IsFalse(mCursor.Next);
end;

procedure TXmlCursorTests.DecodesEntitiesAndKeepsCData;
var
  mCursor: TXmlCursor;
begin
  mCursor.Init('<m t="a &lt; b">x &amp; y<![CDATA[<roh> &amp;]]></m>');
  Assert.IsTrue(mCursor.Next);
  Assert.AreEqual('a < b', mCursor.Attribute('t'));
  Assert.IsTrue(mCursor.Next);
  Assert.AreEqual('x & y', mCursor.Value);
  Assert.IsTrue(mCursor.Next);
  Assert.IsTrue(mCursor.Kind = TXmlNodeKind.Text);
  Assert.AreEqual('<roh> &amp;', mCursor.Value);
end;

procedure TXmlCursorTests.SkipsCommentsAndDeclarations;
var
  mCursor: TXmlCursor;
begin
  mCursor.Init('<?xml version="1.0"?>' + #13#10 + '<!DOCTYPE report PUBLIC "-//JACOCO//DTD Report 1.0//EN" ' +
    '"report.dtd"><!-- Kommentar <a> --><report/>');
  Assert.IsTrue(mCursor.Next);
  while mCursor.Kind = TXmlNodeKind.Text do
  begin
    Assert.AreEqual('', Trim(mCursor.Value));
    Assert.IsTrue(mCursor.Next);
  end;
  Assert.IsTrue(mCursor.Kind = TXmlNodeKind.StartTag);
  Assert.AreEqual('report', mCursor.Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TXmlCursorTests);

end.
