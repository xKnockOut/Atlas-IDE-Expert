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
    StatusId = 'atlas.experimental';
    StatusOrder = 90;
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
  Active: TArray<string>;
  Text: string;
begin
  Active := TAtlasIdeSettings.ActiveExperimental;
  Text := TAtlasExperimental.Summary(Active, TAtlasStrings.Language = TAtlasLanguage.English);
  if Text <> FLast then
  begin
    if Text = '' then
      TAtlasGuard.Log('Experimentelle Funktionen: keine wirksam (#834)')
    else
      TAtlasGuard.Log('Experimentelle Funktionen wirksam (#834): ' + string.Join(', ', Active));
    FLast := Text;
  end;
  if Text = '' then
  begin
    Stop;
    Exit;
  end;
  if FLineRef = nil then
  begin
    FLine := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, StatusId, StatusOrder);
    FLineRef := FLine;
    TAtlasStatusRegistry.Default.Add(FLineRef);
  end;
  FLine.Update(Text, TAtlasStatusState.Neutral, Text);
end;

class procedure TAtlasIdeExperimental.Stop;
begin
  if FLineRef = nil then
    Exit;
  TAtlasStatusRegistry.Default.Remove(StatusId);
  FLine := nil;
  FLineRef := nil;
end;

end.
