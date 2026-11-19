unit Atlas.Core.AiProviders.Catalog;

// Welche Anbieter es gibt (#1922): aus dem Wert von assistants.provider den
// Anbieter bauen. "none" und unbekannte Werte ergeben nil.

interface

uses
  Atlas.Core.AiProviders.Contract;

type
  TAtlasAiProviders = class
  public const
    cNone = 'none';
  public
    /// <summary>Anbieter AId mit dem Modell AModel; nil für "none" und unbekannte Werte.</summary>
    class function Create(const AId, AModel: string; const AHttp: IAtlasAiHttp; const AKeys: TAtlasAiKeyReader):
      IAtlasAiProvider; static;
    /// <summary>Braucht der Anbieter AId einen Schlüssel?</summary>
    class function NeedsKey(const AId: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.AiProviders.Anthropic;

{ TAtlasAiProviders }

class function TAtlasAiProviders.Create(const AId, AModel: string; const AHttp: IAtlasAiHttp;
  const AKeys: TAtlasAiKeyReader): IAtlasAiProvider;
begin
  Result := nil;
  if SameText(AId, TAtlasAnthropicApi.cId) then
  begin
    Result := TAtlasAnthropicProvider.Create(AHttp, AKeys, AModel);
  end;
end;

class function TAtlasAiProviders.NeedsKey(const AId: string): Boolean;
begin
  Result := SameText(AId, TAtlasAnthropicApi.cId);
end;

end.
