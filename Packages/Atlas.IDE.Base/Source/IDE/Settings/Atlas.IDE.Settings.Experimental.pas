unit Atlas.IDE.Settings.Experimental;

// Experimentelle Funktionen in der IDE (#834): Solange mindestens eine wirkt
// (Hauptschalter experimental.enabled an und ihr Schalter nicht auf der
// Vorgabe), steht eine neutrale Zeile im Atlas-Statusfeld (#591) und damit im
// Tooltip; jede Änderung kommt ins Diagnoselog atlas.log. Beides nennt nur
// Schlüssel, keine Werte und keine Pfade.

interface

uses
  System.SysUtils,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry;

type
  TAtlasIdeExperimental = class
  public const
    cStatusId = 'atlas.experimental';
    cStatusOrder = 90;
  private class var
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    FLast: string;
  public
    /// <summary>Nach jeder Änderung der Einstellungen und beim Start: Zeile und Protokoll nachführen.</summary>
    class procedure ApplySettings; static;
    /// <summary>Beim Entladen: Zeile entfernen.</summary>
    class procedure Stop; static;
  end;

implementation

uses
  Atlas.Core.Settings.Experimental,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Strings;

class procedure TAtlasIdeExperimental.ApplySettings;
var
  mActive: TArray<string>;
  mText: string;
begin
  mActive := TAtlasIdeSettings.ActiveExperimental;
  mText := TAtlasExperimental.Summary(mActive, TAtlasStrings.Language = TAtlasLanguage.English);
  if mText <> FLast then
  begin
    if mText = '' then
    begin
      TAtlasGuard.Log('Experimentelle Funktionen: keine wirksam (#834)');
    end
    else
    begin
      TAtlasGuard.Log('Experimentelle Funktionen wirksam (#834): ' + string.Join(', ', mActive));
    end;
    FLast := mText;
  end;
  if mText = '' then
  begin
    Stop;
    Exit;
  end;
  if FLineRef = nil then
  begin
    FLine := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, cStatusId, cStatusOrder);
    FLineRef := FLine;
    TAtlasStatusRegistry.Default.Add(FLineRef);
  end;
  FLine.Update(mText, TAtlasStatusState.Neutral, mText);
end;

class procedure TAtlasIdeExperimental.Stop;
begin
  if FLineRef = nil then
  begin
    Exit;
  end;
  TAtlasStatusRegistry.Default.Remove(cStatusId);
  FLine := nil;
  FLineRef := nil;
end;

end.
