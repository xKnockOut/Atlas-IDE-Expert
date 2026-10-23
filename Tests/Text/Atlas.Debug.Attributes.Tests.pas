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
  System.Rtti,
  Atlas.Debug.Attributes;

type
  [AtlasDebugDisplay('{Name}, {Ort}')]
  [AtlasDebugChildren('Name, Ort')]
  TBeispiel = class
  public
    Name, Ort: string;
  end;

procedure TAtlasDebugAttributesTests.AttributesCarryTheirText;
var
  Context: TRttiContext;
  Attribute: TCustomAttribute;
  Template, Names: string;
begin
  Template := '';
  Names := '';
  Context := TRttiContext.Create;
  try
    for Attribute in Context.GetType(TBeispiel).GetAttributes do
      if Attribute is AtlasDebugDisplayAttribute then
        Template := AtlasDebugDisplayAttribute(Attribute).Template
      else if Attribute is AtlasDebugChildrenAttribute then
        Names := AtlasDebugChildrenAttribute(Attribute).Names;
  finally
    Context.Free;
  end;
  Assert.AreEqual('{Name}, {Ort}', Template);
  Assert.AreEqual('Name, Ort', Names);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugAttributesTests);

end.
