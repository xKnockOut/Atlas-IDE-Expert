unit Shell.Mcp.Conventions.Tests;

// Ressource „Projektkonventionen“ des MCP-Modus (#272): Uri, Markdown und Name in der Sprache der Oberfläche
// (#1458).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Localization.Texts;

type
  [TestFixture]
  TMcpConventionsTests = class
  private
    FSaved: TTextLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RegistersResourceInBothLanguages;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Shell.Mcp.Conventions;

procedure TMcpConventionsTests.Setup;
begin
  FSaved := TAtlasLocale.Language;
end;

procedure TMcpConventionsTests.TearDown;
begin
  TAtlasLocale.Use(FSaved);
end;

/// <summary>Name der einzigen Ressource, nachdem sie in der Sprache ALanguage angemeldet wurde.</summary>
function ResourceName(ALanguage: TTextLanguage; out AUri, AMimeType: string): string;
var
  mServer: TMcpServer;
  mListed: TJSONObject;
  mItem: TJSONValue;
begin
  TAtlasLocale.Use(ALanguage);
  mServer := TMcpServer.Create('Atlas', '0');
  try
    TMcpConventions.Register(mServer, nil);
    mListed := mServer.ListResources;
    try
      mItem := mListed.GetValue<TJSONArray>('resources').Items[0];
      AUri := mItem.GetValue<string>('uri');
      AMimeType := mItem.GetValue<string>('mimeType');
      Result := mItem.GetValue<string>('name');
    finally
      mListed.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TMcpConventionsTests.RegistersResourceInBothLanguages;
var
  mUri, mMimeType: string;
begin
  Assert.AreEqual('Projektkonventionen', ResourceName(TTextLanguage.German, mUri, mMimeType));
  Assert.AreEqual('delphi://conventions', mUri);
  Assert.AreEqual('text/markdown', mMimeType);
  Assert.AreEqual('Project conventions', ResourceName(TTextLanguage.English, mUri, mMimeType));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpConventionsTests);

end.
