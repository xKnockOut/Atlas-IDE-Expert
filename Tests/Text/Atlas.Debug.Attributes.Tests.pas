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
  mContext: TRttiContext;
  mAttribute: TCustomAttribute;
  mTemplate, mNames: string;
begin
  mTemplate := '';
  mNames := '';
  mContext := TRttiContext.Create;
  try
    for mAttribute in mContext.GetType(TBeispiel).GetAttributes do
    begin
      if mAttribute is AtlasDebugDisplayAttribute then
      begin
        mTemplate := AtlasDebugDisplayAttribute(mAttribute).Template;
      end
      else if mAttribute is AtlasDebugChildrenAttribute then
      begin
        mNames := AtlasDebugChildrenAttribute(mAttribute).Names;
      end;
    end;
  finally
    mContext.Free;
  end;
  Assert.AreEqual('{Name}, {Ort}', mTemplate);
  Assert.AreEqual('Name, Ort', mNames);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugAttributesTests);

end.
