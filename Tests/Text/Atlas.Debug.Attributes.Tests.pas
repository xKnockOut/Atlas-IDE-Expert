unit Atlas.Debug.Attributes.Tests;

// Test der mitgelieferten Unit Atlas.Debug.Attributes (#854): übersetzt ohne
// weitere Abhängigkeiten, die Attribute tragen Vorlage und Namen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDebugAttributesTests = class
  public
    [Test]
    procedure AttributesCarryTheirText;
  end;

implementation

uses
  Atlas.Debug.Attributes;

type
  // Übersetzt nur, wenn beide Attribute mit diesen Argumenten passen (sonst meldet der Compiler das Attribut als
  // unbekannt oder die Argumente als falsch). Die Werte prüft der Test über eigene Instanzen: Atlas liest die
  // Attribute aus dem Quelltext, zur Laufzeit tun sie nichts. Über TRttiContext gelesen, blieben Typ und
  // Attribute im RTTI-Zwischenspeicher der RTL bis zum Programmende liegen.
  [AtlasDebugDisplay('{Name}, {Ort}')]
  [AtlasDebugChildren('Name, Ort')]
  TBeispiel = class
  public
    Name, Ort: string;
  end;

{ TAtlasDebugAttributesTests }

procedure TAtlasDebugAttributesTests.AttributesCarryTheirText;
var
  mDisplay: AtlasDebugDisplayAttribute;
  mChildren: AtlasDebugChildrenAttribute;
begin
  mDisplay := AtlasDebugDisplayAttribute.Create('{Name}, {Ort}');
  try
    Assert.AreEqual('{Name}, {Ort}', mDisplay.Template);
  finally
    mDisplay.Free;
  end;
  mChildren := AtlasDebugChildrenAttribute.Create('Name, Ort');
  try
    Assert.AreEqual('Name, Ort', mChildren.Names);
  finally
    mChildren.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugAttributesTests);

end.
