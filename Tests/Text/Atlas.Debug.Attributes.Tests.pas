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
    /// <summary>RTTI-Pool und Attributinstanzen einmal vor dem Leckmonitor anlegen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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

procedure TAtlasDebugAttributesTests.WarmUpFirstUse;
begin
  AttributesCarryTheirText;
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
    begin
      if Attribute is AtlasDebugDisplayAttribute then
      begin
        Template := AtlasDebugDisplayAttribute(Attribute).Template;
      end
      else if Attribute is AtlasDebugChildrenAttribute then
      begin
        Names := AtlasDebugChildrenAttribute(Attribute).Names;
      end;
    end;
  finally
    Context.Free;
  end;
  Assert.AreEqual('{Name}, {Ort}', Template);
  Assert.AreEqual('Name, Ort', Names);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugAttributesTests);

end.
